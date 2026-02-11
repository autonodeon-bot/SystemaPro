# Endpoint для приёма ZIP-архива обследования с мобильного приложения
import os
import json as _json
import zipfile
import tempfile
import shutil
import traceback as _traceback
import uuid as uuid_lib
from pathlib import Path
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from database import get_db
from models import (
    Inspection, Questionnaire, QuestionnaireDocumentFile,
    InspectionHistory, Assignment, User, Equipment,
)
from auth import verify_token_optional
from typing import Optional


def _validate_create_inspection(data: dict) -> None:
    """Валидация тела запроса создания обследования."""
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
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail=err)


router = APIRouter(prefix="/api/inspections", tags=["inspections"])


@router.post("/upload-archive")
async def upload_inspection_archive(
    file: UploadFile = File(...),
    username: Optional[str] = Depends(verify_token_optional),
    db: AsyncSession = Depends(get_db),
):
    """Принять ZIP-архив обследования (manifest.json, checklist.json, photos/*), распаковать и создать обследование."""
    from sqlalchemy import or_

    try:
        if not file.filename or not file.filename.lower().endswith(".zip"):
            raise HTTPException(status_code=400, detail="Ожидается файл .zip")
        content = await file.read()
        if len(content) > 150 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="Архив слишком большой (макс. 150 МБ)")
        created_by_id = None
        if username:
            user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
            u = user_result.scalar_one_or_none()
            if u:
                created_by_id = u.id
        tmpdir = tempfile.mkdtemp(prefix="insp_archive_")
        try:
            zip_path = os.path.join(tmpdir, "upload.zip")
            with open(zip_path, "wb") as f:
                f.write(content)
            with zipfile.ZipFile(zip_path, "r") as zf:
                zf.extractall(tmpdir)
            manifest_path = os.path.join(tmpdir, "manifest.json")
            checklist_path = os.path.join(tmpdir, "checklist.json")
            photos_dir = os.path.join(tmpdir, "photos")
            if not os.path.isfile(manifest_path) or not os.path.isfile(checklist_path):
                raise HTTPException(status_code=400, detail="В архиве должны быть manifest.json и checklist.json")
            with open(manifest_path, "r", encoding="utf-8") as f:
                manifest = _json.load(f)
            with open(checklist_path, "r", encoding="utf-8") as f:
                checklist_payload = _json.load(f)
            data_raw = checklist_payload.get("data") or {}
            if not isinstance(data_raw, dict):
                data_raw = {}
            try:
                data_clean = _json.loads(_json.dumps(data_raw))
            except (TypeError, ValueError):
                data_clean = data_raw
            inspection_data = {
                "equipment_id": checklist_payload.get("equipment_id") or manifest.get("equipment_id"),
                "data": data_clean,
                "conclusion": checklist_payload.get("conclusion") or manifest.get("conclusion"),
                "status": checklist_payload.get("status") or manifest.get("status", "DRAFT"),
                "date_performed": checklist_payload.get("date_performed") or manifest.get("date_performed"),
                "assignment_id": checklist_payload.get("assignment_id") or manifest.get("assignment_id"),
            }
            _validate_create_inspection(inspection_data)
            equipment_id = uuid_lib.UUID(str(inspection_data["equipment_id"]))
            date_performed = None
            if inspection_data.get("date_performed"):
                try:
                    date_performed = datetime.fromisoformat(str(inspection_data["date_performed"]).replace("Z", "+00:00"))
                    if date_performed.tzinfo is None:
                        date_performed = date_performed.replace(tzinfo=timezone.utc)
                except Exception:
                    pass
            project_id = None
            if inspection_data.get("project_id"):
                try:
                    project_id = uuid_lib.UUID(str(inspection_data["project_id"]))
                except Exception:
                    pass
            new_inspection = Inspection(
                equipment_id=equipment_id,
                project_id=project_id,
                data=inspection_data.get("data", {}),
                conclusion=inspection_data.get("conclusion"),
                status=inspection_data.get("status", "DRAFT"),
                date_performed=date_performed,
                is_archived=False,
                created_by=created_by_id,
            )
            db.add(new_inspection)
            await db.commit()
            await db.refresh(new_inspection)
            # Сразу сохраняем ответ, чтобы не зависеть от состояния сессии в конце
            response_data = {
                "id": str(new_inspection.id),
                "equipment_id": str(new_inspection.equipment_id),
                "questionnaire_id": None,
                "status": "created",
                "date_performed": new_inspection.date_performed.isoformat() if new_inspection.date_performed else None,
            }
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
                    assignment_id_q = None
                    if inspection_data.get("assignment_id"):
                        try:
                            aid_uuid = uuid_lib.UUID(str(inspection_data["assignment_id"]))
                            exists = await db.execute(select(Assignment).where(Assignment.id == aid_uuid))
                            if exists.scalar_one_or_none() is not None:
                                assignment_id_q = aid_uuid
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
                    try:
                        new_inspection.questionnaire_id = new_questionnaire.id
                        await db.commit()
                        await db.refresh(new_inspection)
                    except Exception:
                        await db.rollback()
                        questionnaire_id = None
            assignment_id = None
            if inspection_data.get("assignment_id"):
                try:
                    aid_uuid = uuid_lib.UUID(str(inspection_data["assignment_id"]))
                    exists = await db.execute(select(Assignment).where(Assignment.id == aid_uuid))
                    if exists.scalar_one_or_none() is not None:
                        assignment_id = aid_uuid
                except Exception:
                    pass
            inspection_type = "VISUAL"
            if inspection_data_dict:
                if inspection_data_dict.get("documents") or inspection_data_dict.get("vessel_name"):
                    inspection_type = "QUESTIONNAIRE"
                elif inspection_data_dict.get("ndt_methods") or inspection_data_dict.get("method_code"):
                    inspection_type = "NDT"
            inspector_id = None
            if inspection_data_dict and inspection_data_dict.get("inspector_id"):
                try:
                    inspector_id = uuid_lib.UUID(str(inspection_data_dict["inspector_id"]))
                except Exception:
                    pass
            _inspection_date = date_performed or datetime.now(timezone.utc)
            history_entry = InspectionHistory(
                equipment_id=equipment_id,
                assignment_id=assignment_id,
                inspection_type=inspection_type,
                inspector_id=inspector_id,
                inspection_date=_inspection_date,
                data=inspection_data.get("data", {}),
                conclusion=inspection_data.get("conclusion"),
                status=inspection_data.get("status", "DRAFT"),
            )
            db.add(history_entry)
            await db.commit()
            if assignment_id:
                try:
                    assignment_result = await db.execute(select(Assignment).where(Assignment.id == assignment_id))
                    assignment = assignment_result.scalar_one_or_none()
                    if assignment and (inspection_data.get("status") or "").upper() == "SIGNED":
                        assignment.status = "COMPLETED"
                        assignment.completed_at = datetime.now(timezone.utc)
                    await db.commit()
                except Exception:
                    await db.rollback()
            path_map = {}
            if questionnaire_id and os.path.isdir(photos_dir):
                q_uuid = uuid_lib.UUID(questionnaire_id)
                documents_dir = Path("/app/uploads/questionnaire_documents") / str(q_uuid)
                documents_dir.mkdir(parents=True, exist_ok=True)
                for fn in os.listdir(photos_dir):
                    if fn.startswith("."):
                        continue
                    fp = os.path.join(photos_dir, fn)
                    if not os.path.isfile(fp):
                        continue
                    base, ext = os.path.splitext(fn)
                    if base == "factory_plate":
                        doc_num = "factory_plate_photo"
                    elif base == "control_scheme":
                        doc_num = "control_scheme_image"
                    elif base.startswith("doc_"):
                        doc_num = base[4:]
                    elif base.startswith("vd_"):
                        doc_num = base
                    elif base.startswith("uzt_point_"):
                        doc_num = base
                    else:
                        doc_num = f"photo_{base}"
                    stored_name = f"doc_{doc_num}_{uuid_lib.uuid4()}{ext or '.jpg'}"
                    stored_path = documents_dir / stored_name
                    shutil.copy2(fp, stored_path)
                    path_map[f"photos/{fn}"] = str(stored_path)
                    mime = "image/jpeg" if (ext or "").lower() in (".jpg", ".jpeg") else "image/png"
                    qdf = QuestionnaireDocumentFile(
                        questionnaire_id=q_uuid,
                        document_number=doc_num,
                        file_name=fn,
                        file_path=str(stored_path),
                        file_size=os.path.getsize(stored_path),
                        file_type="image",
                        mime_type=mime,
                        uploaded_by=created_by_id,
                    )
                    db.add(qdf)
                await db.commit()
                if path_map and new_inspection.data is not None and isinstance(new_inspection.data, dict):
                    def replace_paths(obj):
                        if isinstance(obj, dict):
                            return {k: replace_paths(v) for k, v in obj.items()}
                        if isinstance(obj, list):
                            return [replace_paths(x) for x in obj]
                        if isinstance(obj, str) and obj in path_map:
                            return path_map[obj]
                        return obj
                    try:
                        new_inspection.data = replace_paths(dict(new_inspection.data))
                        await db.commit()
                        await db.refresh(new_inspection)
                    except Exception:
                        await db.rollback()
            response_data["questionnaire_id"] = questionnaire_id
        finally:
            try:
                shutil.rmtree(tmpdir, ignore_errors=True)
            except Exception:
                pass
        return response_data
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        _traceback.print_exc()
        err_msg = str(e)
        tb_lines = _traceback.format_exc().strip().split("\n")
        # В ответе всегда показываем причину; добавляем ключевую строку traceback (обычно последняя перед "Exception")
        detail = f"Ошибка обработки архива: {err_msg}"
        for line in reversed(tb_lines[-6:]):
            line = line.strip()
            if line and not line.startswith("File ") and "Traceback" not in line:
                detail = f"{detail}. {line}"
                break
        raise HTTPException(status_code=500, detail=detail)
