"""Read official templates, converting legacy Word documents in isolation."""
from pathlib import Path
import subprocess
import tempfile
from docx import Document
from docx_to_pdf import _find_soffice


def load_report_template(path: Path):
    if path.suffix.lower() != ".doc":
        return Document(str(path))
    soffice = _find_soffice()
    if not soffice:
        raise RuntimeError(
            f"Форма {path.stem} сохранена в формате .doc. Для её заполнения "
            "установите LibreOffice или добавьте проверенный шаблон .docx."
        )
    with tempfile.TemporaryDirectory(prefix="report_template_") as directory:
        temp = Path(directory)
        result = subprocess.run([
            soffice, "-env:UserInstallation=" + (temp / "profile").as_uri(),
            "--headless", "--nologo", "--nofirststartwizard", "--convert-to",
            "docx:Office Open XML Text", "--outdir", str(temp), str(path.resolve()),
        ], capture_output=True, text=True, timeout=180, check=False)
        converted = temp / f"{path.stem}.docx"
        if result.returncode != 0 or not converted.is_file():
            raise RuntimeError(f"Не удалось преобразовать официальный шаблон {path.name} в DOCX")
        # Load and validate the entire package before its temporary directory is removed.
        return Document(str(converted))
