"""Dependency-free regression checks: python -m unittest discover -s scripts -p test_report_generation_regressions.py."""
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from report_request import normalize_report_options
from docx_to_pdf import convert_docx_to_pdf


class ReportOptionsTests(unittest.TestCase):
    def test_defaults(self):
        self.assertEqual(normalize_report_options({}), ("TECHNICAL_REPORT", "pdf"))

    def test_aliases_and_whitespace(self):
        for alias in ("expertise", " EPB ", "ЭПБ"):
            self.assertEqual(normalize_report_options({"report_type": alias, "format": " WORD "}), ("EXPERTISE", "docx"))
        self.assertEqual(normalize_report_options({"report_type": " technical ", "format": "doc"}), ("TECHNICAL_REPORT", "docx"))

    def test_invalid_options(self):
        for data in ({"format": "xlsx"}, {"report_type": "unknown"}, {"format": 12}, {"report_type": [1]}):
            with self.subTest(data=data), self.assertRaises(ValueError):
                normalize_report_options(data)


class ConversionTests(unittest.TestCase):
    def convert(self, content, returncode=0):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "report.docx"
            target = Path(directory) / "report.pdf"
            source.write_bytes(b"test input")
            target.write_bytes(b"existing report")
            def run(command, **kwargs):
                self.assertTrue(any(x.startswith("-env:UserInstallation=file:") for x in command))
                output = Path(command[command.index("--outdir") + 1]) / "report.pdf"
                if content is not None:
                    output.write_bytes(content)
                return SimpleNamespace(returncode=returncode, stdout="", stderr="")
            with patch("docx_to_pdf._find_soffice", return_value="soffice"), patch("docx_to_pdf.subprocess.run", side_effect=run):
                result = convert_docx_to_pdf(str(source), str(target))
            return result, target.read_bytes()

    def test_pdf_output(self):
        result, content = self.convert(b"%PDF-1.7\nexample")
        self.assertIsNotNone(result)
        self.assertTrue(content.startswith(b"%PDF-"))

    def test_empty_and_invalid_output_preserve_existing_report(self):
        for value in (b"", b"not a PDF", None):
            with self.subTest(value=value):
                result, content = self.convert(value)
                self.assertIsNone(result)
                self.assertEqual(content, b"existing report")

    def test_failed_conversion_preserves_existing_report(self):
        result, content = self.convert(b"%PDF-1.7", returncode=1)
        self.assertIsNone(result)
        self.assertEqual(content, b"existing report")


if __name__ == "__main__":
    unittest.main()
