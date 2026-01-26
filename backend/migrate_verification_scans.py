"""
Миграция старых сканов поверок в новую структуру:
/app/uploads/verification_scans/<verification_equipment_id>/...
"""
import os
import shutil
import asyncio
from pathlib import Path

from database import AsyncSessionLocal
from models import VerificationEquipment, VerificationHistory
from sqlalchemy import select


def _is_legacy_path(path: str) -> bool:
    if not path:
        return False
    p = path.replace("\\", "/")
    return p.startswith("uploads/verification-scans/") or "/uploads/verification-scans/" in p


async def migrate():
    async with AsyncSessionLocal() as session:
        # VerificationEquipment
        eq_result = await session.execute(select(VerificationEquipment))
        equipments = eq_result.scalars().all()

        updated = 0
        for eq in equipments:
            old_path = getattr(eq, "scan_file_path", None)
            if not old_path or not _is_legacy_path(old_path):
                continue
            src = Path(old_path)
            if not src.exists():
                continue
            dest_dir = Path("/app/uploads/verification_scans") / str(eq.id)
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / src.name
            try:
                shutil.move(str(src), str(dest))
                eq.scan_file_path = str(dest)
                updated += 1
            except Exception as e:
                print(f"Failed to move {src} -> {dest}: {e}")

        # VerificationHistory
        hist_result = await session.execute(select(VerificationHistory))
        history = hist_result.scalars().all()
        for h in history:
            old_path = getattr(h, "scan_file_path", None)
            if not old_path or not _is_legacy_path(old_path):
                continue
            src = Path(old_path)
            if not src.exists():
                continue
            dest_dir = Path("/app/uploads/verification_scans") / str(h.verification_equipment_id)
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / src.name
            try:
                shutil.move(str(src), str(dest))
                h.scan_file_path = str(dest)
                updated += 1
            except Exception as e:
                print(f"Failed to move {src} -> {dest}: {e}")

        if updated:
            await session.commit()
        print(f"Migration complete. Updated records: {updated}")


if __name__ == "__main__":
    asyncio.run(migrate())
