"""
Генератор Word документов для отчетов и опросных листов
"""
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from datetime import datetime
from typing import Dict, Any, Optional, List
from pathlib import Path
import os

class WordGenerator:
    """Генератор Word документов"""
    
    def __init__(self):
        pass
    
    def generate_questionnaire_word(
        self,
        questionnaire_data: Dict[str, Any],
        equipment_data: Dict[str, Any],
        questionnaire_info: Dict[str, Any],
        ndt_methods: List[Dict[str, Any]],
        output_path: str
    ):
        """Генерировать Word документ опросного листа"""
        doc = Document()
        
        # Настройка стилей
        self._setup_styles(doc)
        
        # Титульная страница
        title = doc.add_heading('ОПРОСНЫЙ ЛИСТ', 0)
        title.alignment = WD_ALIGN_PARAGRAPH.CENTER
        
        subtitle = doc.add_paragraph(f'оборудования: {equipment_data.get("name", "Не указано")}')
        subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
        subtitle_format = subtitle.runs[0].font
        subtitle_format.size = Pt(14)
        subtitle_format.bold = True
        
        doc.add_paragraph()
        
        # Раздел 1: Общие сведения об оборудовании
        doc.add_heading('1. ОБЩИЕ СВЕДЕНИЯ ОБ ОБОРУДОВАНИИ', level=1)
        
        equipment_table = doc.add_table(rows=4, cols=2)
        equipment_table.style = 'Light Grid Accent 1'
        equipment_table.alignment = WD_TABLE_ALIGNMENT.LEFT
        
        equipment_info = [
            ['Наименование оборудования:', equipment_data.get('name') or 'Не указано'],
            ['Инвентарный номер:', questionnaire_info.get('inventory_number') or 'Не указан'],
            ['Заводской номер:', equipment_data.get('serial_number') or 'Не указан'],
            ['Место расположения:', equipment_data.get('location') or 'Не указано'],
        ]
        
        for i, (label, value) in enumerate(equipment_info):
            equipment_table.rows[i].cells[0].text = label
            # Обрабатываем None значения
            equipment_table.rows[i].cells[1].text = str(value) if value is not None else 'Не указано'
            equipment_table.rows[i].cells[0].paragraphs[0].runs[0].font.bold = True
        
        doc.add_paragraph()
        
        # Раздел 2: Сведения об обследовании
        doc.add_heading('2. СВЕДЕНИЯ ОБ ОБСЛЕДОВАНИИ', level=1)
        
        inspection_table = doc.add_table(rows=3, cols=2)
        inspection_table.style = 'Light Grid Accent 1'
        
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
            # ВАЖНО: questionnaire_info может содержать ключи со значением None,
            # а python-docx ожидает строку (иначе TypeError: 'NoneType' object is not iterable).
            ['Инженер:', (questionnaire_info.get('inspector_name') or 'Не указан')],
            ['Должность:', (questionnaire_info.get('inspector_position') or 'Не указана')],
        ]
        
        for i, (label, value) in enumerate(inspection_info):
            inspection_table.rows[i].cells[0].text = label
            inspection_table.rows[i].cells[1].text = str(value) if value is not None else ''
            inspection_table.rows[i].cells[0].paragraphs[0].runs[0].font.bold = True
        
        doc.add_paragraph()
        
        # Раздел 3: Результаты неразрушающего контроля
        doc.add_heading('3. РЕЗУЛЬТАТЫ НЕРАЗРУШАЮЩЕГО КОНТРОЛЯ', level=1)
        
        if ndt_methods:
            ndt_table = doc.add_table(rows=len(ndt_methods) + 1, cols=6)
            ndt_table.style = 'Light Grid Accent 1'
            
            # Заголовки
            headers = ['Метод НК', 'Нормативный документ', 'Оборудование', 'Инженер', 'Уровень', 'Результаты']
            for i, header in enumerate(headers):
                cell = ndt_table.rows[0].cells[i]
                cell.text = header
                cell.paragraphs[0].runs[0].font.bold = True
                cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            
            # Данные методов НК
            for idx, method in enumerate(ndt_methods, start=1):
                ndt_table.rows[idx].cells[0].text = str(method.get('method_name') or '')
                ndt_table.rows[idx].cells[1].text = str(method.get('standard') or '')
                ndt_table.rows[idx].cells[2].text = str(method.get('equipment') or '')
                ndt_table.rows[idx].cells[3].text = str(method.get('inspector_name') or '')
                ndt_table.rows[idx].cells[4].text = str(method.get('inspector_level') or '')
                ndt_table.rows[idx].cells[5].text = str(method.get('results') or '')
            
            doc.add_paragraph()
            
            # Детальная информация по каждому методу
            for method in ndt_methods:
                if method.get('is_performed'):
                    method_name = method.get('method_name', 'Неизвестный метод')
                    doc.add_heading(f'{method_name}', level=2)
                    
                    if method.get('defects'):
                        p = doc.add_paragraph()
                        p.add_run('Обнаруженные дефекты: ').bold = True
                        p.add_run(str(method.get('defects') or ''))
                    
                    if method.get('conclusion'):
                        p = doc.add_paragraph()
                        p.add_run('Заключение: ').bold = True
                        p.add_run(str(method.get('conclusion') or ''))
                    
                    doc.add_paragraph()
        else:
            doc.add_paragraph('Методы неразрушающего контроля не указаны.')
        
        # Раздел 4: Перечень документов
        doc.add_paragraph()
        doc.add_heading('4. ПЕРЕЧЕНЬ РАССМОТРЕННЫХ ДОКУМЕНТОВ', level=1)
        
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
        
        docs = questionnaire_data.get('documents', {})
        if isinstance(docs, dict) and docs:
            doc_table = doc.add_table(rows=len(docs) + 1, cols=3)
            doc_table.style = 'Light Grid Accent 1'
            
            # Заголовки
            headers = ['№', 'Наименование документа', 'Наличие']
            for i, header in enumerate(headers):
                cell = doc_table.rows[0].cells[i]
                cell.text = header
                cell.paragraphs[0].runs[0].font.bold = True
                cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            
            # Данные документов
            row_idx = 1
            for num, has_doc in sorted(docs.items(), key=lambda x: int(x[0])):
                doc_name = document_names.get(str(num), f'Документ {num}')
                doc_table.rows[row_idx].cells[0].text = str(num)
                doc_table.rows[row_idx].cells[1].text = doc_name
                doc_table.rows[row_idx].cells[2].text = 'Да' if has_doc else 'Нет'
                doc_table.rows[row_idx].cells[2].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                row_idx += 1
        else:
            doc.add_paragraph('Документы не указаны.')
        
        # Подпись
        doc.add_paragraph()
        doc.add_paragraph('Инженер: _________________')
        doc.add_paragraph(questionnaire_info.get('inspector_name', ''))
        doc.add_paragraph()
        doc.add_paragraph(f"Дата: {inspection_date or datetime.now().strftime('%d.%m.%Y')}")
        
        # Сохранение
        doc.save(output_path)
    
    def generate_report_word(
        self,
        inspection_data: Dict[str, Any],
        equipment_data: Dict[str, Any],
        ndt_methods: List[Dict[str, Any]],
        output_path: str,
        report_type: str = "TECHNICAL_REPORT",
        document_files: Optional[List[Dict[str, Any]]] = None,
        specialist_docs: Optional[List[Dict[str, Any]]] = None,
        verification_equipment: Optional[List[Dict[str, Any]]] = None,
    ):
        """Генерировать Word документ отчета"""
        doc = Document()
        
        # Настройка стилей
        self._setup_styles(doc)
        
        # Титульная страница
        if report_type == "EXPERTISE":
            title = doc.add_heading('ЭКСПЕРТИЗА ПРОМЫШЛЕННОЙ БЕЗОПАСНОСТИ', 0)
        else:
            title = doc.add_heading('ОТЧЕТ О ТЕХНИЧЕСКОМ ДИАГНОСТИРОВАНИИ', 0)
        title.alignment = WD_ALIGN_PARAGRAPH.CENTER
        
        subtitle = doc.add_paragraph(f'оборудования: {equipment_data.get("name", "Не указано")}')
        subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
        subtitle_format = subtitle.runs[0].font
        subtitle_format.size = Pt(14)
        subtitle_format.bold = True
        
        doc.add_paragraph()

        # Содержание (упрощенное)
        doc.add_heading('СОДЕРЖАНИЕ', level=1)
        for item in [
            '1. Общая часть',
            '2. Исходные данные и нормативная база',
            '3. Описание объекта и карта обследования',
            '4. Акт(ы) неразрушающего контроля',
            '5. Результаты обследования (детализация)',
            '6. Заключение',
            '7. Приложения',
        ]:
            doc.add_paragraph(item)
        doc.add_page_break()

        # Общая часть
        doc.add_heading('1. ОБЩАЯ ЧАСТЬ', level=1)
        doc.add_paragraph(
            'Настоящий отчет составлен по результатам технического диагностирования оборудования с целью '
            'оценки технического состояния и определения возможности дальнейшей безопасной эксплуатации.'
        )
        doc.add_paragraph()

        # Нормативная база
        doc.add_heading('2. ИСХОДНЫЕ ДАННЫЕ И НОРМАТИВНАЯ БАЗА', level=1)
        doc.add_paragraph(
            'При выполнении работ использовались данные Заказчика, результаты обследований и применимые нормативные документы (ФНП, ГОСТ, РД и др.).'
        )
        doc.add_paragraph()
        
        # Описание объекта
        doc.add_heading('3. ОПИСАНИЕ ОБЪЕКТА И КАРТА ОБСЛЕДОВАНИЯ', level=1)
        
        equipment_table = doc.add_table(rows=3, cols=2)
        equipment_table.style = 'Light Grid Accent 1'
        
        equipment_info = [
            ['Наименование оборудования:', equipment_data.get('name') or 'Не указано'],
            ['Заводской номер:', equipment_data.get('serial_number') or 'Не указан'],
            ['Место расположения:', equipment_data.get('location') or 'Не указано'],
        ]
        
        for i, (label, value) in enumerate(equipment_info):
            equipment_table.rows[i].cells[0].text = label
            # Обрабатываем None значения
            equipment_table.rows[i].cells[1].text = str(value) if value is not None else 'Не указано'
            equipment_table.rows[i].cells[0].paragraphs[0].runs[0].font.bold = True
        
        doc.add_paragraph()
        
        data = inspection_data.get("data") or {}
        if not isinstance(data, dict):
            data = {}

        def _get(*keys, default=None):
            for k in keys:
                if k in data and data.get(k) is not None:
                    return data.get(k)
            return default

        # Индекс вложений (document_number -> file_path)
        attachments: Dict[str, str] = {}
        if document_files and isinstance(document_files, list):
            for f in document_files:
                if not isinstance(f, dict):
                    continue
                dn = str(f.get("document_number") or "")
                fp = f.get("file_path")
                if dn and isinstance(fp, str) and fp:
                    attachments[dn] = fp

        def add_picture_if_exists(title: str, path: Optional[str]):
            if not path:
                return
            try:
                p = Path(path)
                if not p.exists():
                    return
                par = doc.add_paragraph()
                par.add_run(title).bold = True
                doc.add_paragraph()
                doc.add_picture(str(p), width=Inches(6.0))
                doc.add_paragraph()
            except Exception:
                pass

        # Акт(ы) НК
        doc.add_heading('4. АКТ(Ы) НЕРАЗРУШАЮЩЕГО КОНТРОЛЯ', level=1)
        
        performed = [m for m in (ndt_methods or []) if m.get('is_performed')]
        if performed:
            for i, m in enumerate(performed, start=1):
                doc.add_heading(f'Акт №{i}. {m.get("method_name") or "Метод НК"}', level=2)
                t = doc.add_table(rows=7, cols=2)
                t.style = 'Light Grid Accent 1'
                rows = [
                    ('Метод НК:', m.get('method_name') or ''),
                    ('Код:', m.get('method_code') or ''),
                    ('Нормативный документ:', m.get('standard') or ''),
                    ('Оборудование/прибор:', m.get('equipment') or ''),
                    ('Дата выполнения:', m.get('performed_date') or inspection_data.get('date_performed') or ''),
                    ('Специалист:', m.get('inspector_name') or ''),
                    ('Уровень:', m.get('inspector_level') or ''),
                ]
                for r, (k, v) in enumerate(rows):
                    t.rows[r].cells[0].text = str(k)
                    t.rows[r].cells[1].text = str(v)
                    try:
                        t.rows[r].cells[0].paragraphs[0].runs[0].font.bold = True
                    except Exception:
                        pass
                if m.get('results'):
                    p = doc.add_paragraph()
                    p.add_run('Результаты: ').bold = True
                    p.add_run(str(m.get('results')))
                if m.get('defects'):
                    p = doc.add_paragraph()
                    p.add_run('Дефекты: ').bold = True
                    p.add_run(str(m.get('defects')))
                if m.get('conclusion'):
                    p = doc.add_paragraph()
                    p.add_run('Заключение: ').bold = True
                    p.add_run(str(m.get('conclusion')))

                # Фото по методу (включая аннотированные изображения)
                photos = m.get('photos') or []
                additional_data = m.get('additional_data', {})
                annotated_images = additional_data.get('annotated_images', []) if isinstance(additional_data, dict) else []
                
                # Объединяем обычные фото и аннотированные изображения
                all_images = list(photos) + list(annotated_images) if isinstance(photos, list) else list(annotated_images)
                
                if all_images:
                    doc.add_paragraph()
                    doc.add_paragraph('Фотоматериалы и аннотированные схемы:').runs[0].bold = True
                    for idx, ph in enumerate(all_images[:10], 1):
                        if isinstance(ph, str):
                            doc.add_paragraph(f'Изображение {idx}:')
                            add_picture_if_exists('', ph)

                doc.add_paragraph()
        else:
            doc.add_paragraph('Методы неразрушающего контроля не указаны или не выполнены.')
        
        doc.add_paragraph()

        # Перечень документов (чтобы не было "Документ 1")
        docs = _get("documents", default={})
        if isinstance(docs, dict) and docs:
            doc.add_heading('5. ПЕРЕЧЕНЬ РАССМОТРЕННЫХ ДОКУМЕНТОВ', level=1)

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

            doc_table = doc.add_table(rows=len(docs) + 1, cols=3)
            doc_table.style = 'Light Grid Accent 1'
            headers = ['№', 'Наименование документа', 'Наличие']
            for i, header in enumerate(headers):
                cell = doc_table.rows[0].cells[i]
                cell.text = header
                cell.paragraphs[0].runs[0].font.bold = True
                cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER

            row_idx = 1
            for num, has_doc in sorted(docs.items(), key=lambda x: int(str(x[0]))):
                name = document_names.get(str(num), f'Документ {num}')
                doc_table.rows[row_idx].cells[0].text = str(num)
                doc_table.rows[row_idx].cells[1].text = name
                doc_table.rows[row_idx].cells[2].text = 'Да' if has_doc else 'Нет'
                doc_table.rows[row_idx].cells[2].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                row_idx += 1

            doc.add_paragraph()

        # Фото заводской таблички / схема контроля (из мобильного приложения)
        add_picture_if_exists(
            'Фото заводской таблички',
            attachments.get('factory_plate_photo') or _get('factory_plate_photo'),
        )

        # Толщинометрия (точки + таблица)
        thickness = _get("thickness_measurements", "thicknessMeasurements", default=[])
        if isinstance(thickness, list) and len(thickness) > 0:
            doc.add_heading('6. УЗТ (УЛЬТРАЗВУКОВАЯ ТОЛЩИНОМЕТРИЯ)', level=1)

            t = doc.add_table(rows=len(thickness) + 1, cols=8)
            t.style = 'Light Grid Accent 1'
            headers = ['№', 'Местоположение', 'Сечение', 'Толщина, мм', 'Мин. допустимая, мм', 'X%', 'Y%', 'Комментарий']
            for i, header in enumerate(headers):
                cell = t.rows[0].cells[i]
                cell.text = header
                cell.paragraphs[0].runs[0].font.bold = True
                cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER

            for idx, point in enumerate(thickness, start=1):
                if not isinstance(point, dict):
                    continue
                t.rows[idx].cells[0].text = str(idx)
                t.rows[idx].cells[1].text = str(point.get('location') or '')
                t.rows[idx].cells[2].text = str(point.get('section_number') or '')
                t.rows[idx].cells[3].text = str(point.get('thickness') or '')
                t.rows[idx].cells[4].text = str(point.get('min_allowed_thickness') or '')
                t.rows[idx].cells[5].text = str(point.get('x_percent') or '')
                t.rows[idx].cells[6].text = str(point.get('y_percent') or '')
                t.rows[idx].cells[7].text = str(point.get('comment') or '')

            doc.add_paragraph()

            add_picture_if_exists(
                'Схема контроля / карта обследования',
                attachments.get('control_scheme_image') or _get('control_scheme_image'),
            )

        # ЗРА / СППК / измерительный контроль / твердость / сварные соединения
        zra = _get('zra_items', default=[])
        if isinstance(zra, list) and zra:
            doc.add_heading('5. ЗРА (ЗАПОРНО-РЕГУЛИРУЮЩАЯ АРМАТУРА)', level=1)
            t = doc.add_table(rows=len(zra) + 1, cols=6)
            t.style = 'Light Grid Accent 1'
            headers = ['№', 'Кол-во', 'Типоразмер', 'Тех. №', 'Зав. №', 'Место на схеме']
            for i, h in enumerate(headers):
                c = t.rows[0].cells[i]
                c.text = h
                c.paragraphs[0].runs[0].font.bold = True
            for i, it in enumerate(zra, start=1):
                if not isinstance(it, dict):
                    continue
                t.rows[i].cells[0].text = str(i)
                t.rows[i].cells[1].text = str(it.get('quantity') or '')
                t.rows[i].cells[2].text = str(it.get('type_size') or '')
                t.rows[i].cells[3].text = str(it.get('tech_number') or '')
                t.rows[i].cells[4].text = str(it.get('serial_number') or '')
                t.rows[i].cells[5].text = str(it.get('location_on_scheme') or '')
            doc.add_paragraph()

        sppk = _get('sppk_items', default=[])
        if isinstance(sppk, list) and sppk:
            doc.add_heading('6. СППК (ПРЕДОХРАНИТЕЛЬНЫЕ КЛАПАНЫ)', level=1)
            t = doc.add_table(rows=len(sppk) + 1, cols=6)
            t.style = 'Light Grid Accent 1'
            headers = ['№', 'Кол-во', 'Типоразмер', 'Тех. №', 'Зав. №', 'Место на схеме']
            for i, h in enumerate(headers):
                c = t.rows[0].cells[i]
                c.text = h
                c.paragraphs[0].runs[0].font.bold = True
            for i, it in enumerate(sppk, start=1):
                if not isinstance(it, dict):
                    continue
                t.rows[i].cells[0].text = str(i)
                t.rows[i].cells[1].text = str(it.get('quantity') or '')
                t.rows[i].cells[2].text = str(it.get('type_size') or '')
                t.rows[i].cells[3].text = str(it.get('tech_number') or '')
                t.rows[i].cells[4].text = str(it.get('serial_number') or '')
                t.rows[i].cells[5].text = str(it.get('location_on_scheme') or '')
            doc.add_paragraph()

        ovality = _get('ovality_measurements', default=[])
        if isinstance(ovality, list) and ovality:
            doc.add_heading('7. ИЗМЕРИТЕЛЬНЫЙ КОНТРОЛЬ — ОВАЛЬНОСТЬ', level=1)
            t = doc.add_table(rows=len(ovality) + 1, cols=5)
            t.style = 'Light Grid Accent 1'
            headers = ['№', 'Сечение', 'Dmax', 'Dmin', 'Отклонение, %']
            for i, h in enumerate(headers):
                c = t.rows[0].cells[i]
                c.text = h
                c.paragraphs[0].runs[0].font.bold = True
            for i, it in enumerate(ovality, start=1):
                if not isinstance(it, dict):
                    continue
                t.rows[i].cells[0].text = str(i)
                t.rows[i].cells[1].text = str(it.get('section_number') or '')
                t.rows[i].cells[2].text = str(it.get('max_diameter') or '')
                t.rows[i].cells[3].text = str(it.get('min_diameter') or '')
                t.rows[i].cells[4].text = str(it.get('deviation_percent') or '')
            doc.add_paragraph()

        deflection = _get('deflection_measurements', default=[])
        if isinstance(deflection, list) and deflection:
            doc.add_heading('8. ИЗМЕРИТЕЛЬНЫЙ КОНТРОЛЬ — ПРОГИБ', level=1)
            t = doc.add_table(rows=len(deflection) + 1, cols=4)
            t.style = 'Light Grid Accent 1'
            headers = ['№', 'Сечение', 'Прогиб, мм', 'Прогиб, %']
            for i, h in enumerate(headers):
                c = t.rows[0].cells[i]
                c.text = h
                c.paragraphs[0].runs[0].font.bold = True
            for i, it in enumerate(deflection, start=1):
                if not isinstance(it, dict):
                    continue
                t.rows[i].cells[0].text = str(i)
                t.rows[i].cells[1].text = str(it.get('section_number') or '')
                t.rows[i].cells[2].text = str(it.get('deflection_mm') or '')
                t.rows[i].cells[3].text = str(it.get('deflection_percent') or '')
            doc.add_paragraph()

        hardness = _get('hardness_tests', default=[])
        if isinstance(hardness, list) and hardness:
            doc.add_heading('9. КОНТРОЛЬ ТВЕРДОСТИ', level=1)
            t = doc.add_table(rows=len(hardness) + 1, cols=8)
            t.style = 'Light Grid Accent 1'
            headers = ['№', 'Шов', 'Участок', 'Доп. осн', 'Доп. шов', 'Осн', 'Шов', 'ЗТВ']
            for i, h in enumerate(headers):
                c = t.rows[0].cells[i]
                c.text = h
                c.paragraphs[0].runs[0].font.bold = True
            for i, it in enumerate(hardness, start=1):
                if not isinstance(it, dict):
                    continue
                t.rows[i].cells[0].text = str(i)
                t.rows[i].cells[1].text = str(it.get('weld_number') or '')
                t.rows[i].cells[2].text = str(it.get('area_number') or '')
                t.rows[i].cells[3].text = str(it.get('allowed_hardness_base') or '')
                t.rows[i].cells[4].text = str(it.get('allowed_hardness_weld') or '')
                t.rows[i].cells[5].text = str(it.get('hardness_base') or '')
                t.rows[i].cells[6].text = str(it.get('hardness_weld') or '')
                t.rows[i].cells[7].text = str(it.get('hardness_haz') or '')
            doc.add_paragraph()

        welds = _get('weld_inspections', default=[])
        if isinstance(welds, list) and welds:
            doc.add_heading('10. КОНТРОЛЬ СВАРНЫХ СОЕДИНЕНИЙ (ПВК/УЗК)', level=1)
            t = doc.add_table(rows=len(welds) + 1, cols=6)
            t.style = 'Light Grid Accent 1'
            headers = ['№', 'Шов', 'Место на карте', 'ПВК дефект', 'УЗК дефект', 'Заключение']
            for i, h in enumerate(headers):
                c = t.rows[0].cells[i]
                c.text = h
                c.paragraphs[0].runs[0].font.bold = True
            for i, it in enumerate(welds, start=1):
                if not isinstance(it, dict):
                    continue
                t.rows[i].cells[0].text = str(i)
                t.rows[i].cells[1].text = str(it.get('weld_number') or '')
                t.rows[i].cells[2].text = str(it.get('location_on_control_map') or '')
                t.rows[i].cells[3].text = str(it.get('pvk_defect') or '')
                t.rows[i].cells[4].text = str(it.get('uzk_defect') or '')
                t.rows[i].cells[5].text = str(it.get('conclusion') or '')
            doc.add_paragraph()
        
        # Заключение
        if inspection_data.get('conclusion'):
            doc.add_heading('7. ЗАКЛЮЧЕНИЕ', level=1)
            doc.add_paragraph(str(inspection_data.get('conclusion') or ''))

        # Приложения: документы специалистов
        doc.add_page_break()
        doc.add_heading('8. ПРИЛОЖЕНИЯ', level=1)
        
        # 8.1. Документы специалистов НК
        doc.add_heading('8.1. Документы специалистов неразрушающего контроля', level=2)
        if specialist_docs:
            for s in specialist_docs:
                inspector_name = s.get('inspector_name', 'Не указано')
                doc.add_heading(f"Специалист: {inspector_name}", level=3)
                certifications = s.get('certifications') or []
                if certifications:
                    for idx, c in enumerate(certifications, 1):
                        cert_type = c.get('certification_type', 'Удостоверение')
                        cert_num = c.get('certificate_number', '')
                        org = c.get('issuing_organization', '')
                        issue_date = c.get('issue_date', '')
                        expiry_date = c.get('expiry_date', '')
                        
                        doc.add_paragraph(f"{idx}. {cert_type}")
                        if cert_num:
                            doc.add_paragraph(f"   Номер: {cert_num}")
                        if org:
                            doc.add_paragraph(f"   Организация: {org}")
                        if issue_date:
                            doc.add_paragraph(f"   Дата выдачи: {issue_date}")
                        if expiry_date:
                            doc.add_paragraph(f"   Срок действия: {expiry_date}")
                        
                        # Добавляем скан удостоверения
                        scan_path = c.get('scan_file_path')
                        if scan_path and isinstance(scan_path, str):
                            add_picture_if_exists(f'Скан удостоверения {cert_type} №{cert_num}', scan_path)
                        doc.add_paragraph()
                else:
                    doc.add_paragraph(f'Документы для специалиста {inspector_name} не найдены.')
                doc.add_paragraph()
        else:
            doc.add_paragraph('Документы специалистов НК не приложены.')
        
        # 8.2. Используемое оборудование для поверок
        if verification_equipment and isinstance(verification_equipment, list) and len(verification_equipment) > 0:
            doc.add_paragraph('')
            doc.add_heading('8.2. Используемое оборудование для неразрушающего контроля', level=2)
            doc.add_paragraph('При проведении обследования использовалось следующее поверенное оборудование:')
            
            # Таблица с оборудованием
            table = doc.add_table(rows=1, cols=7)
            table.style = 'Light Grid Accent 1'
            hdr_cells = table.rows[0].cells
            hdr_cells[0].text = '№'
            hdr_cells[1].text = 'Наименование'
            hdr_cells[2].text = 'Тип'
            hdr_cells[3].text = 'Производитель/Модель'
            hdr_cells[4].text = 'Серийный номер'
            hdr_cells[5].text = 'Дата поверки'
            hdr_cells[6].text = 'Срок поверки'
            
            for idx, eq in enumerate(verification_equipment, 1):
                row_cells = table.add_row().cells
                row_cells[0].text = str(idx)
                row_cells[1].text = eq.get('name', '')
                row_cells[2].text = eq.get('equipment_type', '')
                
                manufacturer = eq.get('manufacturer', '')
                model = eq.get('model', '')
                manufacturer_model = f"{manufacturer} {model}".strip() if manufacturer or model else '—'
                row_cells[3].text = manufacturer_model
                
                row_cells[4].text = eq.get('serial_number', '—')
                
                ver_date = eq.get('verification_date', '')
                if ver_date:
                    try:
                        from datetime import datetime as dt
                        d = dt.fromisoformat(ver_date.replace('Z', '+00:00'))
                        ver_date = d.strftime('%d.%m.%Y')
                    except:
                        pass
                row_cells[5].text = ver_date if ver_date else '—'
                
                next_date = eq.get('next_verification_date', '')
                if next_date:
                    try:
                        from datetime import datetime as dt
                        d = dt.fromisoformat(next_date.replace('Z', '+00:00'))
                        next_date = d.strftime('%d.%m.%Y')
                    except:
                        pass
                row_cells[6].text = next_date if next_date else '—'
            
            doc.add_paragraph('')
            doc.add_paragraph('Сканы свидетельств о поверке используемого оборудования:')
            
            # Добавляем сканы с подробной информацией
            for idx, eq in enumerate(verification_equipment, 1):
                scan_path = eq.get('scan_file_path')
                scan_name = eq.get('scan_file_name', '')
                eq_name = eq.get('name', '')
                cert_num = eq.get('verification_certificate_number', '')
                ver_org = eq.get('verification_organization', '')
                
                if scan_path:
                    doc.add_paragraph('')
                    title_parts = [f'{idx}. Свидетельство о поверке: {eq_name}']
                    if cert_num:
                        title_parts.append(f'№ {cert_num}')
                    if ver_org:
                        title_parts.append(f'({ver_org})')
                    doc.add_paragraph(' '.join(title_parts))
                    
                    if os.path.exists(scan_path):
                        add_picture_if_exists('', scan_path)
                    else:
                        doc.add_paragraph(f'[Файл не найден: {scan_path}]')
        
        # Сохранение
        doc.save(output_path)
    
    def _setup_styles(self, doc: Document):
        """Настройка стилей документа"""
        # Можно настроить стили по необходимости
        pass



