import io
import json
import uuid
import zipfile
from unittest.mock import AsyncMock
import pytest
from fastapi import HTTPException
from bulk_report_export import export_reports


@pytest.mark.asyncio
async def test_bulk_uses_single_report_path_and_includes_snapshot_and_failures(tmp_path, monkeypatch):
    ids = [str(uuid.uuid4()), str(uuid.uuid4())]
    path = tmp_path / 'report.docx'; path.write_bytes(b'docx fixture')
    path.with_suffix('.docx.snapshot.json').write_text('{"snapshot_version":1}')
    generate = AsyncMock(side_effect=[{'id': 'created-report', 'file_path': str(path)}, HTTPException(403, 'Нет доступа')])
    monkeypatch.setattr('reports_crud_api.generate_report', generate)
    response = await export_reports({'inspection_ids': ids, 'report_type': 'TECHNICAL_REPORT'}, 'operator', AsyncMock())
    content = b''.join([chunk async for chunk in response.body_iterator])
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        assert f'report_{ids[0]}.docx' in archive.namelist()
        assert f'report_{ids[0]}.snapshot.json' in archive.namelist()
        result = json.loads(archive.read('generation-results.json'))['items']
        assert [item['status'] for item in result] == ['generated', 'failed']
    assert generate.await_args_list[0].args[0]['format'] == 'docx'


@pytest.mark.asyncio
async def test_bulk_does_not_silently_truncate_selection():
    with pytest.raises(HTTPException) as exc:
        await export_reports({'inspection_ids': [str(uuid.uuid4()) for _ in range(16)]}, 'operator', AsyncMock())
    assert exc.value.status_code == 400
