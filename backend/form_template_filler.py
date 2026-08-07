"""
Заполнение Word-формы ТО «Приложение № 1. Обследование сосудов и аппаратов»
данными обследования из мобильного приложения.

Структура шаблона (таблицы/приложения) сохраняется; подставляются
паспортные данные сосуда и результаты измерений (ВИК, УЗТ, твердость, УЗК, МПК).
"""
from __future__ import annotations

import logging
import re
import shutil
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Pt
from docx.table import Table, _Cell
from docx.text.paragraph import Paragraph

from report_forms_registry import resolve_form_path
from report_org_settings import load_report_org_settings
from technical_report_builder import TO_DOCUMENT_NAMES
from form_media_helpers import (
    build_attachments_map,
    collect_hydraulic_act_paths,
    collect_photo_paths,
    collect_scheme_paths,
    find_paragraph_containing,
    insert_media_block,
    insert_paragraph_after,
    is_image_file,
    resolve_image_path,
    add_picture_after_paragraph,
)

logger = logging.getLogger(__name__)

MISSING = "—"
NOT_PROVIDED = "Не предоставлено"
_BLANK_RE = re.compile(r"_+")


def fill_vessel_form_to1(
    inspection_data: Dict[str, Any],
    equipment_data: Dict[str, Any],
    output_path: str,
    verification_equipment: Optional[List[Dict[str, Any]]] = None,
    org_settings: Optional[Dict[str, Any]] = None,
    specialist_docs: Optional[List[Dict[str, Any]]] = None,
    document_files: Optional[List[Dict[str, Any]]] = None,
    find_image: Optional[Any] = None,
    ndt_methods: Optional[List[Dict[str, Any]]] = None,
) -> str:
    """
    Скопировать шаблон to-1 и заполнить данными обследования.
    Возвращает путь к готовому файлу.
    """
    template = resolve_form_path("to-1")
    if template is None or not template.exists():
        raise FileNotFoundError(
            "Шаблон формы to-1 не найден в backend/report_forms/"
        )

    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(template, out)

    doc = Document(str(out))
    if org_settings is None:
        org_settings = load_report_org_settings()

    # Нормализуем/обогащаем data (мобильные ключи + методы НК + схемы УЗТ)
    inspection_data = dict(inspection_data or {})
    raw_data = inspection_data.get("data")
    if not isinstance(raw_data, dict):
        raw_data = {}
    inspection_data["data"] = _enrich_inspection_data(raw_data, ndt_methods or [])

    attachments = build_attachments_map(document_files)
    ctx = _build_context(
        inspection_data,
        equipment_data,
        verification_equipment or [],
        org_settings,
        specialist_docs or [],
        attachments,
    )
    ctx["find_image"] = find_image
    ctx["ndt_methods"] = ndt_methods or []

    tables = doc.tables
    if len(tables) < 39:
        logger.warning(
            "Шаблон to-1: ожидалось ≥39 таблиц, найдено %s", len(tables)
        )

    # Основной отчёт (титул + разделы 1–15) лежит в content control (SDT)
    # и раньше не попадал в doc.tables / doc.paragraphs.
    _fill_main_report(doc, ctx)
    _fix_main_report_captions(doc)

    # Заголовки протоколов (исполнитель / заказчик / зав.№)
    for idx in (0, 11, 14, 19, 23, 28, 33):
        if idx < len(tables):
            _fill_protocol_header(tables[idx], ctx)

    if len(tables) > 1:
        _fill_documents_table(tables[1], ctx)
    if len(tables) > 2:
        _fill_general_data(tables[2], ctx)
    if len(tables) > 3:
        _fill_elements_table(tables[3], ctx)
        _strip_empty_rows(tables[3], 2)
    if len(tables) > 4:
        _fill_characteristics(tables[4], ctx)
    if len(tables) > 5:
        _fill_materials(tables[5], ctx)
        _strip_empty_rows(tables[5], 2)
    if len(tables) > 6:
        _fill_heat_treatment(tables[6], ctx)
        _strip_empty_rows(tables[6], 2)
    if len(tables) > 7:
        _fill_strength_tests(tables[7], ctx)
        _strip_empty_rows(tables[7], 1)
    if len(tables) > 8:
        _fill_previous_inspections(tables[8], ctx)
        _strip_empty_rows(tables[8], 1)
    if len(tables) > 9:
        _fill_additional_data(tables[9], ctx)

    # Подписи специалистов (анализ документации и др.) — с учётом того, какой
    # именно вид НК соответствует протоколу (см. SIGNATURE_METHOD_KEYS).
    for idx in (10, 13, 18, 22, 27, 32, 37):
        if idx < len(tables):
            _fill_signatures(tables[idx], ctx, SIGNATURE_METHOD_KEYS.get(idx))

    # Прил. 2 — оперативная диагностика
    if len(tables) > 12:
        _fill_operational_diagnostics(tables[12], ctx)

    # Прил. 3 — ВИК: оборудование + результаты
    if len(tables) > 15:
        _fill_instrument_table(
            tables[15],
            ctx,
            method_keys=("ВИК", "VIK", "ПВК", "ОСВЕЩ", "ШЕРОХ", "RZ"),
            defaults=[
                ("Комплект ВИК", ""),
                ("Образцы шероховатости", ""),
                ("Измеритель освещённости", ""),
            ],
        )
    if len(tables) > 16:
        _fill_vik_parameters(tables[16], ctx)
    if len(tables) > 17:
        _fill_vik_results(tables[17], ctx)

    # Прил. 4 — УЗТ
    if len(tables) > 20:
        _fill_instrument_table(
            tables[20],
            ctx,
            method_keys=("УЗТ", "UZT", "ТОЛЩИНОМЕР"),
            defaults=[("Толщиномер", ""), ("Настроечный образец", ""), ("Образцы шероховатости", "")],
        )
    if len(tables) > 21:
        _fill_uzt_results(tables[21], ctx)

    # Прил. 5 — твердость
    if len(tables) > 24:
        _fill_instrument_table(
            tables[24],
            ctx,
            method_keys=("ТВЕРД", "TVI", "HARD"),
            defaults=[("Твердомер", ""), ("Меры твердости", ""), ("Образцы шероховатости", "")],
        )
    if len(tables) > 25:
        _fill_hardness_matrix(tables[25], ctx)
    if len(tables) > 26:
        _fill_hardness_list(tables[26], ctx)

    # Прил. 6 — УЗК
    if len(tables) > 29:
        _fill_instrument_table(
            tables[29],
            ctx,
            method_keys=("УЗК", "UZK", "ДЕФЕКТОСКОП"),
            defaults=[("Дефектоскоп", ""), ("СОП", ""), ("Образцы шероховатости", "")],
        )
    if len(tables) > 31:
        _fill_uzk_results(tables[31], ctx)

    # Прил. 7 — МПК
    if len(tables) > 34:
        _fill_instrument_table(
            tables[34],
            ctx,
            method_keys=("МПК", "MPK", "МАГНИТ"),
            defaults=[("Набор для МПД", ""), ("магнит", ""), ("КО", "")],
        )
    if len(tables) > 36:
        _fill_mpk_results(tables[36], ctx)

    _fill_paragraph_blanks(doc, ctx)
    _fill_appendix_8_calculation(doc, ctx)
    _fill_appendix_9_hydraulic_act(doc, ctx)
    _insert_schemes_and_photos(doc, ctx)

    # Унифицируем размер шрифта во всех таблицах данных (кроме титульного
    # листа), чтобы избежать посимвольного переноса и разнобоя в размере
    # текста между таблицами разных Приложений.
    try:
        main_tables_for_font = _main_sdt_tables(doc)
        for t in main_tables_for_font[1:]:
            _shrink_table_font(t)
        for t in doc.tables:
            _shrink_table_font(t)
    except Exception:
        logger.exception("to-1: не удалось унифицировать шрифт таблиц")

    doc.save(str(out))
    logger.info("Форма to-1 заполнена: %s", out)
    return str(out)


# ---------------------------------------------------------------------------
# Контекст данных
# ---------------------------------------------------------------------------

