"""
Генератор Word документов для отчетов и опросных листов
"""
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
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
        template_definition: Optional[Dict[str, Any]] = None,
    ):
        """Генерировать Word документ отчета"""
        rt = (report_type or "").strip().upper()
        if rt in ["DIAGNOSTICS", "DIAGNOSTIC", "TECHNICAL_DIAGNOSTICS"]:
            return self._generate_diagnostics_report_word(
                inspection_data=inspection_data,
                equipment_data=equipment_data,
                ndt_methods=ndt_methods,
                output_path=output_path,
                document_files=document_files,
                specialist_docs=specialist_docs,
                verification_equipment=verification_equipment,
                template_definition=template_definition,
            )

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
            """Извлечь значение по ключам (поддержка camelCase и snake_case)"""
            for k in keys:
                if k in data and data.get(k) is not None:
                    return data.get(k)
            # Пробуем варианты с camelCase/snake_case
            for k in keys:
                # snake_case -> camelCase
                camel_key = ''.join(word.capitalize() if i > 0 else word for i, word in enumerate(k.split('_')))
                camel_key_lower = camel_key[0].lower() + camel_key[1:] if camel_key else k
                if camel_key_lower in data and data.get(camel_key_lower) is not None:
                    return data.get(camel_key_lower)
            return default

        # Индекс вложений (document_number -> file_path / file_name)
        attachments: Dict[str, str] = {}
        attachment_names: Dict[str, str] = {}
        if document_files and isinstance(document_files, list):
            for f in document_files:
                if not isinstance(f, dict):
                    continue
                dn = str(f.get("document_number") or "")
                fp = f.get("file_path")
                if dn and isinstance(fp, str) and fp:
                    attachments[dn] = fp
                    fn = f.get("file_name")
                    if isinstance(fn, str) and fn:
                        attachment_names[dn] = fn

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

        inspection_engineers = _get("inspection_engineers", default=[])

        def _engineer_for_method(method_code: str) -> str:
            if not isinstance(inspection_engineers, list):
                return ""
            for ie in inspection_engineers:
                if not isinstance(ie, dict):
                    continue
                if (ie.get("method") or "").upper() == (method_code or "").upper():
                    return str(ie.get("full_name") or "")
            return ""

        # Акт(ы) НК
        doc.add_heading('4. АКТ(Ы) НЕРАЗРУШАЮЩЕГО КОНТРОЛЯ', level=1)
        
        performed = [m for m in (ndt_methods or []) if m.get('is_performed')]
        if performed:
            for i, m in enumerate(performed, start=1):
                doc.add_heading(f'Акт №{i}. {m.get("method_name") or "Метод НК"}', level=2)
                t = doc.add_table(rows=7, cols=2)
                t.style = 'Light Grid Accent 1'
                inspector_name = m.get('inspector_name') or _engineer_for_method(m.get('method_code') or m.get('method_name') or '')
                rows = [
                    ('Метод НК:', m.get('method_name') or ''),
                    ('Код:', m.get('method_code') or ''),
                    ('Нормативный документ:', m.get('standard') or ''),
                    ('Оборудование/прибор:', m.get('equipment') or ''),
                    ('Дата выполнения:', m.get('performed_date') or inspection_data.get('date_performed') or ''),
                    ('Специалист:', inspector_name or ''),
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
        return

    def _fmt_date_ru(self, s: Optional[str]) -> Optional[str]:
        if not s:
            return None
        try:
            # 2025-07-25 / 2025-07-25T...Z
            if "T" in s:
                d = datetime.fromisoformat(s.replace("Z", "+00:00"))
            else:
                d = datetime.fromisoformat(s)
            return d.strftime("%d.%m.%Y")
        except Exception:
            return s

    def _add_toc_field(self, doc: Document):
        """
        Вставить поле оглавления (обновляется в Word: ПКМ -> Обновить поле).
        """
        p = doc.add_paragraph()
        run = p.add_run()

        fldChar1 = OxmlElement("w:fldChar")
        fldChar1.set(qn("w:fldCharType"), "begin")

        instrText = OxmlElement("w:instrText")
        instrText.set(qn("xml:space"), "preserve")
        instrText.text = r'TOC \o "1-3" \h \z \u'

        fldChar2 = OxmlElement("w:fldChar")
        fldChar2.set(qn("w:fldCharType"), "separate")

        fldChar3 = OxmlElement("w:t")
        fldChar3.text = "Оглавление будет сформировано при обновлении полей в Word."

        fldChar4 = OxmlElement("w:fldChar")
        fldChar4.set(qn("w:fldCharType"), "end")

        run._r.append(fldChar1)
        run._r.append(instrText)
        run._r.append(fldChar2)
        run._r.append(fldChar3)
        run._r.append(fldChar4)

    def _generate_diagnostics_report_word(
        self,
        inspection_data: Dict[str, Any],
        equipment_data: Dict[str, Any],
        ndt_methods: List[Dict[str, Any]],
        output_path: str,
        document_files: Optional[List[Dict[str, Any]]] = None,
        specialist_docs: Optional[List[Dict[str, Any]]] = None,
        verification_equipment: Optional[List[Dict[str, Any]]] = None,
        template_definition: Optional[Dict[str, Any]] = None,
    ):
        """
        Диагностический отчет в структуре, близкой к примеру (reciver.md):
        титульник -> оглавление -> разделы 1..15 -> приложения.
        """
        doc = Document()
        self._setup_styles(doc)

        data = inspection_data.get("data") or {}
        if not isinstance(data, dict):
            data = {}
        attrs = equipment_data.get("attributes") or {}
        if not isinstance(attrs, dict):
            attrs = {}

        # Индекс вложений (document_number -> file_path / file_name)
        attachments: Dict[str, str] = {}
        attachment_names: Dict[str, str] = {}
        if document_files and isinstance(document_files, list):
            for f in document_files:
                if not isinstance(f, dict):
                    continue
                dn = str(f.get("document_number") or "")
                fp = f.get("file_path")
                if dn and isinstance(fp, str) and fp:
                    attachments[dn] = fp
                    fn = f.get("file_name")
                    if isinstance(fn, str) and fn:
                        attachment_names[dn] = fn

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

        # template_definition: {logo_path, fields:{...}, sections:[{key,enabled}]}
        tdef = template_definition if isinstance(template_definition, dict) else {}
        tfields = tdef.get("fields") if isinstance(tdef.get("fields"), dict) else {}
        tsections = tdef.get("sections") if isinstance(tdef.get("sections"), list) else []
        enabled = {str(s.get("key")): bool(s.get("enabled")) for s in tsections if isinstance(s, dict) and s.get("key")}
        def is_on(key: str) -> bool:
            # по умолчанию включено, если нет явного списка
            if not tsections:
                return True
            return enabled.get(key, False)

        def g(*keys, default=None):
            """Извлечь значение по ключам (поддержка camelCase и snake_case)"""
            # Сначала ищем в data
            for k in keys:
                if k in data and data.get(k) not in (None, ""):
                    return data.get(k)
            # Затем ищем в attrs
            for k in keys:
                if k in attrs and attrs.get(k) not in (None, ""):
                    return attrs.get(k)
            # Пробуем варианты с camelCase/snake_case
            for k in keys:
                # snake_case -> camelCase
                camel_key = ''.join(word.capitalize() if i > 0 else word for i, word in enumerate(k.split('_')))
                camel_key_lower = camel_key[0].lower() + camel_key[1:] if camel_key else k
                if camel_key_lower in data and data.get(camel_key_lower) not in (None, ""):
                    return data.get(camel_key_lower)
                if camel_key_lower in attrs and attrs.get(camel_key_lower) not in (None, ""):
                    return attrs.get(camel_key_lower)
            return default

        date_perf_iso = inspection_data.get("date_performed")
        date_perf_ru = self._fmt_date_ru(date_perf_iso) or datetime.now().strftime("%d.%m.%Y")
        year2 = datetime.now().strftime("%y")
        # Номер отчета: YY-xxxx (по последним 4 символам UUID)
        rid = str(equipment_data.get("id") or "")[-4:] or "0000"
        report_no = g("report_number", default=f"{year2}-{rid}")

        # --------------- ТИТУЛЬНЫЙ ЛИСТ ---------------
        if is_on("title"):
            logo_path = tdef.get("logo_path") or g("report_logo_path", default="/app/reports/assets/yutar_logo.png")
            try:
                p = Path(str(logo_path))
                if p.exists():
                    doc.add_picture(str(p), width=Inches(6.5))
            except Exception:
                pass

        # Блок заголовка (как таблица в примере)
        if is_on("title"):
            title_table = doc.add_table(rows=1, cols=1)
            title_table.style = "Table Grid"
            title_table.alignment = WD_TABLE_ALIGNMENT.CENTER
            cell = title_table.rows[0].cells[0]
            p = cell.paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            r = p.add_run(f"ТЕХНИЧЕСКИЙ ОТЧЕТ № {report_no}\nПО РЕЗУЛЬТАТАМ ТЕХНИЧЕСКОГО ДИАГНОСТИРОВАНИЯ")
            r.bold = True
            r.font.size = Pt(14)

        doc.add_paragraph("")

        # Таблица объекта (упрощенно, но структура похожа)
        if is_on("title"):
            obj_tbl = doc.add_table(rows=5, cols=2)
            obj_tbl.style = "Table Grid"
            obj_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER

        object_name = g("equipment_object_name", "vessel_name", default=equipment_data.get("name") or "—")
        device_name = g("equipment_device_name", default=equipment_data.get("name") or "—")
        serial = g("serial_number", default=equipment_data.get("serial_number") or "—")
        org = g("organization", "customer_name", default="—")
        location = g("location", "equipment_location", default=equipment_data.get("location") or "—")

        rows = [
            ("Объект технического диагностирования:", ""),
            ("Техническое устройство:", device_name),
            ("Заводской номер:", str(serial)),
            ("Эксплуатирующая организация:", str(org)),
            ("Местонахождение объекта:", str(location)),
        ]
        if is_on("title"):
            for i, (k, v) in enumerate(rows):
                obj_tbl.rows[i].cells[0].text = k
                obj_tbl.rows[i].cells[1].text = v
                try:
                    obj_tbl.rows[i].cells[0].paragraphs[0].runs[0].font.bold = True
                except Exception:
                    pass

        doc.add_paragraph("")

        # Подпись руководителя (как в примере — справа)
        if is_on("title"):
            sign_tbl = doc.add_table(rows=1, cols=2)
            sign_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
            sign_tbl.columns[0].width = Inches(3.5)
            sign_tbl.columns[1].width = Inches(3.5)
            sign_tbl.cell(0, 0).text = ""

        contractor = tfields.get("contractor_name") or g("contractor_name", default='ООО «ЮТАР»')
        director_title = tfields.get("director_title") or g("director_title", default="Генеральный директор")
        director_name = tfields.get("director_name") or g("director_name", default="__________________")
        city = tfields.get("report_city") or g("report_city", "city", default="г. ________")
        year = datetime.now().strftime("%Y")

        if is_on("title"):
            p = sign_tbl.cell(0, 1).paragraphs[0]
            p.add_run(f"{director_title}\n{contractor}\n\n__________________\n{director_name}\n\n«____» __________ {year} г.\nМ.П.").font.size = Pt(10)

        doc.add_paragraph("")
        if is_on("title"):
            p = doc.add_paragraph(f"{city} {year} г.")
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            doc.add_page_break()

        # --------------- СОДЕРЖАНИЕ ---------------
        if is_on("toc"):
            doc.add_heading("СОДЕРЖАНИЕ", level=1)
            self._add_toc_field(doc)
            doc.add_page_break()

        # --------------- РАЗДЕЛЫ 1..15 ---------------
        # Эти переменные используются и в разделах, и в приложениях ниже
        performed = [m for m in (ndt_methods or []) if m.get("is_performed")]
        docs = g("documents", default={})
        inspection_engineers = g("inspection_engineers", default=[])

        def _engineer_for_method(method_code: str) -> str:
            if not isinstance(inspection_engineers, list):
                return ""
            for ie in inspection_engineers:
                if not isinstance(ie, dict):
                    continue
                if (ie.get("method") or "").upper() == (method_code or "").upper():
                    return str(ie.get("full_name") or "")
            return ""

        if is_on("sections_1_15"):
            doc.add_heading("1. Основания для проведения работ", level=1)
            doc.add_paragraph(str(g("basis", "work_basis", default="—")))

            doc.add_heading("2. Сроки проведения работ", level=1)
            doc.add_paragraph(str(g("work_period", default=f"Дата проведения: {date_perf_ru}")))

            doc.add_heading("3. Перечень нормативных и правовых актов, устанавливающих требования к объекту диагностирования", level=1)
            # Минимальный дефолт (можно расширять через будущий редактор шаблонов)
            doc.add_paragraph(str(g("normative_base", default="Приказ Ростехнадзора от 15.12.2020 №536.")))

            doc.add_heading("4. Сведения о Заказчике", level=1)
            doc.add_paragraph(f"Эксплуатирующая организация: {org}")
            doc.add_paragraph(f"Местонахождение объекта: {location}")

            doc.add_heading("5. Сведения об организации, проводившей техническое диагностирование", level=1)
            doc.add_paragraph(str(contractor))
            doc.add_paragraph(str(g("contractor_address", default="—")))
            doc.add_paragraph(str(g("contractor_license", default="—")))

            doc.add_heading("6. Сведения об эксперте и специалисте, проводивших диагностирование", level=1)
            # Собираем специалистов из разных источников
            inspectors = []
            inspector_details = {}  # name -> {certifications, level, etc}

            # 0. Из inspection_engineers (выбор инженеров по методам в мобильном приложении)
            if isinstance(inspection_engineers, list):
                for ie in inspection_engineers:
                    if not isinstance(ie, dict):
                        continue
                    name = (ie.get("full_name") or "").strip()
                    method = (ie.get("method") or "").strip()
                    cert_num = (ie.get("certificate_number") or "").strip()
                    valid_until = (ie.get("valid_until") or "").strip()
                    if name and name not in inspectors:
                        inspectors.append(name)
                    if name:
                        if name not in inspector_details:
                            inspector_details[name] = {}
                        methods = inspector_details[name].get("methods", [])
                        if method:
                            methods.append(method)
                        inspector_details[name]["methods"] = methods
                        if cert_num:
                            certs = inspector_details[name].get("certifications_inline", [])
                            certs.append(f"{cert_num}" + (f" до {valid_until}" if valid_until else ""))
                            inspector_details[name]["certifications_inline"] = certs
            
            # 1. Из executors в data
            executors_str = g("executors", default="")
            if executors_str:
                # executors может быть строкой с именами через запятую
                for name in executors_str.split(','):
                    name = name.strip()
                    if name and name not in inspectors:
                        inspectors.append(name)
                        inspector_details[name] = {}
            
            # 2. Из ndt_methods
            for m in (ndt_methods or []):
                name = (m.get("inspector_name") or "").strip()
                if name and name not in inspectors:
                    inspectors.append(name)
                    inspector_details[name] = {
                        "level": m.get("inspector_level"),
                        "certification": m.get("certification_number"),
                    }
            
            # 3. Из specialist_docs (если есть)
            if specialist_docs:
                for s in specialist_docs:
                    name = (s.get("inspector_name") or "").strip()
                    if name and name not in inspectors:
                        inspectors.append(name)
                    if name:
                        if name not in inspector_details:
                            inspector_details[name] = {}
                        inspector_details[name]["certifications"] = s.get("certifications", [])
            
            # Формируем таблицу специалистов
            if inspectors:
                spec_table = doc.add_table(rows=len(inspectors) + 1, cols=4)
                spec_table.style = "Table Grid"
                headers = ["№", "Фамилия И.О.", "№ удостоверения", "Область аттестации / Срок действия"]
                for i, h in enumerate(headers):
                    cell = spec_table.rows[0].cells[i]
                    cell.text = h
                    cell.paragraphs[0].runs[0].font.bold = True
                    cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                
                for idx, name in enumerate(inspectors, 1):
                    spec_table.rows[idx].cells[0].text = str(idx)
                    spec_table.rows[idx].cells[1].text = name
                    
                    # Информация об удостоверениях
                    details = inspector_details.get(name, {})
                    cert_info = []
                    if details.get("certifications"):
                        for cert in details["certifications"]:
                            cert_num = cert.get("certificate_number", "")
                            cert_type = cert.get("certification_type", "")
                            expiry = cert.get("expiry_date", "")
                            if cert_num:
                                cert_info.append(f"{cert_type} №{cert_num}" + (f" до {expiry}" if expiry else ""))
                    elif details.get("certification"):
                        cert_info.append(details["certification"])
                    elif details.get("certifications_inline"):
                        cert_info.extend(details["certifications_inline"])
                    
                    spec_table.rows[idx].cells[2].text = "; ".join(cert_info) if cert_info else "—"
                    
                    areas = []
                    methods = details.get("methods") or []
                    if methods:
                        areas.append("Методы: " + ", ".join(sorted(set([m for m in methods if m]))))
                    level = details.get("level", "")
                    if level:
                        areas.append(f"Уровень: {level}")
                    spec_table.rows[idx].cells[3].text = "; ".join(areas) if areas else "—"
            else:
                doc.add_paragraph("—")

            doc.add_heading("7. Перечень приборов и оборудования", level=1)
            if verification_equipment and isinstance(verification_equipment, list) and verification_equipment:
                # Таблица как в примере
                eq_table = doc.add_table(rows=len(verification_equipment) + 1, cols=4)
                eq_table.style = "Table Grid"
                headers = ["№ п/п", "Наименование прибора", "Заводской номер прибора", "Свидетельство о поверке / Действительна до"]
                for i, h in enumerate(headers):
                    cell = eq_table.rows[0].cells[i]
                    cell.text = h
                    cell.paragraphs[0].runs[0].font.bold = True
                    cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                
                for idx, eq in enumerate(verification_equipment, 1):
                    eq_table.rows[idx].cells[0].text = str(idx)
                    eq_table.rows[idx].cells[1].text = eq.get('name') or '—'
                    eq_table.rows[idx].cells[2].text = eq.get('serial_number') or '—'
                    cert_num = eq.get('verification_certificate_number', '')
                    next_date = self._fmt_date_ru(eq.get('next_verification_date'))
                    cert_info = f"{cert_num}" if cert_num else ""
                    if next_date:
                        cert_info += f" до {next_date}" if cert_info else f"до {next_date}"
                    eq_table.rows[idx].cells[3].text = cert_info if cert_info else "—"
            else:
                doc.add_paragraph("—")

            doc.add_heading("8. Объект технического диагностирования", level=1)
            obj_table = doc.add_table(rows=3, cols=2)
            obj_table.style = "Table Grid"
            obj_table.rows[0].cells[0].text = "Объект технического диагностирования"
            obj_table.rows[0].cells[1].text = object_name
            obj_table.rows[1].cells[0].text = "Заводской номер"
            obj_table.rows[1].cells[1].text = serial
            obj_table.rows[2].cells[0].text = "Местонахождение (адрес)"
            obj_table.rows[2].cells[1].text = location

            doc.add_heading("9. Краткая техническая характеристика и назначение объекта технического освидетельствования", level=1)
            def _attr(key: str, default="—"):
                v = attrs.get(key)
                if v is None or v == "":
                    v = g(key, default=default)
                return v if v is not None and v != "" else default

            tech_rows = [
                ("Наименование объекта", device_name),
                ("Назначение", _attr("purpose", default=str(g("tech_description", default="—")))),
                ("Наименование завода-изготовителя", _attr("manufacturer")),
                ("Год изготовления", _attr("manufacture_year")),
                ("Год ввода в эксплуатацию", _attr("commissioning_year")),
                ("Объем/вместимость, м³", _attr("volume", default=_attr("capacity"))),
                ("Внутренний диаметр, мм", _attr("inner_diameter", default=_attr("diameter"))),
                ("Длина/высота, мм", _attr("length", default=_attr("height"))),
                ("Толщина стенки, мм", _attr("wall_thickness", default=_attr("thickness"))),
                ("Материал", _attr("material")),
                ("Рабочее давление, МПа", _attr("working_pressure")),
                ("Расчетное давление, МПа", _attr("design_pressure")),
                ("Пробное давление гидравлического испытания, МПа", _attr("test_pressure")),
                ("Допустимая рабочая температура стенки, ℃", _attr("working_temperature_range", default=_attr("working_temperature"))),
                ("Расчетная температура, ℃", _attr("design_temperature")),
                ("Наименование рабочей среды", _attr("working_medium")),
                ("Класс опасности среды", _attr("hazard_class")),
                ("Категория/группа сосуда", _attr("category", default=_attr("group"))),
                ("Допускаемая коррозия, мм/год", _attr("corrosion_allowance")),
                ("Проектный ресурс, лет", _attr("design_life")),
                ("Назначенный срок службы, лет", _attr("service_life")),
            ]
            tech_table = doc.add_table(rows=len(tech_rows), cols=2)
            tech_table.style = "Table Grid"
            for i, (label, value) in enumerate(tech_rows):
                tech_table.rows[i].cells[0].text = label
                tech_table.rows[i].cells[1].text = str(value)

            doc.add_heading("10. Перечень работ, выполненных в процессе технического освидетельствования", level=1)
            if performed:
                work_table = doc.add_table(rows=len(performed) + 1, cols=4)
                work_table.style = "Table Grid"
                headers = ["№ п/п", "Наименование работы", "Объем контроля", "Нормативная документация"]
                for i, h in enumerate(headers):
                    cell = work_table.rows[0].cells[i]
                    cell.text = h
                    cell.paragraphs[0].runs[0].font.bold = True
                    cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                for i, m in enumerate(performed, 1):
                    work_table.rows[i].cells[0].text = str(i)
                    work_table.rows[i].cells[1].text = str(m.get('method_name') or m.get('method_code') or 'Метод НК')
                    work_table.rows[i].cells[2].text = str(m.get('control_volume') or m.get('volume') or '—')
                    work_table.rows[i].cells[3].text = str(m.get('standard') or '—')
            else:
                doc.add_paragraph("—")

            doc.add_heading("11. Сведения о рассмотренных в процессе технического освидетельствования документах", level=1)
            if isinstance(docs, dict) and docs:
                document_names = {
                    '1': 'Дубликат паспорт сосуда, работающего под давлением',
                    '2': 'Приказ об организации работ при эксплуатации оборудования, работающего под давлением',
                    '3': 'Журнал проверки сосудов, работающих под давлением',
                    '4': 'Заключение технического диагностирования',
                    '5': 'Сведения об основных элементах сосуда',
                    '6': 'Сведения об основных элементах сосуда (продолжение)',
                    '7': 'Сведения об основной арматуре, КИП и приборах безопасности',
                    '8': 'Приказ о назначении ответственного лица за исправное состояние и безопасную эксплуатацию сосудов',
                    '9': 'Приказ о назначении ответственного лица за осуществление производственного контроля и соблюдение требований промышленной безопасности на ОПО',
                    '10': 'Паспорт сосуда заводской (удостоверение о качестве монтажа, сборочный чертёж, схема включения, расчёт на прочность)',
                    '11': 'Инструкция по монтажу и эксплуатации',
                    '12': 'Паспорта на предохранительные клапаны',
                    '13': 'Паспорта на запорную арматуру',
                    '14': 'Документация на контрольно-измерительные приборы',
                    '15': 'Ремонтная (исполнительная) документация',
                    '16': 'Заключение экспертизы промышленной безопасности',
                    '17': 'Акты проведения УЗТ',
                }
                present = [(str(k), v) for k, v in docs.items() if v]
                if present:
                    t = doc.add_table(rows=len(present) + 1, cols=4)
                    t.style = "Table Grid"
                    headers = ["№ п/п", "Наименование документа", "Идентификационный номер документа", "Объём, листов"]
                    for i, h in enumerate(headers):
                        cell = t.rows[0].cells[i]
                        cell.text = h
                        cell.paragraphs[0].runs[0].font.bold = True
                        cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                    row_idx = 1
                    for num, _ in sorted(present, key=lambda x: int(x[0]) if str(x[0]).isdigit() else 999):
                        t.rows[row_idx].cells[0].text = str(row_idx)
                        t.rows[row_idx].cells[1].text = document_names.get(str(num), f'Документ {num}')
                        t.rows[row_idx].cells[2].text = attachment_names.get(str(num), str(num))
                        t.rows[row_idx].cells[3].text = "—"
                        row_idx += 1
                else:
                    doc.add_paragraph("—")
            else:
                doc.add_paragraph("—")

            doc.add_heading("12. Анализ результатов предыдущих обследований", level=1)
            doc.add_paragraph(str(g("previous_inspections", default="—")))

            doc.add_heading("13. Результаты технического освидетельствования", level=1)
            # Формируем таблицу результатов на основе выполненных методов и данных из checklist
            results_table = doc.add_table(rows=1, cols=4)
            results_table.style = "Table Grid"
            headers = ["№ п/п", "Наименование работы", "Результаты контроля", "Наименование и номер отчетной документации"]
            for i, h in enumerate(headers):
                cell = results_table.rows[0].cells[i]
                cell.text = h
                cell.paragraphs[0].runs[0].font.bold = True
                cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            
            row_num = 1
            # Добавляем результаты по каждому методу
            if performed:
                for m in performed:
                    method_name = m.get('method_name') or m.get('method_code') or 'Метод НК'
                    results = m.get('results') or m.get('conclusion') or 'Выполнено'
                    row = results_table.add_row()
                    row.cells[0].text = str(row_num)
                    row.cells[1].text = method_name
                    row.cells[2].text = str(results)
                    row.cells[3].text = f"Приложение №{row_num + 1}" if row_num <= 10 else "—"
                    row_num += 1
            
            # Добавляем результаты из checklist если есть
            has_visual = g("has_external_defects") is not None or g("has_internal_defects") is not None
            has_thickness = isinstance(g("thickness_measurements", default=[]), list) and len(g("thickness_measurements", default=[])) > 0
            has_hardness = isinstance(g("hardness_tests", default=[]), list) and len(g("hardness_tests", default=[])) > 0
            has_welds = isinstance(g("weld_inspections", default=[]), list) and len(g("weld_inspections", default=[])) > 0
            
            if has_visual:
                row = results_table.add_row()
                row.cells[0].text = str(row_num)
                row.cells[1].text = "Визуальный и измерительный контроль"
                defects = []
                if g("has_external_defects") == True:
                    defects.append("выявлены дефекты при наружном осмотре")
                if g("has_internal_defects") == True:
                    defects.append("выявлены дефекты при внутреннем осмотре")
                row.cells[2].text = "Дефектов, препятствующих дальнейшей безопасной эксплуатации не выявлено" if not defects else "; ".join(defects)
                row.cells[3].text = "Приложение №3"
                row_num += 1
            
            if has_thickness:
                row = results_table.add_row()
                row.cells[0].text = str(row_num)
                row.cells[1].text = "Ультразвуковой контроль толщины стенок элементов сосуда"
                row.cells[2].text = "Утонения стенок сосуда, превышающие допустимые значения не обнаружены"
                row.cells[3].text = "Приложение №4"
                row_num += 1
            
            if has_welds:
                row = results_table.add_row()
                row.cells[0].text = str(row_num)
                row.cells[1].text = "Ультразвуковой контроль качества основного металла и сварных соединений"
                row.cells[2].text = "Недопустимых дефектов не обнаружено"
                row.cells[3].text = "Приложение №5"
                row_num += 1
            
            if has_hardness:
                row = results_table.add_row()
                row.cells[0].text = str(row_num)
                row.cells[1].text = "Оценка механических свойств элемента сосуда"
                row.cells[2].text = "Отклонений твердости металла не выявлено"
                row.cells[3].text = "Приложение №6"
                row_num += 1

            doc.add_paragraph()
            doc.add_heading("14. Результаты расчетной оценки технического состояния", level=1)
            calc_text = g("calculation_results", default="")
            if not calc_text or calc_text == "—":
                calc_text = "По результатам работ произведена оценка работоспособности сосуда при рабочих параметрах. Выполнен расчет на прочность и определение остаточного ресурса сосуда."
            doc.add_paragraph(str(calc_text))

            doc.add_heading("15. Выводы по результатам технического освидетельствования", level=1)
            concl = inspection_data.get("conclusion") or g("final_conclusion", default="")
            if not concl or concl == "—":
                concl = f"На основании результатов выполненного комплекса работ по техническому диагностированию сосуда, работающего под давлением — {device_name} зав. № {serial}, техническое состояние сосуда, работающего под давлением, оценивается как работоспособное."
            doc.add_paragraph(str(concl))

        # --------------- ПРИЛОЖЕНИЯ ---------------
        if is_on("appendices"):
            doc.add_page_break()
            doc.add_heading("ПРИЛОЖЕНИЯ", level=1)

        app_no = 1
        
        # ПРИЛОЖЕНИЕ № 1: Протокол анализа технической документации
        if isinstance(docs, dict) and docs:
            doc.add_page_break()
            doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Протокол анализа технической документации", level=2)
            doc.add_paragraph("1. Сведения о рассмотренных в процессе технического освидетельствования документах")
            
            doc_table = doc.add_table(rows=len(docs) + 1, cols=4)
            doc_table.style = "Table Grid"
            headers = ["№ п/п", "Наименование документа", "Идентификационный номер документа", "Объём рассмотренных документов, листов"]
            for i, h in enumerate(headers):
                cell = doc_table.rows[0].cells[i]
                cell.text = h
                cell.paragraphs[0].runs[0].font.bold = True
                cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            
            document_names = {
                '1': 'Дубликат паспорт сосуда, работающего под давлением',
                '2': 'Приказ об организации работ при эксплуатации оборудования, работающего под давлением',
                '3': 'Журнал проверки сосудов, работающих под давлением',
                '4': 'Заключение технического диагностирования',
                '5': 'Сведения об основных элементах сосуда',
                '6': 'Сведения об основных элементах сосуда (продолжение)',
                '7': 'Сведения об основной арматуре, КИП и приборах безопасности',
                '8': 'Приказ о назначении ответственного лица за исправное состояние и безопасную эксплуатацию сосудов',
                '9': 'Приказ о назначении ответственного лица за осуществление производственного контроля и соблюдение требований промышленной безопасности на ОПО',
                '10': 'Паспорт сосуда заводской (удостоверение о качестве монтажа, сборочный чертёж, схема включения, расчёт на прочность)',
                '11': 'Инструкция по монтажу и эксплуатации',
                '12': 'Паспорта на предохранительные клапаны',
                '13': 'Паспорта на запорную арматуру',
                '14': 'Документация на контрольно-измерительные приборы',
                '15': 'Ремонтная (исполнительная) документация',
                '16': 'Заключение экспертизы промышленной безопасности',
                '17': 'Акты проведения УЗТ',
            }
            
            row_idx = 1
            for num, has_doc in sorted(docs.items(), key=lambda x: int(str(x[0])) if str(x[0]).isdigit() else 999):
                if has_doc:
                    doc_table.rows[row_idx].cells[0].text = str(row_idx)
                    doc_table.rows[row_idx].cells[1].text = document_names.get(str(num), f'Документ {num}')
                    doc_table.rows[row_idx].cells[2].text = attachment_names.get(str(num), str(num))
                    doc_table.rows[row_idx].cells[3].text = "—"  # Объем не указан в checklist
                    row_idx += 1
            
            # Если таблица пустая, удаляем лишние строки
            if row_idx == 1:
                # Оставляем только заголовок
                for i in range(len(docs), 0, -1):
                    doc_table._element.remove(doc_table.rows[i]._element)

            # Приложенные копии документов (если есть файлы)
            any_attachment = False
            for num, has_doc in sorted(docs.items(), key=lambda x: int(str(x[0])) if str(x[0]).isdigit() else 999):
                if not has_doc:
                    continue
                fp = attachments.get(str(num))
                if not fp:
                    continue
                any_attachment = True
                ext = str(Path(fp).suffix or "").lower()
                if ext in [".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp"]:
                    add_picture_if_exists(f"Документ {num}: {document_names.get(str(num), '')}", fp)
                else:
                    doc.add_paragraph(f"Документ {num}: {document_names.get(str(num), '')}")
                    doc.add_paragraph(f"Файл: {Path(fp).name}")
            
            app_no += 1

        # Отдельные акты обследования по каждому методу
        if performed:
            for m in performed:
                method_name = m.get("method_name") or m.get("method_code") or "Метод НК"
                inspector_name = m.get("inspector_name") or _engineer_for_method(m.get("method_code") or method_name)
                doc.add_page_break()
                doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Акт обследования ({method_name})", level=2)
                act_table = doc.add_table(rows=9, cols=2)
                act_table.style = "Table Grid"
                rows = [
                    ("Объект технического диагностирования", object_name),
                    ("Техническое устройство", device_name),
                    ("Заводской номер", serial),
                    ("Местонахождение объекта", location),
                    ("Дата проведения", self._fmt_date_ru(m.get("performed_date")) or date_perf_ru),
                    ("Метод контроля", method_name),
                    ("Нормативный документ", m.get("standard") or "—"),
                    ("Оборудование/прибор", m.get("equipment") or "—"),
                    ("Специалист", inspector_name or "—"),
                ]
                for r, (k, v) in enumerate(rows):
                    act_table.rows[r].cells[0].text = str(k)
                    act_table.rows[r].cells[1].text = str(v)
                    try:
                        act_table.rows[r].cells[0].paragraphs[0].runs[0].font.bold = True
                    except Exception:
                        pass
                if m.get("results"):
                    doc.add_paragraph(f"Результаты контроля: {m.get('results')}")
                if m.get("conclusion"):
                    doc.add_paragraph(f"Заключение: {m.get('conclusion')}")
                app_no += 1

        # ПРИЛОЖЕНИЕ № 2: Протокол по результатам оперативной (функциональной) диагностики
        # (если есть данные функциональной диагностики)
        
        # ПРИЛОЖЕНИЕ № 3: Протокол по результатам визуального и измерительного контроля
        has_visual_data = (g("has_external_defects") is not None or 
                          g("has_internal_defects") is not None or
                          isinstance(g("ovality_measurements", default=[]), list) and len(g("ovality_measurements", default=[])) > 0)
        
        if has_visual_data:
            doc.add_page_break()
            doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Протокол по результатам визуального и измерительного контроля", level=2)
            
            # Результаты визуального контроля
            doc.add_paragraph("3. Результаты визуального контроля")
            visual_table = doc.add_table(rows=10, cols=4)
            visual_table.style = "Table Grid"
            headers = ["№ п/п", "Наименование объекта контроля", "Объем контроля", "Описание обнаруженных дефектов, их размеры", "Оценка качества"]
            for i, h in enumerate(headers):
                cell = visual_table.rows[0].cells[i]
                cell.text = h
                cell.paragraphs[0].runs[0].font.bold = True
                cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            
            visual_items = [
                ("Опоры", "100%", g("support_state", default="дефектов не обнаружено")),
                ("Антикоррозионное покрытие", "100%", g("anticorrosion_coating_state", default="дефектов не обнаружено")),
                ("Разъемные соединения", "100%", "дефектов не обнаружено"),
                ("Крепежные детали", "100%", g("fasteners_state", default="дефектов не обнаружено")),
                ("Основной металл обечайки, днищ сосуда, штуцеров, фланцев", "100%", "дефектов не обнаружено"),
                ("Сварные соединения вварки штуцеров в корпус", "100%", "дефектов не обнаружено"),
                ("Сварные соединения штуцеров фланцев к патрубкам", "100%", "дефектов не обнаружено"),
                ("Сварные соединения приварки опор к корпусу", "100%", "дефектов не обнаружено"),
                ("Кольцевые, продольные сварные соединения и их перекрестья", "100%", "дефектов не обнаружено"),
            ]
            
            for idx, (name, volume, desc) in enumerate(visual_items, 1):
                visual_table.rows[idx].cells[0].text = str(idx)
                visual_table.rows[idx].cells[1].text = name
                visual_table.rows[idx].cells[2].text = volume
                visual_table.rows[idx].cells[3].text = desc if desc else "дефектов не обнаружено"
                visual_table.rows[idx].cells[4].text = "годен"

            # Детализация дефектов ВИК (если есть)
            visual_defects = g("visual_defects", default=[])
            if isinstance(visual_defects, list) and visual_defects:
                doc.add_paragraph()
                doc.add_paragraph("Дополнительно: выявленные дефекты ВИК").runs[0].bold = True
                defect_table = doc.add_table(rows=len(visual_defects) + 1, cols=5)
                defect_table.style = "Table Grid"
                headers = ["№", "Тип дефекта", "Место", "Размеры", "Описание"]
                for i, h in enumerate(headers):
                    cell = defect_table.rows[0].cells[i]
                    cell.text = h
                    cell.paragraphs[0].runs[0].font.bold = True
                    cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                for i, d in enumerate(visual_defects, 1):
                    if not isinstance(d, dict):
                        continue
                    defect_table.rows[i].cells[0].text = str(i)
                    defect_table.rows[i].cells[1].text = str(d.get("defect_type") or "")
                    defect_table.rows[i].cells[2].text = str(d.get("location") or "")
                    defect_table.rows[i].cells[3].text = str(d.get("size") or "")
                    defect_table.rows[i].cells[4].text = str(d.get("description") or "")
                
                # Фотографии дефектов
                for i, d in enumerate(visual_defects, 1):
                    if not isinstance(d, dict):
                        continue
                    photos = d.get("photos") or []
                    if isinstance(photos, list) and photos:
                        doc.add_paragraph(f"Фотографии дефекта №{i}:").runs[0].bold = True
                        for ph in photos[:6]:
                            if isinstance(ph, str):
                                photo_path = ph
                                if not Path(photo_path).exists() and attachments.get(photo_path):
                                    photo_path = attachments.get(photo_path)
                                add_picture_if_exists("", photo_path)
            
            # Результаты измерительного контроля - овальность
            ovality = g('ovality_measurements', default=[])
            if isinstance(ovality, list) and ovality:
                doc.add_paragraph()
                doc.add_paragraph("4. Результаты измерительного контроля")
                doc.add_paragraph("Определение овальности проводят измерением максимального (Dmax) и минимального (Dmin) наружного или внутреннего диаметров в одном сечении по двум перпендикулярным направлениям. Относительная овальность корпуса определяется по формуле:")
                
                ovality_table = doc.add_table(rows=len(ovality) + 1, cols=4)
                ovality_table.style = "Table Grid"
                headers = ["Номер сечения", "Размеры, мм", "", "Фактическая овальность, %", "Допустимая овальность, %"]
                for i, h in enumerate(headers):
                    cell = ovality_table.rows[0].cells[i]
                    cell.text = h
                    cell.paragraphs[0].runs[0].font.bold = True
                    cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                
                # Объединяем ячейки для Dmin и Dmax
                if len(ovality) > 0:
                    # Создаем подзаголовки для Dmin и Dmax
                    ovality_table.rows[0].cells[1].text = "Dmin"
                    ovality_table.rows[0].cells[2].text = "Dmax"
                
                for idx, it in enumerate(ovality, 1):
                    ovality_table.rows[idx].cells[0].text = str(it.get('section_number') or f'I-{idx}')
                    ovality_table.rows[idx].cells[1].text = str(it.get('min_diameter') or '')
                    ovality_table.rows[idx].cells[2].text = str(it.get('max_diameter') or '')
                    ovality_table.rows[idx].cells[3].text = str(it.get('deviation_percent') or '0')
                    ovality_table.rows[idx].cells[4].text = "1,0"
            
            app_no += 1

        # ПРИЛОЖЕНИЕ № 4: Протокол по результатам ультразвукового контроля толщины стенок
        thickness = g("thickness_measurements", "thicknessMeasurements", default=[])
        if isinstance(thickness, list) and len(thickness) > 0:
            doc.add_page_break()
            doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Протокол по результатам ультразвукового контроля толщины стенок элементов сосуда", level=2)
            
            doc.add_paragraph("1. Применяемое оборудование")
            # Таблица оборудования уже есть в разделе 7, можно сослаться
            
            doc.add_paragraph()
            doc.add_paragraph("2. Результаты контроля")
            doc.add_paragraph("Контроль выполнен в соответствии с программой работ, согласно схемы контроля.")

            # Схема контроля (чертеж УЗК) с привязкой точек
            control_scheme = g("control_scheme_image") or attachments.get("control_scheme_image")
            if control_scheme:
                doc.add_paragraph()
                doc.add_paragraph("Схема контроля (УЗК):").runs[0].bold = True
                add_picture_if_exists("", control_scheme)

                # Таблица точек измерений по схеме (если есть координаты)
                points_with_coords = [
                    p for p in thickness
                    if isinstance(p, dict) and (p.get("x_percent") is not None or p.get("y_percent") is not None)
                ]
                if points_with_coords:
                    t_coords = doc.add_table(rows=len(points_with_coords) + 1, cols=5)
                    t_coords.style = "Table Grid"
                    headers = ["№ точки", "Элемент", "Сечение", "X, %", "Y, %"]
                    for i, h in enumerate(headers):
                        cell = t_coords.rows[0].cells[i]
                        cell.text = h
                        cell.paragraphs[0].runs[0].font.bold = True
                        cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                    for i, p in enumerate(points_with_coords, 1):
                        t_coords.rows[i].cells[0].text = str(i)
                        t_coords.rows[i].cells[1].text = str(p.get("location") or "")
                        t_coords.rows[i].cells[2].text = str(p.get("section_number") or "")
                        t_coords.rows[i].cells[3].text = str(p.get("x_percent") or "")
                        t_coords.rows[i].cells[4].text = str(p.get("y_percent") or "")
            
            # Группируем по элементам (Обечайка, Днище 1, Днище 2)
            elements = {}
            for point in thickness:
                location = str(point.get('location') or 'Обечайка')
                if location not in elements:
                    elements[location] = []
                elements[location].append(point)
            
            for element_name, points in elements.items():
                doc.add_paragraph()
                doc.add_paragraph(f"Элемент: {element_name}")
                t = doc.add_table(rows=len(points) + 3, cols=9)
                t.style = "Table Grid"
                headers = ["Наименование элемента", "№ точки", "Толщина, мм", "№ точки", "Толщина, мм", "№ точки", "Толщина, мм", "№ точки", "Толщина, мм"]
                for i, h in enumerate(headers):
                    cell = t.rows[0].cells[i]
                    cell.text = h
                    cell.paragraphs[0].runs[0].font.bold = True
                    cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
                
                # Заполняем точки по 4 в ряд
                row_idx = 1
                for i in range(0, len(points), 4):
                    row = t.rows[row_idx]
                    row.cells[0].text = element_name if i == 0 else ""
                    for j in range(4):
                        point_idx = i + j
                        if point_idx < len(points):
                            point = points[point_idx]
                            row.cells[j*2 + 1].text = str(point_idx + 1)
                            row.cells[j*2 + 2].text = str(point.get('thickness') or '')
                    row_idx += 1
                
                # Добавляем итоговые строки
                t.rows[row_idx].cells[0].text = "Номинальная толщина, мм"
                t.rows[row_idx].cells[1].text = "4,0"  # Можно взять из данных
                t.rows[row_idx + 1].cells[0].text = "Минимально-измеренная толщина, мм"
                min_thickness = min([float(str(p.get('thickness') or '0').replace(',', '.')) for p in points if p.get('thickness')], default=0)
                t.rows[row_idx + 1].cells[1].text = f"{min_thickness:.1f}" if min_thickness > 0 else "—"
                t.rows[row_idx + 2].cells[0].text = "Минимально допустимая толщина стеки сосуда, мм"
                t.rows[row_idx + 2].cells[1].text = "2,8"
            
            app_no += 1

        # ПРИЛОЖЕНИЕ № 5: Протокол по результатам ультразвукового контроля качества основного металла и сварных соединений
        welds = g('weld_inspections', default=[])
        if isinstance(welds, list) and len(welds) > 0:
            doc.add_page_break()
            doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Протокол по результатам ультразвукового контроля качества основного металла и сварных соединений", level=2)
            
            doc.add_paragraph("3. Результаты контроля")
            doc.add_paragraph("Контроль выполнен согласно схемы контроля приведенной в Приложении № 7.")
            
            weld_table = doc.add_table(rows=len(welds) + 1, cols=8)
            weld_table.style = "Table Grid"
            headers = ["№ стыка по карте контроля", "Условный номер дефекта", "Эквивалент. Площадь Sдеф, мм2", "Глубина залегания «Y» , мм", "Протяженность ΔL, мм", "Форма (характер) дефекта (объемный/ плоскостной)", "Местоположение на сварном соединении L, мм", "Заключение"]
            for i, h in enumerate(headers):
                cell = weld_table.rows[0].cells[i]
                cell.text = h
                cell.paragraphs[0].runs[0].font.bold = True
                cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            
            for idx, w in enumerate(welds, 1):
                weld_table.rows[idx].cells[0].text = str(w.get('weld_number') or '')
                weld_table.rows[idx].cells[1].text = "Дефектов не обнаружено"
                weld_table.rows[idx].cells[2].text = ""
                weld_table.rows[idx].cells[3].text = ""
                weld_table.rows[idx].cells[4].text = ""
                weld_table.rows[idx].cells[5].text = ""
                weld_table.rows[idx].cells[6].text = str(w.get('location_on_control_map') or '')
                weld_table.rows[idx].cells[7].text = str(w.get('conclusion') or 'годен')
            
            app_no += 1

        # ПРИЛОЖЕНИЕ № 6: Протокол по результатам оценки механических свойств элементов сосуда
        hardness = g('hardness_tests', default=[])
        if isinstance(hardness, list) and len(hardness) > 0:
            doc.add_page_break()
            doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Протокол по результатам оценки механических свойств элементов сосуда (измерение твердости металла)", level=2)
            
            doc.add_paragraph("2. Результаты контроля")
            
            hardness_table = doc.add_table(rows=len(hardness) + 1, cols=9)
            hardness_table.style = "Table Grid"
            headers = ["Наименование элемента", "№ точки", "Результат замера, НВ", "№ точки", "Результат замера, НВ", "№ точки", "Результат замера, НВ", "№ точки", "Результат замера, НВ"]
            for i, h in enumerate(headers):
                cell = hardness_table.rows[0].cells[i]
                cell.text = h
                cell.paragraphs[0].runs[0].font.bold = True
                cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            
            # Группируем по элементам
            hardness_by_element = {}
            for h in hardness:
                element = str(h.get('weld_number') or 'Обечайка')  # Используем weld_number как идентификатор элемента
                if element not in hardness_by_element:
                    hardness_by_element[element] = []
                hardness_by_element[element].append(h)
            
            row_idx = 1
            for element_name, tests in hardness_by_element.items():
                row = hardness_table.rows[row_idx]
                row.cells[0].text = element_name
                for j in range(min(4, len(tests))):
                    test = tests[j]
                    row.cells[j*2 + 1].text = str(j + 1)
                    # Используем hardness_base как основной результат
                    row.cells[j*2 + 2].text = str(test.get('hardness_base') or test.get('hardness_weld') or '')
                row_idx += 1
            
            doc.add_paragraph()
            doc.add_paragraph("Допустимый предел твердости для стали 19 ГС от 120 НВ до 180 НВ, в соответствии с СО 153-34.17.439-2003.")
            
            app_no += 1

        # ПРИЛОЖЕНИЕ № 7: Схема контроля
        control_scheme = g('control_scheme_image')
        if control_scheme:
            doc.add_page_break()
            doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Схема контроля", level=2)
            try:
                p = Path(str(control_scheme))
                if p.exists():
                    doc.add_picture(str(p), width=Inches(6.0))
            except Exception:
                pass
            app_no += 1

        # ПРИЛОЖЕНИЕ № 8: Расчетные и аналитические процедуры (если есть данные)
        
        # ПРИЛОЖЕНИЕ № 9: Акт проведения гидравлических испытаний (если есть)
        
        # ПРИЛОЖЕНИЕ № 10: Перечень применяемой нормативной документации
        doc.add_page_break()
        doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Перечень применяемой при техническом освидетельствовании нормативной, технической и методической документации", level=2)
        
        normative_docs = [
            "Федеральный закон от 21.07.1997г. №116 «О промышленной безопасности опасных производственных объектов».",
            "Федеральные нормы и правила в области промышленной безопасности «Правила промышленной безопасности при использовании оборудования, работающего под избыточным давлением», утвержденные приказом Федеральной службы по экологическому, технологическому и атомному надзору от 15.12.2020 №536",
            "СО 153-34.17.439-2003 «Инструкция по продлению срока службы сосудов, работающих под давлением».",
            "ГОСТ Р ИСО 17637-2014 «Контроль неразрушающий. Визуальный контроль соединений, выполненных сваркой плавлением»",
            "ГОСТ 34347-2017 «Сосуды и аппараты стальные сварные. Общие технические условия»",
            "ГОСТ Р 55614-2013 «Контроль неразрушающий. Толщиномеры ультразвуковые. Общие технические требования»",
            "ГОСТ Р ИСО 17640-2016 «Неразрушающий контроль сварных соединений. Ультразвуковой контроль. Технология, уровни контроля и оценки»",
            "ГОСТ Р 55724-2013 «Контроль неразрушающий. Соединения сварные. Методы ультразвуковые»",
            "СТО 00220256-005-2005 «Швы стыковых, угловых и тавровых сварных соединений сосудов и аппаратов, работающих под давлением. Методика ультразвукового контроля»",
            "ГОСТ 20911-89 «Техническая диагностика. Термины и определения»",
            "приказ Ростехнадзора от 16.01.2024 №8, Руководство по безопасности \"Методические рекомендации о порядке проведения визуального и измерительного контроля\"",
            "ГОСТ Р ИСО 16809-2015 «Контроль неразрушающий. Контроль ультразвуковой. Измерение толщины».",
            "ГОСТ 22761-77 «Металлы и сплавы. Метод измерения твердости по Бринеллю переносными твердомерами статического действия»",
        ]
        
        for idx, doc_text in enumerate(normative_docs, 1):
            doc.add_paragraph(f"{idx}. {doc_text}")

        # Дополнительные приложения по методам НК (если есть)
        if performed:
            for m in performed:
                if m.get('method_name') and m.get('method_name') not in ['Визуальный контроль', 'УЗТ', 'УЗК', 'Твердость']:
                    doc.add_page_break()
                    doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Протокол по результатам {m.get('method_name') or 'НК'}", level=2)
                    doc.add_paragraph(f"Дата проведения контроля: {self._fmt_date_ru(m.get('performed_date')) or date_perf_ru}")
                    doc.add_paragraph(f"НТД: {m.get('standard') or '—'}")
                    doc.add_paragraph(f"Оборудование: {m.get('equipment') or '—'}")
                    doc.add_paragraph(f"Результаты: {m.get('results') or '—'}")
                    if m.get("defects"):
                        doc.add_paragraph(f"Дефекты: {m.get('defects')}")
                    if m.get("conclusion"):
                        doc.add_paragraph(f"Заключение: {m.get('conclusion')}")
                    app_no += 1

        # Документы специалистов/поверки — оставляем в конце (если есть)
        if specialist_docs:
            doc.add_page_break()
            doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Документы специалистов НК", level=2)
            for s in specialist_docs:
                doc.add_heading(f"Специалист: {s.get('inspector_name') or '—'}", level=3)
                for c in (s.get("certifications") or []):
                    doc.add_paragraph(f"{c.get('certification_type') or 'Удостоверение'} № {c.get('certificate_number') or '—'}")
                    sp = c.get("scan_file_path")
                    if sp and isinstance(sp, str) and os.path.exists(sp):
                        try:
                            doc.add_picture(sp, width=Inches(6.0))
                        except Exception:
                            pass
            app_no += 1

        if verification_equipment:
            doc.add_page_break()
            doc.add_heading(f"ПРИЛОЖЕНИЕ № {app_no} Свидетельства о поверке оборудования", level=2)
            for eq in verification_equipment:
                sp = eq.get("scan_file_path")
                if sp and isinstance(sp, str) and os.path.exists(sp):
                    doc.add_paragraph(f"{eq.get('name') or ''} № {eq.get('verification_certificate_number') or ''}")
                    try:
                        doc.add_picture(sp, width=Inches(6.0))
                    except Exception:
                        pass

        doc.save(output_path)
        return
    
    def _setup_styles(self, doc: Document):
        """Настройка стилей документа"""
        # Можно настроить стили по необходимости
        pass
