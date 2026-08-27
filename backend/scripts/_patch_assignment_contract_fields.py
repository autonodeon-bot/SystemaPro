# -*- coding: utf-8 -*-
"""Патч assignments API/модели: поля договора, сроков, техкарты для отчёта ТО."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "backend"

# --- models.py ---
models = BACKEND / "models.py"
mt = models.read_text(encoding="utf-8")
if "contract_number" not in mt:
    mt = mt.replace(
        "    ndt_method_codes = Column(JSONB, nullable=True)  # ['UZT','VIK','UZK',...]\n",
        "    ndt_method_codes = Column(JSONB, nullable=True)  # ['UZT','VIK','UZK',...]\n"
        "    # Данные для титула/разд.1–2 официальной формы ТО (заполняются при выдаче задания)\n"
        "    contract_number = Column(String(128), nullable=True)\n"
        "    contract_date = Column(String(32), nullable=True)\n"
        "    work_period_from = Column(String(32), nullable=True)\n"
        "    work_period_to = Column(String(32), nullable=True)\n"
        "    work_basis = Column(Text, nullable=True)\n"
        "    tech_card_number = Column(String(128), nullable=True)\n",
    )
    models.write_text(mt, encoding="utf-8")
    print("models ok")
else:
    print("models already")

# --- main.py migrations ---
main = BACKEND / "main.py"
main_t = main.read_text(encoding="utf-8")
if "contract_number" not in main_t:
    main_t = main_t.replace(
        '            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS ndt_method_codes JSONB",\n        ]),',
        '            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS ndt_method_codes JSONB",\n'
        '            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS contract_number VARCHAR(128)",\n'
        '            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS contract_date VARCHAR(32)",\n'
        '            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS work_period_from VARCHAR(32)",\n'
        '            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS work_period_to VARCHAR(32)",\n'
        '            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS work_basis TEXT",\n'
        '            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS tech_card_number VARCHAR(128)",\n'
        "        ]),",
    )
    main.write_text(main_t, encoding="utf-8")
    print("main migrate ok")
else:
    print("main already")

# --- assignments_api.py ---
api = BACKEND / "assignments_api.py"
at = api.read_text(encoding="utf-8")

helper = '''
def _assignment_contract_payload(assignment: Assignment) -> dict:
    """Поля договора/сроков/техкарты для ответа API и мобильного."""
    def _s(name: str):
        v = getattr(assignment, name, None)
        if v is None:
            return None
        s = str(v).strip()
        return s or None
    return {
        "contract_number": _s("contract_number"),
        "contract_date": _s("contract_date"),
        "work_period_from": _s("work_period_from"),
        "work_period_to": _s("work_period_to"),
        "work_basis": _s("work_basis"),
        "tech_card_number": _s("tech_card_number"),
    }

'''

if "_assignment_contract_payload" not in at:
    at = at.replace(
        "def _report_form_payload(assignment: Assignment) -> dict:",
        helper + "def _report_form_payload(assignment: Assignment) -> dict:",
    )

# Pydantic create/update/response
if "contract_number" not in at.split("class AssignmentCreate")[1][:400]:
    at = at.replace(
        """class AssignmentCreate(BaseModel):
    equipment_id: str
    assignment_type: str  # 'DIAGNOSTICS', 'EXPERTISE', 'INSPECTION'
    assigned_to: str
    priority: Optional[str] = 'NORMAL'
    due_date: Optional[str] = None
    description: Optional[str] = None
    protocol_template_id: Optional[str] = None
    report_form_id: Optional[str] = None
    ndt_method_codes: Optional[List[str]] = None

class AssignmentUpdate(BaseModel):
    status: Optional[str] = None
    priority: Optional[str] = None
    due_date: Optional[str] = None
    description: Optional[str] = None
    protocol_template_id: Optional[str] = None
    report_form_id: Optional[str] = None
""",
        """class AssignmentCreate(BaseModel):
    equipment_id: str
    assignment_type: str  # 'DIAGNOSTICS', 'EXPERTISE', 'INSPECTION'
    assigned_to: str
    priority: Optional[str] = 'NORMAL'
    due_date: Optional[str] = None
    description: Optional[str] = None
    protocol_template_id: Optional[str] = None
    report_form_id: Optional[str] = None
    ndt_method_codes: Optional[List[str]] = None
    contract_number: Optional[str] = None
    contract_date: Optional[str] = None
    work_period_from: Optional[str] = None
    work_period_to: Optional[str] = None
    work_basis: Optional[str] = None
    tech_card_number: Optional[str] = None

