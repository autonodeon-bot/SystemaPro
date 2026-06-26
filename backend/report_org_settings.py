"""
Справочные данные для формирования отчётов ТО/ЭПБ (заказчик, организация ТД, основания, НД, шапки приложений).
Хранятся в JSON — редактируются администратором/оператором через API.
"""
from __future__ import annotations

import json
import os
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Optional

_SETTINGS_CANDIDATES = [
    Path(os.environ.get("REPORT_ORG_SETTINGS_PATH", "/app/reports/report_org_settings.json")),
    Path(__file__).resolve().parent / "data" / "report_org_settings.json",
]

DEFAULT_NORMATIVE_DOCUMENTS: List[str] = [
    (
        "Федеральный закон от 21.07.1997 № 116-ФЗ «О промышленной безопасности опасных "
        "производственных объектов»;"
    ),
    (
        "Федеральные нормы и правила в области промышленной безопасности "
        "«Правила промышленной безопасности при использовании оборудования, "
        "работающего под избыточным давлением», утверждённые приказом "
        "Ростехнадзора от 15.12.2020 № 536;"
    ),
    (
        "Федеральные нормы и правила «Правила безопасности в нефтяной и газовой "
        "промышленности», утверждённые приказом Ростехнадзора от 15.12.2020 № 534;"
    ),
    "ГОСТ 14249-89 «Сосуды и аппараты. Нормы и методы расчёта на прочность»;",
    "СО 153-34.17.439-2003 «Инструкция по ультразвуковому контролю»;",
    "ГОСТ Р 55614-2013 «Контроль неразрушающий. Соединения сварные. Методы ультразвуковые»;",
]

DEFAULT_REPORT_ORG_SETTINGS: Dict[str, Any] = {
    "work_basis": (
        "Работы по техническому диагностированию проведены на основании договора "
        "с эксплуатирующей организацией и в соответствии с требованиями "
        "нормативно-технической документации."
    ),
    "normative_documents": DEFAULT_NORMATIVE_DOCUMENTS,
    "report_city": "г. Урай",
    "epb_registry_date": "",
    "customer": {
        "legal_name": "",
        "legal_form": "",
        "address": "",
        "phone": "",
        "director": "",
        "department": "",
        "department_address": "",
        "department_phone": "",
        "department_head": "",
        "inn": "",
    },
    "contractor": {
        "name": "Общество с ограниченной ответственностью «ЮТАР»",
        "short_name": "ООО «ЮТАР»",
        "legal_form": "Общество с ограниченной ответственностью",
        "address": (
            "628285, Ханты-Мансийский автономный округ – Югра, г. Урай, "
            "улица Ивана Шестакова, строение 46Б"
        ),
        "license": (
            "Регистрационный номер Л043-00109-72/00514886 на осуществление "
            "деятельности по проведению экспертизы промышленной безопасности"
        ),
        "certificate": (
            "№ АЦЛНК-5-00083 об аттестации лаборатории неразрушающих методов "
            "контроля ООО «ЮТАР»"
        ),
        "director_title": "Генеральный директор",
        "director_name": "",
        "phone": "",
        "email": "",
    },
    "appendix_protocol_header": {
        "customer_label": "Заказчик:",
        "object_label": "Объект контроля:",
        "location_label": "Место проведения контроля:",
        "date_label": "Дата проведения контроля:",
        "ntd_label": "НТД, по которой выполнен контроль:",
    },
    "conclusion_templates": {
        "COMPLIANT": (
            "На основании результатов выполненного комплекса работ по техническому "
            "диагностированию оборудование соответствует требованиям нормативно-технической "
            "документации и пригодно к дальнейшей эксплуатации."
        ),
        "NON_COMPLIANT": (
            "На основании результатов выполненного комплекса работ по техническому "
            "диагностированию оборудование не соответствует требованиям нормативно-технической "
            "документации. Дальнейшая эксплуатация не допускается до устранения выявленных недостатков."
        ),
        "PARTIALLY_COMPLIANT": (
            "На основании результатов выполненного комплекса работ по техническому "
            "диагностированию оборудование ограниченно соответствует требованиям "
            "нормативно-технической документации при соблюдении установленных ограничений."
        ),
    },
}

