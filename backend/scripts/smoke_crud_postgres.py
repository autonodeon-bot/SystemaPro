"""Real PostgreSQL smoke test. Only an explicitly named local audit DB is accepted."""
import asyncio
import os
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


async def main():
    if os.getenv('DB_HOST') not in {'127.0.0.1', 'localhost'} or not os.getenv('DB_NAME', '').startswith('systemapro_audit'):
        raise RuntimeError('Use a dedicated local systemapro_audit database')
    from database import engine, AsyncSessionLocal
    from models import Base, User, Equipment, UserEquipmentAccess, AuditLog
    from equipment_crud_api import EquipmentCreate, EquipmentUpdate, create_equipment, update_equipment, get_equipment, _authorize_equipment_write
    from sqlalchemy import select
    from fastapi import HTTPException
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    suffix = uuid.uuid4().hex[:10]
    async with AsyncSessionLocal() as db:
        admin = User(username='audit-admin-' + suffix, email=suffix + '@example.invalid', password_hash='test-only', role='admin')
        engineer = User(username='audit-engineer-' + suffix, email='e' + suffix + '@example.invalid', password_hash='test-only', role='engineer')
        db.add_all([admin, engineer]); await db.commit()
        created = await create_equipment(EquipmentCreate(name='Контрольный насос', serial_number=suffix, attributes={'pressure': '12', 'zero': 0}), db=db, username=admin.username)
        equipment_id = created['id']
        updated = await update_equipment(equipment_id, EquipmentUpdate(name='Насос после редактирования'), db=db, username=admin.username)
        assert updated['attributes']['pressure'] == '12'
        access = UserEquipmentAccess(user_id=engineer.id, equipment_id=uuid.UUID(equipment_id), access_type='READ')
        db.add(access); await db.commit()
        try:
            await _authorize_equipment_write(db, engineer.username, equipment_id)
            raise AssertionError('Read-only grant allowed a write')
        except HTTPException as exc:
            assert exc.status_code == 403
        access.access_type = 'read_write'; await db.commit()
        updated = await update_equipment(equipment_id, EquipmentUpdate(fill_missing_only=True, attributes={'pressure': '10', 'material': 'Сталь'}), db=db, username=engineer.username)
        assert updated['attributes']['pressure'] == '12' and updated['attributes']['material'] == 'Сталь'
        assert updated['conflicts'] == ['pressure']
        listed = await get_equipment(username=engineer.username, db=db, search=suffix)
        assert any(row['id'] == equipment_id for row in listed['items'])
        audit = (await db.execute(select(AuditLog).where(AuditLog.entity_id == uuid.UUID(equipment_id)))).scalars().all()
        assert len(audit) >= 2 and audit[-1].details['source'] == 'mobile_inspection'
        from equipment_crud_api import equipment_change_history
        history = await equipment_change_history(equipment_id, username=engineer.username, db=db)
        assert len(history['items']) >= 2
        assert history['items'][0]['actor'] == engineer.username
        from models import Assignment
        assigned = await create_equipment(EquipmentCreate(name='Оборудование по заданию'), db=db, username=admin.username)
        task = Assignment(equipment_id=uuid.UUID(assigned['id']), assigned_to=engineer.id, status='PENDING')
        db.add(task); await db.commit()
        assert (await _authorize_equipment_write(db, engineer.username, assigned['id'])).id == engineer.id
        if '--archives' in sys.argv:
            import io
            import json
            import hashlib
            import zipfile
            from unittest.mock import patch
            from fastapi import UploadFile
            from inspection_archive_api import upload_inspection_archive
            from sqlalchemy import func
            from models import Inspection
            login = engineer.username
            task_id = str(task.id)
            if not os.getenv('UPLOADS_DIR'):
                raise RuntimeError('Explicit audit uploads directory is required')
            def upload(revision):
                payload = {'equipment_id': assigned['id'], 'assignment_id': task_id, 'status': 'DRAFT',
                    'data': {'vessel_name': 'Архивный тест', 'document_files': {'1': {'file_path': 'photos/doc_1.pdf'}}}}
                files = {'checklist.json': json.dumps(payload).encode(), 'photos/doc_1.pdf': b'%PDF-1.7 audit'}
                manifest = {'version': 2, 'client_revision': revision,
                    'checksums': {name: hashlib.sha256(value).hexdigest() for name, value in files.items()}}
                stream = io.BytesIO()
                with zipfile.ZipFile(stream, 'w') as archive:
                    for name, value in files.items():
                        archive.writestr(name, value)
                    archive.writestr('manifest.json', json.dumps(manifest))
                stream.seek(0)
                return UploadFile(filename='audit.zip', file=stream)
            first = await upload_inspection_archive(upload('one'), username=login, db=db)
            again = await upload_inspection_archive(upload('one'), username=login, db=db)
            assert first['id'] == again['id'] and again['status'] == 'already_received'
            saved = await db.get(Inspection, uuid.UUID(first['id']))
            saved_path = saved.data['document_files']['1']['file_path']
            assert Path(saved_path).read_bytes() == b'%PDF-1.7 audit'
            count_query = select(func.count()).select_from(Inspection).where(Inspection.equipment_id == uuid.UUID(assigned['id']))
            assert (await db.execute(count_query)).scalar_one() == 1
            with patch('inspection_archive_api.shutil.copy2', side_effect=OSError('audit simulated disk full')):
                try:
                    await upload_inspection_archive(upload('two'), username=login, db=db)
                    raise AssertionError('Broken attachment was acknowledged')
                except HTTPException as exc:
                    assert exc.status_code == 500
            assert (await db.execute(count_query)).scalar_one() == 1
            recovered = await upload_inspection_archive(upload('two'), username=login, db=db)
            assert recovered['id'] != first['id']
            assert (await db.execute(count_query)).scalar_one() == 2
            async def concurrent_upload():
                async with AsyncSessionLocal() as separate:
                    return await upload_inspection_archive(upload('concurrent'), username=login, db=separate)
            concurrent = await asyncio.gather(concurrent_upload(), concurrent_upload())
            assert concurrent[0]['id'] == concurrent[1]['id']
            assert (await db.execute(count_query)).scalar_one() == 3
            print('PASS: archive retry reuses inspection, PDF bytes preserved, failed attachment rolls back, retry recovers')
            print('PASS: concurrent archive submissions produce exactly one inspection')
        print('PASS: real PostgreSQL CRUD, role permissions, scoped search, conflict preservation and audit history')
        if '--reports' in sys.argv:
            from datetime import datetime, timezone
            from models import Inspection, Report
            from reports_crud_api import generate_report
            from report_jobs import JobStore, run_report_job
            import json
            import hashlib
            if not os.getenv('REPORTS_DIR') or not os.getenv('REPORT_JOBS_DIR'):
                raise RuntimeError('Explicit audit report directories are required')
            inspection = Inspection(equipment_id=uuid.UUID(equipment_id), status='DRAFT', created_by=admin.id,
                inspector_id=admin.id, date_performed=datetime(2026, 9, 18, tzinfo=timezone.utc), data={
                    'report_form_id': 'to-5', 'vessel_name': 'Тестовый трансформатор', 'organization': 'Контрольный заказчик',
                    'executors': 'Тестовый специалист', 'conclusion': 'Только проверка программного обеспечения',
                    'additional_data': {'profile_measurements': [{'point': 'Точка 1', 'insulation': '1,25', 'ground': 0}]},
                })
            db.add(inspection); await db.commit()
            request = {'inspection_id': str(inspection.id), 'report_type': 'TECHNICAL_REPORT', 'format': 'docx', 'skip_validation': True}
            result = await generate_report(request, username=admin.username, db=db)
            report = await db.get(Report, uuid.UUID(result['id']))
            snapshot = json.loads(Path(report.json_file_path).read_text(encoding='utf-8'))
            assert snapshot['report_sha256'] == hashlib.sha256(Path(report.file_path).read_bytes()).hexdigest()
            from docx import Document
            document = Document(report.file_path)
            assert any('1,25' in cell.text for table in document.tables for row in table.rows for cell in row.cells)
            job_id = str(uuid.uuid4())
            JobStore().create(job_id, admin.username, {**request, 'format': 'pdf'})
            await run_report_job(job_id, admin.username)
            job = JobStore().read(job_id, admin.username)
            assert job['status'] == 'completed', job
            assert Path(job['result']['file_path']).read_bytes().startswith(b'%PDF')
            await run_report_job(job_id, admin.username)
            # Simulate loss of the status write after PostgreSQL has committed the report.
            job.update(status='running', result=None)
            JobStore().write(job)
            await run_report_job(job_id, admin.username)
            assert JobStore().read(job_id, admin.username)['result']['id'] == job_id
            from unittest.mock import patch
            from sqlalchemy import func
            report_count = (await db.execute(select(func.count()).select_from(Report))).scalar_one()
            with patch('docx_to_pdf.convert_docx_to_pdf', return_value=None):
                try:
                    await generate_report({**request, 'format': 'pdf'}, username=admin.username, db=db)
                    raise AssertionError('Failed conversion silently used another layout')
                except HTTPException as exc:
                    assert exc.status_code == 503
            assert (await db.execute(select(func.count()).select_from(Report))).scalar_one() == report_count
            print('PASS: actual DOCX, PDF background job, measurement values, immutable snapshot and repeated job acknowledgement')
            print('PASS: interrupted job resumes with same report ID; PDF conversion failure cannot fall back to another layout')
            from bulk_report_export import export_reports
            import io
            import zipfile
            bulk = await export_reports({'inspection_ids': [str(inspection.id)], 'report_type': 'TECHNICAL_REPORT', 'skip_validation': True}, admin.username, db)
            raw = b''.join([chunk async for chunk in bulk.body_iterator])
            with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                assert any(name.endswith('.snapshot.json') for name in archive.namelist())
                assert any(name.endswith('.docx') for name in archive.namelist())
            print('PASS: bulk export includes official DOCX and input snapshot through the single generation path')
    await engine.dispose()


if __name__ == '__main__':
    asyncio.run(main())
