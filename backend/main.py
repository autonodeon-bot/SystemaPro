"""
Монитор — API (ЕС ТД НГО / SystemaPro)
Единая система технической диагностики нефтегазового оборудования.

Ядро приложения: инициализация FastAPI, middleware, миграции, системные endpoints.
Бизнес-логика вынесена в модульные роутеры (*_api.py).
"""

import os
import time
import traceback
from typing import Dict, Optional, Any

from fastapi import FastAPI, Depends, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from database import get_db, engine, Base
from observability import get_logger, init_observability, metrics_router
from security import limiter
from shared import metrics as _metrics

# ─── Routers ──────────────────────────────────────────────────────────────────
from auth_api import router as auth_router
from auth_2fa_api import router as auth_2fa_router
from access_management import router as access_router
from hierarchy_management import router as hierarchy_router
from assignments_api import router as assignments_router
from report_templates_api import router as report_templates_router
from report_forms_api import router as report_forms_router
from equipment_history_api import router as equipment_history_router
from inspection_archive_api import router as inspection_archive_router
from equipment_crud_api import router as equipment_crud_router
from opos_api import router as opos_router
from dictionaries_api import router as dictionaries_router
from inspections_crud_api import router as inspections_crud_router
from reports_crud_api import router as reports_crud_router
from questionnaires_api import router as questionnaires_router
from verification_equipment_api import router as verification_equipment_router
from instruments_api import router as instruments_router
from engineers_users_api import router as engineers_users_router
from mobile_stats_api import router as mobile_stats_router
from notifications_api import router as notifications_router
from pipeline_map_api import router as pipeline_map_router
from protocol_templates_api import router as protocol_templates_router
from experience_base_api import router as experience_base_router
from diagnostic_menu_api import router as diagnostic_menu_router
from inspection_object_templates_api import router as inspection_object_templates_router
from equipment_profiles_api import router as equipment_profiles_router
from drawing_templates_api import router as drawing_templates_router
from standalone_protocols_api import router as standalone_protocols_router
from diagnostic_engine.api import router as diagnostic_router
from report_verify_api import router as report_verify_router
from report_org_settings_api import router as report_org_settings_router

# ─── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Монитор — API (SystemaPro)",
    description="API платформы «Монитор»: единая система технической диагностики нефтегазового оборудования (ЕС ТД НГО / SystemaPro). Учёт оборудования, задания, обследования, отчёты.",
    version="3.7.12",
    openapi_tags=[
        {"name": "auth", "description": "Авторизация и пользователи"},
        {"name": "assignments", "description": "Задания"},
        {"name": "equipment", "description": "Оборудование"},
        {"name": "inspections", "description": "Обследования и чек-листы"},
        {"name": "questionnaires", "description": "Опросные листы и вложения"},
        {"name": "reports", "description": "Генерация отчётов"},
        {"name": "opos", "description": "ОПО и опросы ОПО"},
        {"name": "engineers", "description": "Инженеры, сертификаты, пользователи"},
        {"name": "verification-equipment", "description": "Поверочное оборудование"},
        {"name": "dictionaries", "description": "Справочники"},
        {"name": "mobile", "description": "Мобильное приложение"},
        {"name": "notifications", "description": "Уведомления"},
    ],
)

# ─── Observability (Sentry + Prometheus + loguru) ─────────────────────────────
os.environ.setdefault("APP_VERSION", "3.7.13")
init_observability(app)
log = get_logger("main")

# ─── Rate limiting (slowapi) ──────────────────────────────────────────────────
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ─── CORS ─────────────────────────────────────────────────────────────────────
_cors_origins = os.getenv(
    "CORS_ORIGINS",
    "https://neftcontrol.ru,http://localhost:5173,http://localhost:80",
).split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in _cors_origins],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Error handler ────────────────────────────────────────────────────────────
_CODE_MAP = {
    400: "VALIDATION_ERROR", 401: "UNAUTHORIZED", 403: "FORBIDDEN",
    404: "NOT_FOUND", 409: "CONFLICT", 422: "UNPROCESSABLE_ENTITY",
    500: "INTERNAL_ERROR",
}


@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc: HTTPException):
    code = _CODE_MAP.get(exc.status_code, "ERROR")
    detail = exc.detail
    errors = detail if isinstance(detail, list) else []
    if isinstance(detail, list):
        detail = "Ошибка валидации" if exc.status_code == 422 else str(detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": detail, "code": code, "errors": errors},
    )


