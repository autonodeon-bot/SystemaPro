"""Persistent status and idempotent submission for report generation jobs."""
import asyncio
import json
import os
import time
import uuid
from contextvars import ContextVar
from pathlib import Path

from fastapi import HTTPException

_progress = ContextVar('report_progress', default=None)
_job_id = ContextVar('report_job_id', default=None)
_limit = asyncio.Semaphore(2)
_recovery_tasks = set()


def current_report_job_id():
    return _job_id.get()


def recover_pending_report_jobs():
    store = JobStore()
    for path in store.root.glob('*/status.json'):
        try:
            job = json.loads(path.read_text(encoding='utf-8'))
            if job['status'] not in {'queued', 'running'}:
                continue
            task = asyncio.create_task(run_report_job(job['id'], job['owner']))
            _recovery_tasks.add(task)
            task.add_done_callback(_recovery_tasks.discard)
        except (ValueError, KeyError, OSError):
            continue


def report_stage(stage):
    callback = _progress.get()
    if callback:
        callback(stage)


class JobStore:
    def __init__(self, root=None):
        self.root = Path(root or os.getenv('REPORT_JOBS_DIR', '/app/reports/jobs'))

    def path(self, job_id):
        return self.root / str(uuid.UUID(str(job_id))) / 'status.json'

    def write(self, job):
        path = self.path(job['id'])
        temporary = path.with_name(f'{uuid.uuid4().hex}.tmp')
        temporary.write_text(json.dumps(job, ensure_ascii=False), encoding='utf-8')
        temporary.replace(path)

    def read(self, job_id, owner):
        try:
            job = json.loads(self.path(job_id).read_text(encoding='utf-8'))
        except (FileNotFoundError, ValueError):
            raise HTTPException(status_code=404, detail='Задание генерации не найдено')
        if job['owner'] != owner:
            raise HTTPException(status_code=403, detail='Нет доступа к этому заданию')
        return job

    def create(self, job_id, owner, request):
        path = self.path(job_id)
        try:
            path.parent.mkdir(parents=True, exist_ok=False)
        except FileExistsError:
            job = self.read(job_id, owner)
            if job['request'] != request:
                raise HTTPException(status_code=409, detail='Этот идентификатор уже используется для другого отчета')
            return job, False
        job = {'id': str(job_id), 'owner': owner, 'request': request, 'status': 'queued',
               'stage': 'В очереди', 'created_at': time.time(), 'updated_at': time.time(), 'result': None, 'error': None}
        self.write(job)
        return job, True


async def run_report_job(job_id, owner):
    from database import AsyncSessionLocal
    from reports_crud_api import generate_report
    store = JobStore()
    job = store.read(job_id, owner)
    if job['status'] not in {'queued', 'running'}:
        return
    from sqlalchemy import text
    async with _limit, AsyncSessionLocal() as lock_db:
        lock_key = int.from_bytes(uuid.UUID(job_id).bytes[:8], 'big', signed=True)
        acquired = await lock_db.execute(text('SELECT pg_try_advisory_xact_lock(:key)'), {'key': lock_key})
        if not acquired.scalar():
            return
        job = store.read(job_id, owner)
        if job['status'] not in {'queued', 'running'}:
            return
        job['status'] = 'running'
        def stage(label):
            job.update(stage=label, updated_at=time.time())
            store.write(job)
        token = _progress.set(stage)
        identity_token = _job_id.set(job_id)
        stage('Проверка и загрузка данных')
        try:
            async with AsyncSessionLocal() as db:
                job['result'] = await generate_report(job['request'], username=owner, db=db)
            job['status'] = 'completed'
            stage('Отчет готов')
        except Exception as exc:
            job['status'] = 'failed'
            job['error'] = str(exc.detail if isinstance(exc, HTTPException) else exc)
            stage('Ошибка генерации')
        finally:
            _progress.reset(token)
            _job_id.reset(identity_token)
