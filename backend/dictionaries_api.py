"""Справочники: типы оборудования, трубопроводы, ресурсы, нормативные документы, клиенты, проекты."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import date as date_cls

from sqlalchemy import case, distinct, func, select
from typing import Optional
from datetime import datetime
import uuid as uuid_lib

from database import get_db
from auth import verify_token
from models import (
    Assignment,
    EquipmentType,
    PipelineSegment,
    EquipmentResource,
    RegulatoryDocument,
    Client,
    Project,
    User,
    Inspection,
    Report,
    Questionnaire,
)
from shared import cache_get, cache_set, cache_invalidate

router = APIRouter(tags=["dictionaries"])


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
    db: AsyncSession = Depends(get_db),
):
    try:
        query = select(RegulatoryDocument).where(RegulatoryDocument.is_active == True)
        if document_type:
            query = query.where(RegulatoryDocument.document_type == document_type)
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
                    "effective_date": str(d.effective_date) if d.effective_date else None,
                    "expiry_date": str(d.expiry_date) if d.expiry_date else None,
                }
                for d in docs
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/regulatory-documents")
async def create_regulatory_document(doc_data: dict, db: AsyncSession = Depends(get_db)):
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