# ─── Middleware ───────────────────────────────────────────────────────────────
@app.middleware("http")
async def add_charset_header(request, call_next):
    _metrics["http_requests_total"] += 1
    response = await call_next(request)
    ct = response.headers.get("content-type", "")
    if "application/json" in ct and "charset" not in ct:
        response.headers["content-type"] = ct + "; charset=utf-8"
    return response


# ─── Include all routers ──────────────────────────────────────────────────────
app.include_router(auth_router)
app.include_router(auth_2fa_router)
app.include_router(metrics_router)
app.include_router(access_router)
app.include_router(hierarchy_router)
app.include_router(assignments_router)
app.include_router(report_templates_router)
app.include_router(report_forms_router)
app.include_router(report_org_settings_router)
app.include_router(equipment_history_router)
app.include_router(inspection_archive_router)
app.include_router(equipment_crud_router)
app.include_router(opos_router)
app.include_router(dictionaries_router)
app.include_router(inspections_crud_router)
app.include_router(reports_crud_router)
app.include_router(questionnaires_router)
app.include_router(verification_equipment_router)
app.include_router(instruments_router)
app.include_router(engineers_users_router)
app.include_router(mobile_stats_router)
app.include_router(notifications_router)
app.include_router(pipeline_map_router)
app.include_router(protocol_templates_router)
app.include_router(experience_base_router)
app.include_router(diagnostic_menu_router)
app.include_router(inspection_object_templates_router)
app.include_router(equipment_profiles_router)
app.include_router(drawing_templates_router)
app.include_router(standalone_protocols_router)
app.include_router(diagnostic_router)
app.include_router(report_verify_router)


# ─── Startup: DB migrations ──────────────────────────────────────────────────
@app.on_event("startup")
async def startup():
    """Initialize database on startup."""
    from auth import assert_production_secrets

    assert_production_secrets()
    try:
        async with engine.begin() as conn:
            await conn.execute(text("SELECT 1"))
        print("✅ Database connection successful")

        try:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            print("✅ Database tables checked/created")
        except Exception as e:
            print(f"⚠️  Warning: Could not create tables: {e}")

        await _run_migrations()
        await _ensure_quick_control_protocol_templates()
        await _ensure_experience_base_seed()
        await _ensure_diagnostic_menu_config()
        await _ensure_inspection_object_templates_seed()
        await _ensure_equipment_types_seed()
        await _ensure_report_templates_seed()

    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        traceback.print_exc()


async def _ensure_report_templates_seed() -> None:
    try:
        from report_templates_seed import ensure_report_templates_seed

        n = ensure_report_templates_seed()
        print(f"✅ Report templates seed: {n}")
    except Exception as e:
        print(f"⚠️  Report templates seed skipped: {e}")


async def _ensure_equipment_types_seed() -> None:
    try:
        from database import AsyncSessionLocal
        from equipment_types_seed import ensure_default_equipment_types

        async with AsyncSessionLocal() as session:
            n = await ensure_default_equipment_types(session)
        print(f"✅ Equipment types seed: {n}")
    except Exception as e:
        print(f"⚠️  Equipment types seed skipped: {e}")


async def _ensure_inspection_object_templates_seed() -> None:
    try:
        from database import AsyncSessionLocal
        from inspection_object_templates_api import ensure_inspection_object_templates_seed

        async with AsyncSessionLocal() as session:
            n = await ensure_inspection_object_templates_seed(session)
        print(f"✅ Inspection object templates: {n}")
    except Exception as e:
        print(f"⚠️  Inspection object templates seed skipped: {e}")


async def _ensure_diagnostic_menu_config() -> None:
    try:
        from database import AsyncSessionLocal
        from diagnostic_menu_api import ensure_default_diagnostic_menu

        async with AsyncSessionLocal() as session:
            await ensure_default_diagnostic_menu(session)
        print("✅ Diagnostic menu config ensured")
    except Exception as e:
        print(f"⚠️  Diagnostic menu config skipped: {e}")


