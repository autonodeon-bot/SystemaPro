"""Роутер API для опросных листов (questionnaires), методов НК (NDT) и документов."""

import os
import re
import uuid as uuid_lib
import traceback
import logging
from datetime import datetime
from typing import Optional
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from fastapi.responses import FileResponse
from sqlalchemy import select, delete, func, or_
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from auth import verify_token
from models import (
    Questionnaire,
    NDTMethod,
    Inspection,
    Equipment,
    User,
    QuestionnaireDocumentFile,
    Assignment,
)
from report_generator import ReportGenerator
from shared import (
    normalize_image_content_type,
    read_upload_with_limit,
    resolve_report_file_path,
    ALLOWED_IMAGE_MIME_TYPES,
    MAX_NDT_UPLOAD_SIZE_BYTES,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["questionnaires"])


def _parse_questionnaire_dt(val) -> Optional[datetime]:
    if val is None or val == "":
        return None
    try:
        return datetime.fromisoformat(str(val).replace("Z", "+00:00"))
    except Exception:
        return None


async def _questionnaire_editor_user(db: AsyncSession, username: str) -> User:
    """Пользователь с правом создавать/редактировать опросные листы (мобильное/web)."""
    result = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if user.role not in ("admin", "chief_operator", "operator", "engineer"):
        raise HTTPException(status_code=403, detail="Недостаточно прав для опросного листа")
    return user


# ========== Опросные листы ==========


