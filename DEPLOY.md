# Инструкция по деплою ES TD NGO Platform

## Требования

- Сервер с Ubuntu/Debian
- Доступ по SSH
- Удаленная PostgreSQL база данных

## Информация о сервере

- **IP адрес**: 5.129.203.182
- **Пользователь**: root
- **Пароль**: ydR9+CL3?S@dgH

## Информация о базе данных

- **Хост**: 99f541abb57e364deed82c1d.twc1.net
- **Порт**: 5432
- **База данных**: default_db
- **Пользователь**: gen_user
- **Пароль**: #BeH)(rn;Cl}7a
- **SSL**: Требуется (verify-full)

## Шаг 1: Первоначальная настройка сервера

### Вариант A: Автоматическая настройка

```bash
# Скопируйте скрипт на сервер
scp setup-server.sh root@5.129.203.182:/tmp/

# Подключитесь к серверу
ssh root@5.129.203.182

# Запустите скрипт настройки
bash /tmp/setup-server.sh
```

### Вариант B: Ручная настройка

```bash
# Подключитесь к серверу
ssh root@5.129.203.182

# Обновите систему
apt-get update && apt-get upgrade -y

# Установите Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Установите Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Создайте директорию приложения
mkdir -p /opt/es-td-ngo/backend/certs

# Настройте firewall
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 8000/tcp
ufw --force enable
```

## Шаг 2: Скачивание SSL сертификата

```bash
# На сервере
cd /opt/es-td-ngo/backend/certs
curl -o root.crt https://storage.yandexcloud.net/cloud-certs/CA.pem

# Или альтернативный способ
export PGSSLROOTCERT=$HOME/.cloud-certs/root.crt
# Скачайте сертификат вручную и поместите в /opt/es-td-ngo/backend/certs/root.crt
```

## Шаг 3: Деплой приложения

### Вариант A: Использование скрипта деплоя

```bash
# На локальной машине
chmod +x deploy.sh
./deploy.sh
```

### Вариант B: Ручной деплой

```bash
# 1. Создайте архив проекта (на локальной машине)
tar -czf deploy.tar.gz \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    .

# 2. Скопируйте на сервер
scp deploy.tar.gz root@5.129.203.182:/tmp/

# 3. Подключитесь к серверу
ssh root@5.129.203.182

# 4. Распакуйте проект
cd /opt/es-td-ngo
tar -xzf /tmp/deploy.tar.gz
rm /tmp/deploy.tar.gz

# 5. Убедитесь, что SSL сертификат на месте
ls -la backend/certs/root.crt

# 6. Запустите контейнеры
docker-compose build --no-cache
docker-compose up -d
```

## Шаг 4: Проверка работы

```bash
# Проверьте статус контейнеров
docker-compose ps

# Проверьте логи
docker-compose logs -f

# Проверьте доступность API
curl http://localhost:8000/health

# Проверьте frontend
curl http://localhost
```

## Шаг 5: Настройка базы данных

### Создание таблиц (если нужно)

```bash
# Подключитесь к базе данных
export PGSSLROOTCERT=/opt/es-td-ngo/backend/certs/root.crt
psql 'postgresql://gen_user:#BeH)(rn;Cl}7a@99f541abb57e364deed82c1d.twc1.net:5432/default_db?sslmode=verify-full'

# Или используйте миграции Alembic (если настроены)
docker-compose exec backend alembic upgrade head
```

## Полезные команды

### Просмотр логов
```bash
# Все сервисы
docker-compose logs -f

# Только backend
docker-compose logs -f backend

# Только frontend
docker-compose logs -f frontend
```

### Перезапуск сервисов
```bash
docker-compose restart
# или
docker-compose restart backend
docker-compose restart frontend
```

### Остановка сервисов
```bash
docker-compose down
```

### Обновление приложения
```bash
# Остановите контейнеры
docker-compose down

# Обновите код (через git или scp)
# ...

# Пересоберите и запустите
docker-compose build --no-cache
docker-compose up -d
```

### Проверка подключения к БД
```bash
# Из контейнера backend
docker-compose exec backend python -c "
from backend.database import engine
import asyncio
from sqlalchemy import text

async def test():
    async with engine.begin() as conn:
        result = await conn.execute(text('SELECT 1'))
        print('✅ Database connection OK')

asyncio.run(test())
"
```

## Мониторинг

### Prometheus exporters (если настроены)

- **node_exporter**: http://192.168.0.4:9100
- **postgres_exporter**: http://192.168.0.4:9308

## Устранение проблем

### Проблема: Не удается подключиться к БД

1. Проверьте наличие SSL сертификата:
   ```bash
   ls -la /opt/es-td-ngo/backend/certs/root.crt
   ```

2. Проверьте логи backend:
   ```bash
   docker-compose logs backend
   ```

3. Проверьте подключение вручную:
   ```bash
   docker-compose exec backend python -c "
   import os
   print('DB_HOST:', os.getenv('DB_HOST'))
   print('DB_USER:', os.getenv('DB_USER'))
   print('SSL Cert exists:', os.path.exists('/app/certs/root.crt'))
   "
   ```

### Проблема: Frontend не загружается

1. Проверьте, что frontend контейнер запущен:
   ```bash
   docker-compose ps frontend
   ```

2. Проверьте логи:
   ```bash
   docker-compose logs frontend
   ```

3. Проверьте nginx конфигурацию:
   ```bash
   docker-compose exec frontend nginx -t
   ```

### Проблема: Порты заняты

```bash
# Проверьте, какие процессы используют порты
netstat -tulpn | grep :80
netstat -tulpn | grep :8000

# Остановите конфликтующие сервисы
systemctl stop nginx  # если используется
systemctl stop apache2  # если используется
```

## Безопасность

⚠️ **ВАЖНО**: После успешного деплоя:

1. Измените пароль root на сервере
2. Настройте SSH ключи вместо пароля
3. Ограничьте доступ к портам через firewall
4. Настройте HTTPS (Let's Encrypt)
5. Обновите CORS настройки в `backend/main.py`
6. Используйте переменные окружения для секретов

## Контакты и поддержка

При возникновении проблем проверьте:
- Логи контейнеров: `docker-compose logs`
- Статус контейнеров: `docker-compose ps`
- Подключение к БД: проверьте SSL сертификат и credentials

