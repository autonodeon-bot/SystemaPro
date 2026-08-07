"""
Конвертация заполненного Word (.docx) в PDF.

Предпочтительно LibreOffice (soffice) в Docker.
Fallback: если конвертация недоступна — возвращает None.
"""
from __future__ import annotations

import logging
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


def _find_soffice() -> Optional[str]:
    env = os.environ.get("LIBREOFFICE_PATH") or os.environ.get("SOFFICE_PATH")
    if env and Path(env).exists():
        return env
    for name in ("soffice", "libreoffice"):
        found = shutil.which(name)
        if found:
            return found
    # Типичные пути Windows / Linux
    candidates = [
        r"C:\Program Files\LibreOffice\program\soffice.exe",
        r"C:\Program Files (x86)\LibreOffice\program\soffice.exe",
        "/usr/bin/soffice",
        "/usr/bin/libreoffice",
        "/usr/lib/libreoffice/program/soffice",
    ]
    for c in candidates:
        if Path(c).exists():
            return c
    return None


def convert_docx_to_pdf(docx_path: str, pdf_path: Optional[str] = None) -> Optional[str]:
    """
    Конвертировать docx → pdf через LibreOffice.
    Возвращает путь к PDF или None при ошибке.
    """
    src = Path(docx_path)
    if not src.exists() or src.suffix.lower() != ".docx":
        logger.error("convert_docx_to_pdf: файл не найден или не .docx: %s", docx_path)
        return None

    out = Path(pdf_path) if pdf_path else src.with_suffix(".pdf")
    out.parent.mkdir(parents=True, exist_ok=True)

    soffice = _find_soffice()
    if not soffice:
        logger.warning("LibreOffice (soffice) не найден — PDF из Word недоступен")
        return None

    with tempfile.TemporaryDirectory(prefix="docx2pdf_") as tmp:
        tmp_dir = Path(tmp)
        cmd = [
            soffice,
            "--headless",
            "--nologo",
            "--nofirststartwizard",
            "--convert-to",
            "pdf",
            "--outdir",
            str(tmp_dir),
            str(src.resolve()),
        ]
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=180,
                check=False,
            )
            if proc.returncode != 0:
                logger.error(
                    "soffice failed (%s): %s %s",
                    proc.returncode,
                    proc.stdout,
                    proc.stderr,
                )
                return None
            produced = tmp_dir / (src.stem + ".pdf")
            if not produced.exists():
                # Иногда имя отличается
                pdfs = list(tmp_dir.glob("*.pdf"))
                if not pdfs:
                    logger.error("soffice не создал PDF")
                    return None
                produced = pdfs[0]
            shutil.copy2(produced, out)
            logger.info("DOCX→PDF: %s → %s", src, out)
            return str(out)
        except subprocess.TimeoutExpired:
            logger.error("soffice timeout при конвертации %s", src)
            return None
        except Exception as exc:
            logger.error("Ошибка конвертации DOCX→PDF: %s", exc)
            return None


def libreoffice_available() -> bool:
    return _find_soffice() is not None