class AssignmentUpdate(BaseModel):
    status: Optional[str] = None
    priority: Optional[str] = None
    due_date: Optional[str] = None
    description: Optional[str] = None
    protocol_template_id: Optional[str] = None
    report_form_id: Optional[str] = None
    contract_number: Optional[str] = None
    contract_date: Optional[str] = None
    work_period_from: Optional[str] = None
    work_period_to: Optional[str] = None
    work_basis: Optional[str] = None
    tech_card_number: Optional[str] = None
""",
    )

if "contract_number: Optional[str] = None" not in at.split("class AssignmentResponse")[1][:800]:
    at = at.replace(
        """    protocol_template_id: Optional[str] = None
    protocol_template_name: Optional[str] = None
    report_form_id: Optional[str] = None
    report_form_title: Optional[str] = None
    ndt_method_codes: Optional[List[str]] = None
""",
        """    protocol_template_id: Optional[str] = None
    protocol_template_name: Optional[str] = None
    report_form_id: Optional[str] = None
    report_form_title: Optional[str] = None
    ndt_method_codes: Optional[List[str]] = None
    contract_number: Optional[str] = None
    contract_date: Optional[str] = None
    work_period_from: Optional[str] = None
    work_period_to: Optional[str] = None
    work_basis: Optional[str] = None
    tech_card_number: Optional[str] = None
""",
        1,
    )

# Inject into response dicts: after **_report_form_payload(assignment),
if "**_assignment_contract_payload(assignment)" not in at:
    at = at.replace(
        "**_report_form_payload(assignment),",
        "**_report_form_payload(assignment),\n                **_assignment_contract_payload(assignment),",
    )

# create_assignment: save new fields
if "contract_number=assignment_data.contract_number" not in at:
    at = at.replace(
        "            report_form_id=form_id_raw,\n            ndt_method_codes=assignment_data.ndt_method_codes,\n",
        "            report_form_id=form_id_raw,\n"
        "            ndt_method_codes=assignment_data.ndt_method_codes,\n"
        "            contract_number=(assignment_data.contract_number or None),\n"
        "            contract_date=(assignment_data.contract_date or None),\n"
        "            work_period_from=(assignment_data.work_period_from or None),\n"
        "            work_period_to=(assignment_data.work_period_to or None),\n"
        "            work_basis=(assignment_data.work_basis or None),\n"
        "            tech_card_number=(assignment_data.tech_card_number or None),\n",
    )

# update_assignment: apply fields
update_block = '''
        for _fname in (
            "contract_number",
            "contract_date",
            "work_period_from",
            "work_period_to",
            "work_basis",
            "tech_card_number",
        ):
            if _fname in assignment_data.model_fields_set:
                _val = getattr(assignment_data, _fname, None)
                if _val is not None:
                    _val = str(_val).strip() or None
                setattr(assignment, _fname, _val)
'''

if 'for _fname in (\n            "contract_number"' not in at:
    # insert before commit in update_assignment
    marker = "        await db.commit()\n        await db.refresh(assignment)\n\n        return {"
    # find update-specific - there may be multiple. Use unique context near report_form_id update
    idx = at.find('if "report_form_id" in assignment_data.model_fields_set:')
    if idx < 0:
        raise SystemExit("update report_form_id block not found")
    # find next await db.commit after this
    commit_idx = at.find("await db.commit()", idx)
    if commit_idx < 0:
        raise SystemExit("commit not found")
    at = at[:commit_idx] + update_block + "\n        " + at[commit_idx:]

api.write_text(at, encoding="utf-8")
print("assignments_api ok")

# --- reports_crud_api merge ---
rep = BACKEND / "reports_crud_api.py"
rt = rep.read_text(encoding="utf-8")
merge_snip = '''
                # Подмешать договор/сроки/техкарту из задания, если в inspection.data пусто
                try:
                    if asn is not None:
                        dp0 = inspection_payload.get("data")
                        if not isinstance(dp0, dict):
                            dp0 = {}
                            inspection_payload["data"] = dp0
                        for _k in (
                            "contract_number",
                            "contract_date",
                            "work_period_from",
                            "work_period_to",
                            "work_basis",
                            "tech_card_number",
                        ):
                            if not dp0.get(_k):
                                _av = getattr(asn, _k, None)
                                if _av:
                                    dp0[_k] = str(_av)
                except Exception as _e:
                    print(f"Warning: merge assignment contract fields: {_e}")
'''
if "merge assignment contract fields" not in rt:
    # insert after report_form_id resolution block
    needle = '                print(f"Warning: could not resolve report_form_id: {e}")'
    if needle not in rt:
        raise SystemExit("reports needle missing")
    rt = rt.replace(needle, needle + "\n" + merge_snip)
    rep.write_text(rt, encoding="utf-8")
    print("reports_crud ok")
else:
    print("reports already")

print("DONE")
