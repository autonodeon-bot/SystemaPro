"""
Эндпоинты для offline-first режима
POST /api/v1/offline/package - получение зашифрованного offline-пакета
POST /api/v1/offline/sync - синхронизация инспекций и файлов
"""
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text, func, or_
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field
from datetime import datetime, timedelta
import uuid as uuid_lib
import json
import logging

from database import get_db
from models import (
    User as UserModel, Equipment, Inspection, OfflineTask, EquipmentType,
    Workshop, Branch, Client, SyncHistory
)
from auth import verify_token, check_equipment_access, get_user_accessible_equipment_ids
from offline_encryption import encrypt_offline_package, hash_offline_pin

router = APIRouter(prefix="/api/v1/offline", tags=["offline"])
logger = logging.getLogger(__name__)


# Pydantic модели для запросов/ответов
class OfflinePackageRequest(BaseModel):
    """Запрос на создание offline-пакета"""
    name: str = Field(..., description="Название задания")
    equipment_ids: List[str] = Field(..., description="Список ID оборудования")
    offline_pin: str = Field(..., min_length=6, max_length=8, description="Офлайн-PIN пользователя (6-8 цифр)")


class InspectionSyncItem(BaseModel):
    """Элемент инспекции для синхронизации"""
    client_id: str = Field(..., description="Локальный UUID с мобильного устройства")
    equipment_id: str
    data: Dict[str, Any]
    conclusion: Optional[str] = None
    date_performed: Optional[str] = None
    status: str = "DRAFT"
    offline_task_id: Optional[str] = None


class SyncRequest(BaseModel):
    """Запрос на синхронизацию"""
    inspections: List[InspectionSyncItem] = Field(..., description="Список инспекций для синхронизации")
    offline_pin: str = Field(..., min_length=6, max_length=8, description="Офлайн-PIN для проверки")