TO_TOC_ITEMS: List[str] = [
    "1. Основания для проведения работ",
    "2. Сроки проведения работ",
    (
        "3. Перечень нормативных и правовых актов, устанавливающих требования "
        "к объекту диагностирования"
    ),
    "4. Сведения о Заказчике",
    "5. Сведения об организации, проводившей техническое диагностирование",
    "6. Сведения об эксперте и специалисте, проводивших диагностирование",
    "7. Перечень приборов и оборудования",
    "8. Объект технического диагностирования",
    (
        "9. Краткая техническая характеристика и назначение объекта "
        "технического освидетельствования"
    ),
    "10. Перечень работ, выполненных в процессе технического освидетельствования",
    (
        "11. Сведения о рассмотренных в процессе технического освидетельствования документах"
    ),
    "12. Анализ результатов предыдущих обследований",
    "13. Результаты технического освидетельствования",
    "14. Результаты расчетной оценки технического состояния",
    "15. Выводы по результатам технического освидетельствования",
    "Приложение № 1 Протокол анализа технической документации",
    "Приложение № 2 Протокол по результатам оперативной (функциональной) диагностики",
    "Приложение № 3 Протокол по результатам визуального и измерительного контроля",
    "Приложение № 4 Протокол по результатам ультразвукового контроля толщины стенок",
    "Приложение № 5 Протокол по результатам ультразвукового контроля качества металла",
    "Приложение № 6 Протокол по результатам контроля твердости металла",
    "Приложение № 7 Схема проведения неразрушающего контроля",
    "Приложение № 8 Расчёт остаточного ресурса",
    "Приложение № 9 Акт проведения гидравлического испытания",
    "Приложение № 10 Перечень нормативной документации",
]


def settings_file_path() -> Path:
    for candidate in _SETTINGS_CANDIDATES:
        if candidate.parent.exists() or candidate == _SETTINGS_CANDIDATES[0]:
            return candidate
    return _SETTINGS_CANDIDATES[-1]


def _deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    result = deepcopy(base)
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_report_org_settings() -> Dict[str, Any]:
    path = settings_file_path()
    if not path.exists():
        return deepcopy(DEFAULT_REPORT_ORG_SETTINGS)
    try:
        raw = json.loads(path.read_text(encoding="utf-8") or "{}")
        if not isinstance(raw, dict):
            return deepcopy(DEFAULT_REPORT_ORG_SETTINGS)
        return _deep_merge(DEFAULT_REPORT_ORG_SETTINGS, raw)
    except Exception:
        return deepcopy(DEFAULT_REPORT_ORG_SETTINGS)


def save_report_org_settings(data: Dict[str, Any]) -> Dict[str, Any]:
    merged = _deep_merge(DEFAULT_REPORT_ORG_SETTINGS, data if isinstance(data, dict) else {})
    path = settings_file_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
    return merged


def merge_client_into_settings(
    settings: Dict[str, Any],
    client: Optional[Dict[str, Any]] = None,
    enterprise_name: Optional[str] = None,
) -> Dict[str, Any]:
    """Подставить данные клиента из БД в справочник заказчика (если поля не заполнены вручную)."""
    result = deepcopy(settings)
    customer = result.setdefault("customer", {})
    if client:
        if not (customer.get("legal_name") or "").strip():
            customer["legal_name"] = client.get("name") or enterprise_name or ""
        if not (customer.get("address") or "").strip():
            customer["address"] = client.get("address") or ""
        if not (customer.get("phone") or "").strip():
            customer["phone"] = client.get("phone") or ""
        if not (customer.get("director") or "").strip():
            customer["director"] = client.get("contact_person") or ""
        if not (customer.get("inn") or "").strip():
            customer["inn"] = client.get("inn") or ""
    elif enterprise_name and not (customer.get("legal_name") or "").strip():
        customer["legal_name"] = enterprise_name
    return result
