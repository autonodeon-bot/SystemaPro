"""Internal report preparation with access checks and stale-source protection."""
import hashlib
import io
import re
from datetime import datetime, timezone
from uuid import UUID
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from auth import verify_token
from database import get_db
from models import User, Inspection, Equipment, EquipmentType
from equipment_crud_api import _authorize_equipment_write
from observability import get_logger
from report_assistant import prepare_vessel_report

router = APIRouter(prefix='/api/report-assistant', tags=['reports'])
log = get_logger('report_assistant')


class ReviewedDraft(BaseModel):
    source_fingerprint: str = Field(pattern=r'^[a-f0-9]{64}$')
    text: str = Field(min_length=1, max_length=16000)
    confirmed: Literal[True]
    format: Literal['txt', 'docx'] = 'txt'


def word_draft(text, result):
    from docx import Document
    from docx.shared import Pt
    def clean(value):
        return re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', str(value))
    document = Document()
    document.styles['Normal'].font.name = 'Arial'
    document.styles['Normal'].font.size = Pt(11)
    document.add_heading('Рабочий черновик отчёта по сосуду', 0)
    document.sections[0].header.paragraphs[0].text = 'ЧЕРНОВИК • требует инженерной проверки'
    for line in text.splitlines():
        document.add_paragraph(clean(line))
    document.add_heading('Исходные факты для сверки', level=1)
    table = document.add_table(rows=1, cols=3)
    table.style = 'Table Grid'
    for cell, label in zip(table.rows[0].cells, ('Параметр', 'Значение', 'Источник')):
        cell.text = label
    for fact in result['facts']:
        cells = table.add_row().cells
        for cell, value in zip(cells, (fact['label'], f"{fact['value']} {fact['unit']}", fact['source'])):
            cell.text = clean(value)
    output = io.BytesIO()
    document.save(output)
    return output.getvalue()


async def load_source(inspection_id, username, db):
    user = (await db.execute(select(User).where(or_(User.username == username, User.email == username)))).scalar_one_or_none()
    if not user or not user.is_active:
        raise HTTPException(403, 'Учётная запись недоступна')
    if user.role not in {'admin', 'chief_operator', 'operator', 'engineer'}:
        raise HTTPException(403, 'Помощник доступен сотрудникам, готовящим отчёты')
    inspection = await db.get(Inspection, inspection_id)
    if inspection is None:
        raise HTTPException(404, 'Обследование не найдено')
    # Same equipment scope as mobile upload / constructor; additionally accept authorship.
    own = any(getattr(inspection, key, None) == user.id for key in ('created_by', 'performed_by', 'inspector_id'))
    if user.role == 'engineer' and not own:
        await _authorize_equipment_write(db, username, inspection.equipment_id)
    equipment = await db.get(Equipment, inspection.equipment_id)
    if equipment is None:
        raise HTTPException(404, 'Оборудование не найдено')
    kind = await db.get(EquipmentType, equipment.type_id) if equipment.type_id else None
    data = inspection.data if isinstance(inspection.data, dict) else {}
    code = str(getattr(kind, 'code', '') or '').upper()
    form = data.get('report_form_id')
    if form and form != 'to-1' or (code and code != 'VESSEL') or (not code and form != 'to-1'):
        raise HTTPException(422, 'Первый этап помощника поддерживает сосуды (форма ТО-1)')
    source_inspection = {key: getattr(inspection, key, None) for key in ('id', 'data', 'status', 'date_performed', 'conclusion')}
    source_inspection['id'] = str(inspection.id)
    source_equipment = {key: getattr(equipment, key, None) for key in ('id', 'name', 'serial_number', 'attributes', 'type_id')}
    return user, prepare_vessel_report(source_inspection, source_equipment)


@router.get('/inspections/{inspection_id}')
async def analyze(inspection_id: UUID, response: Response, username: str = Depends(verify_token), db: AsyncSession = Depends(get_db)):
    _, result = await load_source(inspection_id, username, db)
    response.headers['Cache-Control'] = 'no-store'
    return result


@router.post('/inspections/{inspection_id}/export')
async def export_draft(inspection_id: UUID, payload: ReviewedDraft, username: str = Depends(verify_token), db: AsyncSession = Depends(get_db)):
    user, result = await load_source(inspection_id, username, db)
    if result['source_fingerprint'] != payload.source_fingerprint:
        raise HTTPException(409, 'Исходные данные изменились. Обновите проверку и заново проверьте черновик.')
    if not payload.text.strip():
        raise HTTPException(422, 'Черновик не должен быть пустым')
    now = datetime.now(timezone.utc).isoformat()
    text = '\n'.join(['РАБОЧИЙ ЧЕРНОВИК — НЕ ЗАКЛЮЧЕНИЕ И НЕ ПОДПИСАННЫЙ ОТЧЁТ',
                      f'Обследование: {inspection_id}', f'Выгружено: {now}', f'Текст проверил: {user.username}',
                      f"Снимок данных: {result['source_fingerprint']}", '', payload.text, '', 'Замечания автоматической проверки:',
                      *[f"- {item['message']} [{item['source']}]" for item in result['findings']]])
    log.info('Draft exported: inspection_id={} user_id={} source_hash={} text_hash={}', str(inspection_id), str(user.id),
             result['source_fingerprint'], hashlib.sha256(payload.text.encode()).hexdigest())
    if payload.format == 'docx':
        return Response(word_draft(text, result), media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                        headers={'Content-Disposition': f'attachment; filename="vessel-draft-{inspection_id}.docx"', 'Cache-Control': 'no-store'})
    return Response(text.encode('utf-8-sig'), media_type='text/plain; charset=utf-8',
                    headers={'Content-Disposition': f'attachment; filename="vessel-draft-{inspection_id}.txt"', 'Cache-Control': 'no-store'})
