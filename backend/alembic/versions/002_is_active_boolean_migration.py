"""is_active: Integer/Smallint → Boolean (как в main._run_migrations).

Revision ID: 002
Revises: 001
Create Date: 2026-03-19
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

IS_ACTIVE_TABLES = (
    "equipment_types",
    "enterprises",
    "branches",
    "workshops",
    "opos",
    "equipment",
    "engineers",
    "certifications",
    "regulatory_documents",
    "users",
    "hierarchy_engineer_assignments",
    "report_templates",
    "verification_equipment",
)


def upgrade() -> None:
    conn = op.get_bind()
    for tbl in IS_ACTIVE_TABLES:
        r = conn.execute(
            sa.text(
                "SELECT data_type FROM information_schema.columns "
                "WHERE table_schema = 'public' AND table_name = :t "
                "AND column_name = 'is_active'"
            ),
            {"t": tbl},
        )
        row = r.fetchone()
        if not row:
            continue
        dtype = (row[0] or "").lower()
        if dtype in ("integer", "smallint", "bigint"):
            op.execute(
                sa.text(
                    f"ALTER TABLE {tbl} ALTER COLUMN is_active TYPE boolean "
                    "USING is_active::boolean"
                )
            )
            op.execute(
                sa.text(
                    f"ALTER TABLE {tbl} ALTER COLUMN is_active SET DEFAULT true"
                )
            )


def downgrade() -> None:
    # Откат типа is_active не выполняем: boolean-значения нельзя без потерь
    # однозначно сопоставить с прежними integer-семантиками.
    pass