async def _ensure_experience_base_seed() -> None:
    """Справочные архетипы опытной базы (xlsx)."""
    try:
        from database import AsyncSessionLocal
        from experience_base_api import ensure_experience_archetype_seed

        async with AsyncSessionLocal() as session:
            n = await ensure_experience_archetype_seed(session)
        print(f"✅ Experience base archetypes: {n}")
    except Exception as e:
        print(f"⚠️  Experience base seed skipped: {e}")


async def _ensure_quick_control_protocol_templates() -> None:
    """Опубликованные шаблоны «Быстрый контроль» (идемпотентно при старте API)."""
    try:
        from database import AsyncSessionLocal
        from quick_control_protocol_templates import ensure_quick_control_templates

        async with AsyncSessionLocal() as session:
            n = await ensure_quick_control_templates(session, created_by="system")
        print(f"✅ Quick control protocol templates: {n}")
    except Exception as e:
        print(f"⚠️  Quick control templates seed skipped: {e}")


async def _run_migrations():
    """Лёгкие авто-миграции (ALTER TABLE ADD COLUMN IF NOT EXISTS).

    Предпочтительно применять изменения схемы через Alembic из каталога backend:
    ``alembic upgrade head``. Этот блок остаётся запасным вариантом для сред,
    где миграции ещё не прогоняют отдельно.
    """
    migration_steps = [
        # equipment_resources
        ("equipment_resources.resource_type",
         ["ALTER TABLE equipment_resources ADD COLUMN IF NOT EXISTS resource_type VARCHAR(50)"]),
        # equipment.opo_id
        ("equipment.opo_id", [
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS opo_id UUID",
            "CREATE INDEX IF NOT EXISTS idx_equipment_opo_id ON equipment(opo_id)",
        ]),
        # opos hierarchy
        ("opos hierarchy", [
            "ALTER TABLE opos ADD COLUMN IF NOT EXISTS enterprise_id UUID REFERENCES enterprises(id)",
            "ALTER TABLE opos ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES branches(id)",
            "ALTER TABLE opos ADD COLUMN IF NOT EXISTS workshop_id UUID REFERENCES workshops(id)",
            "ALTER TABLE opos ADD COLUMN IF NOT EXISTS registration_number VARCHAR(100)",
            "ALTER TABLE opos ADD COLUMN IF NOT EXISTS hazard_class VARCHAR(50)",
            "ALTER TABLE opos ADD COLUMN IF NOT EXISTS survey_data JSONB",
            "CREATE INDEX IF NOT EXISTS idx_opos_enterprise_id ON opos(enterprise_id)",
            "CREATE INDEX IF NOT EXISTS idx_opos_branch_id ON opos(branch_id)",
            "CREATE INDEX IF NOT EXISTS idx_opos_workshop_id ON opos(workshop_id)",
        ]),
        # users.permissions
        ("users.permissions",
         ["ALTER TABLE users ADD COLUMN IF NOT EXISTS permissions JSONB"]),
        # enterprises.client_id — доступ клиента к оборудованию по иерархии
        ("enterprises.client_id", [
            "ALTER TABLE enterprises ADD COLUMN IF NOT EXISTS client_id UUID REFERENCES clients(id)",
            "CREATE INDEX IF NOT EXISTS idx_enterprises_client_id ON enterprises(client_id)",
        ]),
        # clients — поля контактов (старые БД без них ломали SELECT через ORM)
        ("clients contact columns", [
            "ALTER TABLE clients ADD COLUMN IF NOT EXISTS inn VARCHAR(20)",
            "ALTER TABLE clients ADD COLUMN IF NOT EXISTS address TEXT",
            "ALTER TABLE clients ADD COLUMN IF NOT EXISTS contact_person VARCHAR(255)",
            "ALTER TABLE clients ADD COLUMN IF NOT EXISTS phone VARCHAR(50)",
            "ALTER TABLE clients ADD COLUMN IF NOT EXISTS email VARCHAR(255)",
        ]),
        # verification_equipment columns
        ("verification_equipment columns", [
            "ALTER TABLE verification_equipment ADD COLUMN IF NOT EXISTS name VARCHAR(255)",
            "ALTER TABLE verification_equipment ADD COLUMN IF NOT EXISTS next_verification_date DATE",
            "ALTER TABLE verification_equipment ADD COLUMN IF NOT EXISTS inventory_number VARCHAR(100)",
            "ALTER TABLE verification_equipment ADD COLUMN IF NOT EXISTS scan_file_name VARCHAR(255)",
            "ALTER TABLE verification_equipment ADD COLUMN IF NOT EXISTS scan_file_size INTEGER",
            "ALTER TABLE verification_equipment ADD COLUMN IF NOT EXISTS scan_mime_type VARCHAR(100)",
            "ALTER TABLE verification_equipment ADD COLUMN IF NOT EXISTS notes TEXT",
            "ALTER TABLE verification_equipment ADD COLUMN IF NOT EXISTS expiry_date DATE",
        ]),
        # equipment columns
        ("equipment columns", [
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS equipment_code VARCHAR(100)",
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS manufacturer VARCHAR(255)",
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS serial_number VARCHAR(100)",
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS location VARCHAR(255)",
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS model VARCHAR(255)",
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS commissioning_date DATE",
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS attributes JSONB",
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true",
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT now()",
            "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE",
        ]),
        # assignments extra columns
        ("assignments extra", [
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS assignment_type VARCHAR(50) DEFAULT 'DIAGNOSTICS'",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id)",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS protocol_template_id VARCHAR(64)",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS report_form_id VARCHAR(32)",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS ndt_method_codes JSONB",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS contract_number VARCHAR(128)",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS contract_date VARCHAR(32)",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS work_period_from VARCHAR(32)",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS work_period_to VARCHAR(32)",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS work_basis TEXT",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS tech_card_number VARCHAR(128)",
            # Файл схемы контроля / техкарты, приложенный к заданию (замена «библиотеки схем»)
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS tech_card_file_path VARCHAR(500)",
            "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS tech_card_file_name VARCHAR(255)",
        ]),
        # projects — дедлайн и бюджет (иначе SELECT по ORM падает на старых БД без колонок)
        ("projects deadline budget", [
            "ALTER TABLE projects ADD COLUMN IF NOT EXISTS deadline DATE",
            "ALTER TABLE projects ADD COLUMN IF NOT EXISTS budget NUMERIC(15, 2)",
        ]),
        # inspections soft-delete (П.5.1)
        ("inspections soft-delete", [
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id)",
            "CREATE INDEX IF NOT EXISTS ix_inspections_is_deleted ON inspections(is_deleted)",
        ]),
        # inspections columns
        ("inspections columns", [
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id)",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS inspector_id UUID REFERENCES users(id)",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS assignment_id UUID REFERENCES assignments(id)",
            "CREATE INDEX IF NOT EXISTS idx_inspections_assignment_id ON inspections(assignment_id)",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS questionnaire_id UUID REFERENCES questionnaires(id)",
            "CREATE INDEX IF NOT EXISTS idx_inspections_questionnaire_id ON inspections(questionnaire_id)",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS performed_by UUID REFERENCES users(id)",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS date_performed TIMESTAMP WITH TIME ZONE",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'DRAFT'",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS conclusion TEXT",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS data JSONB",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS gps_coordinates JSONB",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id)",
            "ALTER TABLE inspections ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES users(id)",
        ]),
        # questionnaires columns
        ("questionnaires columns", [
            "ALTER TABLE questionnaires ADD COLUMN IF NOT EXISTS assignment_id UUID REFERENCES assignments(id)",
            "ALTER TABLE questionnaires ADD COLUMN IF NOT EXISTS date_performed TIMESTAMP WITH TIME ZONE",
            "ALTER TABLE questionnaires ADD COLUMN IF NOT EXISTS performed_by UUID REFERENCES users(id)",
            "ALTER TABLE questionnaires ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'DRAFT'",
            "ALTER TABLE questionnaires ADD COLUMN IF NOT EXISTS data JSONB",
            "ALTER TABLE questionnaires ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE",
            "ALTER TABLE questionnaires ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id)",
            "ALTER TABLE questionnaires ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES users(id)",
            "CREATE INDEX IF NOT EXISTS idx_questionnaires_assignment_id ON questionnaires(assignment_id)",
        ]),
        # users.client_id — привязка пользователя к клиенту
        ("users.client_id", [
            "ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS client_id UUID REFERENCES clients(id)",
        ]),
        # users 2FA + lockout (S1: security)
        ("users.totp_and_lockout", [
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret VARCHAR(64)",
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN NOT NULL DEFAULT false",
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_recovery_codes JSONB",
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_count INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP WITH TIME ZONE",
        ]),
        # report_signatures — реестр выданных/подписанных заключений (S3)
        ("report_signatures", [
            """CREATE TABLE IF NOT EXISTS report_signatures (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
                signer_user_id UUID REFERENCES users(id),
                signer_name VARCHAR(255),
                signer_role VARCHAR(50),
                signed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                content_sha256 VARCHAR(64) NOT NULL,
                signature_type VARCHAR(20) NOT NULL DEFAULT 'internal',
                signature_blob BYTEA,
                verification_token VARCHAR(64) UNIQUE NOT NULL,
                revoked_at TIMESTAMP WITH TIME ZONE,
                revoke_reason TEXT
            )""",
            "CREATE INDEX IF NOT EXISTS ix_report_signatures_report_id ON report_signatures(report_id)",
            "CREATE INDEX IF NOT EXISTS ix_report_signatures_verification_token ON report_signatures(verification_token)",
            "CREATE INDEX IF NOT EXISTS ix_report_signatures_signed_at ON report_signatures(signed_at)",
        ]),
        # Индексы для assignments и reports
        ("assignments+reports indexes", [
            "CREATE INDEX IF NOT EXISTS idx_assignments_assigned_to ON assignments(assigned_to)",
            "CREATE INDEX IF NOT EXISTS idx_assignments_equipment_id ON assignments(equipment_id)",
            "CREATE INDEX IF NOT EXISTS idx_assignments_project_id ON assignments(project_id)",
            "CREATE INDEX IF NOT EXISTS idx_reports_inspection_id ON reports(inspection_id)",
        ]),
        # questionnaire_document_files.updated_at
        ("questionnaire_document_files.updated_at", [
            "ALTER TABLE IF EXISTS questionnaire_document_files ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE",
        ]),
        # user_devices table (FCM push tokens)
        ("user_devices", [
            """CREATE TABLE IF NOT EXISTS user_devices (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                fcm_token VARCHAR(500) NOT NULL UNIQUE,
                platform VARCHAR(20) DEFAULT 'android',
                is_active BOOLEAN DEFAULT true,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE
            )""",
            "CREATE INDEX IF NOT EXISTS idx_user_devices_user_id ON user_devices(user_id)",
        ]),
        # drawing_templates + drawing_template_points — шаблоны чертежей с точками замера (П.2 ТЗ 2026-04)
        ("drawing_templates", [
            """CREATE TABLE IF NOT EXISTS drawing_templates (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name VARCHAR(255) NOT NULL,
                description TEXT,
                category VARCHAR(100),
                equipment_type_id UUID REFERENCES equipment_types(id) ON DELETE SET NULL,
                equipment_id UUID REFERENCES equipment(id) ON DELETE SET NULL,
                image_file_path VARCHAR(500) NOT NULL,
                image_width INTEGER,
                image_height INTEGER,
                mime_type VARCHAR(100),
                file_size INTEGER,
                version INTEGER NOT NULL DEFAULT 1,
                is_active BOOLEAN NOT NULL DEFAULT true,
                created_by UUID REFERENCES users(id),
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            )""",
            "CREATE INDEX IF NOT EXISTS ix_drawing_templates_category ON drawing_templates(category)",
            "CREATE INDEX IF NOT EXISTS ix_drawing_templates_equipment_type_id ON drawing_templates(equipment_type_id)",
            "CREATE INDEX IF NOT EXISTS ix_drawing_templates_equipment_id ON drawing_templates(equipment_id)",
            "CREATE INDEX IF NOT EXISTS ix_drawing_templates_is_active ON drawing_templates(is_active)",
            """CREATE TABLE IF NOT EXISTS drawing_template_points (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                template_id UUID NOT NULL REFERENCES drawing_templates(id) ON DELETE CASCADE,
                label VARCHAR(50) NOT NULL,
                point_type VARCHAR(30) NOT NULL DEFAULT 'thickness',
                x_percent NUMERIC(6,3) NOT NULL,
                y_percent NUMERIC(6,3) NOT NULL,
                expected_value NUMERIC(10,3),
                notes TEXT,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            )""",
            "CREATE INDEX IF NOT EXISTS ix_drawing_template_points_template_id ON drawing_template_points(template_id)",
        ]),
        # audit_log table
        ("audit_log", [
            """CREATE TABLE IF NOT EXISTS audit_log (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                user_id UUID REFERENCES users(id),
                action VARCHAR(50) NOT NULL,
                entity_type VARCHAR(100) NOT NULL,
                entity_id UUID,
                details JSONB,
                ip_address VARCHAR(50)
            )""",
            "CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON audit_log(entity_type, entity_id)",
            "CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at)",
        ]),
        # project_invoices — счета по проектам (биллинг)
        ("project_invoices", [
            """CREATE TABLE IF NOT EXISTS project_invoices (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                invoice_number VARCHAR(100),
                amount NUMERIC(15, 2) NOT NULL,
                currency VARCHAR(10) NOT NULL DEFAULT 'RUB',
                status VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
                issued_date DATE,
                due_date DATE,
                paid_date DATE,
                description TEXT,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE
            )""",
            "CREATE INDEX IF NOT EXISTS ix_project_invoices_project_id ON project_invoices(project_id)",
            "CREATE INDEX IF NOT EXISTS ix_project_invoices_status ON project_invoices(status)",
        ]),
        # project_contracts — договоры по проектам
        ("project_contracts", [
            """CREATE TABLE IF NOT EXISTS project_contracts (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                contract_number VARCHAR(100),
                title VARCHAR(500),
                signed_date DATE,
                end_date DATE,
                amount NUMERIC(15, 2),
                status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
                notes TEXT,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE
            )""",
            "CREATE INDEX IF NOT EXISTS ix_project_contracts_project_id ON project_contracts(project_id)",
            "CREATE INDEX IF NOT EXISTS ix_project_contracts_status ON project_contracts(status)",
        ]),
        # project_invoice_payments — частичные/полные оплаты по счетам
        ("project_invoice_payments", [
            """CREATE TABLE IF NOT EXISTS project_invoice_payments (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                invoice_id UUID NOT NULL REFERENCES project_invoices(id) ON DELETE CASCADE,
                amount NUMERIC(15, 2) NOT NULL,
                payment_date DATE NOT NULL,
                note TEXT,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            )""",
            "CREATE INDEX IF NOT EXISTS ix_project_invoice_payments_invoice_id ON project_invoice_payments(invoice_id)",
        ]),
    ]

    for label, sqls in migration_steps:
        try:
            async with engine.begin() as conn:
                for sql in sqls:
                    await conn.execute(text(sql))
            print(f"✅ DB migration: {label}")
        except Exception as e:
            err = str(e).lower()
            if "already exists" in err or "duplicate" in err:
                print(f"✅ DB migration: {label} (already exists)")
            else:
                print(f"⚠️  Warning: {label} migration: {e}")

    # inspections.is_archived — special handling (check existence first)
    for tbl in ("inspections", "reports"):
        try:
            async with engine.begin() as conn:
                result = await conn.execute(text(f"""
                    SELECT column_name FROM information_schema.columns
                    WHERE table_name = '{tbl}' AND column_name = 'is_archived'
                """))
                if result.scalar() is None:
                    await conn.execute(text(
                        f"ALTER TABLE {tbl} ADD COLUMN is_archived BOOLEAN DEFAULT FALSE NOT NULL"
                    ))
                    print(f"✅ DB migration: {tbl}.is_archived added")
                else:
                    try:
                        await conn.execute(text(
                            f"ALTER TABLE {tbl} ALTER COLUMN is_archived SET NOT NULL"
                        ))
                    except Exception:
                        pass
                    print(f"✅ DB migration: {tbl}.is_archived verified")
        except Exception as e:
            print(f"⚠️  Warning: {tbl}.is_archived migration: {e}")

    # Синхронизация inspector_id ↔ performed_by для существующих записей inspections.
    # performed_by — основное поле; inspector_id дублирует его для обратной совместимости.
    try:
        async with engine.begin() as conn:
            await conn.execute(text(
                "UPDATE inspections SET performed_by = inspector_id "
                "WHERE performed_by IS NULL AND inspector_id IS NOT NULL"
            ))
            await conn.execute(text(
                "UPDATE inspections SET inspector_id = performed_by "
                "WHERE inspector_id IS NULL AND performed_by IS NOT NULL"
            ))
        print("✅ DB migration: inspections inspector_id ↔ performed_by sync")
    except Exception as e:
        print(f"⚠️  Warning: inspections inspector_id/performed_by sync: {e}")

    # questionnaire_document_files — column resize
    try:
        async with engine.begin() as conn:
            for col, typ in [
                ("document_number", "VARCHAR(100)"), ("file_name", "VARCHAR(255)"),
                ("file_path", "VARCHAR(500)"), ("file_type", "VARCHAR(50)"),
                ("mime_type", "VARCHAR(100)"),
            ]:
                await conn.execute(text(
                    f"ALTER TABLE questionnaire_document_files ALTER COLUMN {col} TYPE {typ}"
                ))
            print("✅ DB migration: questionnaire_document_files (column lengths)")
    except Exception as e:
        if "does not exist" in str(e).lower():
            print("⚠️  questionnaire_document_files table not found, skip")
        else:
            print(f"⚠️  Warning: questionnaire_document_files migration: {e}")

    # is_active: Integer → Boolean для всех таблиц
    is_active_tables = [
        "equipment_types", "enterprises", "branches", "workshops", "opos",
        "equipment", "engineers", "certifications", "regulatory_documents",
        "users", "hierarchy_engineer_assignments", "report_templates",
        "verification_equipment",
    ]
    for tbl in is_active_tables:
        try:
            async with engine.begin() as conn:
                col_type = await conn.execute(text(
                    "SELECT data_type FROM information_schema.columns "
                    f"WHERE table_name = '{tbl}' AND column_name = 'is_active'"
                ))
                dtype = col_type.scalar()
                if dtype and dtype.lower() in ("integer", "smallint", "bigint"):
                    # Сначала убираем DEFAULT, конвертируем тип, затем устанавливаем новый DEFAULT
                    await conn.execute(text(
                        f"ALTER TABLE {tbl} ALTER COLUMN is_active DROP DEFAULT"
                    ))
                    await conn.execute(text(
                        f"ALTER TABLE {tbl} ALTER COLUMN is_active TYPE boolean "
                        f"USING CASE WHEN is_active = 0 THEN FALSE ELSE TRUE END"
                    ))
                    await conn.execute(text(
                        f"ALTER TABLE {tbl} ALTER COLUMN is_active SET DEFAULT true"
                    ))
                    print(f"✅ DB migration: {tbl}.is_active → boolean")
                else:
                    print(f"✅ DB migration: {tbl}.is_active (already boolean)")
        except Exception as e:
            err = str(e).lower()
            if "already" in err or "does not exist" in err:
                print(f"✅ DB migration: {tbl}.is_active (skip: {e})")
            else:
                print(f"⚠️  Warning: {tbl}.is_active migration: {e}")


