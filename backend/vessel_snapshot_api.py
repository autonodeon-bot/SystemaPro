"""Atomic, revision-checked constructor snapshots for browser and mobile clients."""
from copy import deepcopy
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from auth import verify_token
from database import get_db
from models import Inspection, Questionnaire
from equipment_crud_api import _authorize_equipment_write
from vessel_geometry_v2 import normalize_v2, render_v2
from vessel_snapshot_guard import guard_vessel_update
from vessel_vector import export_pdf

router = APIRouter()


def bind_plan(data, geo):
    """Add empty result slots; preserve every existing result including archived points."""
    data = deepcopy(data)
    owners = {e['id']: e for e in geo['parts'] + geo['elements']}
    rows = data.setdefault('thickness_measurements', [])
    known = {r.get('scheme_point_id') for r in rows}
    for p in geo['control_points']:
        if p.get('archived') or p['id'] in known: continue
        number = str(p.get('body_number') or p.get('local_number') or '')
        rows.append(dict(scheme_point_id=p['id'], location=owners[p['owner_id']]['designation'],
                         section_number=number, point_number=number, thickness=None,
                         nominal_thickness=None, min_allowed_thickness=None, photos=[]))
    rows = data.setdefault('weld_inspections', [])
    known = {(r.get('scheme_zone_id'), r.get('control_method')) for r in rows}
    welds = {w['id']: w for w in geo['welds']}
    codes = {'УЗК': 'UZK', 'МК': 'MPK', 'ПВК': 'PVK', 'ВИК': 'VIK', 'ТВ': 'TV'}
    for z in geo['control_zones']:
        if z.get('archived'): continue
        for method in z['planned_methods']:
            code = codes[method]
            if (z['id'], code) in known: continue
            rows.append(dict(scheme_zone_id=z['id'], weld_id=z['weld_id'],
                             model_revision=geo['revision'], weld_number=welds[z['weld_id']]['designation'],
                             control_method=code, result_status='planned'))
    profiles = data.setdefault('hardness_tests', [])
    for section in geo.get('sections', []):
        if section.get('method') != 'ТВ' or section.get('kind') != 'weld_profile': continue
        if any(r.get('section_profile_id') == section['id'] for r in profiles): continue
        profiles.append(dict(section_profile_id=section['id'],weld_id=section['owner_id'],
                             model_revision=geo['revision'],area_number=section['designation'],result_status='planned'))
    base = data.setdefault('base_vessel_scheme', {})
    existing = {p['id']: p for p in base.get('points', [])}
    for point in geo['control_points']:
        if point.get('archived'): continue
        existing.setdefault(point['id'], {}).update(id=point['id'],owner_id=point['owner_id'],
            number=str(point.get('body_number') or point.get('local_number')),control_type='uzt',
            element_name=owners[point['owner_id']]['designation'],model_revision=geo['revision'])
    base['points'] = list(existing.values())
    return data


async def get_inspection(db, ident, username, lock=False):
    row = await db.get(Inspection, ident)
    if row is None or row.is_deleted: raise HTTPException(404, 'Обследование не найдено')
    user = await _authorize_equipment_write(db, username, row.equipment_id)
    questionnaire = None
    # Same lock order as questionnaire editing, then inspection.
    if lock:
        if row.questionnaire_id:
            questionnaire = (await db.execute(select(Questionnaire).where(
                Questionnaire.id == row.questionnaire_id).with_for_update())).scalar_one_or_none()
        row = (await db.execute(select(Inspection).where(Inspection.id == ident)
                               .with_for_update().execution_options(populate_existing=True))).scalar_one()
    return row, questionnaire, user


@router.get('/api/vessel-scheme/inspections/{inspection_id}')
async def read_snapshot(inspection_id: UUID, username: str = Depends(verify_token), db: AsyncSession = Depends(get_db)):
    row, _, _ = await get_inspection(db, inspection_id, username)
    return {'inspection_id': str(row.id), 'data': row.data, 'status': row.status}


