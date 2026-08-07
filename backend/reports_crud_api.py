"""Reports CRUD API — endpoints для генерации, управления и скачивания отчётов."""

import os
import io
import time
import zipfile
import json as _json
import uuid as uuid_lib
from pathlib import Path, Path as _Path
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse, FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, and_, func
from sqlalchemy.orm import load_only
from pydantic import BaseModel

from database import get_db
from auth import verify_token
from auth_api import get_current_user
from models import (
    User, Report, Inspection, Equipment, EquipmentType,
    Workshop, Branch, Enterprise, Opo, EquipmentResource,
    NDTMethod, Questionnaire, QuestionnaireDocumentFile,
    InspectionEquipment, VerificationEquipment, Certification,
    Engineer, Client, Assignment,
)
from report_generator import ReportGenerator
from shared import resolve_report_file_path, metrics
from report_attachments import enrich_document_files_from_inspection
from client_access import get_client_accessible_equipment_ids, client_user_can_access_equipment
from report_org_settings import load_report_org_settings, merge_client_into_settings
from report_forms_registry import suggest_form_id, get_form

_resolve_report_file_path = resolve_report_file_path
_metrics = metrics

router = APIRouter(tags=["reports"])


async def _resolve_client_context(
    db: AsyncSession,
    equipment: Equipment,
) -> tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Получить данные клиента и предприятия по цепочке workshop → branch → enterprise."""
    enterprise_name = None
    if not equipment or not getattr(equipment, "workshop_id", None):
        return None, enterprise_name
    ws_res = await db.execute(select(Workshop).where(Workshop.id == equipment.workshop_id))
    workshop = ws_res.scalar_one_or_none()
    if not workshop or not workshop.branch_id:
        return None, enterprise_name
    br_res = await db.execute(select(Branch).where(Branch.id == workshop.branch_id))
    branch = br_res.scalar_one_or_none()
    if not branch or not branch.enterprise_id:
        return None, enterprise_name
    ent_res = await db.execute(select(Enterprise).where(Enterprise.id == branch.enterprise_id))
    enterprise = ent_res.scalar_one_or_none()
    if not enterprise:
        return None, enterprise_name
    enterprise_name = enterprise.name
    if not enterprise.client_id:
        return None, enterprise_name
    cl_res = await db.execute(select(Client).where(Client.id == enterprise.client_id))
    client = cl_res.scalar_one_or_none()
    if not client:
        return None, enterprise_name
    return {
        "name": client.name,
        "inn": client.inn,
        "address": client.address,
        "phone": client.phone,
        "email": client.email,
        "contact_person": client.contact_person,
    }, enterprise_name


async def _load_user_by_login(db: AsyncSession, username: str) -> Optional[User]:
    result = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    return result.scalar_one_or_none()


def _ensure_template_permissions(user: Optional[User]) -> None:
    allowed_roles = {"admin", "chief_operator", "operator"}
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if getattr(user, "role", None) not in allowed_roles:
        raise HTTPException(status_code=403, detail="Недостаточно прав для управления шаблонами")


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class BulkDeleteReportsRequest(BaseModel):
    report_ids: List[str]


class BulkArchiveReportsRequest(BaseModel):
    report_ids: List[str]
    archive: bool = True


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/api/reports")
async def get_reports(
    inspection_id: Optional[str] = None,
    equipment_id: Optional[str] = None,
    project_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get reports (с учетом прав: инженер видит только свои отчеты)"""
    try:
        # Текущий пользователь и роль
        # Совместимость: username в токене может быть email (старые токены / ввод email)
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        query = select(Report)

        if current_user.role == "client":
            allowed_eq = await get_client_accessible_equipment_ids(db, current_user)
            if not allowed_eq:
                return {"items": [], "total": 0}
            insp_allowed = select(Inspection.id).where(Inspection.equipment_id.in_(allowed_eq))
            query = query.where(Report.inspection_id.in_(insp_allowed))
        # Временно НЕ фильтруем по is_archived, чтобы показать все отчеты
        # Фильтрация будет добавлена позже, когда будет уверенность, что поле корректно работает
        # query = query.where(Report.is_archived == False)
        if inspection_id:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                query = query.where(Report.inspection_id == insp_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid inspection_id format")
        # Фильтрация по equipment_id и project_id через связанные инспекции
        if equipment_id:
            try:
                eq_uuid = uuid_lib.UUID(equipment_id)
                # Фильтруем через связанные инспекции
                insp_subquery = select(Inspection.id).where(Inspection.equipment_id == eq_uuid)
                query = query.where(Report.inspection_id.in_(insp_subquery))
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        if project_id:
            try:
                proj_uuid = uuid_lib.UUID(project_id)
                # Фильтруем через связанные инспекции
                insp_subquery = select(Inspection.id).where(Inspection.project_id == proj_uuid)
                query = query.where(Report.inspection_id.in_(insp_subquery))
            except:
                raise HTTPException(status_code=400, detail="Invalid project_id format")

        # Ограничиваем инженера только своими отчетами.
        # created_by хранится как UUID (users.id). Фолбэк для старых записей: если created_by пустой,
        # пытаемся определить по inspection.inspector_id.
        if current_user.role == "engineer":
            query = (
                query.join(Inspection, Report.inspection_id == Inspection.id, isouter=True)
                .where(
                    or_(
                        Report.created_by == current_user.id,
                        and_(
                            Report.created_by.is_(None),
                            or_(
                                Inspection.inspector_id == current_user.id,
                                Inspection.performed_by == current_user.id,
                            ),
                        ),
                    )
                )
            )

        result = await db.execute(query.order_by(Report.created_at.desc()))
        reports = result.scalars().all()
        
        # Получаем информацию об инженерах из связанных инспекций
        report_items = []
        for r in reports:
            inspector_name = None
            inspector_position = None
            equipment_id = None
            project_id = None
            inspection = None
            enterprise_id = None
            enterprise_name = None
            branch_id = None
            branch_name = None
            workshop_id = None
            workshop_name = None
            equipment_name = None
            
            # Пытаемся получить ФИО инженера из связанной инспекции
            if r.inspection_id:
                insp_result = await db.execute(
                    select(Inspection).where(Inspection.id == r.inspection_id)
                )
                inspection = insp_result.scalar_one_or_none()
                if inspection:
                    # Получаем equipment_id и project_id из инспекции
                    equipment_id = str(inspection.equipment_id) if inspection.equipment_id else None
                    project_id = str(inspection.project_id) if inspection.project_id else None
                    
                    # Получаем информацию об оборудовании и иерархии
                    if inspection.equipment_id:
                        eq_result = await db.execute(
                            select(Equipment).where(Equipment.id == inspection.equipment_id)
                        )
                        equipment = eq_result.scalar_one_or_none()
                        if equipment:
                            equipment_name = equipment.name
                            
                            # Получаем информацию о цехе, филиале и предприятии
                            if equipment.workshop_id:
                                try:
                                    workshop_result = await db.execute(
                                        select(Workshop).where(Workshop.id == equipment.workshop_id)
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
                                                    print(f"⚠️ Error loading enterprise for report {r.id}: {e}")
                                        except Exception as e:
                                            await db.rollback()
                                            print(f"⚠️ Error loading branch for report {r.id}: {e}")
                                except Exception as e:
                                    await db.rollback()
                                    print(f"⚠️ Error loading workshop for report {r.id}: {e}")
                    
                    if inspection.inspector_id:
                        # Получаем информацию об инженере из users
                        user_result = await db.execute(
                            select(User).where(User.id == inspection.inspector_id)
                        )
                        user = user_result.scalar_one_or_none()
                        if user:
                            inspector_name = user.full_name or user.username
                            # Пытаемся получить должность из связанного engineer
                            if user.engineer_id:
                                eng_result = await db.execute(
                                    select(Engineer).where(Engineer.id == user.engineer_id)
                                )
                                engineer = eng_result.scalar_one_or_none()
                                if engineer:
                                    inspector_position = engineer.position
            
            report_items.append({
                "id": str(r.id),
                "inspection_id": str(r.inspection_id) if r.inspection_id else None,
                "equipment_id": equipment_id,
                "equipment_name": equipment_name,
                "project_id": project_id,
                "enterprise_id": enterprise_id,
                "enterprise_name": enterprise_name,
                "branch_id": branch_id,
                "branch_name": branch_name,
                "workshop_id": workshop_id,
                "workshop_name": workshop_name,
                "report_type": r.report_type,
                "title": f"{r.report_type} Report" if r.report_type else "Report",
                "file_path": r.file_path,
                "file_size": r.file_size,
                # Статус отчета берём из статуса инспекции, если она есть (DRAFT/SIGNED/APPROVED).
                # Фолбэк: если инспекции нет, считаем что файл -> GENERATED иначе DRAFT.
                "status": (inspection.status if inspection and getattr(inspection, "status", None) else ("GENERATED" if r.file_path else "DRAFT")),
                "inspector_name": inspector_name,
                "inspector_position": inspector_position,
                "created_by": str(r.created_by) if r.created_by else None,
                "is_archived": getattr(r, "is_archived", False),
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "word_file_path": getattr(r, "word_file_path", None),
                "word_file_size": getattr(r, "word_file_size", None),
            })
        
        return {
            "items": report_items
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_reports: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении отчетов: {error_detail}")


@router.get("/api/reports/validate/{inspection_id}")
async def validate_report_inspection(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Проверка полноты данных обследования перед генерацией отчёта"""
    try:
        from report_utils import validate_inspection_completeness
        result = await validate_inspection_completeness(db, inspection_id)
        return result
    except Exception as e:
        return {
            "is_complete": False,
            "missing_fields": [f"Ошибка проверки: {str(e)}"],
            "warnings": [],
            "can_generate": False
        }


@router.post("/api/reports/generate")
async def generate_report(
    report_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Generate technical report or expertise"""
    try:
        # Текущий пользователь
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        inspection_id = None
        if report_data.get("inspection_id"):
            try:
                inspection_id = uuid_lib.UUID(report_data.get("inspection_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid inspection_id format")

        opo_info = None
        
        # Get inspection data
        if inspection_id:
            result = await db.execute(
                select(Inspection).where(Inspection.id == inspection_id)
            )
            inspection = result.scalar_one_or_none()
            if not inspection:
                raise HTTPException(status_code=404, detail="Inspection not found")
            # Роли и права на отчёты: инженер — только по своим обследованиям
            if getattr(current_user, "role", None) == "engineer":
                own = (
                    (getattr(inspection, "inspector_id", None) == current_user.id)
                    or (getattr(inspection, "performed_by", None) == current_user.id)
                    or (getattr(inspection, "created_by", None) == current_user.id)
                )
                if not own:
                    raise HTTPException(status_code=403, detail="Нет прав на генерацию отчёта по этому обследованию")

            report_type_req = (report_data.get("report_type") or "TECHNICAL_REPORT").strip().upper()
            if report_type_req == "EXPERTISE":
                to_check = await db.execute(
                    select(Report.id).where(
                        Report.inspection_id == inspection_id,
                        Report.report_type == "TECHNICAL_REPORT",
                    ).limit(1)
                )
                if not to_check.scalar_one_or_none():
                    raise HTTPException(
                        status_code=400,
                        detail="Сначала необходимо сгенерировать технический отчёт по этому обследованию",
                    )
            
            # Get equipment data
            eq_result = await db.execute(
                select(Equipment).where(Equipment.id == inspection.equipment_id)
            )
            equipment = eq_result.scalar_one_or_none()
            if not equipment:
                raise HTTPException(status_code=404, detail="Equipment not found")
            
            # Get equipment type information
            equipment_type_code = None
            equipment_type_name = None
            if equipment.type_id:
                type_result = await db.execute(
                    select(EquipmentType).where(EquipmentType.id == equipment.type_id)
                )
                equipment_type = type_result.scalar_one_or_none()
                if equipment_type:
                    equipment_type_code = equipment_type.code
                    equipment_type_name = equipment_type.name

            # Данные ОПО для отчета (если оборудование привязано к ОПО)
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
                        "hazard_class": getattr(opo, "hazard_class", None),
                        "registration_number": getattr(opo, "registration_number", None),
                        "survey_data": opo.survey_data or {},
                        "workshop_id": str(opo.workshop_id) if opo.workshop_id else None,
                        "workshop_name": workshop.name if workshop else None,
                        "branch_id": str(branch.id) if branch else None,
                        "branch_name": branch.name if branch else None,
                        "enterprise_id": str(enterprise.id) if enterprise else None,
                        "enterprise_name": enterprise.name if enterprise else None,
                    }
            except Exception as e:
                print(f"Warning: Could not load OPO info: {e}")
                opo_info = None
            
            # Get resource data if expertise
            resource_data = None
            if report_data.get("report_type") == "EXPERTISE":
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
            
            # Методы НК:
            # 1) Сначала пытаемся взять методы, привязанные напрямую к inspection_id (3.3.0+)
            # 2) Фолбэк: методы, привязанные к последнему questionnaire по этому оборудованию (историческая логика)
            ndt_methods = []
            try:
                ndt_result = await db.execute(
                    select(NDTMethod).where(NDTMethod.inspection_id == inspection.id)
                )
                ndt_methods = ndt_result.scalars().all()
            except Exception:
                ndt_methods = []

            if not ndt_methods:
                questionnaire_result = await db.execute(
                    select(Questionnaire)
                    .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                    .where(Questionnaire.equipment_id == equipment.id)
                    .order_by(Questionnaire.created_at.desc()).limit(1)
                )
                questionnaire = questionnaire_result.scalar_one_or_none()

                if questionnaire:
                    ndt_result = await db.execute(
                        select(NDTMethod).where(NDTMethod.questionnaire_id == questionnaire.id)
                    )
                    ndt_methods = ndt_result.scalars().all()

            # Опросник для вложений отчёта: только связанный с этим обследованием (без «угадайки» по оборудованию —
            # иначе в отчёт попадали файлы из чужих опросников с тем же оборудованием).
            q_for_files = None
            try:
                if getattr(inspection, "questionnaire_id", None):
                    q_by_id = await db.execute(
                        select(Questionnaire)
                        .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                        .where(Questionnaire.id == inspection.questionnaire_id)
                    )
                    q_for_files = q_by_id.scalar_one_or_none()
                if not q_for_files and getattr(inspection, "assignment_id", None):
                    q_by_assign = await db.execute(
                        select(Questionnaire)
                        .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                        .where(Questionnaire.assignment_id == inspection.assignment_id)
                        .order_by(Questionnaire.created_at.desc())
                        .limit(1)
                    )
                    q_for_files = q_by_assign.scalar_one_or_none()
            except Exception:
                q_for_files = None

            questionnaire_scope = str(q_for_files.id) if q_for_files else None
            inspection_scope = str(inspection.id)

            def _inspect_attachment_path(local_path: Optional[str]) -> Optional[str]:
                if not local_path or not isinstance(local_path, str):
                    return local_path
                return resolve_report_file_path(
                    local_path,
                    inspection_id=inspection_scope,
                    questionnaire_id=questionnaire_scope,
                ) or local_path

            document_files = []
            if q_for_files:
                try:
                    files_result = await db.execute(
                        select(QuestionnaireDocumentFile).where(
                            QuestionnaireDocumentFile.questionnaire_id == q_for_files.id
                        )
                    )
                    files = files_result.scalars().all()
                    document_files = [
                        {
                            "document_number": f.document_number,
                            "file_name": f.file_name,
                            "file_path": _inspect_attachment_path(f.file_path) or f.file_path,
                            "file_size": int(f.file_size or 0),
                            "file_type": f.file_type,
                            "mime_type": f.mime_type,
                        }
                        for f in files
                    ]
                except Exception:
                    document_files = []
            # Дополняем из inspection.data (пути после синхронизации с мобильного)
            _existing_dn = {str(f.get("document_number")) for f in document_files if f.get("document_number")}
            _data = inspection.data if isinstance(getattr(inspection, "data", None), dict) else {}
            for _key in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
                if _key not in _existing_dn and _data.get(_key):
                    _p = (_data.get(_key) or "").strip()
                    if _p:
                        document_files.append({"document_number": _key, "file_name": os.path.basename(_p), "file_path": _inspect_attachment_path(_p) or _p})
                        _existing_dn.add(_key)
            document_files = enrich_document_files_from_inspection(
                document_files,
                _data,
                resolve_fn=_inspect_attachment_path,
                questionnaire_id=questionnaire_scope,
            )
            _existing_dn = {str(f.get("document_number")) for f in document_files if f.get("document_number")}
            _vd = _data.get("visual_defects")
            if isinstance(_vd, list):
                for _i, _d in enumerate(_vd):
                    if not isinstance(_d, dict):
                        continue
                    for _j, _ph in enumerate(_d.get("photos") or []):
                        if isinstance(_ph, str) and _ph.strip() and f"vd_{_i}_{_j}" not in _existing_dn:
                            document_files.append({"document_number": f"vd_{_i}_{_j}", "file_name": os.path.basename(_ph), "file_path": _inspect_attachment_path(_ph) or _ph})
                            _existing_dn.add(f"vd_{_i}_{_j}")
            _thickness = _data.get("thickness_measurements") or _data.get("thicknessMeasurements")
            if isinstance(_thickness, list):
                for _i, _t in enumerate(_thickness):
                    if not isinstance(_t, dict):
                        continue
                    for _j, _ph in enumerate(_t.get("photos") or []):
                        if isinstance(_ph, str) and _ph.strip() and f"uzt_point_{_i}_{_j}" not in _existing_dn:
                            document_files.append({"document_number": f"uzt_point_{_i}_{_j}", "file_name": os.path.basename(_ph), "file_path": _inspect_attachment_path(_ph) or _ph})
                            _existing_dn.add(f"uzt_point_{_i}_{_j}")
            _uzt_schemes = _data.get("uzt_schemes")
            if isinstance(_uzt_schemes, list):
                for _i, _scheme in enumerate(_uzt_schemes):
                    if not isinstance(_scheme, dict):
                        continue
                    _sp = _scheme.get("scheme_image_path")
                    if isinstance(_sp, str) and _sp.strip() and f"uzt_scheme_{_i}" not in _existing_dn:
                        document_files.append({
                            "document_number": f"uzt_scheme_{_i}",
                            "file_name": os.path.basename(_sp),
                            "file_path": _inspect_attachment_path(_sp) or _sp,
                        })
                        _existing_dn.add(f"uzt_scheme_{_i}")
                    _meas = _scheme.get("measurements") or []
                    if isinstance(_meas, list):
                        for _j, _m in enumerate(_meas):
                            if not isinstance(_m, dict):
                                continue
                            for _k, _ph in enumerate(_m.get("photos") or []):
                                _dk = f"uzt_scheme_{_i}_point_{_j}_{_k}"
                                if isinstance(_ph, str) and _ph.strip() and _dk not in _existing_dn:
                                    document_files.append({
                                        "document_number": _dk,
                                        "file_name": os.path.basename(_ph),
                                        "file_path": _inspect_attachment_path(_ph) or _ph,
                                    })
                                    _existing_dn.add(_dk)

            # Проверка целостности вложений: логируем отсутствующие файлы
            _missing_att = []
            for _f in (document_files or []):
                if not isinstance(_f, dict):
                    continue
                _fp = _f.get("file_path")
                if isinstance(_fp, str) and _fp.strip():
                    _p = Path(_fp)
                    _candidate = _p if _p.is_absolute() and _p.exists() else None
                    if not _candidate:
                        for _base in ["/app/uploads/questionnaire_documents", "/app/uploads", "/app/reports"]:
                            _cand = Path(_base) / _fp
                            if _cand.exists():
                                _candidate = _cand
                                break
                    if not _candidate or not _candidate.exists():
                        _missing_att.append(_f.get("document_number") or _f.get("file_name") or _fp)
            if _missing_att:
                print(f"Report generation: missing attachment files (inspection_id={inspection.id}): {_missing_att}")

            # Получаем используемое оборудование для поверок
            verification_equipment_list = []
            try:
                # Ищем по inspection_id
                inspection_eq_result = await db.execute(
                    select(InspectionEquipment).where(InspectionEquipment.inspection_id == inspection.id)
                )
                inspection_equipment = inspection_eq_result.scalars().all()
                
                for ie in inspection_equipment:
                    ver_eq_result = await db.execute(
                        select(VerificationEquipment).where(VerificationEquipment.id == ie.verification_equipment_id)
                    )
                    ver_eq = ver_eq_result.scalar_one_or_none()
                    if ver_eq:
                        scan_path = _resolve_report_file_path(ver_eq.scan_file_path) if ver_eq.scan_file_path else ver_eq.scan_file_path
                        verification_equipment_list.append({
                            "id": str(ver_eq.id),
                            "name": ver_eq.name,
                            "equipment_type": ver_eq.equipment_type,
                            "serial_number": ver_eq.serial_number,
                            "manufacturer": ver_eq.manufacturer,
                            "model": ver_eq.model,
                            "verification_date": ver_eq.verification_date.isoformat() if ver_eq.verification_date else None,
                            "next_verification_date": ver_eq.next_verification_date.isoformat() if ver_eq.next_verification_date else None,
                            "verification_certificate_number": ver_eq.verification_certificate_number,
                            "verification_organization": ver_eq.verification_organization,
                            "scan_file_path": scan_path,
                            "scan_file_name": ver_eq.scan_file_name,
                        })
            except Exception as e:
                print(f"Warning: Could not load verification equipment: {e}")
                verification_equipment_list = []
            
            # Generate report
            reports_dir = Path("/app/reports")
            reports_dir.mkdir(exist_ok=True)
            
            report_type = report_data.get("report_type", "TECHNICAL_REPORT")
            # pdf или docx (поддерживаем также WORD/DOC)
            output_format = (report_data.get("format") or "pdf").strip().lower()
            is_docx = output_format in ["docx", "doc", "word"]

            # Подключаем макет отчета (definition) из report_templates.json (MVP без миграций БД)
            template_definition = None
            try:
                templates_path = _Path("/app/reports/report_templates.json")
                if templates_path.exists():
                    templates = _json.loads(templates_path.read_text(encoding="utf-8") or "[]")
                    # ищем шаблон по типу оборудования (type_id), report_type и format
                    eq_type_id = str(getattr(equipment, "type_id", "") or "")
                    eq_type_code_upper = (equipment_type_code or "").strip().upper()

                    def _type_ok(t: dict) -> bool:
                        tid = (t.get("equipment_type_id") or "").strip()
                        tcode = (t.get("equipment_type_code") or "").strip().upper()
                        if tid and tid != eq_type_id:
                            return False
                        if tcode and eq_type_code_upper and tcode != eq_type_code_upper:
                            return False
                        return True

                    def _match(t):
                        if not isinstance(t, dict) or not t.get("is_active"):
                            return False
                        if not _type_ok(t):
                            return False
                        if (t.get("report_type") or "") and (t.get("report_type") != report_type):
                            return False
                        if (t.get("format") or "") and (t.get("format") != output_format):
                            return False
                        return True

                    chosen = next((t for t in templates if _match(t)), None)
                    if not chosen:
                        # fallback: любой активный по type_id / type_code
                        def _match2(t):
                            if not isinstance(t, dict) or not t.get("is_active"):
                                return False
                            if not _type_ok(t):
                                return False
                            if (t.get("report_type") or "") and (t.get("report_type") != report_type):
                                return False
                            return True
                        chosen = next((t for t in templates if _match2(t)), None)
                    if not chosen:
                        # fallback: общий активный (equipment_type_id / code null/empty)
                        def _match3(t):
                            if not isinstance(t, dict) or not t.get("is_active"):
                                return False
                            if (t.get("equipment_type_id") or "").strip():
                                return False
                            if (t.get("equipment_type_code") or "").strip():
                                return False
                            if (t.get("report_type") or "") and (t.get("report_type") != report_type):
                                return False
                            return True
                        chosen = next((t for t in templates if _match3(t)), None)
                    if chosen:
                        template_definition = chosen.get("definition")
            except Exception:
                template_definition = None
            
            if is_docx:
                # Генерация Word документа
                from word_generator import WordGenerator
                word_generator = WordGenerator()
                filename = f"{report_type}_{inspection.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.docx"
                file_path = reports_dir / filename
            else:
                # Генерация PDF
                generator = ReportGenerator()
                filename = f"{report_type}_{inspection.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
                file_path = reports_dir / filename
            
            # Проверяем, что ndt_methods не None и является списком
            if ndt_methods is None:
                ndt_methods = []
            
            def _resolve_photo_list(lst):
                if not isinstance(lst, list):
                    return lst
                return [_inspect_attachment_path(x) or x for x in lst if isinstance(x, str)]

            ndt_methods_data = []
            for m in ndt_methods:
                ad = m.additional_data or {}
                if isinstance(ad, dict) and "annotated_images" in ad and isinstance(ad["annotated_images"], list):
                    ad = dict(ad)
                    ad["annotated_images"] = _resolve_photo_list(ad["annotated_images"])
                cert_num = (ad.get("certificate_number") if isinstance(ad, dict) else None) or None
                ndt_methods_data.append({
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "certificate_number": cert_num,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": _resolve_photo_list(m.photos or []),
                    "additional_data": ad,
                    "performed_date": m.performed_date.isoformat() if m.performed_date else None,
                })

            # Приложения: документы специалистов (удостоверения/сертификаты НК) по ФИО из методов НК
            # + по специалистам, реально выбранным в мобильном приложении для этого обследования
            # (checklist.data.inspection_engineers) — иначе в отчёт может подтянуться
            # посторонний специалист без реального отношения к данному обследованию.
            specialist_docs = []
            try:
                inspector_names_set = {
                    str(m.get("inspector_name")).strip() for m in ndt_methods_data if m.get("inspector_name")
                }
                engineer_ids_set = set()
                raw_insp_data = inspection.data if isinstance(inspection.data, dict) else {}
                for eng in (raw_insp_data.get("inspection_engineers") or []):
                    if isinstance(eng, dict):
                        nm = str(eng.get("full_name") or eng.get("name") or "").strip()
                        if nm:
                            inspector_names_set.add(nm)
                        eid = eng.get("engineer_id")
                        if eid:
                            engineer_ids_set.add(str(eid))
                # Прямой lookup аттестаций по engineer_id из чек-листа —
                # надёжнее, чем только по совпадению ФИО пользователя.
                for eid in sorted(engineer_ids_set):
                    try:
                        eid_uuid = uuid_lib.UUID(str(eid))
                        certs_res = await db.execute(
                            select(Certification).where(
                                Certification.engineer_id == eid_uuid,
                            )
                        )
                        certs = certs_res.scalars().all()
                    except Exception:
                        certs = []
                    if not certs:
                        continue
                    # имя — из inspection_engineers
                    name = next(
                        (
                            str(e.get("full_name") or e.get("name") or "").strip()
                            for e in (raw_insp_data.get("inspection_engineers") or [])
                            if isinstance(e, dict) and str(e.get("engineer_id") or "") == eid
                        ),
                        "",
                    )
                    if not name:
                        continue
                    items = []
                    for c in certs:
                        sp = getattr(c, "scan_file_path", None)
                        sp_resolved = (_resolve_report_file_path(sp) or sp) if sp else None
                        items.append(
                            {
                                "certification_type": getattr(c, "certification_type", None),
                                "certificate_number": getattr(c, "certificate_number", None),
                                "method_code": getattr(c, "method_code", None),
                                "issuing_organization": getattr(c, "issuing_organization", None),
                                "issue_date": str(getattr(c, "issue_date", None)) if getattr(c, "issue_date", None) else None,
                                "expiry_date": str(getattr(c, "expiry_date", None)) if getattr(c, "expiry_date", None) else None,
                                "scan_file_path": sp_resolved,
                                "scan_file_name": getattr(c, "scan_file_name", None),
                                "scan_mime_type": getattr(c, "scan_mime_type", None),
                            }
                        )
                    if items:
                        specialist_docs.append({"inspector_name": name, "certifications": items})
                        inspector_names_set.discard(name)
                inspector_names = sorted(inspector_names_set, key=lambda s: s.lower())
                for name in inspector_names:
                    # ищем пользователя по full_name или username (берём первого при совпадении нескольких)
                    ures = await db.execute(
                        select(User).where(or_(User.full_name == name, User.username == name)).limit(1)
                    )
                    u = ures.scalar_one_or_none()
                    if not u or not getattr(u, "engineer_id", None):
                        continue
                    certs_res = await db.execute(
                        select(Certification).where(
                            Certification.engineer_id == u.engineer_id,
                        )
                    )
                    certs = certs_res.scalars().all()
                    items = []
                    for c in certs:
                        sp = getattr(c, "scan_file_path", None)
                        sp_resolved = (_resolve_report_file_path(sp) or sp) if sp else None
                        # Сертификат включаем даже без скана — номер/срок действия
                        # нужны для таблицы специалистов и подписей протоколов.
                        items.append(
                            {
                                "certification_type": getattr(c, "certification_type", None),
                                "certificate_number": getattr(c, "certificate_number", None),
                                "method_code": getattr(c, "method_code", None),
                                "issuing_organization": getattr(c, "issuing_organization", None),
                                "issue_date": str(getattr(c, "issue_date", None)) if getattr(c, "issue_date", None) else None,
                                "expiry_date": str(getattr(c, "expiry_date", None)) if getattr(c, "expiry_date", None) else None,
                                "scan_file_path": sp_resolved,
                                "scan_file_name": getattr(c, "scan_file_name", None),
                                "scan_mime_type": getattr(c, "scan_mime_type", None),
                            }
                        )
                    if items:
                        specialist_docs.append({"inspector_name": name, "certifications": items})
            except Exception:
                specialist_docs = []

            # Подготавливаем данные для отчета и добавляем информацию об ОПО (если есть)
            inspection_payload = {
                "id": inspection_scope,
                "questionnaire_id": (
                    str(inspection.questionnaire_id)
                    if getattr(inspection, "questionnaire_id", None)
                    else questionnaire_scope
                ),
                "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                "data": inspection.data,
                "conclusion": inspection.conclusion,
                "status": inspection.status,
            }
            # Форма ТО: из данных обследования → из задания → автоподбор по типу оборудования
            try:
                dp0 = inspection_payload.get("data")
                if not isinstance(dp0, dict):
                    dp0 = {}
                else:
                    dp0 = dict(dp0)
                form_id = (dp0.get("report_form_id") or "").strip()
                if not form_id and getattr(inspection, "assignment_id", None):
                    a_res = await db.execute(
                        select(Assignment).where(Assignment.id == inspection.assignment_id)
                    )
                    asn = a_res.scalar_one_or_none()
                    if asn and getattr(asn, "report_form_id", None):
                        form_id = str(asn.report_form_id).strip()
                if not form_id:
                    form_id = suggest_form_id(
                        equipment_type_code=equipment_type_code,
                        equipment_name=equipment.name,
                        equipment_type_name=equipment_type_name,
                    )
                if form_id:
                    dp0["report_form_id"] = form_id
                    meta = get_form(form_id)
                    if meta and meta.get("title"):
                        dp0.setdefault("report_form_title", meta["title"])
                    inspection_payload["data"] = dp0
                    inspection_payload["report_form_id"] = form_id
            except Exception as e:
                print(f"Warning: could not resolve report_form_id: {e}")

            # Подмешать договор/сроки/техкарту (и файл схемы/техкарты) из задания,
            # если в inspection.data они не заполнены. Работает независимо от того,
            # удалось ли выше определить report_form_id.
            try:
                asn = None
                if getattr(inspection, "assignment_id", None):
                    a_res = await db.execute(
                        select(Assignment).where(Assignment.id == inspection.assignment_id)
                    )
                    asn = a_res.scalar_one_or_none()
                if asn is not None:
                    dp0 = inspection_payload.get("data")
                    if not isinstance(dp0, dict):
                        dp0 = {}
                        inspection_payload["data"] = dp0
                    for _k in (
                        "contract_number",
                        "contract_date",
                        "work_period_from",
                        "work_period_to",
                        "work_basis",
                        "tech_card_number",
                        "tech_card_file_name",
                    ):
                        if not dp0.get(_k):
                            _av = getattr(asn, _k, None)
                            if _av:
                                dp0[_k] = str(_av)
                    if not dp0.get("tech_card_file_available"):
                        dp0["tech_card_file_available"] = bool(getattr(asn, "tech_card_file_path", None))
                    # Путь файла техкарты/схемы — для вставки в отчёт как схема контроля
                    tcp = getattr(asn, "tech_card_file_path", None)
                    if tcp and not dp0.get("tech_card_file_path"):
                        resolved = _resolve_report_file_path(tcp) or tcp
                        dp0["tech_card_file_path"] = resolved
                        if isinstance(document_files, list):
                            document_files.append(
                                {
                                    "document_number": "tech_card_file_path",
                                    "file_path": resolved,
                                    "file_name": getattr(asn, "tech_card_file_name", None)
                                    or "tech_card",
                                }
                            )
            except Exception as _e:
                print(f"Warning: merge assignment contract fields: {_e}")

            # Подставляем пути из загруженных document_files в data (фото таблички, схема, фото дефектов ВИК)
            try:
                dp = inspection_payload.get("data")
                if isinstance(dp, dict) and document_files:
                    dp = dict(dp)
                    for f in document_files:
                        dn = f.get("document_number")
                        fp = f.get("file_path")
                        if not dn or not fp:
                            continue
                        if dn in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
                            dp[dn] = fp
                        elif isinstance(dn, str) and dn.startswith("uzt_point_"):
                            parts = dn.split("_")
                            if len(parts) >= 4 and parts[0] == "uzt" and parts[1] == "point":
                                try:
                                    i, j = int(parts[2]), int(parts[3])
                                    tm = dp.get("thickness_measurements") or dp.get("thicknessMeasurements")
                                    if isinstance(tm, list) and 0 <= i < len(tm):
                                        t = tm[i]
                                        if isinstance(t, dict):
                                            t = dict(t)
                                            ph = list(t.get("photos") or [])
                                            while len(ph) <= j:
                                                ph.append("")
                                            ph[j] = fp
                                            t["photos"] = ph
                                            tm = list(tm)
                                            tm[i] = t
                                            dp["thickness_measurements"] = tm
                                except (ValueError, IndexError):
                                    pass
                        elif isinstance(dn, str) and dn.startswith("vd_"):
                            parts = dn.split("_")
                            if len(parts) == 3 and parts[0] == "vd":
                                try:
                                    i, j = int(parts[1]), int(parts[2])
                                    vd = dp.get("visual_defects")
                                    if isinstance(vd, list) and 0 <= i < len(vd):
                                        d = vd[i]
                                        if isinstance(d, dict):
                                            d = dict(d)
                                            ph = list(d.get("photos") or [])
                                            while len(ph) <= j:
                                                ph.append("")
                                            ph[j] = fp
                                            d["photos"] = ph
                                            vd = list(vd)
                                            vd[i] = d
                                            dp["visual_defects"] = vd
                                except (ValueError, IndexError):
                                    pass
                    inspection_payload["data"] = dp
            except Exception:
                pass
            # Разрешаем пути к фото таблички, схемы и фото дефектов в data (для вставки в отчёт)
            try:
                dp = inspection_payload.get("data")
                if isinstance(dp, dict):
                    dp = dict(dp)
                    for key in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
                        if dp.get(key) and isinstance(dp[key], str):
                            dp[key] = _inspect_attachment_path(dp[key]) or dp[key]
                    # Фото дефектов ВИК (синхронизация с мобильного)
                    vd = dp.get("visual_defects")
                    if isinstance(vd, list):
                        vd = list(vd)
                        for i, d in enumerate(vd):
                            if isinstance(d, dict):
                                d = dict(d)
                                ph = d.get("photos") or []
                                if isinstance(ph, list):
                                    d["photos"] = [_inspect_attachment_path(p) or p for p in ph if isinstance(p, str)]
                                vd[i] = d
                        dp["visual_defects"] = vd
                    # Фото замеров УЗТ
                    tm = dp.get("thickness_measurements") or dp.get("thicknessMeasurements")
                    if isinstance(tm, list):
                        tm = list(tm)
                        for i, t in enumerate(tm):
                            if isinstance(t, dict):
                                t = dict(t)
                                ph = t.get("photos") or []
                                if isinstance(ph, list):
                                    t["photos"] = [_inspect_attachment_path(p) or p for p in ph if isinstance(p, str)]
                                tm[i] = t
                        dp["thickness_measurements"] = tm
                    inspection_payload["data"] = dp
            except Exception:
                pass
            try:
                data_payload = inspection_payload.get("data")
                if isinstance(data_payload, dict) and opo_info:
                    data_payload = dict(data_payload)
                    survey = opo_info.get("survey_data") if isinstance(opo_info.get("survey_data"), dict) else {}
                    if isinstance(survey, dict):
                        docs_current = data_payload.get("documents") or {}
                        if isinstance(docs_current, dict) and isinstance(survey.get("documents"), dict):
                            merged_docs = dict(docs_current)
                            for k, v in survey.get("documents").items():
                                try:
                                    n = int(str(k))
                                except Exception:
                                    continue
                                if 1 <= n <= 9 and not merged_docs.get(str(k)):
                                    merged_docs[str(k)] = v
                            data_payload["documents"] = merged_docs
                        if not data_payload.get("organization") and survey.get("organization"):
                            data_payload["organization"] = survey.get("organization")
                        if not data_payload.get("executors") and survey.get("executors"):
                            data_payload["executors"] = survey.get("executors")
                        data_payload.setdefault("opo_survey", survey)

                    data_payload.setdefault("opo", opo_info)
                    if opo_info.get("id"):
                        data_payload.setdefault("opo_id", opo_info["id"])
                    # ОПО-поля: всегда подтягиваем из карточки ОПО, если в обследовании пусто
                    def _blank(v):
                        return v in (None, "", "—", "-", "–")

                    if opo_info.get("name") and _blank(data_payload.get("opo_name")):
                        data_payload["opo_name"] = opo_info["name"]
                    if opo_info.get("code") and _blank(data_payload.get("opo_code")):
                        data_payload["opo_code"] = opo_info["code"]
                    if opo_info.get("hazard_class") and _blank(data_payload.get("opo_hazard_class")):
                        data_payload["opo_hazard_class"] = opo_info["hazard_class"]
                    if opo_info.get("registration_number") and _blank(data_payload.get("opo_reg_number")):
                        data_payload["opo_reg_number"] = opo_info["registration_number"]
                    if opo_info.get("description") and _blank(data_payload.get("opo_description")):
                        data_payload["opo_description"] = opo_info["description"]
                    if opo_info.get("enterprise_name") and _blank(data_payload.get("opo_enterprise")):
                        data_payload["opo_enterprise"] = opo_info["enterprise_name"]
                    if opo_info.get("branch_name") and _blank(data_payload.get("opo_branch")):
                        data_payload["opo_branch"] = opo_info["branch_name"]
                    if opo_info.get("workshop_name") and _blank(data_payload.get("opo_workshop")):
                        data_payload["opo_workshop"] = opo_info["workshop_name"]

                    inspection_payload["data"] = data_payload
            except Exception as e:
                print(f"Warning: Could not merge OPO data into report payload: {e}")

            _report_gen_t0 = time.time()
            client_data, enterprise_name = await _resolve_client_context(db, equipment)
            org_settings = merge_client_into_settings(
                load_report_org_settings(),
                client=client_data,
                enterprise_name=enterprise_name,
            )
            if is_docx:
                # Генерация Word документа во временный файл, затем перемещение (восстановление после сбоя)
                import tempfile as _tf
                _fd, _tmp_path = _tf.mkstemp(suffix=".docx", prefix="report_", dir=str(reports_dir))
                try:
                    os.close(_fd)
                    word_generator.generate_report_word(
                        inspection_payload,
                        {
                            "id": str(equipment.id),
                            "name": equipment.name,
                            "serial_number": equipment.serial_number,
                            "location": equipment.location,
                            "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                            "attributes": equipment.attributes or {},
                            "type_code": equipment_type_code,
                            "type_name": equipment_type_name,
                        },
                        ndt_methods_data,
                        _tmp_path,
                        report_type,
                        document_files=document_files,
                        specialist_docs=specialist_docs,
                        verification_equipment=verification_equipment_list,
                        template_definition=template_definition,
                        org_settings=org_settings,
                    )
                    os.replace(_tmp_path, str(file_path))
                except Exception:
                    if os.path.exists(_tmp_path):
                        try:
                            os.unlink(_tmp_path)
                        except OSError:
                            pass
                    raise
            else:
                # PDF: сначала официальная Word-форма → LibreOffice PDF; иначе ReportLab
                from docx_to_pdf import convert_docx_to_pdf, libreoffice_available

                used_official_pdf = False
                if report_type not in ("EXPERTISE", "EPB", "ЭПБ") and libreoffice_available():
                    import tempfile as _tf
                    _fd, _tmp_docx = _tf.mkstemp(suffix=".docx", prefix="report_", dir=str(reports_dir))
                    try:
                        os.close(_fd)
                        from word_generator import WordGenerator
                        _wg = WordGenerator()
                        _wg.generate_report_word(
                            inspection_payload,
                            {
                                "id": str(equipment.id),
                                "name": equipment.name,
                                "serial_number": equipment.serial_number,
                                "location": equipment.location,
                                "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                                "attributes": equipment.attributes or {},
                                "type_code": equipment_type_code,
                                "type_name": equipment_type_name,
                            },
                            ndt_methods_data,
                            _tmp_docx,
                            report_type,
                            document_files=document_files,
                            specialist_docs=specialist_docs,
                            verification_equipment=verification_equipment_list,
                            template_definition=template_definition,
                            org_settings=org_settings,
                        )
                        pdf_ok = convert_docx_to_pdf(_tmp_docx, str(file_path))
                        if pdf_ok:
                            used_official_pdf = True
                            # Сохраняем также docx рядом
                            try:
                                docx_side = Path(str(file_path)).with_suffix(".docx")
                                os.replace(_tmp_docx, str(docx_side))
                                # word_file_path проставим ниже при создании Report
                                inspection_payload["_generated_docx_path"] = str(docx_side)
                            except Exception:
                                if os.path.exists(_tmp_docx):
                                    os.unlink(_tmp_docx)
                        else:
                            if os.path.exists(_tmp_docx):
                                os.unlink(_tmp_docx)
                    except Exception as _pdf_exc:
                        print(f"Warning: official form PDF failed, fallback ReportLab: {_pdf_exc}")
                        if os.path.exists(_tmp_docx):
                            try:
                                os.unlink(_tmp_docx)
                            except OSError:
                                pass

                if not used_official_pdf:
                    if report_type == "EXPERTISE":
                        generator.generate_expertise_report(
                            inspection_payload,
                            {
                                "id": str(equipment.id),
                                "name": equipment.name,
                                "serial_number": equipment.serial_number,
                                "location": equipment.location,
                                "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                                "attributes": equipment.attributes or {},
                            },
                            resource_data,
                            str(file_path),
                            ndt_methods_data,
                            document_files=document_files,
                            specialist_docs=specialist_docs,
                            verification_equipment=verification_equipment_list,
                        )
                    else:
                        generator.generate_technical_report(
                            inspection_payload,
                            {
                                "id": str(equipment.id),
                                "name": equipment.name,
                                "serial_number": equipment.serial_number,
                                "location": equipment.location,
                                "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                                "attributes": equipment.attributes or {},
                            },
                            str(file_path),
                            ndt_methods_data,
                            document_files=document_files,
                            specialist_docs=specialist_docs,
                            verification_equipment=verification_equipment_list,
                        )
            _metrics["report_generation_seconds_sum"] = _metrics.get("report_generation_seconds_sum", 0) + (time.time() - _report_gen_t0)
            _metrics["report_generation_count"] = _metrics.get("report_generation_count", 0) + 1
            
            # Генерируем номера отчета
            from report_utils import generate_report_number, generate_registration_number
            report_number = await generate_report_number(db, report_type)
            registration_number = await generate_registration_number(db)
            
            # Save report record
            new_report = Report(
                inspection_id=inspection_id,
                report_type=report_type,
                report_number=report_number,
                registration_number=registration_number,
                file_path=str(file_path),
                file_size=file_path.stat().st_size if file_path.exists() else 0,
                created_by=current_user.id,
                is_archived=False  # Явно устанавливаем значение
            )
            # Для DOCX также заполняем word_* поля (для единообразия и будущего расширения)
            if is_docx:
                new_report.word_file_path = str(file_path)
                new_report.word_file_size = new_report.file_size
            elif inspection_payload.get("_generated_docx_path"):
                docx_side = Path(str(inspection_payload["_generated_docx_path"]))
                if docx_side.exists():
                    new_report.word_file_path = str(docx_side)
                    new_report.word_file_size = docx_side.stat().st_size
            db.add(new_report)
            await db.commit()
            await db.refresh(new_report)
            
            return {
                "id": str(new_report.id),
                "report_number": new_report.report_number,
                "registration_number": new_report.registration_number,
                "file_path": str(file_path),
                "file_size": new_report.file_size,
                "format": "docx" if is_docx else "pdf",
                "status": "generated"
            }
        else:
            raise HTTPException(status_code=400, detail="inspection_id is required")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate report: {str(e)}")


@router.post("/api/reports/bulk-export", tags=["reports"])
async def bulk_export_reports(
    body: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Пакетная выгрузка отчётов: по списку inspection_ids генерируются DOCX и возвращаются в ZIP (макс. 15 шт)."""
    import tempfile
    inspection_ids = body.get("inspection_ids") or []
    if not isinstance(inspection_ids, list):
        raise HTTPException(status_code=400, detail="inspection_ids должен быть массивом")
    inspection_ids = [str(x).strip() for x in inspection_ids if x][:15]
    report_type = (body.get("report_type") or "TECHNICAL_REPORT").strip().upper()
    if not inspection_ids:
        raise HTTPException(status_code=400, detail="Укажите хотя бы один inspection_id")

    user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
    current_user = user_result.scalar_one_or_none()
    if not current_user:
        raise HTTPException(status_code=404, detail="User not found")

    from word_generator import WordGenerator
    word_generator = WordGenerator()
    temp_dir = tempfile.mkdtemp(prefix="bulk_report_")
    generated = []
    try:
        for insp_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(insp_id)
            except (ValueError, TypeError):
                continue
            insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
            inspection = insp_result.scalar_one_or_none()
            if not inspection:
                continue
            if current_user.role == "engineer" and getattr(inspection, "inspector_id", None) != current_user.id and getattr(inspection, "performed_by", None) != current_user.id:
                continue
            eq_result = await db.execute(select(Equipment).where(Equipment.id == inspection.equipment_id))
            equipment = eq_result.scalar_one_or_none()
            if not equipment:
                continue
            inspection_payload_bulk = {
                "id": str(inspection.id),
                "questionnaire_id": (
                    str(inspection.questionnaire_id)
                    if getattr(inspection, "questionnaire_id", None)
                    else None
                ),
                "status": getattr(inspection, "status", "DRAFT"),
                "conclusion": getattr(inspection, "conclusion", None),
                "date_performed": inspection.date_performed.isoformat() if getattr(inspection, "date_performed", None) else None,
                "data": inspection.data if isinstance(getattr(inspection, "data", None), dict) else {},
            }
            equipment_data = {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": getattr(equipment, "serial_number", None),
                "location": getattr(equipment, "location", None),
                "commissioning_date": str(equipment.commissioning_date) if getattr(equipment, "commissioning_date", None) else None,
                "attributes": equipment.attributes or {},
                "type_code": None,
                "type_name": None,
            }
            if equipment.type_id:
                t_res = await db.execute(select(EquipmentType).where(EquipmentType.id == equipment.type_id))
                t = t_res.scalar_one_or_none()
                if t:
                    equipment_data["type_code"] = t.code
                    equipment_data["type_name"] = t.name
            ndt_res = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
            ndt_list = ndt_res.scalars().all()

            q_for_files_b = None
            if getattr(inspection, "questionnaire_id", None):
                q_res = await db.execute(select(Questionnaire).where(Questionnaire.id == inspection.questionnaire_id))
                q_for_files_b = q_res.scalar_one_or_none()
            if not q_for_files_b and getattr(inspection, "assignment_id", None):
                q_res2 = await db.execute(
                    select(Questionnaire)
                    .where(Questionnaire.assignment_id == inspection.assignment_id)
                    .order_by(Questionnaire.created_at.desc())
                    .limit(1)
                )
                q_for_files_b = q_res2.scalar_one_or_none()
            q_bulk_scope = str(q_for_files_b.id) if q_for_files_b else None
            inspection_scope_b = str(inspection.id)
            if q_bulk_scope and not inspection_payload_bulk.get("questionnaire_id"):
                inspection_payload_bulk["questionnaire_id"] = q_bulk_scope

            def _bulk_attachment_path(local_path: Optional[str]) -> Optional[str]:
                if not local_path or not isinstance(local_path, str):
                    return local_path
                return resolve_report_file_path(
                    local_path,
                    inspection_id=inspection_scope_b,
                    questionnaire_id=q_bulk_scope,
                ) or local_path

            ndt_methods_data = []
            for m in ndt_list:
                _ph = getattr(m, "photos", None) or []
                if isinstance(_ph, list):
                    _ph_res = [
                        resolve_report_file_path(
                            ph,
                            inspection_id=inspection_scope_b,
                            questionnaire_id=q_bulk_scope,
                        )
                        or ph
                        for ph in _ph
                        if isinstance(ph, str)
                    ]
                else:
                    _ph_res = _ph
                ndt_methods_data.append({
                    "method_code": getattr(m, "method_code", None),
                    "method_name": getattr(m, "method_name", None),
                    "is_performed": bool(getattr(m, "is_performed", False)),
                    "standard": getattr(m, "standard", None),
                    "equipment": getattr(m, "equipment", None),
                    "inspector_name": getattr(m, "inspector_name", None),
                    "inspector_level": getattr(m, "inspector_level", None),
                    "results": getattr(m, "results", None),
                    "defects": getattr(m, "defects", None),
                    "conclusion": getattr(m, "conclusion", None),
                    "photos": _ph_res,
                    "additional_data": getattr(m, "additional_data", None) or {},
                    "performed_date": m.performed_date.isoformat() if getattr(m, "performed_date", None) else None,
                })
            document_files = []
            if q_for_files_b:
                f_res = await db.execute(
                    select(QuestionnaireDocumentFile).where(
                        QuestionnaireDocumentFile.questionnaire_id == q_for_files_b.id
                    )
                )
                for f in f_res.scalars().all():
                    document_files.append({
                        "document_number": f.document_number,
                        "file_name": f.file_name,
                        "file_path": _bulk_attachment_path(f.file_path) or f.file_path,
                        "file_size": int(f.file_size or 0),
                    })
            out_path = os.path.join(temp_dir, f"report_{insp_id}.docx")
            try:
                word_generator.generate_report_word(
                    inspection_payload_bulk,
                    equipment_data,
                    ndt_methods_data,
                    out_path,
                    report_type,
                    document_files=document_files,
                    specialist_docs=[],
                    verification_equipment=[],
                    template_definition=None,
                    org_settings=load_report_org_settings(),
                )
                generated.append((insp_id, out_path))
            except Exception as e:
                print(f"Bulk export: skip inspection {insp_id}: {e}")
        if not generated:
            raise HTTPException(status_code=400, detail="Не удалось сгенерировать ни одного отчёта")
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for _id, p in generated:
                zf.write(p, os.path.basename(p))
        buf.seek(0)
        return StreamingResponse(
            buf,
            media_type="application/zip",
            headers={"Content-Disposition": "attachment; filename=reports.zip"},
        )
    finally:
        try:
            for _id, p in generated:
                if os.path.exists(p):
                    os.unlink(p)
            if os.path.exists(temp_dir):
                os.rmdir(temp_dir)
        except OSError:
            pass


# Report Templates endpoints (работа с БД)
@router.get("/api/report-templates-db")
async def get_report_templates_db(
    client_id: Optional[str] = None,
    template_type: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список шаблонов отчетов из БД"""
    try:
        from models import ReportTemplate
        current_user = await _load_user_by_login(db, username)
        _ensure_template_permissions(current_user)
        query = select(ReportTemplate).where(ReportTemplate.is_active == True)
        
        if client_id:
            try:
                client_uuid = uuid_lib.UUID(client_id)
                query = query.where(ReportTemplate.client_id == client_uuid)
            except:
                pass
        
        if template_type:
            query = query.where(ReportTemplate.template_type == template_type)
        
        result = await db.execute(query)
        templates = result.scalars().all()
        
        items = []
        for t in templates:
            items.append({
                "id": str(t.id),
                "name": t.name,
                "description": t.description,
                "template_type": t.template_type,
                "client_id": str(t.client_id) if t.client_id else None,
                "template_config": t.template_config,
                "is_default": t.is_default,
                "is_active": t.is_active,
            })
        
        return {"items": items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/report-templates-db")
async def create_report_template_db(
    template_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать шаблон отчета в БД"""
    try:
        from models import ReportTemplate
        current_user = await _load_user_by_login(db, username)
        _ensure_template_permissions(current_user)
        
        client_id = None
        if template_data.get("client_id"):
            try:
                client_id = uuid_lib.UUID(template_data.get("client_id"))
            except:
                pass
        
        if template_data.get("is_default"):
            existing_defaults = await db.execute(
                select(ReportTemplate).where(
                    ReportTemplate.template_type == template_data.get("template_type"),
                    ReportTemplate.is_default == True
                )
            )
            for t in existing_defaults.scalars().all():
                t.is_default = False
        
        template = ReportTemplate(
            name=template_data.get("name"),
            description=template_data.get("description"),
            template_type=template_data.get("template_type", "TECHNICAL"),
            client_id=client_id,
            template_config=template_data.get("template_config", {}),
            is_default=template_data.get("is_default", False),
            created_by=current_user.id if current_user else None,
        )
        
        db.add(template)
        await db.commit()
        await db.refresh(template)
        
        return {"id": str(template.id), "name": template.name, "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/api/report-templates-db/{template_id}")
async def update_report_template_db(
    template_id: str,
    template_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Обновить шаблон отчета в БД"""
    try:
        from models import ReportTemplate
        current_user = await _load_user_by_login(db, username)
        _ensure_template_permissions(current_user)
        template_uuid = uuid_lib.UUID(template_id)
        result = await db.execute(
            select(ReportTemplate).where(ReportTemplate.id == template_uuid)
        )
        template = result.scalar_one_or_none()
        
        if not template:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        
        if "name" in template_data:
            template.name = template_data["name"]
        if "description" in template_data:
            template.description = template_data["description"]
        if "template_type" in template_data:
            template.template_type = template_data["template_type"]
        if "template_config" in template_data:
            template.template_config = template_data["template_config"]
        if "client_id" in template_data:
            if template_data["client_id"]:
                try:
                    template.client_id = uuid_lib.UUID(template_data["client_id"])
                except:
                    template.client_id = None
            else:
                template.client_id = None
        
        if "is_default" in template_data:
            if template_data["is_default"]:
                existing_defaults = await db.execute(
                    select(ReportTemplate).where(
                        ReportTemplate.template_type == template.template_type,
                        ReportTemplate.is_default == True,
                        ReportTemplate.id != template_uuid
                    )
                )
                for t in existing_defaults.scalars().all():
                    t.is_default = False
            template.is_default = template_data["is_default"]
        
        await db.commit()
        await db.refresh(template)
        
        return {"id": str(template.id), "name": template.name, "status": "updated"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/api/report-templates-db/{template_id}")
async def delete_report_template_db(
    template_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить шаблон отчета из БД"""
    try:
        from models import ReportTemplate
        current_user = await _load_user_by_login(db, username)
        _ensure_template_permissions(current_user)
        template_uuid = uuid_lib.UUID(template_id)
        result = await db.execute(
            select(ReportTemplate).where(ReportTemplate.id == template_uuid)
        )
        template = result.scalar_one_or_none()
        
        if not template:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        
        template.is_active = 0
        await db.commit()
        
        return {"status": "deleted"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/reports/{report_id}/sign")
async def sign_report(
    report_id: str,
    signature_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Подписать отчет электронной подписью"""
    try:
        from datetime import timezone
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")
        
        report_uuid = uuid_lib.UUID(report_id)
        result = await db.execute(
            select(Report).where(Report.id == report_uuid)
        )
        report = result.scalar_one_or_none()
        
        if not report:
            raise HTTPException(status_code=404, detail="Отчет не найден")
        
        report.is_signed = True
        report.signed_at = datetime.now(timezone.utc)
        report.signed_by = current_user.id
        
        await db.commit()
        await db.refresh(report)
        
        return {
            "id": str(report.id),
            "is_signed": report.is_signed,
            "signed_at": str(report.signed_at),
            "status": "signed"
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/api/reports/{report_id}")
async def delete_report(
    report_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удаление отчета (admin/operator — любой, engineer — только свой)"""
    try:
        report_uuid = uuid_lib.UUID(report_id)

        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
        report = rep_result.scalar_one_or_none()
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")

        # Проверка прав
        if current_user.role in ["admin", "chief_operator", "operator"]:
            allowed = True
        elif current_user.role == "engineer":
            allowed = False
            if report.created_by and report.created_by == current_user.id:
                allowed = True
            elif report.created_by is None and report.inspection_id:
                insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                insp = insp_result.scalar_one_or_none()
                if insp and insp.inspector_id == current_user.id:
                    allowed = True
        else:
            allowed = False

        if not allowed:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Удаляем файлы
        for p in [report.file_path, getattr(report, "word_file_path", None)]:
            if p:
                try:
                    fp = Path(p)
                    if fp.exists():
                        fp.unlink()
                except Exception:
                    pass

        await db.delete(report)
        await db.commit()
        return {"status": "deleted", "id": report_id}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid report_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete report: {str(e)}")


@router.post("/api/reports/bulk-delete")
async def bulk_delete_reports(
    request: BulkDeleteReportsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое удаление отчетов"""
    try:
        report_ids = request.report_ids
        if not report_ids:
            raise HTTPException(status_code=400, detail="No report IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        deleted_count = 0
        for report_id in report_ids:
            try:
                report_uuid = uuid_lib.UUID(report_id)
                rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
                report = rep_result.scalar_one_or_none()
                
                if not report:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if report.created_by and report.created_by == user.id:
                        allowed = True
                    elif report.created_by is None and report.inspection_id:
                        insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                        insp = insp_result.scalar_one_or_none()
                        if insp and insp.inspector_id == user.id:
                            allowed = True
                
                if not allowed:
                    continue
                
                # Удаляем файлы
                for p in [report.file_path, getattr(report, "word_file_path", None)]:
                    if p:
                        try:
                            fp = Path(p)
                            if fp.exists():
                                fp.unlink()
                        except Exception:
                            pass
                
                await db.delete(report)
                deleted_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"deleted": deleted_count, "total": len(report_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete reports: {str(e)}")


@router.post("/api/reports/bulk-archive")
async def bulk_archive_reports(
    request: BulkArchiveReportsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое архивирование/разархивирование отчетов"""
    try:
        report_ids = request.report_ids
        archive = request.archive
        if not report_ids:
            raise HTTPException(status_code=400, detail="No report IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        archived_count = 0
        for report_id in report_ids:
            try:
                report_uuid = uuid_lib.UUID(report_id)
                rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
                report = rep_result.scalar_one_or_none()
                
                if not report:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if report.created_by and report.created_by == user.id:
                        allowed = True
                    elif report.created_by is None and report.inspection_id:
                        insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                        insp = insp_result.scalar_one_or_none()
                        if insp and insp.inspector_id == user.id:
                            allowed = True
                
                if not allowed:
                    continue
                
                report.is_archived = archive
                archived_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"archived": archived_count, "total": len(report_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to archive reports: {str(e)}")


@router.delete("/api/reports/cleanup")
async def cleanup_reports(
    older_than_days: int = 90,
    before: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Массовое удаление старых отчетов.
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои
    Параметры:
      - older_than_days: удалить старше N дней (по created_at)
      - before: ISO дата/время (например 2025-12-01 или 2025-12-01T00:00:00)
    """
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        cutoff = None
        if before:
            try:
                cutoff = datetime.fromisoformat(before.replace("Z", "+00:00"))
            except Exception:
                # fallback для формата YYYY-MM-DD
                try:
                    cutoff = datetime.strptime(before, "%Y-%m-%d")
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid 'before' format")
        else:
            if older_than_days < 1:
                raise HTTPException(status_code=400, detail="older_than_days must be >= 1")
            cutoff = datetime.now() - timedelta(days=int(older_than_days))

        query = select(Report).where(Report.created_at < cutoff)

        # Ограничение инженера только своими отчетами (как в get_reports)
        if current_user.role == "engineer":
            query = (
                query.join(Inspection, Report.inspection_id == Inspection.id, isouter=True)
                .where(
                    or_(
                        Report.created_by == current_user.id,
                        and_(Report.created_by.is_(None), Inspection.inspector_id == current_user.id),
                    )
                )
            )
        elif current_user.role not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        result = await db.execute(query)
        reports = result.scalars().all()

        deleted = 0
        for report in reports:
            # удаляем файлы
            for p in [report.file_path, getattr(report, "word_file_path", None)]:
                if p:
                    try:
                        fp = Path(p)
                        if fp.exists():
                            fp.unlink()
                    except Exception:
                        pass
            await db.delete(report)
            deleted += 1

        await db.commit()
        return {"status": "ok", "deleted": deleted, "cutoff": cutoff.isoformat()}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to cleanup reports: {str(e)}")


@router.get("/api/reports/{report_id}/download")
async def download_report(
    report_id: str,
    format: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Download report file (PDF/DOCX)"""
    try:
        # Текущий пользователь и права
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        result = await db.execute(
            select(Report).where(Report.id == uuid_lib.UUID(report_id))
        )
        report = result.scalar_one_or_none()
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")

        # Инженер может скачивать только свои отчеты
        if current_user.role == "engineer":
            allowed = False
            if report.created_by and report.created_by == current_user.id:
                allowed = True
            elif report.created_by is None and report.inspection_id:
                insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                insp = insp_result.scalar_one_or_none()
                if insp and insp.inspector_id == current_user.id:
                    allowed = True
            if not allowed:
                raise HTTPException(status_code=403, detail="Доступ запрещен")
        elif current_user.role == "client":
            if not report.inspection_id:
                raise HTTPException(status_code=403, detail="Доступ запрещен")
            insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
            insp = insp_result.scalar_one_or_none()
            if not insp or not insp.equipment_id:
                raise HTTPException(status_code=403, detail="Доступ запрещен")
            if not await client_user_can_access_equipment(db, current_user, insp.equipment_id):
                raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Выбор файла по формату (если указан), иначе по расширению/наличию
        fmt = (format or "").strip().lower()
        selected_path = None
        if fmt in ["docx", "doc", "word"]:
            if report.word_file_path and os.path.exists(report.word_file_path):
                selected_path = report.word_file_path
            elif report.file_path and str(report.file_path).lower().endswith(".docx") and os.path.exists(report.file_path):
                selected_path = report.file_path
        elif fmt in ["pdf"]:
            if report.file_path and str(report.file_path).lower().endswith(".pdf") and os.path.exists(report.file_path):
                selected_path = report.file_path

        if not selected_path:
            # auto
            if report.file_path and os.path.exists(report.file_path):
                selected_path = report.file_path
            elif report.word_file_path and os.path.exists(report.word_file_path):
                selected_path = report.word_file_path

        if not selected_path or not os.path.exists(selected_path):
            raise HTTPException(status_code=404, detail="Report file not found")

        filename = os.path.basename(selected_path)
        lower = filename.lower()
        if lower.endswith(".docx"):
            media_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        else:
            media_type = "application/pdf"

        return FileResponse(
            selected_path,
            media_type=media_type,
            filename=filename
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid report_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
