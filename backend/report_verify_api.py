"""Публичный endpoint верификации заключений.

Использование:
  1. Эксперт подписывает отчёт → создаётся `ReportSignature` с токеном.
  2. В PDF наносится QR-штамп со ссылкой:
        https://neftcontrol.ru/api/verify/report/{token}
  3. Любой клиент (госорган, заказчик) сканирует QR:
        → GET /api/verify/report/{token}
          { "valid": true, "report": {...}, "signed_at": "...", "signer": "..." }
  4. Опционально: POST с расчётом hash загруженного PDF → сравнение c оригиналом.

Это минимально достаточный уровень юридической значимости без КриптоПро.
С КриптоПро добавляется PAdES-T штамп (см. pdf_stamping.py).
"""
import hashlib

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models import Report, ReportSignature
from security import VERIFY_RATE_LIMIT, limiter

router = APIRouter(prefix="/api/verify", tags=["verify"])


@router.get("/report/{token}")
@limiter.limit(VERIFY_RATE_LIMIT)
async def verify_report(request: Request, token: str, db: AsyncSession = Depends(get_db)):
    """Публичная проверка подлинности заключения по токену из QR-штампа."""
    result = await db.execute(
        select(ReportSignature).where(ReportSignature.verification_token == token)
    )
    sig = result.scalar_one_or_none()
    if not sig:
        raise HTTPException(status_code=404, detail="Документ с таким токеном не найден")

    if sig.revoked_at is not None:
        return {
            "valid": False,
            "revoked": True,
            "revoked_at": sig.revoked_at.isoformat(),
            "reason": sig.revoke_reason or "Документ отозван",
        }

    # Подтянем сам отчёт
    rep = (
        await db.execute(select(Report).where(Report.id == sig.report_id))
    ).scalar_one_or_none()

    return {
        "valid": True,
        "revoked": False,
        "report_id": str(sig.report_id),
        "report_number": getattr(rep, "report_number", None),
        "report_title": getattr(rep, "title", None),
        "signed_at": sig.signed_at.isoformat() if sig.signed_at else None,
        "signer": sig.signer_name,
        "signer_role": sig.signer_role,
        "content_sha256": sig.content_sha256,
        "signature_type": sig.signature_type,
    }


@router.post("/report/{token}/check-hash")
@limiter.limit(VERIFY_RATE_LIMIT)
async def check_pdf_hash(
    request: Request,
    token: str,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
):
    """Проверка целостности: загружаем PDF → сравниваем sha256 с оригиналом."""
    result = await db.execute(
        select(ReportSignature).where(ReportSignature.verification_token == token)
    )
    sig = result.scalar_one_or_none()
    if not sig:
        raise HTTPException(status_code=404, detail="Токен не найден")

    content = await file.read()
    actual = hashlib.sha256(content).hexdigest()
    match = actual == sig.content_sha256
    return {
        "match": match,
        "expected_sha256": sig.content_sha256,
        "actual_sha256": actual,
        "revoked": sig.revoked_at is not None,
    }
