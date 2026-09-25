import hashlib
import json
import pytest
from report_snapshot import save_report_snapshot


def test_snapshot_preserves_inputs_hash_and_template_version(tmp_path):
    report = tmp_path / 'report.docx'
    report.write_bytes(b'report revision one')
    inputs = {'inspection': {'data': {'pressure': '0', 'organization': 'Заказчик'}}}
    path = save_report_snapshot(report, inputs=inputs, actor='engineer', form_id='to-1')
    inputs['inspection']['data']['pressure'] = 'changed later'
    saved = json.loads(path.read_text(encoding='utf-8'))
    assert saved['inputs']['inspection']['data']['pressure'] == '0'
    assert saved['report_sha256'] == hashlib.sha256(report.read_bytes()).hexdigest()
    assert len(saved['template_sha256']) == 64
    with pytest.raises(FileExistsError):
        save_report_snapshot(report, inputs=inputs, actor='engineer', form_id='to-1')