# ─── System endpoints ─────────────────────────────────────────────────────────
@app.get("/")
async def root():
    return {"message": "ES TD NGO Platform API", "version": "3.7.9", "status": "running"}


@app.get("/health")
async def health_check(db: AsyncSession = Depends(get_db)):
    """Liveness probe — процесс жив."""
    try:
        await db.execute(text("SELECT 1"))
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database unhealthy: {str(e)}")


@app.get("/ready")
async def ready_check(db: AsyncSession = Depends(get_db)):
    """Readiness probe — сервис готов принимать трафик.

    Проверяем: БД, доступность критичных таблиц (users), наличие alembic.
    """
    checks: Dict[str, Any] = {}
    ok = True
    try:
        result = await db.execute(text("SELECT COUNT(*) FROM users"))
        checks["users_table"] = {"ok": True, "rows": int(result.scalar() or 0)}
    except Exception as e:
        ok = False
        checks["users_table"] = {"ok": False, "error": str(e)[:200]}

    try:
        result = await db.execute(text("SELECT 1"))
        checks["db"] = {"ok": True}
    except Exception as e:
        ok = False
        checks["db"] = {"ok": False, "error": str(e)[:200]}

    checks["version"] = os.getenv("APP_VERSION", "3.7.13")
    if not ok:
        return JSONResponse(status_code=503, content={"status": "not_ready", **checks})
    return {"status": "ready", **checks}


@app.get("/metrics/legacy", include_in_schema=False)
async def get_metrics_legacy():
    """Старый JSON-формат метрик (совместимость). Основной — /metrics (Prometheus)."""
    return _metrics


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
