"""Instruments registry API — реестр приборов (приборный парк). П.4"""

import uuid as uuid_lib
import logging
from datetime import datetime, date
from types import SimpleNamespace
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from auth_api import get_current_user

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/instruments", tags=["instruments"])


# ============================================================
#  Вспомогательные функции
# ============================================================

def _check_operator_or_admin(user: dict):
    """Только оператор/администратор могут управлять реестром приборов."""
    if user.get("role") not in ("admin", "chief_operator", "operator"):
        raise HTTPException(status_code=403, detail="Недостаточно прав")


async def _ensure_table(db: AsyncSession):
    """Создаёт таблицу instrument_registry если не существует, добавляет колонки."""
    await db.execute(text("""
        CREATE TABLE IF NOT EXISTS instrument_registry (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name VARCHAR(255) NOT NULL,
            type VARCHAR(100),
            serial_number VARCHAR(150),
            verification_until VARCHAR(20),
            condition VARCHAR(50) DEFAULT 'ok',
            condition_notes TEXT,
            specialist_id UUID REFERENCES users(id) ON DELETE SET NULL,
            created_by UUID REFERENCES users(id) ON DELETE SET NULL,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW(),
            is_deleted BOOLEAN DEFAULT FALSE
        )
    """))
    # Добавляем колонку verification_equipment_id если её нет (связь с поверками)
    await db.execute(text("""
        ALTER TABLE instrument_registry
        ADD COLUMN IF NOT EXISTS verification_equipment_id UUID
            REFERENCES verification_equipment(id) ON DELETE SET NULL
    """))
    await db.commit()


def _ve_shadow_to_dict(ve_row) -> dict:
    """Строка из verification_equipment без записи в instrument_registry — тот же контракт, id с префиксом ve-shadow:."""
    next_d = ve_row.next_verification_date
    verification_until = ""
    verification_status = "unknown"
    if next_d:
        if isinstance(next_d, date):
            verification_until = next_d.strftime("%Y-%m")
        else:
            verification_until = str(next_d)[:7]
        try:
            d = next_d if isinstance(next_d, date) else datetime.strptime(str(next_d)[:10], "%Y-%m-%d").date()
            today = date.today()
            days_left = (d - today).days
            if days_left < 0:
                verification_status = "expired"
            elif days_left <= 30:
                verification_status = "expiring_soon"
            elif days_left <= 90:
                verification_status = "warning"
            else:
                verification_status = "ok"
        except Exception:
            verification_status = "unknown"
    vid = ve_row.id
    return {
        "id": f"ve-shadow:{vid}",
        "name": ve_row.name or ve_row.equipment_type or "Прибор",
        "type": ve_row.equipment_type or "",
        "serial_number": ve_row.serial_number or "",
        "verification_until": verification_until,
        "verification_status": verification_status,
        "condition": "ok",
        "condition_notes": "",
        "specialist_id": None,
        "specialist_name": "",
        "verification_equipment_id": str(vid),
        "ve_name": ve_row.name,
        "ve_manufacturer": ve_row.manufacturer,
        "ve_model": ve_row.model,
        "ve_certificate": ve_row.verification_certificate_number,
        "ve_organization": ve_row.verification_organization,
        "ve_next_verification_date": next_d.isoformat()
        if next_d and isinstance(next_d, date)
        else (str(next_d)[:10] if next_d else None),
        "created_at": None,
        "is_shadow_row": True,
    }


