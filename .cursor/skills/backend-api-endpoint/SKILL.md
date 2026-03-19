# Skill: Создание нового API endpoint (Backend)

## Описание
Создание нового модульного API endpoint для FastAPI backend проекта ЕС ТД НГО.

## Когда использовать
- Пользователь просит добавить новый API endpoint
- Нужно создать новый ресурс/сущность в backend
- Расширение существующего API

## Шаги выполнения

### 1. Определить сущность
- Имя модели (PascalCase)
- Имя таблицы (snake_case, множественное число)
- Поля и типы
- Связи с другими моделями

### 2. Создать/обновить модель в `backend/models.py`
```python
class NewEntity(Base):
    __tablename__ = "new_entities"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    # ... поля
    
    is_archived = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
```

### 3. Создать файл роутера `backend/{entity}_api.py`
```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional, List
from uuid import UUID
from datetime import datetime

from database import get_db
from auth import verify_token
from models import NewEntity

router = APIRouter(prefix="/api/new-entities", tags=["new-entities"])

# --- Pydantic схемы ---
class NewEntityCreate(BaseModel):
    name: str
    # ... поля

class NewEntityUpdate(BaseModel):
    name: Optional[str] = None

class NewEntityResponse(BaseModel):
    id: UUID
    name: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

# --- Endpoints ---
@router.get("/")
async def list_entities(db: AsyncSession = Depends(get_db), user=Depends(verify_token)):
    result = await db.execute(
        select(NewEntity).where(NewEntity.is_archived == False).order_by(NewEntity.created_at.desc())
    )
    return result.scalars().all()

@router.post("/", status_code=201)
async def create_entity(data: NewEntityCreate, db: AsyncSession = Depends(get_db), user=Depends(verify_token)):
    entity = NewEntity(**data.dict())
    db.add(entity)
    await db.commit()
    await db.refresh(entity)
    return entity

@router.get("/{entity_id}")
async def get_entity(entity_id: UUID, db: AsyncSession = Depends(get_db), user=Depends(verify_token)):
    result = await db.execute(select(NewEntity).where(NewEntity.id == entity_id))
    entity = result.scalar_one_or_none()
    if not entity:
        raise HTTPException(404, "Не найдено")
    return entity

@router.put("/{entity_id}")
async def update_entity(entity_id: UUID, data: NewEntityUpdate, db: AsyncSession = Depends(get_db), user=Depends(verify_token)):
    result = await db.execute(select(NewEntity).where(NewEntity.id == entity_id))
    entity = result.scalar_one_or_none()
    if not entity:
        raise HTTPException(404, "Не найдено")
    for key, value in data.dict(exclude_unset=True).items():
        setattr(entity, key, value)
    entity.updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(entity)
    return entity

@router.delete("/{entity_id}", status_code=204)
async def delete_entity(entity_id: UUID, db: AsyncSession = Depends(get_db), user=Depends(verify_token)):
    result = await db.execute(select(NewEntity).where(NewEntity.id == entity_id))
    entity = result.scalar_one_or_none()
    if not entity:
        raise HTTPException(404, "Не найдено")
    entity.is_archived = True
    entity.updated_at = datetime.utcnow()
    await db.commit()
```

### 4. Подключить роутер в `backend/main.py`
В начало файла добавить импорт:
```python
from new_entity_api import router as new_entity_router
```

После остальных `include_router`:
```python
app.include_router(new_entity_router)
```

### 5. Добавить миграцию (если нужна таблица)
В `main.py` в функции startup добавить `CREATE TABLE IF NOT EXISTS` или `ALTER TABLE` для новых колонок.

### 6. Проверить
- Endpoint доступен через `/api/new-entities`
- Авторизация работает
- CRUD операции корректны
- Ошибки возвращаются с правильными статусами
