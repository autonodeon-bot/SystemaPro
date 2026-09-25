"""Write-once provenance for a generated report, independent of mutable cards."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def load_technical_report_snapshot(report_path, snapshot_path):
    """Read the exact technical report revision used as the basis for expertise."""
    if not snapshot_path or not Path(snapshot_path).is_file():
        raise ValueError('У технического отчёта нет снимка исходных данных. Сформируйте технический отчёт заново.')
    payload = json.loads(Path(snapshot_path).read_text(encoding='utf-8'))
    inputs = payload.get('inputs') or {}
    if payload.get('snapshot_version') != 1 or inputs.get('report_type') != 'TECHNICAL_REPORT':
        raise ValueError('Неверный снимок исходного технического отчёта')
    if not report_path or not Path(report_path).is_file():
        raise ValueError('Файл исходного технического отчёта отсутствует')
    if hashlib.sha256(Path(report_path).read_bytes()).hexdigest() != payload.get('report_sha256'):
        raise ValueError('Файл технического отчёта изменён после формирования')
    if not isinstance(inputs.get('inspection'), dict) or not isinstance(inputs.get('equipment'), dict):
        raise ValueError('Снимок не содержит исходных данных обследования и оборудования')
    return inputs


def save_report_snapshot(report_path, *, inputs, actor, form_id=None):
    from report_schema import load_schema
    from report_forms_registry import get_form, FORMS_DIR

    report_path = Path(report_path)
    template = get_form(form_id) if form_id else None
    template_hash = None
    if template:
        filename = template.get('filename') or template.get('file')
        if filename and (FORMS_DIR / filename).is_file():
            template_hash = hashlib.sha256((FORMS_DIR / filename).read_bytes()).hexdigest()
    payload = {
        'snapshot_version': 1,
        'created_at': datetime.now(timezone.utc).isoformat(),
        'actor': str(actor),
        'generator_version': '2026-09-18.2',
        'schema_version': load_schema()['version'],
        'form_id': form_id,
        'template_sha256': template_hash,
        'report_sha256': hashlib.sha256(report_path.read_bytes()).hexdigest(),
        'inputs': inputs,
    }
    encoded = json.dumps(payload, ensure_ascii=False, default=str, sort_keys=True).encode('utf-8')
    destination = report_path.with_suffix(report_path.suffix + '.snapshot.json')
    # Exclusive creation prevents an accidental rewrite of an existing revision.
    with destination.open('xb') as output:
        output.write(encoded)
    return destination
