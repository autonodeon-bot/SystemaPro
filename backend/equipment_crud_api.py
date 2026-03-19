"""CRUD operations for Equipment."""

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text, or_
from typing import Optional
from pydantic import BaseModel
from datetime import datetime
import uuid as uuid_lib
import os

from database import get_db
from auth import verify_token
from models import (
    Equipment, EquipmentType, User, Workshop, Branch, Enterprise, Opo,
    UserEquipmentAccess, HierarchyEngineerAssignment,
)

router = APIRouter(tags=["equipment"])


class EquipmentCreate(BaseModel):
    name: str
    type_id: Optional[str] = None
    serial_number: Optional[str] = None
    location: Optional[str] = None
    workshop_id: Optional[str] = None
    opo_id: Optional[str] = None
    commissioning_date: Optional[str] = None
    attributes: Optional[dict] = None


class EquipmentUpdate(BaseModel):
    name: Optional[str] = None
    type_id: Optional[str] = None
    serial_number: Optional[str] = None
    location: Optional[str] = None
    opo_id: Optional[str] = None
    commissioning_date: Optional[str] = None
    attributes: Optional[dict] = None


@router.get("/api/equipment")
async def get_equipment(
    skip: int = 0,
    offset: int = 0,
    limit: int = 100,
    workshop_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Получить список оборудования с пагинацией (limit макс. 1000).

    Параметры offset и skip взаимозаменяемы (offset приоритетнее).
    """
    try:
        effective_offset = offset if offset > 0 else skip
        effective_limit = min(limit, 1000)

        user_result = await db.execute(
            select(User).where(or_(User.username == username, User.email == username))
        )
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")

        if user.role == "engineer":
            hierarchy_result = await db.execute(
                text("""
                    SELECT enterprise_id, branch_id, workshop_id,
                           equipment_type_id, equipment_id
                    FROM hierarchy_engineer_assignments
                    WHERE user_id = CAST(:user_id AS uuid)
                      AND is_active = 1
                      AND (expires_at IS NULL OR expires_at > NOW())
                """),
                {"user_id": str(user.id)},
            )
            hierarchy_assignments = hierarchy_result.all()

            direct_access_result = await db.execute(
                text("""
                    SELECT equipment_id
                    FROM user_equipment_access
                    WHERE user_id = CAST(:user_id AS uuid)
                      AND is_active = 1
                      AND (expires_at IS NULL OR expires_at > NOW())
                """),
                {"user_id": str(user.id)},
            )
            direct_equipment_ids = [row[0] for row in direct_access_result.all()]

            accessible_equipment_ids = set(direct_equipment_ids)
            enterprise_ids, branch_ids, workshop_ids_list, equipment_type_ids = [], [], [], []
            direct_equipment_from_hierarchy = []

            for a in hierarchy_assignments:
                if a[0]:
                    enterprise_ids.append(a[0])
                if a[1]:
                    branch_ids.append(a[1])
                if a[2]:
                    workshop_ids_list.append(a[2])
                if a[3]:
                    equipment_type_ids.append(a[3])
                if a[4]:
                    direct_equipment_from_hierarchy.append(a[4])

            query = select(Equipment)
            conditions = []

            if direct_equipment_from_hierarchy:
                accessible_equipment_ids.update(direct_equipment_from_hierarchy)

            if workshop_ids_list:
                conditions.append(Equipment.workshop_id.in_(workshop_ids_list))

            if branch_ids:
                workshop_result = await db.execute(
                    select(Workshop.id).where(Workshop.branch_id.in_(branch_ids))
                )
                ws_from_branches = [w[0] for w in workshop_result.all()]
                if ws_from_branches:
                    conditions.append(Equipment.workshop_id.in_(ws_from_branches))

            if enterprise_ids:
                branch_result = await db.execute(
                    select(Branch.id).where(Branch.enterprise_id.in_(enterprise_ids))
                )
                br_from_ent = [b[0] for b in branch_result.all()]
                if br_from_ent:
                    ws_result = await db.execute(
                        select(Workshop.id).where(Workshop.branch_id.in_(br_from_ent))
                    )
                    ws_from_ent = [w[0] for w in ws_result.all()]
                    if ws_from_ent:
                        conditions.append(Equipment.workshop_id.in_(ws_from_ent))

            if equipment_type_ids:
                conditions.append(Equipment.type_id.in_(equipment_type_ids))

            if accessible_equipment_ids:
                conditions.append(Equipment.id.in_(list(accessible_equipment_ids)))

            if conditions:
                query = query.where(or_(*conditions))
                result = await db.execute(query.offset(effective_offset).limit(effective_limit))
                equipment = result.scalars().all()
            else:
                equipment = []
        else:
            query = select(Equipment)
            if workshop_id:
                try:
                    workshop_uuid = uuid_lib.UUID(workshop_id)
                    query = query.where(Equipment.workshop_id == workshop_uuid)
                except ValueError:
                    raise HTTPException(status_code=400, detail="Неверный формат workshop_id")
            result = await db.execute(query.offset(effective_offset).limit(effective_limit))
            equipment = result.scalars().all()

        equipment_items = []
        for eq in equipment:
            item = {
                "id": str(eq.id),
                "equipment_code": getattr(eq, "equipment_code", None),
                "name": eq.name,
                "type_id": str(eq.type_id) if eq.type_id else None,
                "serial_number": eq.serial_number,
                "location": eq.location,
                "attributes": eq.attributes or {},
                "commissioning_date": str(eq.commissioning_date) if eq.commissioning_date else None,
                "created_at": str(eq.created_at) if eq.created_at else None,
                "workshop_id": str(eq.workshop_id) if eq.workshop_id else None,
                "opo_id": str(eq.opo_id) if getattr(eq, "opo_id", None) else None,
            }

            if eq.workshop_id:
                ws_r = await db.execute(select(Workshop).where(Workshop.id == eq.workshop_id))
                ws = ws_r.scalar_one_or_none()
                if ws:
                    item["workshop_name"] = ws.name
                    item["workshop_code"] = ws.code
                    br_r = await db.execute(select(Branch).where(Branch.id == ws.branch_id))
                    br = br_r.scalar_one_or_none()
                    if br:
                        item["branch_id"] = str(br.id)
                        item["branch_name"] = br.name
                        item["branch_code"] = br.code
                        ent_r = await db.execute(select(Enterprise).where(Enterprise.id == br.enterprise_id))
                        ent = ent_r.scalar_one_or_none()
                        if ent:
                            item["enterprise_id"] = str(ent.id)
                            item["enterprise_name"] = ent.name
                            item["enterprise_code"] = ent.code

            if eq.type_id:
                type_r = await db.execute(select(EquipmentType).where(EquipmentType.id == eq.type_id))
                et = type_r.scalar_one_or_none()
                if et:
                    item["type_name"] = et.name
                    item["type_code"] = et.code

            if getattr(eq, "opo_id", None):
                opo_r = await db.execute(select(Opo).where(Opo.id == eq.opo_id))
                opo = opo_r.scalar_one_or_none()
                if opo:
                    item["opo_name"] = opo.name
                    item["opo_code"] = opo.code

            equipment_items.append(item)

        return {"items": equipment_items, "total": len(equipment)}
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@router.get("/api/equipment/{equipment_id}")
async def get_equipment_by_id(equipment_id: str, db: AsyncSession = Depends(get_db)):
    try:
        result = await db.execute(select(Equipment).where(Equipment.id == equipment_id))
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        return {
            "id": str(eq.id),
            "name": eq.name,
            "type_id": str(eq.type_id) if eq.type_id else None,
            "serial_number": eq.serial_number,
            "location": eq.location,
            "attributes": eq.attributes or {},
            "commissioning_date": str(eq.commissioning_date) if eq.commissioning_date else None,
            "created_at": str(eq.created_at) if eq.created_at else None,
            "opo_id": str(eq.opo_id) if getattr(eq, "opo_id", None) else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/equipment/{equipment_id}/photos")
async def get_equipment_object_photos(equipment_id: str, db: AsyncSession = Depends(get_db)):
    try:
        result = await db.execute(select(Equipment).where(Equipment.id == equipment_id))
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        attrs = eq.attributes or {}
        photos = attrs.get("object_photos") if isinstance(attrs, dict) else []
        if not isinstance(photos, list):
            photos = []
        items = []
        for idx, p in enumerate(photos):
            ps = str(p or "").strip()
            if not ps:
                continue
            items.append({
                "index": idx,
                "path": ps,
                "view_url": f"/api/equipment/{equipment_id}/photos/{idx}",
                "file_name": os.path.basename(ps),
            })
        return {"equipment_id": equipment_id, "items": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/equipment/{equipment_id}/photos/{photo_index}")
async def view_equipment_object_photo(
    equipment_id: str, photo_index: int, db: AsyncSession = Depends(get_db)
):
    try:
        result = await db.execute(select(Equipment).where(Equipment.id == equipment_id))
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        attrs = eq.attributes or {}
        photos = attrs.get("object_photos") if isinstance(attrs, dict) else []
        if not isinstance(photos, list):
            photos = []
        if photo_index < 0 or photo_index >= len(photos):
            raise HTTPException(status_code=404, detail="Photo not found")
        target = str(photos[photo_index] or "").strip()
        if not target:
            raise HTTPException(status_code=404, detail="Photo path is empty")
        if not os.path.exists(target):
            raise HTTPException(status_code=404, detail="Photo file not found")
        return FileResponse(target)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/equipment")
async def create_equipment(equipment_data: EquipmentCreate, db: AsyncSession = Depends(get_db)):
    try:
        commissioning_date = None
        if equipment_data.commissioning_date:
            try:
                commissioning_date = datetime.fromisoformat(
                    equipment_data.commissioning_date.replace("Z", "+00:00")
                ).date()
            except Exception:
                pass

        type_id = None
        if equipment_data.type_id:
            try:
                type_id = uuid_lib.UUID(equipment_data.type_id)
            except Exception:
                pass

        workshop_id_uuid = None
        if equipment_data.workshop_id:
            try:
                workshop_id_uuid = uuid_lib.UUID(equipment_data.workshop_id)
            except Exception:
                pass

        opo_id_uuid = None
        if equipment_data.opo_id:
            try:
                opo_id_uuid = uuid_lib.UUID(equipment_data.opo_id)
            except Exception:
                pass

        new_equipment = Equipment(
            name=equipment_data.name,
            type_id=type_id,
            serial_number=equipment_data.serial_number,
            location=equipment_data.location,
            workshop_id=workshop_id_uuid,
            opo_id=opo_id_uuid,
            commissioning_date=commissioning_date,
            attributes=equipment_data.attributes or {},
        )
        db.add(new_equipment)
        await db.commit()
        await db.refresh(new_equipment)
        return {
            "id": str(new_equipment.id),
            "name": new_equipment.name,
            "type_id": str(new_equipment.type_id) if new_equipment.type_id else None,
            "serial_number": new_equipment.serial_number,
            "location": new_equipment.location,
            "attributes": new_equipment.attributes or {},
            "opo_id": str(new_equipment.opo_id) if getattr(new_equipment, "opo_id", None) else None,
            "status": "created",
        }
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create equipment: {str(e)}")


@router.put("/api/equipment/{equipment_id}")
async def update_equipment(
    equipment_id: str, equipment_data: EquipmentUpdate, db: AsyncSession = Depends(get_db)
):
    try:
        result = await db.execute(select(Equipment).where(Equipment.id == equipment_id))
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")

        if equipment_data.name is not None:
            eq.name = equipment_data.name
        if equipment_data.serial_number is not None:
            eq.serial_number = equipment_data.serial_number
        if equipment_data.location is not None:
            eq.location = equipment_data.location
        if equipment_data.opo_id is not None:
            try:
                eq.opo_id = uuid_lib.UUID(equipment_data.opo_id) if equipment_data.opo_id else None
            except Exception:
                pass
        if equipment_data.attributes is not None:
            eq.attributes = equipment_data.attributes
        if equipment_data.commissioning_date is not None:
            try:
                eq.commissioning_date = datetime.fromisoformat(
                    equipment_data.commissioning_date.replace("Z", "+00:00")
                ).date()
            except Exception:
                pass
        if equipment_data.type_id is not None:
            try:
                eq.type_id = uuid_lib.UUID(equipment_data.type_id)
            except Exception:
                pass

        await db.commit()
        await db.refresh(eq)
        return {
            "id": str(eq.id),
            "name": eq.name,
            "type_id": str(eq.type_id) if eq.type_id else None,
            "serial_number": eq.serial_number,
            "location": eq.location,
            "attributes": eq.attributes or {},
            "opo_id": str(eq.opo_id) if getattr(eq, "opo_id", None) else None,
            "status": "updated",
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update equipment: {str(e)}")


@router.delete("/api/equipment/{equipment_id}")
async def delete_equipment(equipment_id: str, db: AsyncSession = Depends(get_db)):
    try:
        result = await db.execute(select(Equipment).where(Equipment.id == equipment_id))
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        await db.delete(eq)
        await db.commit()
        return {"status": "deleted", "id": equipment_id}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete equipment: {str(e)}")
