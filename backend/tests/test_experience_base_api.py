"""Тесты опытной базы."""
from experience_base_api import ARCHETYPE_SEED, DIAGNOSTIC_CATEGORIES, ENTRY_TYPES


def test_archetype_seed_count():
    assert len(ARCHETYPE_SEED) >= 20


def test_categories_match_xlsx_sections():
    codes = {c["code"] for c in DIAGNOSTIC_CATEGORIES}
    assert codes == {"srpd", "bu", "boiler", "bo", "valve_ps"}


def test_entry_types():
    assert "recommendation" in ENTRY_TYPES
    assert "operator_feedback" in ENTRY_TYPES
