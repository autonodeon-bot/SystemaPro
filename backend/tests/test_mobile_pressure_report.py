from types import SimpleNamespace

from docx import Document

from epb_protocol_tables import append_epb_appendix_e


def test_mobile_pressure_results_are_used_without_legacy_example_or_resource_claim():
    data = {'calculation_data': {'strength_calculations': [{
        'name': 'Обечайка инженера',
        'inputs': {'pressure_mpa': 1.6, 'diameter_mm': 1000, 'temperature_c': 20,
                   'material': '09Г2С', 'nominal_mm': 6, 'weld_factor': 1,
                   'c1_mm': 1, 'c2_mm': 0, 'c3_mm': 0, 'stress_basis': 'Проверенный расчёт'},
        'result': {'allowable_stress_mpa': 150, 'calculated_thickness_mm': 5.361930,
                   'minimum_thickness_mm': 6.37, 'clause': '5.3.1.1',
                   'formula': 'sp = pD/(2[σ]φ−p)', 'nominal_sufficient': False}
    }]}}
    def get(*keys, default=None):
        return next((data[k] for k in keys if k in data), default)
    doc = Document()
    append_epb_appendix_e(doc, SimpleNamespace(), get,
                         {'min_wall_thickness': 15, 'working_pressure': 9}, {})
    text = '\n'.join(p.text for p in doc.paragraphs)
    cells = '\n'.join(c.text for table in doc.tables for row in table.rows for c in row.cells)
    assert '6.37' in cells
    assert '150' in cells
    assert 'Обечайка инженера' in text
    assert 'меньше требуемой' in text
    assert 'обеспечивает требуемый запас' not in text
    assert 'может эксплуатироваться' not in text
    assert 'остаточный ресурс' in text
