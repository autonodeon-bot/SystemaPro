# 📊 Информация о базе данных

## Текущая конфигурация

### ✅ Используется УДАЛЕННАЯ база данных

**Параметры подключения:**
- **Хост**: `99f541abb57e364deed82c1d.twc1.net`
- **Порт**: `5432`
- **База данных**: `default_db`
- **Пользователь**: `gen_user`
- **Пароль**: `#BeH)(rn;Cl}7a`
- **SSL**: `verify-full` (требуется сертификат)

### 🔐 SSL сертификат

Сертификат должен находиться в:
- **На сервере**: `/opt/es-td-ngo/backend/certs/root.crt`
- **В контейнере**: `/app/certs/root.crt`

### 📍 Где настроено

1. **docker-compose.yml**:
```yaml
environment:
  - DB_HOST=99f541abb57e364deed82c1d.twc1.net
  - DB_USER=gen_user
  - DB_PASS=#BeH)(rn;Cl}7a
  - DB_NAME=default_db
  - DB_SSLMODE=verify-full
  - DB_SSLCERT=/app/certs/root.crt
```

2. **backend/database.py**:
   - Читает переменные окружения
   - Настраивает SSL подключение
   - Использует asyncpg для асинхронного подключения

### ❌ Локальной базы данных НЕТ

В `docker-compose.yml` **НЕТ** сервиса `postgres` - используется только удаленная БД.

## Проверка подключения

### На сервере:
```bash
ssh root@5.129.203.182
cd /opt/es-td-ngo
docker-compose exec backend python -c "
import asyncio
from backend.database import engine
from sqlalchemy import text

async def test():
    async with engine.begin() as conn:
        result = await conn.execute(text('SELECT 1'))
        print('✅ Database connection OK')

asyncio.run(test())
"
```

### Через API:
```bash
curl http://5.129.203.182:8000/health
```

## Подключение вручную

```bash
export PGSSLROOTCERT=/opt/es-td-ngo/backend/certs/root.crt
psql 'postgresql://gen_user:#BeH)(rn;Cl}7a@99f541abb57e364deed82c1d.twc1.net:5432/default_db?sslmode=verify-full'
```

## Если нужно добавить локальную БД

Если хотите использовать локальную PostgreSQL в Docker, добавьте в `docker-compose.yml`:

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: es_td_ngo
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

volumes:
  postgres_data:
```

Но сейчас используется **только удаленная БД**.

---

**Текущий статус**: ✅ Подключение к удаленной PostgreSQL БД с SSL




