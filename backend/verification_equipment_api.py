"""Verification equipment endpoints — поверочное оборудование."""

import asyncio
import csv
import io
import json
import logging
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request
import uuid as uuid_lib
import traceback
from datetime import datetime, date, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from fastapi.responses import Response, StreamingResponse
from sqlalchemy import select, nulls_last, func
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models import (
    VerificationEquipment,
    VerificationHistory,
    InspectionEquipment,
    Inspection,
    User,
)
from auth import verify_token_optional
from auth_api import get_current_user

router = APIRouter(tags=["verification-equipment"])

logger = logging.getLogger(__name__)

FGIS_VRI_URL = "https://fgis.gost.ru/fundmetrology/eapi/vri"
FGIS_RESULTS_URL = "https://fgis.gost.ru/fundmetrology/cm/results?tab=VRI&type=1"


def _norm_alnum(value: Optional[str]) -> str:
    return "".join(ch for ch in (value or "") if ch.isalnum()).lower()


def _fgis_vri_search(query: str, rows: int = 40) -> List[Dict[str, Any]]:
    """Синхронный запрос к публичному API ФГИС (Аршин) — только чтение."""
    q = (query or "").strip()
    if len(q) < 2:
        return []
    params = urllib.parse.urlencode({"search": q, "rows": str(min(rows, 100)), "start": "0"})
    url = f"{FGIS_VRI_URL}?{params}"
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "SystemaPro-Monitor/3.7.0 (verification lookup)",
        },
    )
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=28, context=ctx) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    return (payload.get("result") or {}).get("items") or []


def _lookup_fgis_arshin_impl(serial_number: Optional[str], certificate_number: Optional[str]) -> Dict[str, Any]:
    """Поиск сведений о поверке в ФГИС по номеру свидетельства и/или заводскому номеру СИ."""
    cert = (certificate_number or "").strip()
    ser = (serial_number or "").strip()
    if not cert and not ser:
        return {"items": [], "hint": "Укажите серийный номер прибора или номер свидетельства о поверке."}

    merged: Dict[str, Dict[str, Any]] = {}
    for q in ([cert] if cert else []) + ([ser] if ser and ser != cert else []):
        try:
            items = _fgis_vri_search(q, rows=50)
        except urllib.error.HTTPError as e:
            logger.warning("ФГИС HTTP %s: %s", e.code, e.reason)
            raise HTTPException(status_code=502, detail="ФГИС вернул ошибку при запросе") from e
        except urllib.error.URLError as e:
            logger.warning("ФГИС сеть: %s", e)
            raise HTTPException(status_code=502, detail="Не удалось связаться с ФГИС. Проверьте сеть или повторите позже.") from e
        except Exception as e:
            logger.exception("ФГИС: неожиданная ошибка")
            raise HTTPException(status_code=502, detail=f"Ошибка при обращении к ФГИС: {e}") from e

        for it in items:
            vid = str(it.get("vri_id") or "")
            if not vid:
                continue
            merged[vid] = it

    slim: List[Dict[str, Any]] = []
    ser_norm = _norm_alnum(ser)
    for it in merged.values():
        mi_num = it.get("mi_number") or ""
        doc = it.get("result_docnum") or ""
        if ser_norm and not cert:
            if ser_norm not in _norm_alnum(mi_num):
                continue
        slim.append(
            {
                "vri_id": it.get("vri_id"),
                "org_title": it.get("org_title"),
                "mit_title": it.get("mit_title"),
                "mit_number": it.get("mit_number"),
                "mi_modification": it.get("mi_modification"),
                "mi_number": mi_num,
                "verification_date": it.get("verification_date"),
                "valid_date": it.get("valid_date"),
                "result_docnum": doc,
                "applicability": it.get("applicability"),
            }
        )

    slim.sort(key=lambda x: (x.get("verification_date") or ""), reverse=True)
    return {
        "items": slim[:30],
        "arshin_portal_url": FGIS_RESULTS_URL,
        "hint": "Точнее всего поиск по номеру свидетельства (как в документе). По одному только серийному номеру реестр может не вернуть строку — тогда введите номер свидетельства.",
    }


