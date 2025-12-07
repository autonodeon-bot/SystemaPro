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
        self._setup_custom_styles()
    
    def _setup_custom_styles(self):
        """Настройка пользовательских стилей"""
        # Заголовок отчета
        self.styles.add(ParagraphStyle(
            name='ReportTitle',
            parent=self.styles['Heading1'],
            fontSize=18,
            textColor=colors.HexColor('#1e293b'),
            spaceAfter=30,
            alignment=TA_CENTER,
            fontName='Helvetica-Bold'
        ))
        
        # Подзаголовок
        self.styles.add(ParagraphStyle(
            name='ReportSubtitle',
            parent=self.styles['Heading2'],
            fontSize=14,
            textColor=colors.HexColor('#475569'),
            spaceAfter=20,
            alignment=TA_CENTER
        ))
        
        # Заголовок раздела
        self.styles.add(ParagraphStyle(
            name='SectionTitle',
            parent=self.styles['Heading2'],
            fontSize=14,
            textColor=colors.HexColor('#0f172a'),
            spaceAfter=12,
            spaceBefore=20,
            fontName='Helvetica-Bold'
        ))
        
        # Обычный текст
        self.styles.add(ParagraphStyle(
            name='BodyText',
            parent=self.styles['Normal'],
            fontSize=11,
            textColor=colors.HexColor('#334155'),
            alignment=TA_JUSTIFY,
            spaceAfter=10
        ))
        
        # Заключение
        self.styles.add(ParagraphStyle(
            name='Conclusion',
            parent=self.styles['Normal'],
            fontSize=12,
            textColor=colors.HexColor('#0f172a'),
            alignment=TA_JUSTIFY,
            spaceAfter=15,
            fontName='Helvetica-Bold'
        ))
    
    def generate_technical_report(self, inspections_data: List[Dict[str, Any]], equipment_data: Dict[str, Any], 
                                  output_path: str) -> str:
        """Генерация технического отчета"""
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
        story.append(Paragraph("ТЕХНИЧЕСКИЙ ОТЧЕТ", self.styles['ReportTitle']))
        story.append(Spacer(1, 0.5*cm))
        story.append(Paragraph(f"по результатам диагностики оборудования", self.styles['ReportSubtitle']))
        story.append(Spacer(1, 1*cm))
        
        # Информация об оборудовании
        story.append(Paragraph("1. ОБЩИЕ СВЕДЕНИЯ ОБ ОБОРУДОВАНИИ", self.styles['SectionTitle']))
        
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
            ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, -1), 10),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
            ('TOPPADDING', (0, 0), (-1, -1), 8),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ]))
        story.append(table)
        story.append(Spacer(1, 0.5*cm))
        
        # Информация о диагностиках (может быть несколько)
        story.append(Paragraph("2. РЕЗУЛЬТАТЫ ДИАГНОСТИКИ", self.styles['SectionTitle']))
        
        # Если одно обследование, обрабатываем как раньше
        if len(inspections_data) == 1:
            inspection_data = inspections_data[0]
            inspection_info = [
                ['Дата проведения диагностики:', inspection_data.get('date_performed', 'Не указана')],
                ['Статус:', inspection_data.get('status', 'DRAFT')],
            ]
            
            if inspection_data.get('data'):
                data = inspection_data['data']
                if isinstance(data, dict):
                    if data.get('executors'):
                        inspection_info.append(['Исполнители:', data['executors']])
                    if data.get('organization'):
                        inspection_info.append(['Организация:', data['organization']])
            
            table2 = Table(inspection_info, colWidths=[6*cm, 12*cm])
            table2.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
                ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, -1), 10),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                ('TOPPADDING', (0, 0), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
            ]))
            story.append(table2)
            story.append(Spacer(1, 0.5*cm))
            
            # Детальные данные диагностики
            if inspection_data.get('data'):
                story.append(Paragraph("3. ДЕТАЛЬНЫЕ РЕЗУЛЬТАТЫ ОБСЛЕДОВАНИЯ", self.styles['SectionTitle']))
                data = inspection_data['data']
                if isinstance(data, dict):
                    self._add_checklist_data(story, data)
            
            # Заключение
            if inspection_data.get('conclusion'):
                story.append(Paragraph("4. ЗАКЛЮЧЕНИЕ", self.styles['SectionTitle']))
                story.append(Paragraph(inspection_data['conclusion'], self.styles['Conclusion']))
        else:
            # Несколько обследований - объединяем в один отчет
            story.append(Paragraph(f"Проведено обследований: {len(inspections_data)}", self.styles['BodyText']))
            story.append(Spacer(1, 0.3*cm))
            
            # Обрабатываем каждое обследование
            for idx, inspection_data in enumerate(inspections_data, 1):
                story.append(Paragraph(f"3.{idx}. ОБСЛЕДОВАНИЕ №{idx}", self.styles['SectionTitle']))
                
                inspection_info = [
                    ['Дата проведения:', inspection_data.get('date_performed', 'Не указана')],
                    ['Статус:', inspection_data.get('status', 'DRAFT')],
                ]
                
                if inspection_data.get('data'):
                    data = inspection_data['data']
                    if isinstance(data, dict):
                        if data.get('executors'):
                            inspection_info.append(['Исполнители:', data['executors']])
                        if data.get('organization'):
                            inspection_info.append(['Организация:', data['organization']])
                
                table2 = Table(inspection_info, colWidths=[6*cm, 12*cm])
                table2.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
                    ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, -1), 10),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                    ('TOPPADDING', (0, 0), (-1, -1), 8),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ]))
                story.append(table2)
                story.append(Spacer(1, 0.3*cm))
                
                # Детальные данные
                if inspection_data.get('data'):
                    data = inspection_data['data']
                    if isinstance(data, dict):
                        self._add_checklist_data(story, data)
                
                # Заключение по обследованию
                if inspection_data.get('conclusion'):
                    story.append(Paragraph(f"Заключение по обследованию №{idx}:", self.styles['BodyText']))
                    story.append(Paragraph(inspection_data['conclusion'], self.styles['BodyText']))
                    story.append(Spacer(1, 0.3*cm))
                
                if idx < len(inspections_data):
                    story.append(PageBreak())
            
            # Общее заключение
            story.append(Paragraph("4. ОБЩЕЕ ЗАКЛЮЧЕНИЕ", self.styles['SectionTitle']))
            conclusions = [insp.get('conclusion') for insp in inspections_data if insp.get('conclusion')]
            if conclusions:
                story.append(Paragraph("\n".join(conclusions), self.styles['Conclusion']))
        
        # Подпись
        story.append(PageBreak())
        story.append(Spacer(1, 10*cm))
        story.append(Paragraph("_________________________", self.styles['BodyText']))
        story.append(Paragraph("Подпись", self.styles['BodyText']))
        story.append(Spacer(1, 0.5*cm))
        story.append(Paragraph(f"Дата: {datetime.now().strftime('%d.%m.%Y')}", self.styles['BodyText']))
        
        doc.build(story)
        return output_path
    
    def _add_checklist_data(self, story, data: Dict[str, Any]):
        """Добавление данных из чек-листа"""
        # Документы
        if data.get('documents'):
            story.append(Paragraph("3.1. Перечень рассмотренных документов", self.styles['SectionTitle']))
            doc_data = [['№', 'Наименование документа', 'Наличие']]
            docs = data['documents']
            if isinstance(docs, dict):
                for num, has_doc in docs.items():
                    doc_data.append([num, f'Документ {num}', 'Да' if has_doc else 'Нет'])
            
            table = Table(doc_data, colWidths=[1*cm, 12*cm, 5*cm])
            table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f172a')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
                ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, 0), 10),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                ('TOPPADDING', (0, 0), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
            ]))
            story.append(table)
            story.append(Spacer(1, 0.5*cm))
        
        # Карта обследования
        if data.get('vesselName'):
            story.append(Paragraph("3.2. Карта обследования", self.styles['SectionTitle']))
            vessel_data = [
                ['Наименование сосуда:', data.get('vesselName', '')],
                ['Заводской номер:', data.get('serialNumber', '')],
                ['Регистрационный номер:', data.get('regNumber', '')],
            ]
            if data.get('workingPressure'):
                vessel_data.append(['Рабочее давление:', data['workingPressure']])
            if data.get('diameter'):
                vessel_data.append(['Диаметр сосуда:', data['diameter']])
            
            table = Table(vessel_data, colWidths=[6*cm, 12*cm])
            table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
                ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, -1), 10),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                ('TOPPADDING', (0, 0), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
            ]))
            story.append(table)
            story.append(Spacer(1, 0.5*cm))
    
    def generate_expertise_report(self, inspection_data: Dict[str, Any], equipment_data: Dict[str, Any],
                                  resource_data: Optional[Dict[str, Any]], output_path: str) -> str:
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
            ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
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
            self._add_checklist_data(story, inspection_data['data'])
        
        # Ресурс оборудования
        if resource_data:
            story.append(Paragraph("3. РЕСУРС ОБОРУДОВАНИЯ", self.styles['SectionTitle']))
            resource_info = [
                ['Остаточный ресурс:', f"{resource_data.get('remaining_resource_years', 0)} лет"],
                ['Дата окончания ресурса:', resource_data.get('resource_end_date', 'Не указана')],
            ]
            if resource_data.get('extension_years'):
                resource_info.append(['Продление ресурса:', f"{resource_data['extension_years']} лет"])
                resource_info.append(['Новая дата окончания:', resource_data.get('extension_date', 'Не указана')])
            
            table = Table(resource_info, colWidths=[6*cm, 12*cm])
            table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f1f5f9')),
                ('TEXTCOLOR', (0, 0), (-1, -1), colors.HexColor('#334155')),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, -1), 10),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                ('TOPPADDING', (0, 0), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
            ]))
            story.append(table)
            story.append(Spacer(1, 0.5*cm))
        
        # Заключение
        if inspection_data.get('conclusion'):
            story.append(Paragraph("4. ЗАКЛЮЧЕНИЕ", self.styles['SectionTitle']))
            story.append(Paragraph(inspection_data['conclusion'], self.styles['Conclusion']))
        
        # Подпись
        story.append(PageBreak())
        story.append(Spacer(1, 10*cm))
        story.append(Paragraph("_________________________", self.styles['BodyText']))
        story.append(Paragraph("Эксперт", self.styles['BodyText']))
        story.append(Spacer(1, 0.5*cm))
        story.append(Paragraph(f"Дата: {datetime.now().strftime('%d.%m.%Y')}", self.styles['BodyText']))
        
        doc.build(story)
        return output_path



