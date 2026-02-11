# Резервное копирование БД и файлов

## Скрипт

В проекте уже есть скрипт `backend/scripts/backup.py`. Он создаёт:
- дамп PostgreSQL (`database_dump.sql`);
- копии каталогов `uploads` и `reports`.

Переменные окружения (как в backend): `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`.

## Запуск на сервере (Docker)

Бэкап внутри контейнера backend (где есть доступ к БД и томам):

```bash
# Создать каталог для бэкапов
mkdir -p /opt/es-td-ngo/backups

# Запуск бэкапа разово (переменные DB_* берутся из .env или docker-compose)
cd /opt/es-td-ngo
docker-compose run --rm -e DB_HOST -e DB_PORT -e DB_NAME -e DB_USER -e DB_PASS backend python scripts/backup.py --output-dir /app/backups
# Файлы появятся в volume/каталоге backend; при необходимости скопировать на хост.
```

Удобнее вызывать скрипт **на хосте** с установленным `pg_dump` и монтированными томами. Ниже — вариант через cron на сервере.

## Cron (регулярные бэкапы)

1. На сервере создайте скрипт `/opt/es-td-ngo/backup-daily.sh`:

```bash
#!/bin/bash
set -e
BACKUP_ROOT=/opt/es-td-ngo/backups
mkdir -p "$BACKUP_ROOT"
cd /opt/es-td-ngo
# Используем переменные из .env или docker-compose
export $(grep -v '^#' .env 2>/dev/null | xargs) 2>/dev/null || true
docker-compose run --rm -e DB_HOST -e DB_PORT -e DB_NAME -e DB_USER -e DB_PASS backend python scripts/backup.py --output-dir /app/backups 2>/dev/null
# Или если pg_dump на хосте: pg_dump ... > "$BACKUP_ROOT/backup_$(date +%Y%m%d).sql"
# Очистка старых бэкапов (хранить 7 дней)
find "$BACKUP_ROOT" -maxdepth 1 -type d -name 'backup_*' -mtime +7 -exec rm -rf {} \;
```

2. Сделайте его исполняемым: `chmod +x /opt/es-td-ngo/backup-daily.sh`

3. Добавьте в crontab (ежедневно в 3:00):
```bash
crontab -e
# строка:
0 3 * * * /opt/es-td-ngo/backup-daily.sh >> /var/log/es-td-ngo-backup.log 2>&1
```

## Восстановление

- **БД:** `psql -h ... -U ... -d ... -f database_dump.sql`
- **Файлы:** скопировать `uploads/` и `reports/` из каталога бэкапа в `/app/uploads` и `/app/reports` на сервере.
