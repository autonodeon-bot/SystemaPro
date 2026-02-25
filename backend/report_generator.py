"""
Генератор технических отчетов и экспертиз промышленной безопасности
"""
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, Image
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT, TA_JUSTIFY
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from datetime import datetime
from typing import Dict, Any, Optional, List
import os
import io

# Экранирование для Paragraph (избегаем краша на <, >, &)
def _escape_para(s: str) -> str:
    if not s:
        return ""
    s = str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return s

class ReportGenerator:
    """Генератор PDF отчетов"""
    
    def __init__(self):
        self.styles = getSampleStyleSheet()
        self._register_fonts()
        self._setup_custom_styles()
    
    def _register_fonts(self):
        """Регистрация шрифтов с поддержкой русского языка"""
        try:
            # Пытаемся использовать системные шрифты с поддержкой кириллицы.
            # Важно: для "????" в PDF почти всегда виноват шрифт без кириллицы,
            # поэтому стараемся везде использовать DejaVu/Liberation.
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

            # Фолбэк: встроенные шрифты (могут не поддерживать кириллицу)
            self.default_font = "Helvetica"
            self.bold_font = "Helvetica-Bold"
        except Exception as e:
            print(f"Warning: Could not register custom fonts: {e}")
            self.default_font = "Helvetica"
            self.bold_font = "Helvetica-Bold"
    
    def _setup_custom_styles(self):
        """Настройка пользовательских стилей"""
        default_font = getattr(self, "default_font", "Helvetica")
        bold_font = getattr(self, "bold_font", default_font)

        # Критично: в коде ниже иногда используются базовые стили ReportLab (Normal/Heading3).
        # Если их не переопределить на шрифт с кириллицей — в PDF будут "квадратики".
        try:
            if 'Normal' in self.styles.byName:
                self.styles['Normal'].fontName = default_font
            if 'Heading1' in self.styles.byName:
                self.styles['Heading1'].fontName = bold_font
            if 'Heading2' in self.styles.byName:
                self.styles['Heading2'].fontName = bold_font
            if 'Heading3' in self.styles.byName:
                self.styles['Heading3'].fontName = bold_font
        except Exception:
            pass

        # Заголовок отчета
        if 'ReportTitle' not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name='ReportTitle',
                parent=self.styles['Heading1'],
                fontSize=18,
                textColor=colors.HexColor('#1e293b'),
                spaceAfter=30,
                alignment=TA_CENTER,
                fontName=bold_font
            ))
        
        # Подзаголовок
        if 'ReportSubtitle' not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name='ReportSubtitle',
                parent=self.styles['Heading2'],
                fontSize=14,
                textColor=colors.HexColor('#475569'),
                spaceAfter=20,
                alignment=TA_CENTER,
                fontName=default_font
            ))
        
        # Заголовок раздела
        if 'SectionTitle' not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name='SectionTitle',
                parent=self.styles['Heading2'],
                fontSize=14,
                textColor=colors.HexColor('#0f172a'),
                spaceAfter=12,
                spaceBefore=20,
                fontName=bold_font
            ))
        
        # Обычный текст - проверяем, существует ли уже
        if 'BodyText' not in self.styles.byName:
            body_style = ParagraphStyle(
                name='BodyText',
                parent=self.styles['Normal'],
                fontSize=11,
                textColor=colors.HexColor('#334155'),
                alignment=TA_JUSTIFY,
                spaceAfter=10,
                fontName=default_font,
                wordWrap='CJK'  # Включаем перенос слов для длинных строк
            )
            self.styles.add(body_style)
        else:
            # Если стиль уже существует, обновляем его
            self.styles['BodyText'].fontSize = 11
            self.styles['BodyText'].textColor = colors.HexColor('#334155')
            self.styles['BodyText'].alignment = TA_JUSTIFY
            self.styles['BodyText'].spaceAfter = 10
            self.styles['BodyText'].fontName = default_font
            self.styles['BodyText'].wordWrap = 'CJK'  # Включаем перенос слов
        
        # Заключение
        if 'Conclusion' not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name='Conclusion',
                parent=self.styles['Normal'],
                fontSize=12,
                textColor=colors.HexColor('#0f172a'),
                alignment=TA_JUSTIFY,
                spaceAfter=15,
                fontName=bold_font
            ))
        # Стиль для ячеек таблиц (перенос текста)
        if 'TableCell' not in self.styles.byName:
            self.styles.add(ParagraphStyle(
                name='TableCell',
                parent=self.styles['Normal'],
                fontSize=8,
                textColor=colors.HexColor('#334155'),
                alignment=TA_LEFT,
                fontName=default_font,
                wordWrap='CJK',
                leading=10,
            ))
    
    def _cell_text(self, text: Any, style_name: str = 'TableCell') -> Paragraph:
        """Текст ячейки таблицы с переносом (Paragraph)."""
        style = self.styles.get(style_name, self.styles['Normal'])
        return Paragraph(_escape_para(str(text) if text is not None else ""), style)
    
    def _find_image_path(self, path: Optional[str]) -> Optional[str]:
        """Найти существующий файл изображения по пути (для фото таблички, карты замеров, дефектов)."""
        if not path or not isinstance(path, str):
            return None
        path = path.strip().replace("\\", "/")
        possible = [path]
        if os.path.isabs(path) and os.path.isfile(path):
            return path
        bases = [
            "/app/uploads/questionnaire_documents",
            "/app/uploads/ndt_photos",
            "/app/uploads/certification_scans",
            "/app/uploads",
            "/app/reports",
            os.getcwd(),
        ]
        for base in bases:
            possible.append(os.path.join(base, path))
        filename = os.path.basename(path)
        for base in bases:
            possible.append(os.path.join(base, filename))
        qd_base = "/app/uploads/questionnaire_documents"
        if os.path.isdir(qd_base) and filename:
            try:
                for sub in os.listdir(qd_base):
                    possible.append(os.path.join(qd_base, sub, filename))
            except OSError:
                pass
        nd_base = "/app/uploads/ndt_photos"
        if os.path.isdir(nd_base) and filename:
            try:
                for sub1 in os.listdir(nd_base):
                    p1 = os.path.join(nd_base, sub1)
                    if os.path.isdir(p1):
                        for sub2 in os.listdir(p1):
                            possible.append(os.path.join(p1, sub2, filename))
                    possible.append(os.path.join(nd_base, sub1, filename))
            except OSError:
                pass
        for p in possible:
            if p and os.path.exists(p) and os.path.isfile(p):
                return p
        return None
    
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
        """Генерация технического отчета (формат, близкий к реальному отчету ТД)"""
        doc = SimpleDocTemplate(
            output_path,
            pagesize=A4,
            rightMargin=2*cm,
            leftMargin=2*cm,
            topMargin=2*cm,
            bottomMargin=2*cm
        )
        
        story = []
        
        # Титульная страница
        org = ""
        try:
            d = inspection_data.get("data") or {}
            if isinstance(d, dict):
                org = str(d.get("organization") or d.get("organization_name") or "").strip()
        except Exception:
            org = ""

        story.append(Paragraph("ОТЧЕТ О ТЕХНИЧЕСКОМ ДИАГНОСТИРОВАНИИ", self.styles['ReportTitle']))
        story.append(Spacer(1, 0.5*cm))
        story.append(Paragraph("по результатам обследования оборудования", self.styles['ReportSubtitle']))
        if org:
            story.append(Spacer(1, 0.2*cm))
            story.append(Paragraph(f"Организация/объект: {org}", self.styles['BodyText']))
        story.append(Spacer(1, 1*cm))
        story.append(Paragraph(f"Оборудование: {equipment_data.get('name', 'Не указано')}", self.styles['BodyText']))
        story.append(Paragraph(f"Дата формирования: {datetime.now().strftime('%d.%m.%Y')}", self.styles['BodyText']))
        story.append(PageBreak())

        # Содержание (упрощённое)
        story.append(Paragraph("СОДЕРЖАНИЕ", self.styles['SectionTitle']))
        toc = [
            "1. Общая часть",
            "2. Исходные данные и нормативная база",
            "3. Описание объекта и карта обследования",
            "4. Акт(ы) неразрушающего контроля (по методам)",
            "5. Результаты обследования (детализация)",
            "6. Заключение",
            "7. Приложения (фото/схемы/документы специалистов)",
        ]
        for item in toc:
            story.append(Paragraph(item, self.styles['BodyText']))
        story.append(PageBreak())

        # 1. Общая часть
        story.append(Paragraph("1. ОБЩАЯ ЧАСТЬ", self.styles['SectionTitle']))
        story.append(Paragraph(
            "Настоящий отчет составлен по результатам технического диагностирования оборудования с целью "
            "оценки технического состояния и определения возможности дальнейшей безопасной эксплуатации.",
            self.styles['BodyText']
        ))
        story.append(Spacer(1, 0.3*cm))

        # 2. Нормативная база (в будущем можно расширить)
        story.append(Paragraph("2. ИСХОДНЫЕ ДАННЫЕ И НОРМАТИВНАЯ БАЗА", self.styles['SectionTitle']))
        story.append(Paragraph(
            "При выполнении работ использовались данные, предоставленные Заказчиком, результаты обследований и "
            "применимые нормативные документы (ФНП, ГОСТ, РД и др.).",
            self.styles['BodyText']
        ))
        story.append(Spacer(1, 0.3*cm))
        
        # 3. Описание объекта и карта обследования
        story.append(Paragraph("3. ОПИСАНИЕ ОБЪЕКТА И КАРТА ОБСЛЕДОВАНИЯ", self.styles['SectionTitle']))
        
        equipment_info = [
            ['Наименование оборудования:', equipment_data.get('name', 'Не указано')],
            ['Заводской номер:', equipment_data.get('serial_number', 'Не указан')],
            ['Место расположения:', equipment_data.get('location', 'Не указано')],
            ['Дата ввода в эксплуатацию:', equipment_data.get('commissioning_date', 'Не указана')],
        ]
        
        if equipment_data.get('attributes'):
            attrs = equipment_data['attributes']
            if attrs.get('regNumber'):
                equipment_info.append(['Регистрационный номер:', attrs['regNumber']])
            if attrs.get('pressure'):
                equipment_info.append(['Рабочее давление:', attrs['pressure']])
            if attrs.get('volume'):
                equipment_info.append(['Объем:', attrs['volume']])
        
        table = Table(equipment_info, colWidths=[6*cm, 12*cm])
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
            ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            # Важно: используем шрифты с кириллицей, иначе будут "квадратики"
            ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
            ('FONTNAME', (0, 0), (0, -1), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
            ('FONTSIZE', (0, 0), (-1, -1), 10),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
            ('TOPPADDING', (0, 0), (-1, -1), 8),
            ('LEFTPADDING', (0, 0), (-1, -1), 4),
            ('RIGHTPADDING', (0, 0), (-1, -1), 4),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ]))
        story.append(table)
        story.append(Spacer(1, 0.5*cm))
        
        # Информация о диагностике (как исходные данные)
        story.append(Paragraph("Сведения об обследовании:", self.styles['BodyText']))
        
        inspection_info = [
            ['Дата проведения диагностики:', inspection_data.get('date_performed', 'Не указана')],
            ['Статус:', inspection_data.get('status', 'DRAFT')],
        ]
        
        if inspection_data.get('data'):
            data = inspection_data['data']
            if isinstance(data, dict):
                # Добавляем основные данные из диагностики
                if data.get('executors'):
                    inspection_info.append(['Исполнители:', data['executors']])
                if data.get('organization'):
                    inspection_info.append(['Организация:', data['organization']])
        
        table2 = Table(inspection_info, colWidths=[6*cm, 12*cm])
        table2.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
            ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
            ('FONTNAME', (0, 0), (0, -1), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
            ('FONTSIZE', (0, 0), (-1, -1), 10),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
            ('TOPPADDING', (0, 0), (-1, -1), 8),
            ('LEFTPADDING', (0, 0), (-1, -1), 4),
            ('RIGHTPADDING', (0, 0), (-1, -1), 4),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ]))
        story.append(table2)
        story.append(Spacer(1, 0.5*cm))

        # Фото таблички/схема (если загружены)
        if inspection_data.get('data') and isinstance(inspection_data.get('data'), dict):
            self._add_checklist_data(story, inspection_data['data'], document_files=document_files)

        story.append(PageBreak())

        # 4. Акт(ы) НК
        story.append(Paragraph("4. АКТ(Ы) НЕРАЗРУШАЮЩЕГО КОНТРОЛЯ", self.styles['SectionTitle']))
        if ndt_methods:
            performed = [m for m in ndt_methods if m.get("is_performed")]
            if not performed:
                story.append(Paragraph("Методы НК не указаны или не выполнены.", self.styles['BodyText']))
            else:
                for idx, m in enumerate(performed, 1):
                    # Преобразуем код метода в русское название для заголовка
                    method_code = str(m.get("method_code") or "").upper()
                    method_name_ru = m.get("method_name") or ""
                    if not method_name_ru or method_name_ru == method_code:
                        method_mapping = {
                            "VIK": "ВИК",
                            "UZK": "УЗК",
                            "UZT": "УЗТ",
                            "PVK": "ПВК",
                            "MK": "МК",
                            "RK": "РК",
                            "MPD": "МПД",
                            "KPD": "КПД",
                            "TVI": "ТВИ",
                            "AK": "АК",
                            "TK": "ТК",
                        }
                        method_name_ru = method_mapping.get(method_code, method_code or "Метод НК")
                    # Преобразуем код метода в русское название для заголовка и таблицы
                    method_code = str(m.get("method_code") or "").upper()
                    method_name_ru = m.get("method_name") or ""
                    if not method_name_ru or method_name_ru == method_code:
                        method_mapping = {
                            "VIK": "ВИК",
                            "UZK": "УЗК",
                            "UZT": "УЗТ",
                            "PVK": "ПВК",
                            "MK": "МК",
                            "RK": "РК",
                            "MPD": "МПД",
                            "KPD": "КПД",
                            "TVI": "ТВИ",
                            "AK": "АК",
                            "TK": "ТК",
                        }
                        method_name_ru = method_mapping.get(method_code, method_code or "Метод НК")
                    story.append(Paragraph(f"Акт №{idx}. {method_name_ru}", self.styles['Heading3']))
                    
                    # Форматируем значения для таблицы, обрезая длинные строки
                    equipment_val = str(m.get("equipment") or "")
                    if len(equipment_val) > 50:
                        equipment_val = equipment_val[:47] + "..."
                    
                    act_rows = [
                        ["Метод НК:", method_name_ru],
                        ["Код:", method_code],
                        ["Нормативный документ:", str(m.get("standard") or "")],
                        ["Оборудование/прибор:", equipment_val],
                        ["Дата выполнения:", str(m.get("performed_date") or inspection_data.get("date_performed") or "")],
                        ["Специалист:", str(m.get("inspector_name") or "")],
                        ["Уровень:", str(m.get("inspector_level") or "")],
                    ]
                    t = Table(act_rows, colWidths=[6*cm, 12*cm])
                    t.setStyle(TableStyle([
                        ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
                        ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
                        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                        ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                        ('FONTNAME', (0, 0), (0, -1), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                        ('FONTSIZE', (0, 0), (-1, -1), 9),
                        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
                        ('TOPPADDING', (0, 0), (-1, -1), 6),
                        ('LEFTPADDING', (0, 0), (-1, -1), 4),
                        ('RIGHTPADDING', (0, 0), (-1, -1), 4),
                        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                    ]))
                    story.append(t)
                    story.append(Spacer(1, 0.2*cm))
                    if m.get("results"):
                        results_text = str(m.get('results') or '')
                        # Разбиваем длинные строки на параграфы
                        if len(results_text) > 100:
                            # Разбиваем по предложениям или запятым
                            parts = results_text.split('. ')
                            for part in parts:
                                if part.strip():
                                    story.append(Paragraph(f"<b>Результаты:</b> {part.strip()}.", self.styles['Normal']))
                        else:
                            story.append(Paragraph(f"<b>Результаты:</b> {results_text}", self.styles['Normal']))
                    if m.get("defects"):
                        defects_text = str(m.get('defects') or '')
                        if len(defects_text) > 100:
                            parts = defects_text.split('. ')
                            for part in parts:
                                if part.strip():
                                    story.append(Paragraph(f"<b>Дефекты:</b> {part.strip()}.", self.styles['Normal']))
                        else:
                            story.append(Paragraph(f"<b>Дефекты:</b> {defects_text}", self.styles['Normal']))
                    if m.get("conclusion"):
                        conclusion_text = str(m.get('conclusion') or '')
                        if len(conclusion_text) > 100:
                            parts = conclusion_text.split('. ')
                            for part in parts:
                                if part.strip():
                                    story.append(Paragraph(f"<b>Заключение:</b> {part.strip()}.", self.styles['Normal']))
                        else:
                            story.append(Paragraph(f"<b>Заключение:</b> {conclusion_text}", self.styles['Normal']))

                    # Фото по методу НК
                    photos = m.get("photos") or []
                    # Также проверяем аннотированные изображения
                    additional_data = m.get("additional_data", {})
                    annotated_images = []
                    if isinstance(additional_data, dict):
                        annotated_images = additional_data.get("annotated_images", []) or []
                    
                    # Объединяем обычные фото и аннотированные
                    all_photos = list(photos) if isinstance(photos, list) else []
                    if isinstance(annotated_images, list):
                        all_photos.extend(annotated_images)
                    
                    if all_photos:
                        story.append(Paragraph("Фотоматериалы (карта замеров, фото дефектов):", self.styles['BodyText']))
                        for p in all_photos[:15]:
                            if not isinstance(p, str):
                                continue
                            found_path = self._find_image_path(p)
                            if found_path:
                                try:
                                    img = Image(found_path)
                                    max_w, max_h = 12.8 * cm, 8 * cm
                                    iw = getattr(img, 'imageWidth', None) or max_w
                                    ih = getattr(img, 'imageHeight', None) or max_h
                                    if iw and ih:
                                        ratio = min(max_w / float(iw), max_h / float(ih), 1.0)
                                        img.drawWidth = iw * ratio
                                        img.drawHeight = ih * ratio
                                    else:
                                        img.drawWidth = max_w
                                        img.drawHeight = max_h
                                    story.append(img)
                                    story.append(Spacer(1, 0.2*cm))
                                except Exception as e:
                                    print(f"Warning: Could not add NDT photo {found_path}: {e}")
                                    pass
                    story.append(Spacer(1, 0.4*cm))
        else:
            story.append(Paragraph("Методы НК не указаны.", self.styles['BodyText']))

        story.append(PageBreak())
        
        # Детальные данные диагностики
        if inspection_data.get('data'):
            story.append(Paragraph("5. РЕЗУЛЬТАТЫ ОБСЛЕДОВАНИЯ (ДЕТАЛИЗАЦИЯ)", self.styles['SectionTitle']))
            data = inspection_data['data']
            if isinstance(data, dict):
                # Добавляем данные из чек-листа
                self._add_checklist_data(story, data, document_files=document_files)
        
        # Заключение
        if inspection_data.get('conclusion'):
            story.append(Paragraph("6. ЗАКЛЮЧЕНИЕ", self.styles['SectionTitle']))
            story.append(Paragraph(inspection_data['conclusion'], self.styles['Conclusion']))

        # Приложения: документы специалистов НК
        story.append(PageBreak())
        story.append(Paragraph("7. ПРИЛОЖЕНИЯ", self.styles['SectionTitle']))
        if specialist_docs:
            for s in specialist_docs:
                story.append(Paragraph(f"Документы специалиста: {s.get('inspector_name','')}", self.styles['Heading3']))
                certs = s.get("certifications") or []
                for c in certs:
                    line = f"{c.get('certification_type','')} №{c.get('certificate_number','')} ({c.get('issuing_organization','')})"
                    story.append(Paragraph(line, self.styles['BodyText']))
                    sp = c.get("scan_file_path")
                    mt = (c.get("scan_mime_type") or "")
                    # Встраиваем изображения; PDF перечисляем строкой (встраивание страниц PDF в ReportLab не делаем)
                    if isinstance(sp, str) and ("image" in mt.lower()):
                        # Проверяем различные варианты путей
                        possible_paths = [sp]
                        if not os.path.isabs(sp):
                            possible_paths.extend([
                                f"/app/uploads/{sp}",
                                f"/app/uploads/certifications/{sp}",
                                f"/opt/es-td-ngo/backend/uploads/{sp}",
                            ])
                        
                        # Если путь содержит только имя файла
                        if "/" not in sp or sp.count("/") == 0:
                            filename = os.path.basename(sp)
                            possible_paths.extend([
                                f"/app/uploads/certifications/{filename}",
                                f"/app/uploads/{filename}",
                            ])
                        
                        found_path = None
                        for path_option in possible_paths:
                            if os.path.exists(path_option) and os.path.isfile(path_option):
                                found_path = path_option
                                break
                        
                        if found_path:
                            try:
                                img = Image(found_path)
                                img.drawWidth = 12.8 * cm
                                img.drawHeight = 8 * cm
                                story.append(img)
                                story.append(Spacer(1, 0.2*cm))
                            except Exception as e:
                                print(f"Warning: Could not add certification scan {found_path}: {e}")
                                pass
        else:
            story.append(Paragraph("Документы специалистов НК не приложены.", self.styles['BodyText']))
        
        # Используемое оборудование для поверок
        fallback_equipment = []
        if not (verification_equipment and isinstance(verification_equipment, list) and len(verification_equipment) > 0):
            for m in (ndt_methods or []):
                name = (m.get('equipment') or '').strip()
                if not name:
                    continue
                if name not in [e.get('name') for e in fallback_equipment]:
                    fallback_equipment.append({'name': name})

        if verification_equipment and isinstance(verification_equipment, list) and len(verification_equipment) > 0:
            story.append(Spacer(1, 0.5*cm))
            story.append(Paragraph("7.1. Используемое оборудование для неразрушающего контроля", self.styles['Heading3']))
            story.append(Paragraph(
                "При проведении обследования использовалось следующее поверенное оборудование:",
                self.styles['BodyText']
            ))
            
            eq_table_data = [['№', 'Наименование', 'Тип', 'Серийный номер', 'Срок поверки', 'Свидетельство']]
            for idx, eq in enumerate(verification_equipment, 1):
                next_date = eq.get('next_verification_date', '')
                if next_date:
                    try:
                        from datetime import datetime as dt
                        d = dt.fromisoformat(next_date.replace('Z', '+00:00'))
                        next_date = d.strftime('%d.%m.%Y')
                    except:
                        pass
                
                cert_num = eq.get('verification_certificate_number', '')
                eq_table_data.append([
                    str(idx),
                    eq.get('name', ''),
                    eq.get('equipment_type', ''),
                    eq.get('serial_number', ''),
                    next_date,
                    cert_num if cert_num else '—',
                ])
            
            eq_table = Table(eq_table_data, colWidths=[0.8*cm, 5*cm, 2.5*cm, 3*cm, 3*cm, 3.7*cm])
            eq_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 9),
                ('FONTSIZE', (0, 1), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ]))
            story.append(eq_table)
            story.append(Spacer(1, 0.3*cm))
            
            # Добавляем сканы свидетельств о поверке
            story.append(Paragraph("Сканы свидетельств о поверке используемого оборудования:", self.styles['BodyText']))
            for eq in verification_equipment:
                scan_path = eq.get('scan_file_path')
                scan_name = eq.get('scan_file_name', '')
                eq_name = eq.get('name', '')
                
                if scan_path and os.path.exists(scan_path):
                    story.append(Spacer(1, 0.2*cm))
                    story.append(Paragraph(f"Свидетельство о поверке: {eq_name} ({scan_name})", self.styles['BodyText']))
                    try:
                        # Пытаемся встроить изображение (для PDF/PNG/JPG)
                        mime_type = eq.get('scan_mime_type', '')
                        if 'image' in mime_type.lower():
                            # Проверяем различные варианты путей
                            possible_paths = [scan_path]
                            if not os.path.isabs(scan_path):
                                possible_paths.extend([
                                    f"/app/uploads/verification_scans/{scan_path}",
                                    f"/app/uploads/{scan_path}",
                                    f"/opt/es-td-ngo/backend/uploads/verification_scans/{scan_path}",
                                ])
                            
                            # Если путь содержит только имя файла
                            if "/" not in scan_path or scan_path.count("/") == 0:
                                filename = os.path.basename(scan_path)
                                possible_paths.extend([
                                    f"/app/uploads/verification_scans/{filename}",
                                    f"/app/uploads/{filename}",
                                ])
                            
                            found_path = None
                            for path_option in possible_paths:
                                if os.path.exists(path_option) and os.path.isfile(path_option):
                                    found_path = path_option
                                    break
                            
                            if found_path:
                                try:
                                    img = Image(found_path)
                                    img.drawWidth = 12.8 * cm
                                    img.drawHeight = 8 * cm
                                    story.append(img)
                                    story.append(Spacer(1, 0.2*cm))
                                except Exception as e:
                                    print(f"Warning: Could not add verification scan {found_path}: {e}")
                                    pass
                        else:
                            # Для PDF просто указываем, что файл приложен
                            story.append(Paragraph(f"Файл: {scan_name}", self.styles['BodyText']))
                    except Exception as e:
                        story.append(Paragraph(f"Не удалось встроить изображение: {str(e)}", self.styles['BodyText']))
        elif fallback_equipment:
            story.append(Spacer(1, 0.5*cm))
            story.append(Paragraph("7.1. Используемое оборудование для неразрушающего контроля", self.styles['Heading3']))
            story.append(Paragraph(
                "При проведении обследования использовалось следующее оборудование (из данных методов НК):",
                self.styles['BodyText']
            ))
            eq_table_data = [['№', 'Наименование', 'Тип', 'Серийный номер', 'Срок поверки', 'Свидетельство']]
            for idx, eq in enumerate(fallback_equipment, 1):
                eq_table_data.append([
                    str(idx),
                    eq.get('name', ''),
                    '—',
                    '—',
                    '—',
                    '—',
                ])
            eq_table = Table(eq_table_data, colWidths=[0.8*cm, 5*cm, 2.5*cm, 3*cm, 3*cm, 3.7*cm])
            eq_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 9),
                ('FONTSIZE', (0, 1), (-1, -1), 8),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
                ('TOPPADDING', (0, 0), (-1, -1), 6),
                ('LEFTPADDING', (0, 0), (-1, -1), 4),
                ('RIGHTPADDING', (0, 0), (-1, -1), 4),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ]))
            story.append(eq_table)
        else:
            # Если нет ни verification_equipment, ни fallback_equipment, показываем сообщение
            story.append(Spacer(1, 0.5*cm))
            story.append(Paragraph("7.1. Используемое оборудование для неразрушающего контроля", self.styles['Heading3']))
            story.append(Paragraph("Приборы не указаны.", self.styles['BodyText']))
        
        # Подпись
        story.append(Spacer(1, 0.8*cm))
        story.append(Paragraph("Ответственный исполнитель: _________________________", self.styles['BodyText']))
        story.append(Paragraph(f"Дата: {datetime.now().strftime('%d.%m.%Y')}", self.styles['BodyText']))
        
        doc.build(story)
        return output_path
    
    def _add_checklist_data(self, story, data: Dict[str, Any], document_files: Optional[List[Dict[str, Any]]] = None):
        """Добавление данных из чек-листа"""
        # Поддерживаем обе схемы ключей (snake_case из мобильного и camelCase из старых версий)
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
                camel_key = ''.join(word.capitalize() if i > 0 else word for i, word in enumerate(k.split('_')))
                camel_key_lower = camel_key[0].lower() + camel_key[1:] if camel_key else k
                if camel_key_lower in opo and opo.get(camel_key_lower) not in (None, ""):
                    return opo.get(camel_key_lower)
            return _get(*keys, default=default)

        # Быстрый индекс вложений по ключу (document_number -> file_path)
        attachments: Dict[str, str] = {}
        if document_files and isinstance(document_files, list):
            for f in document_files:
                if not isinstance(f, dict):
                    continue
                dn = str(f.get("document_number") or "")
                fp = f.get("file_path")
                if dn and isinstance(fp, str) and fp:
                    attachments[dn] = fp

        def _add_image_if_exists(title: str, path: Optional[str]):
            """Добавить изображение в отчет, если оно существует"""
            if not path or not isinstance(path, str):
                return
            found_path = self._find_image_path(path)
            if not found_path:
                return
            try:
                story.append(Paragraph(title, self.styles['BodyText']))
                img = Image(found_path)
                # Вписать в ширину страницы (≈12.8 см после -20%), сохраняя пропорции
                max_w, max_h = 12.8 * cm, 9.6 * cm
                iw = getattr(img, 'imageWidth', None) or getattr(img, '_width', max_w)
                ih = getattr(img, 'imageHeight', None) or getattr(img, '_height', max_h)
                if iw and ih:
                    ratio = min(max_w / float(iw), max_h / float(ih), 1.0)
                    img.drawWidth = iw * ratio
                    img.drawHeight = ih * ratio
                else:
                    img.drawWidth = max_w
                    img.drawHeight = max_h
                story.append(img)
                story.append(Spacer(1, 0.3 * cm))
            except Exception as e:
                print(f"Warning: Could not add image {found_path}: {e}")
                pass

        # Сведения об ОПО (если есть)
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
            story.append(Paragraph("Сведения об ОПО", self.styles['SectionTitle']))
            rows = []
            def _add_row(label, value):
                if value is None:
                    return
                s = str(value).strip()
                if not s:
                    return
                rows.append([label, s])
            _add_row("Наименование ОПО", opo_name)
            _add_row("Код ОПО", opo_code)
            _add_row("Описание", opo_desc)
            _add_row("Предприятие", opo_enterprise)
            _add_row("Филиал", opo_branch)
            _add_row("Цех", opo_workshop)
            _add_row("Организация (опросный лист ОПО)", opo_org)
            _add_row("Исполнители (опросный лист ОПО)", opo_exec)
            if rows:
                # Ячейки со значениями — Paragraph для переноса длинного текста
                table_rows = []
                for r in rows:
                    table_rows.append([self._cell_text(r[0]), self._cell_text(r[1])])
                table = Table(table_rows, colWidths=[5*cm, 11*cm])
                table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
                    ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                    ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                    ('FONTNAME', (0, 0), (0, -1), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                    ('FONTSIZE', (0, 0), (-1, -1), 9),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
                    ('TOPPADDING', (0, 0), (-1, -1), 6),
                    ('LEFTPADDING', (0, 0), (-1, -1), 4),
                    ('RIGHTPADDING', (0, 0), (-1, -1), 4),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ]))
                story.append(table)
                story.append(Spacer(1, 0.4*cm))

        # Документы
        docs = _get('documents', default={})
        docs_info = _get('documents_info', default={})
        if docs or docs_info:
            story.append(Paragraph("3.1. Перечень рассмотренных документов", self.styles['SectionTitle']))
            doc_data = [['№', 'Наименование документа', 'Номер документа', 'Дата документа', 'Наличие']]
            # Список названий документов (из мобильного приложения)
            document_names = {
                '1': 'Лицензия на осуществление деятельности по эксплуатации взрывопожароопасных и химически опасных производственных объектов I, II и III классов опасности',
                '2': 'Свидетельство о регистрации в государственном реестре ОПО, включая сведения характеризующие ОПО',
                '3': 'Технологический регламент объектов опасных производственных объектов',
                '4': 'План мероприятий по локализации и ликвидации последствий аварий на опасном производственном объекте',
                '5': 'Положение о производственном контроле за соблюдением требований промышленной безопасности на опасных производственных объектах',
                '6': 'Журнал учета аварий и инцидентов на ОПО',
                '7': 'Страховой полис страхования гражданской ответственности владельца опасного объекта за причинение вреда в результате аварии на опасном объекте',
                '8': 'Приказ о назначении ответственного лица за исправное состояние и безопасную эксплуатацию сосудов',
                '9': 'Приказ о назначении ответственного лица за осуществление производственного контроля и соблюдение требований промышленной безопасности на опасном производственном объекте',
                '10': 'Паспорт сосуда заводской (удостоверение о качестве монтажа, сертификат соответствия, сборочный чертёж и схема включения сосуда, расчёт на прочность)',
                '11': 'Инструкция по монтажу и эксплуатации',
                '12': 'Паспорта на предохранительные клапаны',
                '13': 'Паспорта на запорную арматуру',
                '14': 'Документация на контрольно-измерительные приборы',
                '15': 'Ремонтная (исполнительная) документация',
                '16': 'Заключение экспертизы промышленной безопасности',
                '17': 'Акты проведения УЗТ',
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
                return (present, doc_number, doc_date)

            doc_keys = set()
            if isinstance(docs, dict):
                doc_keys.update([str(k) for k in docs.keys()])
            if isinstance(docs_info, dict):
                doc_keys.update([str(k) for k in docs_info.keys()])
            doc_keys = sorted(doc_keys, key=lambda x: int(x) if str(x).isdigit() else 999)

            for num in doc_keys:
                doc_name = document_names.get(str(num), f'Документ {num}')
                present, doc_number, doc_date = _doc_meta(str(num))
                presence_text = 'Да' if present else '—'
                doc_data.append([
                    self._cell_text(num),
                    self._cell_text(doc_name),
                    self._cell_text(doc_number or '—'),
                    self._cell_text(doc_date or '—'),
                    self._cell_text(presence_text)
                ])
            table = Table(doc_data, colWidths=[0.8*cm, 7*cm, 2.5*cm, 2.5*cm, 1.5*cm])
            table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 9),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
                ('TOPPADDING', (0, 0), (-1, -1), 6),
                ('LEFTPADDING', (0, 0), (-1, -1), 4),
                ('RIGHTPADDING', (0, 0), (-1, -1), 4),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
            ]))
            story.append(table)
            story.append(Spacer(1, 0.5*cm))
        
        # Карта обследования
        vessel_name = _get('vessel_name', 'vesselName')
        if vessel_name:
            story.append(Paragraph("3.2. Карта обследования", self.styles['SectionTitle']))
            vessel_data = [
                ['Наименование сосуда:', vessel_name or ''],
                ['Заводской номер:', _get('serial_number', 'serialNumber', default='') or ''],
                ['Регистрационный номер:', _get('reg_number', 'regNumber', default='') or ''],
            ]
            working_pressure = _get('working_pressure', 'workingPressure')
            diameter = _get('diameter')
            if working_pressure:
                vessel_data.append(['Рабочее давление:', working_pressure])
            if diameter:
                vessel_data.append(['Диаметр сосуда:', diameter])
            
            table = Table(vessel_data, colWidths=[6*cm, 12*cm])
            table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
                ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (0, -1), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, -1), 10),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                ('TOPPADDING', (0, 0), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
            ]))
            story.append(table)
            story.append(Spacer(1, 0.5*cm))

        # Фото заводской таблички (как в мобильном)
        plate_path = _get('factory_plate_photo', 'factoryPlatePhoto')
        # Проверяем в attachments и в данных
        plate_to_use = attachments.get("factory_plate_photo") or plate_path
        if not plate_to_use and inspection_data.get("data") and isinstance(inspection_data.get("data"), dict):
            plate_to_use = inspection_data["data"].get("factory_plate_photo") or inspection_data["data"].get("factoryPlatePhoto")
        
        # Также проверяем в дополнительных данных
        if not plate_to_use:
            additional_data = inspection_data.get("additional_data", {})
            if isinstance(additional_data, dict):
                plate_to_use = additional_data.get("factory_plate_photo") or additional_data.get("factoryPlatePhoto")
        
        _add_image_if_exists("Фото заводской таблички:", plate_to_use)

        # Толщинометрия (УЗТ) — таблица + схема (если есть)
        thickness = _get('thickness_measurements', 'thicknessMeasurements', default=[])
        if isinstance(thickness, list) and len(thickness) > 0:
            story.append(Paragraph("3.3. УЗТ (Ультразвуковая толщинометрия)", self.styles['SectionTitle']))
            thickness_table_data = [['№', 'Местоположение', 'Сечение', 'Толщина, мм', 'Мин. доп., мм', 'Комментарий']]
            for idx, point in enumerate(thickness, 1):
                if not isinstance(point, dict):
                    continue
                thickness_table_data.append([
                    self._cell_text(idx),
                    self._cell_text(point.get('location') or ''),
                    self._cell_text(point.get('section_number') or ''),
                    self._cell_text(point.get('thickness') or ''),
                    self._cell_text(point.get('min_allowed_thickness') or ''),
                    self._cell_text(point.get('comment') or ''),
                ])
            if len(thickness_table_data) > 1:
                t = Table(thickness_table_data, colWidths=[0.6*cm, 2.8*cm, 1.2*cm, 1.4*cm, 1.4*cm, 6.5*cm])
                t.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", self.default_font)),
                    ('FONTSIZE', (0, 0), (-1, 0), 8),
                    ('FONTSIZE', (0, 1), (-1, -1), 7),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
                    ('TOPPADDING', (0, 0), (-1, -1), 6),
                    ('LEFTPADDING', (0, 0), (-1, -1), 4),
                    ('RIGHTPADDING', (0, 0), (-1, -1), 4),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
                    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ]))
                story.append(t)
                story.append(Spacer(1, 0.3*cm))

            scheme_path = _get('control_scheme_image', 'controlSchemeImage')
            # Проверяем в attachments и в данных
            scheme_to_use = attachments.get("control_scheme_image") or scheme_path
            if not scheme_to_use:
                # Пробуем найти в данных inspection_data
                if inspection_data.get("data") and isinstance(inspection_data.get("data"), dict):
                    scheme_to_use = inspection_data["data"].get("control_scheme_image") or inspection_data["data"].get("controlSchemeImage")
            
            # Также проверяем в дополнительных данных
            if not scheme_to_use:
                additional_data = inspection_data.get("additional_data", {})
                if isinstance(additional_data, dict):
                    scheme_to_use = additional_data.get("control_scheme_image") or additional_data.get("controlSchemeImage")
            
            _add_image_if_exists("Схема контроля:", scheme_to_use)
        else:
            scheme_path = _get('control_scheme_image', 'controlSchemeImage')
            scheme_to_use = attachments.get("control_scheme_image") or scheme_path
            if not scheme_to_use:
                # Пробуем найти в данных inspection_data
                if inspection_data.get("data") and isinstance(inspection_data.get("data"), dict):
                    scheme_to_use = inspection_data["data"].get("control_scheme_image") or inspection_data["data"].get("controlSchemeImage")
            
            # Также проверяем в дополнительных данных
            if not scheme_to_use:
                additional_data = inspection_data.get("additional_data", {})
                if isinstance(additional_data, dict):
                    scheme_to_use = additional_data.get("control_scheme_image") or additional_data.get("controlSchemeImage")
            
            _add_image_if_exists("Схема контроля:", scheme_to_use)

        # ЗРА
        zra = _get('zra_items', default=[])
        if isinstance(zra, list) and zra:
            story.append(Paragraph("3.4. ЗРА (запорно-регулирующая арматура)", self.styles['SectionTitle']))
            zra_rows = [['№', 'Кол-во', 'Типоразмер', 'Тех. №', 'Зав. №', 'Место на схеме']]
            for i, it in enumerate(zra, 1):
                if not isinstance(it, dict):
                    continue
                zra_rows.append([
                    self._cell_text(i),
                    self._cell_text(it.get('quantity') or ''),
                    self._cell_text(it.get('type_size') or ''),
                    self._cell_text(it.get('tech_number') or ''),
                    self._cell_text(it.get('serial_number') or ''),
                    self._cell_text(it.get('location_on_scheme') or ''),
                ])
            t = Table(zra_rows, colWidths=[0.6*cm, 1*cm, 2.5*cm, 2*cm, 2*cm, 6.5*cm])
            t.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 8),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
                ('TOPPADDING', (0, 0), (-1, -1), 4),
                ('LEFTPADDING', (0, 0), (-1, -1), 3),
                ('RIGHTPADDING', (0, 0), (-1, -1), 3),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
            ]))
            story.append(t)
            story.append(Spacer(1, 0.3*cm))

        # СППК
        sppk = _get('sppk_items', default=[])
        if isinstance(sppk, list) and sppk:
            story.append(Paragraph("3.5. СППК (предохранительные клапаны)", self.styles['SectionTitle']))
            sppk_rows = [['№', 'Кол-во', 'Типоразмер', 'Тех. №', 'Зав. №', 'Место на схеме']]
            for i, it in enumerate(sppk, 1):
                if not isinstance(it, dict):
                    continue
                sppk_rows.append([
                    self._cell_text(i),
                    self._cell_text(it.get('quantity') or ''),
                    self._cell_text(it.get('type_size') or ''),
                    self._cell_text(it.get('tech_number') or ''),
                    self._cell_text(it.get('serial_number') or ''),
                    self._cell_text(it.get('location_on_scheme') or ''),
                ])
            t = Table(sppk_rows, colWidths=[0.6*cm, 1*cm, 2.5*cm, 2*cm, 2*cm, 6.5*cm])
            t.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 8),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
                ('TOPPADDING', (0, 0), (-1, -1), 4),
                ('LEFTPADDING', (0, 0), (-1, -1), 3),
                ('RIGHTPADDING', (0, 0), (-1, -1), 3),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
            ]))
            story.append(t)
            story.append(Spacer(1, 0.3*cm))

        # Овальность
        ovality = _get('ovality_measurements', default=[])
        if isinstance(ovality, list) and ovality:
            story.append(Paragraph("3.6. Измерительный контроль — овальность", self.styles['SectionTitle']))
            rows = [['№', 'Сечение', 'Dmax', 'Dmin', 'Отклонение, %']]
            for i, it in enumerate(ovality, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    str(i),
                    str(it.get('section_number', '') or ''),
                    str(it.get('max_diameter', '') or ''),
                    str(it.get('min_diameter', '') or ''),
                    str(it.get('deviation_percent', '') or ''),
                ])
            t = Table(rows, colWidths=[0.8*cm, 3.0*cm, 4.0*cm, 4.0*cm, 4.2*cm])
            t.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 8),
                ('FONTSIZE', (0, 1), (-1, -1), 7),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
            ]))
            story.append(t)
            story.append(Spacer(1, 0.3*cm))

        # Прогиб
        deflection = _get('deflection_measurements', default=[])
        if isinstance(deflection, list) and deflection:
            story.append(Paragraph("3.7. Измерительный контроль — прогиб", self.styles['SectionTitle']))
            rows = [['№', 'Сечение', 'Прогиб, мм', 'Прогиб, %']]
            for i, it in enumerate(deflection, 1):
                if not isinstance(it, dict):
                    continue
                raw_pct = it.get('deflection_percent', '') or ''
                try:
                    deflection_pct = f"{float(str(raw_pct).replace(',', '.')):.2f}"
                except Exception:
                    deflection_pct = str(raw_pct)
                rows.append([
                    str(i),
                    str(it.get('section_number', '') or ''),
                    str(it.get('deflection_mm', '') or ''),
                    deflection_pct,
                ])
            t = Table(rows, colWidths=[0.8*cm, 3.0*cm, 7.0*cm, 7.2*cm])
            t.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 8),
                ('FONTSIZE', (0, 1), (-1, -1), 7),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
            ]))
            story.append(t)
            story.append(Spacer(1, 0.3*cm))

        # Твердость
        hardness = _get('hardness_tests', default=[])
        if isinstance(hardness, list) and hardness:
            story.append(Paragraph("3.8. Контроль твердости", self.styles['SectionTitle']))
            rows = [['№', 'Шов', 'Участок', 'Доп. осн', 'Доп. шов', 'Осн', 'Шов', 'ЗТВ']]
            for i, it in enumerate(hardness, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    str(i),
                    str(it.get('weld_number', '') or ''),
                    str(it.get('area_number', '') or ''),
                    str(it.get('allowed_hardness_base', '') or ''),
                    str(it.get('allowed_hardness_weld', '') or ''),
                    str(it.get('hardness_base', '') or ''),
                    str(it.get('hardness_weld', '') or ''),
                    str(it.get('hardness_haz', '') or ''),
                ])
            t = Table(rows, colWidths=[0.7*cm, 1.2*cm, 1.5*cm, 2.1*cm, 2.1*cm, 2.1*cm, 2.1*cm, 2.2*cm])
            t.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 8),
                ('FONTSIZE', (0, 1), (-1, -1), 7),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
            ]))
            story.append(t)
            story.append(Spacer(1, 0.3*cm))

        # Сварные соединения
        welds = _get('weld_inspections', default=[])
        if isinstance(welds, list) and welds:
            story.append(Paragraph("3.9. Контроль сварных соединений (ПВК/УЗК)", self.styles['SectionTitle']))
            rows = [['№', 'Шов', 'Место на карте', 'ПВК дефект', 'УЗК дефект', 'Заключение']]
            for i, it in enumerate(welds, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    str(i),
                    str(it.get('weld_number', '') or ''),
                    str(it.get('location_on_control_map', '') or ''),
                    str(it.get('pvk_defect', '') or ''),
                    str(it.get('uzk_defect', '') or ''),
                    str(it.get('conclusion', '') or ''),
                ])
            t = Table(rows, colWidths=[0.7*cm, 1.2*cm, 4.0*cm, 4.0*cm, 4.0*cm, 4.1*cm])
            t.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 8),
                ('FONTSIZE', (0, 1), (-1, -1), 7),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
            ]))
            story.append(t)
            story.append(Spacer(1, 0.3*cm))
    
    def generate_expertise_report(self, inspection_data: Dict[str, Any], equipment_data: Dict[str, Any],
                                  resource_data: Optional[Dict[str, Any]], output_path: str, 
                                  ndt_methods: Optional[List[Dict[str, Any]]] = None,
                                  document_files: Optional[List[Dict[str, Any]]] = None,
                                  specialist_docs: Optional[List[Dict[str, Any]]] = None,
                                  verification_equipment: Optional[List[Dict[str, Any]]] = None) -> str:
        """Генерация экспертизы промышленной безопасности"""
        doc = SimpleDocTemplate(
            output_path,
            pagesize=A4,
            rightMargin=2*cm,
            leftMargin=2*cm,
            topMargin=2*cm,
            bottomMargin=2*cm
        )
        
        story = []
        
        # Титульная страница
        story.append(Paragraph("ЭКСПЕРТИЗА ПРОМЫШЛЕННОЙ БЕЗОПАСНОСТИ", self.styles['ReportTitle']))
        story.append(Spacer(1, 0.5*cm))
        story.append(Paragraph(f"оборудования: {equipment_data.get('name', 'Не указано')}", self.styles['ReportSubtitle']))
        story.append(Spacer(1, 1*cm))
        
        # Информация об оборудовании (аналогично техническому отчету)
        story.append(Paragraph("1. ОБЩИЕ СВЕДЕНИЯ ОБ ОБОРУДОВАНИИ", self.styles['SectionTitle']))
        
        equipment_info = [
            ['Наименование оборудования:', equipment_data.get('name', 'Не указано')],
            ['Заводской номер:', equipment_data.get('serial_number', 'Не указан')],
            ['Место расположения:', equipment_data.get('location', 'Не указано')],
        ]
        
        table = Table(equipment_info, colWidths=[6*cm, 12*cm])
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
            ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
            ('FONTNAME', (0, 0), (0, -1), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
            ('FONTSIZE', (0, 0), (-1, -1), 10),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
            ('TOPPADDING', (0, 0), (-1, -1), 8),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ]))
        story.append(table)
        story.append(Spacer(1, 0.5*cm))
        
        # Результаты диагностики
        story.append(Paragraph("2. РЕЗУЛЬТАТЫ ЭКСПЕРТИЗЫ", self.styles['SectionTitle']))
        if inspection_data.get('data'):
            self._add_checklist_data(story, inspection_data['data'], document_files=document_files)
        
        # Ресурс оборудования
        if resource_data:
            story.append(Paragraph("3. РЕСУРС ОБОРУДОВАНИЯ", self.styles['SectionTitle']))
            resource_info = [
                ['Тип ресурса:', resource_data.get('resource_type', 'Не указан')],
                ['Текущее значение:', f"{resource_data.get('current_value', 0)} {resource_data.get('unit', '')}"],
                ['Лимит:', f"{resource_data.get('limit_value', 0)} {resource_data.get('unit', '')}"],
                ['Последнее обновление:', resource_data.get('last_updated', 'Не указана')],
            ]
            
            table = Table(resource_info, colWidths=[6*cm, 12*cm])
            table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
                ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (0, -1), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, -1), 10),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                ('TOPPADDING', (0, 0), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
            ]))
            story.append(table)
            story.append(Spacer(1, 0.5*cm))
            section_num = 4
        else:
            section_num = 3
        
        # Методы неразрушающего контроля
        if ndt_methods:
            story.append(Paragraph(f"{section_num}. МЕТОДЫ НЕРАЗРУШАЮЩЕГО КОНТРОЛЯ", self.styles['SectionTitle']))
            
            # Таблица методов НК
            ndt_table_data = [['Метод НК', 'Нормативный документ', 'Оборудование', 'Инженер', 'Уровень', 'Результаты']]
            for method in ndt_methods:
                if method.get('is_performed'):
                    ndt_table_data.append([
                        method.get('method_name', ''),
                        method.get('standard', ''),
                        method.get('equipment', ''),
                        method.get('inspector_name', ''),
                        method.get('inspector_level', ''),
                        method.get('results', '')[:50] + '...' if method.get('results') and len(method.get('results', '')) > 50 else method.get('results', ''),
                    ])
            
            if len(ndt_table_data) > 1:
                ndt_table = Table(ndt_table_data, colWidths=[3*cm, 3*cm, 3*cm, 3*cm, 2*cm, 4*cm])
                ndt_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                    ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('FONTSIZE', (0, 1), (-1, -1), 8),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
                    ('TOPPADDING', (0, 0), (-1, -1), 6),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
                ]))
                story.append(ndt_table)
                
                # Детальная информация по каждому методу
                for method in ndt_methods:
                    if method.get('is_performed'):
                        story.append(Spacer(1, 0.3*cm))
                        story.append(Paragraph(f"<b>{method.get('method_name', '')}</b>", self.styles['Heading3']))
                        
                        if method.get('defects'):
                            story.append(Paragraph(f"<b>Обнаруженные дефекты:</b> {method.get('defects', '')}", self.styles['Normal']))
                        
                        if method.get('conclusion'):
                            story.append(Paragraph(f"<b>Заключение:</b> {method.get('conclusion', '')}", self.styles['Normal']))
            section_num += 1
        
        # Заключение
        conclusion_section = section_num
        if inspection_data.get('conclusion'):
            story.append(Paragraph(f"{conclusion_section}. ЗАКЛЮЧЕНИЕ", self.styles['SectionTitle']))
            story.append(Paragraph(inspection_data['conclusion'], self.styles['Conclusion']))

        # Приложения специалистов
        story.append(PageBreak())
        story.append(Paragraph("ПРИЛОЖЕНИЯ", self.styles['SectionTitle']))
        if specialist_docs:
            for s in specialist_docs:
                story.append(Paragraph(f"Документы специалиста: {s.get('inspector_name','')}", self.styles['Heading3']))
                for c in (s.get("certifications") or []):
                    story.append(Paragraph(
                        f"{c.get('certification_type','')} №{c.get('certificate_number','')} ({c.get('issuing_organization','')})",
                        self.styles['BodyText']
                    ))
        else:
            story.append(Paragraph("Документы специалистов НК не приложены.", self.styles['BodyText']))
        
        # Используемое оборудование для поверок
        if verification_equipment and isinstance(verification_equipment, list) and len(verification_equipment) > 0:
            story.append(Spacer(1, 0.5*cm))
            story.append(Paragraph("Используемое оборудование для неразрушающего контроля", self.styles['Heading3']))
            story.append(Paragraph(
                "При проведении обследования использовалось следующее поверенное оборудование:",
                self.styles['BodyText']
            ))
            
            eq_table_data = [['№', 'Наименование', 'Тип', 'Серийный номер', 'Срок поверки', 'Свидетельство']]
            for idx, eq in enumerate(verification_equipment, 1):
                next_date = eq.get('next_verification_date', '')
                if next_date:
                    try:
                        from datetime import datetime as dt
                        d = dt.fromisoformat(next_date.replace('Z', '+00:00'))
                        next_date = d.strftime('%d.%m.%Y')
                    except:
                        pass
                
                cert_num = eq.get('verification_certificate_number', '')
                eq_table_data.append([
                    str(idx),
                    eq.get('name', ''),
                    eq.get('equipment_type', ''),
                    eq.get('serial_number', ''),
                    next_date,
                    cert_num if cert_num else '—',
                ])
            
            eq_table = Table(eq_table_data, colWidths=[0.8*cm, 5*cm, 2.5*cm, 3*cm, 3*cm, 3.7*cm])
            eq_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 9),
                ('FONTSIZE', (0, 1), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ]))
            story.append(eq_table)
            story.append(Spacer(1, 0.3*cm))
            
            # Добавляем сканы свидетельств о поверке
            story.append(Paragraph("Сканы свидетельств о поверке используемого оборудования:", self.styles['BodyText']))
            for eq in verification_equipment:
                scan_path = eq.get('scan_file_path')
                scan_name = eq.get('scan_file_name', '')
                eq_name = eq.get('name', '')
                
                if scan_path and os.path.exists(scan_path):
                    story.append(Spacer(1, 0.2*cm))
                    story.append(Paragraph(f"Свидетельство о поверке: {eq_name} ({scan_name})", self.styles['BodyText']))
                    try:
                        mime_type = eq.get('scan_mime_type', '')
                        if 'image' in mime_type.lower():
                            img = Image(scan_path)
                            img.drawWidth = 16 * cm
                            img.drawHeight = 10 * cm
                            story.append(img)
                            story.append(Spacer(1, 0.2*cm))
                        else:
                            story.append(Paragraph(f"Файл: {scan_name}", self.styles['BodyText']))
                    except Exception as e:
                        story.append(Paragraph(f"Не удалось встроить изображение: {str(e)}", self.styles['BodyText']))
        
        # Подпись
        story.append(PageBreak())
        story.append(Spacer(1, 10*cm))
        story.append(Paragraph("_________________________", self.styles['BodyText']))
        story.append(Paragraph("Эксперт", self.styles['BodyText']))
        story.append(Spacer(1, 0.5*cm))
        story.append(Paragraph(f"Дата: {datetime.now().strftime('%d.%m.%Y')}", self.styles['BodyText']))
        
        doc.build(story)
        return output_path
    
    def generate_questionnaire_report(
        self,
        questionnaire_data: Dict[str, Any],
        equipment_data: Dict[str, Any],
        questionnaire_info: Dict[str, Any],
        output_path: str,
        ndt_methods: Optional[List[Dict[str, Any]]] = None
    ):
        """Генерировать PDF опросного листа"""
        doc = SimpleDocTemplate(output_path, pagesize=A4)
        
        story = []
        
        # Титульная страница
        story.append(Paragraph("ОПРОСНЫЙ ЛИСТ", self.styles['ReportTitle']))
        story.append(Spacer(1, 0.5*cm))
        story.append(Paragraph(f"оборудования: {equipment_data.get('name', 'Не указано')}", self.styles['ReportSubtitle']))
        story.append(Spacer(1, 1*cm))
        
        # Информация об оборудовании
        story.append(Paragraph("1. ОБЩИЕ СВЕДЕНИЯ ОБ ОБОРУДОВАНИИ", self.styles['SectionTitle']))
        
        equipment_info = [
            ['Наименование оборудования:', equipment_data.get('name', 'Не указано')],
            ['Инвентарный номер:', questionnaire_info.get('inventory_number', 'Не указан')],
            ['Заводской номер:', equipment_data.get('serial_number', 'Не указан')],
            ['Место расположения:', equipment_data.get('location', 'Не указано')],
        ]
        
        table = Table(equipment_info, colWidths=[6*cm, 12*cm])
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
            ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
            ('FONTNAME', (0, 0), (0, -1), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
            ('FONTSIZE', (0, 0), (-1, -1), 10),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
            ('TOPPADDING', (0, 0), (-1, -1), 8),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ]))
        story.append(table)
        story.append(Spacer(1, 0.5*cm))
        
        # Информация об обследовании
        story.append(Paragraph("2. СВЕДЕНИЯ ОБ ОБСЛЕДОВАНИИ", self.styles['SectionTitle']))
        
        inspection_date = questionnaire_info.get('inspection_date')
        if inspection_date:
            try:
                if 'T' in str(inspection_date):
                    inspection_date = datetime.fromisoformat(str(inspection_date).replace('Z', '+00:00')).strftime('%d.%m.%Y')
                else:
                    inspection_date = datetime.fromisoformat(str(inspection_date)).strftime('%d.%m.%Y')
            except:
                pass
        
        inspection_info = [
            ['Дата обследования:', inspection_date or 'Не указана'],
            ['Инженер:', questionnaire_info.get('inspector_name', 'Не указан')],
            ['Должность:', questionnaire_info.get('inspector_position', 'Не указана')],
        ]
        
        table = Table(inspection_info, colWidths=[6*cm, 12*cm])
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
            ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
            ('FONTNAME', (0, 0), (0, -1), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
            ('FONTSIZE', (0, 0), (-1, -1), 10),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
            ('TOPPADDING', (0, 0), (-1, -1), 8),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ]))
        story.append(table)
        story.append(Spacer(1, 0.5*cm))
        
        # Данные опросного листа
        story.append(Paragraph("3. РЕЗУЛЬТАТЫ ОБСЛЕДОВАНИЯ", self.styles['SectionTitle']))
        
        if questionnaire_data:
            self._add_questionnaire_data(story, questionnaire_data)
        
        # Методы неразрушающего контроля
        if ndt_methods:
            story.append(Spacer(1, 0.5*cm))
            story.append(Paragraph("4. МЕТОДЫ НЕРАЗРУШАЮЩЕГО КОНТРОЛЯ", self.styles['SectionTitle']))
            
            # Таблица методов НК
            ndt_table_data = [['Метод НК', 'Нормативный документ', 'Оборудование', 'Инженер', 'Уровень', 'Результаты']]
            for method in ndt_methods:
                if method.get('is_performed'):
                    ndt_table_data.append([
                        method.get('method_name', ''),
                        method.get('standard', ''),
                        method.get('equipment', ''),
                        method.get('inspector_name', ''),
                        method.get('inspector_level', ''),
                        method.get('results', '')[:50] + '...' if method.get('results') and len(method.get('results', '')) > 50 else method.get('results', ''),
                    ])
            
            if len(ndt_table_data) > 1:
                ndt_table = Table(ndt_table_data, colWidths=[3*cm, 3*cm, 3*cm, 3*cm, 2*cm, 4*cm])
                ndt_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                    ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('FONTSIZE', (0, 1), (-1, -1), 8),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
                    ('TOPPADDING', (0, 0), (-1, -1), 6),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
                ]))
                story.append(ndt_table)
                
                # Детальная информация по каждому методу
                for method in ndt_methods:
                    if method.get('is_performed'):
                        story.append(Spacer(1, 0.3*cm))
                        story.append(Paragraph(f"<b>{method.get('method_name', '')}</b>", self.styles['Heading3']))
                        
                        # Для УЗТ (толщинометрии) добавляем детальную информацию
                        if method.get('method_code') == 'УЗТ' and method.get('additional_data'):
                            thickness_data = method.get('additional_data', {})
                            if thickness_data.get('thickness_measurements'):
                                story.append(Paragraph("<b>Результаты толщинометрии:</b>", self.styles['Normal']))
                                thickness_table_data = [['№', 'Местоположение', 'Толщина, мм', 'Мин. допустимая, мм', 'Комментарий']]
                                for idx, point in enumerate(thickness_data.get('thickness_measurements', []), 1):
                                    thickness_table_data.append([
                                        str(idx),
                                        point.get('location', ''),
                                        str(point.get('thickness', '')),
                                        str(point.get('min_allowed_thickness', '')),
                                        point.get('comment', '')[:50] + '...' if point.get('comment') and len(point.get('comment', '')) > 50 else point.get('comment', ''),
                                    ])
                                if len(thickness_table_data) > 1:
                                    thickness_table = Table(thickness_table_data, colWidths=[1*cm, 4*cm, 2.5*cm, 2.5*cm, 6*cm])
                                    thickness_table.setStyle(TableStyle([
                                        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                                        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                                        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                                        ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                                        ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                                        ('FONTSIZE', (0, 0), (-1, 0), 8),
                                        ('FONTSIZE', (0, 1), (-1, -1), 7),
                                        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
                                        ('TOPPADDING', (0, 0), (-1, -1), 4),
                                        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                                        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
                                    ]))
                                    story.append(thickness_table)
                        
                        if method.get('defects'):
                            story.append(Paragraph(f"<b>Обнаруженные дефекты:</b> {method.get('defects', '')}", self.styles['Normal']))
                        
                        if method.get('conclusion'):
                            story.append(Paragraph(f"<b>Заключение:</b> {method.get('conclusion', '')}", self.styles['Normal']))
        
        # Подпись
        story.append(Spacer(1, 1*cm))
        story.append(Paragraph("Инженер: _________________", self.styles['Normal']))
        story.append(Paragraph(f"{questionnaire_info.get('inspector_name', '')}", self.styles['Normal']))
        story.append(Spacer(1, 0.5*cm))
        story.append(Paragraph(f"Дата: {inspection_date or datetime.now().strftime('%d.%m.%Y')}", self.styles['Normal']))
        
        doc.build(story)
    
    def _add_questionnaire_data(self, story, data: Dict[str, Any], level: int = 0):
        """Рекурсивно добавляет данные опросного листа в PDF"""
        if isinstance(data, dict):
            for key, value in data.items():
                if key == 'photos' and isinstance(value, list):
                    # Пропускаем фото в основном тексте (можно добавить отдельно)
                    continue
                if isinstance(value, (dict, list)):
                    if level == 0:
                        story.append(Paragraph(f"<b>{key}</b>", self.styles['Heading3']))
                    else:
                        story.append(Paragraph(f"{'  ' * level}• {key}", self.styles['Normal']))
                    self._add_questionnaire_data(story, value, level + 1)
                elif value:
                    story.append(Paragraph(f"{'  ' * level}• <b>{key}:</b> {str(value)}", self.styles['Normal']))
        elif isinstance(data, list):
            for item in data:
                if isinstance(item, dict):
                    self._add_questionnaire_data(story, item, level)
                elif item:
                    story.append(Paragraph(f"{'  ' * level}• {str(item)}", self.styles['Normal']))



