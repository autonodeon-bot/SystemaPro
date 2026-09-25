"""
Сборка основного текста заключения ЭПБ (структура по образцу 25-3173).

Разделы 1–9 + оглавление. Приложения А–З формируются в word_generator.py.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH

from equipment_presets import preset_from_equipment_data

EPB_APPENDIX_LETTERS = "АБВГДЕЖЗИКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"

EPB_TOC_ITEMS = [
    "1. Вводная часть",
    "2. Наименование объекта экспертизы, на который распространяется действие заключения",
    "3. Данные о заказчике",
    "4. Цель экспертизы",
    "5. Сведения о документах, рассмотренных в процессе экспертизы",
    "6. Назначение и краткая характеристика объекта экспертизы",
    "7. Результаты проведённой экспертизы со ссылками на конкретные структурные единицы нормативных правовых актов в области промышленной безопасности",
    "8. Сведения о проведенных мероприятиях и о результатах технического диагностирования технического устройства",
    "9. Вывод заключения экспертизы",
    "Приложение А Акт о проведении работ по техническому диагностированию",
    "Приложение Б Акты по результатам неразрушающего контроля",
    "Приложение В Схема проведения неразрушающего контроля",
    "Приложение Г Расчетные и аналитические процедуры оценки и прогнозирования технического состояния объекта экспертизы",
    "Приложение Д Акт проведения гидравлических испытаний",
]

EPB_NORMATIVE_BULLETS = [
    (
        "Федеральный закон «О промышленной безопасности опасных производственных "
        "объектов», ст.9;"
    ),
    (
        "Федеральные нормы и правила в области промышленной безопасности "
        "«Правила промышленной безопасности при использовании оборудования, "
        "работающего под избыточным давлением», утвержденные приказом "
        "Ростехнадзора от 15.12.2020 №536, п.65, п.68, п.69, п.154, п.165, "
        "п.188, п.212, п.215–п.217, п.228, п.236, п.333, п.335, п.338–п.340, "
        "п.346, п.348, п.350, п.360, п.394, п.423, п.424, п.461, п.462, п.463 "
        "(далее по тексту приказ Ростехнадзора от 15.12.2020 №536);"
    ),
    (
        "Федеральные нормы и правила «Правила безопасности в нефтяной и газовой "
        "промышленности», утвержденные приказом Федеральной службы по "
        "экологическому, технологическому и атомному надзору от 15.12.2020 №534, "
        "п.6, п.32, п.125, п.126, п.128, п.129, п.131, п.228п, п.556, п.562, "
        "п.565, п.731, п.733, п.734, п.1148 (далее по тексту приказ "
        "Ростехнадзора от 15.12.2020 №534)."
    ),
]

EPB_EXPERT_ORG_ROWS = [
    ("Наименование", "Общество с ограниченной ответственностью «ЮТАР»"),
    (
        "Юридический (почтовый) адрес",
        "628285, Ханты-Мансийский автономный округ – Югра, г. Урай, "
        "улица Ивана Шестакова, строение 46Б",
    ),
    (
        "Лицензия",
        "Регистрационный номер Л043-00109-72/00514886 на осуществление "
        "деятельности по проведению экспертизы промышленной безопасности",
    ),
    (
        "Свидетельство",
        "№ АЦЛНК-5-00083 об аттестации лаборатории неразрушающих методов "
        "контроля ООО «ЮТАР»",
    ),
]

EPB_PURPOSE_BULLETS = [
    (
        "определение соответствия объекта экспертизы промышленной безопасности "
        "предъявляемым к нему требованиям промышленной безопасности;"
    ),
    "оценка фактического состояния;",
    "определение остаточного ресурса (срока службы);",
    (
        "установление срока и условий дальнейшей безопасной эксплуатации "
        "объекта экспертизы промышленной безопасности."
    ),
]

EPB_DAMAGE_MECHANISMS = [
    "общая поверхностная коррозия и локальные коррозионные повреждения (язвенная коррозия);",
    "механические повреждения, температурная деформация;",
    (
        "развитие трещин от непроектных нагрузок (подвижки фундаментов, "
        "деформации опор, повышенный уровень вибрации трубопроводов)."
    ),
]

EPB_DOCUMENT_NAMES: Dict[str, str] = {
    "1": "Лицензия на эксплуатацию взрывопожароопасных и химически опасных производственных объектов I, II и III классов опасности",
    "2": "Свидетельство о регистрации в государственном реестре опасных производственных объектов",
    "3": "Технологический регламент объектов опасных производственных объектов",
    "4": "План мероприятий по локализации и ликвидации последствий аварий на опасном производственном объекте",
    "5": "Положение о производственном контроле за соблюдением требований промышленной безопасности на ОПО",
    "6": "Журнал учета аварий и инцидентов на ОПО",
    "7": "Страховой полис обязательного страхования гражданской ответственности владельца опасного объекта",
    "8": "Приказ об организации безопасной эксплуатации оборудования, работающего под избыточным давлением",
    "9": "Приказ о назначении ответственного лица за осуществление производственного контроля",
    "10": "Паспорт сосуда (сборочный чертёж, расчёт на прочность, схема включения, инструкция по эксплуатации)",
    "11": "Инструкция по монтажу и эксплуатации",
    "12": "Паспорта на предохранительные клапаны",
    "13": "Паспорта на запорную арматуру",
    "14": "Документация на контрольно-измерительные приборы",
    "15": "Ремонтная (исполнительная) документация",
    "16": "Заключение экспертизы промышленной безопасности",
    "17": "Акты проведения УЗТ",
}


def epb_appendix_letter(app_no: int) -> str:
    idx = app_no - 1
    if 0 <= idx < len(EPB_APPENDIX_LETTERS):
        return EPB_APPENDIX_LETTERS[idx]
    return str(app_no)


def device_type_label(preset: str) -> str:
    return {
        "oil_settler": "Отстойник нефти",
        "gas_separator": "Газосепаратор",
        "underground_tank": "Ёмкость подземная",
        "receiver": "Ресивер",
    }.get(preset, "Сосуд")


@dataclass
class EpbReportContext:
    g: Callable[..., Any]
    opo_get: Callable[..., Any]
    device_name: str
    serial: str
    reg_no: str
    org: str
    location: str
    opo_name: str
    opo_reg: str
    opo_class: str
    date_perf_ru: str
    contractor: str
    director_title: str
    director_name: str
    purpose_default: Optional[str]
    equipment_data: Dict[str, Any]
    inspection_data: Dict[str, Any]
    ndt_methods: List[Dict[str, Any]]
    org_settings: Dict[str, Any] = field(default_factory=dict)
    performed_codes: Set[str] = field(default_factory=set)
    inspectors: List[str] = field(default_factory=list)
    inspection_engineers: List[Dict[str, Any]] = field(default_factory=list)
    docs_dict: Dict[str, Any] = field(default_factory=dict)
    docs_info: Dict[str, Any] = field(default_factory=dict)
    doc_meta_fn: Optional[Callable[[str], tuple]] = None
    scheme_index: str = ""
    construction_type: str = "горизонтальный с эллиптическими днищами"
    residual_life_years: str = "10"
    residual_life_until: str = ""
    allowed_pressure: str = "1,0"
    allowed_temperature: str = "плюс 80"


def _add_grid_table(doc: Document, rows: List[tuple[str, str]]) -> None:
    tbl = doc.add_table(rows=len(rows), cols=2)
    tbl.style = "Table Grid"
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, (k, v) in enumerate(rows):
        tbl.rows[i].cells[0].text = k
        tbl.rows[i].cells[1].text = v
    from epb_layout import format_table
    format_table(tbl, widths=[6,11.7], header_rows=0, size=11)


def _has_method(codes: Set[str], *aliases: str) -> bool:
    up = {c.upper() for c in codes}
    return any(a.upper() in up for a in aliases)


def append_epb_toc(doc: Document) -> None:
    doc.add_heading("Содержание", level=1)
    for item in EPB_TOC_ITEMS:
        p = doc.add_paragraph(item)
        p.paragraph_format.left_indent = None
    doc.add_page_break()


def build_epb_main_body(doc: Document, ctx: EpbReportContext) -> None:
    """Структура образца 26-2335; результаты берутся только из исходного отчёта."""
    from vessel_control_plan import control_scope
    from epb_layout import table as grid
    g = ctx.g
    shells, scope, issues = control_scope(g)
    for i, heading in enumerate(EPB_TOC_ITEMS[:9], 1):
        doc.add_heading(heading, level=1)
        if i == 1:
            doc.add_paragraph("1.1. Основание проведения экспертизы")
            doc.add_paragraph(f"Договор: {g('contract_number', 'basis', default='—')}. Исходный технический отчёт: {g('source_report_number', default='—')}. Дата диагностирования: {ctx.date_perf_ru}.")
            doc.add_paragraph(str(g("normative_basis", default="Нормативная документация приведена в перечне в конце заключения.")))
            doc.add_paragraph("1.2. Сведения об экспертной организации")
            settings = ctx.org_settings.get('contractor') or {}
            _add_grid_table(doc, [("Организационно-правовая форма и наименование", settings.get('legal_name') or ctx.contractor),
                ("Юридический (почтовый) адрес", settings.get('postal_address') or settings.get('address') or g('contractor_address', default='—')),
                ("Руководитель экспертной организации", f"{ctx.director_title} {ctx.director_name}"),
                ("Лицензия", settings.get('license') or '—'), ("Свидетельство", settings.get('certificate') or '—')])
            doc.add_paragraph("1.3. Сведения об экспертах, принимавших участие в проведении экспертизы")
            for expert in ctx.inspection_engineers:
                if isinstance(expert, dict):
                    doc.add_paragraph(f"Эксперт: {expert.get('full_name') or '—'}; удостоверение: {expert.get('certificate_number') or '—'}")
        elif i == 2:
            doc.add_paragraph(f"{ctx.device_name}, зав. № {ctx.serial}, рег. № {ctx.reg_no}.")
            doc.add_paragraph(f"Место эксплуатации: {ctx.location}. ОПО: {ctx.opo_name}; рег. № {ctx.opo_reg}; класс опасности: {ctx.opo_class}.")
        elif i == 3:
            _add_grid_table(doc, [("Заказчик", ctx.org), ("Адрес", str(g("customer_address", "organization_address", default="—")))])
        elif i == 4:
            doc.add_paragraph(str(g("expertise_purpose", default="Оценка соответствия технического устройства требованиям промышленной безопасности и определение возможности дальнейшей безопасной эксплуатации.")))
        elif i == 5:
            keys = sorted(set(ctx.docs_dict) | set(ctx.docs_info), key=str)
            rows = []
            for key in keys:
                meta = ctx.doc_meta_fn(str(key)) if ctx.doc_meta_fn else (None, None, None)
                info = ctx.docs_info.get(str(key)) or {}
                ident = "Не предоставлен" if meta[0] is False else f"№ {meta[1] or '—'}, дата {meta[2] or '—'}"
                rows.append([EPB_DOCUMENT_NAMES.get(str(key), str(key)), ident, info.get('pages') or '—'])
            grid(doc, ["Наименование документа", "Шифр, номер, дата", "Объём материала, л."], rows or [["Перечень не предоставлен", "—", "—"]], [9, 5.7, 3])
        elif i == 6:
            doc.add_paragraph(f"{ctx.device_name} предназначен для {g('purpose', 'vessel_purpose', default=ctx.purpose_default or '—')}.")
            doc.add_paragraph("Таблица 6.1. Регистрационные данные")
            grid(doc, ["Наименование объекта", "Заводской номер", "Регистрационный номер", "Тех. №", "Изготовитель", "Год изготовления", "Год ввода"],
                [[ctx.device_name, ctx.serial, ctx.reg_no, g('scheme_index'), g('manufacturer'), g('manufacturing_year', 'manufacture_year'), g('commissioning_year')]], [3.9,1.7,2,1.3,4.8,2,2])
            doc.add_paragraph("Таблица 6.2. Паспортные характеристики и параметры")
            labels = [("Наименование частей сосуда", "Корпус"), ("Рабочее давление, МПа", g('working_pressure')),
                ("Расчётное давление, МПа", g('design_pressure')), ("Рабочая температура среды, °C", g('working_temperature')),
                ("Расчётная температура стенки, °C", g('design_temperature')), ("Минимальная температура стенки, °C", g('min_wall_temperature')),
                ("Пробное давление, МПа", g('test_pressure')), ("Рабочая среда", g('working_medium')),
                ("Класс опасности рабочей среды", g('hazard_class')), ("Взрывоопасность среды", g('explosion_hazard')),
                ("Пожароопасность среды", g('fire_hazard')), ("Прибавка на коррозию, мм", g('corrosion_allowance')),
                ("Внутренний объём, м³", g('volume','internal_volume'))]
            grid(doc,["Наименование параметра, характеристики", "Значение, величина"],labels,[11,6.7])
            doc.add_paragraph("Таблица 6.3. Сведения об основных частях сосуда")
            elements = g('vessel_elements','passport_elements',default=[]) or []
            heads = [e for e in elements if 'обечай' not in str(e.get('name') or e.get('element_name') or '').lower()]
            grid(doc,["Элемент", "Диаметр, мм", "Длина, мм", "Толщина, мм", "Материал", "ГОСТ (ТУ)", "Сварка"],
                [[e.get('name') or e.get('element_name'), e.get('diameter_mm'), e.get('length_mm'),e.get('wall_thickness_mm'),e.get('material'),e.get('gost'),e.get('weld_data')] for e in shells+heads], [3.2,1.8,1.8,1.8,2.3,2.3,4.5])
            doc.add_paragraph(f"Количество обечаек: {len(shells)}. Объём УЗТ обечаек: {12 * len(shells)} точек. Контроль днищ и штуцеров учитывается отдельно.")
            doc.add_paragraph("Таблица 6.4. Сведения об основной арматуре, КИП и приборах безопасности")
            fittings=g('fittings','vessel_fittings',default=[]) or []
            grid(doc,["Наименование", "Количество, шт.", "Условный проход, мм", "Давление, МПа"],
                [[r.get('name'),r.get('quantity'),r.get('dn'),r.get('pressure')] for r in fittings] or [["Сведения не предоставлены",'—','—','—']],[8.7,2,3.5,3.5])
        elif i == 7:
            for key, label in [("doc_analysis_conclusion", "Анализ документации"), ("operating_conditions_conclusion", "Условия эксплуатации"), ("epb_compliance_analysis", "Оценка соответствия со ссылками на структурные единицы нормативных актов")]:
                doc.add_paragraph(f"{label}: {g(key, default='сведения не предоставлены')}")
        elif i == 8:
            table = doc.add_table(rows=1, cols=3); table.style = "Table Grid"
            for c, text in zip(table.rows[0].cells, ["Метод", "Участков по ТЗ", "Записей в отчёте"]): c.text = text
            for label, planned, actual in scope:
                for c, text in zip(table.add_row().cells, [label, planned if planned is not None else "не задано", actual]): c.text = str(text)
            for key, label in [("vik_conclusion", "ВИК"), ("uzt_conclusion", "УЗТ"), ("hardness_conclusion", "Твердометрия"), ("mpk_conclusion", "МК"), ("pvk_conclusion", "ПВК"), ("uzk_conclusion", "УЗК"), ("calculation_result", "Расчётные процедуры")]:
                doc.add_paragraph(f"{label}: {g(key, default='заключение не внесено')}")
            doc.add_paragraph("Результаты НК — Приложение Б; схема — Приложение В; расчёты — Приложение Г; гидравлическое испытание — Приложение Д.")
            for issue in issues:
                doc.add_paragraph(f"Неполнота исходных данных: {issue}.")
        else:
            conclusion = g("epb_conclusion", default=None)
            if issues:
                doc.add_paragraph("Итоговый вывод требует проверки полноты исходных данных, перечисленных в разделе 8.")
            if conclusion:
                doc.add_paragraph(str(conclusion))
            else:
                doc.add_paragraph("Вывод эксперта о соответствии требованиям промышленной безопасности не внесён.")
            doc.add_paragraph(f"Назначенный срок дальнейшей эксплуатации, лет: {g('residual_life_years', default='—')}; до: {g('residual_life_until', default='—')}.")
            doc.add_paragraph(f"Разрешённое давление, МПа: {g('allowed_pressure', default='—')}; температура, °C: {g('allowed_temperature', default='—')}.")
            doc.add_paragraph(str(g("epb_conditions", default="Условия дальнейшей эксплуатации не внесены.")))
            regulations=g('inspection_reglament',default=[]) or []
            if regulations:
                doc.add_paragraph("Регламент контроля технического состояния")
                grid(doc,["Вид контроля", "Периодичность", "Исполнитель"],[[r.get('control_type'),r.get('periodicity'),r.get('executor')] for r in regulations],[7.7,4,6])
            for expert in ctx.inspection_engineers:
                if isinstance(expert, dict): doc.add_paragraph(f"Эксперт __________________ {expert.get('full_name') or '—'}")
        doc.add_paragraph()


def append_epb_appendix_act(doc: Document, ctx: EpbReportContext) -> None:
    """Приложение А — акт о проведении работ (образец 25-3173)."""
    g = ctx.g
    preset = preset_from_equipment_data(ctx.equipment_data)
    type_label = device_type_label(preset)
    doc.add_paragraph(
        f"{ctx.date_perf_ru} года аттестованными специалистами лаборатории "
        f"неразрушающего контроля {ctx.contractor} было проведено техническое "
        f"диагностирование и оценка технического состояния {type_label} "
        f"зав.№ {ctx.serial}, рег.№ {ctx.reg_no}, эксплуатирующегося на опасном "
        f"производственном объекте – {ctx.opo_name}, {ctx.opo_class} класс опасности, "
        "проводимого в рамках экспертизы промышленной безопасности."
    )
    doc.add_paragraph(
        "Работы выполнены в соответствии с «Программой проведения работ по экспертизе "
        "промышленной безопасности сосудов, работающих под давлением»."
    )
    doc.add_paragraph(
        "Перечень работ, выполненных в ходе проведения технического диагностирования:"
    )
    for w in [
        "Анализ технической документации;",
        "Техническое диагностирование:",
        "Визуальный и измерительный контроль сосуда;",
        "Оперативное (функциональное) диагностирование сосуда;",
        "Ультразвуковой контроль толщины стенок элементов сосуда;",
        "Магнитопорошковый контроль качества сварных соединений сосуда;",
        "Ультразвуковой контроль качества сварных соединений сосуда;",
        "Оценка механических свойств элементов сосуда;",
        "Расчётные и аналитические процедуры оценки и прогнозирования технического состояния;",
        "Проведение гидравлического испытания сосуда.",
    ]:
        doc.add_paragraph(w)
    doc.add_paragraph(
        "По результатам работ составлен отчёт по анализу технической документации, "
        "оформлены протоколы неразрушающего контроля."
    )
    for ie in ctx.inspection_engineers[:3]:
        if isinstance(ie, dict) and ie.get("full_name"):
            role = ie.get("expert_area") or ie.get("role") or "Специалист"
            doc.add_paragraph(f"{role}   {ie['full_name']}")
    doc.add_paragraph()


def append_epb_appendix_doc_analysis(doc: Document, ctx: EpbReportContext) -> None:
    """Приложение Б — отчёт по анализу технической документации."""
    g = ctx.g
    preset = preset_from_equipment_data(ctx.equipment_data)
    type_label = device_type_label(preset)
    year = g("commissioning_year", default="—")
    doc.add_paragraph(
        f"{type_label} зав.№ {ctx.serial}, рег.№ {ctx.reg_no} введён в эксплуатацию "
        f"{year} году."
    )
    doc.add_paragraph(
        "Режимы эксплуатации сосуда ведутся в соответствии с требованиями приказа "
        "Ростехнадзора от 15.12.2020 №536 и требованиями к монтажу и эксплуатации."
    )
    from epb_protocol_tables import append_appendix_b_tables

    append_appendix_b_tables(doc, ctx)
    doc.add_paragraph(
        str(
            g(
                "doc_analysis_appendix_conclusion",
                default=f"{type_label} эксплуатируется по назначению, в пределах паспортных "
                "(разрешённых) характеристик и соответствует технической и эксплуатационной "
                "документации. Замечания по наличию и ведению эксплуатационной документации отсутствуют.",
            )
        )
    )
    doc.add_paragraph("Заключение по результатам анализа технической документации")
    doc.add_paragraph(
        "Предоставленная документация соответствует требованиям нормативных правовых актов."
    )
    doc.add_paragraph()
