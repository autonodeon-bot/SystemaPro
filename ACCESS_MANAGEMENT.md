# Система разграничения доступа - Версия 3.2.8

## Описание

Восстановлена система разграничения доступа, которая позволяет администраторам и шеф-операторам назначать инженерам доступ к конкретному оборудованию, цехам или предприятиям.

## Функционал

### Для администраторов и шеф-операторов:
- Назначение доступа инженерам к оборудованию
- Массовое назначение доступа по фильтрам (предприятие, цех)
- Просмотр текущих назначений доступа
- Отзыв доступа

### Для инженеров:
- Видят только назначенное им оборудование в мобильном приложении
- Не могут видеть оборудование, к которому нет доступа

## API Endpoints

### Управление доступом

#### Предоставить доступ к оборудованию
```
POST /api/access/users/{user_id}/equipment
Authorization: Bearer {token}
Content-Type: application/json

{
  "equipment_ids": ["uuid1", "uuid2", ...],
  "access_type": "read_write",  // или "read_only"
  "expires_at": "2025-12-31T23:59:59"  // опционально
}
```

#### Массовое назначение доступа по фильтрам
```
POST /api/access/users/{user_id}/equipment/bulk
Authorization: Bearer {token}
Content-Type: application/json

{
  "location": "цех 1",  // опционально
  "enterprise": "НГДУ",  // опционально
  "access_type": "read_write",
  "expires_at": "2025-12-31T23:59:59"  // опционально
}
```

#### Отозвать доступ
```
DELETE /api/access/users/{user_id}/equipment/{equipment_id}
Authorization: Bearer {token}
```

#### Получить список доступа пользователя
```
GET /api/access/users/{user_id}/equipment
Authorization: Bearer {token}
```

### Получение оборудования

#### Список оборудования (автоматически фильтруется для инженеров)
```
GET /api/equipment
Authorization: Bearer {token}
```

Для инженеров возвращается только оборудование, к которому есть активный доступ.
Для администраторов, шеф-операторов и операторов возвращается все оборудование.

## База данных

### Таблица `user_equipment_access`
- `id` - UUID, первичный ключ
- `user_id` - UUID, ссылка на users.id
- `equipment_id` - UUID, ссылка на equipment.id
- `access_type` - VARCHAR(20), тип доступа: "read_only" или "read_write"
- `granted_by` - UUID, кто предоставил доступ
- `granted_at` - TIMESTAMP, когда предоставлен доступ
- `expires_at` - TIMESTAMP, срок действия (опционально)
- `is_active` - INTEGER, активен ли доступ (0/1)
- `created_at` - TIMESTAMP
- `updated_at` - TIMESTAMP

### Индексы
- `idx_user_equipment_access_user_id` - на user_id
- `idx_user_equipment_access_equipment_id` - на equipment_id
- `idx_user_equipment_access_is_active` - на is_active
- `idx_user_equipment_access_unique` - уникальный индекс на (user_id, equipment_id) WHERE is_active = 1

## Использование

### Назначение доступа через API

1. Получить список инженеров:
```bash
GET /api/users?role=engineer
```

2. Получить список оборудования:
```bash
GET /api/equipment
```

3. Назначить доступ:
```bash
POST /api/access/users/{engineer_id}/equipment
{
  "equipment_ids": ["equipment_uuid_1", "equipment_uuid_2"],
  "access_type": "read_write"
}
```

### Массовое назначение по предприятию/цеху

```bash
POST /api/access/users/{engineer_id}/equipment/bulk
{
  "enterprise": "НГДУ",
  "location": "цех 1",
  "access_type": "read_write"
}
```

## Мобильное приложение

В мобильном приложении инженеры автоматически видят только назначенное им оборудование. Фильтрация происходит на сервере на основе токена авторизации.

## Миграция

Для создания таблицы доступа выполните:
```bash
python backend/create_user_equipment_access_table.py
```

Или таблица создастся автоматически при первом запуске приложения (через SQLAlchemy metadata).

## Безопасность

- Доступ к endpoints управления доступом имеют только:
  - `admin`
  - `chief_operator`
  - `operator`
  
- Инженеры могут видеть только свой собственный доступ
- Все запросы требуют JWT токен авторизации
- Фильтрация оборудования происходит на уровне базы данных












