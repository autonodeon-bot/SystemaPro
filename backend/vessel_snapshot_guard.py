"""Protect an existing v2 snapshot during questionnaire JSON updates."""
from copy import deepcopy
from fastapi import HTTPException
from vessel_geometry_v2 import normalize_v2


def semantic_geometry(geo):
    value = normalize_v2(geo)
    value['views'] = [v for v in value.get('views', []) if v.get('kind') not in ('part_detail', 'section_detail')]
    return value


def guard_vessel_update(previous: dict, incoming: dict) -> dict:
    old = ((previous or {}).get('base_vessel_scheme') or {}).get('geometry') or {}
    new = ((incoming or {}).get('base_vessel_scheme') or {}).get('geometry') or {}
    if old.get('schema_version') == 2 and new.get('schema_version') != 2:
        raise HTTPException(409, detail={'code':'vessel_client_upgrade_required',
            'message':'Нужна новая версия конструктора; схема v2 не может быть удалена старым клиентом.'})
    if new.get('schema_version') != 2:
        return incoming
    try:
        normalized = normalize_v2(new)
    except (ValueError, KeyError, TypeError) as exc:
        raise HTTPException(400, detail=str(exc)) from exc
    if old.get('schema_version') == 2 and old != new:
        same_operation = new.get('operation_id') and new.get('operation_id') == old.get('operation_id')
        if same_operation:
            if semantic_geometry(old) != semantic_geometry(normalized):
                raise HTTPException(409, detail={'code':'vessel_operation_reused','message':'Операция уже записана с другим содержимым.'})
        elif new.get('base_revision') != old.get('revision') or new.get('model_id') != old.get('model_id'):
            raise HTTPException(409, detail={'code':'vessel_revision_conflict',
                'message':'Схема изменена другим клиентом. Сохраните локальный черновик и сравните версии.',
                'current_revision':old.get('revision'), 'current_geometry':old})
    result = deepcopy(incoming)
    result['base_vessel_scheme']['geometry'] = normalized
    return result
