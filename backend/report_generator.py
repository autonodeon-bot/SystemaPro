"""
Генератор технических отчетов и экспертиз промышленной безопасности.
Форматирование по ГОСТ Р 21.1101, ГОСТ Р 55046.
"""
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, Image,
)
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT, TA_JUSTIFY
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from datetime import datetime
from typing import Dict, Any, Optional, List
import os
import io
import logging

from shared import resolve_report_file_path as _scoped_resolve_upload_path

logger = logging.getLogger(__name__)

USABLE_WIDTH = A4[0] - 2.5 * cm - 1.5 * cm


def _escape_para(s: str) -> str:
    if not s:
        return ""
    s = str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return s


_METHOD_NAME_MAP = {
    "VIK": "ВИК", "UZK": "УЗК", "UZT": "УЗТ", "PVK": "ПВК",
    "MK": "МК", "RK": "РК", "MPD": "МПД", "KPD": "КПД",
    "TVI": "ТВИ", "AK": "АК", "TK": "ТК",
}


class ReportGenerator:
    """Генератор PDF отчетов (ГОСТ Р 21.1101 / ГОСТ Р 55046)"""

    def __init__(self):
        self.styles = getSampleStyleSheet()
        self._report_inspection_id: Optional[str] = None
        self._report_questionnaire_id: Optional[str] = None
        self._register_fonts()
        self._setup_custom_styles()

    def _set_report_path_scope(self, inspection_data: Optional[Dict[str, Any]]) -> None:
        self._report_inspection_id = None
        self._report_questionnaire_id = None
        if not isinstance(inspection_data, dict):
            return
        _iid = inspection_data.get("id")
        if _iid:
            self._report_inspection_id = str(_iid)
        _qid = inspection_data.get("questionnaire_id")
        if _qid:
            self._report_questionnaire_id = str(_qid)

    def _inspection_title_date_ru(self, inspection_data: Dict[str, Any]) -> str:
        """Дата на титульном листе: по данным обследования, если есть."""
        _db = inspection_data.get("data") if isinstance(inspection_data.get("data"), dict) else {}
        dd = inspection_data.get("date_performed")
        if not dd and isinstance(_db, dict):
            dd = _db.get("inspection_date") or _db.get("inspectionDate")
        if isinstance(dd, str) and dd.strip():
            try:
                return datetime.fromisoformat(dd.replace("Z", "+00:00")).strftime("%d.%m.%Y")
            except ValueError:
                pass
        return datetime.now().strftime("%d.%m.%Y")

    # ── Шрифты ──────────────────────────────────────────────────────

    def _register_fonts(self):
        """Регистрация шрифтов с поддержкой кириллицы."""
        try:
            candidates = [
                {
                    "regular": "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                    "bold": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                    "name_regular": "DejaVuSans",
                    "name_bold": "DejaVuSans-Bold",
                },
                {
                    "regular": "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
                    "bold": "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
                    "name_regular": "LiberationSans",
                    "name_bold": "LiberationSans-Bold",
                },
            ]
            for c in candidates:
                if os.path.exists(c["regular"]):
                    try:
                        pdfmetrics.registerFont(TTFont(c["name_regular"], c["regular"]))
                        if os.path.exists(c["bold"]):
                            pdfmetrics.registerFont(TTFont(c["name_bold"], c["bold"]))
                            self.bold_font = c["name_bold"]
                        else:
                            self.bold_font = c["name_regular"]
                        self.default_font = c["name_regular"]
                        return
                    except Exception:
                        continue
            self.default_font = "Helvetica"
            self.bold_font = "Helvetica-Bold"
        except Exception as e:
            logger.warning("Could not register custom fonts: %s", e)
            self.default_font = "Helvetica"
            self.bold_font = "Helvetica-Bold"

    # ── Стили по ГОСТ ───────────────────────────────────────────────

    def _setup_custom_styles(self):
        df = getattr(self, "default_font", "Helvetica")
        bf = getattr(self, "bold_font", df)

        for name in ("Normal",):
            if name in self.styles.byName:
                self.styles[name].fontName = df
        for name in ("Heading1", "Heading2", "Heading3"):
            if name in self.styles.byName:
                self.styles[name].fontName = bf

        if "ReportTitle" not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name="ReportTitle", parent=self.styles["Heading1"],
                fontSize=16, leading=24, textColor=colors.black,
                spaceAfter=12, alignment=TA_CENTER, fontName=bf,
            ))

        if "ReportSubtitle" not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name="ReportSubtitle", parent=self.styles["Heading2"],
                fontSize=14, leading=21, textColor=colors.black,
                spaceAfter=12, alignment=TA_CENTER, fontName=df,
            ))

        if "SectionTitle" not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name="SectionTitle", parent=self.styles["Heading2"],
                fontSize=14, leading=21, textColor=colors.black,
                spaceAfter=12, spaceBefore=18, alignment=TA_LEFT, fontName=bf,
            ))

        if "BodyText" not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name="BodyText", parent=self.styles["Normal"],
                fontSize=12, leading=18, textColor=colors.black,
                alignment=TA_JUSTIFY, spaceAfter=6, spaceBefore=0,
                firstLineIndent=1.25 * cm, fontName=df, wordWrap="CJK",
            ))
        else:
            s = self.styles["BodyText"]
            s.fontSize, s.leading = 12, 18
            s.textColor = colors.black
            s.alignment = TA_JUSTIFY
            s.spaceAfter, s.spaceBefore = 6, 0
            s.firstLineIndent = 1.25 * cm
            s.fontName, s.wordWrap = df, "CJK"

        if "BodyTextNoIndent" not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name="BodyTextNoIndent", parent=self.styles["Normal"],
                fontSize=12, leading=18, textColor=colors.black,
                alignment=TA_LEFT, spaceAfter=6, fontName=df, wordWrap="CJK",
            ))

        if "RightAligned" not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name="RightAligned", parent=self.styles["Normal"],
                fontSize=12, leading=18, textColor=colors.black,
                alignment=TA_RIGHT, fontName=df,
            ))

        if "Conclusion" not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name="Conclusion", parent=self.styles["Normal"],
                fontSize=12, leading=18, textColor=colors.black,
                alignment=TA_JUSTIFY, spaceAfter=12, fontName=bf,
            ))

        if "TableCell" not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name="TableCell", parent=self.styles["Normal"],
                fontSize=9, leading=12, textColor=colors.black,
                alignment=TA_LEFT, fontName=df, wordWrap="CJK",
            ))
        else:
            tc = self.styles["TableCell"]
            tc.fontSize, tc.leading = 9, 12
            tc.textColor = colors.black
            tc.fontName = df

        if "TableCellBold" not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name="TableCellBold", parent=self.styles["Normal"],
                fontSize=10, leading=13, textColor=colors.black,
                alignment=TA_CENTER, fontName=bf, wordWrap="CJK",
            ))

    # ── ГОСТ-стили таблиц ──────────────────────────────────────────

    def _gost_table_style(self, has_header: bool = True) -> TableStyle:
        """ГОСТ-совместимый стиль таблицы."""
        cmds: list = [
            ("FONTNAME", (0, 0), (-1, -1), self.default_font),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("LEADING", (0, 0), (-1, -1), 12),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ("LEFTPADDING", (0, 0), (-1, -1), 4),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.black),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ]
        if has_header:
            cmds.extend([
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e2e8f0")),
                ("FONTNAME", (0, 0), (-1, 0), self.bold_font),
                ("FONTSIZE", (0, 0), (-1, 0), 10),
                ("ALIGN", (0, 0), (-1, 0), "CENTER"),
            ])
        return TableStyle(cmds)

    def _gost_kv_style(self) -> TableStyle:
        """ГОСТ-совместимый стиль для таблиц «ключ-значение»."""
        return TableStyle([
            ("FONTNAME", (0, 0), (-1, -1), self.default_font),
            ("FONTNAME", (0, 0), (0, -1), self.bold_font),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("LEADING", (0, 0), (-1, -1), 14),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ("LEFTPADDING", (0, 0), (-1, -1), 4),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#e2e8f0")),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.black),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ])

    # ── Вспомогательные методы ─────────────────────────────────────

    def _cell_text(self, text: Any, style_name: str = "TableCell") -> Paragraph:
        """Paragraph-ячейка с переносом текста."""
        style = self.styles.get(style_name, self.styles["Normal"])
        return Paragraph(_escape_para(str(text) if text is not None else ""), style)

    def _cell_header(self, text: Any) -> Paragraph:
        return self._cell_text(text, "TableCellBold")

    def _kv_table(self, rows, story):
        """Построить KV-таблицу шириной в страницу и добавить в story."""
        kv_w = [5.5 * cm, 11.5 * cm]
        t = Table(rows, colWidths=kv_w)
        t.setStyle(self._gost_kv_style())
        story.append(t)

    def _find_image_path(self, path: Optional[str]) -> Optional[str]:
        """Путь к изображению для отчёта — без подстановки чужих файлов по совпадению имени."""
        if not path or not isinstance(path, str):
            return None
        path = path.strip().replace("\\", "/")
        if os.path.isabs(path) and os.path.isfile(path):
            return path
        resolved = _scoped_resolve_upload_path(
            path,
            inspection_id=self._report_inspection_id,
            questionnaire_id=self._report_questionnaire_id,
        )
        if resolved and isinstance(resolved, str) and os.path.isfile(resolved):
            return resolved
        return None

    def _page_number_handler(self):
        """Возвращает callback для нумерации страниц (— N —)."""
        font = self.default_font

        def _handler(canvas, doc):
            canvas.saveState()
            canvas.setFont(font, 10)
            canvas.drawCentredString(
                A4[0] / 2, 1.5 * cm,
                f"\u2014 {canvas.getPageNumber()} \u2014",
            )
            canvas.restoreState()

        return _handler

    def _add_image_to_story(self, story, title: str, path: Optional[str]):
        """Добавить изображение в story если оно найдено."""
        if not path or not isinstance(path, str):
            return
        found = self._find_image_path(path)
        if not found:
            return
        try:
            story.append(Paragraph(title, self.styles["BodyTextNoIndent"]))
            img = Image(found)
            max_w, max_h = USABLE_WIDTH * 0.85, 9.6 * cm
            iw = getattr(img, "imageWidth", None) or max_w
            ih = getattr(img, "imageHeight", None) or max_h
            ratio = min(max_w / float(iw), max_h / float(ih), 1.0)
            img.drawWidth = iw * ratio
            img.drawHeight = ih * ratio
            story.append(img)
            story.append(Spacer(1, 0.3 * cm))
        except Exception as e:
            logger.warning("Could not add image %s: %s", found, e)

    def _resolve_scan_path(self, raw_path: str, subdirs: List[str]) -> Optional[str]:
        """Ищет файл скана в нескольких директориях."""
        possible = [raw_path]
        if not os.path.isabs(raw_path):
            for sd in subdirs:
                possible.append(f"/app/uploads/{sd}/{raw_path}")
            possible.append(f"/app/uploads/{raw_path}")
        filename = os.path.basename(raw_path)
        if "/" not in raw_path or raw_path.count("/") == 0:
            for sd in subdirs:
                possible.append(f"/app/uploads/{sd}/{filename}")
            possible.append(f"/app/uploads/{filename}")
        for p in possible:
            if os.path.exists(p) and os.path.isfile(p):
                return p
        return None

    def _method_name_ru(self, method: Dict[str, Any]) -> str:
        code = str(method.get("method_code") or "").upper()
        name = method.get("method_name") or ""
        if not name or name == code:
            return _METHOD_NAME_MAP.get(code, code or "Метод НК")
        return name

    # ═══════════════════════════════════════════════════════════════
    #  Технический отчёт
    # ═══════════════════════════════════════════════════════════════

    def generate_technical_report(
        self,
        inspection_data: Dict[str, Any],
        equipment_data: Dict[str, Any],
        output_path: str,
        ndt_methods: Optional[List[Dict[str, Any]]] = None,
        document_files: Optional[List[Dict[str, Any]]] = None,
        specialist_docs: Optional[List[Dict[str, Any]]] = None,
        verification_equipment: Optional[List[Dict[str, Any]]] = None,
    ) -> str:
        """Генерация технического отчета (ГОСТ Р 21.1101 / ГОСТ Р 55046)."""
        self._set_report_path_scope(inspection_data)

        title_date_str = self._inspection_title_date_ru(inspection_data)

        doc = SimpleDocTemplate(
            output_path,
            pagesize=A4,
            rightMargin=1.5 * cm,
            leftMargin=2.5 * cm,
            topMargin=2 * cm,
            bottomMargin=2 * cm,
        )

        story: list = []

        # ── Титульная страница ──────────────────────────────────────
        org = ""
        try:
            d = inspection_data.get("data") or {}
            if isinstance(d, dict):
                org = str(d.get("organization") or d.get("organization_name") or "").strip()
        except Exception:
            org = ""

        eq_name = equipment_data.get("name", "Не указано")
        reg_num = ""
        attrs = equipment_data.get("attributes") or {}
        if isinstance(attrs, dict):
            reg_num = attrs.get("regNumber", "")

        story.append(Spacer(1, 3 * cm))
        story.append(Paragraph("УТВЕРЖДАЮ", self.styles["RightAligned"]))
        story.append(Paragraph("________________________", self.styles["RightAligned"]))
        story.append(Spacer(1, 2 * cm))
        story.append(Paragraph("ОТЧЁТ", self.styles["ReportTitle"]))
        story.append(Paragraph("О ТЕХНИЧЕСКОМ ДИАГНОСТИРОВАНИИ", self.styles["ReportTitle"]))
        story.append(Spacer(1, 0.5 * cm))
        story.append(Paragraph(
            f"по результатам обследования оборудования", self.styles["ReportSubtitle"]
        ))
        if org:
            story.append(Paragraph(f"Организация/объект: {org}", self.styles["ReportSubtitle"]))
        story.append(Spacer(1, 0.5 * cm))
        story.append(Paragraph(f"Объект: {eq_name}", self.styles["ReportSubtitle"]))
        story.append(Spacer(1, 2 * cm))
        story.append(Paragraph(
            f"Дата: {title_date_str}", self.styles["BodyTextNoIndent"],
        ))
        if reg_num:
            story.append(Paragraph(
                f"Регистрационный номер: {reg_num}", self.styles["BodyTextNoIndent"],
            ))
        story.append(PageBreak())

        # ── Содержание ──────────────────────────────────────────────
        story.append(Paragraph("СОДЕРЖАНИЕ", self.styles["SectionTitle"]))
        for item in [
            "1. Общая часть",
            "2. Исходные данные и нормативная база",
            "3. Описание объекта и карта обследования",
            "4. Акт(ы) неразрушающего контроля (по методам)",
            "5. Результаты обследования (детализация)",
            "6. Заключение",
            "7. Приложения (фото/схемы/документы специалистов)",
        ]:
            story.append(Paragraph(item, self.styles["BodyTextNoIndent"]))
        story.append(PageBreak())

        # ── 1. Общая часть ──────────────────────────────────────────
        story.append(Paragraph("1. ОБЩАЯ ЧАСТЬ", self.styles["SectionTitle"]))
        story.append(Paragraph(
            "Настоящий отчет составлен по результатам технического диагностирования "
            "оборудования с целью оценки технического состояния и определения возможности "
            "дальнейшей безопасной эксплуатации.",
            self.styles["BodyText"],
        ))

        # ── 2. Нормативная база ─────────────────────────────────────
        story.append(Paragraph("2. ИСХОДНЫЕ ДАННЫЕ И НОРМАТИВНАЯ БАЗА", self.styles["SectionTitle"]))
        story.append(Paragraph(
            "При выполнении работ использовались данные, предоставленные Заказчиком, "
            "результаты обследований и применимые нормативные документы (ФНП, ГОСТ, РД и др.).",
            self.styles["BodyText"],
        ))

        # ── 3. Описание объекта ─────────────────────────────────────
        story.append(Paragraph("3. ОПИСАНИЕ ОБЪЕКТА И КАРТА ОБСЛЕДОВАНИЯ", self.styles["SectionTitle"]))

        equipment_info = [
            ["Наименование оборудования:", eq_name],
            ["Заводской номер:", equipment_data.get("serial_number", "Не указан")],
            ["Место расположения:", equipment_data.get("location", "Не указано")],
            ["Дата ввода в эксплуатацию:", equipment_data.get("commissioning_date", "Не указана")],
        ]
        if isinstance(attrs, dict):
            if attrs.get("regNumber"):
                equipment_info.append(["Регистрационный номер:", attrs["regNumber"]])
            if attrs.get("pressure"):
                equipment_info.append(["Рабочее давление:", attrs["pressure"]])
            if attrs.get("volume"):
                equipment_info.append(["Объем:", attrs["volume"]])

        self._kv_table(equipment_info, story)
        story.append(Spacer(1, 0.3 * cm))

        story.append(Paragraph("Сведения об обследовании:", self.styles["BodyTextNoIndent"]))
        inspection_info = [
            ["Дата проведения диагностики:", inspection_data.get("date_performed", "Не указана")],
            ["Статус:", inspection_data.get("status", "DRAFT")],
        ]
        if inspection_data.get("data"):
            data = inspection_data["data"]
            if isinstance(data, dict):
                if data.get("executors"):
                    inspection_info.append(["Исполнители:", data["executors"]])
                if data.get("organization"):
                    inspection_info.append(["Организация:", data["organization"]])
        self._kv_table(inspection_info, story)
        story.append(Spacer(1, 0.3 * cm))

        if inspection_data.get("data") and isinstance(inspection_data.get("data"), dict):
            self._add_checklist_data(story, inspection_data["data"], document_files=document_files)

        story.append(PageBreak())

        # ── 4. Акт(ы) НК ───────────────────────────────────────────
        story.append(Paragraph("4. АКТ(Ы) НЕРАЗРУШАЮЩЕГО КОНТРОЛЯ", self.styles["SectionTitle"]))
        if ndt_methods:
            performed = [m for m in ndt_methods if m.get("is_performed")]
            if not performed:
                story.append(Paragraph(
                    "Методы НК не указаны или не выполнены.", self.styles["BodyText"],
                ))
            else:
                for idx, m in enumerate(performed, 1):
                    method_name_ru = self._method_name_ru(m)
                    method_code = str(m.get("method_code") or "").upper()

                    story.append(Paragraph(
                        f"Акт №{idx}. {method_name_ru}", self.styles["SectionTitle"],
                    ))

                    act_rows = [
                        ["Метод НК:", method_name_ru],
                        ["Код:", method_code],
                        ["Нормативный документ:", str(m.get("standard") or "")],
                        ["Оборудование/прибор:", str(m.get("equipment") or "")],
                        ["Дата выполнения:", str(
                            m.get("performed_date") or inspection_data.get("date_performed") or ""
                        )],
                        ["Специалист:", str(m.get("inspector_name") or "")],
                        ["Уровень:", str(m.get("inspector_level") or "")],
                    ]
                    self._kv_table(act_rows, story)
                    story.append(Spacer(1, 0.3 * cm))

                    # Детализация по методу НК (таблицы из additional_data)
                    self._build_ndt_detail_section(story, m)

                    if m.get("results"):
                        story.append(Paragraph(
                            f"<b>Результаты:</b> {_escape_para(str(m['results']))}",
                            self.styles["BodyTextNoIndent"],
                        ))
                    if m.get("defects"):
                        story.append(Paragraph(
                            f"<b>Дефекты:</b> {_escape_para(str(m['defects']))}",
                            self.styles["BodyTextNoIndent"],
                        ))
                    if m.get("conclusion"):
                        story.append(Paragraph(
                            f"<b>Заключение:</b> {_escape_para(str(m['conclusion']))}",
                            self.styles["BodyTextNoIndent"],
                        ))

                    # Фото по методу НК
                    additional_data = m.get("additional_data", {})
                    photos = m.get("photos") or []
                    annotated_images = []
                    if isinstance(additional_data, dict):
                        annotated_images = additional_data.get("annotated_images", []) or []
                    all_photos = list(photos) if isinstance(photos, list) else []
                    if isinstance(annotated_images, list):
                        all_photos.extend(annotated_images)
                    if all_photos:
                        story.append(Paragraph(
                            "Фотоматериалы (карта замеров, фото дефектов):",
                            self.styles["BodyTextNoIndent"],
                        ))
                        for p in all_photos[:15]:
                            if not isinstance(p, str):
                                continue
                            found_path = self._find_image_path(p)
                            if found_path:
                                try:
                                    img = Image(found_path)
                                    max_w, max_h = USABLE_WIDTH * 0.8, 8 * cm
                                    iw = getattr(img, "imageWidth", None) or max_w
                                    ih = getattr(img, "imageHeight", None) or max_h
                                    if iw and ih:
                                        ratio = min(max_w / float(iw), max_h / float(ih), 1.0)
                                        img.drawWidth = iw * ratio
                                        img.drawHeight = ih * ratio
                                    else:
                                        img.drawWidth, img.drawHeight = max_w, max_h
                                    story.append(img)
                                    story.append(Spacer(1, 0.2 * cm))
                                except Exception as e:
                                    logger.warning("Could not add NDT photo %s: %s", found_path, e)
                    story.append(Spacer(1, 0.3 * cm))
        else:
            story.append(Paragraph("Методы НК не указаны.", self.styles["BodyText"]))

        story.append(PageBreak())

        # ── 5. Результаты обследования ──────────────────────────────
        if inspection_data.get("data"):
            story.append(Paragraph(
                "5. РЕЗУЛЬТАТЫ ОБСЛЕДОВАНИЯ (ДЕТАЛИЗАЦИЯ)", self.styles["SectionTitle"],
            ))
            data = inspection_data["data"]
            if isinstance(data, dict):
                self._add_checklist_data(story, data, document_files=document_files)

        # ── 6. Заключение ───────────────────────────────────────────
        if inspection_data.get("conclusion"):
            story.append(Paragraph("6. ЗАКЛЮЧЕНИЕ", self.styles["SectionTitle"]))
            story.append(Paragraph(inspection_data["conclusion"], self.styles["Conclusion"]))

        # ── 7. Приложения ───────────────────────────────────────────
        story.append(PageBreak())
        story.append(Paragraph("7. ПРИЛОЖЕНИЯ", self.styles["SectionTitle"]))
        if specialist_docs:
            for s in specialist_docs:
                story.append(Paragraph(
                    f"Документы специалиста: {s.get('inspector_name', '')}",
                    self.styles["SectionTitle"],
                ))
                certs = s.get("certifications") or []
                for c in certs:
                    line = (
                        f"{c.get('certification_type', '')} "
                        f"№{c.get('certificate_number', '')} "
                        f"({c.get('issuing_organization', '')})"
                    )
                    story.append(Paragraph(line, self.styles["BodyText"]))
                    sp = c.get("scan_file_path")
                    mt = c.get("scan_mime_type") or ""
                    if isinstance(sp, str) and "image" in mt.lower():
                        found = self._resolve_scan_path(sp, ["certifications"])
                        if found:
                            try:
                                img = Image(found)
                                max_w = USABLE_WIDTH * 0.8
                                img.drawWidth = max_w
                                img.drawHeight = max_w * 0.625
                                story.append(img)
                                story.append(Spacer(1, 0.2 * cm))
                            except Exception as e:
                                logger.warning("Could not add cert scan %s: %s", found, e)
        else:
            story.append(Paragraph(
                "Документы специалистов НК не приложены.", self.styles["BodyText"],
            ))

        # Используемое поверочное оборудование
        fallback_equipment: list = []
        if not (verification_equipment and isinstance(verification_equipment, list)
                and len(verification_equipment) > 0):
            for m in (ndt_methods or []):
                name = (m.get("equipment") or "").strip()
                if name and name not in [e.get("name") for e in fallback_equipment]:
                    fallback_equipment.append({"name": name})

        self._add_verification_equipment_section(
            story, verification_equipment, fallback_equipment,
        )

        # Подпись
        story.append(Spacer(1, 0.8 * cm))
        story.append(Paragraph(
            "Ответственный исполнитель: _________________________",
            self.styles["BodyTextNoIndent"],
        ))
        story.append(Paragraph(
            f"Дата: {title_date_str}",
            self.styles["BodyTextNoIndent"],
        ))

        page_handler = self._page_number_handler()
        doc.build(story, onFirstPage=page_handler, onLaterPages=page_handler)
        return output_path

    # ── Детализация результатов НК по методу ────────────────────────

    def _build_ndt_detail_section(self, story, method: Dict[str, Any]):
        """Таблица результатов, специфичная для метода НК."""
        code = str(method.get("method_code") or "").upper()
        ad = method.get("additional_data") or {}
        if not isinstance(ad, dict):
            return
        if code in ("UZT", "УЗТ"):
            self._ndt_uzt_table(story, ad)
        elif code in ("VIK", "ВИК"):
            self._ndt_vik_table(story, ad)
        elif code in ("PVK", "ПВК", "KPD", "КПД"):
            self._ndt_pvk_table(story, ad)
        elif code in ("UZK", "УЗК", "UZK_SS", "УЗК_СС"):
            self._ndt_uzk_table(story, ad)
        elif code in ("MPD", "МПД", "MK", "МК"):
            self._ndt_mpd_table(story, ad)
        elif code in ("RK", "РК"):
            self._ndt_rk_table(story, ad)

    def _ndt_uzt_table(self, story, ad: dict):
        points = ad.get("measurement_points") or ad.get("thickness_measurements") or []
        if not isinstance(points, list) or not points:
            return
        nom = ad.get("nominal_thickness", "")
        min_a = ad.get("min_allowed_thickness", "")
        rows = [[
            self._cell_header("№ п/п"),
            self._cell_header("Точка замера"),
            self._cell_header("Номинальная\nтолщина, мм"),
            self._cell_header("Фактическая\nтолщина, мм"),
            self._cell_header("Мин. допуст., мм"),
            self._cell_header("Заключение"),
        ]]
        for i, p in enumerate(points, 1):
            if not isinstance(p, dict):
                continue
            rows.append([
                self._cell_text(i),
                self._cell_text(p.get("location") or p.get("point_name") or f"Точка {i}"),
                self._cell_text(p.get("nominal_thickness") or nom),
                self._cell_text(p.get("thickness") or p.get("measured_thickness") or ""),
                self._cell_text(p.get("min_allowed_thickness") or min_a),
                self._cell_text(p.get("conclusion") or p.get("comment") or ""),
            ])
        if len(rows) > 1:
            t = Table(rows, colWidths=[0.8*cm, 3.5*cm, 2.7*cm, 2.7*cm, 3.0*cm, 4.3*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

    def _ndt_vik_table(self, story, ad: dict):
        defects = ad.get("defects_list") or ad.get("defects") or []
        if not isinstance(defects, list) or not defects:
            return
        rows = [[
            self._cell_header("№ п/п"),
            self._cell_header("Элемент"),
            self._cell_header("Описание дефекта"),
            self._cell_header("Размер"),
            self._cell_header("Классификация"),
            self._cell_header("Допустимость"),
        ]]
        for i, d in enumerate(defects, 1):
            if not isinstance(d, dict):
                continue
            rows.append([
                self._cell_text(i),
                self._cell_text(d.get("element") or d.get("zone") or ""),
                self._cell_text(d.get("description") or d.get("type") or ""),
                self._cell_text(d.get("size") or ""),
                self._cell_text(d.get("classification") or ""),
                self._cell_text(d.get("acceptability") or ""),
            ])
        if len(rows) > 1:
            t = Table(rows, colWidths=[0.8*cm, 2.5*cm, 4.5*cm, 2.2*cm, 3.2*cm, 3.8*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

    def _ndt_pvk_table(self, story, ad: dict):
        items = ad.get("indications_list") or ad.get("indications") or []
        if not isinstance(items, list) or not items:
            return
        rows = [[
            self._cell_header("№ п/п"),
            self._cell_header("Зона контроля"),
            self._cell_header("Индикация"),
            self._cell_header("Размер"),
            self._cell_header("Оценка"),
        ]]
        for i, ind in enumerate(items, 1):
            if not isinstance(ind, dict):
                continue
            rows.append([
                self._cell_text(i),
                self._cell_text(ind.get("zone") or ""),
                self._cell_text(ind.get("indication") or ind.get("description") or ""),
                self._cell_text(ind.get("size") or ""),
                self._cell_text(ind.get("assessment") or ind.get("evaluation") or ""),
            ])
        if len(rows) > 1:
            t = Table(rows, colWidths=[0.8*cm, 4.0*cm, 4.5*cm, 3.0*cm, 4.7*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

    def _ndt_uzk_table(self, story, ad: dict):
        items = ad.get("results_list") or ad.get("scan_results") or []
        if not isinstance(items, list) or not items:
            return
        rows = [[
            self._cell_header("№ п/п"),
            self._cell_header("Зона контроля"),
            self._cell_header("Координата"),
            self._cell_header("Амплитуда, дБ"),
            self._cell_header("Эквив. размер, мм"),
            self._cell_header("Оценка"),
        ]]
        for i, r in enumerate(items, 1):
            if not isinstance(r, dict):
                continue
            rows.append([
                self._cell_text(i),
                self._cell_text(r.get("zone") or ""),
                self._cell_text(r.get("coordinate") or ""),
                self._cell_text(r.get("amplitude") or ""),
                self._cell_text(r.get("equivalent_size") or ""),
                self._cell_text(r.get("assessment") or r.get("evaluation") or ""),
            ])
        if len(rows) > 1:
            t = Table(rows, colWidths=[0.8*cm, 3.2*cm, 2.5*cm, 2.8*cm, 3.5*cm, 4.2*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

    def _ndt_mpd_table(self, story, ad: dict):
        items = ad.get("indications_list") or ad.get("indications") or []
        if not isinstance(items, list) or not items:
            return
        rows = [[
            self._cell_header("№ п/п"),
            self._cell_header("Зона контроля"),
            self._cell_header("Тип индикации"),
            self._cell_header("Размер"),
            self._cell_header("Оценка"),
        ]]
        for i, ind in enumerate(items, 1):
            if not isinstance(ind, dict):
                continue
            rows.append([
                self._cell_text(i),
                self._cell_text(ind.get("zone") or ""),
                self._cell_text(ind.get("type") or ind.get("indication") or ""),
                self._cell_text(ind.get("size") or ""),
                self._cell_text(ind.get("assessment") or ""),
            ])
        if len(rows) > 1:
            t = Table(rows, colWidths=[0.8*cm, 4.0*cm, 4.5*cm, 3.0*cm, 4.7*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

    def _ndt_rk_table(self, story, ad: dict):
        params = []
        for key, label in [
            ("radiation_source", "Источник излучения"),
            ("energy_kv", "Энергия, кВ"),
            ("exposure", "Экспозиция, мА·мин"),
            ("film_detector", "Плёнка/детектор"),
            ("sensitivity", "Чувствительность контроля"),
        ]:
            val = ad.get(key)
            if val:
                params.append([label, str(val)])
        if params:
            self._kv_table(params, story)
            story.append(Spacer(1, 0.3 * cm))

    # ── Секция поверочного оборудования ─────────────────────────────

    def _add_verification_equipment_section(
        self, story, verification_equipment, fallback_equipment,
    ):
        eq_list = verification_equipment or fallback_equipment
        is_verified = bool(verification_equipment and isinstance(verification_equipment, list)
                          and len(verification_equipment) > 0)

        story.append(Spacer(1, 0.3 * cm))
        story.append(Paragraph(
            "7.1. Используемое оборудование для неразрушающего контроля",
            self.styles["SectionTitle"],
        ))
        if not eq_list:
            story.append(Paragraph("Приборы не указаны.", self.styles["BodyText"]))
            return

        story.append(Paragraph(
            "При проведении обследования использовалось следующее "
            + ("поверенное " if is_verified else "")
            + "оборудование:",
            self.styles["BodyText"],
        ))

        header = [
            self._cell_header("№"),
            self._cell_header("Наименование"),
            self._cell_header("Тип"),
            self._cell_header("Серийный номер"),
            self._cell_header("Срок поверки"),
            self._cell_header("Свидетельство"),
        ]
        rows = [header]
        for idx, eq in enumerate(eq_list, 1):
            next_date = eq.get("next_verification_date", "")
            if next_date:
                try:
                    from datetime import datetime as dt
                    d = dt.fromisoformat(next_date.replace("Z", "+00:00"))
                    next_date = d.strftime("%d.%m.%Y")
                except Exception:
                    pass
            cert_num = eq.get("verification_certificate_number", "")
            rows.append([
                self._cell_text(idx),
                self._cell_text(eq.get("name", "")),
                self._cell_text(eq.get("equipment_type", "") or "\u2014"),
                self._cell_text(eq.get("serial_number", "") or "\u2014"),
                self._cell_text(next_date or "\u2014"),
                self._cell_text(cert_num if cert_num else "\u2014"),
            ])

        t = Table(rows, colWidths=[0.8*cm, 4.5*cm, 2.5*cm, 3.0*cm, 3.0*cm, 3.2*cm])
        t.setStyle(self._gost_table_style())
        story.append(t)
        story.append(Spacer(1, 0.3 * cm))

        if is_verified:
            story.append(Paragraph(
                "Сканы свидетельств о поверке:", self.styles["BodyTextNoIndent"],
            ))
            for eq in verification_equipment:
                scan_path = eq.get("scan_file_path")
                scan_name = eq.get("scan_file_name", "")
                eq_name = eq.get("name", "")
                if not scan_path:
                    continue
                mime_type = eq.get("scan_mime_type", "")
                if "image" in mime_type.lower():
                    found = self._resolve_scan_path(scan_path, ["verification_scans"])
                    if found:
                        story.append(Paragraph(
                            f"Свидетельство: {eq_name} ({scan_name})",
                            self.styles["BodyTextNoIndent"],
                        ))
                        try:
                            img = Image(found)
                            max_w = USABLE_WIDTH * 0.8
                            img.drawWidth = max_w
                            img.drawHeight = max_w * 0.625
                            story.append(img)
                            story.append(Spacer(1, 0.2 * cm))
                        except Exception as e:
                            logger.warning("Could not add verification scan %s: %s", found, e)
                elif scan_path and os.path.exists(scan_path):
                    story.append(Paragraph(f"Файл: {scan_name}", self.styles["BodyTextNoIndent"]))

    # ═══════════════════════════════════════════════════════════════
    #  Данные чек-листа
    # ═══════════════════════════════════════════════════════════════

    def _add_checklist_data(
        self, story, data: Dict[str, Any],
        document_files: Optional[List[Dict[str, Any]]] = None,
    ):
        """Добавление данных из чек-листа."""

        def _get(*keys, default=None):
            for k in keys:
                if k in data and data.get(k) is not None:
                    return data.get(k)
            return default

        opo = data.get("opo") or data.get("opo_info") or {}
        if not isinstance(opo, dict):
            opo = {}

        def _opo_get(*keys, default=None):
            for k in keys:
                if k in opo and opo.get(k) not in (None, ""):
                    return opo.get(k)
            for k in keys:
                camel = "".join(
                    word.capitalize() if i > 0 else word
                    for i, word in enumerate(k.split("_"))
                )
                cl = camel[0].lower() + camel[1:] if camel else k
                if cl in opo and opo.get(cl) not in (None, ""):
                    return opo.get(cl)
            return _get(*keys, default=default)

        attachments: Dict[str, str] = {}
        if document_files and isinstance(document_files, list):
            for f in document_files:
                if not isinstance(f, dict):
                    continue
                dn = str(f.get("document_number") or "")
                fp = f.get("file_path")
                if dn and isinstance(fp, str) and fp:
                    attachments[dn] = fp

        # ── Сведения об ОПО ─────────────────────────────────────────
        opo_name = _opo_get("name", "opo_name")
        opo_code = _opo_get("code", "opo_code")
        opo_desc = _opo_get("description", "opo_description")
        opo_enterprise = _opo_get("enterprise_name", "opo_enterprise")
        opo_branch = _opo_get("branch_name", "opo_branch")
        opo_workshop = _opo_get("workshop_name", "opo_workshop")
        survey = data.get("opo_survey") if isinstance(data.get("opo_survey"), dict) else opo.get("survey_data")
        if not isinstance(survey, dict):
            survey = {}
        opo_org = survey.get("organization")
        opo_exec = survey.get("executors")

        if any([opo_name, opo_code, opo_desc, opo_enterprise, opo_branch, opo_workshop, opo_org, opo_exec]):
            story.append(Paragraph("Сведения об ОПО", self.styles["SectionTitle"]))
            rows = []

            def _add_row(label, value):
                if value is None:
                    return
                s = str(value).strip()
                if not s:
                    return
                rows.append([self._cell_text(label), self._cell_text(s)])

            _add_row("Наименование ОПО", opo_name)
            _add_row("Код ОПО", opo_code)
            _add_row("Описание", opo_desc)
            _add_row("Предприятие", opo_enterprise)
            _add_row("Филиал", opo_branch)
            _add_row("Цех", opo_workshop)
            _add_row("Организация (опросный лист ОПО)", opo_org)
            _add_row("Исполнители (опросный лист ОПО)", opo_exec)
            if rows:
                t = Table(rows, colWidths=[5.5 * cm, 11.5 * cm])
                t.setStyle(self._gost_kv_style())
                story.append(t)
                story.append(Spacer(1, 0.3 * cm))

        # ── Документы ───────────────────────────────────────────────
        docs = _get("documents", default={})
        docs_info = _get("documents_info", default={})
        if docs or docs_info:
            story.append(Paragraph(
                "3.1. Перечень рассмотренных документов", self.styles["SectionTitle"],
            ))

            document_names = {
                "1": "Лицензия на осуществление деятельности по эксплуатации взрывопожароопасных и химически опасных производственных объектов I, II и III классов опасности",
                "2": "Свидетельство о регистрации в государственном реестре ОПО, включая сведения характеризующие ОПО",
                "3": "Технологический регламент объектов опасных производственных объектов",
                "4": "План мероприятий по локализации и ликвидации последствий аварий на опасном производственном объекте",
                "5": "Положение о производственном контроле за соблюдением требований промышленной безопасности на опасных производственных объектах",
                "6": "Журнал учета аварий и инцидентов на ОПО",
                "7": "Страховой полис страхования гражданской ответственности владельца опасного объекта за причинение вреда в результате аварии на опасном объекте",
                "8": "Приказ о назначении ответственного лица за исправное состояние и безопасную эксплуатацию сосудов",
                "9": "Приказ о назначении ответственного лица за осуществление производственного контроля и соблюдение требований промышленной безопасности на опасном производственном объекте",
                "10": "Паспорт сосуда заводской (удостоверение о качестве монтажа, сертификат соответствия, сборочный чертёж и схема включения сосуда, расчёт на прочность)",
                "11": "Инструкция по монтажу и эксплуатации",
                "12": "Паспорта на предохранительные клапаны",
                "13": "Паспорта на запорную арматуру",
                "14": "Документация на контрольно-измерительные приборы",
                "15": "Ремонтная (исполнительная) документация",
                "16": "Заключение экспертизы промышленной безопасности",
                "17": "Акты проведения УЗТ",
            }

            def _doc_meta(num: str):
                num_key = str(num)
                present = None
                doc_number = ""
                doc_date = ""
                if isinstance(docs, dict) and num_key in docs:
                    val = docs.get(num_key)
                    if isinstance(val, dict):
                        present = val.get("present")
                        if present is None:
                            present = val.get("has") if val.get("has") is not None else val.get("value")
                        doc_number = str(val.get("number") or val.get("doc_number") or "")
                        doc_date = str(val.get("date") or val.get("doc_date") or "")
                    else:
                        if isinstance(val, str):
                            present = val.strip().lower() in ("true", "1", "yes", "да")
                        else:
                            present = bool(val)
                if isinstance(docs_info, dict) and num_key in docs_info:
                    info = docs_info.get(num_key) or {}
                    if isinstance(info, dict):
                        if present is None:
                            present = info.get("present")
                            if present is None:
                                present = info.get("has") if info.get("has") is not None else info.get("value")
                        if not doc_number:
                            doc_number = str(info.get("number") or info.get("doc_number") or "")
                        if not doc_date:
                            doc_date = str(info.get("date") or info.get("doc_date") or "")
                return present, doc_number, doc_date

            doc_keys: set = set()
            if isinstance(docs, dict):
                doc_keys.update(str(k) for k in docs.keys())
            if isinstance(docs_info, dict):
                doc_keys.update(str(k) for k in docs_info.keys())
            doc_keys_sorted = sorted(doc_keys, key=lambda x: int(x) if str(x).isdigit() else 999)

            doc_header = [
                self._cell_header("№"),
                self._cell_header("Наименование документа"),
                self._cell_header("Номер"),
                self._cell_header("Дата"),
                self._cell_header("Наличие"),
            ]
            doc_data = [doc_header]
            for num in doc_keys_sorted:
                doc_name = document_names.get(str(num), f"Документ {num}")
                present, doc_number, doc_date = _doc_meta(str(num))
                doc_data.append([
                    self._cell_text(num),
                    self._cell_text(doc_name),
                    self._cell_text(doc_number or "\u2014"),
                    self._cell_text(doc_date or "\u2014"),
                    self._cell_text("Да" if present else "\u2014"),
                ])

            t = Table(doc_data, colWidths=[0.8*cm, 8.2*cm, 2.5*cm, 2.5*cm, 3.0*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

        # ── Карта обследования ──────────────────────────────────────
        vessel_name = _get("vessel_name", "vesselName")
        if vessel_name:
            story.append(Paragraph("3.2. Карта обследования", self.styles["SectionTitle"]))
            vessel_data = [
                ["Наименование сосуда:", vessel_name or ""],
                ["Заводской номер:", _get("serial_number", "serialNumber", default="") or ""],
                ["Регистрационный номер:", _get("reg_number", "regNumber", default="") or ""],
            ]
            wp = _get("working_pressure", "workingPressure")
            diam = _get("diameter")
            if wp:
                vessel_data.append(["Рабочее давление:", wp])
            if diam:
                vessel_data.append(["Диаметр сосуда:", diam])
            self._kv_table(vessel_data, story)
            story.append(Spacer(1, 0.3 * cm))

        # Фото заводской таблички
        plate_path = _get("factory_plate_photo", "factoryPlatePhoto")
        plate_to_use = attachments.get("factory_plate_photo") or plate_path
        if not plate_to_use:
            plate_to_use = data.get("factory_plate_photo") or data.get("factoryPlatePhoto")
        self._add_image_to_story(story, "Фото заводской таблички:", plate_to_use)

        # ── УЗТ ─────────────────────────────────────────────────────
        thickness = _get("thickness_measurements", "thicknessMeasurements", default=[])
        if isinstance(thickness, list) and len(thickness) > 0:
            story.append(Paragraph(
                "3.3. УЗТ (Ультразвуковая толщинометрия)", self.styles["SectionTitle"],
            ))
            header = [
                self._cell_header("№"),
                self._cell_header("Местоположение"),
                self._cell_header("Сечение"),
                self._cell_header("Толщина, мм"),
                self._cell_header("Мин. доп., мм"),
                self._cell_header("Комментарий"),
            ]
            t_rows = [header]
            for idx, point in enumerate(thickness, 1):
                if not isinstance(point, dict):
                    continue
                t_rows.append([
                    self._cell_text(idx),
                    self._cell_text(point.get("location") or ""),
                    self._cell_text(point.get("section_number") or ""),
                    self._cell_text(point.get("thickness") or ""),
                    self._cell_text(point.get("min_allowed_thickness") or ""),
                    self._cell_text(point.get("comment") or ""),
                ])
            if len(t_rows) > 1:
                t = Table(t_rows, colWidths=[0.8*cm, 3.0*cm, 1.5*cm, 2.0*cm, 2.0*cm, 7.7*cm])
                t.setStyle(self._gost_table_style())
                story.append(t)
                story.append(Spacer(1, 0.3 * cm))

        # Схема контроля
        scheme_path = _get("control_scheme_image", "controlSchemeImage")
        scheme_to_use = attachments.get("control_scheme_image") or scheme_path
        if not scheme_to_use:
            scheme_to_use = data.get("control_scheme_image") or data.get("controlSchemeImage")
        self._add_image_to_story(story, "Схема контроля:", scheme_to_use)

        # ── ЗРА ─────────────────────────────────────────────────────
        zra = _get("zra_items", default=[])
        if isinstance(zra, list) and zra:
            story.append(Paragraph(
                "3.4. ЗРА (запорно-регулирующая арматура)", self.styles["SectionTitle"],
            ))
            header = [
                self._cell_header("№"), self._cell_header("Кол-во"),
                self._cell_header("Типоразмер"), self._cell_header("Тех. №"),
                self._cell_header("Зав. №"), self._cell_header("Место на схеме"),
            ]
            rows = [header]
            for i, it in enumerate(zra, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    self._cell_text(i),
                    self._cell_text(it.get("quantity") or ""),
                    self._cell_text(it.get("type_size") or ""),
                    self._cell_text(it.get("tech_number") or ""),
                    self._cell_text(it.get("serial_number") or ""),
                    self._cell_text(it.get("location_on_scheme") or ""),
                ])
            t = Table(rows, colWidths=[0.8*cm, 1.5*cm, 3.5*cm, 2.5*cm, 2.5*cm, 6.2*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

        # ── СППК ────────────────────────────────────────────────────
        sppk = _get("sppk_items", default=[])
        if isinstance(sppk, list) and sppk:
            story.append(Paragraph(
                "3.5. СППК (предохранительные клапаны)", self.styles["SectionTitle"],
            ))
            header = [
                self._cell_header("№"), self._cell_header("Кол-во"),
                self._cell_header("Типоразмер"), self._cell_header("Тех. №"),
                self._cell_header("Зав. №"), self._cell_header("Место на схеме"),
            ]
            rows = [header]
            for i, it in enumerate(sppk, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    self._cell_text(i),
                    self._cell_text(it.get("quantity") or ""),
                    self._cell_text(it.get("type_size") or ""),
                    self._cell_text(it.get("tech_number") or ""),
                    self._cell_text(it.get("serial_number") or ""),
                    self._cell_text(it.get("location_on_scheme") or ""),
                ])
            t = Table(rows, colWidths=[0.8*cm, 1.5*cm, 3.5*cm, 2.5*cm, 2.5*cm, 6.2*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

        # ── Овальность ──────────────────────────────────────────────
        ovality = _get("ovality_measurements", default=[])
        if isinstance(ovality, list) and ovality:
            story.append(Paragraph(
                "3.6. Измерительный контроль \u2014 овальность", self.styles["SectionTitle"],
            ))
            header = [
                self._cell_header("№"), self._cell_header("Сечение"),
                self._cell_header("Dmax"), self._cell_header("Dmin"),
                self._cell_header("Отклонение, %"),
            ]
            rows = [header]
            for i, it in enumerate(ovality, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    self._cell_text(i),
                    self._cell_text(it.get("section_number", "") or ""),
                    self._cell_text(it.get("max_diameter", "") or ""),
                    self._cell_text(it.get("min_diameter", "") or ""),
                    self._cell_text(it.get("deviation_percent", "") or ""),
                ])
            t = Table(rows, colWidths=[0.8*cm, 3.5*cm, 4.0*cm, 4.0*cm, 4.7*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

        # ── Прогиб ──────────────────────────────────────────────────
        deflection = _get("deflection_measurements", default=[])
        if isinstance(deflection, list) and deflection:
            story.append(Paragraph(
                "3.7. Измерительный контроль \u2014 прогиб", self.styles["SectionTitle"],
            ))
            header = [
                self._cell_header("№"), self._cell_header("Сечение"),
                self._cell_header("Прогиб, мм"), self._cell_header("Прогиб, %"),
            ]
            rows = [header]
            for i, it in enumerate(deflection, 1):
                if not isinstance(it, dict):
                    continue
                raw_pct = it.get("deflection_percent", "") or ""
                try:
                    deflection_pct = f"{float(str(raw_pct).replace(',', '.')):.2f}"
                except Exception:
                    deflection_pct = str(raw_pct)
                rows.append([
                    self._cell_text(i),
                    self._cell_text(it.get("section_number", "") or ""),
                    self._cell_text(it.get("deflection_mm", "") or ""),
                    self._cell_text(deflection_pct),
                ])
            t = Table(rows, colWidths=[0.8*cm, 4.0*cm, 6.1*cm, 6.1*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

        # ── Твёрдость ───────────────────────────────────────────────
        hardness = _get("hardness_tests", default=[])
        if isinstance(hardness, list) and hardness:
            story.append(Paragraph("3.8. Контроль твёрдости", self.styles["SectionTitle"]))
            header = [
                self._cell_header("№"), self._cell_header("Шов"),
                self._cell_header("Участок"), self._cell_header("Доп. осн"),
                self._cell_header("Доп. шов"), self._cell_header("Осн"),
                self._cell_header("Шов"), self._cell_header("ЗТВ"),
            ]
            rows = [header]
            for i, it in enumerate(hardness, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    self._cell_text(i),
                    self._cell_text(it.get("weld_number", "") or ""),
                    self._cell_text(it.get("area_number", "") or ""),
                    self._cell_text(it.get("allowed_hardness_base", "") or ""),
                    self._cell_text(it.get("allowed_hardness_weld", "") or ""),
                    self._cell_text(it.get("hardness_base", "") or ""),
                    self._cell_text(it.get("hardness_weld", "") or ""),
                    self._cell_text(it.get("hardness_haz", "") or ""),
                ])
            t = Table(rows, colWidths=[
                0.8*cm, 1.8*cm, 2.0*cm, 2.3*cm, 2.3*cm, 2.3*cm, 2.3*cm, 3.2*cm,
            ])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

        # ── Сварные соединения ──────────────────────────────────────
        welds = _get("weld_inspections", default=[])
        if isinstance(welds, list) and welds:
            story.append(Paragraph(
                "3.9. Контроль сварных соединений (ПВК/УЗК)", self.styles["SectionTitle"],
            ))
            header = [
                self._cell_header("№"), self._cell_header("Шов"),
                self._cell_header("Место на карте"), self._cell_header("ПВК дефект"),
                self._cell_header("УЗК дефект"), self._cell_header("Заключение"),
            ]
            rows = [header]
            for i, it in enumerate(welds, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    self._cell_text(i),
                    self._cell_text(it.get("weld_number", "") or ""),
                    self._cell_text(it.get("location_on_control_map", "") or ""),
                    self._cell_text(it.get("pvk_defect", "") or ""),
                    self._cell_text(it.get("uzk_defect", "") or ""),
                    self._cell_text(it.get("conclusion", "") or ""),
                ])
            t = Table(rows, colWidths=[0.8*cm, 1.5*cm, 3.5*cm, 3.5*cm, 3.5*cm, 4.2*cm])
            t.setStyle(self._gost_table_style())
            story.append(t)
            story.append(Spacer(1, 0.3 * cm))

    # ═══════════════════════════════════════════════════════════════
    #  Экспертиза промышленной безопасности
    # ═══════════════════════════════════════════════════════════════

    def generate_expertise_report(
        self,
        inspection_data: Dict[str, Any],
        equipment_data: Dict[str, Any],
        resource_data: Optional[Dict[str, Any]],
        output_path: str,
        ndt_methods: Optional[List[Dict[str, Any]]] = None,
        document_files: Optional[List[Dict[str, Any]]] = None,
        specialist_docs: Optional[List[Dict[str, Any]]] = None,
        verification_equipment: Optional[List[Dict[str, Any]]] = None,
    ) -> str:
        """Генерация экспертизы промышленной безопасности."""
        self._set_report_path_scope(inspection_data)
        exp_title_date = self._inspection_title_date_ru(inspection_data)
        doc = SimpleDocTemplate(
            output_path, pagesize=A4,
            rightMargin=1.5 * cm, leftMargin=2.5 * cm,
            topMargin=2 * cm, bottomMargin=2 * cm,
        )

        story: list = []
        eq_name = equipment_data.get("name", "Не указано")

        # Титульная страница
        story.append(Spacer(1, 3 * cm))
        story.append(Paragraph("УТВЕРЖДАЮ", self.styles["RightAligned"]))
        story.append(Paragraph("________________________", self.styles["RightAligned"]))
        story.append(Spacer(1, 2 * cm))
        story.append(Paragraph(
            "ЭКСПЕРТИЗА ПРОМЫШЛЕННОЙ БЕЗОПАСНОСТИ", self.styles["ReportTitle"],
        ))
        story.append(Spacer(1, 0.5 * cm))
        story.append(Paragraph(f"оборудования: {eq_name}", self.styles["ReportSubtitle"]))
        story.append(Spacer(1, 2 * cm))
        story.append(Paragraph(
            f"Дата: {exp_title_date}", self.styles["BodyTextNoIndent"],
        ))
        story.append(PageBreak())

        # 1. Общие сведения
        story.append(Paragraph("1. ОБЩИЕ СВЕДЕНИЯ ОБ ОБОРУДОВАНИИ", self.styles["SectionTitle"]))
        equipment_info = [
            ["Наименование оборудования:", eq_name],
            ["Заводской номер:", equipment_data.get("serial_number", "Не указан")],
            ["Место расположения:", equipment_data.get("location", "Не указано")],
        ]
        self._kv_table(equipment_info, story)
        story.append(Spacer(1, 0.3 * cm))

        # 2. Результаты
        story.append(Paragraph("2. РЕЗУЛЬТАТЫ ЭКСПЕРТИЗЫ", self.styles["SectionTitle"]))
        if inspection_data.get("data"):
            self._add_checklist_data(story, inspection_data["data"], document_files=document_files)

        # 3. Ресурс
        section_num = 3
        if resource_data:
            story.append(Paragraph("3. РЕСУРС ОБОРУДОВАНИЯ", self.styles["SectionTitle"]))
            resource_info = [
                ["Тип ресурса:", resource_data.get("resource_type", "Не указан")],
                ["Текущее значение:", f"{resource_data.get('current_value', 0)} {resource_data.get('unit', '')}"],
                ["Лимит:", f"{resource_data.get('limit_value', 0)} {resource_data.get('unit', '')}"],
                ["Последнее обновление:", resource_data.get("last_updated", "Не указана")],
            ]
            self._kv_table(resource_info, story)
            story.append(Spacer(1, 0.3 * cm))
            section_num = 4

        # Методы НК
        if ndt_methods:
            story.append(Paragraph(
                f"{section_num}. МЕТОДЫ НЕРАЗРУШАЮЩЕГО КОНТРОЛЯ", self.styles["SectionTitle"],
            ))
            header = [
                self._cell_header("Метод НК"),
                self._cell_header("Нормативный документ"),
                self._cell_header("Оборудование"),
                self._cell_header("Инженер"),
                self._cell_header("Уровень"),
                self._cell_header("Результаты"),
            ]
            ndt_rows = [header]
            for method in ndt_methods:
                if method.get("is_performed"):
                    res = method.get("results", "") or ""
                    ndt_rows.append([
                        self._cell_text(method.get("method_name", "")),
                        self._cell_text(method.get("standard", "")),
                        self._cell_text(method.get("equipment", "")),
                        self._cell_text(method.get("inspector_name", "")),
                        self._cell_text(method.get("inspector_level", "")),
                        self._cell_text(res[:50] + "..." if len(res) > 50 else res),
                    ])
            if len(ndt_rows) > 1:
                t = Table(ndt_rows, colWidths=[2.5*cm, 3.0*cm, 3.0*cm, 2.5*cm, 1.5*cm, 4.5*cm])
                t.setStyle(self._gost_table_style())
                story.append(t)
                for method in ndt_methods:
                    if method.get("is_performed"):
                        story.append(Spacer(1, 0.3 * cm))
                        story.append(Paragraph(
                            f"<b>{_escape_para(method.get('method_name', ''))}</b>",
                            self.styles["BodyTextNoIndent"],
                        ))
                        self._build_ndt_detail_section(story, method)
                        if method.get("defects"):
                            story.append(Paragraph(
                                f"<b>Обнаруженные дефекты:</b> {_escape_para(method['defects'])}",
                                self.styles["BodyTextNoIndent"],
                            ))
                        if method.get("conclusion"):
                            story.append(Paragraph(
                                f"<b>Заключение:</b> {_escape_para(method['conclusion'])}",
                                self.styles["BodyTextNoIndent"],
                            ))
            section_num += 1

        # Заключение
        if inspection_data.get("conclusion"):
            story.append(Paragraph(f"{section_num}. ЗАКЛЮЧЕНИЕ", self.styles["SectionTitle"]))
            story.append(Paragraph(inspection_data["conclusion"], self.styles["Conclusion"]))

        # Приложения
        story.append(PageBreak())
        story.append(Paragraph("ПРИЛОЖЕНИЯ", self.styles["SectionTitle"]))
        if specialist_docs:
            for s in specialist_docs:
                story.append(Paragraph(
                    f"Документы специалиста: {s.get('inspector_name', '')}",
                    self.styles["SectionTitle"],
                ))
                for c in s.get("certifications") or []:
                    story.append(Paragraph(
                        f"{c.get('certification_type', '')} "
                        f"№{c.get('certificate_number', '')} "
                        f"({c.get('issuing_organization', '')})",
                        self.styles["BodyText"],
                    ))
        else:
            story.append(Paragraph(
                "Документы специалистов НК не приложены.", self.styles["BodyText"],
            ))

        fallback_eq: list = []
        if not (verification_equipment and isinstance(verification_equipment, list)
                and len(verification_equipment) > 0):
            for m in (ndt_methods or []):
                nm = (m.get("equipment") or "").strip()
                if nm and nm not in [e.get("name") for e in fallback_eq]:
                    fallback_eq.append({"name": nm})
        self._add_verification_equipment_section(story, verification_equipment, fallback_eq)

        # Подпись
        story.append(PageBreak())
        story.append(Spacer(1, 8 * cm))
        story.append(Paragraph("_________________________", self.styles["BodyTextNoIndent"]))
        story.append(Paragraph("Эксперт", self.styles["BodyTextNoIndent"]))
        story.append(Spacer(1, 0.3 * cm))
        story.append(Paragraph(
            f"Дата: {datetime.now().strftime('%d.%m.%Y')}", self.styles["BodyTextNoIndent"],
        ))

        page_handler = self._page_number_handler()
        doc.build(story, onFirstPage=page_handler, onLaterPages=page_handler)
        return output_path

    # ═══════════════════════════════════════════════════════════════
    #  Опросный лист
    # ═══════════════════════════════════════════════════════════════

    def generate_questionnaire_report(
        self,
        questionnaire_data: Dict[str, Any],
        equipment_data: Dict[str, Any],
        questionnaire_info: Dict[str, Any],
        output_path: str,
        ndt_methods: Optional[List[Dict[str, Any]]] = None,
    ):
        """Генерировать PDF опросного листа."""
        self._report_inspection_id = None
        _qn = questionnaire_info.get("questionnaire_id") if isinstance(questionnaire_info, dict) else None
        if not _qn and isinstance(questionnaire_info, dict):
            _qn = questionnaire_info.get("id")
        self._report_questionnaire_id = str(_qn) if _qn else None

        doc = SimpleDocTemplate(
            output_path, pagesize=A4,
            rightMargin=1.5 * cm, leftMargin=2.5 * cm,
            topMargin=2 * cm, bottomMargin=2 * cm,
        )

        story: list = []

        # Титульная
        story.append(Spacer(1, 3 * cm))
        story.append(Paragraph("ОПРОСНЫЙ ЛИСТ", self.styles["ReportTitle"]))
        story.append(Spacer(1, 0.5 * cm))
        story.append(Paragraph(
            f"оборудования: {equipment_data.get('name', 'Не указано')}",
            self.styles["ReportSubtitle"],
        ))
        story.append(Spacer(1, 2 * cm))
        story.append(PageBreak())

        # 1. Общие сведения
        story.append(Paragraph("1. ОБЩИЕ СВЕДЕНИЯ ОБ ОБОРУДОВАНИИ", self.styles["SectionTitle"]))
        equipment_info = [
            ["Наименование оборудования:", equipment_data.get("name", "Не указано")],
            ["Инвентарный номер:", questionnaire_info.get("inventory_number", "Не указан")],
            ["Заводской номер:", equipment_data.get("serial_number", "Не указан")],
            ["Место расположения:", equipment_data.get("location", "Не указано")],
        ]
        self._kv_table(equipment_info, story)
        story.append(Spacer(1, 0.3 * cm))

        # 2. Сведения об обследовании
        story.append(Paragraph("2. СВЕДЕНИЯ ОБ ОБСЛЕДОВАНИИ", self.styles["SectionTitle"]))
        inspection_date = questionnaire_info.get("inspection_date")
        if inspection_date:
            try:
                if "T" in str(inspection_date):
                    inspection_date = datetime.fromisoformat(
                        str(inspection_date).replace("Z", "+00:00")
                    ).strftime("%d.%m.%Y")
                else:
                    inspection_date = datetime.fromisoformat(str(inspection_date)).strftime("%d.%m.%Y")
            except Exception:
                pass

        inspection_info = [
            ["Дата обследования:", inspection_date or "Не указана"],
            ["Инженер:", questionnaire_info.get("inspector_name", "Не указан")],
            ["Должность:", questionnaire_info.get("inspector_position", "Не указана")],
        ]
        self._kv_table(inspection_info, story)
        story.append(Spacer(1, 0.3 * cm))

        # 3. Результаты
        story.append(Paragraph("3. РЕЗУЛЬТАТЫ ОБСЛЕДОВАНИЯ", self.styles["SectionTitle"]))
        if questionnaire_data:
            self._add_questionnaire_data(story, questionnaire_data)

        # 4. Методы НК
        if ndt_methods:
            story.append(Paragraph("4. МЕТОДЫ НЕРАЗРУШАЮЩЕГО КОНТРОЛЯ", self.styles["SectionTitle"]))
            header = [
                self._cell_header("Метод НК"),
                self._cell_header("Нормативный документ"),
                self._cell_header("Оборудование"),
                self._cell_header("Инженер"),
                self._cell_header("Уровень"),
                self._cell_header("Результаты"),
            ]
            ndt_rows = [header]
            for method in ndt_methods:
                if method.get("is_performed"):
                    res = method.get("results", "") or ""
                    ndt_rows.append([
                        self._cell_text(method.get("method_name", "")),
                        self._cell_text(method.get("standard", "")),
                        self._cell_text(method.get("equipment", "")),
                        self._cell_text(method.get("inspector_name", "")),
                        self._cell_text(method.get("inspector_level", "")),
                        self._cell_text(res[:50] + "..." if len(res) > 50 else res),
                    ])
            if len(ndt_rows) > 1:
                t = Table(ndt_rows, colWidths=[2.5*cm, 3.0*cm, 3.0*cm, 2.5*cm, 1.5*cm, 4.5*cm])
                t.setStyle(self._gost_table_style())
                story.append(t)
                for method in ndt_methods:
                    if method.get("is_performed"):
                        story.append(Spacer(1, 0.3 * cm))
                        story.append(Paragraph(
                            f"<b>{_escape_para(method.get('method_name', ''))}</b>",
                            self.styles["BodyTextNoIndent"],
                        ))
                        self._build_ndt_detail_section(story, method)
                        if method.get("defects"):
                            story.append(Paragraph(
                                f"<b>Обнаруженные дефекты:</b> {_escape_para(method['defects'])}",
                                self.styles["BodyTextNoIndent"],
                            ))
                        if method.get("conclusion"):
                            story.append(Paragraph(
                                f"<b>Заключение:</b> {_escape_para(method['conclusion'])}",
                                self.styles["BodyTextNoIndent"],
                            ))

        # Подпись
        story.append(Spacer(1, 0.8 * cm))
        story.append(Paragraph(
            "Инженер: _________________", self.styles["BodyTextNoIndent"],
        ))
        story.append(Paragraph(
            questionnaire_info.get("inspector_name", ""), self.styles["BodyTextNoIndent"],
        ))
        story.append(Spacer(1, 0.3 * cm))
        story.append(Paragraph(
            f"Дата: {inspection_date or datetime.now().strftime('%d.%m.%Y')}",
            self.styles["BodyTextNoIndent"],
        ))

        page_handler = self._page_number_handler()
        doc.build(story, onFirstPage=page_handler, onLaterPages=page_handler)

    # ── Рекурсивный вывод опросного листа ──────────────────────────

    def _add_questionnaire_data(self, story, data: Dict[str, Any], level: int = 0):
        """Рекурсивно добавляет данные опросного листа в PDF."""
        if isinstance(data, dict):
            for key, value in data.items():
                if key == "photos" and isinstance(value, list):
                    continue
                if isinstance(value, (dict, list)):
                    if level == 0:
                        story.append(Paragraph(
                            f"<b>{_escape_para(str(key))}</b>",
                            self.styles["BodyTextNoIndent"],
                        ))
                    else:
                        story.append(Paragraph(
                            f"{'  ' * level}\u2022 {_escape_para(str(key))}",
                            self.styles["BodyTextNoIndent"],
                        ))
                    self._add_questionnaire_data(story, value, level + 1)
                elif value:
                    story.append(Paragraph(
                        f"{'  ' * level}\u2022 <b>{_escape_para(str(key))}:</b> {_escape_para(str(value))}",
                        self.styles["BodyTextNoIndent"],
                    ))
        elif isinstance(data, list):
            for item in data:
                if isinstance(item, dict):
                    self._add_questionnaire_data(story, item, level)
                elif item:
                    story.append(Paragraph(
                        f"{'  ' * level}\u2022 {_escape_para(str(item))}",
                        self.styles["BodyTextNoIndent"],
                    ))
