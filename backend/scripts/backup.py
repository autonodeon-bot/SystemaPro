#!/usr/bin/env python3
"""
Скрипт резервного копирования БД и каталогов uploads/reports.
Требует: pg_dump в PATH (PostgreSQL client), или только копирование файлов при отсутствии pg_dump.

Использование:
  python scripts/backup.py [--output-dir DIR] [--skip-db] [--skip-files]
  Переменные окружения: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS (как в backend).
"""
import os
import sys
import subprocess
import shutil
from datetime import datetime
from pathlib import Path

# Корень проекта (backend)
BACKEND_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = BACKEND_ROOT / "backups"
UPLOADS_DIR = Path(os.getenv("UPLOADS_DIR", "/app/uploads"))
REPORTS_DIR = Path(os.getenv("REPORTS_DIR", "/app/reports"))


def get_db_env():
    return {
        "host": os.getenv("DB_HOST", "localhost"),
        "port": os.getenv("DB_PORT", "5432"),
        "name": os.getenv("DB_NAME", "default_db"),
        "user": os.getenv("DB_USER", "gen_user"),
        "password": os.getenv("DB_PASS", ""),
    }


def backup_db(output_path: Path, db: dict) -> bool:
    """Дамп PostgreSQL в output_path (файл .sql). Возвращает True при успехе."""
    sql_path = output_path / "database_dump.sql"
    env = os.environ.copy()
    if db["password"]:
        env["PGPASSWORD"] = db["password"]
    try:
        subprocess.run(
            [
                "pg_dump",
                "-h", db["host"],
                "-p", db["port"],
                "-U", db["user"],
                "-d", db["name"],
                "-F", "p",  # plain text
                "-f", str(sql_path),
            ],
            env=env,
            check=True,
            capture_output=True,
        )
        print(f"  БД: {sql_path}")
        return True
    except FileNotFoundError:
        print("  БД: pg_dump не найден, пропуск дампа. Установите PostgreSQL client.")
        return True  # не считаем фатальной ошибкой
    except subprocess.CalledProcessError as e:
        err = e.stderr.decode(errors="replace") if e.stderr else str(e)
        print(f"  БД: ошибка pg_dump: {err}")
        return False


def backup_dir(src: Path, dest: Path, name: str) -> bool:
    """Копирует каталог src в dest/name. Возвращает True если скопировано или src отсутствует."""
    if not src.exists():
        print(f"  {name}: каталог не найден {src}, пропуск.")
        return True
    dest_dir = dest / name
    try:
        if dest_dir.exists():
            shutil.rmtree(dest_dir)
        shutil.copytree(src, dest_dir, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".git"))
        print(f"  {name}: {dest_dir}")
        return True
    except Exception as e:
        print(f"  {name}: ошибка {e}")
        return False


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Резервное копирование ЕС ТД НГО")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="Каталог для бэкапов")
    parser.add_argument("--skip-db", action="store_true", help="Не делать дамп БД")
    parser.add_argument("--skip-files", action="store_true", help="Не копировать uploads/reports")
    args = parser.parse_args()

    out_root = Path(args.output_dir)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir_path = out_root / f"backup_{stamp}"
    backup_dir_path.mkdir(parents=True, exist_ok=True)
    print(f"Бэкап: {backup_dir_path}")

    ok = True
    if not args.skip_db:
        db = get_db_env()
        if not backup_db(backup_dir_path, db):
            ok = False
    if not args.skip_files:
        if UPLOADS_DIR != BACKEND_ROOT:
            ok = backup_dir(UPLOADS_DIR, backup_dir_path, "uploads") and ok
        else:
            uploads_local = BACKEND_ROOT / "uploads"
            ok = backup_dir(uploads_local, backup_dir_path, "uploads") and ok
        if REPORTS_DIR != BACKEND_ROOT:
            ok = backup_dir(REPORTS_DIR, backup_dir_path, "reports") and ok
        else:
            reports_local = BACKEND_ROOT / "reports"
            ok = backup_dir(reports_local, backup_dir_path, "reports") and ok

    readme = backup_dir_path / "README.txt"
    readme.write_text(
        f"Бэкап ЕС ТД НГО {stamp}\n"
        f"Создан: {datetime.now().isoformat()}\n"
        f"Восстановление БД: psql -h ... -U ... -d ... -f database_dump.sql\n"
        f"Восстановление файлов: скопировать uploads/ и reports/ на целевой сервер.\n",
        encoding="utf-8",
    )
    print(f"  README: {readme}")

    if not ok:
        sys.exit(1)
    print("Готово.")


if __name__ == "__main__":
    main()