@router.post("/package")
async def create_offline_package(
    request: OfflinePackageRequest,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """
    Создать и вернуть зашифрованный offline-пакет для конкретного задания
    
    Проверяет права пользователя на каждый equipment_id и возвращает:
    - Оборудование с доступом
    - Схемы форм (JSON Schema)
    - Справочники
    - Существующие инспекции (status != APPROVED)
    
    Весь пакет шифруется AES-256-GCM с ключом от хэша офлайн-PIN
    """
    try:
        # Проверяем, что пользователь - инженер (или имеет права)
        if user.role not in ["engineer", "admin", "chief_operator", "operator"]:
            raise HTTPException(
                status_code=403,
                detail="Только инженеры могут создавать offline-пакеты"
            )
        
        # Получаем список доступного оборудования пользователя
        accessible_equipment_ids = await get_user_accessible_equipment_ids(db, user)
        
        # Фильтруем equipment_ids - оставляем только те, к которым есть доступ
        valid_equipment_ids = []
        invalid_equipment_ids = []
        
        for eq_id_str in request.equipment_ids:
            try:
                eq_uuid = uuid_lib.UUID(eq_id_str)
                # Проверяем доступ
                if eq_id_str in accessible_equipment_ids:
                    valid_equipment_ids.append(eq_id_str)
                else:
                    invalid_equipment_ids.append(eq_id_str)
            except ValueError:
                invalid_equipment_ids.append(eq_id_str)
        
        if not valid_equipment_ids:
            raise HTTPException(
                status_code=403,
                detail="Нет доступа ни к одному из указанного оборудования"
            )
        
        # Получаем данные оборудования
        equipment_list = []
        equipment_uuids = [uuid_lib.UUID(eid) for eid in valid_equipment_ids]
        
        result = await db.execute(
            select(Equipment).where(Equipment.id.in_(equipment_uuids))
        )
        equipment_items = result.scalars().all()
        
        for eq in equipment_items:
            equipment_list.append({
                "id": str(eq.id),
                "name": eq.name,
                "serial_number": eq.serial_number,
                "location": eq.location,
                "type_id": str(eq.type_id) if eq.type_id else None,
                "attributes": eq.attributes or {},
            })
        
        # Получаем типы оборудования для схем форм
        type_ids = [eq.type_id for eq in equipment_items if eq.type_id]
        equipment_types = []
        if type_ids:
            type_result = await db.execute(
                select(EquipmentType).where(EquipmentType.id.in_(type_ids))
            )
            for eq_type in type_result.scalars().all():
                equipment_types.append({
                    "id": str(eq_type.id),
                    "name": eq_type.name,
                    "code": eq_type.code,
                    "description": eq_type.description,
                })
        
        # Получаем существующие инспекции (status != APPROVED)
        inspections_result = await db.execute(
            select(Inspection).where(
                Inspection.equipment_id.in_(equipment_uuids),
                Inspection.status != "APPROVED"
            ).order_by(Inspection.created_at.desc())
        )
        inspections = []
        for insp in inspections_result.scalars().all():
            inspections.append({
                "id": str(insp.id),
                "equipment_id": str(insp.equipment_id),
                "inspector_id": str(insp.inspector_id) if insp.inspector_id else None,
                "date_performed": insp.date_performed.isoformat() if insp.date_performed else None,
                "data": insp.data,
                "conclusion": insp.conclusion,
                "status": insp.status,
                "created_at": insp.created_at.isoformat() if insp.created_at else None,
            })
        
        # Создаем offline-задание
        offline_task = OfflineTask(
            user_id=user.id,
            name=request.name,
            equipment_ids=valid_equipment_ids,
            downloaded_at=None,  # Будет обновлено после скачивания
        )
        db.add(offline_task)
        await db.commit()
        await db.refresh(offline_task)
        
        # Получаем справочники
        dictionaries = await _get_dictionaries(db)
        
        # Формируем пакет данных
        package_data = {
            "task_id": str(offline_task.id),
            "task_name": request.name,
            "created_at": datetime.utcnow().isoformat(),
            "expires_at": offline_task.expires_at.isoformat() if offline_task.expires_at else None,
            "equipment": equipment_list,
            "equipment_types": equipment_types,
            "inspections": inspections,
            "schemas": _get_equipment_schemas(equipment_types),  # Схемы форм из EquipmentType
            "dictionaries": dictionaries  # Справочники
        }
        
        # Шифруем пакет
        package_json = json.dumps(package_data, ensure_ascii=False)
        encrypted_package = encrypt_offline_package(
            package_json.encode('utf-8'),
            request.offline_pin
        )
        
        # Сохраняем хеш PIN на сервере (для проверки при синхронизации)
        pin_hash = hash_offline_pin(request.offline_pin)
        user.offline_pin_hash = pin_hash
        await db.commit()
        
        # Возвращаем зашифрованный пакет
        return {
            "task_id": str(offline_task.id),
            "encrypted_package": encrypted_package,
            "equipment_count": len(equipment_list),
            "inspections_count": len(inspections),
            "invalid_equipment_ids": invalid_equipment_ids,  # Для информации
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Ошибка при создании offline-пакета: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка при создании offline-пакета: {str(e)}"
        )


@router.post("/sync")
async def sync_offline_data(
    request: SyncRequest,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """
    Синхронизировать инспекции и файлы с сервера
    
    Обязательные проверки:
    0. Только инженеры могут синхронизировать
    1. Проверка офлайн-PIN (сравнение хеша)
    2. Проверка прав на каждый equipment_id из JWT
    3. Если хотя бы один equipment_id не принадлежит пользователю → 403 + лог в аудит
    
    После успешной синхронизации:
    - Обновить is_synced = true
    - Обновить synced_at
    - Сохранить inspector_id (автор отчета)
    - Записать в историю синхронизаций
    - Вернуть список синхронизированных ID
    """
    try:
        # 0. Проверка роли - только инженеры могут синхронизировать
        if user.role != 'engineer':
            logger.warning(
                f"Попытка синхронизации пользователем с ролью {user.role} (ID: {user.id}, username: {user.username})"
            )
            raise HTTPException(
                status_code=403,
                detail="Синхронизация доступна только инженерам"
            )
        
        # 1. Проверка офлайн-PIN
        if not user.offline_pin_hash:
            raise HTTPException(
                status_code=400,
                detail="Офлайн-PIN не установлен. Сначала создайте offline-пакет."
            )
        
        pin_hash = hash_offline_pin(request.offline_pin)
        if pin_hash != user.offline_pin_hash:
            # Логируем попытку неверного PIN
            logger.warning(
                f"Попытка синхронизации с неверным PIN для пользователя {user.username} (ID: {user.id})"
            )
            raise HTTPException(
                status_code=403,
                detail="Неверный офлайн-PIN"
            )
        
        # 2. Получаем список доступного оборудования пользователя
        accessible_equipment_ids = await get_user_accessible_equipment_ids(db, user)
        accessible_equipment_set = set(accessible_equipment_ids)
        
        # 3. Проверяем права на каждое equipment_id из запроса
        invalid_equipment_ids = []
        valid_inspections = []
        
        for inspection_item in request.inspections:
            if inspection_item.equipment_id not in accessible_equipment_set:
                invalid_equipment_ids.append(inspection_item.equipment_id)
            else:
                valid_inspections.append(inspection_item)
        
        # 4. Если есть недопустимые equipment_id - возвращаем 403
        if invalid_equipment_ids:
            # Логируем попытку доступа к чужому оборудованию
            logger.error(
                f"Попытка синхронизации с недопустимыми equipment_id для пользователя {user.username} (ID: {user.id}): {invalid_equipment_ids}"
            )
            raise HTTPException(
                status_code=403,
                detail=f"Доступ запрещен к следующему оборудованию: {', '.join(invalid_equipment_ids)}"
            )
        
        # 5. Синхронизируем каждую инспекцию
        synced_ids = []
        failed_ids = []
        
        for inspection_item in valid_inspections:
            try:
                # Проверяем, не существует ли уже инспекция с таким client_id
                existing_result = await db.execute(
                    select(Inspection).where(
                        Inspection.client_id == uuid_lib.UUID(inspection_item.client_id)
                    )
                )
                existing = existing_result.scalar_one_or_none()
                
                if existing:
                    # Обновляем существующую инспекцию
                    existing.equipment_id = uuid_lib.UUID(inspection_item.equipment_id)
                    existing.data = inspection_item.data
                    existing.conclusion = inspection_item.conclusion
                    existing.status = inspection_item.status
                    existing.inspector_id = user.id  # Обновляем автора (инженера, который синхронизировал)
                    if inspection_item.date_performed:
                        existing.date_performed = datetime.fromisoformat(
                            inspection_item.date_performed.replace('Z', '+00:00')
                        )
                    existing.is_synced = True
                    existing.synced_at = datetime.utcnow()
                    if inspection_item.offline_task_id:
                        existing.offline_task_id = uuid_lib.UUID(inspection_item.offline_task_id)
                    
                    synced_ids.append(str(existing.id))
                else:
                    # Создаем новую инспекцию
                    new_inspection = Inspection(
                        id=uuid_lib.uuid4(),  # Генерируем новый UUID на сервере
                        client_id=uuid_lib.UUID(inspection_item.client_id),  # Сохраняем client_id для отслеживания
                        equipment_id=uuid_lib.UUID(inspection_item.equipment_id),
                        inspector_id=user.id,
                        data=inspection_item.data,
                        conclusion=inspection_item.conclusion,
                        status=inspection_item.status,
                        is_synced=True,
                        synced_at=datetime.utcnow(),
                    )
                    if inspection_item.date_performed:
                        new_inspection.date_performed = datetime.fromisoformat(
                            inspection_item.date_performed.replace('Z', '+00:00')
                        )
                    if inspection_item.offline_task_id:
                        new_inspection.offline_task_id = uuid_lib.UUID(inspection_item.offline_task_id)
                    
                    db.add(new_inspection)
                    synced_ids.append(str(new_inspection.id))
                
            except Exception as e:
                logger.error(
                    f"Ошибка при синхронизации инспекции {inspection_item.client_id}: {e}",
                    exc_info=True
                )
                failed_ids.append(inspection_item.client_id)
        
        # 6. Сохраняем историю синхронизации
        sync_history = SyncHistory(
            user_id=user.id,
            inspection_ids=[uuid_lib.UUID(sid) for sid in synced_ids],
            synced_count=len(synced_ids),
            failed_count=len(failed_ids),
            sync_type="offline",
        )
        db.add(sync_history)
        
        # Коммитим изменения
        await db.commit()
        
        # Логируем успешную синхронизацию
        logger.info(
            f"Синхронизация завершена для инженера {user.username} (ID: {user.id}): "
            f"синхронизировано {len(synced_ids)} инспекций, ошибок: {len(failed_ids)}"
        )
        
        return {
            "success": True,
            "synced_count": len(synced_ids),
            "failed_count": len(failed_ids),
            "synced_ids": synced_ids,
            "failed_client_ids": failed_ids,
            "sync_history_id": str(sync_history.id),
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Ошибка при синхронизации: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка при синхронизации: {str(e)}"
        )


@router.get("/tasks")
async def get_offline_tasks(
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Получить список offline-заданий пользователя"""
    try:
        result = await db.execute(
            select(OfflineTask).where(
                OfflineTask.user_id == user.id
            ).order_by(OfflineTask.created_at.desc())
        )
        tasks = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(task.id),
                    "name": task.name,
                    "equipment_ids": task.equipment_ids or [],
                    "equipment_count": len(task.equipment_ids) if task.equipment_ids else 0,
                    "downloaded_at": task.downloaded_at.isoformat() if task.downloaded_at else None,
                    "expires_at": task.expires_at.isoformat() if task.expires_at else None,
                    "created_at": task.created_at.isoformat() if task.created_at else None,
                }
                for task in tasks
            ]
        }
    except Exception as e:
        logger.error(f"Ошибка при получении offline-заданий: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка при получении offline-заданий: {str(e)}"
        )


def _get_equipment_schemas(equipment_types: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Получить схемы форм для типов оборудования"""
    schemas = {}
    for eq_type in equipment_types:
        eq_type_id = eq_type.get('id')
        # Базовая схема по умолчанию
        schemas[eq_type_id] = {
            "type": "object",
            "properties": {
                "date_performed": {"type": "string", "format": "date"},
                "conclusion": {"type": "string"},
                "data": {"type": "object"}
            }
        }
    return schemas


async def _get_dictionaries(db: AsyncSession) -> Dict[str, Any]:
    """Получить справочники для offline-пакета"""
    dictionaries = {
        "equipment_types": [],
        "inspection_statuses": ["DRAFT", "SIGNED", "APPROVED"],
        "access_types": ["read", "read_write", "create_equipment"],
    }
    
    # Получаем типы оборудования
    try:
        result = await db.execute(select(EquipmentType).where(EquipmentType.is_active == 1))
        equipment_types = result.scalars().all()
        dictionaries["equipment_types"] = [
            {
                "id": str(eq_type.id),
                "name": eq_type.name,
                "code": eq_type.code,
            }
            for eq_type in equipment_types
        ]
    except Exception as e:
        logger.warning(f"Не удалось загрузить справочник типов оборудования: {e}")
    
    return dictionaries