@router.get("/api/questionnaires")
async def get_questionnaires(
    equipment_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Получить список опросных листов"""
    try:
        query = select(Questionnaire)
        
        if equipment_id:
            try:
                equipment_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(Questionnaire.equipment_id == equipment_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        query = query.order_by(Questionnaire.created_at.desc()).offset(skip).limit(limit)
        
        result = await db.execute(query)
        questionnaires = result.scalars().all()
        
        items = []
        for q in questionnaires:
            insp_date = getattr(q, "inspection_date", None) or getattr(q, "date_performed", None)
            items.append({
                "id": str(q.id),
                "equipment_id": str(q.equipment_id),
                "equipment_inventory_number": getattr(q, "equipment_inventory_number", None),
                "equipment_name": getattr(q, "equipment_name", None),
                "inspection_date": insp_date.isoformat() if insp_date else None,
                "inspector_name": getattr(q, "inspector_name", None),
                "inspector_position": getattr(q, "inspector_position", None),
                "file_path": getattr(q, "file_path", None),
                "file_size": getattr(q, "file_size", None) or 0,
                "word_file_path": getattr(q, "word_file_path", None),
                "word_file_size": getattr(q, "word_file_size", None) or 0,
                "created_by": str(q.created_by) if getattr(q, "created_by", None) else None,
                "created_at": q.created_at.isoformat() if q.created_at else None,
            })
        return {"items": items, "total": len(questionnaires)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/questionnaires/{questionnaire_id}")
async def get_questionnaire(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Получить опросный лист по ID"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        insp_date = getattr(questionnaire, "inspection_date", None) or getattr(questionnaire, "date_performed", None)
        return {
            "id": str(questionnaire.id),
            "equipment_id": str(questionnaire.equipment_id),
            "equipment_inventory_number": getattr(questionnaire, "equipment_inventory_number", None),
            "equipment_name": getattr(questionnaire, "equipment_name", None),
            "inspection_date": insp_date.isoformat() if insp_date else None,
            "inspector_name": getattr(questionnaire, "inspector_name", None),
            "inspector_position": getattr(questionnaire, "inspector_position", None),
            "questionnaire_data": getattr(questionnaire, "questionnaire_data", None) or getattr(questionnaire, "data", None),
            "file_path": getattr(questionnaire, "file_path", None),
            "file_size": getattr(questionnaire, "file_size", None) or 0,
            "word_file_path": getattr(questionnaire, "word_file_path", None),
            "word_file_size": getattr(questionnaire, "word_file_size", None) or 0,
            "created_by": str(questionnaire.created_by) if getattr(questionnaire, "created_by", None) else None,
            "created_at": questionnaire.created_at.isoformat() if questionnaire.created_at else None,
            "updated_at": questionnaire.updated_at.isoformat() if questionnaire.updated_at else None,
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
                    "performed_date": m.performed_date.isoformat() if m.performed_date else None,
                }
                for m in ndt_methods
            ]
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/questionnaires")
async def create_questionnaire(
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Создать опросный лист (структура JSON в поле data — как у мобильного клиента)."""
    try:
        user = await _questionnaire_editor_user(db, username)
        equipment_id_raw = payload.get("equipment_id")
        data = payload.get("data")
        if not equipment_id_raw:
            raise HTTPException(status_code=400, detail="Поле equipment_id обязательно")
        if data is None or not isinstance(data, dict):
            raise HTTPException(status_code=400, detail="Поле data должно быть объектом JSON")
        try:
            eid = uuid_lib.UUID(str(equipment_id_raw))
        except Exception:
            raise HTTPException(status_code=400, detail="Неверный формат equipment_id")

        eq_row = (await db.execute(select(Equipment).where(Equipment.id == eid))).scalar_one_or_none()
        if not eq_row:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")

        assignment_uuid = None
        if payload.get("assignment_id"):
            try:
                assignment_uuid = uuid_lib.UUID(str(payload.get("assignment_id")))
            except Exception:
                raise HTTPException(status_code=400, detail="Неверный формат assignment_id")
            asn = (
                await db.execute(select(Assignment).where(Assignment.id == assignment_uuid))
            ).scalar_one_or_none()
            if not asn:
                raise HTTPException(status_code=404, detail="Задание не найдено")
            if asn.equipment_id != eid:
                raise HTTPException(status_code=400, detail="Задание относится к другому оборудованию")

        status_raw = payload.get("status") or "DRAFT"
        status_val = status_raw.strip()[:50] if isinstance(status_raw, str) else "DRAFT"

        dp = _parse_questionnaire_dt(payload.get("date_performed")) or _parse_questionnaire_dt(
            data.get("inspection_date")
        )

        new_q = Questionnaire(
            equipment_id=eid,
            assignment_id=assignment_uuid,
            date_performed=dp,
            status=status_val,
            data=data,
            created_by=user.id,
            updated_by=user.id,
        )
        db.add(new_q)
        await db.commit()
        await db.refresh(new_q)
        return {
            "id": str(new_q.id),
            "equipment_id": str(new_q.equipment_id),
            "assignment_id": str(new_q.assignment_id) if new_q.assignment_id else None,
            "status": new_q.status,
            "date_performed": new_q.date_performed.isoformat() if new_q.date_performed else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        logger.exception("create_questionnaire")
        raise HTTPException(status_code=500, detail=str(e))


@router.patch("/api/questionnaires/{questionnaire_id}")
async def update_questionnaire(
    questionnaire_id: str,
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Обновить JSON опросного листа и при необходимости статус / дату."""
    try:
        user = await _questionnaire_editor_user(db, username)
        try:
            q_uuid = uuid_lib.UUID(questionnaire_id)
        except Exception:
            raise HTTPException(status_code=400, detail="Неверный формат идентификатора")

        q_row = (await db.execute(select(Questionnaire).where(Questionnaire.id == q_uuid))).scalar_one_or_none()
        if not q_row:
            raise HTTPException(status_code=404, detail="Опросный лист не найден")

        if "data" in payload:
            data = payload.get("data")
            if data is not None and not isinstance(data, dict):
                raise HTTPException(status_code=400, detail="Поле data должно быть объектом JSON")
            if data is not None:
                q_row.data = data

        if payload.get("status") is not None:
            s = payload.get("status")
            q_row.status = (str(s).strip()[:50] if s is not None else q_row.status)

        if payload.get("date_performed") is not None:
            q_row.date_performed = _parse_questionnaire_dt(payload.get("date_performed"))
        elif isinstance(payload.get("data"), dict) and payload["data"].get("inspection_date"):
            q_row.date_performed = _parse_questionnaire_dt(payload["data"]["inspection_date"])

        q_row.updated_by = user.id
        await db.commit()
        await db.refresh(q_row)
        return {
            "id": str(q_row.id),
            "equipment_id": str(q_row.equipment_id),
            "status": q_row.status,
            "date_performed": q_row.date_performed.isoformat() if q_row.date_performed else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        logger.exception("update_questionnaire")
        raise HTTPException(status_code=500, detail=str(e))


# ========== Методы НК (NDT) для опросных листов ==========


@router.post("/api/questionnaires/{questionnaire_id}/ndt-methods")
async def add_ndt_method(
    questionnaire_id: str,
    method_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Добавить метод НК к опросному листу"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        q_result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = q_result.scalar_one_or_none()
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        performed_date = None
        if method_data.get("performed_date"):
            try:
                performed_date = datetime.fromisoformat(method_data.get("performed_date").replace('Z', '+00:00'))
            except:
                pass
        
        photos_list = method_data.get("photos", [])
        additional_data = method_data.get("additional_data", {})
        
        new_method = NDTMethod(
            questionnaire_id=q_uuid,
            equipment_id=questionnaire.equipment_id,
            method_code=method_data.get("method_code"),
            method_name=method_data.get("method_name"),
            is_performed=1 if method_data.get("is_performed", False) else 0,
            standard=method_data.get("standard"),
            equipment=method_data.get("equipment"),
            inspector_name=method_data.get("inspector_name"),
            inspector_level=method_data.get("inspector_level"),
            results=method_data.get("results"),
            defects=method_data.get("defects"),
            conclusion=method_data.get("conclusion"),
            photos=photos_list,
            additional_data=additional_data,
            performed_date=performed_date,
        )
        
        db.add(new_method)
        await db.commit()
        await db.refresh(new_method)
        
        return {
            "id": str(new_method.id),
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to add NDT method: {str(e)}")


@router.post("/api/questionnaires/{questionnaire_id}/ndt-methods/{method_id}/photos/upload")
async def upload_ndt_method_photo(
    questionnaire_id: str,
    method_id: str,
    file: UploadFile = File(...),
    annotated: Optional[bool] = Form(False),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить фото для метода НК (опросный лист)"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        m_uuid = uuid_lib.UUID(method_id)

        method_result = await db.execute(
            select(NDTMethod).where(
                NDTMethod.id == m_uuid,
                NDTMethod.questionnaire_id == q_uuid
            )
        )
        method = method_result.scalar_one_or_none()
        if not method:
            raise HTTPException(status_code=404, detail="NDT method not found")

        normalized_content_type = normalize_image_content_type(file)
        if normalized_content_type not in ALLOWED_IMAGE_MIME_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Allowed: {', '.join(sorted(ALLOWED_IMAGE_MIME_TYPES))}"
            )

        upload_dir = Path("/app/uploads/ndt_photos") / "questionnaires" / str(q_uuid) / str(m_uuid)
        upload_dir.mkdir(parents=True, exist_ok=True)

        file_ext = Path(file.filename).suffix if file.filename else ".jpg"
        stored_name = f"{uuid_lib.uuid4()}{file_ext}"
        stored_path = upload_dir / stored_name

        content = await read_upload_with_limit(file, MAX_NDT_UPLOAD_SIZE_BYTES)
        with open(stored_path, "wb") as f:
            f.write(content)

        photos = list(method.photos or [])
        photos.append(str(stored_path))
        method.photos = photos

        if annotated:
            additional = method.additional_data or {}
            annotated_images = list(additional.get("annotated_images") or [])
            annotated_images.append(str(stored_path))
            additional["annotated_images"] = annotated_images
            method.additional_data = additional

        await db.commit()
        await db.refresh(method)

        return {
            "status": "uploaded",
            "file_path": str(stored_path),
            "photos": method.photos,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to upload NDT photo: {str(e)}")


@router.get("/api/ndt-methods/{method_id}/photos/{file_name}")
async def get_ndt_method_photo(
    method_id: str,
    file_name: str,
    db: AsyncSession = Depends(get_db)
):
    """Получить фото метода НК по имени файла"""
    try:
        m_uuid = uuid_lib.UUID(method_id)
        method_result = await db.execute(select(NDTMethod).where(NDTMethod.id == m_uuid))
        method = method_result.scalar_one_or_none()
        if not method:
            raise HTTPException(status_code=404, detail="NDT method not found")

        photos = list(method.photos or [])
        target = None
        for p in photos:
            if p and Path(p).name == file_name:
                target = p
                break
        if not target or not os.path.exists(target):
            raise HTTPException(status_code=404, detail="Photo not found")

        return FileResponse(target)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid method_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get NDT photo: {str(e)}")


# ========== Методы НК для обследований (inspections) ==========


@router.post("/api/inspections/{inspection_id}/ndt-methods")
async def add_ndt_method_to_inspection(
    inspection_id: str,
    method_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Добавить метод НК к обследованию"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        
        insp_result = await db.execute(
            select(Inspection).where(Inspection.id == insp_uuid)
        )
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")
        
        performed_date = None
        if method_data.get("performed_date"):
            try:
                performed_date = datetime.fromisoformat(method_data.get("performed_date").replace('Z', '+00:00'))
            except:
                pass
        
        new_method = NDTMethod(
            inspection_id=insp_uuid,
            equipment_id=inspection.equipment_id,
            method_code=method_data.get("method_code"),
            method_name=method_data.get("method_name"),
            is_performed=1 if method_data.get("is_performed", False) else 0,
            standard=method_data.get("standard"),
            equipment=method_data.get("equipment"),
            inspector_name=method_data.get("inspector_name"),
            inspector_level=method_data.get("inspector_level"),
            results=method_data.get("results"),
            defects=method_data.get("defects"),
            conclusion=method_data.get("conclusion"),
            photos=method_data.get("photos", []),
            additional_data=method_data.get("additional_data", {}),
            performed_date=performed_date,
        )
        
        db.add(new_method)
        await db.commit()
        await db.refresh(new_method)
        
        return {
            "id": str(new_method.id),
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to add NDT method: {str(e)}")


@router.post("/api/inspections/{inspection_id}/ndt-methods/{method_id}/photos/upload")
async def upload_ndt_method_photo_for_inspection(
    inspection_id: str,
    method_id: str,
    file: UploadFile = File(...),
    annotated: Optional[bool] = Form(False),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить фото для метода НК (обследование)"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        m_uuid = uuid_lib.UUID(method_id)

        method_result = await db.execute(
            select(NDTMethod).where(
                NDTMethod.id == m_uuid,
                NDTMethod.inspection_id == insp_uuid
            )
        )
        method = method_result.scalar_one_or_none()
        if not method:
            raise HTTPException(status_code=404, detail="NDT method not found")

        normalized_content_type = normalize_image_content_type(file)
        if normalized_content_type not in ALLOWED_IMAGE_MIME_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Allowed: {', '.join(sorted(ALLOWED_IMAGE_MIME_TYPES))}"
            )

        upload_dir = Path("/app/uploads/ndt_photos") / "inspections" / str(insp_uuid) / str(m_uuid)
        upload_dir.mkdir(parents=True, exist_ok=True)

        file_ext = Path(file.filename).suffix if file.filename else ".jpg"
        stored_name = f"{uuid_lib.uuid4()}{file_ext}"
        stored_path = upload_dir / stored_name

        content = await read_upload_with_limit(file, MAX_NDT_UPLOAD_SIZE_BYTES)
        with open(stored_path, "wb") as f:
            f.write(content)

        photos = list(method.photos or [])
        photos.append(str(stored_path))
        method.photos = photos

        if annotated:
            additional = method.additional_data or {}
            annotated_images = list(additional.get("annotated_images") or [])
            annotated_images.append(str(stored_path))
            additional["annotated_images"] = annotated_images
            method.additional_data = additional

        await db.commit()
        await db.refresh(method)

        return {
            "status": "uploaded",
            "file_path": str(stored_path),
            "photos": method.photos,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to upload NDT photo: {str(e)}")


# ========== Генерация и скачивание PDF / Word ==========


@router.post("/api/questionnaires/{questionnaire_id}/generate-pdf")
async def generate_questionnaire_pdf(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Сгенерировать PDF для опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == questionnaire.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        generator = ReportGenerator()
        questionnaires_dir = Path("/app/reports/questionnaires")
        questionnaires_dir.mkdir(parents=True, exist_ok=True)
        
        filename = f"questionnaire_{questionnaire.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        file_path = questionnaires_dir / filename
        
        generator.generate_questionnaire_report(
            questionnaire.questionnaire_data or {},
            {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
            },
            {
                "inventory_number": questionnaire.equipment_inventory_number,
                "equipment_name": questionnaire.equipment_name,
                "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
                "inspector_name": questionnaire.inspector_name,
                "inspector_position": questionnaire.inspector_position,
            },
            str(file_path),
            [
                {
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
                }
                for m in ndt_methods
            ]
        )
        
        questionnaire.file_path = str(file_path)
        questionnaire.file_size = file_path.stat().st_size if file_path.exists() else 0
        await db.commit()
        
        return {
            "id": str(questionnaire.id),
            "file_path": str(file_path),
            "file_size": questionnaire.file_size,
            "status": "generated"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate PDF: {str(e)}")


@router.get("/api/questionnaires/{questionnaire_id}/download")
async def download_questionnaire(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать опросный лист (PDF)"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        if not questionnaire.file_path or not Path(questionnaire.file_path).exists():
            await generate_questionnaire_pdf(questionnaire_id, db)
            result = await db.execute(
                select(Questionnaire).where(Questionnaire.id == q_uuid)
            )
            questionnaire = result.scalar_one_or_none()
        
        if not questionnaire.file_path:
            raise HTTPException(status_code=404, detail="PDF file not found")
        
        file_path = Path(questionnaire.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="PDF file not found on disk")
        
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type='application/pdf'
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/questionnaires/{questionnaire_id}/generate-word")
async def generate_questionnaire_word(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Сгенерировать Word документ для опросного листа"""
    try:
        from word_generator import WordGenerator
        
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == questionnaire.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        generator = WordGenerator()
        questionnaires_dir = Path("/app/reports/questionnaires")
        questionnaires_dir.mkdir(parents=True, exist_ok=True)
        
        filename = f"questionnaire_{questionnaire.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.docx"
        file_path = questionnaires_dir / filename
        
        generator.generate_questionnaire_word(
            questionnaire.questionnaire_data or {},
            {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
            },
            {
                "inventory_number": questionnaire.equipment_inventory_number,
                "equipment_name": questionnaire.equipment_name,
                "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
                "inspector_name": questionnaire.inspector_name,
                "inspector_position": questionnaire.inspector_position,
            },
            [
                {
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
                }
                for m in ndt_methods
            ],
            str(file_path)
        )
        
        questionnaire.word_file_path = str(file_path)
        questionnaire.word_file_size = file_path.stat().st_size if file_path.exists() else 0
        await db.commit()
        
        return {
            "id": str(questionnaire.id),
            "word_file_path": str(file_path),
            "word_file_size": questionnaire.word_file_size,
            "status": "generated"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate Word: {str(e)}")


@router.get("/api/questionnaires/{questionnaire_id}/download-word")
async def download_questionnaire_word(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать Word документ опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        if not questionnaire.word_file_path or not Path(questionnaire.word_file_path).exists():
            await generate_questionnaire_word(questionnaire_id, db)
            result = await db.execute(
                select(Questionnaire).where(Questionnaire.id == q_uuid)
            )
            questionnaire = result.scalar_one_or_none()
        
        if not questionnaire.word_file_path:
            raise HTTPException(status_code=404, detail="Word file not found")
        
        file_path = Path(questionnaire.word_file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="Word file not found on disk")
        
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ========== Документы опросного листа ==========


@router.post("/api/questionnaires/{questionnaire_id}/documents/{document_number}/upload")
async def upload_document_file(
    questionnaire_id: str,
    document_number: str,
    file: UploadFile = File(...),
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить файл документа для чек-листа. Лимит: 25 МБ на файл, до 60 вложений на опросник."""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        q_result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = q_result.scalar_one_or_none()
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        allowed_numbers = {str(i) for i in range(1, 18)}
        if document_number not in allowed_numbers:
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", document_number):
                raise HTTPException(
                    status_code=400,
                    detail="Invalid document key. Use 1..17 or a safe key like factory_plate_photo/control_scheme_image/photo_1",
                )
        
        allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'application/pdf']
        content_type = file.content_type
        if not content_type or content_type not in allowed_types:
            ext = (Path(file.filename or "").suffix or "").lower()
            if ext in (".jpg", ".jpeg"):
                content_type = "image/jpeg"
            elif ext == ".png":
                content_type = "image/png"
            elif ext == ".pdf":
                content_type = "application/pdf"
            else:
                content_type = None
        if content_type not in allowed_types:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Allowed types: {', '.join(allowed_types)}",
            )
        
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        user_id = user.id if user else None
        
        documents_dir = Path("/app/uploads/questionnaire_documents") / str(q_uuid)
        documents_dir.mkdir(parents=True, exist_ok=True)
        
        file_extension = Path(file.filename).suffix if file.filename else '.bin'
        if content_type == 'application/pdf':
            file_extension = '.pdf'
        elif content_type and 'image' in content_type:
            file_extension = '.jpg' if 'jpeg' in content_type else '.png'
        
        file_id = uuid_lib.uuid4()
        file_name = f"doc_{document_number}_{file_id}{file_extension}"
        file_path = documents_dir / file_name
        
        MAX_FILE_SIZE_BYTES = 25 * 1024 * 1024
        file_content = b""
        while True:
            chunk = await file.read(1024 * 1024)
            if not chunk:
                break
            file_content += chunk
            if len(file_content) > MAX_FILE_SIZE_BYTES:
                raise HTTPException(
                    status_code=400,
                    detail=f"Файл слишком большой. Максимум {MAX_FILE_SIZE_BYTES // (1024*1024)} МБ.",
                )
        old_file_result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        old_file = old_file_result.scalar_one_or_none()
        if not old_file:
            MAX_DOCS = 60
            cnt = (await db.execute(select(func.count(QuestionnaireDocumentFile.id)).where(QuestionnaireDocumentFile.questionnaire_id == q_uuid))).scalar() or 0
            if cnt >= MAX_DOCS:
                raise HTTPException(status_code=400, detail=f"Превышен лимит вложений ({MAX_DOCS}).")
        if old_file:
            old_path = Path(old_file.file_path)
            if old_path.exists():
                old_path.unlink()
            await db.execute(delete(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.id == old_file.id))
        with open(file_path, 'wb') as f:
            f.write(file_content)
        file_size = len(file_content)
        
        new_file = QuestionnaireDocumentFile(
            questionnaire_id=q_uuid,
            document_number=document_number,
            file_name=file.filename or file_name,
            file_path=str(file_path),
            file_size=file_size,
            file_type=content_type.split('/')[0] if content_type else None,
            mime_type=content_type,
            uploaded_by=user_id
        )
        
        db.add(new_file)
        await db.commit()
        await db.refresh(new_file)
        
        if isinstance(document_number, str) and document_number.startswith("vd_"):
            try:
                parts = document_number.split("_")
                if len(parts) == 3 and parts[0] == "vd":
                    i, j = int(parts[1]), int(parts[2])
                    insp_result = await db.execute(
                        select(Inspection).where(Inspection.questionnaire_id == q_uuid)
                    )
                    insp = insp_result.scalar_one_or_none()
                    if insp and isinstance(insp.data, dict):
                        data = dict(insp.data)
                        vd = data.get("visual_defects")
                        if isinstance(vd, list) and 0 <= i < len(vd):
                            d = vd[i]
                            if isinstance(d, dict):
                                d = dict(d)
                                ph = d.get("photos") or []
                                if isinstance(ph, list) and 0 <= j < len(ph):
                                    ph = list(ph)
                                    ph[j] = str(file_path)
                                    d["photos"] = ph
                                    vd = list(vd)
                                    vd[i] = d
                                    data["visual_defects"] = vd
                                    insp.data = data
                                    await db.commit()
            except Exception:
                pass
        
        return {
            "id": str(new_file.id),
            "questionnaire_id": questionnaire_id,
            "document_number": document_number,
            "file_name": new_file.file_name,
            "file_size": new_file.file_size,
            "file_type": new_file.file_type,
            "mime_type": new_file.mime_type,
            "created_at": new_file.created_at.isoformat() if new_file.created_at else None
        }
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to upload file: {str(e)}")


@router.get("/api/questionnaires/{questionnaire_id}/documents/{document_number}/download")
async def download_document_file(
    questionnaire_id: str,
    document_number: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать файл документа чек-листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()
        
        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")
        
        file_path = Path(doc_file.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="File not found on disk")
        
        media_type = doc_file.mime_type or 'application/octet-stream'
        if doc_file.file_type == 'image':
            if 'jpeg' in doc_file.mime_type or 'jpg' in doc_file.mime_type:
                media_type = 'image/jpeg'
            elif 'png' in doc_file.mime_type:
                media_type = 'image/png'
        elif doc_file.file_type == 'application' or 'pdf' in doc_file.mime_type:
            media_type = 'application/pdf'
        
        return FileResponse(
            path=str(file_path),
            filename=doc_file.file_name,
            media_type=media_type
        )
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/questionnaires/{questionnaire_id}/documents")
async def get_questionnaire_documents(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Получить список всех файлов документов для опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid
            ).order_by(QuestionnaireDocumentFile.document_number)
        )
        files = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(f.id),
                    "document_number": f.document_number,
                    "file_name": f.file_name,
                    "file_size": f.file_size,
                    "file_type": f.file_type,
                    "mime_type": f.mime_type,
                    "created_at": f.created_at.isoformat() if f.created_at else None
                }
                for f in files
            ],
            "total": len(files)
        }
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/questionnaires/{questionnaire_id}/documents/{document_number}/view")
async def view_document_file(
    questionnaire_id: str,
    document_number: str,
    db: AsyncSession = Depends(get_db)
):
    """
    Просмотр файла документа чек-листа в браузере (Content-Disposition: inline).
    Поддерживает изображения и PDF.
    """
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)

        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()

        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")

        file_path = Path(doc_file.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="File not found on disk")

        media_type = doc_file.mime_type or 'application/octet-stream'
        if doc_file.file_type == 'image':
            if doc_file.mime_type and ('jpeg' in doc_file.mime_type or 'jpg' in doc_file.mime_type):
                media_type = 'image/jpeg'
            elif doc_file.mime_type and 'png' in doc_file.mime_type:
                media_type = 'image/png'
        elif (doc_file.file_type == 'application') or (doc_file.mime_type and 'pdf' in doc_file.mime_type):
            media_type = 'application/pdf'

        return FileResponse(
            path=str(file_path),
            media_type=media_type,
            headers={
                "Content-Disposition": f'inline; filename="{doc_file.file_name}"'
            }
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/api/questionnaires/{questionnaire_id}/documents/{document_number}")
async def delete_document_file(
    questionnaire_id: str,
    document_number: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить файл документа чек-листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()
        
        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")
        
        file_path = Path(doc_file.file_path)
        if file_path.exists():
            file_path.unlink()
        
        await db.execute(delete(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.id == doc_file.id))
        await db.commit()
        
        return {"status": "deleted", "document_number": document_number}
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))
