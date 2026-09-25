"""Canonical report options shared by generation and numbering."""


def normalize_report_options(data: dict) -> tuple[str, str]:
    report_type = data.get("report_type") or "TECHNICAL_REPORT"
    output_format = data.get("format") or "pdf"
    if not isinstance(report_type, str) or not isinstance(output_format, str):
        raise ValueError("Тип отчёта и формат должны быть строками")
    report_type = report_type.strip().upper()
    output_format = output_format.strip().lower()
    report_type = {"TECHNICAL": "TECHNICAL_REPORT", "EPB": "EXPERTISE", "ЭПБ": "EXPERTISE"}.get(report_type, report_type)
    output_format = {"word": "docx", "doc": "docx"}.get(output_format, output_format)
    if report_type not in {"TECHNICAL_REPORT", "EXPERTISE"}:
        raise ValueError("Неизвестный тип отчёта")
    if output_format not in {"pdf", "docx"}:
        raise ValueError("Поддерживаются только форматы PDF и DOCX")
    return report_type, output_format
