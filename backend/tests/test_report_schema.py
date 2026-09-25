from pathlib import Path
import pytest
from report_schema import SCHEMA_PATH, schema_for_form, validate_profile_values


def test_server_and_mobile_use_identical_field_contract():
    mobile = SCHEMA_PATH.parents[2] / 'mobile/assets/data/report_fields.json'
    assert SCHEMA_PATH.read_bytes() == mobile.read_bytes()
    for number in range(1, 45):
        assert schema_for_form(f'to-{number}')['fields']


@pytest.mark.parametrize('value', ['NaN', 'inf', '-1', 'abc'])
def test_invalid_electrical_measurement_is_rejected(value):
    assert validate_profile_values({'report_form_id': 'to-5', 'additional_data': {'profile_values': {'insulation_resistance': value}}})


@pytest.mark.parametrize('value', ['0', '1,25', '12.5'])
def test_decimal_comma_and_zero_are_accepted(value):
    assert not validate_profile_values({'report_form_id': 'to-5', 'additional_data': {'profile_values': {'insulation_resistance': value}}})


def test_measurement_table_validation_and_export():
    from docx import Document
    from report_supplement import append_report_fields
    data = {'report_form_id': 'to-5', 'additional_data': {'profile_measurements': [
        {'point': 'Заземлитель 1', 'voltage': '500', 'insulation': '1,25', 'ground': 0}
    ]}}
    assert not validate_profile_values(data)
    doc = Document()
    assert append_report_fields(doc, data) == 1
    assert [c.text for c in doc.tables[-1].rows[1].cells] == ['Заземлитель 1', '500', '1,25', '0']
    data['additional_data']['profile_measurements'][0]['ground'] = '-2'
    assert validate_profile_values(data)[0]['field'] == 'profile_measurements.0.ground'