def _row_to_dict(row) -> dict:
    """Преобразует строку запроса в словарь."""
    # Определяем дату поверки: предпочитаем из verification_equipment
    ve_next_date = getattr(row, 've_next_verification_date', None)
    if ve_next_date:
        if isinstance(ve_next_date, date):
            verification_until = ve_next_date.strftime('%Y-%m')
        else:
            verification_until = str(ve_next_date)[:7]
        # Вычисляем статус поверки
        try:
            d = ve_next_date if isinstance(ve_next_date, date) else datetime.strptime(str(ve_next_date)[:10], '%Y-%m-%d').date()
            today = date.today()
            days_left = (d - today).days
            if days_left < 0:
                verification_status = 'expired'
            elif days_left <= 30:
                verification_status = 'expiring_soon'
            elif days_left <= 90:
                verification_status = 'warning'
            else:
                verification_status = 'ok'
        except Exception:
            verification_status = 'unknown'
    else:
        verification_until = getattr(row, 'verification_until', '') or ''
        # Пробуем вычислить статус из manual поля
        verification_status = 'unknown'
        if verification_until:
            try:
                d = datetime.strptime(f'{verification_until}-01', '%Y-%m-%d').date()
                today = date.today()
                days_left = (d - today).days
                if days_left < 0:
                    verification_status = 'expired'
                elif days_left <= 30:
                    verification_status = 'expiring_soon'
                elif days_left <= 90:
                    verification_status = 'warning'
                else:
                    verification_status = 'ok'
            except Exception:
                pass

    dct = {
        "id": str(row.id),
        "name": row.name,
        "type": row.type or "",
        "serial_number": row.serial_number or "",
        "verification_until": verification_until,
        "verification_status": verification_status,
        "condition": row.condition or "ok",
        "condition_notes": row.condition_notes or "",
        "specialist_id": str(row.specialist_id) if row.specialist_id else None,
        "specialist_name": getattr(row, 'specialist_name', '') or "",
        "verification_equipment_id": str(row.verification_equipment_id) if row.verification_equipment_id else None,
        # Дополнительные данные из verification_equipment
        "ve_name": getattr(row, 've_name', None),
        "ve_manufacturer": getattr(row, 've_manufacturer', None),
        "ve_model": getattr(row, 've_model', None),
        "ve_certificate": getattr(row, 've_certificate', None),
        "ve_organization": getattr(row, 've_organization', None),
        "ve_next_verification_date": ve_next_date.isoformat() if ve_next_date and isinstance(ve_next_date, date) else (str(ve_next_date)[:10] if ve_next_date else None),
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "is_shadow_row": False,
    }
    return dct


# ============================================================
#  GET /api/instruments — список всех приборов (П.4)
# ============================================================

