import uuid
import pytest
from fastapi import HTTPException
from report_jobs import JobStore
from unittest.mock import AsyncMock, MagicMock


def test_repeated_submission_reuses_job_and_result(tmp_path):
    store = JobStore(tmp_path)
    job_id = str(uuid.uuid4())
    job, created = store.create(job_id, 'operator', {'inspection_id': 'inspection'})
    assert created
    job.update(status='completed', result={'id': 'report-id'})
    store.write(job)
    duplicate, created = store.create(job_id, 'operator', {'inspection_id': 'inspection'})
    assert not created
    assert duplicate['result']['id'] == 'report-id'


def test_job_cannot_be_read_by_another_user_or_reused_for_different_inputs(tmp_path):
    store = JobStore(tmp_path)
    job_id = str(uuid.uuid4())
    store.create(job_id, 'engineer-a', {'format': 'pdf'})
    with pytest.raises(HTTPException) as exc:
        store.read(job_id, 'engineer-b')
    assert exc.value.status_code == 403
    with pytest.raises(HTTPException) as exc:
        store.create(job_id, 'engineer-a', {'format': 'docx'})
    assert exc.value.status_code == 409


@pytest.mark.asyncio
async def test_worker_persists_result_and_does_not_execute_twice(tmp_path, monkeypatch):
    from report_jobs import run_report_job
    monkeypatch.setenv('REPORT_JOBS_DIR', str(tmp_path))
    job_id = str(uuid.uuid4())
    store = JobStore()
    store.create(job_id, 'operator', {'inspection_id': 'example'})
    generator = AsyncMock(return_value={'id': 'report'})
    session = MagicMock()
    database = AsyncMock()
    acquired = MagicMock(); acquired.scalar.return_value = True
    database.execute.return_value = acquired
    session.return_value.__aenter__ = AsyncMock(return_value=database)
    session.return_value.__aexit__ = AsyncMock(return_value=None)
    monkeypatch.setattr('database.AsyncSessionLocal', session)
    monkeypatch.setattr('reports_crud_api.generate_report', generator)
    await run_report_job(job_id, 'operator')
    await run_report_job(job_id, 'operator')
    assert store.read(job_id, 'operator')['status'] == 'completed'
    assert store.read(job_id, 'operator')['result'] == {'id': 'report'}
    generator.assert_awaited_once()


@pytest.mark.asyncio
async def test_running_job_resumes_after_worker_restart(tmp_path, monkeypatch):
    from report_jobs import run_report_job, current_report_job_id
    monkeypatch.setenv('REPORT_JOBS_DIR', str(tmp_path))
    job_id = str(uuid.uuid4())
    store = JobStore()
    job, _ = store.create(job_id, 'operator', {'inspection_id': 'example'})
    job['status'] = 'running'; store.write(job)
    database = AsyncMock()
    lock = MagicMock(); lock.scalar.return_value = True
    database.execute.return_value = lock
    session = MagicMock()
    session.return_value.__aenter__ = AsyncMock(return_value=database)
    session.return_value.__aexit__ = AsyncMock(return_value=None)
    async def generate(*args, **kwargs):
        assert current_report_job_id() == job_id
        return {'id': job_id}
    monkeypatch.setattr('database.AsyncSessionLocal', session)
    monkeypatch.setattr('reports_crud_api.generate_report', generate)
    await run_report_job(job_id, 'operator')
    assert store.read(job_id, 'operator')['status'] == 'completed'
    assert current_report_job_id() is None
