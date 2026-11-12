"""Evidence-only preparation for vessel reports. No network calls or safety verdicts."""
import hashlib
import json
from decimal import Decimal, InvalidOperation
from collections import Counter

VERSION = 'vessel-preparation-2'


def number(value):
    if isinstance(value, bool) or value is None:
        return None
    try:
        result = Decimal(str(value).strip().replace(',', '.'))
        return result if result.is_finite() else None
    except InvalidOperation:
        return None


def present(value):
    return value is not None and str(value).strip() != ''


def prepare_vessel_report(inspection, equipment):
    data = inspection.get('data') or {}
    if not isinstance(data, dict):
        data = {}
    additional = data.get('additional_data')
    profile = additional.get('profile_values', {}) if isinstance(additional, dict) else {}
    profile = profile if isinstance(profile, dict) else {}
    attributes = equipment.get('attributes') or {}
    attributes = attributes if isinstance(attributes, dict) else {}
    source = {'version': VERSION, 'inspection': inspection, 'equipment': equipment}
    fingerprint = hashlib.sha256(json.dumps(source, ensure_ascii=False, sort_keys=True, default=str).encode()).hexdigest()
    findings, facts = [], []

    def issue(code, message, path, severity='warning'):
        findings.append({'code': code, 'message': message, 'source': path, 'severity': severity})

    def field(key, label, unit='', numeric=False):
        candidates = [(f'inspection.data.{key}', data.get(key)),
                      (f'inspection.data.additional_data.profile_values.{key}', profile.get(key)),
                      (f'equipment.{key}', equipment.get(key)),
                      (f'equipment.attributes.{key}', attributes.get(key))]
        values = [(path, value) for path, value in candidates if present(value)]
        if not values:
            issue('missing_'+key, f'Уточните поле «{label}».', candidates[0][0])
            return None
        path, value = values[0]
        normalized = [number(v) if numeric else str(v).strip() for _, v in values]
        if len(set(normalized)) > 1:
            details = '; '.join(f'{p}: {str(v)[:120]}' for p, v in values)
            issue('conflict_'+key, f'Поле «{label}» различается в источниках; значение исключено из черновика. {details}', path, 'error')
            return None
        if numeric and (number(value) is None or number(value) <= 0):
            issue('invalid_'+key, f'«{label}»: требуется положительное конечное число.', path, 'error')
            return None
        facts.append({'label': label, 'value': str(value)[:500], 'unit': unit, 'source': path})
        return number(value) if numeric else str(value)[:500]

    serial = field('serial_number', 'Заводской номер')
    working = field('working_pressure', 'Рабочее давление', 'МПа', True)
    design = field('design_pressure', 'Расчётное давление', 'МПа', True)
    field('volume', 'Объём', 'м³', True)
    field('wall_thickness', 'Номинальная толщина стенки', 'мм', True)
    if working is not None and design is not None and working > design:
        issue('pressure_conflict', 'Рабочее давление превышает указанное расчётное. Проверьте значения и единицы.',
              'inspection.data.working_pressure', 'error')
    raw_rows = data.get('thickness_measurements', [])
    if not isinstance(raw_rows, list):
        issue('invalid_rows', 'Измерения толщины должны быть списком.', 'inspection.data.thickness_measurements', 'error')
        raw_rows = []
    measured, pending, invalid, archived = [], 0, 0, 0
    scheme = data.get('base_vessel_scheme')
    geometry = scheme.get('geometry') if isinstance(scheme, dict) else None
    points = geometry.get('control_points', []) if isinstance(geometry, dict) else []
    archived_ids = {str(p['id']) for p in points if isinstance(p, dict) and p.get('archived') is True and p.get('id')} if isinstance(points, list) else set()
    identities = Counter(str(row['scheme_point_id']) for row in raw_rows
                         if isinstance(row, dict) and row.get('scheme_point_id')
                         and row.get('archived') is not True and str(row['scheme_point_id']) not in archived_ids)
    duplicate_rows = 0
    for index, row in enumerate(raw_rows):
        path = f'inspection.data.thickness_measurements.{index}'
        if not isinstance(row, dict):
            invalid += 1
            issue('invalid_row', f'Строка {index + 1}: неверный формат результата УЗТ.', path, 'error')
            continue
        if row.get('archived') is True or str(row.get('scheme_point_id')) in archived_ids:
            archived += 1
            continue
        identity = row.get('scheme_point_id')
        if identity and identities[str(identity)] > 1:
            duplicate_rows += 1
            issue('duplicate_point', f'Строка {index + 1}: идентификатор точки повторяется. Все строки этой точки исключены из сводки до сверки.', path, 'error')
            continue
        raw = row.get('thickness')
        if not present(raw):
            pending += 1
            continue
        value = number(raw)
        if value is None or value <= 0:
            invalid += 1
            issue('invalid_thickness', f'Строка {index + 1}: некорректная толщина.', path+'.thickness', 'error')
        else:
            measured.append(value)
    if not measured:
        issue('no_measurements', 'В таблице УЗТ нет положительных числовых результатов. Плановые точки не считаются измерениями.',
              'inspection.data.thickness_measurements')
    if pending:
        issue('pending_measurements', f'Не заполнены результаты в {pending} строках УЗТ.', 'inspection.data.thickness_measurements')
    # Older formats are intentionally not guessed or counted twice.
    if data.get('uzt_schemes') or data.get('thicknessMeasurements'):
        issue('other_measurements', 'Обнаружены дополнительные/старые таблицы УЗТ. Сверьте их вручную; сводка учитывает только thickness_measurements.',
              'inspection.data.uzt_schemes')
    documents = data.get('documents')
    marked_documents = sum(value is True for value in documents.values()) if isinstance(documents, dict) else 0
    if not marked_documents:
        issue('documents_unconfirmed', 'Нет отмеченных документов. Проверьте комплектность и наличие вложений.', 'inspection.data.documents')
    defects = data.get('defects')
    defect_count = len(defects) if isinstance(defects, list) else None
    issue('expert_review', 'Прочность, допустимость дефектов, остаточный ресурс и пригодность к эксплуатации оценивает инженер.',
          'inspection.data.calculation_data', 'info')
    stats = {'measured': len(measured), 'pending': pending, 'invalid': invalid, 'archived': archived, 'duplicate_rows': duplicate_rows,
             'minimum_mm': str(min(measured)) if measured else None,
             'maximum_mm': str(max(measured)) if measured else None}
    paragraphs = ['Рабочий черновик описательной части. Требует проверки инженером.']
    if serial:
        paragraphs.append(f'В исходных данных указан заводской номер: {serial}.')
    for fact in facts:
        if fact['label'] != 'Заводской номер':
            paragraphs.append(f"По исходным данным: {fact['label'].lower()} — {fact['value']} {fact['unit']}. [{fact['source']}]")
    if measured:
        paragraphs.append(f'В таблице УЗТ записано числовых результатов: {len(measured)}; диапазон {min(measured)}–{max(measured)} мм. '
                          'Это сводка введённых значений, без оценки допустимости. [inspection.data.thickness_measurements]')
    else:
        paragraphs.append('Числовые результаты УЗТ для сводки отсутствуют.')
    if defect_count is not None:
        paragraphs.append(f'В списке дефектов записей: {defect_count}. Пустой список не подтверждает отсутствие дефектов. [inspection.data.defects]')
    paragraphs.append('Заключение о техническом состоянии и условиях эксплуатации в этот черновик не включено.')
    return {'version': VERSION, 'inspection_id': inspection['id'], 'source_fingerprint': fingerprint,
            'mode': 'rules', 'llm_connected': False, 'facts': facts, 'findings': findings, 'measurements': stats,
            'draft_text': '\n\n'.join(paragraphs),
            'scope': 'Чек-лист и карточка оборудования. Содержимое сканов, фотографии и отдельные протоколы не анализируются.'}