@router.get("")
async def list_instruments(
    type_filter: Optional[str] = Query(None, alias="type"),
    specialist_id: Optional[str] = None,
    condition: Optional[str] = None,
    expiring_days: Optional[int] = None,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Получить реестр всех приборов с фильтрацией. Доступно всем авторизованным."""
    await _ensure_table(db)

    # JOIN с verification_equipment для получения актуальных данных поверки
    q = """
        SELECT
            ir.*,
            u.full_name AS specialist_name,
            ve.name AS ve_name,
            ve.manufacturer AS ve_manufacturer,
            ve.model AS ve_model,
            ve.verification_certificate_number AS ve_certificate,
            ve.verification_organization AS ve_organization,
            ve.next_verification_date AS ve_next_verification_date
        FROM instrument_registry ir
        LEFT JOIN users u ON u.id = ir.specialist_id
        LEFT JOIN verification_equipment ve ON ve.id = ir.verification_equipment_id
        WHERE ir.is_deleted = FALSE
    """
    params: dict = {}

    if type_filter:
        q += " AND ir.type ILIKE :type"
        params["type"] = f"%{type_filter}%"
    if specialist_id:
        q += " AND ir.specialist_id = :specialist_id"
        params["specialist_id"] = specialist_id
    if condition:
        q += " AND ir.condition = :condition"
        params["condition"] = condition

    q += " ORDER BY ir.name"

    result = await db.execute(text(q), params)
    rows = result.fetchall()

    instruments = [_row_to_dict(r) for r in rows]

    # Поверочные приборы без строки в реестре — показываем как «тень», чтобы списки совпадали с журналом поверок
    orphan_sql = text(
        """
        SELECT ve.id, ve.name, ve.equipment_type, ve.serial_number, ve.next_verification_date,
               ve.manufacturer, ve.model, ve.verification_certificate_number, ve.verification_organization
        FROM verification_equipment ve
        WHERE (ve.is_active IS NULL OR ve.is_active = TRUE)
          AND NOT EXISTS (
            SELECT 1 FROM instrument_registry ir
            WHERE ir.is_deleted = FALSE AND ir.verification_equipment_id = ve.id
          )
        ORDER BY COALESCE(ve.name, ve.equipment_type, '')
        """
    )
    try:
        for vr in (await db.execute(orphan_sql)).mappings().all():
            instruments.append(_ve_shadow_to_dict(SimpleNamespace(**dict(vr))))
    except Exception as ex:
        logger.warning("instrument_registry orphan merge skipped: %s", ex)

    # Доп. фильтры по полному списку (в т.ч. тени)
    if type_filter:
        tl = type_filter.lower()
        instruments = [
            i
            for i in instruments
            if tl in (i.get("type") or "").lower() or tl in (i.get("name") or "").lower()
        ]
    if specialist_id:
        instruments = [i for i in instruments if str(i.get("specialist_id") or "") == str(specialist_id)]
    if condition:
        instruments = [i for i in instruments if (i.get("condition") or "") == str(condition)]

    # Фильтр по истекающей поверке (на уровне Python)
    if expiring_days is not None:
        today = date.today()
        filtered = []
        for inst in instruments:
            ve_date = None
            raw = inst.get("ve_next_verification_date")
            if raw:
                try:
                    ve_date = datetime.strptime(raw[:10], '%Y-%m-%d').date()
                except Exception:
                    pass
            if ve_date is None and inst.get("verification_until"):
                try:
                    ve_date = datetime.strptime(f'{inst["verification_until"]}-01', '%Y-%m-%d').date()
                except Exception:
                    pass
            if ve_date is not None and (ve_date - today).days <= expiring_days:
                filtered.append(inst)
        instruments = filtered

    return instruments


# ============================================================
#  GET /api/instruments/my — приборы текущего пользователя
# ============================================================

@router.get("/my")
async def my_instruments(
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Получить приборы, закреплённые за текущим пользователем (П.4.3)."""
    await _ensure_table(db)
    user_id = current_user.get("id") or current_user.get("user_id")
    result = await db.execute(text("""
        SELECT
            ir.*,
            u.full_name AS specialist_name,
            ve.name AS ve_name,
            ve.manufacturer AS ve_manufacturer,
            ve.model AS ve_model,
            ve.verification_certificate_number AS ve_certificate,
            ve.verification_organization AS ve_organization,
            ve.next_verification_date AS ve_next_verification_date
        FROM instrument_registry ir
        LEFT JOIN users u ON u.id = ir.specialist_id
        LEFT JOIN verification_equipment ve ON ve.id = ir.verification_equipment_id
        WHERE ir.is_deleted = FALSE
          AND ir.specialist_id = :uid
        ORDER BY ir.name
    """), {"uid": user_id})
    rows = result.fetchall()
    return [_row_to_dict(r) for r in rows]


# ============================================================
#  GET /api/instruments/verification-equipment-options
#  Список verification_equipment для выбора при создании/редактировании
# ============================================================

@router.get("/ve-options")
async def get_ve_options(
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Получить список приборов из поверок для привязки к реестру."""
    result = await db.execute(text("""
        SELECT id, name, equipment_type, serial_number,
               next_verification_date, manufacturer, model
        FROM verification_equipment
        WHERE is_active = TRUE
        ORDER BY name
    """))
    rows = result.fetchall()
    return [
        {
            "id": str(r.id),
            "name": r.name,
            "equipment_type": r.equipment_type or "",
            "serial_number": r.serial_number or "",
            "next_verification_date": r.next_verification_date.isoformat() if r.next_verification_date else None,
            "manufacturer": r.manufacturer or "",
            "model": r.model or "",
        }
        for r in rows
    ]


# ============================================================
#  GET /api/instruments/specialists — пользователи для назначения
# ============================================================

@router.get("/specialists")
async def get_specialists(
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Получить список сотрудников для закрепления приборов. Доступно всем авторизованным."""
    result = await db.execute(text("""
        SELECT id, full_name, username, role
        FROM users
        WHERE is_active = TRUE
          AND role IN ('admin', 'chief_operator', 'operator', 'engineer')
        ORDER BY full_name, username
    """))
    rows = result.fetchall()
    return [
        {
            "id": str(r.id),
            "full_name": r.full_name or r.username,
            "username": r.username,
            "role": r.role,
        }
        for r in rows
    ]


# ============================================================
#  POST /api/instruments — создать прибор
# ============================================================

@router.post("", status_code=201)
async def create_instrument(
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Создать новый прибор в реестре. Только оператор/администратор."""
    _check_operator_or_admin(current_user)
    await _ensure_table(db)

    user_id = current_user.get("id") or current_user.get("user_id")
    inst_id = str(uuid_lib.uuid4())

    specialist_id = payload.get("specialist_id") or None
    if specialist_id == "":
        specialist_id = None

    verification_equipment_id = payload.get("verification_equipment_id") or None
    if verification_equipment_id == "":
        verification_equipment_id = None

    await db.execute(text("""
        INSERT INTO instrument_registry
            (id, name, type, serial_number, verification_until,
             condition, condition_notes, specialist_id, created_by,
             verification_equipment_id)
        VALUES
            (:id, :name, :type, :serial_number, :verification_until,
             :condition, :condition_notes, :specialist_id, :created_by,
             :verification_equipment_id)
    """), {
        "id": inst_id,
        "name": payload.get("name", ""),
        "type": payload.get("type", ""),
        "serial_number": payload.get("serial_number", ""),
        "verification_until": payload.get("verification_until", ""),
        "condition": payload.get("condition", "ok"),
        "condition_notes": payload.get("condition_notes", ""),
        "specialist_id": specialist_id,
        "created_by": user_id,
        "verification_equipment_id": verification_equipment_id,
    })
    await db.commit()

    result = await db.execute(text("""
        SELECT ir.*, u.full_name AS specialist_name,
               ve.name AS ve_name, ve.manufacturer AS ve_manufacturer,
               ve.model AS ve_model,
               ve.verification_certificate_number AS ve_certificate,
               ve.verification_organization AS ve_organization,
               ve.next_verification_date AS ve_next_verification_date
        FROM instrument_registry ir
        LEFT JOIN users u ON u.id = ir.specialist_id
        LEFT JOIN verification_equipment ve ON ve.id = ir.verification_equipment_id
        WHERE ir.id = :id
    """), {"id": inst_id})
    row = result.fetchone()
    return _row_to_dict(row)


# ============================================================
#  PUT /api/instruments/{inst_id} — обновить прибор
# ============================================================

@router.put("/{inst_id}")
async def update_instrument(
    inst_id: str,
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Обновить прибор. Оператор/администратор или инженер (только своё состояние)."""
    await _ensure_table(db)
    if inst_id.startswith("ve-shadow:"):
        raise HTTPException(
            status_code=400,
            detail="Это запись только из журнала поверок. Создайте строку реестра («Добавить прибор») с привязкой к этой поверке.",
        )

    result = await db.execute(
        text("SELECT * FROM instrument_registry WHERE id = :id AND is_deleted = FALSE"),
        {"id": inst_id},
    )
    row = result.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Прибор не найден")

    role = current_user.get("role", "")
    user_id = str(current_user.get("id") or current_user.get("user_id") or "")
    is_specialist = str(row.specialist_id) == user_id if row.specialist_id else False

    if role not in ("admin", "chief_operator", "operator") and not is_specialist:
        raise HTTPException(status_code=403, detail="Недостаточно прав")

    if role in ("admin", "chief_operator", "operator"):
        specialist_id = payload.get("specialist_id", row.specialist_id)
        if specialist_id == "":
            specialist_id = None

        verification_equipment_id = payload.get("verification_equipment_id", row.verification_equipment_id)
        if verification_equipment_id == "":
            verification_equipment_id = None

        await db.execute(text("""
            UPDATE instrument_registry SET
                name = :name,
                type = :type,
                serial_number = :serial_number,
                verification_until = :verification_until,
                condition = :condition,
                condition_notes = :condition_notes,
                specialist_id = :specialist_id,
                verification_equipment_id = :verification_equipment_id,
                updated_at = NOW()
            WHERE id = :id
        """), {
            "id": inst_id,
            "name": payload.get("name", row.name),
            "type": payload.get("type", row.type),
            "serial_number": payload.get("serial_number", row.serial_number),
            "verification_until": payload.get("verification_until", row.verification_until),
            "condition": payload.get("condition", row.condition),
            "condition_notes": payload.get("condition_notes", row.condition_notes),
            "specialist_id": specialist_id,
            "verification_equipment_id": verification_equipment_id,
        })
    else:
        # Инженер может обновить только состояние своего прибора (П.4.8)
        await db.execute(text("""
            UPDATE instrument_registry SET
                condition = :condition,
                condition_notes = :condition_notes,
                updated_at = NOW()
            WHERE id = :id
        """), {
            "id": inst_id,
            "condition": payload.get("condition", row.condition),
            "condition_notes": payload.get("condition_notes", row.condition_notes),
        })

    await db.commit()
    result = await db.execute(text("""
        SELECT ir.*, u.full_name AS specialist_name,
               ve.name AS ve_name, ve.manufacturer AS ve_manufacturer,
               ve.model AS ve_model,
               ve.verification_certificate_number AS ve_certificate,
               ve.verification_organization AS ve_organization,
               ve.next_verification_date AS ve_next_verification_date
        FROM instrument_registry ir
        LEFT JOIN users u ON u.id = ir.specialist_id
        LEFT JOIN verification_equipment ve ON ve.id = ir.verification_equipment_id
        WHERE ir.id = :id
    """), {"id": inst_id})
    return _row_to_dict(result.fetchone())


# ============================================================
#  DELETE /api/instruments/{inst_id} — удалить прибор
# ============================================================

@router.delete("/{inst_id}", status_code=204)
async def delete_instrument(
    inst_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Мягкое удаление прибора. Только оператор/администратор."""
    _check_operator_or_admin(current_user)
    await _ensure_table(db)
    if inst_id.startswith("ve-shadow:"):
        raise HTTPException(status_code=400, detail="Запись из журнала поверок удаляется только через справочник поверок.")

    result = await db.execute(
        text("SELECT id FROM instrument_registry WHERE id = :id AND is_deleted = FALSE"),
        {"id": inst_id},
    )
    if not result.fetchone():
        raise HTTPException(status_code=404, detail="Прибор не найден")

    await db.execute(
        text("UPDATE instrument_registry SET is_deleted = TRUE, updated_at = NOW() WHERE id = :id"),
        {"id": inst_id},
    )
    await db.commit()
