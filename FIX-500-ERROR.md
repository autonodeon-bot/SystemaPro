# Исправление ошибки 500 в мобильном приложении

## Проблема

При запуске мобильного приложения возникает ошибка:
```
Ошибка загрузки оборудования. Exception: Error fetching equipment, failed to load 500
```

## Причина

Backend не может подключиться к базе данных из-за ошибки SSL сертификата:
```
❌ Database connection failed: [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: self-signed certificate
```

## Решение

### 1. Исправления в коде

Внесены следующие изменения:

#### `backend/database.py`
- Исправлена обработка SSL для самоподписанных сертификатов
- Используется SSL контекст с отключенной проверкой сертификата (`CERT_NONE`)
- Это решает проблему `[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: self-signed certificate`

#### `docker-compose.yml`
- Добавлены переменные окружения:
  - `DB_SSLMODE=require` - использовать SSL без строгой проверки сертификата
  - `DB_SSLCERT=/app/certs/root.crt` - путь к сертификату

#### `backend/main.py`
- Улучшена обработка ошибок в `/api/equipment`
- Добавлено логирование ошибок для отладки

#### `mobile/lib/services/api_service.dart`
- Улучшена обработка ошибок
- Добавлены понятные сообщения об ошибках на русском языке
- Обработка ошибок подключения к серверу

### 2. Применение исправлений

#### Вариант 1: Автоматический (рекомендуется)

Запустите скрипт:
```cmd
deploy-fix.bat
```

#### Вариант 2: Вручную

1. Скопируйте файлы на сервер:
```bash
scp backend/database.py root@5.129.203.182:/opt/es-td-ngo/backend/
scp backend/main.py root@5.129.203.182:/opt/es-td-ngo/backend/
scp docker-compose.yml root@5.129.203.182:/opt/es-td-ngo/
```

2. Перезапустите backend:
```bash
ssh root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose restart backend"
```

3. Проверьте логи:
```bash
ssh root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose logs backend --tail=20"
```

### 3. Пересборка мобильного приложения

После исправления backend, пересоберите мобильное приложение:

```cmd
cd mobile
flutter build apk --release
```

### 4. Проверка

1. Проверьте работу API:
   - Откройте в браузере: `http://5.129.203.182:8000/health`
   - Должно вернуть: `{"status":"healthy","database":"connected"}`

2. Проверьте список оборудования:
   - Откройте: `http://5.129.203.182:8000/api/equipment`
   - Должен вернуть список оборудования или пустой массив

3. Запустите мобильное приложение и проверьте загрузку оборудования

## Дополнительная информация

Если проблема сохраняется:

1. Проверьте логи backend:
   ```bash
   ssh root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose logs backend"
   ```

2. Проверьте подключение к базе данных:
   ```bash
   ssh root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose exec backend python -c 'from database import engine; import asyncio; async def test(): async with engine.begin() as conn: await conn.execute(\"SELECT 1\"); print(\"OK\"); asyncio.run(test())'"
   ```

3. Убедитесь, что сертификат существует:
   ```bash
   ssh root@5.129.203.182 "ls -la /opt/es-td-ngo/backend/certs/"
   ```

## Контакты

Если проблема не решена, проверьте:
- Настройки файрвола
- Доступность базы данных
- Правильность учетных данных БД

