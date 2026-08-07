"""Справочники: типы оборудования, трубопроводы, ресурсы, нормативные документы, клиенты, проекты."""

from fastapi import APIRouter, Depends, HTTPException, File, Form, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import date as date_cls

from sqlalchemy import case, distinct, func, or_, select
from typing import Optional
from datetime import datetime
from pathlib import Path as FsPath
import uuid as uuid_lib
import os

from database import get_db
from auth import verify_token
from pydantic import BaseModel

from models import (
    Assignment,
    Equipment,
    EquipmentType,
    PipelineSegment,
    EquipmentResource,
    RegulatoryDocument,
    Client,
    Project,
    ProjectInvoice,
    ProjectInvoicePayment,
    ProjectContract,
    User,
    Inspection,
    Report,
    Questionnaire,
)
from shared import cache_get, cache_set, cache_invalidate

router = APIRouter(tags=["dictionaries"])

_INVOICE_STATUSES = frozenset({"DRAFT", "ISSUED", "PAID", "CANCELLED"})
_CONTRACT_STATUSES = frozenset({"ACTIVE", "CLOSED"})


# ──────────────────── Equipment Types ────────────────────

@router.get("/api/equipment-types")
async def get_equipment_types(db: AsyncSession = Depends(get_db)):
    cached = cache_get("equipment_types")
    if cached is not None:
        return cached
    try:
        result = await db.execute(select(EquipmentType).where(EquipmentType.is_active == True))
        types = result.scalars().all()
        response = {
            "items": [
                {"id": str(et.id), "name": et.name, "description": et.description, "code": et.code}
                for et in types
            ]
        }
        cache_set("equipment_types", response)
        return response
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class EquipmentTypeUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None
    description: Optional[str] = None


