import pytest
from vessel_elements import normalize_elements
from vessel_scheme_renderer import normalize_geometry, render_vessel_scheme


def element(part='shell_1', **kw):
    return dict(id='E1', kind='nozzle', part_id=part, x=.25, y=.4, **kw)


def test_round_trip_and_single_shell():
    raw = dict(equipment_kind='vessel', shell_count=1, weld_preset='multi_shell',
               elements=[element(control_points=4)])
    normalized = normalize_geometry(raw)
    assert normalized['shell_count'] == 1
    assert normalize_geometry(normalized)['elements'] == normalized['elements']


@pytest.mark.parametrize('part', ['shell_0', 'shell_4', 'head_unknown'])
def test_missing_part_is_rejected(part):
    with pytest.raises(ValueError): normalize_elements([element(part)], 3)


def test_invalid_coordinates_and_duplicate_ids():
    for field, value in [('x', float('nan')), ('y', 2), ('control_points', 3)]:
        e = element(); e[field] = value
        with pytest.raises(ValueError): normalize_elements([e], 3)
    with pytest.raises(ValueError): normalize_elements([element(), element()], 3)


@pytest.mark.parametrize('orientation', ['vertical', 'horizontal'])
def test_render_does_not_create_measurement_points(orientation):
    base = dict(equipment_kind='vessel', shell_count=3, orientation=orientation)
    plain, _, points = render_vessel_scheme(base)
    png, geo, with_elements = render_vessel_scheme(dict(base, elements=[element('head_bottom', control_points=2)]))
    assert png.startswith(b'\x89PNG') and png != plain
    assert with_elements == points
    assert geo['elements'][0]['part_id'] == 'head_bottom'
