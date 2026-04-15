"""CRUD operations for Inspections (чек-листы/обследования)."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, func, nulls_last
from sqlalchemy.orm import load_only
from typing import List, Optional, Dict
from pydantic import BaseModel
from datetime import datetime, timedelta
from pathlib import Path
import uuid as uuid_lib

from database import get_db
from auth import verify_token, verify_token_optional
from auth_api import get_current_user
from models import (
    Inspection, Equipment, User, Workshop, Branch, Enterprise,
    Report, NDTMethod, Questionnaire, QuestionnaireDocumentFile,
    EquipmentResource, InspectionHistory, Assignment, InspectionEquipment,
    Opo, AuditLog,
)
from inspection_utils import (
    create_ndt_methods_from_mobile as _create_ndt_methods_from_mobile,
    update_equipment_attributes_from_inspection as _update_equipment_attrs,
)
from client_access import get_client_accessible_equipment_ids

router = APIRouter(tags=["inspections"])


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------
class BulkDeleteInspectionsRequest(BaseModel):
    inspection_ids: List[str]


class BulkArchiveRequest(BaseModel):
    inspection_ids: List[str]
    archive: bool = True


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
async def _log_audit(
    db: AsyncSession,
    user_id: Optional[uuid_lib.UUID],
    action: str,
    entity_type: str,
    entity_id: Optional[uuid_lib.UUID],
    details: Optional[dict] = None,
) -> None:
    """Пишет запись в журнал аудита. Не бросает исключений."""
    try:
        entry = AuditLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            details=details,
        )
        db.add(entry)
    except Exception:
        pass


def _validate_create_inspection(data: dict) -> None:
    """Валидация тела запроса создания обследования. При ошибках бросает HTTPException с списком errors."""
    err = []
    eq_id = data.get("equipment_id")
    if not eq_id:
        err.append({"field": "equipment_id", "message": "equipment_id обязателен"})
    elif not isinstance(eq_id, str) or not str(eq_id).strip():
        err.append({"field": "equipment_id", "message": "equipment_id должен быть непустой строкой"})
    else:
        try:
            uuid_lib.UUID(str(eq_id))
        except (ValueError, TypeError):
            err.append({"field": "equipment_id", "message": "equipment_id должен быть валидным UUID"})
    st = data.get("status")
    if st is not None and str(st).strip():
        allowed = {"DRAFT", "SIGNED", "APPROVED", "COMPLETED"}
        if str(st).strip().upper() not in allowed:
            err.append({"field": "status", "message": f"status должен быть один из: {', '.join(sorted(allowed))}"})
    if "data" in data and data["data"] is not None and not isinstance(data["data"], dict):
        err.append({"field": "data", "message": "data должен быть объектом (словарём)"})
    aid = data.get("assignment_id")
    if aid is not None and str(aid).strip():
        try:
            uuid_lib.UUID(str(aid))
        except (ValueError, TypeError):
            err.append({"field": "assignment_id", "message": "assignment_id должен быть валидным UUID"})
    if err:
        raise HTTPException(status_code=400, detail=err)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@router.get("/api/inspections")
async def get_inspections(
    equipment_id: Optional[str] = None,
    enterprise_id: Optional[str] = None,
    branch_id: Optional[str] = None,
    workshop_id: Optional[str] = None,
    inspection_type: Optional[str] = None,
    inspection_method: Optional[str] = None,
    inspection_category: Optional[str] = None,
    group_by: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get inspections (с учетом прав: инженер видит только свои). Фильтр по предприятию/филиалу/цеху."""
    try:
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        # П.5.1 — Скрываем мягко удалённые записи
        query = select(Inspection).where(
            or_(Inspection.is_deleted == False, Inspection.is_deleted == None)
        )

        if current_user.role == "engineer":
            query = query.where(
                or_(
                    Inspection.inspector_id == current_user.id,
                    Inspection.performed_by == current_user.id,
                )
            )
        elif current_user.role == "client":
            allowed_eq = await get_client_accessible_equipment_ids(db, current_user)
            if not allowed_eq:
                if group_by in {"type", "method", "category", "type_method"}:
                    return {
                        "grouped": True,
                        "group_by": group_by,
                        "groups": [],
                        "total_groups": 0,
                        "total": 0,
                    }
                return {"items": [], "total": 0}
            query = query.where(Inspection.equipment_id.in_(allowed_eq))

        if equipment_id:
            try:
                equipment_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(Inspection.equipment_id == equipment_uuid)
            except Exception:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        elif enterprise_id or branch_id or workshop_id:
            subq = select(Equipment.id)
            if workshop_id:
                try:
                    ws_uuid = uuid_lib.UUID(workshop_id)
                    subq = subq.where(Equipment.workshop_id == ws_uuid)
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid workshop_id format")
            elif branch_id:
                try:
                    br_uuid = uuid_lib.UUID(branch_id)
                    subq = subq.where(Equipment.workshop_id.in_(select(Workshop.id).where(Workshop.branch_id == br_uuid)))
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid branch_id format")
            elif enterprise_id:
                try:
                    ent_uuid = uuid_lib.UUID(enterprise_id)
                    subq = subq.where(
                        Equipment.workshop_id.in_(
                            select(Workshop.id).where(
                                Workshop.branch_id.in_(select(Branch.id).where(Branch.enterprise_id == ent_uuid))
                            )
                        )
                    )
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid enterprise_id format")
            query = query.where(Inspection.equipment_id.in_(subq))

        if inspection_type:
            query = query.where(Inspection.inspection_type == inspection_type)
        if inspection_method:
            query = query.where(Inspection.inspection_method == inspection_method)
        if inspection_category:
            query = query.where(Inspection.inspection_category == inspection_category)

        if group_by in {"type", "method", "category", "type_method"}:
            grouped_query = query.order_by(
                nulls_last(Inspection.date_performed.desc()),
                nulls_last(Inspection.created_at.desc()),
            )
            grouped_result = await db.execute(grouped_query)
            grouped_inspections = grouped_result.scalars().all()
            groups: Dict[str, list] = {}
            for ins in grouped_inspections:
                if group_by == "type":
                    key = str(ins.inspection_type or "UNSPECIFIED")
                elif group_by == "method":
                    key = str(ins.inspection_method or "UNSPECIFIED")
                elif group_by == "category":
                    key = str(ins.inspection_category or "UNSPECIFIED")
                else:
                    key = f"{ins.inspection_type or 'UNSPECIFIED'}::{ins.inspection_method or 'UNSPECIFIED'}"
                groups.setdefault(key, []).append(ins)

            items = []
            for key, group_items in groups.items():
                sliced = group_items[skip : skip + limit]
                items.append(
                    {
                        "key": key,
                        "count": len(group_items),
                        "items": [
                            {
                                "id": str(ins.id),
                                "equipment_id": str(ins.equipment_id),
                                "date_performed": ins.date_performed.isoformat() if ins.date_performed else None,
                                "status": ins.status,
                                "inspection_type": ins.inspection_type,
                                "inspection_method": ins.inspection_method,
                                "inspection_category": ins.inspection_category,
                                "created_at": ins.created_at.isoformat() if ins.created_at else None,
                            }
                            for ins in sliced
                        ],
                    }
                )
            return {
                "grouped": True,
                "group_by": group_by,
                "groups": items,
                "total_groups": len(groups),
                "total": len(grouped_inspections),
            }
        # Сортировка: сначала по date_performed (если есть), затем по created_at, с учетом NULL
        query = query.order_by(
            nulls_last(Inspection.date_performed.desc()),
            nulls_last(Inspection.created_at.desc())
        )
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        inspections = result.scalars().all()
        
        # Получаем информацию об оборудовании для каждого inspection
        equipment_ids = [str(insp.equipment_id) for insp in inspections if insp.equipment_id]
        equipment_map = {}
        if equipment_ids:
            equipment_result = await db.execute(
                select(Equipment).where(Equipment.id.in_([uuid_lib.UUID(eid) for eid in equipment_ids]))
            )
            for eq in equipment_result.scalars().all():
                # Получаем информацию о цехе, филиале и предприятии
                enterprise_id = None
                enterprise_name = None
                branch_id = None
                branch_name = None
                workshop_id = None
                workshop_name = None
                
                if eq.workshop_id:
                    try:
                        workshop_result = await db.execute(
                            select(Workshop).where(Workshop.id == eq.workshop_id)
                        )
                        workshop = workshop_result.scalar_one_or_none()
                        if workshop:
                            workshop_id = str(workshop.id)
                            workshop_name = workshop.name
                            
                            # Получаем филиал
                            try:
                                branch_result = await db.execute(
                                    select(Branch).where(Branch.id == workshop.branch_id)
                                )
                                branch = branch_result.scalar_one_or_none()
                                if branch:
                                    branch_id = str(branch.id)
                                    branch_name = branch.name
                                    
                                    # Получаем предприятие
                                    try:
                                        enterprise_result = await db.execute(
                                            select(Enterprise).where(Enterprise.id == branch.enterprise_id)
                                        )
                                        enterprise = enterprise_result.scalar_one_or_none()
                                        if enterprise:
                                            enterprise_id = str(enterprise.id)
                                            enterprise_name = enterprise.name
                                    except Exception as e:
                                        await db.rollback()
                                        print(f"⚠️ Error loading enterprise for inspection equipment {eq.id}: {e}")
                            except Exception as e:
                                await db.rollback()
                                print(f"⚠️ Error loading branch for inspection equipment {eq.id}: {e}")
                    except Exception as e:
                        await db.rollback()
                        print(f"⚠️ Error loading workshop for inspection equipment {eq.id}: {e}")
                
                equipment_map[str(eq.id)] = {
                    "name": eq.name,
                    "location": eq.location,
                    "enterprise_id": enterprise_id,
                    "enterprise_name": enterprise_name,
                    "branch_id": branch_id,
                    "branch_name": branch_name,
                    "workshop_id": workshop_id,
                    "workshop_name": workshop_name,
                }
        
        return {
            "items": [
                {
                    "id": str(ins.id),
                    "equipment_id": str(ins.equipment_id),
                    "equipment_name": equipment_map.get(str(ins.equipment_id), {}).get("name"),
                    "equipment_location": equipment_map.get(str(ins.equipment_id), {}).get("location"),
                    "enterprise_id": equipment_map.get(str(ins.equipment_id), {}).get("enterprise_id"),
                    "enterprise_name": equipment_map.get(str(ins.equipment_id), {}).get("enterprise_name"),
                    "branch_id": equipment_map.get(str(ins.equipment_id), {}).get("branch_id"),
                    "branch_name": equipment_map.get(str(ins.equipment_id), {}).get("branch_name"),
                    "workshop_id": equipment_map.get(str(ins.equipment_id), {}).get("workshop_id"),
                    "workshop_name": equipment_map.get(str(ins.equipment_id), {}).get("workshop_name"),
                    "date_performed": ins.date_performed.isoformat() if ins.date_performed else None,
                    "data": ins.data,
                    "conclusion": ins.conclusion,
                    "status": ins.status,
                    "inspection_type": getattr(ins, "inspection_type", None),
                    "inspection_method": getattr(ins, "inspection_method", None),
                    "inspection_category": getattr(ins, "inspection_category", None),
                    "is_archived": getattr(ins, "is_archived", False),
                    "created_at": ins.created_at.isoformat() if ins.created_at else None,
                }
                for ins in inspections
            ],
            "total": len(inspections)
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_inspections: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении чеклистов: {error_detail}")


@router.get("/api/inspections/groups")
async def get_inspection_groups(
    group_by: str = "type",
    inspection_type: Optional[str] = None,
    inspection_method: Optional[str] = None,
    inspection_category: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Сводка по группам обследований без полного payload."""
    valid_group_by = {"type", "method", "category", "type_method"}
    if group_by not in valid_group_by:
        raise HTTPException(status_code=400, detail=f"group_by must be one of {sorted(valid_group_by)}")

    user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
    current_user = user_result.scalar_one_or_none()
    if not current_user:
        raise HTTPException(status_code=404, detail="User not found")

    query = select(Inspection)
    if current_user.role == "engineer":
        query = query.where(or_(Inspection.inspector_id == current_user.id, Inspection.performed_by == current_user.id))

    if inspection_type:
        query = query.where(Inspection.inspection_type == inspection_type)
    if inspection_method:
        query = query.where(Inspection.inspection_method == inspection_method)
    if inspection_category:
        query = query.where(Inspection.inspection_category == inspection_category)

    result = await db.execute(query)
    rows = result.scalars().all()
    grouped: Dict[str, int] = {}
    for ins in rows:
        if group_by == "type":
            key = str(ins.inspection_type or "UNSPECIFIED")
        elif group_by == "method":
            key = str(ins.inspection_method or "UNSPECIFIED")
        elif group_by == "category":
            key = str(ins.inspection_category or "UNSPECIFIED")
        else:
            key = f"{ins.inspection_type or 'UNSPECIFIED'}::{ins.inspection_method or 'UNSPECIFIED'}"
        grouped[key] = grouped.get(key, 0) + 1

    return {
        "grouped": True,
        "group_by": group_by,
        "groups": [{"key": k, "count": v} for k, v in sorted(grouped.items(), key=lambda x: x[0])],
        "total_groups": len(grouped),
        "total": len(rows),
    }


@router.patch("/api/inspections/{inspection_id}/status")
async def update_inspection_status(
    inspection_id: str,
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Изменить статус чек-листа/обследования (Inspection).
    Статусы: DRAFT, SIGNED, APPROVED
    - admin/chief_operator/operator: могут устанавливать любой из поддерживаемых статусов
    - engineer: может менять статус только своих инспекций и только на DRAFT/SIGNED
    """
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)

        # Совместимость: username в токене может быть email (старые токены / ввод email)
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        new_status = (payload.get("status") or "").strip().upper()
        allowed_statuses = {"DRAFT", "SIGNED", "APPROVED"}
        if new_status not in allowed_statuses:
            raise HTTPException(status_code=400, detail="Invalid status. Allowed: DRAFT, SIGNED, APPROVED")

        # RBAC
        if current_user.role in ["admin", "chief_operator", "operator"]:
            pass
        elif current_user.role == "engineer":
            if not (inspection.inspector_id and inspection.inspector_id == current_user.id):
                raise HTTPException(status_code=403, detail="Доступ запрещен")
            if new_status not in {"DRAFT", "SIGNED"}:
                raise HTTPException(status_code=403, detail="Инженер не может утверждать (APPROVED)")
        else:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        inspection.status = new_status
        inspection.updated_by = current_user.id
        await db.commit()
        await db.refresh(inspection)

        return {"status": "ok", "id": inspection_id, "new_status": inspection.status}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update inspection status: {str(e)}")


@router.post("/api/inspections")
async def create_inspection(
    inspection_data: dict,
    username: Optional[str] = Depends(verify_token_optional),
    db: AsyncSession = Depends(get_db)
):
    """Create new inspection. При авторизации заполняются created_by (аудит)."""
    try:
        created_by_id = None
        if username:
            user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
            u = user_result.scalar_one_or_none()
            if u:
                created_by_id = u.id
        _validate_create_inspection(inspection_data)
        # Parse equipment_id
        equipment_id = None
        if inspection_data.get("equipment_id"):
            try:
                equipment_id = uuid_lib.UUID(inspection_data.get("equipment_id"))
            except (ValueError, TypeError):
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        # Parse date_performed if provided
        date_performed = None
        if inspection_data.get("date_performed"):
            try:
                date_performed = datetime.fromisoformat(inspection_data.get("date_performed").replace('Z', '+00:00'))
            except:
                pass
        
        # Parse project_id if provided
        project_id = None
        if inspection_data.get("project_id"):
            try:
                project_id = uuid_lib.UUID(inspection_data.get("project_id"))
            except:
                pass

        # Parse assignment_id if provided
        assignment_id_parsed = None
        if inspection_data.get("assignment_id"):
            try:
                assignment_id_parsed = uuid_lib.UUID(str(inspection_data.get("assignment_id")))
            except (ValueError, TypeError):
                pass

        # Если в data указано include_opo_data=false, а у оборудования есть opo_id —
        # подтягиваем сохранённые данные ОПО и сливаем документы 1..9.
        try:
            inspection_data_dict = inspection_data.get("data", {}) or {}
            if isinstance(inspection_data_dict, dict):
                include_opo_data = inspection_data_dict.get("include_opo_data", True)
                if include_opo_data is False and equipment_id:
                    eq_result = await db.execute(select(Equipment).where(Equipment.id == equipment_id))
                    equipment = eq_result.scalar_one_or_none()
                    opo_id = getattr(equipment, "opo_id", None) if equipment else None
                    if opo_id:
                        opo_result = await db.execute(select(Opo).where(Opo.id == opo_id))
                        opo = opo_result.scalar_one_or_none()
                        survey = (opo.survey_data or {}) if opo else {}

                        # Мерджим documents[1..9] из survey в текущий documents
                        docs_current = inspection_data_dict.get("documents") or {}
                        if isinstance(docs_current, dict) and isinstance(survey, dict) and isinstance(survey.get("documents"), dict):
                            merged_docs = dict(docs_current)
                            for k, v in survey.get("documents").items():
                                try:
                                    n = int(str(k))
                                except Exception:
                                    continue
                                if 1 <= n <= 9:
                                    merged_docs[str(k)] = v
                            inspection_data_dict["documents"] = merged_docs

                        # Подтягиваем organization/executors, если не заполнены в чек-листе оборудования
                        if isinstance(survey, dict):
                            if not inspection_data_dict.get("organization") and survey.get("organization"):
                                inspection_data_dict["organization"] = survey.get("organization")
                            if not inspection_data_dict.get("executors") and survey.get("executors"):
                                inspection_data_dict["executors"] = survey.get("executors")

                            # Сохраняем survey отдельным блоком (для отчетов/просмотра)
                            inspection_data_dict["opo_survey"] = survey

                        inspection_data["data"] = inspection_data_dict
        except Exception:
            # Не блокируем создание инспекции из-за мерджа ОПО
            pass
        
        inspection_payload_data = inspection_data.get("data", {}) if isinstance(inspection_data.get("data", {}), dict) else {}
        inspection_type_value = (
            inspection_data.get("inspection_type")
            or inspection_payload_data.get("inspection_type")
        )
        if not inspection_type_value:
            if inspection_payload_data.get("weld_inspections") or inspection_payload_data.get("thickness_measurements"):
                inspection_type_value = "NDT"
            elif inspection_payload_data.get("documents") or inspection_payload_data.get("questionnaire"):
                inspection_type_value = "QUESTIONNAIRE"
            else:
                inspection_type_value = "VISUAL"

        inspection_method_value = (
            inspection_data.get("inspection_method")
            or inspection_payload_data.get("inspection_method")
            or inspection_payload_data.get("method_code")
        )
        inspection_category_value = (
            inspection_data.get("inspection_category")
            or inspection_payload_data.get("inspection_category")
        )

        new_inspection = Inspection(
            equipment_id=equipment_id,
            project_id=project_id,
            assignment_id=assignment_id_parsed,
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT"),
            date_performed=date_performed,
            inspection_type=inspection_type_value,
            inspection_method=inspection_method_value,
            inspection_category=inspection_category_value,
            is_archived=False,
            created_by=created_by_id,
            inspector_id=created_by_id,
            performed_by=created_by_id,
        )
        db.add(new_inspection)
        await db.flush()
        await _log_audit(
            db, created_by_id, "CREATE", "inspection", new_inspection.id,
            {"equipment_id": str(equipment_id), "status": inspection_data.get("status", "DRAFT")},
        )
        await db.commit()
        await db.refresh(new_inspection)
        
        # Если это чек-лист сосуда (vessel checklist), создаем questionnaire (чтобы мобильное могло загрузить фото/сканы)
        questionnaire_id = None
        inspection_data_dict = inspection_data.get("data", {})
        if inspection_data_dict and isinstance(inspection_data_dict, dict):
            has_vessel_data = (
                inspection_data_dict.get("documents")
                or inspection_data_dict.get("vessel_name")
                or inspection_data_dict.get("factory_plate_photo")
                or inspection_data_dict.get("control_scheme_image")
                or (inspection_data_dict.get("visual_defects") and len(inspection_data_dict.get("visual_defects") or []) > 0)
                or (inspection_data_dict.get("thickness_measurements") and len(inspection_data_dict.get("thickness_measurements") or []) > 0)
            )
            if has_vessel_data:
                # Получаем информацию об оборудовании
                eq_result = await db.execute(
                    select(Equipment).where(Equipment.id == equipment_id)
                )
                equipment = eq_result.scalar_one_or_none()
                
                # Извлекаем данные из inspection_data
                inspection_date_str = inspection_data_dict.get("inspection_date")
                inspection_date_obj = None
                if inspection_date_str:
                    try:
                        if isinstance(inspection_date_str, str):
                            inspection_date_obj = datetime.fromisoformat(inspection_date_str.replace('Z', '+00:00')).date()
                    except:
                        pass
                
                # Создаем questionnaire (только поля из модели: equipment_id, data, date_performed, status, assignment_id)
                assignment_id_q = None
                if inspection_data.get("assignment_id"):
                    try:
                        assignment_id_q = uuid_lib.UUID(inspection_data.get("assignment_id"))
                    except Exception:
                        pass
                new_questionnaire = Questionnaire(
                    equipment_id=equipment_id,
                    data=inspection_data_dict,
                    date_performed=date_performed,
                    status=inspection_data.get("status", "DRAFT"),
                    assignment_id=assignment_id_q,
                    created_by=created_by_id,
                )
                db.add(new_questionnaire)
                await db.commit()
                await db.refresh(new_questionnaire)
                questionnaire_id = str(new_questionnaire.id)
                # Привязываем инспекцию к опросному листу (для отчётов и загрузки документов)
                new_inspection.questionnaire_id = new_questionnaire.id
                await db.commit()
                await db.refresh(new_inspection)
                _create_ndt_methods_from_mobile(
                    db, new_inspection, new_questionnaire, equipment_id, inspection_data_dict
                )
                await db.commit()
        
        # Создаем запись в истории обследований (версия 3.3.0)
        assignment_id = None
        if inspection_data.get("assignment_id"):
            try:
                assignment_id = uuid_lib.UUID(inspection_data.get("assignment_id"))
            except:
                pass
        
        # Определяем тип обследования
        inspection_type = "VISUAL"
        if inspection_data_dict:
            if inspection_data_dict.get("documents") or inspection_data_dict.get("vessel_name"):
                inspection_type = "QUESTIONNAIRE"
            elif inspection_data_dict.get("ndt_methods") or inspection_data_dict.get("method_code"):
                inspection_type = "NDT"
        
        # Получаем ID инженера из данных или из токена
        inspector_id = None
        if inspection_data_dict.get("inspector_id"):
            try:
                inspector_id = uuid_lib.UUID(inspection_data_dict.get("inspector_id"))
            except:
                pass
        
        # Создаем запись в истории
        history_entry = InspectionHistory(
            equipment_id=equipment_id,
            assignment_id=assignment_id,
            inspection_type=inspection_type,
            inspector_id=inspector_id,
            inspection_date=date_performed or datetime.now(),
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT")
        )
        db.add(history_entry)
        await db.commit()
        await db.refresh(history_entry)

        # Обновляем статус задания (чтобы у инженера отмечалось выполнено/не выполнено)
        if assignment_id:
            try:
                assignment_result = await db.execute(
                    select(Assignment).where(Assignment.id == assignment_id)
                )
                assignment = assignment_result.scalar_one_or_none()
                if assignment:
                    insp_status = (inspection_data.get("status") or "DRAFT").upper()
                    if insp_status == "SIGNED":
                        assignment.status = "COMPLETED"
                        assignment.completed_at = datetime.now()
                        # Обновляем equipment.attributes теххарактеристикой из обследования
                        try:
                            data_dict = inspection_data.get("data") or {}
                            if data_dict and isinstance(data_dict, dict):
                                await _update_equipment_attrs(db, equipment_id, data_dict)
                        except Exception:
                            pass
                    elif insp_status == "DRAFT":
                        # Черновик — это "в работе"
                        if assignment.status not in ["COMPLETED", "CANCELLED"]:
                            assignment.status = "IN_PROGRESS"
                    else:
                        # Прочие статусы не меняем, чтобы не ломать логику
                        pass
                    await db.commit()
            except Exception:
                # Не блокируем создание инспекции из-за статуса задания
                await db.rollback()
        
        return {
            "id": str(new_inspection.id),
            "equipment_id": str(new_inspection.equipment_id),
            "questionnaire_id": questionnaire_id,
            "history_id": str(history_entry.id),  # ID записи в истории (версия 3.3.0)
            "status": "created",
            "date_performed": new_inspection.date_performed.isoformat() if new_inspection.date_performed else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create inspection: {str(e)}")


@router.delete("/api/inspections/{inspection_id}")
async def delete_inspection(
    inspection_id: str,
    force: bool = False,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    П.5.1 — Мягкое удаление обследования (soft-delete).
    Запись помечается как удалённая (is_deleted=True) и хранится 60 дней.
    Параметр force=true (только admin) — немедленное физическое удаление.
    """
    from datetime import datetime, timezone as tz
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)

        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")

        insp_result = await db.execute(
            select(Inspection).where(Inspection.id == insp_uuid)
        )
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Обследование не найдено")

        # Права доступа
        allowed = False
        if current_user.role in ["admin", "chief_operator", "operator"]:
            allowed = True
        elif current_user.role == "engineer":
            if inspection.inspector_id and inspection.inspector_id == current_user.id:
                allowed = True
        if not allowed:
            raise HTTPException(status_code=403, detail="Доступ запрещён")

        if force and current_user.role == "admin":
            # Физическое удаление (только admin, принудительно)
            rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
            related_reports = rep_result.scalars().all()
            for report in related_reports:
                for p in [report.file_path, getattr(report, "word_file_path", None)]:
                    if p:
                        try:
                            fp = Path(p)
                            if fp.exists():
                                fp.unlink()
                        except Exception:
                            pass
                await db.delete(report)
            await db.flush()

            try:
                ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
                for m in ndt_result.scalars().all():
                    await db.delete(m)
                await db.flush()
            except Exception:
                pass

            await db.delete(inspection)
            await db.commit()
            return {"status": "permanently_deleted", "id": inspection_id}
        else:
            # Мягкое удаление — пометить, не трогать данные
            inspection.is_deleted = True
            inspection.deleted_at = datetime.now(tz.utc)
            inspection.deleted_by = current_user.id
            await db.commit()
            return {
                "status": "soft_deleted",
                "id": inspection_id,
                "deleted_at": inspection.deleted_at.isoformat(),
                "restore_within_days": 60,
            }
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат inspection_id")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Ошибка удаления: {str(e)}")


@router.post("/api/inspections/{inspection_id}/restore")
async def restore_inspection(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    П.5.1 — Восстановление мягко удалённого обследования (в течение 60 дней).
    """
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)

        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")

        insp_result = await db.execute(
            select(Inspection).where(Inspection.id == insp_uuid, Inspection.is_deleted == True)
        )
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Удалённое обследование не найдено")

        # Только admin/chief_operator и автор могут восстанавливать
        allowed = current_user.role in ["admin", "chief_operator"]
        if not allowed and inspection.deleted_by == current_user.id:
            allowed = True
        if not allowed:
            raise HTTPException(status_code=403, detail="Доступ запрещён")

        inspection.is_deleted = False
        inspection.deleted_at = None
        inspection.deleted_by = None
        await db.commit()
        return {"status": "restored", "id": inspection_id}
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат inspection_id")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Ошибка восстановления: {str(e)}")


@router.delete("/api/inspections-trash/purge")
async def purge_deleted_inspections(
    older_than_days: int = 60,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    П.5.1 — Принудительная очистка корзины (только admin).
    Физически удаляет записи с is_deleted=True старше older_than_days дней.
    """
    from datetime import datetime, timedelta, timezone as tz

    user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
    current_user = user_result.scalar_one_or_none()
    if not current_user or current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Только для администратора")

    cutoff = datetime.now(tz.utc) - timedelta(days=older_than_days)
    result = await db.execute(
        select(Inspection).where(
            Inspection.is_deleted == True,
            Inspection.deleted_at <= cutoff,
        )
    )
    to_purge = result.scalars().all()

    deleted_count = 0
    for inspection in to_purge:
        # Удаляем связанные отчёты
        rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
        for report in rep_result.scalars().all():
            for p in [report.file_path, getattr(report, "word_file_path", None)]:
                if p:
                    try:
                        fp = Path(p)
                        if fp.exists():
                            fp.unlink()
                    except Exception:
                        pass
            await db.delete(report)
        await db.flush()

        try:
            ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
            for m in ndt_result.scalars().all():
                await db.delete(m)
            await db.flush()
        except Exception:
            pass

        await db.delete(inspection)
        deleted_count += 1

    await db.commit()
    return {"status": "purged", "deleted_count": deleted_count, "older_than_days": older_than_days}


@router.get("/api/inspections-trash")
async def list_deleted_inspections(
    skip: int = 0,
    limit: int = 100,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """П.5.1 — Список мягко удалённых обследований (корзина). Только admin/chief_operator."""
    user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
    current_user = user_result.scalar_one_or_none()
    if not current_user or current_user.role not in ["admin", "chief_operator"]:
        raise HTTPException(status_code=403, detail="Доступ запрещён")

    result = await db.execute(
        select(Inspection)
        .where(Inspection.is_deleted == True)
        .order_by(Inspection.deleted_at.desc())
        .offset(skip)
        .limit(limit)
    )
    items = result.scalars().all()

    from datetime import datetime, timezone as tz
    now = datetime.now(tz.utc)
    rows = []
    for ins in items:
        days_left = None
        if ins.deleted_at:
            delta = (ins.deleted_at.replace(tzinfo=tz.utc) + __import__('datetime').timedelta(days=60)) - now
            days_left = max(0, delta.days)
        rows.append({
            "id": str(ins.id),
            "equipment_id": str(ins.equipment_id) if ins.equipment_id else None,
            "status": ins.status,
            "inspection_type": ins.inspection_type,
            "deleted_at": ins.deleted_at.isoformat() if ins.deleted_at else None,
            "days_left_to_restore": days_left,
        })
    return {"total": len(rows), "items": rows}


@router.delete("/api/inspections/cleanup")
async def cleanup_inspections(
    older_than_days: int = 180,
    before: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Массовое удаление старых чек-листов (inspections) и связанных отчетов/методов НК.
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои
    """
    try:
        # Совместимость: username в токене может быть email
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        cutoff = None
        if before:
            try:
                cutoff = datetime.fromisoformat(before.replace("Z", "+00:00"))
            except Exception:
                try:
                    cutoff = datetime.strptime(before, "%Y-%m-%d")
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid 'before' format")
        else:
            if older_than_days < 1:
                raise HTTPException(status_code=400, detail="older_than_days must be >= 1")
            cutoff = datetime.now() - timedelta(days=int(older_than_days))

        insp_query = select(Inspection).where(Inspection.created_at < cutoff)
        if current_user.role == "engineer":
            insp_query = insp_query.where(Inspection.inspector_id == current_user.id)
        elif current_user.role not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        insp_result = await db.execute(insp_query)
        inspections = insp_result.scalars().all()

        deleted = 0
        reports_deleted = 0
        for inspection in inspections:
            # связанные отчеты (сначала отчёты, иначе FK violation)
            rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
            related_reports = rep_result.scalars().all()
            for report in related_reports:
                for p in [report.file_path, getattr(report, "word_file_path", None)]:
                    if p:
                        try:
                            fp = Path(p)
                            if fp.exists():
                                fp.unlink()
                        except Exception:
                            pass
                await db.delete(report)
                reports_deleted += 1
            if related_reports:
                await db.flush()

            # методы НК
            try:
                ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
                for m in ndt_result.scalars().all():
                    await db.delete(m)
                await db.flush()
            except Exception:
                pass

            await db.delete(inspection)
            deleted += 1

        await db.commit()
        return {"status": "ok", "deleted": deleted, "reports_deleted": reports_deleted, "cutoff": cutoff.isoformat()}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to cleanup inspections: {str(e)}")


@router.get("/api/inspections/{inspection_id}/preview")
async def get_inspection_preview(inspection_id: str, db: AsyncSession = Depends(get_db)):
    """Получить данные инспекции для предпросмотра перед генерацией отчета"""
    try:
        inspection_uuid = uuid_lib.UUID(inspection_id)
        
        # Получаем данные инспекции
        result = await db.execute(
            select(Inspection).where(Inspection.id == inspection_uuid)
        )
        inspection = result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")
        
        # Получаем данные оборудования
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == inspection.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")

        # Данные ОПО (если оборудование привязано к ОПО)
        opo_info = None
        try:
            opo = None
            if getattr(equipment, "opo_id", None):
                opo_result = await db.execute(select(Opo).where(Opo.id == equipment.opo_id))
                opo = opo_result.scalar_one_or_none()
            if opo:
                workshop = None
                branch = None
                enterprise = None
                if getattr(opo, "workshop_id", None):
                    w_result = await db.execute(select(Workshop).where(Workshop.id == opo.workshop_id))
                    workshop = w_result.scalar_one_or_none()
                if workshop and getattr(workshop, "branch_id", None):
                    b_result = await db.execute(select(Branch).where(Branch.id == workshop.branch_id))
                    branch = b_result.scalar_one_or_none()
                if branch and getattr(branch, "enterprise_id", None):
                    e_result = await db.execute(select(Enterprise).where(Enterprise.id == branch.enterprise_id))
                    enterprise = e_result.scalar_one_or_none()

                opo_info = {
                    "id": str(opo.id),
                    "name": opo.name,
                    "code": opo.code,
                    "description": opo.description,
                    "survey_data": opo.survey_data or {},
                    "workshop_id": str(opo.workshop_id) if opo.workshop_id else None,
                    "workshop_name": workshop.name if workshop else None,
                    "branch_id": str(branch.id) if branch else None,
                    "branch_name": branch.name if branch else None,
                    "enterprise_id": str(enterprise.id) if enterprise else None,
                    "enterprise_name": enterprise.name if enterprise else None,
                }
        except Exception as e:
            print(f"Warning: Could not load OPO info for preview: {e}")
            opo_info = None
        
        # Questionnaire: приоритет — questionnaire_id инспекции, иначе последний по оборудованию
        questionnaire = None
        if getattr(inspection, "questionnaire_id", None):
            q_by_inspection = await db.execute(
                select(Questionnaire)
                .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                .where(Questionnaire.id == inspection.questionnaire_id)
            )
            questionnaire = q_by_inspection.scalar_one_or_none()
        if not questionnaire:
            questionnaire_result = await db.execute(
                select(Questionnaire)
                .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                .where(Questionnaire.equipment_id == equipment.id)
                .order_by(Questionnaire.created_at.desc()).limit(1)
            )
            questionnaire = questionnaire_result.scalar_one_or_none()

        # Методы НК: по inspection_id, затем по questionnaire (привязанному к инспекции)
        ndt_methods = []
        try:
            ndt_result = await db.execute(
                select(NDTMethod).where(NDTMethod.inspection_id == inspection.id)
            )
            ndt_methods = ndt_result.scalars().all()
        except Exception:
            ndt_methods = []
        if not ndt_methods and questionnaire:
            ndt_result = await db.execute(
                select(NDTMethod).where(NDTMethod.questionnaire_id == questionnaire.id)
            )
            ndt_methods = ndt_result.scalars().all()

        # Файлы документов/вложений (при наличии questionnaire_id у инспекции — берём его)
        document_files = []
        try:
            q_for_files = questionnaire
            if not q_for_files and getattr(inspection, "questionnaire_id", None):
                q_by_id = await db.execute(
                    select(Questionnaire)
                    .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                    .where(Questionnaire.id == inspection.questionnaire_id)
                )
                q_for_files = q_by_id.scalar_one_or_none()
            if not q_for_files:
                q_query = (
                    select(Questionnaire)
                    .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                    .where(Questionnaire.equipment_id == equipment.id)
                )
                if getattr(inspection, "created_at", None):
                    q_query = q_query.order_by(
                        func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
                    ).limit(1)
                else:
                    q_query = q_query.order_by(Questionnaire.created_at.desc()).limit(1)
                q_result = await db.execute(q_query)
                q_for_files = q_result.scalar_one_or_none()
            if q_for_files:
                questionnaire = q_for_files
                files_result = await db.execute(
                    select(QuestionnaireDocumentFile).where(
                        QuestionnaireDocumentFile.questionnaire_id == q_for_files.id
                    )
                )
                files = files_result.scalars().all()
                qid = str(q_for_files.id)
                document_files = [
                    {
                        "document_number": f.document_number,
                        "file_name": f.file_name,
                        "file_size": int(f.file_size or 0),
                        "file_type": f.file_type,
                        "mime_type": f.mime_type,
                        "view_url": f"/api/questionnaires/{qid}/documents/{f.document_number}/view",
                    }
                    for f in files
                ]
        except Exception:
            document_files = []
        
        # Получаем данные ресурса, если есть
        resource_data = None
        res_result = await db.execute(
            select(EquipmentResource).where(EquipmentResource.equipment_id == equipment.id)
            .order_by(EquipmentResource.created_at.desc()).limit(1)
        )
        resource = res_result.scalar_one_or_none()
        if resource:
            # Используем поля, которые есть в модели EquipmentResource
            resource_data = {
                "resource_type": resource.resource_type,
                "current_value": float(resource.current_value) if resource.current_value else None,
                "limit_value": float(resource.limit_value) if resource.limit_value else None,
                "unit": resource.unit,
                "last_updated": resource.last_updated.isoformat() if resource.last_updated else None,
            }
        
        return {
            "inspection": {
                "id": str(inspection.id),
                "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                "status": inspection.status,
                "conclusion": inspection.conclusion,
                "data": inspection.data,
            },
            "equipment": {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
                "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                "attributes": equipment.attributes or {},
            },
            "questionnaire": {
                "id": str(questionnaire.id) if questionnaire else None,
            },
            "document_files": document_files,
            "opo": opo_info,
            "ndt_methods": [
                {
                    "id": str(m.id),
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": m.photos or [],
                    "additional_data": m.additional_data or {},
                }
                for m in ndt_methods
            ],
            "resource": resource_data,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to get preview: {str(e)}")


@router.get("/api/inspections/{inspection_id}/questionnaire")
async def get_inspection_questionnaire_info(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """
    Получить привязанный к инспекции опросный лист (questionnaire_id) и файлы документов.
    Нужен для корректного отображения названий и вложений документов в веб-интерфейсе.
    """
    try:
        inspection_uuid = uuid_lib.UUID(inspection_id)

        ins_result = await db.execute(select(Inspection).where(Inspection.id == inspection_uuid))
        inspection = ins_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        # Ищем наиболее подходящий questionnaire (load_only — без assignment_id)
        q_query = (
            select(Questionnaire)
            .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
            .where(Questionnaire.equipment_id == inspection.equipment_id)
        )
        if getattr(inspection, "created_at", None):
            q_query = q_query.order_by(
                func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
            ).limit(1)
        else:
            q_query = q_query.order_by(Questionnaire.created_at.desc()).limit(1)

        q_result = await db.execute(q_query)
        questionnaire = q_result.scalar_one_or_none()

        if not questionnaire:
            return {"questionnaire_id": None, "document_files": []}

        files_result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == questionnaire.id
            )
        )
        files = files_result.scalars().all()

        qid = str(questionnaire.id)
        return {
            "questionnaire_id": qid,
            "document_files": [
                {
                    "id": str(f.id),
                    "document_number": f.document_number,
                    "file_name": f.file_name,
                    "file_size": int(f.file_size or 0),
                    "file_type": f.file_type,
                    "mime_type": f.mime_type,
                    "created_at": f.created_at.isoformat() if f.created_at else None,
                    "view_url": f"/api/questionnaires/{qid}/documents/{f.document_number}/view",
                }
                for f in files
            ],
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Failed to get inspection questionnaire info: {str(e)}")


@router.post("/api/inspections/bulk-delete")
async def bulk_delete_inspections(
    request: BulkDeleteInspectionsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое удаление чек-листов"""
    try:
        inspection_ids = request.inspection_ids
        if not inspection_ids:
            raise HTTPException(status_code=400, detail="No inspection IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        deleted_count = 0
        for inspection_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
                inspection = insp_result.scalar_one_or_none()
                
                if not inspection:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if inspection.inspector_id and inspection.inspector_id == user.id:
                        allowed = True
                
                if not allowed:
                    continue
                
                # ВАЖНО: НЕ удаляем связанные отчеты при удалении чек-листа!
                # Отчеты должны оставаться в системе даже если чек-лист удален.
                # Проверяем, есть ли связанные отчеты - если есть, не удаляем инспекцию
                rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
                related_reports = rep_result.scalars().all()
                
                if related_reports:
                    # Если есть связанные отчеты, пропускаем удаление этой инспекции
                    print(f"⚠️ Inspection {inspection_id} has {len(related_reports)} related reports. Skipping deletion to preserve reports.")
                    continue
                
                # Удаляем связанные методы НК
                try:
                    ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
                    ndt_methods = ndt_result.scalars().all()
                    for m in ndt_methods:
                        await db.delete(m)
                    if ndt_methods:
                        await db.flush()
                except Exception as e:
                    print(f"⚠️ Error deleting NDT methods for inspection {inspection_id}: {str(e)}")
                
                # Удаляем связанное оборудование для поверок
                try:
                    eq_result = await db.execute(select(InspectionEquipment).where(InspectionEquipment.inspection_id == inspection.id))
                    inspection_equipment = eq_result.scalars().all()
                    for eq in inspection_equipment:
                        await db.delete(eq)
                    if inspection_equipment:
                        await db.flush()
                except Exception as e:
                    print(f"⚠️ Error deleting inspection equipment for inspection {inspection_id}: {str(e)}")
                
                # Теперь можно безопасно удалить сам чек-лист
                await db.delete(inspection)
                deleted_count += 1
            except Exception as e:
                # Логируем ошибку для отладки, но продолжаем обработку других записей
                print(f"⚠️ Error deleting inspection {inspection_id}: {str(e)}")
                continue
        
        await db.commit()
        return {"deleted": deleted_count, "total": len(inspection_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete inspections: {str(e)}")


@router.post("/api/inspections/bulk-archive")
async def bulk_archive_inspections(
    request: BulkArchiveRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое архивирование/разархивирование чек-листов"""
    try:
        inspection_ids = request.inspection_ids
        archive = request.archive
        if not inspection_ids:
            raise HTTPException(status_code=400, detail="No inspection IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        archived_count = 0
        for inspection_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
                inspection = insp_result.scalar_one_or_none()
                
                if not inspection:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if inspection.inspector_id and inspection.inspector_id == user.id:
                        allowed = True
                
                if not allowed:
                    continue
                
                inspection.is_archived = archive
                archived_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"archived": archived_count, "total": len(inspection_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to archive inspections: {str(e)}")
