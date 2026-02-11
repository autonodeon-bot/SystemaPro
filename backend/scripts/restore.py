#!/usr/bin/env python3
"""
Скрипт восстановления из бэкапа (описание шагов и при необходимости запуск).
Использование:
  python scripts/restore.py <каталог_бэкапа> [--dry-run]
  Переменные окружения: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS.
"""
import os
import sys
import subprocess
import shutil
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent


def get_db_env():
    return {
        "host": os.getenv("DB_HOST", "localhost"),
        "port": os.getenv("DB_PORT", "5432"),
        "name": os.getenv("DB_NAME", "default_db"),
        "user": os.getenv("DB_USER", "gen_user"),
        "password": os.getenv("DB_PASS", ""),
    }


def restore_db(backup_dir: Path, db: dict, dry_run: bool) -> bool:
    sql_path = backup_dir / "database_dump.sql"
    if not sql_path.exists():
        print(f"  БД: файл не найден {sql_path}")
        return False
    if dry_run:
        print(f"  БД (dry-run): psql -f {sql_path}")
        return True
    env = os.environ.copy()
    if db["password"]:
        env["PGPASSWORD"] = db["password"]
    try:
        subprocess.run(
            ["psql", "-h", db["host"], "-p", db["port"], "-U", db["user"], "-d", db["name"], "-f", str(sql_path)],
            env=env,
            check=True,
        )
        print("  БД: восстановлено.")
        return True
    except Exception as e:
        print(f"  БД: ошибка {e}")
        return False


def restore_dir(backup_dir: Path, name: str, target: Path, dry_run: bool) -> bool:
    src = backup_dir / name
    if not src.exists():
        print(f"  {name}: не найден в бэкапе")
        return True
    if dry_run:
        print(f"  {name} (dry-run): копировать {src} -> {target}")
        return True
    try:
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(src, target)
        print(f"  {name}: восстановлено в {target}")
        return True
    except Exception as e:
        print(f"  {name}: ошибка {e}")
        return False


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Восстановление из бэкапа ЕС ТД НГО")
    parser.add_argument("backup_dir", type=Path, help="Каталог бэкапа (например backups/backup_20250128_120000)")
    parser.add_argument("--dry-run", action="store_true", help="Только показать действия")
    args = parser.parse_args()

    backup_dir = args.backup_dir.resolve()
    if not backup_dir.is_dir():
        print(f"Не найден каталог: {backup_dir}")
        sys.exit(1)
    print(f"Восстановление из: {backup_dir}")

    db = get_db_env()
    ok = True
    if (backup_dir / "database_dump.sql").exists():
        ok = restore_db(backup_dir, db, args.dry_run) and ok
    uploads_target = Path(os.getenv("UPLOADS_DIR", "/app/uploads"))
    if uploads_target == Path("/app/uploads") and not uploads_target.exists():
        uploads_target = BACKEND_ROOT / "uploads"
    ok = restore_dir(backup_dir, "uploads", uploads_target, args.dry_run) and ok
    reports_target = Path(os.getenv("REPORTS_DIR", "/app/reports"))
    if reports_target == Path("/app/reports") and not reports_target.exists():
        reports_target = BACKEND_ROOT / "reports"
    ok = restore_dir(backup_dir, "reports", reports_target, args.dry_run) and ok

    if not ok:
        sys.exit(1)
    print("Готово.")


if __name__ == "__main__":
    main()
