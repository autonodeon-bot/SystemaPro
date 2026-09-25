"""Bulk exports use exactly the same data enrichment and snapshots as individual reports."""
import io
import json
import uuid
import zipfile
from pathlib import Path

from fastapi import HTTPException
from fastapi.responses import StreamingResponse


async def export_reports(body, username, db):
    from reports_crud_api import generate_report
    from report_request import normalize_report_options
    ids = body.get('inspection_ids')
    if not isinstance(ids, list) or not ids or len(ids) > 15:
        raise HTTPException(status_code=400, detail='Выберите от 1 до 15 обследований')
    try:
        ids = list(dict.fromkeys(str(uuid.UUID(str(item))) for item in ids))
        report_type, _ = normalize_report_options({**body, 'format': 'docx'})
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    result = []
    files = []
    for inspection_id in ids:
        try:
            report = await generate_report({'inspection_id': inspection_id, 'report_type': report_type,
                'format': 'docx', 'skip_validation': body.get('skip_validation') is True}, username=username, db=db)
            path = Path(report['file_path'])
            snapshot = path.with_suffix(path.suffix + '.snapshot.json')
            if not path.is_file() or not snapshot.is_file():
                raise RuntimeError('Отсутствует файл отчета или снимок данных')
            files.append((inspection_id, path, snapshot))
            result.append({'inspection_id': inspection_id, 'report_id': report['id'], 'status': 'generated'})
        except Exception as exc:
            await db.rollback()
            result.append({'inspection_id': inspection_id, 'status': 'failed',
                'error': str(exc.detail if isinstance(exc, HTTPException) else exc)})
    if not files:
        raise HTTPException(status_code=400, detail={'message': 'Отчеты не созданы', 'items': result})
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for inspection_id, path, snapshot in files:
            archive.write(path, f'report_{inspection_id}.docx')
            archive.write(snapshot, f'report_{inspection_id}.snapshot.json')
        archive.writestr('generation-results.json', json.dumps({'items': result}, ensure_ascii=False, indent=2))
    output.seek(0)
    return StreamingResponse(output, media_type='application/zip',
        headers={'Content-Disposition': 'attachment; filename=reports.zip'})
