"""Начальная схема: все таблицы из models (идемпотентно).

Revision ID: 001
Revises:
Create Date: 2026-03-19

Для уже существующих БД `create_all(checkfirst=True)` не трогает таблицы.
"""
from typing import Sequence, Union

from alembic import op

from database import Base

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    import models  # noqa: F401 — все модели в metadata

    bind = op.get_bind()
    Base.metadata.create_all(bind=bind, checkfirst=True)


def downgrade() -> None:
    import models  # noqa: F401

    bind = op.get_bind()
    Base.metadata.drop_all(bind=bind, checkfirst=True)
