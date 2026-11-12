"""Resolve report identity and ownership from the same equipment as the inspection."""
from copy import deepcopy

from fastapi import HTTPException

from models import Assignment, Branch, Enterprise, Opo, Workshop


def _present(value):
    return value is not None and str(value).strip() not in ('', '-', '—', '–')


async def _hierarchy(db, workshop_id=None, branch_id=None, enterprise_id=None):
    workshop = await db.get(Workshop, workshop_id) if workshop_id else None
    branch_id = workshop.branch_id if workshop else branch_id
    branch = await db.get(Branch, branch_id) if branch_id else None
    enterprise_id = branch.enterprise_id if branch else enterprise_id
    enterprise = await db.get(Enterprise, enterprise_id) if enterprise_id else None
    return {'workshop': workshop, 'branch': branch, 'enterprise': enterprise}


async def resolve_report_object(db, equipment, data, assignment_id=None):
    if assignment_id:
        assignment = await db.get(Assignment, assignment_id)
        if assignment and assignment.equipment_id != equipment.id:
            raise HTTPException(409, 'Оборудование обследования не совпадает с оборудованием задания. Проверьте привязку чек-листа.')

    data = deepcopy(data) if isinstance(data, dict) else {}
    attrs = equipment.attributes if isinstance(equipment.attributes, dict) else {}
    hierarchy = await _hierarchy(db, getattr(equipment, 'workshop_id', None))
    warnings = []
    opo_info = None
    opo_id = getattr(equipment, 'opo_id', None)
    opo = await db.get(Opo, opo_id) if opo_id and data.get('include_opo_data') is not False else None
    if opo:
        opo_hierarchy = await _hierarchy(db, opo.workshop_id, opo.branch_id, opo.enterprise_id)
        conflict = any(
            hierarchy[level] and opo_hierarchy[level] and hierarchy[level].id != opo_hierarchy[level].id
            for level in hierarchy
        ) or any(
            getattr(opo, level + '_id', None) and opo_hierarchy[level]
            and getattr(opo, level + '_id') != opo_hierarchy[level].id
            for level in hierarchy
        )
        if conflict:
            warnings.append('Привязанное ОПО относится к другому подразделению. Его сведения исключены из отчёта. Проверьте ОПО в карточке оборудования.')
        else:
            opo_info = {key: getattr(opo, key, None) for key in
                        ('name', 'code', 'description', 'hazard_class', 'registration_number')}
            opo_info.update(id=str(opo.id), survey_data=opo.survey_data or {})
            for level, item in opo_hierarchy.items():
                opo_info[level + '_id'] = str(item.id) if item else None
                opo_info[level + '_name'] = item.name if item else None
                if hierarchy[level] is None:
                    hierarchy[level] = item

    # Remove only a stored copy explicitly tied to the rejected/excluded OPO.
    nested = data.get('opo') if isinstance(data.get('opo'), dict) else {}
    if opo_info is None and opo_id and str(opo_id) in (str(data.get('opo_id')), str(nested.get('id'))):
        for key in list(data):
            if key in ('opo', 'opo_info', 'opo_survey') or key.startswith('opo_'):
                data.pop(key)

    def value(*keys, fallback=None):
        for source in (data, attrs):
            for key in keys:
                if _present(source.get(key)):
                    return source[key]
                camel = ''.join(word.capitalize() if index else word for index, word in enumerate(key.split('_')))
                if _present(source.get(camel)):
                    return source[camel]
        return fallback

    workshop = hierarchy['workshop']
    location = value('location', 'equipment_location', fallback=equipment.location)
    if not _present(location):
        location = attrs.get('location_detail') or (workshop.name if workshop else None)
    if _present(location) and not _present(data.get('location')) and not _present(data.get('equipment_location')):
        data['location'] = location
    if not _present(value('organization', 'customer_name', 'enterprise_name')) and hierarchy['enterprise']:
        data['organization'] = hierarchy['enterprise'].name

    if opo_info:
        survey = opo_info['survey_data'] if isinstance(opo_info['survey_data'], dict) else {}
        for key in ('organization', 'executors'):
            if not _present(data.get(key)) and _present(survey.get(key)):
                data[key] = survey[key]
        documents = dict(data['documents']) if isinstance(data.get('documents'), dict) else {}
        survey_documents = survey.get('documents') if isinstance(survey.get('documents'), dict) else {}
        for key, flag in survey_documents.items():
            if str(key) in {str(n) for n in range(1, 10)} and str(key) not in documents:
                documents[str(key)] = flag
        data['documents'] = documents
        data['opo'] = opo_info
        data['opo_survey'] = survey
        data['opo_id'] = opo_info['id']
        for field, key in {'opo_name': 'name', 'opo_code': 'code', 'opo_hazard_class': 'hazard_class',
                           'opo_reg_number': 'registration_number', 'opo_description': 'description',
                           'opo_enterprise': 'enterprise_name', 'opo_branch': 'branch_name',
                           'opo_workshop': 'workshop_name'}.items():
            if not _present(data.get(field)) and _present(opo_info.get(key)):
                data[field] = opo_info[key]

    payload = {
        'id': str(equipment.id), 'equipment_code': getattr(equipment, 'equipment_code', None),
        'name': value('equipment_device_name', 'vessel_name', 'device_name', fallback=equipment.name),
        'serial_number': value('serial_number', 'factory_number', 'equipment_serial', fallback=equipment.serial_number),
        'location': location,
        'commissioning_date': str(equipment.commissioning_date) if equipment.commissioning_date else None,
        'attributes': attrs,
    }
    for level, item in hierarchy.items():
        payload[level + '_id'] = str(item.id) if item else None
        payload[level + '_name'] = item.name if item else None
    return {'equipment': payload, 'data': data, 'opo': opo_info, 'warnings': warnings}
