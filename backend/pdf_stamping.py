"""PDF stamping: QR-штамп для проверки подлинности + точка подключения PAdES.

Workflow подписи заключения:
  1) `compute_pdf_sha256(pdf_bytes)` → хэш
  2) запись в таблицу `report_signatures` (→ verification_token)
  3) `stamp_pdf_with_qr(pdf_bytes, verify_url)` — рисует QR на последней стр.
  4) опционально: `sign_pdf_pades(pdf_bytes, cert_profile)` — ставит
     криптографическую подпись PAdES-T. В production требует КриптоПро CSP
     и сертификата подписанта. По умолчанию — fallback (NoOp), сохраняющий
     PDF как есть.

Публичная проверка: `/api/verify/report/{token}` → сравнение sha256 + метаданные.
"""
from __future__ import annotations

import hashlib
import io
import logging
import os
import secrets
from dataclasses import dataclass
from typing import Optional

import qrcode
from pypdf import PdfReader, PdfWriter  # type: ignore
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

log = logging.getLogger(__name__)


def compute_pdf_sha256(pdf_bytes: bytes) -> str:
    """Sha256 PDF-контента (hex)."""
    return hashlib.sha256(pdf_bytes).hexdigest()


def new_verification_token() -> str:
    """64-символьный URL-safe токен (секрет в БД)."""
    return secrets.token_urlsafe(48)[:64]


@dataclass(frozen=True)
class StampStyle:
    corner: str = "bottom-right"  # top-right | top-left | bottom-left | bottom-right
    size_mm: float = 28.0
    margin_mm: float = 8.0
    caption: str = "Подлинник: отсканируйте QR"


def _mm_to_pt(mm: float) -> float:
    return mm * 2.834645669


def _make_qr_png(url: str) -> bytes:
    qr = qrcode.QRCode(version=None, box_size=8, border=1)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image()
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def stamp_pdf_with_qr(
    pdf_bytes: bytes,
    verify_url: str,
    *,
    caption_line2: Optional[str] = None,
    style: Optional[StampStyle] = None,
) -> bytes:
    """Нарисовать QR-штамп на последней странице PDF.

    Работает так: создаём overlay-PDF нужного формата, мёрджим поверх последней
    страницы исходного документа.
    """
    if not pdf_bytes:
        return pdf_bytes
    style = style or StampStyle()

    try:
        reader = PdfReader(io.BytesIO(pdf_bytes))
    except Exception as exc:
        log.warning("stamp_pdf_with_qr: не удалось открыть PDF: %s", exc)
        return pdf_bytes

    if not reader.pages:
        return pdf_bytes

    last_page = reader.pages[-1]
    mb = last_page.mediabox
    page_width = float(mb.width)
    page_height = float(mb.height)

    # Overlay
    overlay_buf = io.BytesIO()
    c = canvas.Canvas(overlay_buf, pagesize=(page_width, page_height))

    qr_png = _make_qr_png(verify_url)
    size = _mm_to_pt(style.size_mm)
    margin = _mm_to_pt(style.margin_mm)

    if "right" in style.corner:
        x = page_width - margin - size
    else:
        x = margin
    if "top" in style.corner:
        y = page_height - margin - size
    else:
        y = margin

    from reportlab.lib.utils import ImageReader

    c.drawImage(ImageReader(io.BytesIO(qr_png)), x, y, width=size, height=size, mask="auto")

    c.setFont("Helvetica", 6)
    c.setFillGray(0.2)
    c.drawString(x, y - 8, style.caption)
    if caption_line2:
        c.drawString(x, y - 16, caption_line2[:60])
    c.save()

    overlay_buf.seek(0)
    overlay_reader = PdfReader(overlay_buf)
    overlay_page = overlay_reader.pages[0]

    writer = PdfWriter()
    for i, page in enumerate(reader.pages):
        if i == len(reader.pages) - 1:
            page.merge_page(overlay_page)
        writer.add_page(page)

    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


# ─── PAdES-T signing hook ─────────────────────────────────────────────────────
def is_pades_enabled() -> bool:
    return os.getenv("PADES_ENABLED", "0") == "1"


def sign_pdf_pades(pdf_bytes: bytes, *, signer_name: str, reason: Optional[str] = None) -> bytes:
    """Поставить PAdES-T подпись.

    Production-реализация требует:
      - КриптоПро CSP (или pyhanko + cryptography + сертификат)
      - Сертификат X.509 с закрытым ключом (PKCS#11 / PKCS#12 / csp-key)
      - TSA endpoint для RFC3161 timestamp

    Ниже — скелет с pyhanko (если установлен). Если зависимости нет или
    переменная PADES_ENABLED не "1" — возвращает исходный PDF без изменений.

    Чтобы включить:
      pip install pyhanko pyhanko-certvalidator
      PADES_ENABLED=1
      PADES_CERT_PATH=/etc/systema/signer.p12
      PADES_CERT_PASSWORD=...
      PADES_TSA_URL=http://timestamp.digitalsignaturetrust.com/...
    """
    if not is_pades_enabled():
        return pdf_bytes
    try:
        from pyhanko.sign import signers, PdfSignatureMetadata  # type: ignore
        from pyhanko.sign.fields import SigFieldSpec  # type: ignore
        from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter  # type: ignore
    except ImportError:
        log.warning("PAdES: pyhanko не установлен — пропуск подписи")
        return pdf_bytes

    cert_path = os.getenv("PADES_CERT_PATH")
    cert_password = os.getenv("PADES_CERT_PASSWORD", "")
    if not cert_path or not os.path.exists(cert_path):
        log.warning("PAdES: PADES_CERT_PATH не задан или файл не найден — пропуск")
        return pdf_bytes

    try:
        signer = signers.SimpleSigner.load_pkcs12(
            pfx_file=cert_path, passphrase=cert_password.encode("utf-8")
        )
        src = io.BytesIO(pdf_bytes)
        writer = IncrementalPdfFileWriter(src)
        out = io.BytesIO()
        signers.sign_pdf(
            writer,
            PdfSignatureMetadata(field_name="Signature1", reason=reason or "Утверждение"),
            signer=signer,
            output=out,
        )
        return out.getvalue()
    except Exception as exc:
        log.exception("PAdES signing failed: %s", exc)
        return pdf_bytes
