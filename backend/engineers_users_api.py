"""Engineers, users, and certifications API endpoints."""

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional, Dict, List, Any
from datetime import datetime
import uuid as uuid_lib
from pathlib import Path

from database import get_db
from auth import verify_token
from models import Engineer, Certification, User
from shared import cache_get, cache_set, cache_invalidate, cert_areas_list

router = APIRouter(tags=["engineers"])


@router.get("/api/engineers")
async def get_engineers(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get list of engineers (кэш 5 мин)"""
    cached = cache_get("engineers")
    if cached is not None:
        return cached
    try:
        result = await db.execute(select(Engineer).where(Engineer.is_active == 1))
        engineers = result.scalars().all()

        certs_by_engineer: Dict[str, List[Dict[str, Any]]] = {}
        try:
            def _norm_method_code(raw: Any) -> str:
                s = str(raw or "").strip().upper()
                mapping = {
                    "ВИК": "VIK",
                    "УЗК": "UZK",
                    "УЗТ": "UZT",
                    "ПВК": "PVK",
                    "МК": "MK",
                    "РК": "RK",
                    "МПД": "MPD",
                    "КПД": "KPD",
                    "ТВИ": "TVI",
                    "ВТК": "VTK",
                    "АК": "AK",
                    "ТК": "TK",
                }
                return mapping.get(s, s)

            eng_ids = [e.id for e in engineers if getattr(e, "id", None)]
            if eng_ids:
                certs_res = await db.execute(select(Certification).where(Certification.engineer_id.in_(eng_ids)))
                certs = certs_res.scalars().all()
                for c in certs:
                    try:
                        eid = str(getattr(c, "engineer_id", "") or "")
                        if not eid:
                            continue
                        raw_method = getattr(c, "method_code", None)
                        method_code_norm = _norm_method_code(raw_method)
                        method_code_original = (raw_method if raw_method and str(raw_method).strip() else method_code_norm)
                        cert_num = getattr(c, "certificate_number", None) or ""
                        expiry = getattr(c, "expiry_date", None)
                        expiry_str = str(expiry) if expiry else ""
                        item = {
                            "method": method_code_norm,
                            "method_code": method_code_original,
                            "certificate_number": cert_num,
                            "number": cert_num,
                            "expiry_date": expiry_str,
                            "valid_until": expiry_str,
                            "certification_type": getattr(c, "certification_type", None) or "",
                            "certification_areas": cert_areas_list(c),
                        }
                        certs_by_engineer.setdefault(eid, []).append(item)
                    except Exception:
                        continue
        except Exception:
            certs_by_engineer = {}

        items = []
        for e in engineers:
            try:
                eid = str(e.id)
                q = e.qualifications if e.qualifications is not None else []
                if (not q) and certs_by_engineer.get(eid):
                    q = certs_by_engineer[eid]
                items.append({
                    "id": eid,
                    "full_name": e.full_name or "",
                    "position": e.position or "",
                    "email": e.email or "",
                    "phone": e.phone or "",
                    "qualifications": q,
                    "equipment_types": e.equipment_types if e.equipment_types is not None else [],
                })
            except Exception as item_error:
                import traceback
                print(f"Error processing engineer {e.id}: {item_error}")
                traceback.print_exc()
                continue
        
        response = {"items": items}
        cache_set("engineers", response)
        return response
    except Exception as e:
        import traceback
        print(f"Error in get_engineers: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/users")
async def get_users(
    role: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список пользователей"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        query = select(User).where(User.is_active == 1)
        if role:
            query = query.where(User.role == role)
        
        result = await db.execute(query.order_by(User.username))
        users = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(u.id),
                    "username": u.username,
                    "email": u.email,
                    "full_name": u.full_name,
                    "role": u.role,
                    "engineer_id": str(u.engineer_id) if u.engineer_id else None,
                }
                for u in users
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get users: {str(e)}")


@router.post("/api/engineers")
async def create_engineer(engineer_data: dict, db: AsyncSession = Depends(get_db)):
    """Create engineer"""
    try:
        new_engineer = Engineer(
            full_name=engineer_data.get("full_name"),
            position=engineer_data.get("position"),
            email=engineer_data.get("email"),
            phone=engineer_data.get("phone"),
            qualifications=engineer_data.get("qualifications", []),
            equipment_types=engineer_data.get("equipment_types", []),
        )
        db.add(new_engineer)
        await db.commit()
        await db.refresh(new_engineer)
        
        certifications_data = engineer_data.get("certifications", [])
        if certifications_data:
            for cert_data in certifications_data:
                cert = Certification(
                    engineer_id=new_engineer.id,
                    certification_type=cert_data.get("certification_type"),
                    method=cert_data.get("method"),
                    level=cert_data.get("level"),
                    number=cert_data.get("number"),
                    issued_by=cert_data.get("issued_by"),
                    issue_date=cert_data.get("issue_date"),
                    expiry_date=cert_data.get("expiry_date"),
                    is_active=1
                )
                db.add(cert)
            await db.commit()
        
        cache_invalidate("engineers")
        return {"id": str(new_engineer.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/certifications")
async def get_certifications(
    engineer_id: Optional[str] = None,
    method_code: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get certifications (method_code — фильтр по виду НК для мобильной синхронизации)"""
    try:
        query = select(Certification).where(Certification.is_active == 1)
        if engineer_id:
            try:
                eng_uuid = uuid_lib.UUID(engineer_id)
                query = query.where(Certification.engineer_id == eng_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid engineer_id format")
        if method_code:
            query = query.where(Certification.method_code == method_code)
        
        result = await db.execute(query)
        certs = result.scalars().all()
        items = []
        for c in certs:
            try:
                items.append({
                    "id": str(c.id),
                    "engineer_id": str(c.engineer_id) if c.engineer_id else None,
                    "certification_type": c.certification_type or "",
                    "certificate_number": c.certificate_number or "",
                    "number": c.certificate_number or "",
                    "issued_by": c.issuing_organization or "",
                    "issuing_organization": c.issuing_organization or "",
                    "issue_date": str(c.issue_date) if c.issue_date else None,
                    "expiry_date": str(c.expiry_date) if c.expiry_date else None,
                    "document_number": c.document_number or None,
                    "document_date": str(c.document_date) if c.document_date else None,
                    "method_code": c.method_code or None,
                    "certification_areas": cert_areas_list(c),
                    "certification_area": (cert_areas_list(c)[0] if cert_areas_list(c) else None),
                    "equipment_type_id": str(c.equipment_type_id) if c.equipment_type_id else None,
                    "scan_file_name": getattr(c, "scan_file_name", None),
                    "scan_file_size": getattr(c, "scan_file_size", None),
                    "scan_mime_type": getattr(c, "scan_mime_type", None),
                })
            except Exception as item_error:
                import traceback
                print(f"Error processing certification {c.id if c else 'unknown'}: {item_error}")
                traceback.print_exc()
                continue
        
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/certifications")
async def create_certification(
    certification_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать сертификат"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        engineer_id = uuid_lib.UUID(certification_data.get("engineer_id"))
        
        method_code = certification_data.get("method_code") or None
        equipment_type_id = None
        if certification_data.get("equipment_type_id"):
            try:
                equipment_type_id = uuid_lib.UUID(certification_data.get("equipment_type_id"))
            except:
                pass
        areas_raw = certification_data.get("certification_areas")
        if not isinstance(areas_raw, list):
            areas_raw = [certification_data.get("certification_area")] if certification_data.get("certification_area") else []
        cert_areas = [str(a).strip() for a in areas_raw if a]
        
        certification = Certification(
            engineer_id=engineer_id,
            certification_type=certification_data.get("certification_type"),
            certificate_number=certification_data.get("certificate_number"),
            method_code=method_code,
            certification_areas=cert_areas if cert_areas else None,
            certification_area=cert_areas[0] if cert_areas else None,
            equipment_type_id=equipment_type_id,
            issue_date=datetime.strptime(certification_data.get("issue_date"), "%Y-%m-%d").date() if certification_data.get("issue_date") else None,
            expiry_date=datetime.strptime(certification_data.get("expiry_date"), "%Y-%m-%d").date() if certification_data.get("expiry_date") else None,
            issuing_organization=certification_data.get("issuing_organization"),
            document_number=certification_data.get("document_number"),
            document_date=datetime.strptime(certification_data.get("document_date"), "%Y-%m-%d").date() if certification_data.get("document_date") else None,
            is_active=1
        )
        
        db.add(certification)
        await db.commit()
        await db.refresh(certification)
        
        return {
            "id": str(certification.id),
            "engineer_id": str(certification.engineer_id),
            "certification_type": certification.certification_type,
            "certificate_number": certification.certificate_number,
            "method_code": certification.method_code,
            "certification_areas": getattr(certification, "certification_areas", None) or cert_areas_list(certification),
            "certification_area": (getattr(certification, "certification_areas", None) or [])[0] if (getattr(certification, "certification_areas", None) or []) else getattr(certification, "certification_area", None),
            "equipment_type_id": str(certification.equipment_type_id) if certification.equipment_type_id else None,
            "issue_date": str(certification.issue_date) if certification.issue_date else None,
            "expiry_date": str(certification.expiry_date) if certification.expiry_date else None,
            "issuing_organization": certification.issuing_organization,
            "document_number": certification.document_number,
            "document_date": str(certification.document_date) if certification.document_date else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid date format: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create certification: {str(e)}")


@router.put("/api/certifications/{certification_id}")
async def update_certification(
    certification_id: str,
    certification_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Обновить сертификат"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(
            select(Certification).where(Certification.id == cert_uuid)
        )
        certification = result.scalar_one_or_none()
        
        if not certification:
            raise HTTPException(status_code=404, detail="Сертификат не найден")
        
        if "certification_type" in certification_data:
            certification.certification_type = certification_data["certification_type"]
        if "certificate_number" in certification_data:
            certification.certificate_number = certification_data["certificate_number"]
        if "issue_date" in certification_data:
            certification.issue_date = datetime.strptime(certification_data["issue_date"], "%Y-%m-%d").date() if certification_data["issue_date"] else None
        if "expiry_date" in certification_data:
            certification.expiry_date = datetime.strptime(certification_data["expiry_date"], "%Y-%m-%d").date() if certification_data["expiry_date"] else None
        if "issuing_organization" in certification_data:
            certification.issuing_organization = certification_data["issuing_organization"]
        if "document_number" in certification_data:
            certification.document_number = certification_data["document_number"]
        if "document_date" in certification_data:
            certification.document_date = datetime.strptime(certification_data["document_date"], "%Y-%m-%d").date() if certification_data["document_date"] else None
        if "method_code" in certification_data:
            certification.method_code = certification_data["method_code"] or None
        if "certification_areas" in certification_data:
            areas_raw = certification_data.get("certification_areas")
            cert_areas = [str(a).strip() for a in (areas_raw if isinstance(areas_raw, list) else []) if a]
            certification.certification_areas = cert_areas if cert_areas else None
            certification.certification_area = cert_areas[0] if cert_areas else None
        elif "certification_area" in certification_data:
            single = (certification_data.get("certification_area") or "").strip() or None
            certification.certification_area = single
            certification.certification_areas = [single] if single else None
        if "equipment_type_id" in certification_data:
            if certification_data["equipment_type_id"]:
                try:
                    certification.equipment_type_id = uuid_lib.UUID(certification_data["equipment_type_id"])
                except:
                    certification.equipment_type_id = None
            else:
                certification.equipment_type_id = None
        
        await db.commit()
        await db.refresh(certification)
        
        return {
            "id": str(certification.id),
            "engineer_id": str(certification.engineer_id),
            "certification_type": certification.certification_type,
            "certificate_number": certification.certificate_number,
            "method_code": certification.method_code,
            "certification_areas": getattr(certification, "certification_areas", None) or cert_areas_list(certification),
            "certification_area": (cert_areas_list(certification)[0] if cert_areas_list(certification) else None),
            "equipment_type_id": str(certification.equipment_type_id) if certification.equipment_type_id else None,
            "issue_date": str(certification.issue_date) if certification.issue_date else None,
            "expiry_date": str(certification.expiry_date) if certification.expiry_date else None,
            "issuing_organization": certification.issuing_organization,
            "document_number": certification.document_number,
            "document_date": str(certification.document_date) if certification.document_date else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid date format: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update certification: {str(e)}")


@router.delete("/api/certifications/{certification_id}")
async def delete_certification(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить сертификат (мягкое удаление)"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(
            select(Certification).where(Certification.id == cert_uuid)
        )
        certification = result.scalar_one_or_none()
        
        if not certification:
            raise HTTPException(status_code=404, detail="Сертификат не найден")
        
        certification.is_active = 0
        await db.commit()
        
        return {"message": "Сертификат успешно удален"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete certification: {str(e)}")


@router.post("/api/certifications/{certification_id}/scan")
async def upload_certification_scan(
    certification_id: str,
    file: UploadFile = File(...),
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить скан сертификата (фото/PDF)"""
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        allowed = {
            "application/pdf",
            "image/jpeg",
            "image/png",
            "image/webp",
        }
        if file.content_type and file.content_type not in allowed:
            raise HTTPException(status_code=400, detail="Разрешены только фото (JPEG/PNG/WEBP) или PDF")

        uploads_dir = Path("/app/uploads/certification_scans") / str(cert.id)
        uploads_dir.mkdir(parents=True, exist_ok=True)

        safe_name = (file.filename or "scan").replace("\\", "_").replace("/", "_")
        stored_name = f"{uuid_lib.uuid4()}_{safe_name}"
        stored_path = uploads_dir / stored_name

        old_path = getattr(cert, "scan_file_path", None)
        if old_path:
            try:
                old_p = Path(old_path)
                if old_p.exists():
                    old_p.unlink()
            except Exception:
                pass

        size = 0
        with stored_path.open("wb") as f:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                f.write(chunk)

        cert.scan_file_path = str(stored_path)
        cert.scan_file_name = file.filename
        cert.scan_file_size = size
        cert.scan_mime_type = file.content_type

        await db.commit()
        await db.refresh(cert)

        return {
            "id": str(cert.id),
            "scan_file_name": cert.scan_file_name,
            "scan_file_size": cert.scan_file_size,
            "scan_mime_type": cert.scan_mime_type,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to upload scan: {str(e)}")


@router.get("/api/certifications/{certification_id}/scan")
async def download_certification_scan(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Скачать скан сертификата"""
    try:
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        scan_path = getattr(cert, "scan_file_path", None)
        if not scan_path or not Path(scan_path).exists():
            raise HTTPException(status_code=404, detail="Скан не найден")

        return FileResponse(
            path=scan_path,
            filename=(getattr(cert, "scan_file_name", None) or "certificate-scan"),
            media_type=(getattr(cert, "scan_mime_type", None) or "application/octet-stream"),
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to download scan: {str(e)}")


@router.delete("/api/certifications/{certification_id}/scan")
async def delete_certification_scan(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить скан сертификата"""
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        scan_path = getattr(cert, "scan_file_path", None)
        if scan_path:
            try:
                p = Path(scan_path)
                if p.exists():
                    p.unlink()
            except Exception:
                pass

        cert.scan_file_path = None
        cert.scan_file_name = None
        cert.scan_file_size = None
        cert.scan_mime_type = None
        await db.commit()

        return {"message": "Скан удален"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete scan: {str(e)}")
