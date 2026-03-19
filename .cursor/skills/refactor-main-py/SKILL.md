# Skill: Рефакторинг main.py

## Описание
Пошаговый план извлечения endpoints из монолитного `backend/main.py` (~12000 строк) в отдельные модульные роутеры.

## Когда использовать
- Пользователь просит разделить main.py
- Нужно вынести группу endpoints в отдельный файл
- Рефакторинг backend архитектуры

## Текущее состояние
`backend/main.py` содержит ВСЕ endpoints. Часть уже вынесена в роутеры:
- `auth_api.py` — авторизация
- `access_management.py` — доступ к оборудованию
- `hierarchy_management.py` — иерархия предприятий
- `assignments_api.py` — задания
- `report_templates_api.py` — шаблоны отчётов
- `equipment_history_api.py` — история оборудования
- `inspection_archive_api.py` — загрузка архивов

## Группы для выделения

### Приоритет 1 (самые большие группы)
1. **equipment_api.py** — CRUD оборудования, фото, фильтры
2. **inspections_api.py** — CRUD обследований, группировка, bulk операции, НК методы
3. **reports_api.py** — генерация, экспорт, подписание, скачивание отчётов
4. **questionnaires_api.py** — опросные листы, документы, PDF/Word

### Приоритет 2
5. **engineers_api.py** — инженеры и сертификаты
6. **verification_api.py** — поверочное оборудование
7. **clients_api.py** — клиенты и проекты
8. **opos_api.py** — ОПО (опасные объекты)
9. **stats_api.py** — статистика и метрики

### Приоритет 3
10. **mobile_api.py** — мобильные endpoints
11. **dictionaries_api.py** — справочники (типы оборудования, документы, ресурсы)

## Процесс извлечения одного модуля

### Шаг 1: Создать файл роутера
```python
# backend/equipment_api.py
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, func
from typing import Optional, List
from uuid import UUID
from datetime import datetime

from database import get_db
from auth import verify_token, verify_token_optional
from models import Equipment, EquipmentType, Enterprise, Branch, Workshop

router = APIRouter(prefix="/api", tags=["equipment"])
```

### Шаг 2: Перенести endpoints
- Скопировать все endpoints связанные с сущностью
- Перенести все Pydantic схемы, используемые этими endpoints
- Перенести вспомогательные функции, если они используются только этими endpoints

### Шаг 3: Обновить импорты в main.py
```python
from equipment_api import router as equipment_router
app.include_router(equipment_router)
```

### Шаг 4: Удалить перенесённый код из main.py
- Удалить endpoints
- Удалить неиспользуемые импорты
- Удалить неиспользуемые Pydantic схемы

### Шаг 5: Проверить
- Все endpoints доступны
- Нет дублирования маршрутов
- Нет ошибок импорта
- Тесты проходят (если есть)

## Важно
- **НЕ менять URL endpoints** — сохранять обратную совместимость с frontend и mobile
- **НЕ менять формат ответов** — клиенты ожидают текущий формат
- **Общие зависимости** (Pydantic модели, хелперы) — оставлять в main.py или вынести в `schemas.py` / `helpers.py`
- Выделять по одному модулю за раз, проверяя после каждого
