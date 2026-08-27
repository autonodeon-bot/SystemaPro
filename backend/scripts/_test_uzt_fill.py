# diagnose UZT fill
import sys
from pathlib import Path
from copy import deepcopy
from docx import Document

sys.path.insert(0, str(Path(__file__).resolve().parent))
from form_template_filler import fill_vessel_form_to1, _fill_uzt_results, _build_context, _enrich_inspection_data

sample = {
    "thickness_measurements": [
        {"location": "Обечайка", "section_number": "T1", "thickness": 8.2},
        {"location": "Обечайка", "section_number": "T2", "thickness": 8.1},
        {"location": "Днище", "section_number": "T3", "thickness": 10.0},
    ],
    "uzt_schemes": [
        {
            "label": "Схема 1",
            "measurements": [
                {"location": "Патрубок", "section_number": "T4", "thickness": 7.5},
            ],
        }
    ],
}
ndt = [
    {
        "method_code": "УЗТ",
        "additional_data": {
            "measurement_points": [
                {"location": "Корпус", "thickness": "9.1"},
            ]
        },
    }
]
enriched = _enrich_inspection_data(dict(sample), ndt)
print("enriched thickness count", len(enriched.get("thickness_measurements") or []))
for p in enriched.get("thickness_measurements") or []:
    print(p)

out = Path("_test_uzt_fill.docx")
fill_vessel_form_to1(
    inspection_data={"id": "test", "data": sample, "report_form_id": "to-1"},
    equipment_data={"name": "Test", "serial_number": "1", "attributes": {}},
    output_path=str(out),
    ndt_methods=ndt,
)
doc = Document(str(out))
t = doc.tables[21]
print("=== filled table 21 ===")
for ri, r in enumerate(t.rows):
    print(ri, [(c.text or "").replace("\n", " ")[:40] for c in r.cells])
