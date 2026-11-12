import copy
import json
from pathlib import Path
import pytest
from vessel_annotations import coordinate_callout, legend_entries, legend_lines
from vessel_geometry_v2 import render_v2, normalize_v2
from vessel_sheet import sheet_spec


def example():
    return json.loads((Path(__file__).parents[2]/'public/examples/visio-vessel.json').read_text(encoding='utf-8'))


def test_coordinates_from_both_reference_welds_do_not_modify_model():
    g=example(); e=g['elements'][0]; owner=next(p for p in g['parts'] if p['id']==e['parent_id'])
    e['placement'].update(z_local_mm=350.5,theta_deg=450)
    end=next(w for w in g['welds'] if w['kind']=='circumferential' and w['connected_part_ids'][0]==owner['id'])
    e['placement']['reference_weld_id']=end['id']; before=copy.deepcopy(g)
    lines=coordinate_callout(g,e,owner,owner['id'])
    assert f"{owner['dimensions']['length_mm']-350.5:g}".replace('.',',') in lines[0]
    assert end['designation'] in lines[0] and '90°' in lines[1]
    assert g==before
    e['placement'].pop('reference_weld_id'); assert coordinate_callout(g,e,owner,owner['id'])[0]=='350,5 мм от начала детали'


def test_schematic_and_unknown_are_never_converted_to_fake_dimensions():
    g=example();e=g['elements'][0];owner=g['parts'][1]
    e['placement']={'mode':'schematic','u':.4,'v':.2}
    assert coordinate_callout(g,e,owner,owner['id'])==['Положение условное']
    e['placement']={'mode':'physical','theta_deg':30}
    assert coordinate_callout(g,e,owner,owner['id'])==['Координаты не заданы']
    g['print_settings']={'show_dimensions':False}
    assert coordinate_callout(g,e,owner)==[]


def test_head_radius_and_point_dimensions_only_on_details():
    g=example();owner={'id':'head','kind':'head'}
    e={'owner_id':'head','placement':{'mode':'physical','radius_projection_mm':120.25,'theta_deg':90,'angle_convention':'visio-head-2026'}}
    assert coordinate_callout(g,e,owner)==[]
    assert coordinate_callout(g,e,owner,'head')==['Rпр=120,25 мм от центра','θ=90° · Visio']


def test_legend_respects_visible_parts_archiving_and_selected_method():
    g=example(); head=next(p for p in g['parts'] if p['kind']=='head')
    g['control_points']=[];g['elements']=[];g['sections']=[]
    assert legend_entries(g,{head['id']},detail=head['id'])==['Шов днища']
    visible={p['id'] for p in g['parts']}
    g['control_zones']=[]
    entries=legend_entries(g,visible)
    assert not any('УЗТ' in e or 'ПВК' in e or 'твердометрия' in e for e in entries)
    w=next(w for w in g['welds'] if w['kind']=='circumferential')
    g['control_zones']=[{'weld_id':w['id'],'planned_methods':['УЗК','МК']}]
    assert '/ УЗК' in legend_entries(g,visible,layer='МК')
    assert '× МК' in legend_entries(g,visible,layer='МК')
    assert '× ПВК' not in legend_entries(g,visible,layer='МК')
    assert '/ УЗК' not in legend_entries(g,visible,layer='ПВК')


@pytest.mark.parametrize('orientation',['horizontal','vertical'])
def test_rendered_svg_contains_coordinates_dynamic_legend_and_preserves_snapshot(orientation):
    g=example();g['orientation']=orientation;before=copy.deepcopy(g);spec=sheet_spec(g)
    svg=render_v2(g,spec['width'],spec['height'],svg=True)[0].decode()
    assert 'Обозначения:' in svg and 'от начала детали' not in svg
    shell=next(p for p in g['parts'] if p['kind']=='shell')
    detailed=render_v2(g,spec['width'],spec['height'],svg=True,detail=shell['id'])[0].decode()
    assert 'от начала детали' in detailed and 'θ=' in detailed
    assert g==before
    g['print_settings']={'show_dimensions':False}
    assert 'от начала детали' not in render_v2(g,spec['width'],spec['height'],svg=True)[0].decode()


def test_invalid_dimension_toggle_rejected():
    g=example();g['print_settings']={'show_dimensions':'false'}
    with pytest.raises(ValueError,match='show_dimensions'):normalize_v2(g)


def test_a4_number_tag_keeps_existing_angle_label_visible():
    from unittest.mock import Mock
    from vessel_annotations import draw_print_callouts
    from vessel_scheme_renderer import _font

    draw = Mock()
    angle_label = (114, 110, 138, 138)
    draw_print_callouts(draw, {'p1': (100, 150)}, [('p1', '1', 'Точка 1', ['θ=180°'])],
                        842, 1190, _font, [angle_label])
    tag = draw.rectangle.call_args_list[1].args[0]
    assert tag[2] <= angle_label[0] or tag[0] >= angle_label[2] or tag[3] <= angle_label[1] or tag[1] >= angle_label[3]
