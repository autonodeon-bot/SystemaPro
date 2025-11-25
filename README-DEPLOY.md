# 🚀 Быстрый старт - Деплой ES TD NGO Platform

## ⚡ Быстрый деплой (рекомендуется)

```bash
# На Windows используйте Git Bash или WSL
bash quick-deploy.sh
```

Этот скрипт автоматически:
1. ✅ Настроит сервер
2. ✅ Установит Docker и Docker Compose
3. ✅ Скачает SSL сертификат
4. ✅ Скопирует проект
5. ✅ Запустит контейнеры

## 📋 Ручной деплой

### Шаг 1: Подключение к серверу

```bash
ssh root@5.129.203.182
# Пароль: ydR9+CL3?S@dgH
```

### Шаг 2: Настройка сервера

```bash
# Скопируйте скрипт на сервер
scp setup-server.sh root@5.129.203.182:/tmp/

# На сервере
bash /tmp/setup-server.sh
```

### Шаг 3: Скачивание SSL сертификата

```bash
# На сервере
mkdir -p /opt/es-td-ngo/backend/certs
cd /opt/es-td-ngo/backend/certs
curl -o root.crt https://storage.yandexcloud.net/cloud-certs/CA.pem
chmod 644 root.crt
```

### Шаг 4: Копирование проекта

```bash
# На локальной машине
tar -czf deploy.tar.gz \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='__pycache__' \
    .

scp deploy.tar.gz root@5.129.203.182:/tmp/

# На сервере
cd /opt/es-td-ngo
tar -xzf /tmp/deploy.tar.gz
rm /tmp/deploy.tar.gz
```

### Шаг 5: Запуск

```bash
# На сервере
cd /opt/es-td-ngo
docker-compose build --no-cache
docker-compose up -d
```

## 🔍 Проверка работы

```bash
# Проверка статуса
docker-compose ps

# Проверка логов
docker-compose logs -f

# Проверка API
curl http://localhost:8000/health

# Проверка frontend
curl http://localhost
```

## 🌐 Доступ к приложению

После успешного деплоя:

- **Frontend**: http://5.129.203.182
- **Backend API**: http://5.129.203.182:8000
- **Health Check**: http://5.129.203.182:8000/health
- **API Docs**: http://5.129.203.182:8000/docs

## 📊 База данных

### Подключение к БД

```bash
export PGSSLROOTCERT=/opt/es-td-ngo/backend/certs/root.crt
psql 'postgresql://gen_user:#BeH)(rn;Cl}7a@99f541abb57e364deed82c1d.twc1.net:5432/default_db?sslmode=verify-full'
```

### Создание таблиц

Таблицы создаются автоматически при первом запуске через SQLAlchemy.

Если нужно создать вручную:

```sql
-- Подключитесь к БД и выполните SQL из backend/models.py
-- Или используйте Alembic миграции
```

## 🛠️ Управление

### Просмотр логов
```bash
docker-compose logs -f
docker-compose logs -f backend
docker-compose logs -f frontend
```

### Перезапуск
```bash
docker-compose restart
docker-compose restart backend
docker-compose restart frontend
```

### Остановка
```bash
docker-compose down
```

### Обновление
```bash
docker-compose down
# Обновите код
docker-compose build --no-cache
docker-compose up -d
```

## ⚠️ Устранение проблем

### Проблема: Не подключается к БД

1. Проверьте SSL сертификат:
   ```bash
   ls -la /opt/es-td-ngo/backend/certs/root.crt
   ```

2. Проверьте логи:
   ```bash
   docker-compose logs backend
   ```

3. Проверьте переменные окружения:
   ```bash
   docker-compose exec backend env | grep DB_
   ```

### Проблема: Frontend не работает

1. Проверьте контейнер:
   ```bash
   docker-compose ps frontend
   ```

2. Проверьте логи:
   ```bash
   docker-compose logs frontend
   ```

3. Проверьте nginx:
   ```bash
   docker-compose exec frontend nginx -t
   ```

### Проблема: Порты заняты

```bash
# Проверьте порты
netstat -tulpn | grep :80
netstat -tulpn | grep :8000

# Остановите конфликтующие сервисы
systemctl stop nginx
systemctl stop apache2
```

## 🔐 Безопасность

⚠️ **ВАЖНО после деплоя:**

1. Измените пароль root
2. Настройте SSH ключи
3. Ограничьте доступ через firewall
4. Настройте HTTPS (Let's Encrypt)
5. Обновите CORS в `backend/main.py`
6. Используйте переменные окружения для секретов

## 📞 Поддержка

При проблемах проверьте:
- Логи: `docker-compose logs`
- Статус: `docker-compose ps`
- БД подключение: проверьте SSL сертификат

---

**Готово!** 🎉 Приложение должно быть доступно по адресу http://5.129.203.182

