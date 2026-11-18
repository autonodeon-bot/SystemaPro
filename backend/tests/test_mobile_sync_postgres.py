"""Full ZIP → PostgreSQL round trip; isolated schema is rolled back after the test."""
import io
import json
import os
import uuid
import zipfile

import pytest
from fastapi import HTTPException, UploadFile
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from database import Base
from inspection_archive_api import upload_inspection_archive
from models import Assignment, AuditLog, Equipment, EquipmentType, Inspection, Report, User


def archive(payload):
    output=io.BytesIO()
    with zipfile.ZipFile(output,'w') as z:
        z.writestr('manifest.json',json.dumps({'version':1}))
        z.writestr('checklist.json',json.dumps(payload))
    output.seek(0)
    return UploadFile(output,filename='inspection.zip')


@pytest.mark.asyncio
async def test_mobile_autosave_sign_edit_retry_keeps_one_complete_inspection():
    url=os.getenv('TEST_DATABASE_URL')
    if not url:pytest.skip('TEST_DATABASE_URL required')
    engine=create_async_engine(url)
    try:
        async with engine.connect() as connection:
            transaction=await connection.begin()
            try:
                schema='test_mobile_sync_'+uuid.uuid4().hex
                await connection.execute(text(f'CREATE SCHEMA {schema}'))
                await connection.execute(text(f'SET LOCAL search_path TO {schema}'))
                await connection.run_sync(Base.metadata.create_all)
                async with AsyncSession(bind=connection,expire_on_commit=False,join_transaction_mode='create_savepoint') as db:
                    user=User(id=uuid.uuid4(),username='sync-test',password_hash='not-used',role='admin',is_active=True)
                    kind=EquipmentType(id=uuid.uuid4(),name='Сосуд',code='VESSEL')
                    db.add_all([user,kind]);await db.flush()
                    equipment=Equipment(id=uuid.uuid4(),type_id=kind.id,name='Сепаратор',attributes={})
                    db.add(equipment);await db.flush()
                    assignment=Assignment(id=uuid.uuid4(),equipment_id=equipment.id,assigned_to=user.id,assigned_by=user.id,assignment_type='DIAGNOSTICS',status='IN_PROGRESS')
                    db.add(assignment);await db.commit()
                    payload={'client_document_id':str(uuid.uuid4()),'equipment_id':str(equipment.id),'assignment_id':str(assignment.id),
                        'status':'DRAFT','date_performed':'2026-11-18T10:00:00Z','data':{
                            'report_form_id':'to-1','vessel_name':'Данные инженера','manufacturer':'Сохранённый завод',
                            'thickness_measurements':[{'point_number':'1','thickness':9.3}],
                            'additional_data':{'profile_values':{'shell_material':'09Г2С'}}}}
                    first=await upload_inspection_archive(archive(payload),'sync-test',db)
                    retry=await upload_inspection_archive(archive(payload),'sync-test',db)
                    assert retry['id']==first['id'] and retry['revision']==first['revision']
                    assert retry['status']=='already_received'
                    payload.update(inspection_id=first['id'],source_revision=first['revision'])
                    payload['data']['manufacturer']='Исправленный завод'
                    edited=await upload_inspection_archive(archive(payload),'sync-test',db)
                    payload.update(source_revision=edited['revision'],status='SIGNED')
                    signed=await upload_inspection_archive(archive(payload),'sync-test',db)
                    payload.update(source_revision=signed['revision'],status='DRAFT')
                    payload['data']['conclusion']='Дополнено после завершения'
                    corrected=await upload_inspection_archive(archive(payload),'sync-test',db)
                    assert corrected['id']==first['id']
                    assert await db.scalar(select(func.count()).select_from(Inspection))==1
                    saved=await db.get(Inspection,uuid.UUID(first['id']))
                    assert saved.data['manufacturer']=='Исправленный завод'
                    assert saved.data['thickness_measurements'][0]['thickness']==9.3
                    assert saved.data['additional_data']['profile_values']['shell_material']=='09Г2С'
                    legacy={**payload,'data':{'report_form_id':'to-1','vessel_name':'Пустой старый черновик'}}
                    for key in ['inspection_id','source_revision','client_document_id']:legacy.pop(key)
                    with pytest.raises(HTTPException) as error:
                        await upload_inspection_archive(archive(legacy),'sync-test',db)
                    assert error.value.status_code==409
                    assert await db.scalar(select(func.count()).select_from(Inspection))==1
                    db.add(Report(inspection_id=uuid.UUID(first['id']),report_type='TECHNICAL_REPORT',file_path='signed.pdf',is_signed=True))
                    await db.commit()
                    payload['source_revision']=corrected['revision']
                    payload['data']['manufacturer']='Не должно сохраниться'
                    with pytest.raises(HTTPException) as error:
                        await upload_inspection_archive(archive(payload),'sync-test',db)
                    assert error.value.status_code==409
                    assert (await db.get(Inspection,uuid.UUID(first['id']))).data['manufacturer']=='Исправленный завод'
                    assert await db.scalar(select(func.count()).select_from(AuditLog))==4
            finally:
                await transaction.rollback()
    finally:
        await engine.dispose()
