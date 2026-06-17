"""Тесты меню диагностики по умолчанию."""
from diagnostic_menu_default import build_default_diagnostic_menu


def test_default_menu_structure():
    menu = build_default_diagnostic_menu()
    assert menu["version"] == 1
    assert len(menu["quick_control_tree"]) >= 3
    assert len(menu["object_categories"]) == 5
    assert menu["quick_control_tree"][0]["action"] == "emergencyInspection"
