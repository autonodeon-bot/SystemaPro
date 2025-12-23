"""
API endpoints для управления доступом к оборудованию
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func, text
from sqlalchemy.orm import selectinload
import uuid as uuid_lib
from datetime import datetime, timedelta
from typing import Optional, List
from database import get_db
from models import User, Equipment, UserEquipmentAccess
from auth import verify_token

router = APIRouter(prefix="/api/access", tags=["access"])

def check_access_management_permission(user_role: str):
    """Проверка права на управление доступом"""
    if user_role not in ["admin", "chief_operator", "operator"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для управления доступом"
        )

@router.post("/users/{user_id}/equipment")
async def grant_equipment_access(
    user_id: str,
    equipment_ids: List[str],
    access_type: str = "read_write",
    expires_at: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Предоставить доступ к оборудованию пользователю"""
    try:
        # Проверяем права текущего пользователя
        current_user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = current_user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="Current user not found")
        
        check_access_management_permission(current_user.role)
        
        # Проверяем существование пользователя
        target_user_result = await db.execute(
            select(User).where(User.id == uuid_lib.UUID(user_id))
        )
        target_user = target_user_result.scalar_one_or_none()
        if not target_user:
            raise HTTPException(status_code=404, detail="Target user not found")
        
        # Проверяем, что это инженер
        if target_user.role != "engineer":
            raise HTTPException(
                status_code=400,
                detail="Доступ можно предоставлять только инженерам"
            )
        
        # Парсим дату истечения
        expires_date = None
        if expires_at:
            try:
                expires_date = datetime.fromisoformat(expires_at.replace('Z', '+00:00'))
            except:
                pass
        
        granted_count = 0
        for equipment_id in equipment_ids:
            try:
                equipment_uuid = uuid_lib.UUID(equipment_id)
                
                # Проверяем существование оборудования
                equipment_result = await db.execute(
                    select(Equipment).where(Equipment.id == equipment_uuid)
                )
                if not equipment_result.scalar_one_or_none():
                    continue
                
                # Проверяем, не существует ли уже активный доступ
                existing_result = await db.execute(
                    select(UserEquipmentAccess).where(
                        and_(
                            UserEquipmentAccess.user_id == target_user.id,
                            UserEquipmentAccess.equipment_id == equipment_uuid,
                            text("user_equipment_access.is_active = 1")
                        )
                    )
                )
                existing = existing_result.scalar_one_or_none()
                
                if existing:
                    # Обновляем существующий доступ
                    existing.access_type = access_type
                    existing.granted_by = current_user.id
                    existing.granted_at = datetime.now()
                    if expires_date:
                        existing.expires_at = expires_date
                    existing.is_active = 1
                else:
                    # Создаем новый доступ
                    new_access = UserEquipmentAccess(
                        user_id=target_user.id,
                        equipment_id=equipment_uuid,
                        access_type=access_type,
                        granted_by=current_user.id,
                        expires_at=expires_date,
                        is_active=1
                    )
                    db.add(new_access)
                
                granted_count += 1
            except ValueError:
                continue
        
        await db.commit()
        
        return {
            "message": f"Доступ предоставлен к {granted_count} единицам оборудования",
            "granted_count": granted_count,
            "total_requested": len(equipment_ids)
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to grant access: {str(e)}")

@router.delete("/users/{user_id}/equipment/{equipment_id}")
async def revoke_equipment_access(
    user_id: str,
    equipment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Отозвать доступ к оборудованию"""
    try:
        # Проверяем права текущего пользователя
        current_user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = current_user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="Current user not found")
        
        check_access_management_permission(current_user.role)
        
        # Находим и деактивируем доступ
        access_result = await db.execute(
            select(UserEquipmentAccess).where(
                and_(
                    UserEquipmentAccess.user_id == uuid_lib.UUID(user_id),
                    UserEquipmentAccess.equipment_id == uuid_lib.UUID(equipment_id),
                    text("user_equipment_access.is_active = 1")
                )
            )
        )
        access = access_result.scalar_one_or_none()
        
        if not access:
            raise HTTPException(status_code=404, detail="Access not found")
        
        access.is_active = 0
        await db.commit()
        
        return {"message": "Доступ отозван"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to revoke access: {str(e)}")

@router.get("/users/{user_id}/equipment")
async def get_user_equipment_access(
    user_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список оборудования, к которому у пользователя есть доступ"""
    try:
        # Проверяем права
        current_user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = current_user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="Current user not found")
        
        # Пользователь может видеть только свой доступ, если он инженер
        # Или если у него есть права на управление доступом
        target_user_id = uuid_lib.UUID(user_id)
        if current_user.role == "engineer" and current_user.id != target_user_id:
            raise HTTPException(
                status_code=403,
                detail="Недостаточно прав для просмотра доступа других пользователей"
            )
        
        # Получаем доступ
        access_result = await db.execute(
            select(UserEquipmentAccess, Equipment)
            .join(Equipment, UserEquipmentAccess.equipment_id == Equipment.id)
            .where(
                and_(
                    UserEquipmentAccess.user_id == target_user_id,
                    text("user_equipment_access.is_active = 1"),
                    or_(
                        UserEquipmentAccess.expires_at.is_(None),
                        UserEquipmentAccess.expires_at > func.now()
                    )
                )
            )
        )
        
        access_list = []
        for access, equipment in access_result.all():
            access_list.append({
                "equipment_id": str(equipment.id),
                "equipment_name": equipment.name,
                "equipment_location": equipment.location,
                "access_type": access.access_type,
                "granted_at": access.granted_at.isoformat() if access.granted_at else None,
                "expires_at": access.expires_at.isoformat() if access.expires_at else None,
            })
        
        return {"items": access_list, "total": len(access_list)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get access: {str(e)}")

@router.post("/users/{user_id}/equipment/bulk")
async def grant_bulk_equipment_access(
    user_id: str,
    request_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Массовое предоставление доступа к оборудованию по фильтрам"""
    try:
        # Проверяем права
        current_user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = current_user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="Current user not found")
        
        check_access_management_permission(current_user.role)
        
        # Получаем фильтры
        location_filter = request_data.get("location")  # НГДУ, цех
        enterprise_filter = request_data.get("enterprise")  # Предприятие
        access_type = request_data.get("access_type", "read_write")
        expires_at = request_data.get("expires_at")
        
        # Строим запрос для поиска оборудования
        equipment_query = select(Equipment)
        
        if location_filter:
            equipment_query = equipment_query.where(
                Equipment.location.contains(location_filter)
            )
        
        if enterprise_filter:
            equipment_query = equipment_query.where(
                Equipment.location.startswith(enterprise_filter)
            )
        
        equipment_result = await db.execute(equipment_query)
        equipment_list = equipment_result.scalars().all()
        
        if not equipment_list:
            return {
                "message": "Оборудование по указанным фильтрам не найдено",
                "granted_count": 0
            }
        
        # Предоставляем доступ ко всему найденному оборудованию
        equipment_ids = [str(eq.id) for eq in equipment_list]
        
        return await grant_equipment_access(
            user_id=user_id,
            equipment_ids=equipment_ids,
            access_type=access_type,
            expires_at=expires_at,
            username=username,
            db=db
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to grant bulk access: {str(e)}")