@router.get("/api/verification-equipment")
async def get_verification_equipment(
    days_before_expiry: Optional[int] = None,
    equipment_type: Optional[str] = None,
    is_active: Optional[bool] = True,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить список оборудования для поверок"""
    try:
        query = select(VerificationEquipment)
        
        if is_active is not None:
            query = query.where(VerificationEquipment.is_active == bool(is_active))
        
        if equipment_type:
            query = query.where(VerificationEquipment.equipment_type == equipment_type)
        
        if days_before_expiry is not None:
            today = date.today()
            warning_date = today + timedelta(days=days_before_expiry)
            query = query.where(
                VerificationEquipment.next_verification_date <= warning_date,
                VerificationEquipment.next_verification_date >= today
            )
        
        result = await db.execute(query.order_by(nulls_last(VerificationEquipment.next_verification_date)))
        items = result.scalars().all()
        
        return [{
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "category": item.category,
            "serial_number": item.serial_number,
            "manufacturer": item.manufacturer,
            "model": item.model,
            "inventory_number": item.inventory_number,
            "verification_date": item.verification_date.isoformat() if item.verification_date else None,
            "next_verification_date": item.next_verification_date.isoformat() if item.next_verification_date else None,
            "verification_certificate_number": item.verification_certificate_number,
            "verification_organization": item.verification_organization,
            "scan_file_path": item.scan_file_path,
            "scan_file_name": item.scan_file_name,
            "is_active": bool(item.is_active),
            "notes": item.notes,
            "days_until_expiry": (item.next_verification_date - date.today()).days if item.next_verification_date else None,
            "is_expired": item.next_verification_date < date.today() if item.next_verification_date else False,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        } for item in items]
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_verification_equipment: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении оборудования для поверок: {error_detail}")


@router.get("/api/verification-equipment/statistics/usage")
async def verification_equipment_usage_statistics(
    days: int = 90,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional),
):
    """Сколько раз поверочное оборудование фигурировало в обследованиях за период."""
    if days < 1:
        days = 1
    if days > 366:
        days = 366
    since = datetime.now(timezone.utc) - timedelta(days=days)
    try:
        q = (
            select(
                VerificationEquipment.id,
                VerificationEquipment.name,
                VerificationEquipment.equipment_type,
                VerificationEquipment.serial_number,
                func.count(InspectionEquipment.id).label("cnt"),
            )
            .select_from(InspectionEquipment)
            .join(VerificationEquipment, InspectionEquipment.verification_equipment_id == VerificationEquipment.id)
            .join(Inspection, InspectionEquipment.inspection_id == Inspection.id)
            .where(
                Inspection.created_at >= since,
                VerificationEquipment.is_active == True,
            )
            .group_by(
                VerificationEquipment.id,
                VerificationEquipment.name,
                VerificationEquipment.equipment_type,
                VerificationEquipment.serial_number,
            )
        )
        result = await db.execute(q)
        rows = result.all()
        equipment_list: List[Dict[str, Any]] = []
        total_uses = 0
        for row in rows:
            cnt = int(row.cnt or 0)
            total_uses += cnt
            equipment_list.append(
                {
                    "id": str(row.id),
                    "name": row.name or "",
                    "equipment_type": row.equipment_type or "",
                    "serial_number": row.serial_number or "",
                    "usage_count": cnt,
                }
            )
        equipment_list.sort(key=lambda x: x["usage_count"], reverse=True)
        return {
            "period_days": days,
            "total_uses": total_uses,
            "equipment_count": len(equipment_list),
            "equipment": equipment_list,
        }
    except Exception as e:
        logger.exception("verification_equipment_usage_statistics")
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("/api/verification-equipment/fgis-arshin/lookup")
async def lookup_verification_in_fgis_arshin(
    serial_number: Optional[str] = None,
    certificate_number: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
):
    """Проверка сведений о поверке в публичном фонде ФГИС (Аршин) по номеру СИ / свидетельства."""
    role = current_user.get("role")
    if role not in ("admin", "chief_operator", "operator", "engineer"):
        raise HTTPException(status_code=403, detail="Недостаточно прав")
    try:
        return await asyncio.to_thread(_lookup_fgis_arshin_impl, serial_number, certificate_number)
    except HTTPException:
        raise


@router.post("/api/verification-equipment")
async def create_verification_equipment(
    name: str = Form(...),
    equipment_type: str = Form(...),
    serial_number: str = Form(...),
    verification_date: str = Form(...),
    next_verification_date: str = Form(...),
    category: Optional[str] = Form(None),
    manufacturer: Optional[str] = Form(None),
    model: Optional[str] = Form(None),
    inventory_number: Optional[str] = Form(None),
    verification_certificate_number: Optional[str] = Form(None),
    verification_organization: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    scan_file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Создать новое оборудование для поверки"""
    try:
        if current_user.get("role") not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        new_id = uuid_lib.uuid4()
        scan_file_path = None
        scan_file_name = None
        scan_file_size = None
        scan_mime_type = None
        
        if scan_file:
            upload_dir = Path("/app/uploads/verification_scans") / str(new_id)
            upload_dir.mkdir(parents=True, exist_ok=True)
            
            file_ext = Path(scan_file.filename).suffix
            file_name = f"{uuid_lib.uuid4()}{file_ext}"
            file_path = upload_dir / file_name
            
            content = await scan_file.read()
            with open(file_path, "wb") as f:
                f.write(content)
            
            scan_file_path = str(file_path)
            scan_file_name = scan_file.filename
            scan_file_size = len(content)
            scan_mime_type = scan_file.content_type
        
        verification_date_obj = datetime.strptime(verification_date, "%Y-%m-%d").date()
        next_verification_date_obj = datetime.strptime(next_verification_date, "%Y-%m-%d").date()
        
        new_equipment = VerificationEquipment(
            id=new_id,
            name=name,
            equipment_type=equipment_type,
            category=category,
            serial_number=serial_number,
            manufacturer=manufacturer,
            model=model,
            inventory_number=inventory_number,
            verification_date=verification_date_obj,
            next_verification_date=next_verification_date_obj,
            verification_certificate_number=verification_certificate_number,
            verification_organization=verification_organization,
            scan_file_path=scan_file_path,
            scan_file_name=scan_file_name,
            scan_file_size=scan_file_size,
            scan_mime_type=scan_mime_type,
            notes=notes
        )
        
        db.add(new_equipment)
        await db.commit()
        await db.refresh(new_equipment)
        
        return {
            "id": str(new_equipment.id),
            "name": new_equipment.name,
            "equipment_type": new_equipment.equipment_type,
            "serial_number": new_equipment.serial_number,
            "next_verification_date": new_equipment.next_verification_date.isoformat(),
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Неверный формат даты: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/verification-equipment/{equipment_id}")
async def get_verification_equipment_by_id(
    equipment_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить оборудование для поверки по ID"""
    try:
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        history_result = await db.execute(
            select(VerificationHistory)
            .where(VerificationHistory.verification_equipment_id == item.id)
            .order_by(VerificationHistory.verification_date.desc())
        )
        history = history_result.scalars().all()
        
        return {
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "category": item.category,
            "serial_number": item.serial_number,
            "manufacturer": item.manufacturer,
            "model": item.model,
            "inventory_number": item.inventory_number,
            "verification_date": item.verification_date.isoformat() if item.verification_date else None,
            "next_verification_date": item.next_verification_date.isoformat() if item.next_verification_date else None,
            "verification_certificate_number": item.verification_certificate_number,
            "verification_organization": item.verification_organization,
            "scan_file_path": item.scan_file_path,
            "scan_file_name": item.scan_file_name,
            "scan_file_size": item.scan_file_size,
            "scan_mime_type": item.scan_mime_type,
            "is_active": bool(item.is_active),
            "notes": item.notes,
            "days_until_expiry": (item.next_verification_date - date.today()).days if item.next_verification_date else None,
            "is_expired": item.next_verification_date < date.today() if item.next_verification_date else False,
            "history": [{
                "id": str(h.id),
                "verification_date": h.verification_date.isoformat(),
                "next_verification_date": h.next_verification_date.isoformat(),
                "certificate_number": h.certificate_number,
                "verification_organization": h.verification_organization,
                "scan_file_path": h.scan_file_path,
                "scan_file_name": h.scan_file_name,
                "notes": h.notes,
                "created_at": h.created_at.isoformat() if h.created_at else None,
            } for h in history],
            "created_at": item.created_at.isoformat() if item.created_at else None,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/api/verification-equipment/{equipment_id}")
async def update_verification_equipment(
    equipment_id: str,
    name: Optional[str] = Form(None),
    equipment_type: Optional[str] = Form(None),
    serial_number: Optional[str] = Form(None),
    verification_date: Optional[str] = Form(None),
    next_verification_date: Optional[str] = Form(None),
    category: Optional[str] = Form(None),
    manufacturer: Optional[str] = Form(None),
    model: Optional[str] = Form(None),
    inventory_number: Optional[str] = Form(None),
    verification_certificate_number: Optional[str] = Form(None),
    verification_organization: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    is_active: Optional[bool] = Form(None),
    scan_file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Обновить оборудование для поверки"""
    try:
        if current_user.get("role") not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        if verification_date and item.verification_date:
            old_date = item.verification_date
            new_date = datetime.strptime(verification_date, "%Y-%m-%d").date()
            if old_date != new_date:
                history_entry = VerificationHistory(
                    verification_equipment_id=item.id,
                    verification_date=old_date,
                    next_verification_date=item.next_verification_date,
                    certificate_number=item.verification_certificate_number,
                    verification_organization=item.verification_organization,
                    scan_file_path=item.scan_file_path,
                    scan_file_name=item.scan_file_name,
                    notes=item.notes
                )
                if "id" in current_user:
                    history_entry.created_by = uuid_lib.UUID(current_user["id"])
                db.add(history_entry)
        
        if name is not None:
            item.name = name
        if equipment_type is not None:
            item.equipment_type = equipment_type
        if category is not None:
            item.category = category
        if serial_number is not None:
            item.serial_number = serial_number
        if manufacturer is not None:
            item.manufacturer = manufacturer
        if model is not None:
            item.model = model
        if inventory_number is not None:
            item.inventory_number = inventory_number
        if verification_date is not None:
            item.verification_date = datetime.strptime(verification_date, "%Y-%m-%d").date()
        if next_verification_date is not None:
            item.next_verification_date = datetime.strptime(next_verification_date, "%Y-%m-%d").date()
        if verification_certificate_number is not None:
            item.verification_certificate_number = verification_certificate_number
        if verification_organization is not None:
            item.verification_organization = verification_organization
        if notes is not None:
            item.notes = notes
        if is_active is not None:
            item.is_active = 1 if is_active else 0
        
        if scan_file:
            if item.scan_file_path and os.path.exists(item.scan_file_path):
                try:
                    os.remove(item.scan_file_path)
                except:
                    pass
            
            upload_dir = Path("/app/uploads/verification_scans") / str(item.id)
            upload_dir.mkdir(parents=True, exist_ok=True)
            
            file_ext = Path(scan_file.filename).suffix
            file_name = f"{uuid_lib.uuid4()}{file_ext}"
            file_path = upload_dir / file_name
            
            content = await scan_file.read()
            with open(file_path, "wb") as f:
                f.write(content)
            
            item.scan_file_path = str(file_path)
            item.scan_file_name = scan_file.filename
            item.scan_file_size = len(content)
            item.scan_mime_type = scan_file.content_type
        
        await db.commit()
        await db.refresh(item)
        
        return {
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "next_verification_date": item.next_verification_date.isoformat(),
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Неверный формат: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/api/verification-equipment/{equipment_id}")
async def delete_verification_equipment(
    equipment_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Удалить оборудование для поверки"""
    try:
        if current_user.get("role") not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        if item.scan_file_path and os.path.exists(item.scan_file_path):
            try:
                os.remove(item.scan_file_path)
            except:
                pass
        
        await db.delete(item)
        await db.commit()
        
        return {"status": "deleted", "id": equipment_id}
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/verification-equipment/{equipment_id}/scan")
async def get_verification_scan(
    equipment_id: str,
    inline: bool = False,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить скан свидетельства о поверке"""
    try:
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item or not item.scan_file_path:
            raise HTTPException(status_code=404, detail="Скан не найден")
        
        if not os.path.exists(item.scan_file_path):
            raise HTTPException(status_code=404, detail="Файл не найден на сервере")
        
        def iterfile():
            with open(item.scan_file_path, mode="rb") as file_like:
                yield from file_like
        
        headers = {}
        if inline:
            headers["Content-Disposition"] = f'inline; filename="{item.scan_file_name or "scan.pdf"}"'
        else:
            headers["Content-Disposition"] = f'attachment; filename="{item.scan_file_name or "scan.pdf"}"'
        
        return StreamingResponse(
            iterfile(),
            media_type=item.scan_mime_type or "application/pdf",
            headers=headers
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/inspections/{inspection_id}/equipment")
async def add_equipment_to_inspection(
    inspection_id: str,
    equipment_data: dict,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Добавить используемое оборудование для поверок к обследованию"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        
        if not inspection:
            raise HTTPException(status_code=404, detail="Обследование не найдено")
        
        user_result = await db.execute(select(User).where(User.username == current_user["username"]))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        
        if user.role not in ["admin", "chief_operator", "operator", "engineer"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        if user.role == "engineer" and inspection.inspector_id != user.id:
            raise HTTPException(status_code=403, detail="Можно добавлять оборудование только к своим обследованиям")
        
        equipment_ids = equipment_data.get("verification_equipment_ids", [])
        if not isinstance(equipment_ids, list):
            raise HTTPException(status_code=400, detail="verification_equipment_ids должен быть списком")
        
        added = []
        for eq_id in equipment_ids:
            try:
                eq_uuid = uuid_lib.UUID(eq_id)
                eq_result = await db.execute(
                    select(VerificationEquipment).where(VerificationEquipment.id == eq_uuid)
                )
                ver_eq = eq_result.scalar_one_or_none()
                
                if not ver_eq:
                    continue
                
                existing = await db.execute(
                    select(InspectionEquipment).where(
                        InspectionEquipment.inspection_id == insp_uuid,
                        InspectionEquipment.verification_equipment_id == eq_uuid
                    )
                )
                if existing.scalar_one_or_none():
                    continue
                
                inspection_equipment = InspectionEquipment(
                    inspection_id=insp_uuid,
                    verification_equipment_id=eq_uuid
                )
                db.add(inspection_equipment)
                added.append(str(eq_id))
            except ValueError:
                continue
        
        await db.commit()
        
        return {
            "status": "success",
            "inspection_id": inspection_id,
            "equipment_added": len(added),
            "equipment_ids": added
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/inspections/{inspection_id}/equipment")
async def get_inspection_equipment(
    inspection_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить список используемого оборудования для обследования"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        
        result = await db.execute(
            select(InspectionEquipment, VerificationEquipment)
            .join(VerificationEquipment, InspectionEquipment.verification_equipment_id == VerificationEquipment.id)
            .where(InspectionEquipment.inspection_id == insp_uuid)
        )
        items = result.all()
        
        equipment_list = []
        for ie, ve in items:
            equipment_list.append({
                "id": str(ve.id),
                "name": ve.name,
                "equipment_type": ve.equipment_type,
                "serial_number": ve.serial_number,
                "manufacturer": ve.manufacturer,
                "model": ve.model,
                "verification_date": ve.verification_date.isoformat() if ve.verification_date else None,
                "next_verification_date": ve.next_verification_date.isoformat() if ve.next_verification_date else None,
                "verification_certificate_number": ve.verification_certificate_number,
                "verification_organization": ve.verification_organization,
                "scan_file_path": ve.scan_file_path,
                "scan_file_name": ve.scan_file_name,
                "is_expired": ve.next_verification_date < date.today() if ve.next_verification_date else False,
            })
        
        return equipment_list
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/verification-equipment/export")
async def export_verification_equipment(
    format: str = "csv",
    days_before_expiry: Optional[int] = None,
    equipment_type: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Экспорт списка оборудования для поверок"""
    try:
        query = select(VerificationEquipment).where(VerificationEquipment.is_active == True)
        
        if equipment_type:
            query = query.where(VerificationEquipment.equipment_type == equipment_type)
        
        if days_before_expiry is not None:
            today = date.today()
            warning_date = today + timedelta(days=days_before_expiry)
            query = query.where(
                VerificationEquipment.next_verification_date <= warning_date,
                VerificationEquipment.next_verification_date >= today
            )
        
        result = await db.execute(query.order_by(VerificationEquipment.next_verification_date))
        items = result.scalars().all()
        
        if format.lower() == "csv":
            output = io.StringIO()
            writer = csv.writer(output)
            
            writer.writerow([
                'Название', 'Тип', 'Категория', 'Серийный номер', 'Производитель', 'Модель',
                'Инвентарный номер', 'Дата поверки', 'Следующая поверка', 'Номер свидетельства',
                'Организация поверки', 'Статус', 'Дней до истечения'
            ])
            
            for item in items:
                days = (item.next_verification_date - date.today()).days if item.next_verification_date else None
                status = "Просрочено" if (item.next_verification_date and item.next_verification_date < date.today()) else (
                    f"Предупреждение ({days} дн.)" if days and days <= 30 else "Активно"
                )
                writer.writerow([
                    item.name or '',
                    item.equipment_type or '',
                    item.category or '',
                    item.serial_number or '',
                    item.manufacturer or '',
                    item.model or '',
                    item.inventory_number or '',
                    item.verification_date.strftime('%d.%m.%Y') if item.verification_date else '',
                    item.next_verification_date.strftime('%d.%m.%Y') if item.next_verification_date else '',
                    item.verification_certificate_number or '',
                    item.verification_organization or '',
                    status,
                    str(days) if days is not None else '',
                ])
            
            csv_content = output.getvalue()
            output.close()
            
            return Response(
                content='\ufeff' + csv_content,
                media_type='text/csv; charset=utf-8',
                headers={'Content-Disposition': f'attachment; filename="verification_equipment_{date.today().isoformat()}.csv"'}
            )
        else:
            raise HTTPException(status_code=400, detail="Неподдерживаемый формат экспорта")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/verification-equipment/export/csv")
async def export_verification_equipment_csv(
    days_before_expiry: Optional[int] = None,
    equipment_type: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional),
):
    """Алиас пути `/export/csv` для фронтенда (то же, что `export?format=csv`)."""
    return await export_verification_equipment(
        format="csv",
        days_before_expiry=days_before_expiry,
        equipment_type=equipment_type,
        db=db,
        current_user=current_user,
    )
