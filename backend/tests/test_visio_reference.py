import json
from pathlib import Path
import xml.etree.ElementTree as ET
from vessel_geometry_v2 import normalize_v2, render_v2

def test_all_reference_entities_are_exported_and_owned():
    root=Path(__file__).parents[2]
    g=normalize_v2(json.loads((root/'public/examples/visio-vessel.json').read_text(encoding='utf-8')))
    assert not g['diagnostics']
    assert len(g['control_points'])==138
    for orientation in ['horizontal','vertical']:
        g['orientation']=orientation
        svg=render_v2(g,1190,842,svg=True)[0]
        ids={e.attrib['data-entity-id'] for e in ET.fromstring(svg).iter() if 'data-entity-id' in e.attrib}
        assert {e['id'] for e in g['parts']+g['elements']+g['control_points']} <= ids
    g['orientation']='horizontal'
    (root/'artifacts/vessel-constructor-v2/visio-overview.png').write_bytes(render_v2(g,1190,842)[0])
