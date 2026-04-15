"""inspections: soft-delete columns (is_deleted, deleted_at, deleted_by) — П.5.1

Revision ID: 004
Revises: 003
Create Date: 2026-04-07
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "004"
down_revision: Union[str, None] = "003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "inspections",
        sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "inspections",
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "inspections",
        sa.Column(
            "deleted_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id"),
            nullable=True,
        ),
    )
    op.create_index(
        "ix_inspections_is_deleted",
        "inspections",
        ["is_deleted"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_inspections_is_deleted", table_name="inspections")
    op.drop_column("inspections", "deleted_by")
    op.drop_column("inspections", "deleted_at")
    op.drop_column("inspections", "is_deleted")