@router.post("/api/equipment-types")
async def create_equipment_type(
    type_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        user = user_result.scalar_one_or_none()
        if not user or user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        new_type = EquipmentType(
            name=type_data.get("name"),
            code=type_data.get("code"),
            description=type_data.get("description"),
        )
        db.add(new_type)
        await db.commit()
        await db.refresh(new_type)
        cache_invalidate("equipment_types")
        return {"id": str(new_type.id), "name": new_type.name, "code": new_type.code, "description": new_type.description}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/api/equipment-types/{type_id}")
async def update_equipment_type(
    type_id: str,
    type_data: EquipmentTypeUpdate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Обновить тип оборудования"""
    user_result = await db.execute(select(User).where(User.username == username))
    user = user_result.scalar_one_or_none()
    if not user or user.role not in ["admin", "chief_operator"]:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    try:
        type_uuid = uuid_lib.UUID(type_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Некорректный ID типа") from exc

    result = await db.execute(select(EquipmentType).where(EquipmentType.id == type_uuid))
    eq_type = result.scalar_one_or_none()
    if not eq_type or not eq_type.is_active:
        raise HTTPException(status_code=404, detail="Тип оборудования не найден")

    try:
        if type_data.name is not None:
            name = type_data.name.strip()
            if not name:
                raise HTTPException(status_code=400, detail="Название не может быть пустым")
            eq_type.name = name

        if type_data.code is not None:
            code = type_data.code.strip() or None
            if code:
                dup = await db.execute(
                    select(EquipmentType).where(
                        EquipmentType.code == code,
                        EquipmentType.id != type_uuid,
                        EquipmentType.is_active == True,
                    )
                )
                if dup.scalar_one_or_none():
                    raise HTTPException(status_code=409, detail="Тип с таким кодом уже существует")
            eq_type.code = code

        if type_data.description is not None:
            eq_type.description = type_data.description.strip() or None

        await db.commit()
        await db.refresh(eq_type)
        cache_invalidate("equipment_types")
        return {
            "id": str(eq_type.id),
            "name": eq_type.name,
            "code": eq_type.code,
            "description": eq_type.description,
        }
    except HTTPException:
        await db.rollback()
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.delete("/api/equipment-types/{type_id}")
async def delete_equipment_type(
    type_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Деактивировать тип оборудования"""
    user_result = await db.execute(select(User).where(User.username == username))
    user = user_result.scalar_one_or_none()
    if not user or user.role not in ["admin", "chief_operator"]:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    try:
        type_uuid = uuid_lib.UUID(type_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Некорректный ID типа") from exc

    result = await db.execute(select(EquipmentType).where(EquipmentType.id == type_uuid))
    eq_type = result.scalar_one_or_none()
    if not eq_type or not eq_type.is_active:
        raise HTTPException(status_code=404, detail="Тип оборудования не найден")

    usage_count = await db.execute(
        select(func.count())
        .select_from(Equipment)
        .where(Equipment.type_id == type_uuid, Equipment.is_active == True)
    )
    if (usage_count.scalar() or 0) > 0:
        raise HTTPException(
            status_code=409,
            detail="Нельзя удалить тип: к нему привязано активное оборудование",
        )

    try:
        eq_type.is_active = False
        await db.commit()
        cache_invalidate("equipment_types")
        return {"message": "Тип оборудования удалён", "id": str(eq_type.id)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e)) from e


# ──────────────────── Pipelines ────────────────────

@router.get("/api/pipelines")
async def get_pipelines(db: AsyncSession = Depends(get_db)):
    try:
        result = await db.execute(select(PipelineSegment))
        segments = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(seg.id),
                    "name": seg.name,
                    "segment_type": seg.segment_type,
                    "corrosion_rate": seg.corrosion_rate,
                    "thickness": seg.thickness,
                    "last_inspection_date": str(seg.last_inspection_date) if seg.last_inspection_date else None,
                    "remaining_life": seg.remaining_life,
                }
                for seg in segments
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ──────────────────── Clients ────────────────────

@router.get("/api/clients")
async def get_clients(db: AsyncSession = Depends(get_db)):
    try:
        result = await db.execute(select(Client))
        clients = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(c.id),
                    "name": c.name,
                    "contact_person": c.contact_person,
                    "email": c.email,
                    "phone": c.phone,
                    "address": c.address,
                    "inn": getattr(c, "inn", None),
                }
                for c in clients
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/clients")
async def create_client(client_data: dict, db: AsyncSession = Depends(get_db)):
    try:
        new_client = Client(
            name=client_data.get("name"),
            contact_person=client_data.get("contact_person"),
            email=client_data.get("email"),
            phone=client_data.get("phone"),
            address=client_data.get("address"),
        )
        if hasattr(new_client, "inn"):
            new_client.inn = client_data.get("inn")
        db.add(new_client)
        await db.commit()
        await db.refresh(new_client)
        return {"id": str(new_client.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


# ──────────────────── Projects ────────────────────

def _project_budget_safe(p: Project) -> Optional[float]:
    b = getattr(p, "budget", None)
    if b is None:
        return None
    try:
        return float(b)
    except (TypeError, ValueError):
        return None


@router.get("/api/projects")
async def get_projects(
    client_id: Optional[str] = None,
    status: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    try:
        query = select(Project)
        if client_id:
            try:
                query = query.where(Project.client_id == uuid_lib.UUID(client_id))
            except Exception:
                raise HTTPException(status_code=400, detail="Invalid client_id format")
        if status:
            query = query.where(Project.status == status)

        result = await db.execute(query.order_by(Project.created_at.desc()))
        projects = result.scalars().all()
        items = []
        for p in projects:
            dl = getattr(p, "deadline", None)
            try:
                created = p.created_at.isoformat() if p.created_at else None
            except Exception:
                created = str(p.created_at) if p.created_at else None
            items.append(
                {
                    "id": str(p.id),
                    "client_id": str(p.client_id) if p.client_id else None,
                    "name": p.name,
                    "description": p.description,
                    "status": p.status,
                    "start_date": str(p.start_date) if p.start_date else None,
                    "end_date": str(p.end_date) if p.end_date else None,
                    "deadline": str(dl) if dl else None,
                    "budget": _project_budget_safe(p),
                    "created_at": created,
                }
            )
        return {"items": items, "total": len(items)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/projects/{project_id}/statistics")
async def get_project_statistics(project_id: str, db: AsyncSession = Depends(get_db)):
    """Сводка по проекту (совместима с модальным окном ProjectsManagement)."""
    try:
        pid = uuid_lib.UUID(project_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат идентификатора проекта")

    proj = (await db.execute(select(Project).where(Project.id == pid))).scalar_one_or_none()
    if not proj:
        raise HTTPException(status_code=404, detail="Проект не найден")

    tot_asg = (
        await db.execute(select(func.count()).select_from(Assignment).where(Assignment.project_id == pid))
    ).scalar() or 0
    done_asg = (
        await db.execute(
            select(func.count())
            .select_from(Assignment)
            .where(Assignment.project_id == pid, Assignment.status == "COMPLETED")
        )
    ).scalar() or 0
    prog_asg = (
        await db.execute(
            select(func.count())
            .select_from(Assignment)
            .where(Assignment.project_id == pid, Assignment.status == "IN_PROGRESS")
        )
    ).scalar() or 0
    pend_asg = int(tot_asg) - int(done_asg) - int(prog_asg)
    if pend_asg < 0:
        pend_asg = 0

    neq = (
        await db.execute(
            select(func.count(distinct(Assignment.equipment_id))).where(Assignment.project_id == pid)
        )
    ).scalar() or 0

    ic = (
        await db.execute(select(func.count()).select_from(Inspection).where(Inspection.project_id == pid))
    ).scalar() or 0
    rc = (
        await db.execute(
            select(func.count())
            .select_from(Report)
            .join(Inspection, Report.inspection_id == Inspection.id)
            .where(Inspection.project_id == pid)
        )
    ).scalar() or 0
    qc = (
        await db.execute(
            select(func.count())
            .select_from(Questionnaire)
            .join(Assignment, Questionnaire.assignment_id == Assignment.id)
            .where(Assignment.project_id == pid)
        )
    ).scalar() or 0

    progress_percent = (100.0 * float(done_asg) / float(tot_asg)) if tot_asg else 0.0

    days_running = 1
    if proj.start_date:
        try:
            sd = proj.start_date if isinstance(proj.start_date, date_cls) else date_cls.fromisoformat(str(proj.start_date)[:10])
            days_running = max(1, (date_cls.today() - sd).days)
        except Exception:
            days_running = 1
    speed_per_day = float(done_asg) / float(days_running)

    eng_rows = (
        await db.execute(
            select(
                User.id,
                User.full_name,
                func.count(Assignment.id).label("total"),
                func.sum(case((Assignment.status == "COMPLETED", 1), else_=0)).label("completed"),
                func.sum(case((Assignment.status == "IN_PROGRESS", 1), else_=0)).label("in_progress"),
            )
            .select_from(Assignment)
            .join(User, Assignment.assigned_to == User.id)
            .where(Assignment.project_id == pid)
            .group_by(User.id, User.full_name)
        )
    ).all()

    engineers = []
    for row in eng_rows:
        uid, fname, total, completed, in_progress = row
        t = int(total or 0)
        c = int(completed or 0)
        ip = int(in_progress or 0)
        engineers.append(
            {
                "engineer_id": str(uid),
                "engineer_name": fname or "—",
                "total": t,
                "completed": c,
                "in_progress": ip,
            }
        )

    return {
        "project_id": str(pid),
        "assignments_total": int(tot_asg),
        "inspections_total": int(ic),
        "reports_total": int(rc),
        "questionnaires_total": int(qc),
        "progress_percent": progress_percent,
        "total_equipment": int(neq) if neq else int(tot_asg),
        "completed_equipment": int(done_asg),
        "in_progress_equipment": int(prog_asg),
        "pending_equipment": int(pend_asg),
        "speed_per_day": speed_per_day,
        "estimated_completion_date": None,
        "inspections_count": int(ic),
        "reports_count": int(rc),
        "engineers": engineers,
    }


@router.post("/api/projects")
async def create_project(project_data: dict, db: AsyncSession = Depends(get_db)):
    try:
        client_id = None
        if project_data.get("client_id"):
            try:
                client_id = uuid_lib.UUID(project_data["client_id"])
            except Exception:
                raise HTTPException(status_code=400, detail="Invalid client_id format")

        def _parse_date(val):
            if not val:
                return None
            try:
                return datetime.fromisoformat(val.replace("Z", "+00:00")).date()
            except Exception:
                try:
                    return datetime.fromisoformat(val).date()
                except Exception:
                    return None

        new_project = Project(
            client_id=client_id,
            name=project_data.get("name"),
            description=project_data.get("description"),
            status=project_data.get("status", "PLANNED"),
            start_date=_parse_date(project_data.get("start_date")),
            end_date=_parse_date(project_data.get("end_date")),
            deadline=_parse_date(project_data.get("deadline")),
            budget=float(project_data["budget"]) if project_data.get("budget") else None,
        )
        db.add(new_project)
        await db.commit()
        await db.refresh(new_project)
        return {"id": str(new_project.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


async def _require_finance_user(db: AsyncSession, username: str) -> User:
    result = await db.execute(select(User).where(User.username == username))
    user = result.scalar_one_or_none()
    if not user or user.role not in ("admin", "chief_operator"):
        raise HTTPException(status_code=403, detail="Доступ запрещён")
    return user


async def _require_admin_user(db: AsyncSession, username: str) -> User:
    result = await db.execute(select(User).where(User.username == username))
    user = result.scalar_one_or_none()
    if not user or user.role != "admin":
        raise HTTPException(status_code=403, detail="Требуется роль администратора")
    return user


def _invoice_amount_safe(inv: ProjectInvoice) -> Optional[float]:
    a = getattr(inv, "amount", None)
    if a is None:
        return None
    try:
        return float(a)
    except (TypeError, ValueError):
        return None


def _invoice_to_item(inv: ProjectInvoice, payments_paid: float = 0.0) -> dict:
    try:
        created = inv.created_at.isoformat() if inv.created_at else None
    except Exception:
        created = str(inv.created_at) if inv.created_at else None
    try:
        updated = inv.updated_at.isoformat() if inv.updated_at else None
    except Exception:
        updated = str(inv.updated_at) if inv.updated_at else None
    try:
        pt = round(float(payments_paid), 2)
    except (TypeError, ValueError):
        pt = 0.0
    return {
        "id": str(inv.id),
        "project_id": str(inv.project_id),
        "invoice_number": inv.invoice_number,
        "amount": _invoice_amount_safe(inv),
        "currency": inv.currency or "RUB",
        "status": inv.status,
        "issued_date": str(inv.issued_date) if inv.issued_date else None,
        "due_date": str(inv.due_date) if inv.due_date else None,
        "paid_date": str(inv.paid_date) if inv.paid_date else None,
        "description": inv.description,
        "payments_total": pt,
        "created_at": created,
        "updated_at": updated,
    }


def _parse_invoice_date(val):
    if not val:
        return None
    try:
        return datetime.fromisoformat(val.replace("Z", "+00:00")).date()
    except Exception:
        try:
            return datetime.fromisoformat(val).date()
        except Exception:
            return None


async def _sum_invoice_payments(db: AsyncSession, invoice_id: uuid_lib.UUID) -> float:
    q = select(func.coalesce(func.sum(ProjectInvoicePayment.amount), 0)).where(
        ProjectInvoicePayment.invoice_id == invoice_id
    )
    r = await db.execute(q)
    v = r.scalar()
    try:
        return float(v or 0)
    except (TypeError, ValueError):
        return 0.0


async def _invoice_payment_rows_map(db: AsyncSession, invoice_ids: list) -> dict:
    if not invoice_ids:
        return {}
    q = (
        select(ProjectInvoicePayment.invoice_id, func.coalesce(func.sum(ProjectInvoicePayment.amount), 0))
        .where(ProjectInvoicePayment.invoice_id.in_(invoice_ids))
        .group_by(ProjectInvoicePayment.invoice_id)
    )
    result = await db.execute(q)
    out = {}
    for iid, s in result.all():
        try:
            out[str(iid)] = float(s or 0)
        except (TypeError, ValueError):
            out[str(iid)] = 0.0
    return out


async def _apply_ledger_to_invoice(db: AsyncSession, inv: ProjectInvoice) -> float:
    """Синхронизация статуса счёта с суммой платежей: PAID при полной оплате, возврат к ISSUED при недоборе."""
    total = await _sum_invoice_payments(db, inv.id)
    if inv.status == "CANCELLED":
        return total
    try:
        amt = float(inv.amount or 0)
    except (TypeError, ValueError):
        amt = 0.0
    if amt > 0 and total + 1e-6 >= amt:
        inv.status = "PAID"
        if inv.paid_date is None:
            mx = await db.scalar(
                select(func.max(ProjectInvoicePayment.payment_date)).where(
                    ProjectInvoicePayment.invoice_id == inv.id
                )
            )
            inv.paid_date = mx if mx else date_cls.today()
    elif inv.status == "PAID" and amt > 0 and total + 1e-6 < amt:
        inv.status = "ISSUED"
        inv.paid_date = None
    return total


@router.get("/api/project-invoices")
async def get_project_invoices(
    project_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Список счетов по проектам (роли admin, chief_operator)."""
    await _require_finance_user(db, username)
    try:
        query = select(ProjectInvoice).order_by(ProjectInvoice.created_at.desc())
        if project_id:
            try:
                pid = uuid_lib.UUID(project_id)
            except Exception:
                raise HTTPException(status_code=400, detail="Неверный формат project_id")
            query = query.where(ProjectInvoice.project_id == pid)
        result = await db.execute(query)
        rows = result.scalars().all()
        ids = [r.id for r in rows]
        pay_map = await _invoice_payment_rows_map(db, ids)
        return {
            "items": [
                _invoice_to_item(r, pay_map.get(str(r.id), 0.0)) for r in rows
            ],
            "total": len(rows),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/project-invoices")
async def create_project_invoice(
    data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_finance_user(db, username)
    pid_raw = data.get("project_id")
    if not pid_raw:
        raise HTTPException(status_code=400, detail="Укажите project_id")
    try:
        pid = uuid_lib.UUID(str(pid_raw))
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат project_id")

    proj = (await db.execute(select(Project).where(Project.id == pid))).scalar_one_or_none()
    if not proj:
        raise HTTPException(status_code=404, detail="Проект не найден")

    amount_raw = data.get("amount")
    try:
        amount_val = float(amount_raw)
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="Некорректная сумма amount")
    if amount_val <= 0:
        raise HTTPException(status_code=400, detail="Сумма должна быть больше нуля")

    st = (data.get("status") or "DRAFT").upper()
    if st not in _INVOICE_STATUSES:
        raise HTTPException(status_code=400, detail="Недопустимый статус счёта")

    inv = ProjectInvoice(
        project_id=pid,
        invoice_number=data.get("invoice_number"),
        amount=amount_val,
        currency=(data.get("currency") or "RUB")[:10],
        status=st,
        issued_date=_parse_invoice_date(data.get("issued_date")),
        due_date=_parse_invoice_date(data.get("due_date")),
        paid_date=_parse_invoice_date(data.get("paid_date")),
        description=data.get("description"),
    )
    if inv.status == "PAID" and inv.paid_date is None:
        inv.paid_date = date_cls.today()

    try:
        db.add(inv)
        await db.commit()
        await db.refresh(inv)
        return _invoice_to_item(inv, 0.0)
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.patch("/api/project-invoices/{invoice_id}")
async def patch_project_invoice(
    invoice_id: str,
    data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_finance_user(db, username)
    try:
        iid = uuid_lib.UUID(invoice_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат идентификатора")

    inv = (await db.execute(select(ProjectInvoice).where(ProjectInvoice.id == iid))).scalar_one_or_none()
    if not inv:
        raise HTTPException(status_code=404, detail="Счёт не найден")

    if "invoice_number" in data:
        inv.invoice_number = data.get("invoice_number")
    if "description" in data:
        inv.description = data.get("description")
    if "currency" in data and data.get("currency"):
        inv.currency = str(data["currency"])[:10]
    if "amount" in data and data["amount"] is not None:
        try:
            av = float(data["amount"])
        except (TypeError, ValueError):
            raise HTTPException(status_code=400, detail="Некорректная сумма")
        if av <= 0:
            raise HTTPException(status_code=400, detail="Сумма должна быть больше нуля")
        inv.amount = av
    if "issued_date" in data:
        inv.issued_date = _parse_invoice_date(data.get("issued_date"))
    if "due_date" in data:
        inv.due_date = _parse_invoice_date(data.get("due_date"))
    if "paid_date" in data:
        inv.paid_date = _parse_invoice_date(data.get("paid_date"))

    if "status" in data and data["status"]:
        st = str(data["status"]).upper()
        if st not in _INVOICE_STATUSES:
            raise HTTPException(status_code=400, detail="Недопустимый статус счёта")
        inv.status = st
        if st == "PAID" and inv.paid_date is None:
            inv.paid_date = date_cls.today()

    try:
        await _apply_ledger_to_invoice(db, inv)
        await db.commit()
        await db.refresh(inv)
        total_p = await _sum_invoice_payments(db, inv.id)
        return _invoice_to_item(inv, total_p)
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


def _invoice_payment_to_item(p: ProjectInvoicePayment) -> dict:
    try:
        created = p.created_at.isoformat() if p.created_at else None
    except Exception:
        created = str(p.created_at) if p.created_at else None
    return {
        "id": str(p.id),
        "invoice_id": str(p.invoice_id),
        "amount": float(p.amount) if p.amount is not None else 0.0,
        "payment_date": str(p.payment_date) if p.payment_date else None,
        "note": p.note,
        "created_at": created,
    }


@router.get("/api/project-invoices/{invoice_id}/payments")
async def list_invoice_payments(
    invoice_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_finance_user(db, username)
    try:
        iid = uuid_lib.UUID(invoice_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат идентификатора")

    inv = (await db.execute(select(ProjectInvoice).where(ProjectInvoice.id == iid))).scalar_one_or_none()
    if not inv:
        raise HTTPException(status_code=404, detail="Счёт не найден")

    result = await db.execute(
        select(ProjectInvoicePayment)
        .where(ProjectInvoicePayment.invoice_id == iid)
        .order_by(ProjectInvoicePayment.payment_date.desc(), ProjectInvoicePayment.created_at.desc())
    )
    rows = result.scalars().all()
    return {"items": [_invoice_payment_to_item(p) for p in rows], "total": len(rows)}


@router.post("/api/project-invoices/{invoice_id}/payments")
async def add_invoice_payment(
    invoice_id: str,
    data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_finance_user(db, username)
    try:
        iid = uuid_lib.UUID(invoice_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат идентификатора")

    inv = (await db.execute(select(ProjectInvoice).where(ProjectInvoice.id == iid))).scalar_one_or_none()
    if not inv:
        raise HTTPException(status_code=404, detail="Счёт не найден")
    if inv.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Нельзя принять оплату по отменённому счёту")

    try:
        am = float(data.get("amount"))
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="Некорректная сумма платежа")
    if am <= 0:
        raise HTTPException(status_code=400, detail="Сумма платежа должна быть больше нуля")

    pd = _parse_invoice_date(data.get("payment_date")) or date_cls.today()
    pay = ProjectInvoicePayment(invoice_id=iid, amount=am, payment_date=pd, note=data.get("note"))

    try:
        db.add(pay)
        await db.flush()
        await _apply_ledger_to_invoice(db, inv)
        await db.commit()
        await db.refresh(pay)
        await db.refresh(inv)
        total_p = await _sum_invoice_payments(db, iid)
        return {"payment": _invoice_payment_to_item(pay), "invoice": _invoice_to_item(inv, total_p)}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/api/project-invoice-payments/{payment_id}")
async def delete_project_invoice_payment(
    payment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Удаление строки оплаты (роли admin, chief_operator)."""
    await _require_finance_user(db, username)
    try:
        pid = uuid_lib.UUID(payment_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат идентификатора")

    pay = (
        await db.execute(select(ProjectInvoicePayment).where(ProjectInvoicePayment.id == pid))
    ).scalar_one_or_none()
    if not pay:
        raise HTTPException(status_code=404, detail="Платёж не найден")

    inv = (
        await db.execute(select(ProjectInvoice).where(ProjectInvoice.id == pay.invoice_id))
    ).scalar_one_or_none()
    if not inv:
        raise HTTPException(status_code=404, detail="Счёт не найден")

    try:
        await db.delete(pay)
        await db.flush()
        await _apply_ledger_to_invoice(db, inv)
        await db.commit()
        await db.refresh(inv)
        total_p = await _sum_invoice_payments(db, inv.id)
        return {"status": "deleted", "payment_id": str(pid), "invoice": _invoice_to_item(inv, total_p)}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/api/project-invoices/{invoice_id}")
async def delete_project_invoice(
    invoice_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_admin_user(db, username)
    try:
        iid = uuid_lib.UUID(invoice_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат идентификатора")

    inv = (await db.execute(select(ProjectInvoice).where(ProjectInvoice.id == iid))).scalar_one_or_none()
    if not inv:
        raise HTTPException(status_code=404, detail="Счёт не найден")
    try:
        await db.delete(inv)
        await db.commit()
        return {"status": "deleted", "id": str(iid)}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


def _contract_amount_safe(c: ProjectContract) -> Optional[float]:
    a = getattr(c, "amount", None)
    if a is None:
        return None
    try:
        return float(a)
    except (TypeError, ValueError):
        return None


def _contract_to_item(c: ProjectContract) -> dict:
    try:
        created = c.created_at.isoformat() if c.created_at else None
    except Exception:
        created = str(c.created_at) if c.created_at else None
    try:
        updated = c.updated_at.isoformat() if c.updated_at else None
    except Exception:
        updated = str(c.updated_at) if c.updated_at else None
    return {
        "id": str(c.id),
        "project_id": str(c.project_id),
        "contract_number": c.contract_number,
        "title": c.title,
        "signed_date": str(c.signed_date) if c.signed_date else None,
        "end_date": str(c.end_date) if c.end_date else None,
        "amount": _contract_amount_safe(c),
        "status": c.status,
        "notes": c.notes,
        "created_at": created,
        "updated_at": updated,
    }


@router.get("/api/project-contracts")
async def get_project_contracts(
    project_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Договоры по проектам (роли admin, chief_operator)."""
    await _require_finance_user(db, username)
    try:
        query = select(ProjectContract).order_by(ProjectContract.created_at.desc())
        if project_id:
            try:
                pid = uuid_lib.UUID(project_id)
            except Exception:
                raise HTTPException(status_code=400, detail="Неверный формат project_id")
            query = query.where(ProjectContract.project_id == pid)
        result = await db.execute(query)
        rows = result.scalars().all()
        return {"items": [_contract_to_item(r) for r in rows], "total": len(rows)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/project-contracts")
async def create_project_contract(
    data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_finance_user(db, username)
    pid_raw = data.get("project_id")
    if not pid_raw:
        raise HTTPException(status_code=400, detail="Укажите project_id")
    try:
        pid = uuid_lib.UUID(str(pid_raw))
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат project_id")

    proj = (await db.execute(select(Project).where(Project.id == pid))).scalar_one_or_none()
    if not proj:
        raise HTTPException(status_code=404, detail="Проект не найден")

    amount_val = None
    if data.get("amount") not in (None, ""):
        try:
            amount_val = float(data["amount"])
        except (TypeError, ValueError):
            raise HTTPException(status_code=400, detail="Некорректная сумма договора")
        if amount_val < 0:
            raise HTTPException(status_code=400, detail="Сумма не может быть отрицательной")

    st = (data.get("status") or "ACTIVE").upper()
    if st not in _CONTRACT_STATUSES:
        raise HTTPException(status_code=400, detail="Недопустимый статус договора")

    row = ProjectContract(
        project_id=pid,
        contract_number=data.get("contract_number"),
        title=data.get("title"),
        signed_date=_parse_invoice_date(data.get("signed_date")),
        end_date=_parse_invoice_date(data.get("end_date")),
        amount=amount_val,
        status=st,
        notes=data.get("notes"),
    )
    try:
        db.add(row)
        await db.commit()
        await db.refresh(row)
        return _contract_to_item(row)
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.patch("/api/project-contracts/{contract_id}")
async def patch_project_contract(
    contract_id: str,
    data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_finance_user(db, username)
    try:
        cid = uuid_lib.UUID(contract_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат идентификатора")

    row = (await db.execute(select(ProjectContract).where(ProjectContract.id == cid))).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Договор не найден")

    if "contract_number" in data:
        row.contract_number = data.get("contract_number")
    if "title" in data:
        row.title = data.get("title")
    if "signed_date" in data:
        row.signed_date = _parse_invoice_date(data.get("signed_date"))
    if "end_date" in data:
        row.end_date = _parse_invoice_date(data.get("end_date"))
    if "notes" in data:
        row.notes = data.get("notes")
    if "amount" in data:
        if data["amount"] in (None, ""):
            row.amount = None
        else:
            try:
                av = float(data["amount"])
            except (TypeError, ValueError):
                raise HTTPException(status_code=400, detail="Некорректная сумма")
            if av < 0:
                raise HTTPException(status_code=400, detail="Сумма не может быть отрицательной")
            row.amount = av
    if "status" in data and data["status"]:
        st = str(data["status"]).upper()
        if st not in _CONTRACT_STATUSES:
            raise HTTPException(status_code=400, detail="Недопустимый статус договора")
        row.status = st

    try:
        await db.commit()
        await db.refresh(row)
        return _contract_to_item(row)
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/api/project-contracts/{contract_id}")
async def delete_project_contract(
    contract_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_admin_user(db, username)
    try:
        cid = uuid_lib.UUID(contract_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Неверный формат идентификатора")

    row = (await db.execute(select(ProjectContract).where(ProjectContract.id == cid))).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Договор не найден")
    try:
        await db.delete(row)
        await db.commit()
        return {"status": "deleted", "id": str(cid)}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


# ──────────────────── Equipment Resources ────────────────────

@router.get("/api/equipment-resources")
async def get_equipment_resources(
    equipment_id: Optional[str] = None, db: AsyncSession = Depends(get_db)
):
    try:
        query = select(EquipmentResource)
        if equipment_id:
            try:
                query = query.where(EquipmentResource.equipment_id == uuid_lib.UUID(equipment_id))
            except Exception:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        result = await db.execute(query.order_by(EquipmentResource.created_at.desc()))
        resources = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(r.id),
                    "equipment_id": str(r.equipment_id),
                    "remaining_resource_years": float(r.remaining_resource_years) if r.remaining_resource_years else None,
                    "resource_end_date": str(r.resource_end_date) if r.resource_end_date else None,
                    "extension_years": float(r.extension_years) if r.extension_years else None,
                    "extension_date": str(r.extension_date) if r.extension_date else None,
                    "calculation_method": r.calculation_method,
                    "calculation_data": r.calculation_data if isinstance(r.calculation_data, dict) else {},
                    "status": r.status,
                    "document_number": r.document_number,
                }
                for r in resources
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/equipment-resources")
async def create_equipment_resource(resource_data: dict, db: AsyncSession = Depends(get_db)):
    try:
        equipment_id = None
        if resource_data.get("equipment_id"):
            try:
                equipment_id = uuid_lib.UUID(resource_data["equipment_id"])
            except Exception:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")

        def _parse_date(val):
            if not val:
                return None
            try:
                return datetime.fromisoformat(val).date()
            except Exception:
                return None

        new_resource = EquipmentResource(
            equipment_id=equipment_id,
            remaining_resource_years=resource_data.get("remaining_resource_years"),
            resource_end_date=_parse_date(resource_data.get("resource_end_date")),
            extension_years=resource_data.get("extension_years"),
            extension_date=_parse_date(resource_data.get("extension_date")),
            calculation_method=resource_data.get("calculation_method"),
            calculation_data=resource_data.get("calculation_data", {}),
            document_number=resource_data.get("document_number"),
            status=resource_data.get("status", "ACTIVE"),
        )
        db.add(new_resource)
        await db.commit()
        await db.refresh(new_resource)
        return {"id": str(new_resource.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


# ──────────────────── Regulatory Documents ────────────────────

@router.get("/api/regulatory-documents")
async def get_regulatory_documents(
    document_type: Optional[str] = None,
    equipment_type: Optional[str] = None,
    q: Optional[str] = None,
    limit: int = 500,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
):
    """Справочник НД с поиском и фильтрацией (тип документа, тип оборудования в JSON)."""
    try:
        query = select(RegulatoryDocument).where(RegulatoryDocument.is_active == True)
        if document_type:
            query = query.where(RegulatoryDocument.document_type == document_type)
        if q and q.strip():
            term = f"%{q.strip()}%"
            query = query.where(
                or_(
                    RegulatoryDocument.name.ilike(term),
                    RegulatoryDocument.number.ilike(term),
                    RegulatoryDocument.description.ilike(term),
                )
            )
        if equipment_type and equipment_type.strip():
            et = equipment_type.strip()
            query = query.where(RegulatoryDocument.equipment_types.contains([et]))
        eff_limit = max(1, min(limit, 1000))
        eff_offset = max(0, offset)
        query = query.order_by(
            RegulatoryDocument.document_type.asc(),
            RegulatoryDocument.number.asc().nulls_last(),
            RegulatoryDocument.name.asc(),
        ).offset(eff_offset).limit(eff_limit)
        result = await db.execute(query)
        docs = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(d.id),
                    "document_type": d.document_type,
                    "number": d.number,
                    "name": d.name,
                    "description": d.description,
                    "equipment_types": d.equipment_types,
                    "requirements": d.requirements if isinstance(d.requirements, dict) else {},
                    "effective_date": str(d.effective_date) if d.effective_date else None,
                    "expiry_date": str(d.expiry_date) if d.expiry_date else None,
                    "has_file": bool(d.file_path),
                    "file_name": FsPath(d.file_path).name if d.file_path else None,
                }
                for d in docs
            ],
            "total_returned": len(docs),
            "limit": eff_limit,
            "offset": eff_offset,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/regulatory-documents")
async def create_regulatory_document(
    doc_data: dict,
    db: AsyncSession = Depends(get_db),
    username: str = Depends(verify_token),
):
    try:
        new_doc = RegulatoryDocument(
            document_type=doc_data.get("document_type"),
            number=doc_data.get("number"),
            name=doc_data.get("name"),
            description=doc_data.get("description"),
            content=doc_data.get("content"),
            file_path=doc_data.get("file_path"),
            equipment_types=doc_data.get("equipment_types", []),
            requirements=doc_data.get("requirements", {}),
            effective_date=datetime.fromisoformat(doc_data["effective_date"]).date() if doc_data.get("effective_date") else None,
            expiry_date=datetime.fromisoformat(doc_data["expiry_date"]).date() if doc_data.get("expiry_date") else None,
        )
        db.add(new_doc)
        await db.commit()
        await db.refresh(new_doc)
        return {"id": str(new_doc.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/regulatory-documents/upload")
async def upload_regulatory_document(
    file: UploadFile = File(...),
    document_type: str = Form("OTHER"),
    number: str = Form(""),
    name: str = Form(""),
    description: str = Form(""),
    db: AsyncSession = Depends(get_db),
    username: str = Depends(verify_token),
):
    """Загрузка нормативного документа (PDF или DOCX) с метаданными."""
    filename = (file.filename or "").strip()
    if not filename:
        raise HTTPException(status_code=400, detail="Не указано имя файла")
    ext = FsPath(filename).suffix.lower()
    if ext not in (".pdf", ".docx", ".doc"):
        raise HTTPException(
            status_code=400,
            detail="Допустимы только файлы PDF, DOC или DOCX",
        )
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Пустой файл")
    if len(content) > 40 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Файл больше 40 МБ")

    upload_dir = FsPath("/app/uploads/regulatory_documents")
    upload_dir.mkdir(parents=True, exist_ok=True)
    safe_stem = "".join(c if c.isalnum() or c in "-_." else "_" for c in FsPath(filename).stem)[:80]
    stored_name = f"{uuid_lib.uuid4().hex}_{safe_stem}{ext}"
    dest = upload_dir / stored_name
    dest.write_bytes(content)

    display_name = (name or "").strip() or FsPath(filename).stem
    new_doc = RegulatoryDocument(
        document_type=(document_type or "OTHER").strip().upper() or "OTHER",
        number=(number or "").strip() or None,
        name=display_name,
        description=(description or "").strip() or None,
        file_path=str(dest),
        equipment_types=[],
        requirements={},
    )
    db.add(new_doc)
    await db.commit()
    await db.refresh(new_doc)
    return {
        "id": str(new_doc.id),
        "status": "created",
        "name": new_doc.name,
        "file_name": filename,
        "has_file": True,
    }


@router.get("/api/regulatory-documents/{doc_id}/download")
async def download_regulatory_document(
    doc_id: str,
    db: AsyncSession = Depends(get_db),
    username: str = Depends(verify_token),
):
    result = await db.execute(
        select(RegulatoryDocument).where(RegulatoryDocument.id == doc_id)
    )
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Документ не найден")
    if not doc.file_path:
        raise HTTPException(status_code=404, detail="Файл не прикреплён")
    path = FsPath(doc.file_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Файл отсутствует на сервере")
    media = "application/pdf" if path.suffix.lower() == ".pdf" else (
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        if path.suffix.lower() == ".docx"
        else "application/msword"
    )
    return FileResponse(
        path,
        media_type=media,
        filename=f"{doc.number or doc.name}{path.suffix}",
    )
