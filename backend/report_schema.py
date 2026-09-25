"""Shared field contract for profile-specific report values."""
import json
from decimal import Decimal, InvalidOperation
from functools import lru_cache
from pathlib import Path

SCHEMA_PATH = Path(__file__).parent / "report_forms" / "report_fields.json"


@lru_cache(maxsize=1)
def load_schema():
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def schema_for_form(form_id):
    schema = load_schema()
    profile = schema["forms"].get(form_id)
    if profile is None:
        raise ValueError("Неизвестная форма отчёта")
    return {"version": schema["version"], "form_id": form_id,
            "profile": profile, "fields": schema["profiles"][profile],
            "measurement_columns": schema.get("measurements", {}).get(profile, [])}


def validate_profile_values(data):
    form_id = data.get("report_form_id") or "to-1"
    schema = schema_for_form(form_id)
    additional = data.get("additional_data") or {}
    values = additional.get("profile_values") or {} if isinstance(additional, dict) else {}
    if not isinstance(values, dict):
        return [{"field": "profile_values", "message": "Характеристики должны быть объектом"}]
    errors = []
    for field in schema["fields"]:
        value = values.get(field["key"])
        if value is None or str(value).strip() == "" or field["type"] != "number":
            continue
        try:
            number = Decimal(str(value).strip().replace(",", "."))
            valid = number.is_finite() and ("min" not in field or number >= Decimal(str(field["min"])))
        except InvalidOperation:
            valid = False
        if not valid:
            errors.append({"field": field["key"], "message": f"{field['label']}: некорректное число ({field.get('unit', '')})"})
    rows = additional.get('profile_measurements', []) if isinstance(additional, dict) else []
    if not isinstance(rows, list):
        errors.append({'field': 'profile_measurements', 'message': 'Измерения должны быть списком'})
        return errors
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            errors.append({'field': f'profile_measurements.{index}', 'message': 'Неверный формат строки измерений'})
            continue
        for field in schema['measurement_columns']:
            value = row.get(field['key'])
            if value in (None, '') or field['type'] != 'number':
                continue
            try:
                number = Decimal(str(value).strip().replace(',', '.'))
                valid = number.is_finite() and ('min' not in field or number >= Decimal(str(field['min'])))
            except InvalidOperation:
                valid = False
            if not valid:
                errors.append({'field': f"profile_measurements.{index}.{field['key']}",
                    'message': f"Измерение {index + 1}, {field['label']}: некорректное число"})
    return errors