def _enrich_inspection_data(
    data: Dict[str, Any],
    ndt_methods: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Свести мобильные ключи и данные методов НК к единому словарю для формы."""
    out = dict(data or {})

    # Материал корпуса из элементов сосуда
    elements = out.get("vessel_elements") or out.get("elements") or []
    if isinstance(elements, list) and elements:
        first = next((e for e in elements if isinstance(e, dict)), None)
        if first:
            mat = first.get("material") or first.get("steel_grade")
            if mat and not out.get("shell_material"):
                out["shell_material"] = mat
            if first.get("gost") and not out.get("material_gost"):
                out["material_gost"] = first.get("gost")

    # Вложенные характеристики среды (mobile: medium_characteristics)
    medium = out.get("medium_characteristics")
    if isinstance(medium, dict):
        for src, dst in (
            ("hazard_class", "hazard_class"),
            ("class_hazard", "hazard_class"),
            ("explosion_hazard", "explosion_hazard"),
            ("explosion_category", "explosion_hazard"),
            ("fire_hazard", "fire_hazard"),
            ("fire_category", "fire_hazard"),
            ("composition", "working_medium"),
            ("working_medium", "working_medium"),
            ("temperature", "working_medium_temperature"),
        ):
            if medium.get(src) and not out.get(dst):
                out[dst] = medium.get(src)

    # ОПО: плоские ключи из вложенного объекта (если API/mobile положили dict)
    opo = out.get("opo")
    if isinstance(opo, dict):
        for src, dst in (
            ("name", "opo_name"),
            ("hazard_class", "opo_hazard_class"),
            ("registration_number", "opo_reg_number"),
            ("code", "opo_code"),
            ("description", "opo_description"),
        ):
            if opo.get(src) and not out.get(dst):
                out[dst] = opo.get(src)

    # Пустые заготовки previous_inspections / ndt_control_history не считаем данными
    for key in ("previous_inspections", "ndt_control_history", "heat_treatment_records"):
        recs = out.get(key)
        if isinstance(recs, list):
            cleaned = []
            for rec in recs:
                if not isinstance(rec, dict):
                    continue
                if any(
                    str(v).strip()
                    for k, v in rec.items()
                    if v not in (None, "", [], {}) and k not in ("id",)
                ):
                    cleaned.append(rec)
            out[key] = cleaned

    # История НК (Б4) → таблица предыдущих контролей, если previous_inspections пуст
    if not out.get("previous_inspections") and out.get("ndt_control_history"):
        out["previous_inspections"] = list(out["ndt_control_history"])
    elif out.get("previous_inspections") and out.get("ndt_control_history"):
        # Дополнить уникальными записями из ndt_control_history
        existing = out["previous_inspections"]
        if isinstance(existing, list):
            merged = list(existing)
            for rec in out["ndt_control_history"]:
                if isinstance(rec, dict) and rec not in merged:
                    merged.append(rec)
            out["previous_inspections"] = merged

    # Гидравлика: унифицировать type ← test_type
    hydro = out.get("hydraulic_test_history")
    if isinstance(hydro, list):
        for rec in hydro:
            if isinstance(rec, dict) and not rec.get("type") and rec.get("test_type"):
                rec["type"] = rec.get("test_type")

    # УЗТ: точки из uzt_schemes[].measurements → thickness_measurements
    thickness = out.get("thickness_measurements") or out.get("thicknessMeasurements")
    if not isinstance(thickness, list):
        thickness = []
    else:
        thickness = list(thickness)
    schemes = out.get("uzt_schemes") or []
    if isinstance(schemes, list):
        for sch in schemes:
            if not isinstance(sch, dict):
                continue
            for m in sch.get("measurements") or []:
                if isinstance(m, dict):
                    thickness.append(dict(m))
            # путь схемы как control_scheme, если основной пуст
            sp = sch.get("scheme_image_path") or sch.get("scheme_path")
            if sp and not out.get("control_scheme_image"):
                out["control_scheme_image"] = sp

    # Методы НК (таблица ndt_methods): точки УЗТ, дефекты, приборы, даты
    for m in ndt_methods or []:
        if not isinstance(m, dict):
            continue
        code = str(m.get("method_code") or m.get("method_name") or "").upper()
        ad = m.get("additional_data") or {}
        if not isinstance(ad, dict):
            ad = {}

        # Прибор метода → verification-like список в data
        eq_name = m.get("equipment") or ad.get("equipment")
        if eq_name:
            instruments = out.setdefault("_ndt_instruments", [])
            if isinstance(instruments, list):
                instruments.append(
                    {
                        "name": eq_name,
                        "serial_number": ad.get("serial_number") or "",
                        "equipment_type": code,
                        "method_code": code,
                    }
                )

        # Дата выполнения → inspection_date / method dates
        if m.get("performed_date") and not out.get("inspection_date"):
            out["inspection_date"] = m.get("performed_date")

        # УЗТ measurement_points из экрана «добавить метод НК»
        if any(k in code for k in ("УЗТ", "UZT", "ТОЛЩ")):
            pts = ad.get("measurement_points") or ad.get("points") or []
            if isinstance(pts, list):
                for p in pts:
                    if not isinstance(p, dict):
                        continue
                    thickness.append(
                        {
                            "location": p.get("location") or p.get("element") or p.get("zone") or "",
                            "section_number": p.get("point") or p.get("section_number") or p.get("number") or "",
                            "thickness": p.get("thickness") or p.get("value"),
                            "nominal_thickness": p.get("nominal_thickness")
                            or ad.get("nominal_thickness"),
                            "min_allowed_thickness": p.get("min_allowed_thickness")
                            or ad.get("min_allowed_thickness"),
                        }
                    )
            if ad.get("nominal_thickness") and not out.get("wall_thickness"):
                out["wall_thickness"] = ad.get("nominal_thickness")

        # ВИК дефекты + параметры контроля (шероховатость/освещённость)
        if any(k in code for k in ("ВИК", "VIK", "ПВК")):
            defects = m.get("defects")
            if isinstance(defects, list) and defects:
                existing = out.get("visual_defects") or []
                if not isinstance(existing, list) or not existing:
                    out["visual_defects"] = defects
            if m.get("results") and not out.get("vik_results_text"):
                out["vik_results_text"] = m.get("results")
            if m.get("conclusion") and not out.get("vik_conclusion_text"):
                out["vik_conclusion_text"] = m.get("conclusion")
            if ad.get("illumination") and not out.get("vik_illumination"):
                out["vik_illumination"] = ad.get("illumination")
            if ad.get("additional_lighting") is not None and "vik_additional_lighting" not in out:
                out["vik_additional_lighting"] = ad.get("additional_lighting")
            if ad.get("roughness") and not out.get("vik_roughness"):
                out["vik_roughness"] = ad.get("roughness")

        # УЗК
        if any(k in code for k in ("УЗК", "UZK")):
            mapped: List[Dict[str, Any]] = []
            defects = m.get("defects")
            if isinstance(defects, list) and defects:
                for d in defects:
                    if not isinstance(d, dict):
                        continue
                    mapped.append(
                        {
                            "weld_number": d.get("weld_number") or d.get("joint") or d.get("seam"),
                            "defect_description": d.get("description") or d.get("defect"),
                            "conclusion": d.get("conclusion") or d.get("assessment"),
                            "uzk_defect": d.get("description") or d.get("defect"),
                            "control_method": "UZK",
                        }
                    )

            # Экран «Добавить метод НК»: результаты точечного сканирования
            # (additional_data.results_list — zone/coordinate/amplitude/equivalent_size)
            results_list = ad.get("results_list") or []
            if isinstance(results_list, list) and results_list:
                method_conclusion = m.get("conclusion") or ""
                for r in results_list:
                    if not isinstance(r, dict):
                        continue
                    parts = []
                    if r.get("coordinate"):
                        parts.append(f"коорд. {r.get('coordinate')}")
                    if r.get("amplitude"):
                        parts.append(f"амплитуда {r.get('amplitude')} дБ")
                    if r.get("equivalent_size"):
                        parts.append(f"экв. размер {r.get('equivalent_size')} мм")
                    desc = ", ".join(parts)
                    mapped.append(
                        {
                            "weld_number": r.get("zone") or ad.get("control_zone") or "",
                            "defect_description": desc,
                            "uzk_defect": desc,
                            "area": r.get("equivalent_size") or r.get("area") or "",
                            "equivalent_area": r.get("equivalent_size") or "",
                            "depth": r.get("depth") or "",
                            "length": r.get("length") or r.get("extent") or "",
                            "form": r.get("form") or r.get("character") or "",
                            "location": r.get("coordinate") or r.get("location") or "",
                            "conclusion": method_conclusion,
                            "control_method": "UZK",
                        }
                    )

            # Свободный текст «Дефекты» (formData['defects']) — если структурированных
            # данных нет, заносим как единственную запись
            if not mapped and isinstance(defects, str) and defects.strip():
                mapped.append(
                    {
                        "weld_number": ad.get("control_zone") or "",
                        "defect_description": defects.strip(),
                        "uzk_defect": defects.strip(),
                        "conclusion": m.get("conclusion") or "",
                        "control_method": "UZK",
                    }
                )

            if mapped:
                existing = out.get("weld_inspections") or []
                if not isinstance(existing, list) or not existing:
                    out["weld_inspections"] = mapped

        # Твердость
        if any(k in code for k in ("ТВЕРД", "HARD", "TVI")):
            ht = ad.get("hardness_tests") or ad.get("points") or []
            if isinstance(ht, list) and ht:
                existing = out.get("hardness_tests") or []
                if not isinstance(existing, list) or not existing:
                    out["hardness_tests"] = ht

        # МПК / магнитный контроль
        if any(k in code for k in ("МПК", "MPK", "МАГНИТ", "MPI")):
            mapped_mpk: List[Dict[str, Any]] = []
            defects = m.get("defects")
            if isinstance(defects, list):
                for d in defects:
                    if not isinstance(d, dict):
                        continue
                    mapped_mpk.append(
                        {
                            "object": d.get("element") or d.get("object") or d.get("zone") or "",
                            "zone": d.get("zone") or d.get("location") or "",
                            "scope": d.get("scope") or ad.get("control_volume") or "100%",
                            "defects": d.get("description") or d.get("defect") or "",
                            "assessment": d.get("assessment")
                            or d.get("conclusion")
                            or m.get("conclusion")
                            or "",
                        }
                    )
            indications = ad.get("indications_list") or ad.get("results_list") or []
            if isinstance(indications, list):
                for ind in indications:
                    if not isinstance(ind, dict):
                        continue
                    mapped_mpk.append(
                        {
                            "object": ind.get("element") or ind.get("object") or "",
                            "zone": ind.get("zone") or ind.get("location") or "",
                            "scope": ind.get("scope") or "100%",
                            "defects": ind.get("description") or ind.get("indication") or "",
                            "assessment": ind.get("assessment") or m.get("conclusion") or "",
                        }
                    )
            if mapped_mpk:
                existing = out.get("mpk_results") or []
                if not isinstance(existing, list) or not existing:
                    out["mpk_results"] = mapped_mpk

    if thickness:
        out["thickness_measurements"] = thickness

    return out


def _build_context(
    inspection_data: Dict[str, Any],
    equipment_data: Dict[str, Any],
    verification_equipment: List[Dict[str, Any]],
    org_settings: Dict[str, Any],
    specialist_docs: List[Dict[str, Any]],
    attachments: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    data = inspection_data.get("data") or {}
    if not isinstance(data, dict):
        data = {}
    attrs = equipment_data.get("attributes") or {}
    if not isinstance(attrs, dict):
        attrs = {}

    def g(*keys: str, default: Any = MISSING) -> Any:
        for k in keys:
            if k in data and data.get(k) not in (None, ""):
                return data.get(k)
        for k in keys:
            if k in attrs and attrs.get(k) not in (None, ""):
                return attrs.get(k)
        for k in keys:
            camel = "".join(
                w.capitalize() if i else w for i, w in enumerate(k.split("_"))
            )
            camel_l = camel[0].lower() + camel[1:] if camel else k
            if camel_l in data and data.get(camel_l) not in (None, ""):
                return data.get(camel_l)
            if camel_l in attrs and attrs.get(camel_l) not in (None, ""):
                return attrs.get(camel_l)
        return default

    date_perf = (
        inspection_data.get("date_performed")
        or data.get("inspection_date")
    )
    date_ru = _fmt_date_ru(date_perf) or datetime.now().strftime("%d.%m.%Y")

    contractor = (org_settings.get("contractor") or {}) if isinstance(org_settings, dict) else {}
    customer = (org_settings.get("customer") or {}) if isinstance(org_settings, dict) else {}
    lab = (org_settings.get("ndt_lab") or {}) if isinstance(org_settings, dict) else {}

    device_name = str(
        g("equipment_device_name", "vessel_name", default=equipment_data.get("name") or MISSING)
    )
    serial = str(g("serial_number", default=equipment_data.get("serial_number") or MISSING))
    reg_no = str(g("reg_number", "regNumber", default=MISSING))
    inv_no = str(g("inventory_number", "inv_number", default=MISSING))
    location = str(g("location", "equipment_location", default=equipment_data.get("location") or ""))
    org_name = str(
        g(
            "organization",
            "customer_name",
            "enterprise_name",
            default=customer.get("legal_name") or MISSING,
        )
    )
    org_name, location = _split_customer_location(org_name, location)

    docs_dict = g("documents", default={}) or {}
    docs_info = g("documents_info", default={}) or {}
    if not isinstance(docs_dict, dict):
        docs_dict = {}
    if not isinstance(docs_info, dict):
        docs_info = {}

    specialists = _extract_specialists(data, specialist_docs)
    opo_name = str(g("opo_name", default=MISSING))
    opo_class = str(g("opo_hazard_class", "opo_class", default=MISSING))
    # Регистрационный № ОПО — официальный рег.номер; внутренний код (OPO-004)
    # не подставляем как «рег. №», чтобы не путать с реестровым номером Ростехнадзора.
    opo_reg = str(g("opo_reg_number", "opo_registration_number", default=MISSING))
    if opo_name in ("", MISSING):
        nested = data.get("opo") if isinstance(data.get("opo"), dict) else {}
        if nested.get("name"):
            opo_name = str(nested.get("name"))
    if opo_class in ("", MISSING):
        nested = data.get("opo") if isinstance(data.get("opo"), dict) else {}
        if nested.get("hazard_class"):
            opo_class = str(nested.get("hazard_class"))
    if opo_reg in ("", MISSING):
        nested = data.get("opo") if isinstance(data.get("opo"), dict) else {}
        if nested.get("registration_number"):
            opo_reg = str(nested.get("registration_number"))

    return {
        "g": g,
        "data": data,
        "attrs": attrs,
        "date_ru": date_ru,
        "device_name": device_name,
        "serial": serial,
        "reg_no": reg_no,
        "inv_no": inv_no,
        "location": location,
        "org_name": org_name,
        "opo_name": opo_name,
        "opo_class": opo_class,
        "opo_reg": opo_reg,
        "contractor_name": contractor.get("legal_name") or contractor.get("name") or "",
        "contractor_address": contractor.get("postal_address") or contractor.get("address") or "",
        "contractor_director": contractor.get("director_name") or contractor.get("director") or "",
        "contractor_phone": contractor.get("phone") or "",
        "contractor_email": contractor.get("email") or "",
        "customer_director": customer.get("director") or customer.get("director_name") or "",
        "customer_address": customer.get("address") or customer.get("legal_address") or "",
        "customer_phone": customer.get("phone") or "",
        "customer_email": customer.get("email") or "",
        "lab_name": lab.get("name") or contractor.get("legal_name") or "",
        "lab_cert": lab.get("certificate") or lab.get("attestation_number") or "",
        "docs_dict": docs_dict,
        "docs_info": docs_info,
        "verification_equipment": verification_equipment,
        "specialists": specialists,
        "specialist_docs": specialist_docs,
        "attachments": attachments or {},
        "org_settings": org_settings,
        "conclusion_doc": str(g("documentation_conclusion", "doc_analysis_conclusion", default="")),
        "conclusion_suitable": str(
            g("suitability_conclusion", "conclusion", default="соответствует")
        ),
        "operational_ok": str(
            g("operational_conclusion", "operational_ok", default="соответствует")
        ),
        "calculation_result": str(
            g(
                "calculation_result",
                "calc_assessment",
                default="сосуда при рабочих параметрах",
            )
        ),
        "tech_state": str(
            g(
                "technical_state",
                "suitability_status",
                default="работоспособное, пригодно к дальнейшей эксплуатации",
            )
        ),
    }



# Соответствие латинских/сокращённых кодов методов НК русскоязычным
# наименованиям области аттестации (кириллицей), как того требует НТД.
_METHOD_CODE_TO_RU = {
    "VIK": "ВИК",
    "VT": "ВИК",
    "VISUAL": "ВИК",
    "ПВК": "ВИК",
    "PVK": "ВИК",
    "UZK": "УЗК",
    "UT": "УЗК",
    "UZT": "УЗТ",
    "UTT": "УЗТ",
    "ТОЛЩИНОМЕТРИЯ": "УЗТ",
    "MPK": "МПК",
    "MT": "МПК",
    "МАГНИТ": "МПК",
    "TVI": "Твёрдометрия",
    "HARD": "Твёрдометрия",
    "HARDNESS": "Твёрдометрия",
    "ТВЕРД": "Твёрдометрия",
    "PT": "ПВК (капиллярный)",
    "ПВК-К": "ПВК (капиллярный)",
}


# Развёрнутые наименования приборов/оборудования по типу (коду метода НК),
# как того требует нормативная документация (не аббревиатура, а полное
# наименование + марка/модель прибора).
_INSTRUMENT_TYPE_FULL_NAME = {
    "ВИК": "Комплект для визуально-измерительного контроля",
    "VIK": "Комплект для визуально-измерительного контроля",
    "УЗК": "Ультразвуковой дефектоскоп",
    "UZK": "Ультразвуковой дефектоскоп",
    "УЗТ": "Ультразвуковой толщиномер",
    "UZT": "Ультразвуковой толщиномер",
    "МПК": "Дефектоскоп магнитопорошковый",
    "MPK": "Дефектоскоп магнитопорошковый",
    "ТВЕРД": "Твердомер",
    "HARD": "Твердомер",
    "TVI": "Твердомер",
    "ТВЕРДОМЕР": "Твердомер",
    "ПВК": "Комплект капиллярного контроля",
    "PVK": "Комплект капиллярного контроля",
    "ПВК (КАПИЛЛЯРНЫЙ)": "Комплект капиллярного контроля",
    "КОМПЛЕКТ КАПИЛЛЯРНОГО КОНТРОЛЯ (С РЕАГЕНТАМИ)": "Комплект капиллярного контроля",
    "ШЕРОХ": "Образец шероховатости поверхности",
    "RZ": "Образец шероховатости поверхности",
    "ОБРАЗЕЦ ШЕРОХОВАТОСТИ": "Образец шероховатости поверхности",
    "ОСВЕЩ": "Люксметр",
    "LUX": "Люксметр",
    "ЛЮКСМЕТР": "Люксметр",
}


def _instrument_full_name(eq: Dict[str, Any]) -> str:
    """Полное наименование прибора: <тип прибора> <марка/модель>."""
    et = str(eq.get("equipment_type") or "").strip()
    name = str(eq.get("name") or "").strip()
    model = str(eq.get("model") or "").strip()
    manufacturer = str(eq.get("manufacturer") or "").strip()
    prefix = _INSTRUMENT_TYPE_FULL_NAME.get(et.upper())
    # Марка — модель прибора, либо (если модели нет) собственное имя записи,
    # но только если оно не совпадает с кодом типа (иначе получим "ВИК ВИК").
    brand_parts = [manufacturer] if manufacturer else []
    if model:
        brand_parts.append(model)
    elif name and name.upper() != et.upper():
        brand_parts.append(name)
    brand = " ".join(p for p in brand_parts if p)
    if prefix:
        return f"{prefix} {brand}".strip() if brand else f"{prefix} __________ (марка прибора)"
    return name or et or MISSING


def method_label_ru(code: str) -> str:
    """Область аттестации кириллицей вместо латинского кода метода (напр. VIK → ВИК)."""
    raw = (code or "").strip()
    if not raw:
        return raw
    # Несколько кодов через запятую/слэш — переводим каждый
    parts = re.split(r"[,/;]+", raw)
    if len(parts) > 1:
        return ", ".join(method_label_ru(p.strip()) for p in parts if p.strip())
    return _METHOD_CODE_TO_RU.get(raw.upper(), raw)


def _extract_specialists(
    data: Dict[str, Any], specialist_docs: List[Dict[str, Any]]
) -> List[Dict[str, str]]:
    """Собрать специалистов, реально задействованных в ДАННОМ обследовании.

    Приоритет отдаётся специалистам, выбранным в мобильном приложении для
    этого обследования (``inspection_engineers``) — иначе в отчёт могли
    попасть посторонние ФИО (например, общий список исполнителей ОПО),
    не имеющие отношения к фактически выполненному контролю.
    """
    result: List[Dict[str, str]] = []

    def _upsert(
        name: str,
        cert: str = "",
        role: str = "",
        scan: str = "",
        valid_until: str = "",
    ) -> None:
        name = (name or "").strip()
        if not name:
            return
        for s in result:
            if s["name"].lower() == name.lower():
                if cert and not s.get("cert"):
                    s["cert"] = cert
                if role:
                    existing_roles = {r.strip().upper() for r in s.get("role", "").split(",") if r.strip()}
                    if role.strip().upper() not in existing_roles:
                        s["role"] = ", ".join(filter(None, [s.get("role", ""), role])).strip(", ")
                if scan and not s.get("scan"):
                    s["scan"] = scan
                if valid_until and not s.get("valid_until"):
                    s["valid_until"] = valid_until
                return
        result.append(
            {
                "name": name,
                "cert": cert or "",
                "role": role or "",
                "scan": scan or "",
                "valid_until": valid_until or "",
            }
        )

    def _cert_lookup(name: str) -> Dict[str, str]:
        """Найти № удостоверения / срок действия по ФИО в specialist_docs (справочник)."""
        for doc in specialist_docs or []:
            if not isinstance(doc, dict):
                continue
            doc_name = str(
                doc.get("inspector_name") or doc.get("specialist_name") or doc.get("name") or ""
            )
            if doc_name.strip().lower() != name.strip().lower():
                continue
            certs = doc.get("certifications") or []
            if isinstance(certs, list):
                for c in certs:
                    if not isinstance(c, dict):
                        continue
                    cert_no = str(c.get("certificate_number") or c.get("number") or "")
                    if cert_no:
                        return {
                            "cert": cert_no,
                            "scan": str(c.get("scan_file_path") or ""),
                            "valid_until": str(c.get("expiry_date") or ""),
                            "role": method_label_ru(str(c.get("method_code") or c.get("certification_type") or "")),
                        }
        return {}

    # 1) Специалисты, реально выбранные в мобильном приложении для этого обследования
    #    (по каждому виду НК — свой инженер).
    engineers = data.get("inspection_engineers") or []
    if isinstance(engineers, list):
        for eng in engineers:
            if not isinstance(eng, dict):
                continue
            name = str(eng.get("full_name") or eng.get("name") or "").strip()
            if not name:
                continue
            role_raw = str(eng.get("method") or "")
            _upsert(
                name,
                str(eng.get("certificate_number") or eng.get("cert") or ""),
                method_label_ru(role_raw),
                valid_until=str(eng.get("valid_until") or eng.get("expiry") or ""),
            )
            # Дозаполнить № удостоверения / срок действия из справочника (Certification),
            # если в чек-листе они не сохранились.
            found = _cert_lookup(name)
            if found:
                for s in result:
                    if s["name"].lower() == name.lower():
                        if not s.get("cert"):
                            s["cert"] = found.get("cert", "")
                        if not s.get("valid_until"):
                            s["valid_until"] = found.get("valid_until", "")
                        if not s.get("scan"):
                            s["scan"] = found.get("scan", "")
                        break

    if result:
        return result

    # 2) Фолбэк — specialist_docs из API (сертификаты по методам НК, выполненным в обследовании)
    for doc in specialist_docs or []:
        if not isinstance(doc, dict):
            continue
        name = str(
            doc.get("inspector_name")
            or doc.get("specialist_name")
            or doc.get("name")
            or ""
        )
        certs = doc.get("certifications") or []
        cert_no = ""
        scan = ""
        valid_until = ""
        role = str(doc.get("role") or "")
        if isinstance(certs, list) and certs:
            for c in certs:
                if not isinstance(c, dict):
                    continue
                cert_no = str(
                    c.get("certificate_number") or c.get("number") or c.get("cert") or ""
                )
                scan = str(c.get("scan_file_path") or c.get("scan") or "")
                valid_until = str(c.get("expiry_date") or c.get("valid_until") or "")
                method = str(c.get("method_code") or c.get("certification_type") or "")
                if method and not role:
                    role = method_label_ru(method)
                if cert_no:
                    break
        else:
            cert_no = str(doc.get("certificate_number") or doc.get("cert") or "")
            scan = str(doc.get("scan_file_path") or "")
        _upsert(name, cert_no, role, scan, valid_until)

    if result:
        return result

    # 3) Последний фолбэк — свободный текст исполнителей (напр. общий список по ОПО),
    #    используется, только если конкретных специалистов по обследованию нет вовсе.
    executors = data.get("executors") or data.get("specialists")
    if isinstance(executors, str) and executors.strip():
        for part in re.split(r"[,;/\n]+", executors):
            _upsert(part.strip())
    if isinstance(executors, list):
        for item in executors:
            if isinstance(item, dict):
                _upsert(
                    str(item.get("name") or item.get("full_name") or ""),
                    str(item.get("certificate") or item.get("cert_number") or ""),
                    method_label_ru(str(item.get("role") or "")),
                )
            elif isinstance(item, str) and item.strip():
                _upsert(item.strip())

    return result


# ---------------------------------------------------------------------------
# Низкоуровневые хелперы ячеек
# ---------------------------------------------------------------------------

def _set_cell(cell: _Cell, text: Any, *, nowrap: bool = False) -> None:
    value = "" if text is None else str(text)
    if value in ("None",):
        value = ""
    # Неразрывный дефис — чтобы «09Г2С» / даты не ломались посередине
    if nowrap:
        value = value.replace("-", "\u2011")
    paragraphs = cell.paragraphs
    if not paragraphs:
        cell.text = value
        return
    p0 = paragraphs[0]
    if p0.runs:
        p0.runs[0].text = value
        for run in p0.runs[1:]:
            run.text = ""
    else:
        p0.text = value
    for p in paragraphs[1:]:
        p.clear()
    try:
        tc = cell._tc
        tcPr = tc.get_or_add_tcPr()
        for old in list(tcPr.findall(qn("w:noWrap"))):
            tcPr.remove(old)
        if nowrap:
            tcPr.append(OxmlElement("w:noWrap"))
        # Иначе явно НЕ добавляем noWrap — длинный текст (напр. полное
        # наименование организации-исполнителя) должен переноситься по
        # словам, а не обрезаться/вылезать за пределы ячейки шаблона.
    except Exception:
        pass


def _cell(table: Table, row: int, col: int) -> Optional[_Cell]:
    try:
        return table.rows[row].cells[col]
    except (IndexError, KeyError):
        return None


def _set(table: Table, row: int, col: int, text: Any, *, nowrap: bool = False) -> None:
    c = _cell(table, row, col)
    if c is not None:
        _set_cell(c, text, nowrap=nowrap)


def _split_customer_location(org_name: str, location: str) -> Tuple[str, str]:
    """Отделить местонахождение от иерархии заказчика (… / Пункт подготовки…)."""
    org = (org_name or "").strip()
    loc = (location or "").strip()
    if loc in ("", "-", "—", MISSING):
        loc = ""
    if not loc and " / " in org:
        parts = [p.strip() for p in org.split(" / ") if p.strip()]
        if len(parts) >= 2:
            loc = parts[-1]
            org = " / ".join(parts[:-1])
    return org or MISSING, loc or MISSING


def _iter_all_paragraphs(doc: Document):
    """Все абзацы документа, включая content controls (SDT)."""
    body = doc.element.body
    for p_el in body.iter(qn("w:p")):
        yield Paragraph(p_el, doc)


def _main_sdt_tables(doc: Document) -> List[Table]:
    """Таблицы основного отчёта (титул + разд. 1–15) из первого SDT."""
    body = doc.element.body
    for child in body.iterchildren():
        if child.tag != qn("w:sdt"):
            continue
        content = child.find(qn("w:sdtContent"))
        if content is None:
            continue
        texts = "".join(t.text or "" for t in content.iter(qn("w:t")))
        if "ТЕХНИЧЕСКИЙ ОТЧЕТ" not in texts and "УТВЕРЖДАЮ" not in texts:
            continue
        return [Table(tbl, doc) for tbl in content.iter(qn("w:tbl"))]
    return []


def _insert_page_break_before_paragraph(paragraph: Paragraph) -> None:
    """Вставить разрыв страницы перед абзацем (СОДЕРЖАНИЕ на новой странице)."""
    p = paragraph._p
    parent = p.getparent()
    if parent is None:
        return
    prev = p.getprevious()
    if prev is not None and prev.tag == qn("w:p"):
        for br in prev.iter(qn("w:br")):
            if br.get(qn("w:type")) == "page":
                return
    new_p = OxmlElement("w:p")
    r = OxmlElement("w:r")
    br = OxmlElement("w:br")
    br.set(qn("w:type"), "page")
    r.append(br)
    new_p.append(r)
    parent.insert(list(parent).index(p), new_p)


_APPENDIX_TABLE_FONT_PT = 8.5


def _shrink_table_font(table: Table, pt: float = _APPENDIX_TABLE_FONT_PT) -> None:
    """Уменьшить и унифицировать размер шрифта во всех ячейках таблицы.

    Данные в таблицах Приложений должны отображаться одинаково и легко
    читаться; также уменьшение шрифта снижает риск посимвольного переноса
    длинных «слов» без пробелов (марка стали, ГОСТ, «Автоматическая» и т.п.)
    в узких колонках при конвертации docx → pdf.
    """
    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                for r in p.runs:
                    r.font.size = Pt(pt)


def _add_table_row(table: Table) -> None:
    """Добавить строку, копируя структуру последней и очищая текст."""
    tbl = table._tbl
    last_tr = tbl.tr_lst[-1]
    new_tr = deepcopy(last_tr)
    for tc in new_tr.tc_lst:
        for node in tc.iterchildren():
            if node.tag == qn("w:p"):
                for r in node.findall(qn("w:r")):
                    for t in r.findall(qn("w:t")):
                        t.text = ""
    tbl.append(new_tr)


def _ensure_rows(table: Table, needed: int) -> None:
    while len(table.rows) < needed:
        _add_table_row(table)


def _insert_row_after(table: Table, after_idx: int, values: Sequence[Any]) -> int:
    """Вставить пустую строку-копию сразу после ``after_idx`` и заполнить
    значениями, начиная с колонки 1. Возвращает индекс новой строки.

    Нужно для динамического добавления объектов контроля (напр. ВИК), когда
    их больше, чем предусмотрено строк-заготовок в шаблоне.
    """
    ref_tr = table.rows[after_idx]._tr
    new_tr = deepcopy(ref_tr)
    for tc in new_tr.tc_lst:
        for node in tc.iterchildren():
            if node.tag == qn("w:p"):
                for r in node.findall(qn("w:r")):
                    for t in r.findall(qn("w:t")):
                        t.text = ""
    ref_tr.addnext(new_tr)
    new_idx = after_idx + 1
    for c, v in enumerate(values, start=1):
        _set(table, new_idx, c, v)
    return new_idx


def _row_is_blank(row, ignore_cols: Optional[Sequence[int]] = None) -> bool:
    ignore = set(ignore_cols or ())
    for c, cell in enumerate(row.cells):
        if c in ignore:
            continue
        text = (cell.text or "").strip().strip(".")
        if text and text not in ("—", "-"):
            return False
    return True


def _strip_empty_rows(
    table: Table, start_row: int, ignore_cols: Optional[Sequence[int]] = None
) -> int:
    """Удалить полностью незаполненные строки таблицы (кроме заголовков).

    Нужно, чтобы в готовом отчёте не оставались пустые строки таблиц —
    например, если специалистов/точек контроля меньше, чем строк-заготовок
    в исходном шаблоне.
    """
    tbl = table._tbl
    removed = 0
    for idx in range(len(table.rows) - 1, start_row - 1, -1):
        if idx >= len(table.rows):
            continue
        row = table.rows[idx]
        if _row_is_blank(row, ignore_cols=ignore_cols):
            tbl.remove(row._tr)
            removed += 1
    return removed


def _replace_underscores(text: str, replacements: Sequence[str]) -> str:
    """Последовательно заменить группы подчёркиваний значениями."""
    result = text
    for val in replacements:
        m = _BLANK_RE.search(result)
        if not m:
            break
        result = result[: m.start()] + (val or "____") + result[m.end() :]
    return result


def _fmt_date_ru(value: Any) -> Optional[str]:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value.strftime("%d.%m.%Y")
    s = str(value).strip()
    if not s:
        return None
    if re.match(r"^\d{2}\.\d{2}\.\d{4}$", s):
        return s
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).strftime("%d.%m.%Y")
    except Exception:
        pass
    for fmt, length in (("%Y-%m-%d", 10), ("%d.%m.%Y", 10)):
        try:
            return datetime.strptime(s[:length], fmt).strftime("%d.%m.%Y")
        except ValueError:
            continue
    return s


# ---------------------------------------------------------------------------
# Основной отчёт (SDT: титул + разделы 1–15)
# ---------------------------------------------------------------------------

def _fix_main_report_captions(doc: Document) -> None:
    """Исправить задвоение «Таблица № 6» у раздела 10 → «Таблица № 7»."""
    seen_works = False
    for p in _iter_all_paragraphs(doc):
        tx = (p.text or "").strip()
        # Не брать строку оглавления («…диагностирования5»)
        if tx.startswith("10. Перечень работ, выполненных") and not tx[-1:].isdigit():
            seen_works = True
            continue
        if seen_works and tx in ("Таблица № 6", "Таблица №6"):
            _set_paragraph_text(p, "Таблица № 7")
            break


def _uzt_smin_summary(ctx: Dict[str, Any]) -> str:
    g = ctx["g"]
    measurements = g("thickness_measurements", "thicknessMeasurements", default=[])
    if not isinstance(measurements, list) or not measurements:
        return "Обечайка Smin= — мм\nДнище верхнее Smin= — мм\nДнище нижнее Smin= — мм"
    by_el: Dict[str, List[float]] = {}
    for m in measurements:
        if not isinstance(m, dict):
            continue
        el = str(m.get("element") or m.get("element_name") or m.get("location") or "Элемент")
        raw = m.get("thickness") or m.get("value") or m.get("thickness_mm")
        try:
            val = float(str(raw).replace(",", "."))
        except (TypeError, ValueError):
            continue
        by_el.setdefault(el, []).append(val)
    if not by_el:
        return "Обечайка Smin= — мм\nДнище верхнее Smin= — мм\nДнище нижнее Smin= — мм"
    lines = []
    for el, vals in by_el.items():
        lines.append(f"{el} Smin= {min(vals):g} мм")
    return "\n".join(lines)


def _fill_main_report(doc: Document, ctx: Dict[str, Any]) -> None:
    """Заполнить титул и таблицы/абзацы разделов 1–15 внутри SDT."""
    main_tables = _main_sdt_tables(doc)
    if not main_tables:
        logger.warning("to-1: основной отчёт (SDT) не найден — титул/разд.1–15 не заполнены")
        return

    g = ctx["g"]
    device = ctx["device_name"]
    serial = ctx["serial"]
    reg_no = ctx["reg_no"]
    inv_no = ctx["inv_no"]
    location = ctx["location"]
    org_name = ctx["org_name"]

    # --- Таблица 0: титул ---
    if len(main_tables) > 0:
        title = main_tables[0]
        if len(title.rows) > 6:
            _set(title, 6, 1, device)
            if len(title.rows[6].cells) > 2:
                _set(title, 6, 2, device)
        if len(title.rows) > 7:
            _set(title, 7, 1, serial, nowrap=True)
            if len(title.rows[7].cells) > 2:
                _set(title, 7, 2, serial, nowrap=True)
        if len(title.rows) > 8:
            _set(title, 8, 1, reg_no, nowrap=True)
            if len(title.rows[8].cells) > 2:
                _set(title, 8, 2, reg_no, nowrap=True)
        if len(title.rows) > 9:
            # В одной ячейке шаблона склеены инв.№ / ОПО
            inv_block = (
                f"{inv_no}\n{ctx.get('opo_name') or MISSING}\n"
                f"{ctx.get('opo_class') or MISSING}\n{ctx.get('opo_reg') or MISSING}"
            )
            _set(title, 9, 1, inv_block)
            if len(title.rows[9].cells) > 2:
                _set(title, 9, 2, inv_block)
        if len(title.rows) > 11:
            # Местонахождение объекта на титуле — полный адрес: наименование
            # заказчика/структурного подразделения + место нахождения.
            addr_parts = [p for p in (org_name, location) if p and p != MISSING]
            loc_text = ", ".join(addr_parts) if addr_parts else MISSING
            _set(title, 11, 1, loc_text)
            if len(title.rows[11].cells) > 2:
                _set(title, 11, 2, loc_text)

    # --- Таблица 1: номер отчёта ---
    if len(main_tables) > 1:
        report_no = str(g("protocol_number", "report_number", default="") or "")
        if report_no:
            _set(main_tables[1], 0, 1, report_no, nowrap=True)

    # --- Таблица 2: заказчик ---
    if len(main_tables) > 2:
        cust = main_tables[2]
        vals = [
            org_name,
            ctx.get("customer_director") or MISSING,
            ctx.get("customer_address") or MISSING,
            location if location != MISSING else MISSING,
            ctx.get("customer_phone") or MISSING,
            ctx.get("customer_email") or MISSING,
        ]
        for i, v in enumerate(vals):
            if i < len(cust.rows):
                _set(cust, i, 1, v)

    # --- Таблица 3: исполнитель ---
    if len(main_tables) > 3:
        contr = main_tables[3]
        vals = [
            ctx.get("contractor_name") or MISSING,
            ctx.get("contractor_director") or MISSING,
            ctx.get("contractor_address") or MISSING,
            ctx.get("contractor_address") or MISSING,
            ctx.get("contractor_phone") or MISSING,
            ctx.get("contractor_email") or MISSING,
            ctx.get("lab_cert") or MISSING,
        ]
        for i, v in enumerate(vals):
            if i < len(contr.rows):
                _set(contr, i, 1, v)

    # --- Таблица 4: специалисты ---
    if len(main_tables) > 4:
        specs = ctx.get("specialists") or []
        st = main_tables[4]
        data_rows = max(0, len(st.rows) - 1)
        for i in range(data_rows):
            r = i + 1
            if i < len(specs):
                s = specs[i]
                _set(st, r, 0, f"{i + 1}.")
                _set(st, r, 1, s.get("name") or "")
                _set(st, r, 2, s.get("cert") or MISSING, nowrap=True)
                _set(st, r, 3, s.get("role") or s.get("area") or MISSING)
                _set(st, r, 4, _fmt_date_ru(s.get("valid_until") or s.get("expiry")) or (s.get("valid_until") or s.get("expiry")) or MISSING)
            else:
                # Нет данных на эту строку — очищаем, чтобы не оставался
                # посторонний текст из шаблона (напр. пример из старого обследования).
                for c in range(len(st.rows[r].cells)):
                    _set(st, r, c, "")
        _strip_empty_rows(st, 1, ignore_cols=(0,))

    # --- Таблица 5: приборы ---
    if len(main_tables) > 5:
        ve = list(ctx.get("verification_equipment") or [])
        it = main_tables[5]
        data_rows = max(0, len(it.rows) - 1)
        for i in range(data_rows):
            r = i + 1
            if i < len(ve) and isinstance(ve[i], dict):
                eq = ve[i]
                _set(it, r, 0, f"{i + 1}.")
                _set(it, r, 1, _instrument_full_name(eq))
                _set(
                    it,
                    r,
                    2,
                    eq.get("serial_number") or eq.get("factory_number") or MISSING,
                    nowrap=True,
                )
                _set(
                    it,
                    r,
                    3,
                    eq.get("verification_certificate_number")
                    or eq.get("certificate")
                    or eq.get("verification_certificate")
                    or MISSING,
                    nowrap=True,
                )
                _set(
                    it,
                    r,
                    4,
                    _fmt_date_ru(
                        eq.get("next_verification_date")
                        or eq.get("valid_until")
                        or eq.get("verification_until")
                    )
                    or eq.get("next_verification_date")
                    or MISSING,
                    nowrap=True,
                )
            else:
                for c in range(len(it.rows[r].cells)):
                    _set(it, r, c, "")
        _strip_empty_rows(it, 1, ignore_cols=(0,))

    # --- Таблица 6: перечень объектов ---
    if len(main_tables) > 6:
        ot = main_tables[6]
        obj_rows = [
            ("Наименование", device),
            ("Заводской №", serial),
            ("Регистрационный №", reg_no),
            ("Инвентарный №", inv_no),
            ("Местонахождение", location),
            ("Заказчик", org_name),
        ]
        for i, (k, v) in enumerate(obj_rows):
            if i < len(ot.rows):
                if not (ot.rows[i].cells[0].text or "").strip():
                    _set(ot, i, 0, k)
                _set(ot, i, 1, v)

    # --- Таблица 7: краткая теххарактеристика ---
    if len(main_tables) > 7:
        tech = main_tables[7]
        tech_vals = [
            device,
            g("purpose", "vessel_purpose", default=MISSING),
            g("designation", "conditional_designation", "scheme_index", default=MISSING),
            g("manufacturer", default=MISSING),
            g("manufacture_year", "year_of_manufacture", "manufacturing_year", default=MISSING),
            g("commissioning_year", default=MISSING),
            g("design_pressure", default=MISSING),
            g("working_pressure", default=MISSING),
            g("diameter", "inner_diameter", default=MISSING),
            g("working_medium", "medium", default=MISSING),
            g(
                "working_medium_temperature",
                "medium_temperature",
                "working_temperature",
                default=MISSING,
            ),
            g("shell_material", "material", default=MISSING),
            g("volume", "capacity", default=MISSING),
            g("connection_scheme", default=MISSING),
            g("climatic_version", default=MISSING),
            g("service_life", default=MISSING),
        ]
        for i, v in enumerate(tech_vals):
            if i < len(tech.rows):
                _set(tech, i, 1, v if v not in (None, "") else MISSING)

    # --- Таблица 8: перечень работ ---
    if len(main_tables) > 8:
        works = main_tables[8]
        ndt = ctx.get("ndt_methods") or []
        scope_by_key = {
            "ВИК": "100%",
            "УЗТ": "по схеме контроля",
            "УЗК": "по схеме контроля",
            "МПК": "100%",
            "ТВЕРД": "по схеме контроля",
        }
        for r in range(1, len(works.rows)):
            name = (works.rows[r].cells[1].text or "").upper()
            scope = "в полном объёме"
            ntd = "СТО Газпром 2-2.3-491-2010"
            if "ВИЗУАЛЬ" in name:
                scope = scope_by_key["ВИК"]
                ntd = "СТО 9701105632-003-2021"
            elif "ТОЛЩИНОМЕТР" in name:
                scope = scope_by_key["УЗТ"]
                ntd = "ГОСТ Р ИСО 16809-2015"
            elif "ТВЕРД" in name:
                scope = scope_by_key["ТВЕРД"]
                ntd = "ГОСТ 22761-77"
            elif "УЛЬТРАЗВУКОВОЙ КОНТРОЛЬ КАЧЕСТВА" in name or "УЗК" in name:
                scope = scope_by_key["УЗК"]
                ntd = "ГОСТ Р 55724-2013"
            elif "МАГНИТ" in name:
                scope = scope_by_key["МПК"]
                ntd = "ГОСТ Р 56512-2015"
            elif "ГИДРАВЛ" in name:
                scope = "в соответствии с программой"
                ntd = "ФНП №536"
            # Если метод не выполнялся — оставить пустым объём
            performed = True
            if isinstance(ndt, list) and ndt:
                # не блокируем стандартный перечень — всегда заполняем объём/НТД
                performed = True
            if performed:
                _set(works, r, 2, scope)
                _set(works, r, 3, ntd)

    # --- Таблица 9: рассмотренные документы (как прил.1 / табл.1) ---
    if len(main_tables) > 9:
        docs_tbl = main_tables[9]
        docs_dict = ctx["docs_dict"]
        docs_info = ctx["docs_info"]
        for r in range(1, len(docs_tbl.rows)):
            num_txt = (docs_tbl.rows[r].cells[0].text or "").strip().rstrip(".")
            if not num_txt.isdigit():
                continue
            info = docs_info.get(num_txt) or docs_info.get(int(num_txt)) or {}
            if not isinstance(info, dict):
                info = {}
            present = docs_dict.get(num_txt, docs_dict.get(int(num_txt)))
            ident, pages = _doc_ident_and_pages(present, info)
            _set(docs_tbl, r, 2, ident)
            _set(docs_tbl, r, 3, pages)

    # --- Таблица 10: предыдущие обследования ---
    if len(main_tables) > 10:
        prev_tbl = main_tables[10]
        records = g("previous_inspections", default=[])
        if not isinstance(records, list):
            records = []
        if not records:
            legacy = g("previous_inspection_result", default="")
            if legacy and legacy != MISSING:
                records = [{"kind": "Техническое диагностирование", "result": legacy}]
        for i, rec in enumerate(records[: max(0, len(prev_tbl.rows) - 1)]):
            if not isinstance(rec, dict):
                continue
            r = i + 1
            _set(prev_tbl, r, 0, f"{i + 1}.")
            _set(prev_tbl, r, 1, rec.get("kind") or rec.get("type") or "")
            _set(prev_tbl, r, 2, rec.get("result") or "")
            report = rec.get("report_number") or rec.get("report") or ""
            date = _fmt_date_ru(rec.get("date")) or rec.get("date") or ""
            doc_ref = f"{report} от {date}".strip(" от") if (report or date) else ""
            _set(prev_tbl, r, 3, doc_ref)
        _strip_empty_rows(prev_tbl, 1, ignore_cols=(0,))

    # --- Таблица 11: результаты ТД ---
    if len(main_tables) > 11:
        res = main_tables[11]
        smin = _uzt_smin_summary(ctx)
        if len(res.rows) > 4:
            _set(res, 4, 2, smin)
        appendix_nums = {
            1: "1",
            2: "2",
            3: "3",
            4: "4",
            5: "5",
            6: "6",
            7: "7",
            8: "8",
        }
        for r, app in appendix_nums.items():
            if r < len(res.rows) and len(res.rows[r].cells) > 3:
                cell_txt = (res.rows[r].cells[3].text or "").strip()
                if "Приложение" in cell_txt and "_" in cell_txt:
                    _set(res, r, 3, f"Приложение № {app}")

    # --- Абзацы разделов 1, 2, 14, 15 + разрыв перед СОДЕРЖАНИЕ ---
    contract = str(g("contract_number", "work_basis", "basis", default="") or "")
    contract_date = _fmt_date_ru(g("contract_date", default="")) or str(g("contract_date", default="") or "")
    period_from = _fmt_date_ru(g("work_period_from", "date_from", default="")) or ""
    period_to = _fmt_date_ru(g("work_period_to", "date_to", "date_performed", default=ctx["date_ru"])) or ctx["date_ru"]
    calc_txt = ctx.get("calculation_result") or "сосуда при рабочих параметрах"
    tech_state = ctx.get("tech_state") or "работоспособное"
    conclusion = ctx.get("conclusion_suitable") or "соответствует"

    for p in _iter_all_paragraphs(doc):
        text = p.text or ""
        stripped = text.strip()
        if stripped == "СОДЕРЖАНИЕ":
            _insert_page_break_before_paragraph(p)
            continue
        if stripped.startswith("Работы по техническому диагностированию проведены в соответствии с договором"):
            parties = org_name if org_name != MISSING else "__________________________"
            c_no = contract or "____________"
            c_dt = contract_date or "______"
            _set_paragraph_text(
                p,
                f"Работы по техническому диагностированию проведены в соответствии с договором между {parties} от {c_dt} № {c_no}.",
            )
        elif stripped.startswith("Работы по техническому диагностированию проведены в период"):
            pf = period_from or "__.__.____"
            pt = period_to or "__.__.____"
            loc = location if location != MISSING else "____________________"
            _set_paragraph_text(
                p,
                f"Работы по техническому диагностированию проведены в период с {pf} по {pt}, "
                f"на объекте {loc}.",
            )
        elif "По результатам работ произведена оценка работоспособности" in text:
            _set_paragraph_text(
                p,
                f"По результатам работ произведена оценка работоспособности {calc_txt}. (Приложение № 8)",
            )
        elif stripped.startswith("Фактическое значение параметров, определяющих состояние эксплуатации"):
            _set_paragraph_text(
                p,
                f"Фактическое значение параметров, определяющих состояние эксплуатации сосуда "
                f"работающего под давлением – {device}, зав.№ {serial}, рег.№ {reg_no}, "
                f"инв.№ {inv_no}, удовлетворяют требованиям нормативных документов.",
            )
        elif stripped.startswith("Техническое состояние объекта диагностирования"):
            _set_paragraph_text(
                p,
                f"Техническое состояние объекта диагностирования: {tech_state} ({conclusion}).",
            )


def _fill_protocol_header(table: Table, ctx: Dict[str, Any]) -> None:
    """Шапка протокола 8×3: исполнитель / заказчик / оборудование."""
    if len(table.rows) < 7:
        return
    _set(table, 0, 0, ctx.get("contractor_name") or "")
    _set(table, 0, 2, ctx.get("org_name") or "")
    _set(table, 2, 0, ctx.get("contractor_address") or "")
    # Место нахождения оборудования — отдельная графа (не путать с заказчиком)
    _set(table, 2, 2, ctx.get("location") or MISSING)
    _set(table, 4, 0, ctx.get("lab_name") or "")
    _set(table, 4, 2, ctx.get("device_name") or "")
    _set(table, 6, 0, ctx.get("lab_cert") or "")
    ids = f"Зав.№ {ctx['serial']}, рег.№ {ctx['reg_no']}, инв.№ {ctx['inv_no']}"
    _set(table, 6, 2, ids, nowrap=True)


def _doc_ident_and_pages(present: Any, info: Dict[str, Any]) -> Tuple[str, str]:
    """Идентификатор и объём документа; при отсутствии — «Не предоставлено»."""
    doc_number = str(info.get("number") or info.get("doc_number") or "").strip()
    doc_date = _fmt_date_ru(info.get("date") or info.get("doc_date")) or ""
    pages = str(info.get("pages") or info.get("volume") or "").strip()
    ident = doc_number
    if doc_date:
        ident = f"{ident} от {doc_date}".strip() if ident else f"от {doc_date}"
    provided = present is True or (present is not False and bool(ident))
    if present is False or not provided:
        # Если документ «Не предоставлено» — соседняя колонка должна быть
        # тире, а не дублировать тот же текст.
        return NOT_PROVIDED, MISSING
    return ident or NOT_PROVIDED, pages or MISSING


def _fill_documents_table(table: Table, ctx: Dict[str, Any]) -> None:
    docs_dict = ctx["docs_dict"]
    docs_info = ctx["docs_info"]
    keys = set(str(k) for k in docs_dict.keys()) | set(str(k) for k in docs_info.keys())
    keys |= set(TO_DOCUMENT_NAMES.keys())
    ordered = sorted(keys, key=lambda x: int(x) if x.isdigit() else 999)

    # Строка 0 — заголовок; данные с 1
    needed = len(ordered) + 1
    _ensure_rows(table, needed)

    for i, num in enumerate(ordered):
        if not str(num).isdigit():
            continue
        row = i + 1
        name = TO_DOCUMENT_NAMES.get(str(num), f"Документ {num}")
        info = docs_info.get(str(num)) or docs_info.get(num) or {}
        if not isinstance(info, dict):
            info = {}
        present = docs_dict.get(str(num), docs_dict.get(num))
        ident, pages = _doc_ident_and_pages(present, info)
        _set(table, row, 0, f"{num}.")
        _set(table, row, 1, name)
        _set(table, row, 2, ident)
        if len(table.rows[row].cells) > 3:
            _set(table, row, 3, pages)


def _fill_general_data(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    rows = [
        g("vessel_name", "equipment_device_name", default=ctx["device_name"]),
        g("designation", "conditional_designation", default=MISSING),
        g("manufacturer", default=MISSING),
        g("manufacture_year", "year_of_manufacture", default=MISSING),
        g("commissioning_year", default=MISSING),
        g("working_pressure", default=MISSING),
        g("diameter", "inner_diameter", default=MISSING),
        g("working_temperature", default=MISSING),
        g("working_medium", "medium", default=MISSING),
        g("shell_material", "material", default=MISSING),
        g("volume", "capacity", default=MISSING),
        g("connection_scheme", default=MISSING),
        g("climatic_version", default=MISSING),
    ]
    for i, val in enumerate(rows):
        if i < len(table.rows):
            _set(table, i, 1, val)


def _fill_elements_table(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    elements = g("vessel_elements", "elements", default=[])
    if not isinstance(elements, list):
        elements = []
    # Строки 0–1 заголовки; данные с 2
    data_start = 2
    if not elements:
        # Заполнить корпус из паспортных полей
        defaults = [
            ("Корпус", g("shell_qty", default="1"), g("diameter", default=""), g("shell_length", "height", default=""),
             g("wall_thickness", "thickness", default=""), g("calc_thickness", default=""),
             g("shell_material", "material", default=""), g("material_gost", default=""),
             g("weld_type", default=""), g("electrodes", default=""), g("ndt_method", default="")),
        ]
        for i, row_vals in enumerate(defaults):
            r = data_start + i
            if r >= len(table.rows):
                break
            for c, v in enumerate(row_vals):
                if c < len(table.rows[r].cells):
                    _set(table, r, c, v, nowrap=(c in (2, 3, 4, 5, 6, 7)))
        return

    needed = data_start + len(elements)
    _ensure_rows(table, needed)
    for i, el in enumerate(elements):
        if not isinstance(el, dict):
            continue
        r = data_start + i
        vals = [
            el.get("name") or el.get("element_name") or "",
            el.get("quantity") or el.get("qty") or "1",
            el.get("diameter_mm")
            or el.get("inner_diameter")
            or el.get("diameter")
            or "",
            el.get("length_mm") or el.get("length") or el.get("height") or "",
            el.get("wall_thickness_mm")
            or el.get("nominal_thickness")
            or el.get("thickness")
            or el.get("wall_thickness")
            or "",
            # Расчётная толщина до прибавки на коррозию
            el.get("calc_thickness")
            or el.get("calculated_thickness")
            or el.get("design_thickness")
            or "",
            el.get("steel_grade") or el.get("material") or "",
            el.get("gost") or el.get("material_gost") or "",
            el.get("weld_type") or el.get("weld_data") or "",
            el.get("electrodes") or "",
            el.get("ndt_method") or "",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                # Размеры и марка стали — без «ломания» по символу в узких колонках
                _set(table, r, c, v, nowrap=(c in (2, 3, 4, 5, 6, 7)))
    # Очистить оставшиеся строки-заготовки шаблона (напр. «Нижнее днище»)
    for r in range(data_start + len(elements), len(table.rows)):
        for c in range(len(table.rows[r].cells)):
            _set(table, r, c, "")


def _fill_characteristics(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    # Колонки: наименование | подпоказатель | проектные | фактические | примечание
    # Строки: 1 раб.давл, 2 расч.давл, 3 пневмо, 4 гидро,
    # 5 расч.t стенки, 6 t рабочей среды, 7 min t стенки, 8 состав среды,
    # 9 класс опасности, 10 взрывоопасность, 11 пожароопасность, …
    design_temp = g("design_temperature", default="")
    # Температура рабочей среды — отдельное поле; не путать с t стенки
    medium_temp = g(
        "working_medium_temperature",
        "medium_temperature",
        "working_temperature",
        default="",
    )
    wall_work_temp = g("wall_working_temperature", "working_temperature_wall", default="")
    mapping = {
        1: (g("working_pressure_design", "working_pressure", default=""), g("working_pressure", default="")),
        2: (g("design_pressure", default=""), g("design_pressure_fact", "design_pressure", default="")),
        3: (g("test_pressure_pneumo", default=""), g("test_pressure_pneumo_fact", default="")),
        4: (g("test_pressure", "test_pressure_hydro", default=""), g("test_pressure_fact", "test_pressure", default="")),
        5: (design_temp, g("design_temperature_fact", "design_temperature", default=design_temp)),
        6: (medium_temp, g("working_medium_temperature_fact", "working_medium_temperature", "medium_temperature", default=medium_temp)),
        7: (
            g("min_wall_temp", default=wall_work_temp),
            g("min_wall_temp_fact", "min_wall_temp", default=wall_work_temp),
        ),
        8: (g("working_medium", "medium", default=""), g("working_medium_fact", "working_medium", "medium", default="")),
        9: (
            g("hazard_class", "medium_hazard_class", default=""),
            g("hazard_class_fact", "hazard_class", "medium_hazard_class", default=""),
        ),
        10: (
            g("explosion_hazard", "explosion_category", default=""),
            g("explosion_hazard_fact", "explosion_hazard", "explosion_category", default=""),
        ),
        11: (
            g("fire_hazard", "fire_category", default=""),
            g("fire_hazard_fact", "fire_hazard", "fire_category", default=""),
        ),
        12: (g("volume", "capacity", default=""), g("volume_fact", "volume", "capacity", default="")),
        13: (g("empty_mass", "mass", default=""), g("empty_mass_fact", "empty_mass", "mass", default="")),
        14: (g("corrosion_allowance", default=""), g("corrosion_allowance_fact", "corrosion_allowance", default="")),
        15: (g("load_cycles", default=""), g("load_cycles_fact", "load_cycles", default="")),
        16: (g("service_life", default=""), g("service_life_fact", "service_life", default="")),
    }
    for row, (proj, fact) in mapping.items():
        if row < len(table.rows):
            cols = len(table.rows[row].cells)
            if cols >= 4:
                _set(table, row, 2, proj if proj not in (None, MISSING) else "", nowrap=True)
                _set(table, row, 3, fact if fact not in (None, MISSING) else "", nowrap=True)


def _fill_materials(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    materials = g("materials", "element_materials", default=[])
    if not isinstance(materials, list) or not materials:
        materials = []
        elements = g("vessel_elements", "elements", default=[])
        if isinstance(elements, list):
            for el in elements:
                if not isinstance(el, dict):
                    continue
                mat = el.get("material") or el.get("steel_grade")
                if not mat:
                    continue
                materials.append(
                    {
                        "element": el.get("name") or el.get("element_name") or "",
                        "grade": mat,
                        "gost": el.get("gost") or el.get("material_gost") or "",
                        "yield_strength": el.get("yield_strength") or "",
                        "tensile_strength": el.get("tensile_strength") or "",
                        "elongation": el.get("elongation") or "",
                        "reduction": el.get("reduction") or "",
                        "impact": el.get("impact") or "",
                        "temperature": el.get("temperature") or el.get("test_temperature") or "",
                        "specimen_type": el.get("specimen_type") or "",
                    }
                )
    if isinstance(materials, list) and materials:
        start = 2
        _ensure_rows(table, start + len(materials))
        for i, m in enumerate(materials):
            if not isinstance(m, dict):
                continue
            r = start + i
            vals = [
                m.get("element") or m.get("name") or "",
                m.get("grade") or m.get("material") or "",
                m.get("gost") or "",
                m.get("yield_strength") or "",
                m.get("tensile_strength") or "",
                m.get("elongation") or "",
                m.get("reduction") or "",
                m.get("impact") or "",
                m.get("temperature") or "",
                m.get("specimen_type") or "",
            ]
            for c, v in enumerate(vals):
                if c < len(table.rows[r].cells):
                    _set(table, r, c, v)
        for r in range(start + len(materials), len(table.rows)):
            for c in range(len(table.rows[r].cells)):
                _set(table, r, c, "")
        return
    # Минимум — корпус
    if len(table.rows) > 2:
        _set(table, 2, 0, "Корпус")
        _set(table, 2, 1, g("shell_material", "material", default=""))
        _set(table, 2, 2, g("material_gost", default=""))
        for r in range(3, len(table.rows)):
            for c in range(len(table.rows[r].cells)):
                _set(table, r, c, "")


def _fill_heat_treatment(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    records = g("heat_treatment_records", "heat_treatment", default=[])
    if not isinstance(records, list) or not records:
        return
    start = 2
    _ensure_rows(table, start + len(records))
    for i, rec in enumerate(records):
        if not isinstance(rec, dict):
            continue
        r = start + i
        vals = [
            rec.get("element") or rec.get("name") or "",
            rec.get("type") or rec.get("kind") or "",
            rec.get("temperature") or "",
            rec.get("duration") or "",
            rec.get("cooling") or "",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def _fill_strength_tests(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    records = g("hydraulic_test_history", "strength_tests", default=[])
    if not isinstance(records, list):
        return
    # Отбросить полностью пустые записи
    records = [
        rec
        for rec in records
        if isinstance(rec, dict)
        and any(
            str(rec.get(k) or "").strip()
            for k in ("date", "type", "test_type", "kind", "pressure", "medium", "temperature")
        )
    ]
    if not records:
        _strip_empty_rows(table, 1)
        return
    start = 1
    _ensure_rows(table, start + len(records))
    for i, rec in enumerate(records):
        r = start + i
        vals = [
            _fmt_date_ru(rec.get("date")) or rec.get("date") or "",
            rec.get("type") or rec.get("test_type") or rec.get("kind") or "гидравлическое",
            rec.get("pressure") or "",
            rec.get("medium") or rec.get("test_medium") or "",
            rec.get("temperature") or rec.get("medium_temperature") or "",
            rec.get("note") or rec.get("remark") or "",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v, nowrap=(c in (0, 2, 4)))
    # Очистить лишние строки-заготовки шаблона
    for r in range(start + len(records), len(table.rows)):
        for c in range(len(table.rows[r].cells)):
            _set(table, r, c, "")


def _fill_previous_inspections(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    records = g("previous_inspections", "ndt_control_history", default=[])
    if not isinstance(records, list):
        records = []
    records = [
        rec
        for rec in records
        if isinstance(rec, dict)
        and any(
            str(rec.get(k) or "").strip()
            for k in (
                "date",
                "type",
                "kind",
                "control_type",
                "scope",
                "volume",
                "result",
                "results",
                "report_number",
                "organization",
                "executor",
            )
        )
    ]
    # Если есть только legacy-строка — разложить в одну запись
    if not records:
        legacy = g("previous_inspection_result", default="")
        if legacy and legacy != MISSING:
            records = [{"type": "Техническое диагностирование", "result": legacy}]
    start = 1
    if not records:
        for r in range(start, len(table.rows)):
            for c in range(len(table.rows[r].cells)):
                _set(table, r, c, "")
        return
    _ensure_rows(table, start + len(records))
    for i, rec in enumerate(records):
        r = start + i
        vals = [
            _fmt_date_ru(rec.get("date")) or rec.get("date") or "",
            rec.get("type") or rec.get("kind") or rec.get("control_type") or "",
            rec.get("scope") or rec.get("volume") or "",
            rec.get("result") or rec.get("results") or rec.get("report_number") or "",
            rec.get("organization") or rec.get("executor") or "",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v, nowrap=(c == 0))
    for r in range(start + len(records), len(table.rows)):
        for c in range(len(table.rows[r].cells)):
            _set(table, r, c, "")

def _fill_additional_data(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    mapping = {
        1: g("vessel_installed", "installation_info", default=""),
        2: g("load_cycles", default=""),
        3: g("supervisory_remarks", default=""),
        4: g("accidents_info", "incidents_info", default=""),
        5: g("repair_info", default=""),
    }
    for row, val in mapping.items():
        if row < len(table.rows) and len(table.rows[row].cells) > 2:
            # Явно показываем «—», если поле не заполнено техником в мобильном
            # приложении, вместо пустой ячейки.
            _set(table, row, 2, val if val not in (None, "") else MISSING)


# Индексы таблиц-подписей протоколов (doc.tables) → коды методов НК, которым
# соответствует данный протокол/приложение. Нужно, чтобы под протоколом ВИК
# расписывался специалист по ВИК, а не случайный человек из общего списка.
SIGNATURE_METHOD_KEYS: Dict[int, Tuple[str, ...]] = {
    18: ("ВИК", "VIK", "ПВК", "PVK"),
    22: ("УЗТ", "UZT"),
    27: ("ТВЕРД", "TVI", "HARD"),
    32: ("УЗК", "UZK"),
    37: ("МПК", "MPK"),
}


def _specialists_for_methods(
    ctx: Dict[str, Any], method_keys: Optional[Tuple[str, ...]]
) -> List[Dict[str, str]]:
    specs = ctx.get("specialists") or []
    if not method_keys:
        return specs
    matched = [
        s
        for s in specs
        if any(k.upper() in str(s.get("role") or "").upper() for k in method_keys)
    ]
    # Если по конкретному методу никто не привязан явно — не подставляем
    # посторонних специалистов, но если ролей вообще не было указано (одна
    # запись без разбивки по методам) — используем общий список.
    if matched:
        return matched
    if all(not str(s.get("role") or "").strip() for s in specs):
        return specs
    return []


def _fill_signatures(
    table: Table, ctx: Dict[str, Any], method_keys: Optional[Tuple[str, ...]] = None
) -> None:
    specs = _specialists_for_methods(ctx, method_keys)
    # Строки 1,2 — контроль; 4 — заключение
    slots = [1, 2, 4]
    for i, row in enumerate(slots):
        if row >= len(table.rows):
            continue
        if specs:
            # Если специалистов меньше, чем строк подписи (частый случай —
            # один специалист выполнял весь контроль), используем их по кругу
            # вместо того, чтобы оставлять строку с посторонними ФИО из шаблона.
            s = specs[i % len(specs)]
            name = s.get("name") or ""
            cert = s.get("cert") or ""
            label = f"Специалист {name}"
            if cert:
                label += f"  квал. уд. № {cert}"
            else:
                label += "  квал. уд. № ________________"
            _set(table, row, 0, label)
            if len(table.rows[row].cells) > 1:
                _set(table, row, 1, name)
            if len(table.rows[row].cells) > 2 and name:
                _set(table, row, 2, "Ф.И.О.")
        else:
            # Данных нет — не оставляем в отчёте посторонние ФИО из шаблона.
            _set(table, row, 0, "Специалист  квал. уд. № ________________")
            if len(table.rows[row].cells) > 1:
                _set(table, row, 1, "")
            if len(table.rows[row].cells) > 2:
                _set(table, row, 2, "")


def _fill_operational_diagnostics(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    op = g("operational_diagnostics", "functional_diagnostics", default={})
    if not isinstance(op, dict):
        op = {}
    # Строки 1–5: оценка / примечания в кол. 2 и 3
    defaults = {
        1: (op.get("params_ok") or "Соответствуют", op.get("params_note") or ""),
        2: (op.get("vibration") or "Не выявлена", op.get("vibration_note") or ""),
        3: (op.get("foundation") or "Не выявлена", op.get("foundation_note") or ""),
        4: (op.get("supports") or "Работоспособное", op.get("supports_note") or g("support_state", default="")),
        5: (op.get("kip") or "Работоспособное", op.get("kip_note") or ""),
    }
    for row, (eval_, note) in defaults.items():
        if row < len(table.rows):
            if len(table.rows[row].cells) > 2:
                _set(table, row, 2, eval_)
            if len(table.rows[row].cells) > 3:
                _set(table, row, 3, note)


def _fill_instrument_table(
    table: Table,
    ctx: Dict[str, Any],
    method_keys: Tuple[str, ...],
    defaults: Optional[List[Tuple[str, str]]] = None,
) -> None:
    ve = list(ctx.get("verification_equipment") or [])
    for item in (ctx.get("data") or {}).get("_ndt_instruments") or []:
        if isinstance(item, dict):
            ve.append(item)
    matched: List[Dict[str, Any]] = []
    for eq in ve:
        if not isinstance(eq, dict):
            continue
        et = str(
            eq.get("equipment_type") or eq.get("type") or eq.get("method_code") or ""
        ).upper()
        name = str(eq.get("name") or "")
        blob = f"{et} {name}".upper()
        if any(k.upper() in blob for k in method_keys):
            matched.append(eq)
    if not matched and defaults:
        matched = [{"name": n, "serial_number": s} for n, s in defaults]
    # Очистим строки шаблона и заполним фактическими приборами
    for r in range(1, len(table.rows)):
        for c in range(len(table.rows[r].cells)):
            _set(table, r, c, "")
    for i, eq in enumerate(matched[: max(0, len(table.rows) - 1)]):
        r = i + 1
        if r >= len(table.rows):
            break
        serial = str(eq.get("serial_number") or eq.get("factory_number") or "")
        _set(table, r, 0, f"{i + 1}.")
        if len(table.rows[r].cells) > 1:
            _set(table, r, 1, _instrument_full_name(eq) if eq.get("equipment_type") or eq.get("name") else (eq.get("name") or ""))
        if len(table.rows[r].cells) > 2:
            _set(table, r, 2, serial, nowrap=True)
        if len(table.rows[r].cells) > 3:
            _set(
                table,
                r,
                3,
                eq.get("verification_certificate_number")
                or eq.get("certificate")
                or eq.get("verification_certificate")
                or "",
                nowrap=True,
            )
        if len(table.rows[r].cells) > 4:
            _set(
                table,
                r,
                4,
                _fmt_date_ru(
                    eq.get("next_verification_date")
                    or eq.get("valid_until")
                    or eq.get("verification_until")
                )
                or eq.get("next_verification_date")
                or "",
                nowrap=True,
            )
    _strip_empty_rows(table, 1, ignore_cols=(0,))


def _fill_vik_parameters(table: Table, ctx: Dict[str, Any]) -> None:
    """Таблица «Параметры контроля» ВИК — шероховатость/освещённость по факту,
    вместо статичных примерных значений («Rz 80», «500 Лк») из шаблона."""
    g = ctx["g"]
    roughness = g("vik_roughness", "roughness_rz", default="")
    illumination = g("vik_illumination", "illumination", default="")
    extra_light = g("vik_additional_lighting", default=None)
    if len(table.rows) > 0 and len(table.rows[0].cells) > 1:
        _set(table, 0, 1, roughness if roughness else MISSING)
    if len(table.rows) > 1 and len(table.rows[1].cells) > 1:
        illum_text = f"{illumination} лк" if illumination else MISSING
        if extra_light is True:
            illum_text = f"{illum_text} (с доп. освещением)" if illum_text != MISSING else "с дополнительным освещением"
        elif extra_light is False:
            illum_text = f"{illum_text} (без доп. освещения)" if illum_text != MISSING else MISSING
        _set(table, 1, 1, illum_text)


def _fill_vik_results(table: Table, ctx: Dict[str, Any]) -> None:
    """Таблица результатов ВИК: строки 2/3 — базовые объекты наружного
    осмотра (фундаменты, сварные соединения), строка 4 — доп. объекты
    наружного осмотра, строка 6 — объекты внутреннего осмотра.

    Поддерживает произвольный список объектов контроля
    ``vik_control_objects`` (каждый со своей «зоной» — наружный/внутренний),
    который техник может дополнять в мобильном приложении, а не только
    2 предустановленные категории.
    """
    g = ctx["g"]

    def _row_from(o: Dict[str, Any]) -> Tuple[str, str, str, str]:
        return (
            str(o.get("object") or o.get("location") or o.get("element") or ""),
            str(o.get("scope") or o.get("volume") or "100%"),
            str(o.get("description") or o.get("defects") or o.get("defect") or "Дефектов не обнаружено"),
            str(o.get("assessment") or o.get("quality") or "Годен"),
        )

    # Базовые (всегда присутствующие) категории наружного осмотра
    _set(table, 2, 1, "фундаментов")
    _set(table, 2, 2, "100%")
    _set(table, 2, 3, "Дефектов не обнаружено")
    _set(table, 2, 4, "Годен")
    _set(table, 3, 1, "сварных соединений")
    _set(table, 3, 2, "100%")
    _set(table, 3, 3, "Дефектов не обнаружено")
    _set(table, 3, 4, "Годен")

    # Список объектов контроля ВИК: технику доступно добавление произвольных
    # объектов (не только 2 предустановленные категории) через раздел
    # «Дефекты ВИК» мобильного приложения — каждая запись может нести
    # зону (наружный/внутренний), объём контроля и оценку.
    objects = g("vik_control_objects", "inspection_objects", "visual_defects", "vik_defects", "defects", default=None)
    external_extra: List[Tuple[str, str, str, str]] = []
    internal_extra: List[Tuple[str, str, str, str]] = []

    if isinstance(objects, list) and objects:
        for o in objects:
            if not isinstance(o, dict):
                continue
            zone = str(o.get("zone") or o.get("area") or "external").strip().lower()
            row_vals = _row_from(o)
            if zone.startswith("intern") or "внутр" in zone:
                internal_extra.append(row_vals)
            else:
                external_extra.append(row_vals)

    # Строка 4 (по умолчанию placeholder «….») — доп. объекты наружного осмотра
    ext_row_idx = 4
    if external_extra:
        for c, v in enumerate(external_extra[0], start=1):
            _set(table, ext_row_idx, c, v)
        for extra in external_extra[1:]:
            ext_row_idx = _insert_row_after(table, ext_row_idx, extra)
    else:
        for c in range(len(table.rows[ext_row_idx].cells)):
            _set(table, ext_row_idx, c, "")

    # Строка после «Внутренний осмотр:» — объекты внутреннего осмотра
    int_label_idx = ext_row_idx + 1
    int_row_idx = int_label_idx + 1 if int_label_idx + 1 < len(table.rows) else None
    if int_row_idx is not None:
        if internal_extra:
            for c, v in enumerate(internal_extra[0], start=1):
                _set(table, int_row_idx, c, v)
            for extra in internal_extra[1:]:
                int_row_idx = _insert_row_after(table, int_row_idx, extra)
        else:
            for c in range(len(table.rows[int_row_idx].cells)):
                _set(table, int_row_idx, c, "")

    _strip_empty_rows(table, 2, ignore_cols=(0,))


def _fill_uzt_results(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    points = g("thickness_measurements", "thicknessMeasurements", default=[])
    if not isinstance(points, list) or not points:
        return
    # Группируем по элементу: 3 точки на строку
    by_element: Dict[str, List[Dict[str, Any]]] = {}
    for p in points:
        if not isinstance(p, dict):
            continue
        el = str(
            p.get("location")
            or p.get("element")
            or p.get("zone")
            or p.get("name")
            or "Элемент"
        )
        by_element.setdefault(el, []).append(p)

    rows_needed = 1  # header
    for pts in by_element.values():
        rows_needed += max(1, (len(pts) + 2) // 3)
    _ensure_rows(table, rows_needed)

    # Колонка «элемент» в шаблоне часто объединена — пишем список один раз
    element_label = " / ".join(by_element.keys())
    written_element_cells: set = set()
    row = 1
    for el_name, pts in by_element.items():
        for chunk_start in range(0, len(pts), 3):
            chunk = pts[chunk_start : chunk_start + 3]
            if row >= len(table.rows):
                _ensure_rows(table, row + 1)
            cell0 = table.rows[row].cells[0]
            cid = id(cell0._tc)
            if cid not in written_element_cells:
                _set_cell(
                    cell0,
                    el_name if len(by_element) == 1 else element_label,
                )
                written_element_cells.add(cid)
            for j, p in enumerate(chunk):
                num = (
                    p.get("section_number")
                    or p.get("point_number")
                    or p.get("number")
                    or p.get("point")
                    or (chunk_start + j + 1)
                )
                thick = (
                    p.get("thickness")
                    or p.get("value")
                    or p.get("measured_thickness")
                    or ""
                )
                point_label = str(num)
                base = 1 + j * 2
                if base < len(table.rows[row].cells):
                    _set(table, row, base, point_label)
                if base + 1 < len(table.rows[row].cells):
                    _set(table, row, base + 1, thick)
            row += 1


def _fill_hardness_matrix(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    tests = g("hardness_tests", "hardnessTests", default=[])
    if not isinstance(tests, list) or not tests:
        return
    # Строки 3.. — Т1..Т6; колонки 2..6 — значения 1..5
    for i, t in enumerate(tests[:6]):
        if not isinstance(t, dict):
            continue
        r = 3 + i
        if r >= len(table.rows):
            break
        zone = (
            t.get("weld_number")
            or t.get("location")
            or t.get("zone")
            or t.get("section")
            or t.get("element")
            or f"Т{i + 1}"
        )
        _set(table, r, 1, zone)
        vals = [
            t.get("hardness_base_t1") or t.get("hardness_base") or "",
            t.get("hardness_haz_t2") or t.get("hardness_haz") or "",
            t.get("hardness_weld") or "",
            t.get("hardness_haz_t4") or t.get("hardness_haz") or "",
            t.get("hardness_base_t5") or t.get("hardness_base") or "",
        ]
        for c, v in enumerate(vals):
            if 2 + c < len(table.rows[r].cells):
                _set(table, r, 2 + c, v)


def _fill_hardness_list(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    tests = g("hardness_tests", "hardnessTests", default=[])
    if not isinstance(tests, list) or not tests:
        return
    start = 1
    _ensure_rows(table, start + len(tests))
    for i, t in enumerate(tests):
        if not isinstance(t, dict):
            continue
        r = start + i
        _set(
            table,
            r,
            0,
            t.get("weld_number")
            or t.get("location")
            or t.get("zone")
            or t.get("section")
            or "",
        )
        _set(
            table,
            r,
            1,
            t.get("area_number") or t.get("point_number") or t.get("point") or (i + 1),
        )
        _set(
            table,
            r,
            2,
            t.get("hardness_base")
            or t.get("hardness_weld")
            or t.get("value")
            or "",
        )
        _set(
            table,
            r,
            3,
            t.get("allowed_hardness_base")
            or t.get("allowed_hardness_weld")
            or t.get("allowed")
            or "",
        )


def _fill_uzk_results(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    welds = g("weld_inspections", "uzk_results", "weld_defects", default=[])
    if not isinstance(welds, list) or not welds:
        if len(table.rows) > 1:
            _set(table, 1, 0, "—")
            if len(table.rows[1].cells) > 7:
                _set(table, 1, 7, "Дефектов не обнаружено")
        return
    start = 1
    _ensure_rows(table, start + len(welds))
    for i, w in enumerate(welds):
        if not isinstance(w, dict):
            continue
        r = start + i
        # Мобильное приложение (карта обследования, раздел «УЗК/ПВК») собирает
        # свободный текст дефекта под ключами uzk_defect/defect_description и
        # место контроля под location_on_control_map — сопоставляем их со
        # структурными колонками шаблона (форма/характер и место).
        defect_text = (
            w.get("defect_description")
            or w.get("uzk_defect")
            or w.get("pvk_defect")
            or ""
        )
        location = w.get("location") or w.get("location_on_control_map") or ""
        form_char = w.get("form") or w.get("character") or defect_text
        conclusion = (
            w.get("conclusion")
            or w.get("assessment")
            or (defect_text if defect_text else "Дефектов не обнаружено")
        )
        vals = [
            w.get("joint") or w.get("weld_number") or w.get("seam") or "",
            w.get("defect_number") or (i + 1 if defect_text else ""),
            w.get("area") or w.get("equivalent_area") or "",
            w.get("depth") or "",
            w.get("length") or "",
            form_char,
            location,
            conclusion,
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def _fill_mpk_results(table: Table, ctx: Dict[str, Any]) -> None:
    g = ctx["g"]
    items = g("mpk_results", "magnetic_results", default=[])
    if not isinstance(items, list) or not items:
        if len(table.rows) > 1:
            _set(table, 1, 0, "Сварные соединения")
            _set(table, 1, 2, "100%")
            _set(table, 1, 3, "Дефектов не обнаружено")
            _set(table, 1, 4, "Годен")
        return
    start = 1
    _ensure_rows(table, start + len(items))
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        r = start + i
        vals = [
            item.get("object") or item.get("element") or "",
            item.get("zone") or "",
            item.get("scope") or item.get("volume") or "",
            item.get("defects") or item.get("description") or "",
            item.get("assessment") or item.get("quality") or "",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def _fill_paragraph_blanks(doc: Document, ctx: Dict[str, Any]) -> None:
    """Подставить номера протоколов, даты и выводы в абзацы с подчёркиваниями."""
    date_ru = ctx["date_ru"]
    serial = ctx["serial"]
    reg_no = ctx["reg_no"]
    inv_no = ctx["inv_no"]
    device = ctx["device_name"]
    conclusion = ctx.get("conclusion_suitable") or "соответствует"
    doc_concl = ctx.get("conclusion_doc") or "в полном объёме"
    op_ok = ctx.get("operational_ok") or "соответствует"
    g = ctx["g"]
    protocol_no = str(g("protocol_number", "report_number", default="") or "")
    tech_card = str(g("tech_card_number", "technological_card", default="") or "")

    # Важно: основной отчёт в SDT — doc.paragraphs его не видит
    for p in _iter_all_paragraphs(doc):
        text = p.text
        if not text:
            continue
        new_text = text
        stripped = text.strip()

        # «№ _____ от _____ г.» — дату подставляем всегда; номер — если есть
        if stripped.startswith("№") and "от" in stripped and "г." in stripped:
            no_part = protocol_no if protocol_no else "_________"
            new_text = f"№ {no_part} от {date_ru} г."
        elif "При анализе технической документации установлено" in text:
            new_text = _replace_underscores(text, [doc_concl or "соответствие НТД"])
        elif "ВЫВОД:" in text or "Представленная техническая документация" in text:
            new_text = (
                f"ВЫВОД: Представленная техническая документация на сосуд, "
                f"работающий под давлением – {device} зав. № {serial}, рег. № {reg_no}, "
                f"инв. № {inv_no} ведется в соответствии с требованиями действующей "
                f"нормативно-технической документации ({conclusion})."
            )
        elif "функциональной (оперативной) диагностики установлено" in text:
            new_text = (
                f"В результате функциональной (оперативной) диагностики установлено, "
                f"что сосуд {op_ok} и соответствует паспортным характеристикам. "
                f"Сосуд соответствует требованиям действующей НТД."
            )
        elif "Технологическая карта №" in text:
            card_val = tech_card if tech_card else "—"
            if "_" in text:
                new_text = _replace_underscores(text, [card_val])
            else:
                new_text = re.sub(
                    r"(Технологическая карта №)\s*$",
                    rf"\1 {card_val}",
                    text,
                )
        elif "недопустимых дефектов не обнаружено" in text and (
            "_" in text or "документацииСТО" in text.replace(" ", "")
        ):
            # Если техник выбрал в мобильном приложении конкретную
            # формулировку заключения по ВИК — используем её, иначе —
            # стандартный текст по умолчанию.
            vik_conclusion = str(g("vik_conclusion_text", default="") or "").strip()
            if vik_conclusion:
                new_text = vik_conclusion
            else:
                ntd = str(g("vik_ntd", default="СТО 9701105632-003-2021") or "")
                new_text = (
                    "По результатам визуального и измерительного контроля основного "
                    "металла и сварных соединений сосуда, недопустимых дефектов не обнаружено, "
                    f"что удовлетворяет требованиям нормативно-технической документации {ntd}."
                )
        else:
            continue

        if new_text != text:
            _set_paragraph_text(p, new_text)


def _set_paragraph_text(paragraph: Paragraph, text: str) -> None:
    if paragraph.runs:
        paragraph.runs[0].text = text
        for run in paragraph.runs[1:]:
            run.text = ""
    else:
        paragraph.text = text


def _fill_appendix_8_calculation(doc: Document, ctx: Dict[str, Any]) -> None:
    """Приложение № 8 — расчёт на прочность из calculation_data."""
    g = ctx["g"]
    calc = g("calculation_data", "calculationData", default=None)
    if calc in (None, MISSING, ""):
        calc = {}
    if not isinstance(calc, dict):
        calc = {"description": str(calc)}

    anchor = find_paragraph_containing(doc, "ПРИЛОЖЕНИЕ № 8")
    if anchor is None:
        anchor = find_paragraph_containing(doc, "Расчет на прочность")
    if anchor is None:
        return

    lines: List[str] = []
    residual = calc.get("residual_life_years") or calc.get("residual_life") or g(
        "residual_life_text", "residual_life_years", default=""
    )
    if residual and residual != MISSING:
        lines.append(f"Остаточный ресурс: {residual} лет.")
    description = calc.get("description") or calc.get("text") or calc.get("summary") or ""
    if description:
        lines.append(str(description))
    for key in (
        "allowable_stress",
        "design_pressure",
        "calc_thickness",
        "min_thickness",
        "corrosion_rate",
        "method",
        "conclusion",
    ):
        val = calc.get(key)
        if val not in (None, ""):
            labels = {
                "allowable_stress": "Допускаемое напряжение",
                "design_pressure": "Расчётное давление",
                "calc_thickness": "Расчётная толщина",
                "min_thickness": "Минимальная толщина",
                "corrosion_rate": "Скорость коррозии",
                "method": "Методика расчёта",
                "conclusion": "Заключение",
            }
            lines.append(f"{labels.get(key, key)}: {val}")

    # Таблица результатов, если есть rows
    rows = calc.get("rows") or calc.get("results") or []
    last = anchor
    if not lines and not rows:
        last = insert_paragraph_after(
            last,
            "Расчёт на прочность выполнен по результатам УЗТ. "
            "Значения толщин стенок удовлетворяют требованиям прочности.",
        )
        return

    for line in lines:
        last = insert_paragraph_after(last, line)

    if isinstance(rows, list) and rows:
        last = insert_paragraph_after(last, "Результаты расчёта:")
        for row in rows:
            if isinstance(row, dict):
                parts = [f"{k}: {v}" for k, v in row.items() if v not in (None, "")]
                last = insert_paragraph_after(last, "; ".join(parts))
            else:
                last = insert_paragraph_after(last, str(row))


def _fill_appendix_9_hydraulic_act(doc: Document, ctx: Dict[str, Any]) -> None:
    """Приложение № 9 — копия акта гидравлического испытания (скан)."""
    data = ctx.get("data") or {}
    attachments = ctx.get("attachments") or {}
    find_image = ctx.get("find_image")
    paths = collect_hydraulic_act_paths(data, attachments)

    # Fallback: документ №9 журнала / или текст из истории испытаний
    if not paths:
        for key in ("9", "15", "17"):
            if key in attachments:
                paths.append(attachments[key])

    anchor = find_paragraph_containing(doc, "ПРИЛОЖЕНИЕ № 9")
    if anchor is None:
        anchor = find_paragraph_containing(doc, "гидравлического испытания")
    if anchor is None:
        return

    last = anchor
    inserted = 0
    for path in paths:
        resolved = resolve_image_path(path, find_image)
        if not resolved:
            continue
        if is_image_file(resolved):
            pic = add_picture_after_paragraph(
                last,
                resolved,
                width_inches=5.5,
                caption="Копия акта гидравлического испытания",
            )
            if pic is not None:
                last = pic
                inserted += 1
        else:
            last = insert_paragraph_after(
                last,
                f"Приложенный документ: {Path(resolved).name}",
            )
            inserted += 1

    if inserted == 0:
        g = ctx["g"]
        hist = g("hydraulic_test_history", "strength_tests", default=[])
        if isinstance(hist, list) and hist:
            last_rec = hist[-1] if isinstance(hist[-1], dict) else {}
            date = _fmt_date_ru(last_rec.get("date")) or last_rec.get("date") or "—"
            pressure = last_rec.get("pressure") or g("test_pressure", default="—")
            insert_paragraph_after(
                last,
                f"Акт гидравлического испытания от {date}, пробное давление {pressure}. "
                f"Скан акта не приложен к обследованию.",
            )
        else:
            insert_paragraph_after(
                last,
                "Скан акта гидравлического испытания не приложен к материалам обследования.",
            )


def _insert_schemes_and_photos(doc: Document, ctx: Dict[str, Any]) -> None:
    """Вставить схемы контроля и фото измерений в соответствующие разделы."""
    data = ctx.get("data") or {}
    attachments = ctx.get("attachments") or {}
    find_image = ctx.get("find_image")

    schemes = collect_scheme_paths(data, attachments)
    photos = collect_photo_paths(data, attachments)

    # Схемы — после заголовков «Схема контроля»
    n_schemes = insert_media_block(
        doc,
        "Схема контроля",
        schemes,
        find_image=find_image,
        width_inches=5.4,
        max_items=8,
    )
    logger.info("Вставлено схем: %s", n_schemes)

    # Фото УЗТ — после результатов УЗТ / таблицы толщин
    uzt_photos = [p for p in photos if "УЗТ" in (p.get("label") or "")]
    other_photos = [p for p in photos if p not in uzt_photos]

    n_uzt = insert_media_block(
        doc,
        "Результаты контроля",
        uzt_photos,
        find_image=find_image,
        width_inches=4.5,
        max_items=15,
    )
    # Фото дефектов ВИК
    vik_photos = [p for p in other_photos if "дефект" in (p.get("label") or "").lower() or "ВИК" in (p.get("label") or "")]
    n_vik = insert_media_block(
        doc,
        "Результаты визуального и измерительного контроля",
        vik_photos,
        find_image=find_image,
        width_inches=4.5,
        max_items=10,
    )
    # Остальные фото объекта — в конец перед прил.10 или после прил.9
    rest = [p for p in other_photos if p not in vik_photos]
    if rest:
        n_rest = insert_media_block(
            doc,
            "ПРИЛОЖЕНИЕ № 9",
            rest,
            find_image=find_image,
            width_inches=4.5,
            max_items=10,
        )
    else:
        n_rest = 0
    logger.info("Вставлено фото: УЗТ=%s ВИК=%s прочие=%s", n_uzt, n_vik, n_rest)