@router.put('/api/vessel-scheme/inspections/{inspection_id}')
async def save_snapshot(inspection_id: UUID, payload: dict, username: str = Depends(verify_token), db: AsyncSession = Depends(get_db)):
    if not isinstance(payload.get('geometry'),dict) or payload['geometry'].get('schema_version') != 2:
        raise HTTPException(400, 'Требуется объект geometry версии 2')
    row, questionnaire, user = await get_inspection(db, inspection_id, username, True)
    if row.status not in ('DRAFT', None):
        raise HTTPException(409, 'Редактирование доступно только для черновика обследования')
    old_data = row.data or {}
    old = (old_data.get('base_vessel_scheme') or {}).get('geometry') or {}
    incoming = deepcopy(old_data)
    incoming.setdefault('base_vessel_scheme', {})['geometry'] = payload.get('geometry')
    data = guard_vessel_update(old_data, incoming)
    geo = data['base_vessel_scheme']['geometry']
    if geo.get('schema_version') != 2: raise HTTPException(400, 'Требуется схема v2')
    if old.get('operation_id') and old.get('operation_id') == geo.get('operation_id'):
        return {'inspection_id': str(row.id), 'geometry': old, 'saved': True, 'replayed': True}
    if old and geo['revision'] <= old.get('revision', -1):
        raise HTTPException(409, 'Новая ревизия должна быть больше сохранённой')
    old_points = {p['id']: p for p in old.get('control_points', [])}
    new_points = {p['id']: p for p in geo['control_points']}
    for result in old_data.get('thickness_measurements', []):
        ident = result.get('scheme_point_id')
        if result.get('thickness') is None or ident not in old_points: continue
        if ident not in new_points: raise HTTPException(400, 'Точку с результатом можно архивировать, но нельзя удалить')
        before, after = old_points[ident], new_points[ident]
        if (before.get('placement') != after.get('placement') or before.get('owner_id') != after.get('owner_id')) and not any(h.get('entity_id') == ident and h.get('reason') and h.get('old_placement') == before.get('placement') for h in geo.get('revision_history', [])):
            raise HTTPException(400, 'Для переноса точки с результатом укажите причину')
    folder = Path('/app/uploads/vessel_snapshots') / str(inspection_id) / str(uuid4())
    folder.mkdir(parents=True, exist_ok=False)
    try:
        from vessel_sheet import sheet_spec
        spec=sheet_spec(geo)
        overview = folder / 'overview.png'
        overview.write_bytes(render_v2(geo, spec['width'], spec['height'])[0])
        views = [v for v in geo.get('views', []) if v.get('kind') not in ('part_detail', 'section_detail')]
        for part in geo['parts']:
            path = folder / f'{uuid4()}.png'
            path.write_bytes(render_v2(geo, spec['width'], spec['height'], detail=part['id'])[0])
            views.append(dict(id=str(uuid4()), kind='part_detail', part_id=part['id'],
                              designation=part['designation'], revision=geo['revision'],
                              document_number=f'vessel_detail_{part["id"]}', image_path=str(path)))
        geo['views'] = views
        (folder / 'drawing.pdf').write_bytes(export_pdf(geo))
        (folder / 'drawing.svg').write_bytes(render_v2(geo, spec['width'], spec['height'], svg=True)[0])
        data = bind_plan(data, geo)
        data['base_vessel_scheme'].update(source='constructor', geometry=geo, image_path=str(overview))
        data['control_scheme_image'] = str(overview)
        row.data, row.updated_by = data, user.id
        if questionnaire:
            questionnaire.data, questionnaire.updated_by = deepcopy(data), user.id
        await db.commit()
    except Exception:
        await db.rollback()
        # Only this request's newly created, UUID-scoped files can be removed.
        for file in folder.iterdir(): file.unlink()
        folder.rmdir()
        raise
    return {'inspection_id': str(row.id), 'geometry': geo, 'saved': True}
