"""Shared utilities: cache, audit logging, file helpers."""

import os
import time
import logging
from typing import Optional, Any, Dict, Set
from pathlib import Path
from uuid import UUID

from fastapi import UploadFile, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from models import AuditLog

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Cache (in-memory, TTL 5 min)
# ---------------------------------------------------------------------------
_CACHE_TTL_SEC = 300
_ref_cache: Dict[str, tuple] = {}


def cache_get(key: str) -> Optional[Any]:
    if key not in _ref_cache:
        return None
    expires, val = _ref_cache[key]
    if time.time() > expires:
        del _ref_cache[key]
        return None
    return val


def cache_set(key: str, value: Any) -> None:
    _ref_cache[key] = (time.time() + _CACHE_TTL_SEC, value)


def cache_invalidate(prefix: str) -> None:
    to_del = [k for k in _ref_cache if k.startswith(prefix)]
    for k in to_del:
        del _ref_cache[k]


# ---------------------------------------------------------------------------
# Audit logging
# ---------------------------------------------------------------------------
async def log_audit(
    db: AsyncSession,
    user_id: Optional[UUID],
    action: str,
    entity_type: str,
    entity_id: Optional[UUID],
    details: Optional[dict] = None,
) -> None:
    try:
        entry = AuditLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            details=details,
        )
        db.add(entry)
    except Exception:
        logger.exception("Failed to write audit log")


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
metrics = {
    "http_requests_total": 0,
    "report_generation_seconds_sum": 0.0,
    "report_generation_count": 0,
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
ALLOWED_IMAGE_MIME_TYPES: Set[str] = {"image/jpeg", "image/jpg", "image/png"}
MAX_NDT_UPLOAD_SIZE_BYTES = 10 * 1024 * 1024


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------
def resolve_report_file_path(
    path: Optional[str],
    *,
    inspection_id: Optional[str] = None,
    questionnaire_id: Optional[str] = None,
) -> Optional[str]:
    """Привести путь к вложению отчёта к существующему файлу на сервере.

    Не ищем файл только по имени по всей базе uploads — это подставляло чужие
    фото из старых опросников/обследований при совпадающих именах.
    При неоднозначном пути возвращаем исходную строку (генератор пропускает файл).
    """
    if not path or not isinstance(path, str) or not path.strip():
        return path
    path = path.strip().replace("\\", "/")
    p = Path(path)
    if p.is_absolute() and p.exists():
        return str(p)

    bases = [
        "/app/uploads/questionnaire_documents",
        "/app/uploads/ndt_photos",
        "/app/uploads/certification_scans",
        "/app/uploads",
        "/app/reports",
        os.getcwd(),
    ]
    rel = path.lstrip("/")
    if not p.is_absolute():
        for base in bases:
            candidate = Path(base) / rel
            if candidate.is_file():
                return str(candidate.resolve())

    filename = os.path.basename(path)
    if not filename:
        return path

    if questionnaire_id:
        scoped = Path("/app/uploads/questionnaire_documents") / questionnaire_id / filename
        if scoped.is_file():
            return str(scoped.resolve())

    if inspection_id:
        root = Path("/app/uploads/ndt_photos") / "inspections" / inspection_id
        if root.is_dir():
            try:
                hits = list(root.rglob(filename))
            except OSError:
                hits = []
            existing = [h for h in hits if h.is_file()]
            if len(existing) == 1:
                return str(existing[0].resolve())

    return path


def normalize_image_content_type(file: UploadFile) -> Optional[str]:
    content_type = (file.content_type or "").lower()
    if content_type in ALLOWED_IMAGE_MIME_TYPES:
        return content_type
    ext = (Path(file.filename or "").suffix or "").lower()
    if ext in {".jpg", ".jpeg"}:
        return "image/jpeg"
    if ext == ".png":
        return "image/png"
    return None


async def read_upload_with_limit(file: UploadFile, max_size: int) -> bytes:
    content = b""
    while True:
        chunk = await file.read(1024 * 1024)
        if not chunk:
            break
        content += chunk
        if len(content) > max_size:
            raise HTTPException(
                status_code=400,
                detail=f"Файл слишком большой. Максимум {max_size // (1024 * 1024)} МБ.",
            )
    return content


def cert_areas_list(c) -> list:
    """Extract certification areas as a flat list."""
    areas = getattr(c, "certification_areas", None)
    if isinstance(areas, list):
        return [str(a) for a in areas if a]
    single = getattr(c, "certification_area", None)
    if single:
        return [str(single)]
    return []
