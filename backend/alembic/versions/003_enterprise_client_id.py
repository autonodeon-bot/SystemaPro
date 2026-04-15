"""enterprises.client_id — привязка предприятия к клиенту (доступ в портале).

Revision ID: 003
Revises: 002
Create Date: 2026-03-31
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    tbl = conn.execute(
        sa.text(
            "SELECT 1 FROM information_schema.tables "
            "WHERE table_schema = 'public' AND table_name = 'enterprises'"
        )
    )
    if not tbl.scalar():
        # Пустая/чужая БД — полная схема поднимается через create_all / старт API
        return
    r = conn.execute(
        sa.text(
            "SELECT 1 FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = 'enterprises' AND column_name = 'client_id'"
        )
    )
    if r.scalar():
        return
    op.add_column(
        "enterprises",
        sa.Column("client_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_enterprises_client_id_clients",
        "enterprises",
        "clients",
        ["client_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_enterprises_client_id", "enterprises", ["client_id"])


def downgrade() -> None:
    conn = op.get_bind()
    tbl = conn.execute(
        sa.text(
            "SELECT 1 FROM information_schema.tables "
            "WHERE table_schema = 'public' AND table_name = 'enterprises'"
        )
    )
    if not tbl.scalar():
        return
    col = conn.execute(
        sa.text(
            "SELECT 1 FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = 'enterprises' AND column_name = 'client_id'"
        )
    )
    if not col.scalar():
        return
    op.drop_index("ix_enterprises_client_id", table_name="enterprises")
    op.drop_constraint("fk_enterprises_client_id_clients", "enterprises", type_="foreignkey")
    op.drop_column("enterprises", "client_id")
