"""Проверка начального наполнения на PostgreSQL в откатываемой тестовой схеме."""
import os
import uuid

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from experience_base_api import ARCHETYPE_SEED, ensure_experience_archetype_seed


@pytest.mark.asyncio
async def test_seed_postgres_is_repeatable_and_preserves_existing_content():
    database_url = os.getenv('TEST_DATABASE_URL')
    if not database_url:
        pytest.skip('Для интеграционной проверки нужен TEST_DATABASE_URL')
    engine = create_async_engine(database_url)
    try:
        async with engine.connect() as connection:
            transaction = await connection.begin()
            try:
                schema = f'test_experience_seed_{uuid.uuid4().hex}'
                await connection.execute(text(f'CREATE SCHEMA {schema}'))
                await connection.execute(text(f'SET LOCAL search_path TO {schema}'))
                for table in ('users', 'equipment', 'assignments'):
                    await connection.execute(text(f'CREATE TABLE {table} (id UUID PRIMARY KEY)'))
                async with AsyncSession(bind=connection, join_transaction_mode='create_savepoint') as session:
                    assert await ensure_experience_archetype_seed(session) == len(ARCHETYPE_SEED)
                    count = await session.scalar(text('SELECT count(*) FROM experience_base_entries'))
                    assert count == len(ARCHETYPE_SEED)
                    await session.execute(text("""
                        UPDATE experience_base_entries
                        SET title = 'Сохранённое название', body = 'Текст инженера', equipment_mark = NULL
                        WHERE equipment_kind = 'Ресивер'
                    """))
                    await session.commit()
                    assert await ensure_experience_archetype_seed(session) == len(ARCHETYPE_SEED)
                    assert await session.scalar(text('SELECT count(*) FROM experience_base_entries')) == count
                    saved = (await session.execute(text("""
                        SELECT title, body, equipment_mark FROM experience_base_entries
                        WHERE equipment_kind = 'Ресивер'
                    """))).one()
                    assert saved.title == 'Сохранённое название'
                    assert saved.body == 'Текст инженера'
                    assert saved.equipment_mark is None
                    assert await session.scalar(text("""
                        SELECT count(*) FROM experience_base_entries
                        WHERE category_code = 'srpd' AND equipment_mark = 'М-103А'
                    """)) == 1
            finally:
                await transaction.rollback()
    finally:
        await engine.dispose()
