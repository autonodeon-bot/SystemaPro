"""drawing_templates + drawing_template_points — шаблоны чертежей оборудования с точками замера (П.2 ТЗ 2026-04)

Revision ID: 005
Revises: 004
Create Date: 2026-04-19
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "005"
down_revision: Union[str, None] = "004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "drawing_templates",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("category", sa.String(100), nullable=True),
        sa.Column(
            "equipment_type_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("equipment_types.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "equipment_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("equipment.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("image_file_path", sa.String(500), nullable=False),
        sa.Column("image_width", sa.Integer(), nullable=True),
        sa.Column("image_height", sa.Integer(), nullable=True),
        sa.Column("mime_type", sa.String(100), nullable=True),
        sa.Column("file_size", sa.Integer(), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column(
            "created_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id"),
            nullable=True,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_drawing_templates_category", "drawing_templates", ["category"])
    op.create_index("ix_drawing_templates_equipment_type_id", "drawing_templates", ["equipment_type_id"])
    op.create_index("ix_drawing_templates_equipment_id", "drawing_templates", ["equipment_id"])
    op.create_index("ix_drawing_templates_is_active", "drawing_templates", ["is_active"])

    op.create_table(
        "drawing_template_points",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column(
            "template_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("drawing_templates.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("label", sa.String(50), nullable=False),
        sa.Column("point_type", sa.String(30), nullable=False, server_default="thickness"),
        sa.Column("x_percent", sa.Numeric(6, 3), nullable=False),
        sa.Column("y_percent", sa.Numeric(6, 3), nullable=False),
        sa.Column("expected_value", sa.Numeric(10, 3), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_drawing_template_points_template_id", "drawing_template_points", ["template_id"])


def downgrade() -> None:
    op.drop_index("ix_drawing_template_points_template_id", table_name="drawing_template_points")
    op.drop_table("drawing_template_points")
    op.drop_index("ix_drawing_templates_is_active", table_name="drawing_templates")
    op.drop_index("ix_drawing_templates_equipment_id", table_name="drawing_templates")
    op.drop_index("ix_drawing_templates_equipment_type_id", table_name="drawing_templates")
    op.drop_index("ix_drawing_templates_category", table_name="drawing_templates")
    op.drop_table("drawing_templates")
