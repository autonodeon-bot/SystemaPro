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
                fontName=default_font
            )
            self.styles.add(body_style)
        else:
            # Если стиль уже существует, обновляем его
            self.styles['BodyText'].fontSize = 11
            self.styles['BodyText'].textColor = colors.HexColor('#334155')
            self.styles['BodyText'].alignment = TA_JUSTIFY
            self.styles['BodyText'].spaceAfter = 10
            self.styles['BodyText'].fontName = default_font
        
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
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
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
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
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
                    story.append(Paragraph(f"Акт №{idx}. {m.get('method_name', 'Метод НК')}", self.styles['Heading3']))
                    act_rows = [
                        ["Метод НК:", str(m.get("method_name") or "")],
                        ["Код:", str(m.get("method_code") or "")],
                        ["Нормативный документ:", str(m.get("standard") or "")],
                        ["Оборудование/прибор:", str(m.get("equipment") or "")],
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
                        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                    ]))
                    story.append(t)
                    story.append(Spacer(1, 0.2*cm))
                    if m.get("results"):
                        story.append(Paragraph(f"<b>Результаты:</b> {str(m.get('results'))}", self.styles['Normal']))
                    if m.get("defects"):
                        story.append(Paragraph(f"<b>Дефекты:</b> {str(m.get('defects'))}", self.styles['Normal']))
                    if m.get("conclusion"):
                        story.append(Paragraph(f"<b>Заключение:</b> {str(m.get('conclusion'))}", self.styles['Normal']))

                    # Фото по методу НК
                    photos = m.get("photos") or []
                    if isinstance(photos, list) and photos:
                        story.append(Paragraph("Фотоматериалы:", self.styles['BodyText']))
                        for p in photos[:10]:
                            if isinstance(p, str) and os.path.exists(p):
                                try:
                                    img = Image(p)
                                    img.drawWidth = 16 * cm
                                    img.drawHeight = 10 * cm
                                    story.append(img)
                                    story.append(Spacer(1, 0.2*cm))
                                except Exception:
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
                    if isinstance(sp, str) and os.path.exists(sp) and ("image" in mt):
                        try:
                            img = Image(sp)
                            img.drawWidth = 16 * cm
                            img.drawHeight = 10 * cm
                            story.append(img)
                            story.append(Spacer(1, 0.2*cm))
                        except Exception:
                            pass
        else:
            story.append(Paragraph("Документы специалистов НК не приложены.", self.styles['BodyText']))
        
        # Используемое оборудование для поверок
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
                            img = Image(scan_path)
                            img.drawWidth = 16 * cm
                            img.drawHeight = 10 * cm
                            story.append(img)
                            story.append(Spacer(1, 0.2*cm))
                        else:
                            # Для PDF просто указываем, что файл приложен
                            story.append(Paragraph(f"Файл: {scan_name}", self.styles['BodyText']))
                    except Exception as e:
                        story.append(Paragraph(f"Не удалось встроить изображение: {str(e)}", self.styles['BodyText']))
        
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
            if not path or not isinstance(path, str):
                return
            if not os.path.exists(path):
                return
            try:
                story.append(Paragraph(title, self.styles['BodyText']))
                img = Image(path)
                # масштабируем по ширине страницы
                img.drawWidth = 16 * cm
                img.drawHeight = 10 * cm
                story.append(img)
                story.append(Spacer(1, 0.3 * cm))
            except Exception:
                pass

        # Документы
        if _get('documents'):
            story.append(Paragraph("3.1. Перечень рассмотренных документов", self.styles['SectionTitle']))
            doc_data = [['№', 'Наименование документа', 'Наличие']]
            docs = _get('documents', default={})
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
            if isinstance(docs, dict):
                for num, has_doc in docs.items():
                    doc_name = document_names.get(str(num), f'Документ {num}')
                    doc_data.append([num, doc_name, 'Да' if has_doc else 'Нет'])
            
            table = Table(doc_data, colWidths=[1*cm, 12*cm, 5*cm])
            table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
                ('FONTNAME', (0, 0), (-1, -1), getattr(self, "default_font", "Helvetica")),
                ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", getattr(self, "default_font", "Helvetica"))),
                ('FONTSIZE', (0, 0), (-1, 0), 10),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                ('TOPPADDING', (0, 0), (-1, -1), 8),
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
        _add_image_if_exists("Фото заводской таблички:", attachments.get("factory_plate_photo") or plate_path)

        # Толщинометрия (УЗТ) — таблица + схема (если есть)
        thickness = _get('thickness_measurements', 'thicknessMeasurements', default=[])
        if isinstance(thickness, list) and len(thickness) > 0:
            story.append(Paragraph("3.3. УЗТ (Ультразвуковая толщинометрия)", self.styles['SectionTitle']))
            thickness_table_data = [['№', 'Местоположение', 'Сечение', 'Толщина, мм', 'Мин. допустимая, мм', 'X%', 'Y%', 'Комментарий']]
            for idx, point in enumerate(thickness, 1):
                if not isinstance(point, dict):
                    continue
                thickness_table_data.append([
                    str(idx),
                    str(point.get('location', '') or ''),
                    str(point.get('section_number', '') or ''),
                    str(point.get('thickness', '') or ''),
                    str(point.get('min_allowed_thickness', '') or ''),
                    str(point.get('x_percent', '') or ''),
                    str(point.get('y_percent', '') or ''),
                    str(point.get('comment', '') or ''),
                ])
            if len(thickness_table_data) > 1:
                t = Table(thickness_table_data, colWidths=[0.8*cm, 3.0*cm, 1.6*cm, 1.9*cm, 2.3*cm, 1.1*cm, 1.1*cm, 6.0*cm])
                t.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (-1, 0), getattr(self, "bold_font", self.default_font)),
                    ('FONTSIZE', (0, 0), (-1, 0), 8),
                    ('FONTSIZE', (0, 1), (-1, -1), 7),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
                    ('TOPPADDING', (0, 0), (-1, -1), 4),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
                ]))
                story.append(t)
                story.append(Spacer(1, 0.3*cm))

            scheme_path = _get('control_scheme_image', 'controlSchemeImage')
            _add_image_if_exists("Схема контроля:", attachments.get("control_scheme_image") or scheme_path)

        # ЗРА
        zra = _get('zra_items', default=[])
        if isinstance(zra, list) and zra:
            story.append(Paragraph("3.4. ЗРА (запорно-регулирующая арматура)", self.styles['SectionTitle']))
            rows = [['№', 'Кол-во', 'Типоразмер', 'Тех. №', 'Зав. №', 'Место на схеме']]
            for i, it in enumerate(zra, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    str(i),
                    str(it.get('quantity', '') or ''),
                    str(it.get('type_size', '') or ''),
                    str(it.get('tech_number', '') or ''),
                    str(it.get('serial_number', '') or ''),
                    str(it.get('location_on_scheme', '') or ''),
                ])
            t = Table(rows, colWidths=[0.8*cm, 1.3*cm, 3.0*cm, 2.0*cm, 2.0*cm, 8.0*cm])
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

        # СППК
        sppk = _get('sppk_items', default=[])
        if isinstance(sppk, list) and sppk:
            story.append(Paragraph("3.5. СППК (предохранительные клапаны)", self.styles['SectionTitle']))
            rows = [['№', 'Кол-во', 'Типоразмер', 'Тех. №', 'Зав. №', 'Место на схеме']]
            for i, it in enumerate(sppk, 1):
                if not isinstance(it, dict):
                    continue
                rows.append([
                    str(i),
                    str(it.get('quantity', '') or ''),
                    str(it.get('type_size', '') or ''),
                    str(it.get('tech_number', '') or ''),
                    str(it.get('serial_number', '') or ''),
                    str(it.get('location_on_scheme', '') or ''),
                ])
            t = Table(rows, colWidths=[0.8*cm, 1.3*cm, 3.0*cm, 2.0*cm, 2.0*cm, 8.0*cm])
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
                rows.append([
                    str(i),
                    str(it.get('section_number', '') or ''),
                    str(it.get('deflection_mm', '') or ''),
                    str(it.get('deflection_percent', '') or ''),
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



