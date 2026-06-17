"""Тесты шаблонов быстрого контроля."""
import pytest

from quick_control_protocol_templates import QC_TEMPLATE_IDS, _build_structures


def test_all_codes_have_metadata():
    structures = _build_structures()
    assert set(structures.keys()) == set(QC_TEMPLATE_IDS.keys())
    for code, meta in structures.items():
        assert meta.get("name")
        assert isinstance(meta.get("structure"), list)
        assert len(meta["structure"]) >= 3


def test_template_ids_stable():
    assert len(QC_TEMPLATE_IDS) == 8
    assert all(v.startswith("qc-template-") for v in QC_TEMPLATE_IDS.values())
