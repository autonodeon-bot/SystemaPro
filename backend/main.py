from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse, StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text, or_, and_, func, Integer, cast, delete, nulls_last
from sqlalchemy.orm import load_only
from typing import List, Optional, Dict, Any
from pydantic import BaseModel
from datetime import datetime, date, timedelta
import os
import time
import uuid as uuid_lib
from database import get_db, engine, Base
from models import (
    UserEquipmentAccess,
    Equipment, EquipmentType, PipelineSegment, Inspection,
    Client, Project, EquipmentResource, RegulatoryDocument,
    Engineer, Certification, Report, Questionnaire, NDTMethod, User,
    Enterprise, Branch, Workshop, HierarchyEngineerAssignment,
    QuestionnaireDocumentFile, InspectionHistory, Assignment, RepairJournal,
    VerificationEquipment, VerificationHistory, InspectionEquipment, Opo,
    AuditLog,
)
from report_generator import ReportGenerator
from auth import USERS_DB, create_access_token, verify_token, verify_token_optional, verify_password, hash_password
from pathlib import Path
from auth_api import router as auth_router, get_current_user
from access_management import router as access_router
from hierarchy_management import router as hierarchy_router
from assignments_api import router as assignments_router
from report_templates_api import router as report_templates_router
from equipment_history_api import router as equipment_history_router
from inspection_archive_api import router as inspection_archive_router
from pathlib import Path as _Path
import json as _json
import zipfile
import io

app = FastAPI(
    title="ЕС ТД НГО — API",
    description="""API для системы учёта оборудования и диагностирования (ЕС ТД НГО).

**Авторизация:** Bearer JWT в заголовке `Authorization`.

**Формат ошибок:** все ответы с ошибкой возвращают `{"detail": "текст", "code": "VALIDATION_ERROR"|"UNAUTHORIZED"|"NOT_FOUND"|..., "errors": [{"field": "...", "message": "..."}]}`.

**Основные разделы:** задания, оборудование, обследования (inspections), опросные листы (questionnaires), отчёты, ОПО, пользователи.""",
    version="3.23.0",
    openapi_tags=[
        {"name": "auth", "description": "Авторизация и пользователи"},
        {"name": "assignments", "description": "Задания"},
        {"name": "equipment", "description": "Оборудование"},
        {"name": "inspections", "description": "Обследования и чек-листы"},
        {"name": "questionnaires", "description": "Опросные листы и вложения"},
        {"name": "reports", "description": "Генерация отчётов"},
        {"name": "opos", "description": "ОПО и опросы ОПО"},
    ],
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # В продакшене указать конкретные домены
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Кэш справочников (TTL 5 мин), инвалидация при изменении данных
_CACHE_TTL_SEC = 300
_ref_cache: Dict[str, tuple] = {}

def _cache_get(key: str) -> Optional[Any]:
    if key not in _ref_cache:
        return None
    expires, val = _ref_cache[key]
    if time.time() > expires:
        del _ref_cache[key]
        return None
    return val

def _cache_set(key: str, value: Any) -> None:
    _ref_cache[key] = (time.time() + _CACHE_TTL_SEC, value)

def _cache_invalidate(prefix: str) -> None:
    to_del = [k for k in _ref_cache if k.startswith(prefix)]
    for k in to_del:
        del _ref_cache[k]

# Метрики для мониторинга (п.9): счётчики запросов и генерации отчётов
_metrics = {"http_requests_total": 0, "report_generation_seconds_sum": 0.0, "report_generation_count": 0}
ALLOWED_IMAGE_MIME_TYPES = {"image/jpeg", "image/jpg", "image/png"}
MAX_NDT_UPLOAD_SIZE_BYTES = 10 * 1024 * 1024

# Единый формат ошибок API: { "detail", "code", "errors" }
@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc: HTTPException):
    code_map = {
        400: "VALIDATION_ERROR",
        401: "UNAUTHORIZED",
        403: "FORBIDDEN",
        404: "NOT_FOUND",
        409: "CONFLICT",
        422: "UNPROCESSABLE_ENTITY",
        500: "INTERNAL_ERROR",
    }
    code = code_map.get(exc.status_code, "ERROR")
    detail = exc.detail
    if isinstance(detail, list):
        errors = detail
        detail = "Ошибка валидации" if exc.status_code == 422 else str(detail)
    else:
        errors = []
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": detail, "code": code, "errors": errors},
    )

async def _log_audit(
    db: AsyncSession,
    user_id: Optional[uuid_lib.UUID],
    action: str,
    entity_type: str,
    entity_id: Optional[uuid_lib.UUID],
    details: Optional[dict] = None,
) -> None:
    """Пишет запись в журнал аудита. Не бросает исключений."""
    try:
        entry = AuditLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            details=details,
        )
        db.add(entry)
    except Exception:
        pass

def _validate_create_inspection(data: dict) -> None:
    """Валидация тела запроса создания обследования. При ошибках бросает HTTPException с списком errors."""
    err = []
    eq_id = data.get("equipment_id")
    if not eq_id:
        err.append({"field": "equipment_id", "message": "equipment_id обязателен"})
    elif not isinstance(eq_id, str) or not str(eq_id).strip():
        err.append({"field": "equipment_id", "message": "equipment_id должен быть непустой строкой"})
    else:
        try:
            uuid_lib.UUID(str(eq_id))
        except (ValueError, TypeError):
            err.append({"field": "equipment_id", "message": "equipment_id должен быть валидным UUID"})
    st = data.get("status")
    if st is not None and str(st).strip():
        allowed = {"DRAFT", "SIGNED", "APPROVED", "COMPLETED"}
        if str(st).strip().upper() not in allowed:
            err.append({"field": "status", "message": f"status должен быть один из: {', '.join(sorted(allowed))}"})
    if "data" in data and data["data"] is not None and not isinstance(data["data"], dict):
        err.append({"field": "data", "message": "data должен быть объектом (словарём)"})
    aid = data.get("assignment_id")
    if aid is not None and str(aid).strip():
        try:
            uuid_lib.UUID(str(aid))
        except (ValueError, TypeError):
            err.append({"field": "assignment_id", "message": "assignment_id должен быть валидным UUID"})
    if err:
        raise HTTPException(status_code=400, detail=err)


from inspection_utils import create_ndt_methods_from_mobile as _create_ndt_methods_from_mobile, update_equipment_attributes_from_inspection as _update_equipment_attrs

# Middleware для правильной кодировки UTF-8 и учёт запросов (метрики)
@app.middleware("http")
async def add_charset_header(request, call_next):
    if request.url.path != "/metrics":
        _metrics["http_requests_total"] = _metrics.get("http_requests_total", 0) + 1
    response = await call_next(request)
    if response.headers.get("content-type", "").startswith("application/json"):
        response.headers["content-type"] = "application/json; charset=utf-8"
    return response


def _resolve_report_file_path(path: Optional[str]) -> Optional[str]:
    """Преобразует относительный путь к файлу в абсолютный для вставки в отчёт."""
    if not path or not isinstance(path, str) or not path.strip():
        return path
    path = path.strip().replace("\\", "/")
    p = Path(path)
    if p.is_absolute() and p.exists():
        return str(p)
    if not p.is_absolute():
        for base in ["/app/uploads/questionnaire_documents", "/app/uploads/ndt_photos", "/app/uploads/certification_scans", "/app/uploads", "/app/reports", os.getcwd()]:
            candidate = Path(base) / path
            if candidate.exists():
                return str(candidate.resolve())
    filename = os.path.basename(path)
    if filename:
        qd_base = Path("/app/uploads/questionnaire_documents")
        if qd_base.is_dir():
            try:
                for sub in qd_base.iterdir():
                    if sub.is_dir():
                        candidate = sub / filename
                        if candidate.is_file():
                            return str(candidate.resolve())
            except OSError:
                pass
    return path


def _normalize_image_content_type(file: UploadFile) -> Optional[str]:
    content_type = (file.content_type or "").lower()
    if content_type in ALLOWED_IMAGE_MIME_TYPES:
        return content_type
    ext = (Path(file.filename or "").suffix or "").lower()
    if ext in {".jpg", ".jpeg"}:
        return "image/jpeg"
    if ext == ".png":
        return "image/png"
    return None


async def _read_upload_with_limit(file: UploadFile, max_size: int) -> bytes:
    content = b""
    while True:
        chunk = await file.read(1024 * 1024)
        if not chunk:
            break
        content += chunk
        if len(content) > max_size:
            raise HTTPException(
                status_code=400,
                detail=f"Файл слишком большой. Максимум {max_size // (1024 * 1024)} МБ.",
            )
    return content


# Include routers
app.include_router(auth_router)
app.include_router(access_router)
app.include_router(hierarchy_router)
app.include_router(assignments_router)  # Новый роутер для заданий (версия 3.3.0)
app.include_router(report_templates_router)  # Шаблоны отчетов (MVP без миграций БД)
app.include_router(equipment_history_router)  # Новый роутер для истории (версия 3.3.0)
app.include_router(inspection_archive_router)  # Загрузка ZIP-архива обследования с мобильного

# Версия мобильного приложения (должна соответствовать реально доступному APK по ссылке)
MOBILE_APP_VERSION = "3.25.0"
MOBILE_APP_BUILD = "25"
MOBILE_APP_DOWNLOAD_URL = f"http://5.129.203.182/mobile/es-td-ngo-{MOBILE_APP_VERSION}-{MOBILE_APP_BUILD}.apk"

# Endpoint для проверки версии мобильного приложения
@app.get("/api/mobile/version")
async def get_mobile_version():
    """Получить информацию о версии мобильного приложения"""
    return {
        "version": MOBILE_APP_VERSION,
        "build": MOBILE_APP_BUILD,
        "download_url": MOBILE_APP_DOWNLOAD_URL,
        "release_date": datetime.now().isoformat()
    }


def _cert_areas_list(c):
    """Список областей аттестации из сертификата (certification_areas или certification_area)."""
    areas = getattr(c, "certification_areas", None)
    if areas is not None and isinstance(areas, list):
        return [str(a).strip() for a in areas if a]
    single = getattr(c, "certification_area", None)
    return [str(single).strip()] if single else []


@app.get("/api/mobile/sync/engineers-by-ndt")
async def mobile_sync_engineers_by_ndt(
    method_code: Optional[str] = None,
    username: str = Depends(verify_token_optional),
    db: AsyncSession = Depends(get_db)
):
    """
    Синхронизация для мобильного приложения: инженеры с сертификатами по видам НК.
    Возвращает список сертификатов с данными инженера и method_code для группировки по виду НК.
    method_code: опциональный фильтр (УЗК, ВИК, ПВК, РК, МК и т.д.)
    """
    try:
        query = (
            select(Certification, Engineer, User)
            .join(Engineer, Certification.engineer_id == Engineer.id)
            .outerjoin(User, User.engineer_id == Engineer.id)
            .where(Certification.is_active == 1)
            .where(Engineer.is_active == 1)
        )
        if method_code:
            query = query.where(Certification.method_code == method_code)
        result = await db.execute(query)
        rows = result.all()
        items = []
        for c, eng, u in rows:
            items.append({
                "id": str(c.id),
                "engineer_id": str(c.engineer_id),
                "engineer_full_name": eng.full_name or "",
                "engineer_position": eng.position or "",
                "engineer_phone": eng.phone or "",
                "engineer_email": eng.email or "",
                "user_id": str(u.id) if u else None,
                "username": u.username if u else None,
                "method_code": c.method_code or "",
                "certification_type": c.certification_type or "",
                "certificate_number": c.certificate_number or "",
                "certification_areas": _cert_areas_list(c),
                "issue_date": str(c.issue_date) if c.issue_date else None,
                "expiry_date": str(c.expiry_date) if c.expiry_date else None,
                "issuing_organization": c.issuing_organization or "",
            })
        return {"items": items, "total": len(items)}
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/vessel-templates/{template_name}")
async def get_vessel_template(
    template_name: str,
    username: str = Depends(verify_token_optional)
):
    """
    Получить шаблон чертежа сосуда.
    template_name: название шаблона (например, 'vessel_template.png')
    """
    try:
        # Безопасность: разрешаем только PNG/JPG файлы из assets
        if not template_name.endswith(('.png', '.jpg', '.jpeg')):
            raise HTTPException(status_code=400, detail="Invalid file type")
        
        # Убираем путь из имени файла для безопасности
        safe_name = Path(template_name).name
        
        template_path = Path(f"/app/reports/assets/{safe_name}")
        
        if not template_path.exists():
            raise HTTPException(status_code=404, detail="Template not found")
        
        # Определяем media type
        if safe_name.endswith('.png'):
            media_type = 'image/png'
        elif safe_name.endswith(('.jpg', '.jpeg')):
            media_type = 'image/jpeg'
        else:
            media_type = 'application/octet-stream'
        
        return FileResponse(
            path=str(template_path),
            media_type=media_type,
            headers={
                "Content-Disposition": f'inline; filename="{safe_name}"',
                "Cache-Control": "public, max-age=3600"
            }
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/vessel-templates")
async def list_vessel_templates(
    username: str = Depends(verify_token_optional)
):
    """Получить список доступных шаблонов чертежей"""
    try:
        assets_dir = Path("/app/reports/assets")
        if not assets_dir.exists():
            return {"templates": []}
        
        templates = []
        for file in assets_dir.glob("*_template.*"):
            if file.suffix.lower() in ['.png', '.jpg', '.jpeg']:
                templates.append({
                    "name": file.name,
                    "type": file.suffix.lower().replace('.', ''),
                    "size": file.stat().st_size if file.exists() else 0
                })
        
        return {"templates": templates}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/mobile/check-update")
async def check_mobile_update(current_version: str, current_build: str):
    """Проверить наличие обновления для мобильного приложения"""
    try:
        # Парсим версию (формат: "3.6.1" или "3.6.2")
        current_v_parts = current_version.split('.')
        server_v_parts = MOBILE_APP_VERSION.split('.')
        
        # Сравниваем версии по частям (major.minor.patch)
        has_update = False
        version_different = False
        
        # Сравниваем каждую часть версии
        for i in range(max(len(current_v_parts), len(server_v_parts))):
            current_v = int(current_v_parts[i]) if i < len(current_v_parts) else 0
            server_v = int(server_v_parts[i]) if i < len(server_v_parts) else 0
            
            if server_v > current_v:
                has_update = True
                version_different = True
                break
            elif server_v < current_v:
                # Текущая версия новее серверной (не должно быть, но на всякий случай)
                version_different = True
                break
        
        # Если версии одинаковые, сравниваем build номер
        if not version_different:
            try:
                current_b = int(current_build)
                server_b = int(MOBILE_APP_BUILD)
                # Обновление есть только если build номер сервера больше
                has_update = server_b > current_b
            except (ValueError, TypeError):
                # Если не удалось распарсить build, считаем что обновления нет
                has_update = False
        
        return {
            "has_update": has_update,
            "current_version": current_version,
            "current_build": current_build,
            "latest_version": MOBILE_APP_VERSION,
            "latest_build": MOBILE_APP_BUILD,
            "download_url": MOBILE_APP_DOWNLOAD_URL if has_update else None,
            "is_latest": not has_update  # Флаг, что версия последняя
        }
    except Exception as e:
        return {
            "has_update": False,
            "error": str(e),
            "is_latest": True  # При ошибке считаем что версия последняя
        }

@app.on_event("startup")
async def startup():
    """Initialize database on startup"""
    try:
        # Test database connection
        async with engine.begin() as conn:
            await conn.execute(text("SELECT 1"))
        print("✅ Database connection successful")
        
        # Create tables if they don't exist
        try:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            print("✅ Database tables checked/created")
        except Exception as e:
            print(f"⚠️  Warning: Could not create tables: {e}")

        # Лёгкие авто-миграции (исправление расхождений схемы БД и моделей)
        # Важно: Base.metadata.create_all НЕ добавляет колонки в уже существующие таблицы.
        try:
            # Выполняем миграции по отдельности, чтобы не откатывать все при ошибке одной
            async with engine.begin() as conn:
                # equipment_resources.resource_type отсутствует в старых БД, но используется в предпросмотре/отчетах
                try:
                    await conn.execute(
                        text(
                            "ALTER TABLE equipment_resources "
                            "ADD COLUMN IF NOT EXISTS resource_type VARCHAR(50)"
                        )
                    )
                    print("✅ DB migration: equipment_resources.resource_type")
                except Exception as e:
                    print(f"⚠️  Warning: equipment_resources.resource_type migration: {e}")

                # equipment.opo_id + индекс (ОПО, версия 3.7.x)
                try:
                    await conn.execute(
                        text(
                            "ALTER TABLE equipment "
                            "ADD COLUMN IF NOT EXISTS opo_id UUID"
                        )
                    )
                    await conn.execute(
                        text(
                            "CREATE INDEX IF NOT EXISTS idx_equipment_opo_id ON equipment(opo_id)"
                        )
                    )
                    print("✅ DB migration: equipment.opo_id")
                except Exception as e:
                    print(f"⚠️  Warning: equipment.opo_id migration: {e}")

                # opos.* (ОПО) — в старых БД часто нет колонок иерархии, из-за чего падают /api/equipment и /api/assignments
                try:
                    await conn.execute(text(
                        "ALTER TABLE opos ADD COLUMN IF NOT EXISTS enterprise_id UUID REFERENCES enterprises(id)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE opos ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES branches(id)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE opos ADD COLUMN IF NOT EXISTS workshop_id UUID REFERENCES workshops(id)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE opos ADD COLUMN IF NOT EXISTS registration_number VARCHAR(100)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE opos ADD COLUMN IF NOT EXISTS hazard_class VARCHAR(50)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE opos ADD COLUMN IF NOT EXISTS survey_data JSONB"
                    ))
                    await conn.execute(text(
                        "CREATE INDEX IF NOT EXISTS idx_opos_enterprise_id ON opos(enterprise_id)"
                    ))
                    await conn.execute(text(
                        "CREATE INDEX IF NOT EXISTS idx_opos_branch_id ON opos(branch_id)"
                    ))
                    await conn.execute(text(
                        "CREATE INDEX IF NOT EXISTS idx_opos_workshop_id ON opos(workshop_id)"
                    ))
                    print("✅ DB migration: opos.enterprise_id, opos.branch_id, opos.workshop_id")
                except Exception as e:
                    print(f"⚠️  Warning: opos columns migration: {e}")

            # inspections.is_archived (версия 3.7.x) - выполняем отдельно
            # Сначала проверяем, существует ли колонка
            async with engine.begin() as conn:
                try:
                    # Проверяем существование колонки
                    result = await conn.execute(
                        text("""
                            SELECT column_name 
                            FROM information_schema.columns 
                            WHERE table_name = 'inspections' 
                            AND column_name = 'is_archived'
                        """)
                    )
                    column_exists = result.scalar() is not None
                    
                    if not column_exists:
                        # Добавляем колонку с DEFAULT
                        await conn.execute(
                            text(
                                "ALTER TABLE inspections "
                                "ADD COLUMN is_archived BOOLEAN DEFAULT FALSE NOT NULL"
                            )
                        )
                        print("✅ DB migration: inspections.is_archived added")
                    else:
                        # Колонка существует, проверяем, что она NOT NULL
                        try:
                            await conn.execute(
                                text(
                                    "ALTER TABLE inspections "
                                    "ALTER COLUMN is_archived SET NOT NULL"
                                )
                            )
                            print("✅ DB migration: inspections.is_archived verified")
                        except Exception:
                            # Колонка уже NOT NULL, это нормально
                            print("✅ DB migration: inspections.is_archived already NOT NULL")
                except Exception as e:
                    print(f"⚠️  Warning: inspections.is_archived migration failed: {e}")
                    import traceback
                    traceback.print_exc()

            # reports.is_archived (версия 3.7.x) - выполняем отдельно
            async with engine.begin() as conn:
                try:
                    # Проверяем существование колонки
                    result = await conn.execute(
                        text("""
                            SELECT column_name 
                            FROM information_schema.columns 
                            WHERE table_name = 'reports' 
                            AND column_name = 'is_archived'
                        """)
                    )
                    column_exists = result.scalar() is not None
                    
                    if not column_exists:
                        # Добавляем колонку с DEFAULT
                        await conn.execute(
                            text(
                                "ALTER TABLE reports "
                                "ADD COLUMN is_archived BOOLEAN DEFAULT FALSE NOT NULL"
                            )
                        )
                        print("✅ DB migration: reports.is_archived added")
                    else:
                        # Колонка существует, проверяем, что она NOT NULL
                        try:
                            await conn.execute(
                                text(
                                    "ALTER TABLE reports "
                                    "ALTER COLUMN is_archived SET NOT NULL"
                                )
                            )
                            print("✅ DB migration: reports.is_archived verified")
                        except Exception:
                            # Колонка уже NOT NULL, это нормально
                            print("✅ DB migration: reports.is_archived already NOT NULL")
                except Exception as e:
                    print(f"⚠️  Warning: reports.is_archived migration failed: {e}")
                    import traceback
                    traceback.print_exc()

            # users.permissions (JSONB для дополнительных прав)
            async with engine.begin() as conn:
                try:
                    await conn.execute(
                        text(
                            "ALTER TABLE users "
                            "ADD COLUMN IF NOT EXISTS permissions JSONB"
                        )
                    )
                    print("✅ DB migration: users.permissions")
                except Exception as e:
                    print(f"⚠️  Warning: users.permissions migration: {e}")

            # verification_equipment: колонки для UI (name, next_verification_date, inventory_number, scan_file_name, scan_file_size, scan_mime_type, notes, expiry_date)
            async with engine.begin() as conn:
                for col, col_type in [
                    ("name", "VARCHAR(255)"),
                    ("next_verification_date", "DATE"),
                    ("inventory_number", "VARCHAR(100)"),
                    ("scan_file_name", "VARCHAR(255)"),
                    ("scan_file_size", "INTEGER"),
                    ("scan_mime_type", "VARCHAR(100)"),
                    ("notes", "TEXT"),
                    ("expiry_date", "DATE"),
                ]:
                    try:
                        await conn.execute(
                            text(
                                f"ALTER TABLE verification_equipment "
                                f"ADD COLUMN IF NOT EXISTS {col} {col_type}"
                            )
                        )
                    except Exception as e:
                        print(f"⚠️  Warning: verification_equipment.{col} migration: {e}")
                print("✅ DB migration: verification_equipment columns")

            # equipment.* (колонки, которые есть в модели, но могут отсутствовать в старых БД)
            # + assignments.assignment_type, assignments.completed_at
            async with engine.begin() as conn:
                try:
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS equipment_code VARCHAR(100)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS manufacturer VARCHAR(255)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS serial_number VARCHAR(100)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS location VARCHAR(255)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS model VARCHAR(255)"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS commissioning_date DATE"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS attributes JSONB"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS is_active INTEGER DEFAULT 1"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT now()"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE equipment ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS assignment_type VARCHAR(50) DEFAULT 'DIAGNOSTICS'"
                    ))
                    await conn.execute(text(
                        "ALTER TABLE assignments ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE"
                    ))
                    print("✅ DB migration: equipment columns + assignments.assignment_type, completed_at")
                except Exception as e:
                    err_msg = str(e).lower()
                    if "already exists" in err_msg or "duplicate" in err_msg:
                        print("✅ DB migration: equipment/assignments columns (already exist)")
                    else:
                        print(f"⚠️  Warning: assignments/equipment migration: {e}")
            
            # Добавляем project_id в assignments если его нет
            async with engine.begin() as conn:
                try:
                    await conn.execute(text("""
                        ALTER TABLE assignments 
                        ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id)
                    """))
                    print("✅ DB migration: assignments.project_id")
                except Exception as e:
                    err_msg = str(e).lower()
                    if "already exists" in err_msg or "duplicate" in err_msg:
                        print("✅ DB migration: assignments.project_id (already exists)")
                    else:
                        print(f"⚠️  Warning: assignments.project_id migration: {e}")
                        import traceback
                        traceback.print_exc()
            
            # Добавляем project_id и inspector_id в inspections если их нет
            async with engine.begin() as conn:
                try:
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id)
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS inspector_id UUID REFERENCES users(id)
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS assignment_id UUID REFERENCES assignments(id)
                    """))
                    await conn.execute(text("""
                        CREATE INDEX IF NOT EXISTS idx_inspections_assignment_id ON inspections(assignment_id)
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS questionnaire_id UUID REFERENCES questionnaires(id)
                    """))
                    await conn.execute(text("""
                        CREATE INDEX IF NOT EXISTS idx_inspections_questionnaire_id ON inspections(questionnaire_id)
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS performed_by UUID REFERENCES users(id)
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS date_performed TIMESTAMP WITH TIME ZONE
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'DRAFT'
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS conclusion TEXT
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS data JSONB
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS gps_coordinates JSONB
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id)
                    """))
                    await conn.execute(text("""
                        ALTER TABLE inspections 
                        ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES users(id)
                    """))
                    print("✅ DB migration: inspections - all columns (+ created_by, updated_by)")
                except Exception as e:
                    err_msg = str(e).lower()
                    if "already exists" in err_msg or "duplicate" in err_msg:
                        print("✅ DB migration: inspections (already exist)")
                    else:
                        print(f"⚠️  Warning: inspections migration: {e}")
                        import traceback
                        traceback.print_exc()

            # questionnaires: колонки для связи с заданиями и данными (assignment_id, date_performed, performed_by, status, data, updated_at)
            async with engine.begin() as conn:
                try:
                    await conn.execute(text("""
                        ALTER TABLE questionnaires 
                        ADD COLUMN IF NOT EXISTS assignment_id UUID REFERENCES assignments(id)
                    """))
                    await conn.execute(text("""
                        ALTER TABLE questionnaires 
                        ADD COLUMN IF NOT EXISTS date_performed TIMESTAMP WITH TIME ZONE
                    """))
                    await conn.execute(text("""
                        ALTER TABLE questionnaires 
                        ADD COLUMN IF NOT EXISTS performed_by UUID REFERENCES users(id)
                    """))
                    await conn.execute(text("""
                        ALTER TABLE questionnaires 
                        ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'DRAFT'
                    """))
                    await conn.execute(text("""
                        ALTER TABLE questionnaires 
                        ADD COLUMN IF NOT EXISTS data JSONB
                    """))
                    await conn.execute(text("""
                        ALTER TABLE questionnaires 
                        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE
                    """))
                    await conn.execute(text("""
                        ALTER TABLE questionnaires 
                        ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id)
                    """))
                    await conn.execute(text("""
                        ALTER TABLE questionnaires 
                        ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES users(id)
                    """))
                    await conn.execute(text("""
                        CREATE INDEX IF NOT EXISTS idx_questionnaires_assignment_id ON questionnaires(assignment_id)
                    """))
                    print("✅ DB migration: questionnaires (+ created_by, updated_by)")
                except Exception as e:
                    err_msg = str(e).lower()
                    if "already exists" in err_msg or "duplicate" in err_msg:
                        print("✅ DB migration: questionnaires (already exist)")
                    else:
                        print(f"⚠️  Warning: questionnaires migration: {e}")
                        import traceback
                        traceback.print_exc()

            # audit_log: журнал аудита
            async with engine.begin() as conn:
                try:
                    await conn.execute(text("""
                        CREATE TABLE IF NOT EXISTS audit_log (
                            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                            user_id UUID REFERENCES users(id),
                            action VARCHAR(50) NOT NULL,
                            entity_type VARCHAR(100) NOT NULL,
                            entity_id UUID,
                            details JSONB,
                            ip_address VARCHAR(50)
                        )
                    """))
                    await conn.execute(text("""
                        CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON audit_log(entity_type, entity_id)
                    """))
                    await conn.execute(text("""
                        CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at)
                    """))
                    print("✅ DB migration: audit_log")
                except Exception as e:
                    err_msg = str(e).lower()
                    if "already exists" in err_msg or "duplicate" in err_msg:
                        print("✅ DB migration: audit_log (already exist)")
                    else:
                        print(f"⚠️  Warning: audit_log migration: {e}")
                        import traceback
                        traceback.print_exc()

            # questionnaire_document_files: расширяем VARCHAR-колонки (было varying(10) — не хватало для document_number и др.)
            async with engine.begin() as conn:
                try:
                    for col, typ in [
                        ("document_number", "VARCHAR(100)"),
                        ("file_name", "VARCHAR(255)"),
                        ("file_path", "VARCHAR(500)"),
                        ("file_type", "VARCHAR(50)"),
                        ("mime_type", "VARCHAR(100)"),
                    ]:
                        await conn.execute(text(f"""
                            ALTER TABLE questionnaire_document_files
                            ALTER COLUMN {col} TYPE {typ}
                        """))
                    print("✅ DB migration: questionnaire_document_files (column lengths)")
                except Exception as e:
                    err_msg = str(e).lower()
                    if "does not exist" in err_msg:
                        print("⚠️  questionnaire_document_files table not found, skip column resize")
                    else:
                        print(f"⚠️  Warning: questionnaire_document_files migration: {e}")
                        import traceback
                        traceback.print_exc()
                    
        except Exception as e:
            print(f"⚠️  Warning: DB migration failed: {e}")
            import traceback
            traceback.print_exc()
            
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        import traceback
        traceback.print_exc()

@app.get("/")
async def root():
    return {
        "message": "ES TD NGO Platform API",
        "version": "1.0.0",
        "status": "running"
    }

@app.get("/health")
async def health_check(db: AsyncSession = Depends(get_db)):
    """Health check endpoint"""
    try:
        result = await db.execute(text("SELECT 1"))
        return {
            "status": "healthy",
            "database": "connected"
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database connection failed: {str(e)}")


@app.get("/metrics")
async def metrics():
    """Метрики в формате Prometheus (п.9): счётчики запросов и генерации отчётов."""
    from fastapi.responses import PlainTextResponse
    lines = [
        "# TYPE es_td_ngo_http_requests_total counter",
        f"es_td_ngo_http_requests_total {_metrics.get('http_requests_total', 0)}",
        "# TYPE es_td_ngo_report_generation_seconds_sum counter",
        f"es_td_ngo_report_generation_seconds_sum {_metrics.get('report_generation_seconds_sum', 0):.3f}",
        "# TYPE es_td_ngo_report_generation_count counter",
        f"es_td_ngo_report_generation_count {_metrics.get('report_generation_count', 0)}",
    ]
    return PlainTextResponse("\n".join(lines) + "\n", media_type="text/plain; charset=utf-8")


@app.get("/api/stats")
async def api_stats(
    days: int = 30,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Панель статистики: обследования, отчёты, задания по периодам."""
    from datetime import timedelta
    cutoff = date.today() - timedelta(days=days)
    # Обследования
    ins_res = await db.execute(
        select(func.count(Inspection.id)).where(Inspection.created_at >= cutoff)
    )
    inspections_count = ins_res.scalar() or 0
    # Отчёты
    rep_res = await db.execute(
        select(func.count(Report.id)).where(Report.created_at >= cutoff)
    )
    reports_count = rep_res.scalar() or 0
    # Задания
    ass_res = await db.execute(
        select(func.count(Assignment.id)).where(Assignment.created_at >= cutoff)
    )
    assignments_count = ass_res.scalar() or 0
    # По месяцам
    month_col = func.date_trunc('month', Inspection.created_at)
    months_res = await db.execute(
        select(month_col, func.count(Inspection.id))
        .where(Inspection.created_at >= cutoff)
        .group_by(month_col)
        .order_by(month_col)
    )
    rows = months_res.all()
    by_month = [{"month": str(r[0])[:7] if r[0] else "", "count": r[1] or 0} for r in rows]
    return {
        "inspections": inspections_count,
        "reports": reports_count,
        "assignments": assignments_count,
        "period_days": days,
        "by_month": by_month,
    }

# Pydantic models for request/response
class EquipmentCreate(BaseModel):
    name: str
    type_id: Optional[str] = None
    serial_number: Optional[str] = None
    location: Optional[str] = None
    workshop_id: Optional[str] = None
    opo_id: Optional[str] = None
    commissioning_date: Optional[str] = None
    attributes: Optional[dict] = None

class EquipmentUpdate(BaseModel):
    name: Optional[str] = None
    type_id: Optional[str] = None
    serial_number: Optional[str] = None
    location: Optional[str] = None
    opo_id: Optional[str] = None
    commissioning_date: Optional[str] = None
    attributes: Optional[dict] = None

# Equipment endpoints
@app.get("/api/equipment")
async def get_equipment(
    skip: int = 0,
    limit: int = 100,
    workshop_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get list of equipment (filtered by access for engineers)"""
    try:
        # Получаем информацию о пользователе
        # Совместимость: username в токене может быть email (старые токены / ввод email)
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        user = user_result.scalar_one_or_none()
        
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        # Для инженеров фильтруем по доступу (иерархия + прямое назначение)
        if user.role == "engineer":
            # Получаем назначения по иерархии
            hierarchy_result = await db.execute(
                text("""
                    SELECT 
                        enterprise_id, branch_id, workshop_id, 
                        equipment_type_id, equipment_id
                    FROM hierarchy_engineer_assignments 
                    WHERE user_id = CAST(:user_id AS uuid)
                    AND is_active = 1
                    AND (expires_at IS NULL OR expires_at > NOW())
                """),
                {"user_id": str(user.id)}
            )
            hierarchy_assignments = hierarchy_result.all()
            
            # Получаем прямое назначение оборудования
            direct_access_result = await db.execute(
                text("""
                    SELECT equipment_id 
                    FROM user_equipment_access 
                    WHERE user_id = CAST(:user_id AS uuid)
                    AND is_active = 1
                    AND (expires_at IS NULL OR expires_at > NOW())
                """),
                {"user_id": str(user.id)}
            )
            direct_equipment_ids = [row[0] for row in direct_access_result.all()]
            
            # Собираем все ID оборудования из иерархии
            accessible_equipment_ids = set(direct_equipment_ids)
            
            # Обрабатываем назначения по иерархии
            enterprise_ids = []
            branch_ids = []
            workshop_ids = []
            equipment_type_ids = []
            direct_equipment_from_hierarchy = []
            
            for assignment in hierarchy_assignments:
                if assignment[0]:  # enterprise_id
                    enterprise_ids.append(assignment[0])
                if assignment[1]:  # branch_id
                    branch_ids.append(assignment[1])
                if assignment[2]:  # workshop_id
                    workshop_ids.append(assignment[2])
                if assignment[3]:  # equipment_type_id
                    equipment_type_ids.append(assignment[3])
                if assignment[4]:  # equipment_id
                    direct_equipment_from_hierarchy.append(assignment[4])
            
            # Получаем оборудование по иерархии
            query = select(Equipment)
            conditions = []
            
            if direct_equipment_from_hierarchy:
                accessible_equipment_ids.update(direct_equipment_from_hierarchy)
            
            if workshop_ids:
                conditions.append(Equipment.workshop_id.in_(workshop_ids))
            
            if branch_ids:
                # Получаем цеха для этих филиалов
                workshop_result = await db.execute(
                    select(Workshop.id).where(Workshop.branch_id.in_(branch_ids))
                )
                workshop_ids_from_branches = [w[0] for w in workshop_result.all()]
                if workshop_ids_from_branches:
                    conditions.append(Equipment.workshop_id.in_(workshop_ids_from_branches))
            
            if enterprise_ids:
                # Получаем филиалы для этих предприятий
                branch_result = await db.execute(
                    select(Branch.id).where(Branch.enterprise_id.in_(enterprise_ids))
                )
                branch_ids_from_enterprises = [b[0] for b in branch_result.all()]
                if branch_ids_from_enterprises:
                    # Получаем цеха для этих филиалов
                    workshop_result = await db.execute(
                        select(Workshop.id).where(Workshop.branch_id.in_(branch_ids_from_enterprises))
                    )
                    workshop_ids_from_enterprises = [w[0] for w in workshop_result.all()]
                    if workshop_ids_from_enterprises:
                        conditions.append(Equipment.workshop_id.in_(workshop_ids_from_enterprises))
            
            if equipment_type_ids:
                conditions.append(Equipment.type_id.in_(equipment_type_ids))
            
            if accessible_equipment_ids:
                conditions.append(Equipment.id.in_(list(accessible_equipment_ids)))
            
            if conditions:
                query = query.where(or_(*conditions))
                result = await db.execute(query.offset(skip).limit(limit))
                equipment = result.scalars().all()
            else:
                # Если нет назначений, возвращаем пустой список
                equipment = []
        else:
            # Для admin, chief_operator, operator - полный доступ
            query = select(Equipment)
            
            # Фильтр по workshop_id, если указан
            if workshop_id:
                try:
                    workshop_uuid = uuid_lib.UUID(workshop_id)
                    query = query.where(Equipment.workshop_id == workshop_uuid)
                except ValueError:
                    raise HTTPException(status_code=400, detail="Invalid workshop_id format")
            
            # Для админов и операторов увеличиваем лимит, если не указан явно
            effective_limit = limit if limit > 100 else 10000  # Большой лимит для админов
            result = await db.execute(query.offset(skip).limit(effective_limit))
            equipment = result.scalars().all()
        
        # Обогащаем данные об оборудовании информацией об иерархии
        equipment_items = []
        for eq in equipment:
            item = {
                "id": str(eq.id),
                "equipment_code": eq.equipment_code if hasattr(eq, 'equipment_code') and eq.equipment_code else None,  # Уникальный код оборудования (версия 3.3.0)
                "name": eq.name,
                "type_id": str(eq.type_id) if eq.type_id else None,
                "serial_number": eq.serial_number,
                "location": eq.location,
                "attributes": eq.attributes or {},
                "commissioning_date": str(eq.commissioning_date) if eq.commissioning_date else None,
                "created_at": str(eq.created_at) if eq.created_at else None,
                "workshop_id": str(eq.workshop_id) if eq.workshop_id else None,
                "opo_id": str(eq.opo_id) if getattr(eq, "opo_id", None) else None,
            }
            
            # Получаем информацию о цехе, филиале и предприятии
            if eq.workshop_id:
                workshop_result = await db.execute(
                    select(Workshop).where(Workshop.id == eq.workshop_id)
                )
                workshop = workshop_result.scalar_one_or_none()
                if workshop:
                    item["workshop_name"] = workshop.name
                    item["workshop_code"] = workshop.code
                    
                    # Получаем филиал
                    branch_result = await db.execute(
                        select(Branch).where(Branch.id == workshop.branch_id)
                    )
                    branch = branch_result.scalar_one_or_none()
                    if branch:
                        item["branch_id"] = str(branch.id)
                        item["branch_name"] = branch.name
                        item["branch_code"] = branch.code
                        
                        # Получаем предприятие
                        enterprise_result = await db.execute(
                            select(Enterprise).where(Enterprise.id == branch.enterprise_id)
                        )
                        enterprise = enterprise_result.scalar_one_or_none()
                        if enterprise:
                            item["enterprise_id"] = str(enterprise.id)
                            item["enterprise_name"] = enterprise.name
                            item["enterprise_code"] = enterprise.code
            
            # Получаем информацию о типе оборудования
            if eq.type_id:
                type_result = await db.execute(
                    select(EquipmentType).where(EquipmentType.id == eq.type_id)
                )
                equipment_type = type_result.scalar_one_or_none()
                if equipment_type:
                    item["type_name"] = equipment_type.name
                    item["type_code"] = equipment_type.code

            # ОПО (если задано)
            if getattr(eq, "opo_id", None):
                opo_result = await db.execute(
                    select(Opo).where(Opo.id == eq.opo_id)
                )
                opo = opo_result.scalar_one_or_none()
                if opo:
                    item["opo_name"] = opo.name
                    item["opo_code"] = opo.code
            
            equipment_items.append(item)
        
        return {
            "items": equipment_items,
            "total": len(equipment)
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_equipment: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(
            status_code=500, 
            detail=f"Database error: {error_detail}"
        )

@app.get("/api/equipment/{equipment_id}")
async def get_equipment_by_id(
    equipment_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Get equipment by ID"""
    try:
        result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        return {
            "id": str(eq.id),
            "name": eq.name,
            "type_id": str(eq.type_id) if eq.type_id else None,
            "serial_number": eq.serial_number,
            "location": eq.location,
            "attributes": eq.attributes or {},
            "commissioning_date": str(eq.commissioning_date) if eq.commissioning_date else None,
            "created_at": str(eq.created_at) if eq.created_at else None,
            "opo_id": str(eq.opo_id) if getattr(eq, "opo_id", None) else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/equipment")
async def create_equipment(
    equipment_data: EquipmentCreate,
    db: AsyncSession = Depends(get_db)
):
    """Create new equipment"""
    try:
        # Parse commissioning_date if provided
        commissioning_date = None
        if equipment_data.commissioning_date:
            try:
                commissioning_date = datetime.fromisoformat(equipment_data.commissioning_date.replace('Z', '+00:00')).date()
            except:
                pass
        
        # Parse type_id if provided
        type_id = None
        if equipment_data.type_id:
            try:
                type_id = uuid_lib.UUID(equipment_data.type_id)
            except:
                pass
        
        # Parse workshop_id if provided
        workshop_id_uuid = None
        if equipment_data.workshop_id:
            try:
                workshop_id_uuid = uuid_lib.UUID(equipment_data.workshop_id)
            except:
                pass
        
        # Parse opo_id if provided
        opo_id_uuid = None
        if equipment_data.opo_id:
            try:
                opo_id_uuid = uuid_lib.UUID(equipment_data.opo_id)
            except:
                pass

        new_equipment = Equipment(
            name=equipment_data.name,
            type_id=type_id,
            serial_number=equipment_data.serial_number,
            location=equipment_data.location,
            workshop_id=workshop_id_uuid,
            opo_id=opo_id_uuid,
            commissioning_date=commissioning_date,
            attributes=equipment_data.attributes or {}
        )
        db.add(new_equipment)
        await db.commit()
        await db.refresh(new_equipment)
        return {
            "id": str(new_equipment.id),
            "name": new_equipment.name,
            "type_id": str(new_equipment.type_id) if new_equipment.type_id else None,
            "serial_number": new_equipment.serial_number,
            "location": new_equipment.location,
            "attributes": new_equipment.attributes or {},
            "opo_id": str(new_equipment.opo_id) if getattr(new_equipment, "opo_id", None) else None,
            "status": "created"
        }
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create equipment: {str(e)}")

@app.put("/api/equipment/{equipment_id}")
async def update_equipment(
    equipment_id: str,
    equipment_data: EquipmentUpdate,
    db: AsyncSession = Depends(get_db)
):
    """Update equipment"""
    try:
        result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Update fields if provided
        if equipment_data.name is not None:
            eq.name = equipment_data.name
        if equipment_data.serial_number is not None:
            eq.serial_number = equipment_data.serial_number
        if equipment_data.location is not None:
            eq.location = equipment_data.location
        if equipment_data.opo_id is not None:
            try:
                eq.opo_id = uuid_lib.UUID(equipment_data.opo_id) if equipment_data.opo_id else None
            except:
                pass
        if equipment_data.attributes is not None:
            eq.attributes = equipment_data.attributes
        if equipment_data.commissioning_date is not None:
            try:
                eq.commissioning_date = datetime.fromisoformat(equipment_data.commissioning_date.replace('Z', '+00:00')).date()
            except:
                pass
        if equipment_data.type_id is not None:
            try:
                eq.type_id = uuid_lib.UUID(equipment_data.type_id)
            except:
                pass
        
        await db.commit()
        await db.refresh(eq)
        return {
            "id": str(eq.id),
            "name": eq.name,
            "type_id": str(eq.type_id) if eq.type_id else None,
            "serial_number": eq.serial_number,
            "location": eq.location,
            "attributes": eq.attributes or {},
            "opo_id": str(eq.opo_id) if getattr(eq, "opo_id", None) else None,
            "status": "updated"
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update equipment: {str(e)}")

@app.delete("/api/equipment/{equipment_id}")
async def delete_equipment(
    equipment_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Delete equipment"""
    try:
        result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        await db.delete(eq)
        await db.commit()
        return {"status": "deleted", "id": equipment_id}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete equipment: {str(e)}")


# -----------------------------
# ОПО (Опасные производственные объекты)
# -----------------------------

@app.get("/api/opos")
async def list_opos(
    workshop_id: Optional[str] = None,
    enterprise_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Список ОПО (кэш 5 мин)"""
    cache_key = f"opos:{workshop_id}:{enterprise_id}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    try:
        query = select(Opo).where(Opo.is_active == 1)
        if workshop_id:
            try:
                query = query.where(Opo.workshop_id == uuid_lib.UUID(workshop_id))
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid workshop_id format")
        elif enterprise_id:
            # Фильтруем по предприятию через цеха
            try:
                enterprise_uuid = uuid_lib.UUID(enterprise_id)
                # Получаем все филиалы предприятия
                branches_result = await db.execute(
                    select(Branch).where(Branch.enterprise_id == enterprise_uuid)
                )
                branches = branches_result.scalars().all()
                branch_ids = [b.id for b in branches]
                
                if branch_ids:
                    # Получаем все цеха филиалов
                    workshops_result = await db.execute(
                        select(Workshop).where(Workshop.branch_id.in_(branch_ids))
                    )
                    workshops = workshops_result.scalars().all()
                    workshop_ids = [w.id for w in workshops]
                    
                    if workshop_ids:
                        query = query.where(Opo.workshop_id.in_(workshop_ids))
                    else:
                        # Нет цехов - возвращаем пустой список
                        return {"items": []}
                else:
                    # Нет филиалов - возвращаем пустой список
                    return {"items": []}
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid enterprise_id format")

        result = await db.execute(query.order_by(Opo.name))
        items = result.scalars().all()
        response = {
            "items": [
                {
                    "id": str(o.id),
                    "workshop_id": str(o.workshop_id) if o.workshop_id else None,
                    "name": o.name,
                    "code": o.code,
                    "description": o.description,
                    "survey_data": o.survey_data or None,
                    "is_active": o.is_active,
                    "created_at": str(o.created_at) if o.created_at else None,
                    "updated_at": str(o.updated_at) if o.updated_at else None,
                }
                for o in items
            ]
        }
        _cache_set(cache_key, response)
        return response
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/opos")
async def create_opo(
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Создать ОПО (admin/operator/chief_operator)"""
    try:
        # Ограничиваем доступ
        user_result = await db.execute(select(User).where(User.username == username))
        user = user_result.scalar_one_or_none()
        if not user or user.role not in {"admin", "chief_operator", "operator"}:
            raise HTTPException(status_code=403, detail="Forbidden")

        name = (payload.get("name") or "").strip()
        if not name:
            raise HTTPException(status_code=400, detail="name is required")

        workshop_id = None
        if payload.get("workshop_id"):
            try:
                workshop_id = uuid_lib.UUID(payload.get("workshop_id"))
            except Exception:
                raise HTTPException(status_code=400, detail="Invalid workshop_id")

        opo = Opo(
            name=name,
            code=(payload.get("code") or None),
            description=(payload.get("description") or None),
            workshop_id=workshop_id,
            survey_data=payload.get("survey_data"),
            is_active=1,
        )
        db.add(opo)
        await db.commit()
        await db.refresh(opo)
        _cache_invalidate("opos:")
        return {"id": str(opo.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/api/opos/{opo_id}")
async def update_opo(
    opo_id: str,
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Обновить ОПО (admin/operator/chief_operator)"""
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        user = user_result.scalar_one_or_none()
        if not user or user.role not in {"admin", "chief_operator", "operator"}:
            raise HTTPException(status_code=403, detail="Forbidden")

        try:
            opo_uuid = uuid_lib.UUID(opo_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid opo_id format")

        result = await db.execute(select(Opo).where(Opo.id == opo_uuid))
        opo = result.scalar_one_or_none()
        if not opo:
            raise HTTPException(status_code=404, detail="OPO not found")

        if "name" in payload and payload["name"] is not None:
            opo.name = str(payload["name"]).strip()
        if "code" in payload:
            opo.code = payload.get("code")
        if "description" in payload:
            opo.description = payload.get("description")
        if "survey_data" in payload:
            opo.survey_data = payload.get("survey_data")
        if "is_active" in payload and payload["is_active"] is not None:
            opo.is_active = int(payload["is_active"])
        if "workshop_id" in payload:
            if payload.get("workshop_id"):
                try:
                    opo.workshop_id = uuid_lib.UUID(payload.get("workshop_id"))
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid workshop_id")
            else:
                opo.workshop_id = None

        await db.commit()
        _cache_invalidate("opos:")
        return {"id": str(opo.id), "status": "updated"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/opos/{opo_id}/survey")
async def get_opo_survey(
    opo_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Получить опросный лист ОПО (доступно инженеру/оператору/админу)"""
    try:
        try:
            opo_uuid = uuid_lib.UUID(opo_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid opo_id format")

        # Любой авторизованный пользователь может читать (для автоподтягивания)
        result = await db.execute(select(Opo).where(Opo.id == opo_uuid))
        opo = result.scalar_one_or_none()
        if not opo:
            raise HTTPException(status_code=404, detail="OPO not found")

        return {
            "opo_id": str(opo.id),
            "survey_data": opo.survey_data or {},
            "updated_at": str(opo.updated_at) if opo.updated_at else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/api/opos/{opo_id}/survey")
async def update_opo_survey(
    opo_id: str,
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Обновить опросный лист ОПО (инженер может менять только survey_data)"""
    try:
        try:
            opo_uuid = uuid_lib.UUID(opo_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid opo_id format")

        user_result = await db.execute(select(User).where(User.username == username))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        # Инженеру разрешаем только survey_data
        allowed_roles = {"admin", "chief_operator", "operator", "engineer"}
        if user.role not in allowed_roles:
            raise HTTPException(status_code=403, detail="Forbidden")

        result = await db.execute(select(Opo).where(Opo.id == opo_uuid))
        opo = result.scalar_one_or_none()
        if not opo:
            raise HTTPException(status_code=404, detail="OPO not found")

        if "survey_data" not in payload:
            raise HTTPException(status_code=400, detail=[{"field": "survey_data", "message": "survey_data обязателен"}])
        sd = payload.get("survey_data")
        if sd is not None and not isinstance(sd, dict):
            raise HTTPException(status_code=400, detail=[{"field": "survey_data", "message": "survey_data должен быть объектом (словарём)"}])

        opo.survey_data = sd or {}
        await db.commit()
        _cache_invalidate("opos:")
        return {"opo_id": str(opo.id), "status": "updated"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/opos/{opo_id}")
async def get_opo(
    opo_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Получить ОПО по ID"""
    try:
        try:
            opo_uuid = uuid_lib.UUID(opo_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid opo_id format")

        result = await db.execute(select(Opo).where(Opo.id == opo_uuid))
        opo = result.scalar_one_or_none()
        if not opo:
            raise HTTPException(status_code=404, detail="OPO not found")

        return {
            "id": str(opo.id),
            "workshop_id": str(opo.workshop_id) if opo.workshop_id else None,
            "name": opo.name,
            "code": opo.code,
            "description": opo.description,
            "survey_data": opo.survey_data or None,
            "is_active": opo.is_active,
            "created_at": str(opo.created_at) if opo.created_at else None,
            "updated_at": str(opo.updated_at) if opo.updated_at else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Equipment types endpoints
@app.get("/api/equipment-types")
async def get_equipment_types(
    db: AsyncSession = Depends(get_db)
):
    """Get list of equipment types (кэш 5 мин)"""
    cached = _cache_get("equipment_types")
    if cached is not None:
        return cached
    try:
        result = await db.execute(
            select(EquipmentType).where(EquipmentType.is_active == 1)
        )
        types = result.scalars().all()
        response = {
            "items": [
                {
                    "id": str(et.id),
                    "name": et.name,
                    "description": et.description,
                    "code": et.code,
                }
                for et in types
            ]
        }
        _cache_set("equipment_types", response)
        return response
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/equipment-types")
async def create_equipment_type(
    type_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать тип оборудования"""
    try:
        # Проверяем права (только admin и chief_operator)
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        if not user or user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        new_type = EquipmentType(
            name=type_data.get("name"),
            code=type_data.get("code"),
            description=type_data.get("description")
        )
        db.add(new_type)
        await db.commit()
        await db.refresh(new_type)
        _cache_invalidate("equipment_types")
        return {
            "id": str(new_type.id),
            "name": new_type.name,
            "code": new_type.code,
            "description": new_type.description,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create equipment type: {str(e)}")

# Pipeline segments endpoints
@app.get("/api/pipelines")
async def get_pipelines(db: AsyncSession = Depends(get_db)):
    """Get pipeline segments"""
    try:
        result = await db.execute(select(PipelineSegment))
        segments = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(seg.id),
                    "name": seg.name,
                    "segment_type": seg.segment_type,
                    "corrosion_rate": seg.corrosion_rate,
                    "thickness": seg.thickness,
                    "last_inspection_date": str(seg.last_inspection_date) if seg.last_inspection_date else None,
                    "remaining_life": seg.remaining_life,
                }
                for seg in segments
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Inspections endpoints
@app.get("/api/inspections")
async def get_inspections(
    equipment_id: Optional[str] = None,
    enterprise_id: Optional[str] = None,
    branch_id: Optional[str] = None,
    workshop_id: Optional[str] = None,
    inspection_type: Optional[str] = None,
    inspection_method: Optional[str] = None,
    inspection_category: Optional[str] = None,
    group_by: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get inspections (с учетом прав: инженер видит только свои). Фильтр по предприятию/филиалу/цеху."""
    try:
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        query = select(Inspection)

        if current_user.role == "engineer":
            query = query.where(
                or_(
                    Inspection.inspector_id == current_user.id,
                    Inspection.performed_by == current_user.id,
                )
            )

        if equipment_id:
            try:
                equipment_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(Inspection.equipment_id == equipment_uuid)
            except Exception:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        elif enterprise_id or branch_id or workshop_id:
            subq = select(Equipment.id)
            if workshop_id:
                try:
                    ws_uuid = uuid_lib.UUID(workshop_id)
                    subq = subq.where(Equipment.workshop_id == ws_uuid)
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid workshop_id format")
            elif branch_id:
                try:
                    br_uuid = uuid_lib.UUID(branch_id)
                    subq = subq.where(Equipment.workshop_id.in_(select(Workshop.id).where(Workshop.branch_id == br_uuid)))
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid branch_id format")
            elif enterprise_id:
                try:
                    ent_uuid = uuid_lib.UUID(enterprise_id)
                    subq = subq.where(
                        Equipment.workshop_id.in_(
                            select(Workshop.id).where(
                                Workshop.branch_id.in_(select(Branch.id).where(Branch.enterprise_id == ent_uuid))
                            )
                        )
                    )
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid enterprise_id format")
            query = query.where(Inspection.equipment_id.in_(subq))

        if inspection_type:
            query = query.where(Inspection.inspection_type == inspection_type)
        if inspection_method:
            query = query.where(Inspection.inspection_method == inspection_method)
        if inspection_category:
            query = query.where(Inspection.inspection_category == inspection_category)

        if group_by in {"type", "method", "category", "type_method"}:
            grouped_query = query.order_by(
                nulls_last(Inspection.date_performed.desc()),
                nulls_last(Inspection.created_at.desc()),
            )
            grouped_result = await db.execute(grouped_query)
            grouped_inspections = grouped_result.scalars().all()
            groups: Dict[str, list] = {}
            for ins in grouped_inspections:
                if group_by == "type":
                    key = str(ins.inspection_type or "UNSPECIFIED")
                elif group_by == "method":
                    key = str(ins.inspection_method or "UNSPECIFIED")
                elif group_by == "category":
                    key = str(ins.inspection_category or "UNSPECIFIED")
                else:
                    key = f"{ins.inspection_type or 'UNSPECIFIED'}::{ins.inspection_method or 'UNSPECIFIED'}"
                groups.setdefault(key, []).append(ins)

            items = []
            for key, group_items in groups.items():
                sliced = group_items[skip : skip + limit]
                items.append(
                    {
                        "key": key,
                        "count": len(group_items),
                        "items": [
                            {
                                "id": str(ins.id),
                                "equipment_id": str(ins.equipment_id),
                                "date_performed": ins.date_performed.isoformat() if ins.date_performed else None,
                                "status": ins.status,
                                "inspection_type": ins.inspection_type,
                                "inspection_method": ins.inspection_method,
                                "inspection_category": ins.inspection_category,
                                "created_at": ins.created_at.isoformat() if ins.created_at else None,
                            }
                            for ins in sliced
                        ],
                    }
                )
            return {
                "grouped": True,
                "group_by": group_by,
                "groups": items,
                "total_groups": len(groups),
                "total": len(grouped_inspections),
            }
        # Сортировка: сначала по date_performed (если есть), затем по created_at, с учетом NULL
        query = query.order_by(
            nulls_last(Inspection.date_performed.desc()),
            nulls_last(Inspection.created_at.desc())
        )
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        inspections = result.scalars().all()
        
        # Получаем информацию об оборудовании для каждого inspection
        equipment_ids = [str(insp.equipment_id) for insp in inspections if insp.equipment_id]
        equipment_map = {}
        if equipment_ids:
            equipment_result = await db.execute(
                select(Equipment).where(Equipment.id.in_([uuid_lib.UUID(eid) for eid in equipment_ids]))
            )
            for eq in equipment_result.scalars().all():
                # Получаем информацию о цехе, филиале и предприятии
                enterprise_id = None
                enterprise_name = None
                branch_id = None
                branch_name = None
                workshop_id = None
                workshop_name = None
                
                if eq.workshop_id:
                    try:
                        workshop_result = await db.execute(
                            select(Workshop).where(Workshop.id == eq.workshop_id)
                        )
                        workshop = workshop_result.scalar_one_or_none()
                        if workshop:
                            workshop_id = str(workshop.id)
                            workshop_name = workshop.name
                            
                            # Получаем филиал
                            try:
                                branch_result = await db.execute(
                                    select(Branch).where(Branch.id == workshop.branch_id)
                                )
                                branch = branch_result.scalar_one_or_none()
                                if branch:
                                    branch_id = str(branch.id)
                                    branch_name = branch.name
                                    
                                    # Получаем предприятие
                                    try:
                                        enterprise_result = await db.execute(
                                            select(Enterprise).where(Enterprise.id == branch.enterprise_id)
                                        )
                                        enterprise = enterprise_result.scalar_one_or_none()
                                        if enterprise:
                                            enterprise_id = str(enterprise.id)
                                            enterprise_name = enterprise.name
                                    except Exception as e:
                                        await db.rollback()
                                        print(f"⚠️ Error loading enterprise for inspection equipment {eq.id}: {e}")
                            except Exception as e:
                                await db.rollback()
                                print(f"⚠️ Error loading branch for inspection equipment {eq.id}: {e}")
                    except Exception as e:
                        await db.rollback()
                        print(f"⚠️ Error loading workshop for inspection equipment {eq.id}: {e}")
                
                equipment_map[str(eq.id)] = {
                    "name": eq.name,
                    "location": eq.location,
                    "enterprise_id": enterprise_id,
                    "enterprise_name": enterprise_name,
                    "branch_id": branch_id,
                    "branch_name": branch_name,
                    "workshop_id": workshop_id,
                    "workshop_name": workshop_name,
                }
        
        return {
            "items": [
                {
                    "id": str(ins.id),
                    "equipment_id": str(ins.equipment_id),
                    "equipment_name": equipment_map.get(str(ins.equipment_id), {}).get("name"),
                    "equipment_location": equipment_map.get(str(ins.equipment_id), {}).get("location"),
                    "enterprise_id": equipment_map.get(str(ins.equipment_id), {}).get("enterprise_id"),
                    "enterprise_name": equipment_map.get(str(ins.equipment_id), {}).get("enterprise_name"),
                    "branch_id": equipment_map.get(str(ins.equipment_id), {}).get("branch_id"),
                    "branch_name": equipment_map.get(str(ins.equipment_id), {}).get("branch_name"),
                    "workshop_id": equipment_map.get(str(ins.equipment_id), {}).get("workshop_id"),
                    "workshop_name": equipment_map.get(str(ins.equipment_id), {}).get("workshop_name"),
                    "date_performed": ins.date_performed.isoformat() if ins.date_performed else None,
                    "data": ins.data,
                    "conclusion": ins.conclusion,
                    "status": ins.status,
                    "inspection_type": getattr(ins, "inspection_type", None),
                    "inspection_method": getattr(ins, "inspection_method", None),
                    "inspection_category": getattr(ins, "inspection_category", None),
                    "is_archived": getattr(ins, "is_archived", False),
                    "created_at": ins.created_at.isoformat() if ins.created_at else None,
                }
                for ins in inspections
            ],
            "total": len(inspections)
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_inspections: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении чеклистов: {error_detail}")


@app.get("/api/inspections/groups")
async def get_inspection_groups(
    group_by: str = "type",
    inspection_type: Optional[str] = None,
    inspection_method: Optional[str] = None,
    inspection_category: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Сводка по группам обследований без полного payload."""
    valid_group_by = {"type", "method", "category", "type_method"}
    if group_by not in valid_group_by:
        raise HTTPException(status_code=400, detail=f"group_by must be one of {sorted(valid_group_by)}")

    user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
    current_user = user_result.scalar_one_or_none()
    if not current_user:
        raise HTTPException(status_code=404, detail="User not found")

    query = select(Inspection)
    if current_user.role == "engineer":
        query = query.where(or_(Inspection.inspector_id == current_user.id, Inspection.performed_by == current_user.id))

    if inspection_type:
        query = query.where(Inspection.inspection_type == inspection_type)
    if inspection_method:
        query = query.where(Inspection.inspection_method == inspection_method)
    if inspection_category:
        query = query.where(Inspection.inspection_category == inspection_category)

    result = await db.execute(query)
    rows = result.scalars().all()
    grouped: Dict[str, int] = {}
    for ins in rows:
        if group_by == "type":
            key = str(ins.inspection_type or "UNSPECIFIED")
        elif group_by == "method":
            key = str(ins.inspection_method or "UNSPECIFIED")
        elif group_by == "category":
            key = str(ins.inspection_category or "UNSPECIFIED")
        else:
            key = f"{ins.inspection_type or 'UNSPECIFIED'}::{ins.inspection_method or 'UNSPECIFIED'}"
        grouped[key] = grouped.get(key, 0) + 1

    return {
        "grouped": True,
        "group_by": group_by,
        "groups": [{"key": k, "count": v} for k, v in sorted(grouped.items(), key=lambda x: x[0])],
        "total_groups": len(grouped),
        "total": len(rows),
    }


def _validate_create_inspection(data: dict) -> None:
    """Валидация тела запроса создания обследования. При ошибках бросает HTTPException с списком errors."""
    err = []
    eq_id = data.get("equipment_id")
    if not eq_id:
        err.append({"field": "equipment_id", "message": "equipment_id обязателен"})
    elif not isinstance(eq_id, str) or not str(eq_id).strip():
        err.append({"field": "equipment_id", "message": "equipment_id должен быть непустой строкой"})
    else:
        try:
            uuid_lib.UUID(str(eq_id))
        except (ValueError, TypeError):
            err.append({"field": "equipment_id", "message": "equipment_id должен быть валидным UUID"})
    st = data.get("status")
    if st is not None and str(st).strip():
        allowed = {"DRAFT", "SIGNED", "APPROVED", "COMPLETED"}
        if str(st).strip().upper() not in allowed:
            err.append({"field": "status", "message": f"status должен быть один из: {', '.join(sorted(allowed))}"})
    if "data" in data and data["data"] is not None and not isinstance(data["data"], dict):
        err.append({"field": "data", "message": "data должен быть объектом (словарём)"})
    aid = data.get("assignment_id")
    if aid is not None and str(aid).strip():
        try:
            uuid_lib.UUID(str(aid))
        except (ValueError, TypeError):
            err.append({"field": "assignment_id", "message": "assignment_id должен быть валидным UUID"})
    if err:
        raise HTTPException(status_code=400, detail=err)


@app.patch("/api/inspections/{inspection_id}/status", tags=["inspections"])
async def update_inspection_status(
    inspection_id: str,
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Изменить статус чек-листа/обследования (Inspection).
    Статусы: DRAFT, SIGNED, APPROVED
    - admin/chief_operator/operator: могут устанавливать любой из поддерживаемых статусов
    - engineer: может менять статус только своих инспекций и только на DRAFT/SIGNED
    """
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)

        # Совместимость: username в токене может быть email (старые токены / ввод email)
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        new_status = (payload.get("status") or "").strip().upper()
        allowed_statuses = {"DRAFT", "SIGNED", "APPROVED"}
        if new_status not in allowed_statuses:
            raise HTTPException(status_code=400, detail="Invalid status. Allowed: DRAFT, SIGNED, APPROVED")

        # RBAC
        if current_user.role in ["admin", "chief_operator", "operator"]:
            pass
        elif current_user.role == "engineer":
            if not (inspection.inspector_id and inspection.inspector_id == current_user.id):
                raise HTTPException(status_code=403, detail="Доступ запрещен")
            if new_status not in {"DRAFT", "SIGNED"}:
                raise HTTPException(status_code=403, detail="Инженер не может утверждать (APPROVED)")
        else:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        inspection.status = new_status
        inspection.updated_by = current_user.id
        await db.commit()
        await db.refresh(inspection)

        return {"status": "ok", "id": inspection_id, "new_status": inspection.status}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update inspection status: {str(e)}")

@app.post("/api/inspections", tags=["inspections"])
async def create_inspection(
    inspection_data: dict,
    username: Optional[str] = Depends(verify_token_optional),
    db: AsyncSession = Depends(get_db)
):
    """Create new inspection. При авторизации заполняются created_by (аудит)."""
    try:
        created_by_id = None
        if username:
            user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
            u = user_result.scalar_one_or_none()
            if u:
                created_by_id = u.id
        _validate_create_inspection(inspection_data)
        # Parse equipment_id
        equipment_id = None
        if inspection_data.get("equipment_id"):
            try:
                equipment_id = uuid_lib.UUID(inspection_data.get("equipment_id"))
            except (ValueError, TypeError):
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        # Parse date_performed if provided
        date_performed = None
        if inspection_data.get("date_performed"):
            try:
                date_performed = datetime.fromisoformat(inspection_data.get("date_performed").replace('Z', '+00:00'))
            except:
                pass
        
        # Parse project_id if provided
        project_id = None
        if inspection_data.get("project_id"):
            try:
                project_id = uuid_lib.UUID(inspection_data.get("project_id"))
            except:
                pass

        # Если в data указано include_opo_data=false, а у оборудования есть opo_id —
        # подтягиваем сохранённые данные ОПО и сливаем документы 1..9.
        try:
            inspection_data_dict = inspection_data.get("data", {}) or {}
            if isinstance(inspection_data_dict, dict):
                include_opo_data = inspection_data_dict.get("include_opo_data", True)
                if include_opo_data is False and equipment_id:
                    eq_result = await db.execute(select(Equipment).where(Equipment.id == equipment_id))
                    equipment = eq_result.scalar_one_or_none()
                    opo_id = getattr(equipment, "opo_id", None) if equipment else None
                    if opo_id:
                        opo_result = await db.execute(select(Opo).where(Opo.id == opo_id))
                        opo = opo_result.scalar_one_or_none()
                        survey = (opo.survey_data or {}) if opo else {}

                        # Мерджим documents[1..9] из survey в текущий documents
                        docs_current = inspection_data_dict.get("documents") or {}
                        if isinstance(docs_current, dict) and isinstance(survey, dict) and isinstance(survey.get("documents"), dict):
                            merged_docs = dict(docs_current)
                            for k, v in survey.get("documents").items():
                                try:
                                    n = int(str(k))
                                except Exception:
                                    continue
                                if 1 <= n <= 9:
                                    merged_docs[str(k)] = v
                            inspection_data_dict["documents"] = merged_docs

                        # Подтягиваем organization/executors, если не заполнены в чек-листе оборудования
                        if isinstance(survey, dict):
                            if not inspection_data_dict.get("organization") and survey.get("organization"):
                                inspection_data_dict["organization"] = survey.get("organization")
                            if not inspection_data_dict.get("executors") and survey.get("executors"):
                                inspection_data_dict["executors"] = survey.get("executors")

                            # Сохраняем survey отдельным блоком (для отчетов/просмотра)
                            inspection_data_dict["opo_survey"] = survey

                        inspection_data["data"] = inspection_data_dict
        except Exception:
            # Не блокируем создание инспекции из-за мерджа ОПО
            pass
        
        inspection_payload_data = inspection_data.get("data", {}) if isinstance(inspection_data.get("data", {}), dict) else {}
        inspection_type_value = (
            inspection_data.get("inspection_type")
            or inspection_payload_data.get("inspection_type")
        )
        if not inspection_type_value:
            if inspection_payload_data.get("weld_inspections") or inspection_payload_data.get("thickness_measurements"):
                inspection_type_value = "NDT"
            elif inspection_payload_data.get("documents") or inspection_payload_data.get("questionnaire"):
                inspection_type_value = "QUESTIONNAIRE"
            else:
                inspection_type_value = "VISUAL"

        inspection_method_value = (
            inspection_data.get("inspection_method")
            or inspection_payload_data.get("inspection_method")
            or inspection_payload_data.get("method_code")
        )
        inspection_category_value = (
            inspection_data.get("inspection_category")
            or inspection_payload_data.get("inspection_category")
        )

        new_inspection = Inspection(
            equipment_id=equipment_id,
            project_id=project_id,
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT"),
            date_performed=date_performed,
            inspection_type=inspection_type_value,
            inspection_method=inspection_method_value,
            inspection_category=inspection_category_value,
            is_archived=False,  # Явно устанавливаем значение
            created_by=created_by_id,
        )
        db.add(new_inspection)
        await db.flush()
        await _log_audit(
            db, created_by_id, "CREATE", "inspection", new_inspection.id,
            {"equipment_id": str(equipment_id), "status": inspection_data.get("status", "DRAFT")},
        )
        await db.commit()
        await db.refresh(new_inspection)
        
        # Если это чек-лист сосуда (vessel checklist), создаем questionnaire (чтобы мобильное могло загрузить фото/сканы)
        questionnaire_id = None
        inspection_data_dict = inspection_data.get("data", {})
        if inspection_data_dict and isinstance(inspection_data_dict, dict):
            has_vessel_data = (
                inspection_data_dict.get("documents")
                or inspection_data_dict.get("vessel_name")
                or inspection_data_dict.get("factory_plate_photo")
                or inspection_data_dict.get("control_scheme_image")
                or (inspection_data_dict.get("visual_defects") and len(inspection_data_dict.get("visual_defects") or []) > 0)
                or (inspection_data_dict.get("thickness_measurements") and len(inspection_data_dict.get("thickness_measurements") or []) > 0)
            )
            if has_vessel_data:
                # Получаем информацию об оборудовании
                eq_result = await db.execute(
                    select(Equipment).where(Equipment.id == equipment_id)
                )
                equipment = eq_result.scalar_one_or_none()
                
                # Извлекаем данные из inspection_data
                inspection_date_str = inspection_data_dict.get("inspection_date")
                inspection_date_obj = None
                if inspection_date_str:
                    try:
                        if isinstance(inspection_date_str, str):
                            inspection_date_obj = datetime.fromisoformat(inspection_date_str.replace('Z', '+00:00')).date()
                    except:
                        pass
                
                # Создаем questionnaire (только поля из модели: equipment_id, data, date_performed, status, assignment_id)
                assignment_id_q = None
                if inspection_data.get("assignment_id"):
                    try:
                        assignment_id_q = uuid_lib.UUID(inspection_data.get("assignment_id"))
                    except Exception:
                        pass
                new_questionnaire = Questionnaire(
                    equipment_id=equipment_id,
                    data=inspection_data_dict,
                    date_performed=date_performed,
                    status=inspection_data.get("status", "DRAFT"),
                    assignment_id=assignment_id_q,
                    created_by=created_by_id,
                )
                db.add(new_questionnaire)
                await db.commit()
                await db.refresh(new_questionnaire)
                questionnaire_id = str(new_questionnaire.id)
                # Привязываем инспекцию к опросному листу (для отчётов и загрузки документов)
                new_inspection.questionnaire_id = new_questionnaire.id
                await db.commit()
                await db.refresh(new_inspection)
                _create_ndt_methods_from_mobile(
                    db, new_inspection, new_questionnaire, equipment_id, inspection_data_dict
                )
                await db.commit()
        
        # Создаем запись в истории обследований (версия 3.3.0)
        assignment_id = None
        if inspection_data.get("assignment_id"):
            try:
                assignment_id = uuid_lib.UUID(inspection_data.get("assignment_id"))
            except:
                pass
        
        # Определяем тип обследования
        inspection_type = "VISUAL"
        if inspection_data_dict:
            if inspection_data_dict.get("documents") or inspection_data_dict.get("vessel_name"):
                inspection_type = "QUESTIONNAIRE"
            elif inspection_data_dict.get("ndt_methods") or inspection_data_dict.get("method_code"):
                inspection_type = "NDT"
        
        # Получаем ID инженера из данных или из токена
        inspector_id = None
        if inspection_data_dict.get("inspector_id"):
            try:
                inspector_id = uuid_lib.UUID(inspection_data_dict.get("inspector_id"))
            except:
                pass
        
        # Создаем запись в истории
        history_entry = InspectionHistory(
            equipment_id=equipment_id,
            assignment_id=assignment_id,
            inspection_type=inspection_type,
            inspector_id=inspector_id,
            inspection_date=date_performed or datetime.now(),
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT")
        )
        db.add(history_entry)
        await db.commit()
        await db.refresh(history_entry)

        # Обновляем статус задания (чтобы у инженера отмечалось выполнено/не выполнено)
        if assignment_id:
            try:
                assignment_result = await db.execute(
                    select(Assignment).where(Assignment.id == assignment_id)
                )
                assignment = assignment_result.scalar_one_or_none()
                if assignment:
                    insp_status = (inspection_data.get("status") or "DRAFT").upper()
                    if insp_status == "SIGNED":
                        assignment.status = "COMPLETED"
                        assignment.completed_at = datetime.now()
                        # Обновляем equipment.attributes теххарактеристикой из обследования
                        try:
                            data_dict = inspection_data.get("data") or {}
                            if data_dict and isinstance(data_dict, dict):
                                await _update_equipment_attrs(db, equipment_id, data_dict)
                        except Exception:
                            pass
                    elif insp_status == "DRAFT":
                        # Черновик — это "в работе"
                        if assignment.status not in ["COMPLETED", "CANCELLED"]:
                            assignment.status = "IN_PROGRESS"
                    else:
                        # Прочие статусы не меняем, чтобы не ломать логику
                        pass
                    await db.commit()
            except Exception:
                # Не блокируем создание инспекции из-за статуса задания
                await db.rollback()
        
        return {
            "id": str(new_inspection.id),
            "equipment_id": str(new_inspection.equipment_id),
            "questionnaire_id": questionnaire_id,
            "history_id": str(history_entry.id),  # ID записи в истории (версия 3.3.0)
            "status": "created",
            "date_performed": new_inspection.date_performed.isoformat() if new_inspection.date_performed else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create inspection: {str(e)}")

# Clients endpoints
@app.get("/api/clients")
async def get_clients(
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get list of clients"""
    try:
        # Используем прямой SQL запрос, чтобы избежать проблем с отсутствующими колонками
        from sqlalchemy import text
        # Используем только базовые колонки, которые точно есть в БД
        query = text("""
            SELECT id, name, inn, address, contact_person
            FROM clients
            LIMIT :limit OFFSET :offset
        """)
        result = await db.execute(query, {"limit": limit, "offset": skip})
        clients = result.fetchall()
        items = []
        for row in clients:
            try:
                items.append({
                    "id": str(row[0]),  # id
                    "name": row[1] if row[1] else None,  # name
                    "inn": row[2] if row[2] else None,  # inn
                    "address": row[3] if row[3] else None,  # address
                    "contact_person": row[4] if row[4] else None,  # contact_person
                    "contact_phone": None,  # будет добавлено позже если нужно
                    "contact_email": None,  # будет добавлено позже если нужно
                })
            except Exception as e:
                # Если какое-то поле отсутствует, пропускаем его
                continue
        
        return {
            "items": items,
            "total": len(items)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/clients")
async def create_client(client_data: dict, db: AsyncSession = Depends(get_db)):
    """Create new client"""
    try:
        # Используем прямой SQL запрос, проверяя наличие колонок
        from sqlalchemy import text
        import uuid as uuid_lib
        
        # Проверяем какие колонки есть в таблице
        check_query = text("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'clients'
        """)
        result = await db.execute(check_query)
        columns = [row[0] for row in result.fetchall()]
        
        client_id = uuid_lib.uuid4()
        
        # Формируем список колонок и значений в зависимости от наличия колонок в БД
        insert_cols = ["id", "name", "created_at", "updated_at"]
        insert_vals = [":id", ":name", "NOW()", "NOW()"]
        params = {
            "id": client_id,
            "name": client_data.get("name"),
        }
        
        # Добавляем колонки только если они существуют
        if "inn" in columns:
            insert_cols.append("inn")
            insert_vals.append(":inn")
            params["inn"] = client_data.get("inn") or None
        
        if "address" in columns:
            insert_cols.append("address")
            insert_vals.append(":address")
            params["address"] = client_data.get("address") or None
        
        if "contact_person" in columns:
            insert_cols.append("contact_person")
            insert_vals.append(":contact_person")
            params["contact_person"] = client_data.get("contact_person") or None
        
        if "phone" in columns:
            insert_cols.append("phone")
            insert_vals.append(":phone")
            params["phone"] = client_data.get("contact_phone") or client_data.get("phone") or None
        
        if "email" in columns:
            insert_cols.append("email")
            insert_vals.append(":email")
            params["email"] = client_data.get("contact_email") or client_data.get("email") or None
        
        query = text(f"""
            INSERT INTO clients ({', '.join(insert_cols)})
            VALUES ({', '.join(insert_vals)})
            RETURNING id
        """)
        
        result = await db.execute(query, params)
        await db.commit()
        
        return {"id": str(client_id), "status": "created"}
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/inspections/{inspection_id}")
async def delete_inspection(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Удаление чек-листа (inspection).
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои (по inspector_id)
    При удалении также удаляются связанные отчеты (reports) и методы НК (ndt_methods) по inspection_id.
    """
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)

        # Совместимость: username в токене может быть email
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        # Права
        allowed = False
        if current_user.role in ["admin", "chief_operator", "operator"]:
            allowed = True
        elif current_user.role == "engineer":
            if inspection.inspector_id and inspection.inspector_id == current_user.id:
                allowed = True
        if not allowed:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Удаляем связанные отчеты и их файлы (сначала отчёты, иначе FK violation)
        rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
        related_reports = rep_result.scalars().all()
        for report in related_reports:
            for p in [report.file_path, getattr(report, "word_file_path", None)]:
                if p:
                    try:
                        fp = Path(p)
                        if fp.exists():
                            fp.unlink()
                    except Exception:
                        pass
            await db.delete(report)
        await db.flush()

        # Удаляем связанные методы НК (новая схема привязки к inspection_id)
        try:
            ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
            for m in ndt_result.scalars().all():
                await db.delete(m)
            await db.flush()
        except Exception:
            pass

        await db.delete(inspection)
        await db.commit()
        return {"status": "deleted", "id": inspection_id, "reports_deleted": len(related_reports)}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete inspection: {str(e)}")


@app.delete("/api/inspections/cleanup")
async def cleanup_inspections(
    older_than_days: int = 180,
    before: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Массовое удаление старых чек-листов (inspections) и связанных отчетов/методов НК.
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои
    """
    try:
        # Совместимость: username в токене может быть email
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        cutoff = None
        if before:
            try:
                cutoff = datetime.fromisoformat(before.replace("Z", "+00:00"))
            except Exception:
                try:
                    cutoff = datetime.strptime(before, "%Y-%m-%d")
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid 'before' format")
        else:
            if older_than_days < 1:
                raise HTTPException(status_code=400, detail="older_than_days must be >= 1")
            cutoff = datetime.now() - timedelta(days=int(older_than_days))

        insp_query = select(Inspection).where(Inspection.created_at < cutoff)
        if current_user.role == "engineer":
            insp_query = insp_query.where(Inspection.inspector_id == current_user.id)
        elif current_user.role not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        insp_result = await db.execute(insp_query)
        inspections = insp_result.scalars().all()

        deleted = 0
        reports_deleted = 0
        for inspection in inspections:
            # связанные отчеты (сначала отчёты, иначе FK violation)
            rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
            related_reports = rep_result.scalars().all()
            for report in related_reports:
                for p in [report.file_path, getattr(report, "word_file_path", None)]:
                    if p:
                        try:
                            fp = Path(p)
                            if fp.exists():
                                fp.unlink()
                        except Exception:
                            pass
                await db.delete(report)
                reports_deleted += 1
            if related_reports:
                await db.flush()

            # методы НК
            try:
                ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
                for m in ndt_result.scalars().all():
                    await db.delete(m)
                await db.flush()
            except Exception:
                pass

            await db.delete(inspection)
            deleted += 1

        await db.commit()
        return {"status": "ok", "deleted": deleted, "reports_deleted": reports_deleted, "cutoff": cutoff.isoformat()}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to cleanup inspections: {str(e)}")

# Projects endpoints
@app.get("/api/projects")
async def get_projects(
    client_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get list of projects"""
    try:
        query = select(Project)
        if client_id:
            try:
                client_uuid = uuid_lib.UUID(client_id)
                query = query.where(Project.client_id == client_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid client_id format")
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        projects = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(p.id),
                    "client_id": str(p.client_id),
                    "name": p.name,
                    "description": p.description,
                    "status": p.status,
                    "start_date": str(p.start_date) if p.start_date else None,
                    "end_date": str(p.end_date) if p.end_date else None,
                    "deadline": str(p.deadline) if p.deadline else None,
                    "budget": float(p.budget) if p.budget else None,
                }
                for p in projects
            ],
            "total": len(projects)
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"❌ Error in get_reports: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/projects")
async def create_project(project_data: dict, db: AsyncSession = Depends(get_db)):
    """Create new project"""
    try:
        client_id = None
        if project_data.get("client_id"):
            try:
                client_id = uuid_lib.UUID(project_data.get("client_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid client_id format")
        
        # Преобразуем deadline в end_date если deadline указан, иначе используем end_date
        deadline_date = None
        if project_data.get("deadline"):
            try:
                deadline_date = datetime.fromisoformat(project_data.get("deadline").replace('Z', '+00:00')).date()
            except:
                try:
                    deadline_date = datetime.fromisoformat(project_data.get("deadline")).date()
                except:
                    pass
        
        end_date_val = None
        if project_data.get("end_date"):
            try:
                end_date_val = datetime.fromisoformat(project_data.get("end_date").replace('Z', '+00:00')).date()
            except:
                try:
                    end_date_val = datetime.fromisoformat(project_data.get("end_date")).date()
                except:
                    pass
        
        new_project = Project(
            client_id=client_id,
            name=project_data.get("name"),
            description=project_data.get("description"),
            status=project_data.get("status", "PLANNED"),
            start_date=datetime.fromisoformat(project_data.get("start_date").replace('Z', '+00:00')).date() if project_data.get("start_date") else None,
            end_date=end_date_val,
            deadline=deadline_date,
            budget=float(project_data.get("budget")) if project_data.get("budget") else None
        )
        db.add(new_project)
        await db.commit()
        await db.refresh(new_project)
        return {"id": str(new_project.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Equipment Resource endpoints
@app.get("/api/equipment-resources")
async def get_equipment_resources(
    equipment_id: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Get equipment resources"""
    try:
        query = select(EquipmentResource)
        if equipment_id:
            try:
                eq_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(EquipmentResource.equipment_id == eq_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        result = await db.execute(query.order_by(EquipmentResource.created_at.desc()))
        resources = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(r.id),
                    "equipment_id": str(r.equipment_id),
                    "remaining_resource_years": float(r.remaining_resource_years) if r.remaining_resource_years else None,
                    "resource_end_date": str(r.resource_end_date) if r.resource_end_date else None,
                    "extension_years": float(r.extension_years) if r.extension_years else None,
                    "extension_date": str(r.extension_date) if r.extension_date else None,
                    "status": r.status,
                    "document_number": r.document_number,
                }
                for r in resources
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"❌ Error in get_reports: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/equipment-resources")
async def create_equipment_resource(resource_data: dict, db: AsyncSession = Depends(get_db)):
    """Create equipment resource record"""
    try:
        equipment_id = None
        if resource_data.get("equipment_id"):
            try:
                equipment_id = uuid_lib.UUID(resource_data.get("equipment_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        new_resource = EquipmentResource(
            equipment_id=equipment_id,
            remaining_resource_years=resource_data.get("remaining_resource_years"),
            resource_end_date=datetime.fromisoformat(resource_data.get("resource_end_date")).date() if resource_data.get("resource_end_date") else None,
            extension_years=resource_data.get("extension_years"),
            extension_date=datetime.fromisoformat(resource_data.get("extension_date")).date() if resource_data.get("extension_date") else None,
            calculation_method=resource_data.get("calculation_method"),
            calculation_data=resource_data.get("calculation_data", {}),
            document_number=resource_data.get("document_number"),
            status=resource_data.get("status", "ACTIVE")
        )
        db.add(new_resource)
        await db.commit()
        await db.refresh(new_resource)
        return {"id": str(new_resource.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Regulatory Documents endpoints
@app.get("/api/regulatory-documents")
async def get_regulatory_documents(
    document_type: Optional[str] = None,
    equipment_type: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Get regulatory documents"""
    try:
        query = select(RegulatoryDocument).where(RegulatoryDocument.is_active == 1)
        if document_type:
            query = query.where(RegulatoryDocument.document_type == document_type)
        
        result = await db.execute(query)
        docs = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(d.id),
                    "document_type": d.document_type,
                    "number": d.number,
                    "name": d.name,
                    "description": d.description,
                    "equipment_types": d.equipment_types,
                    "effective_date": str(d.effective_date) if d.effective_date else None,
                    "expiry_date": str(d.expiry_date) if d.expiry_date else None,
                }
                for d in docs
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/regulatory-documents")
async def create_regulatory_document(doc_data: dict, db: AsyncSession = Depends(get_db)):
    """Create regulatory document"""
    try:
        new_doc = RegulatoryDocument(
            document_type=doc_data.get("document_type"),
            number=doc_data.get("number"),
            name=doc_data.get("name"),
            description=doc_data.get("description"),
            content=doc_data.get("content"),
            file_path=doc_data.get("file_path"),
            equipment_types=doc_data.get("equipment_types", []),
            requirements=doc_data.get("requirements", {}),
            effective_date=datetime.fromisoformat(doc_data.get("effective_date")).date() if doc_data.get("effective_date") else None,
            expiry_date=datetime.fromisoformat(doc_data.get("expiry_date")).date() if doc_data.get("expiry_date") else None,
        )
        db.add(new_doc)
        await db.commit()
        await db.refresh(new_doc)
        return {"id": str(new_doc.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Engineers endpoints
@app.get("/api/engineers")
async def get_engineers(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get list of engineers (кэш 5 мин)"""
    cached = _cache_get("engineers")
    if cached is not None:
        return cached
    try:
        result = await db.execute(select(Engineer).where(Engineer.is_active == 1))
        engineers = result.scalars().all()

        # Подтягиваем удостоверения/сертификаты инженеров (для мобильного: подбор специалиста по виду НК)
        certs_by_engineer: Dict[str, List[Dict[str, Any]]] = {}
        try:
            from models import Certification

            def _norm_method_code(raw: Any) -> str:
                s = str(raw or "").strip().upper()
                mapping = {
                    "ВИК": "VIK",
                    "УЗК": "UZK",
                    "УЗТ": "UZT",
                    "ПВК": "PVK",
                    "МК": "MK",
                    "РК": "RK",
                    "МПД": "MPD",
                    "КПД": "KPD",
                    "ТВИ": "TVI",
                    "ВТК": "VTK",
                    "АК": "AK",
                    "ТК": "TK",
                }
                return mapping.get(s, s)

            eng_ids = [e.id for e in engineers if getattr(e, "id", None)]
            if eng_ids:
                certs_res = await db.execute(select(Certification).where(Certification.engineer_id.in_(eng_ids)))
                certs = certs_res.scalars().all()
                for c in certs:
                    try:
                        eid = str(getattr(c, "engineer_id", "") or "")
                        if not eid:
                            continue
                        raw_method = getattr(c, "method_code", None)
                        method_code_norm = _norm_method_code(raw_method)
                        # method_code — как в БД (ВИК, УЗК), для совпадения с методами НК; method — нормализованный (VIK, UZK)
                        method_code_original = (raw_method if raw_method and str(raw_method).strip() else method_code_norm)
                        cert_num = getattr(c, "certificate_number", None) or ""
                        expiry = getattr(c, "expiry_date", None)
                        expiry_str = str(expiry) if expiry else ""
                        item = {
                            "method": method_code_norm,
                            "method_code": method_code_original,
                            # для отображения в UI (разные ключи поддержаны)
                            "certificate_number": cert_num,
                            "number": cert_num,
                            "expiry_date": expiry_str,
                            "valid_until": expiry_str,
                            "certification_type": getattr(c, "certification_type", None) or "",
                            "certification_areas": _cert_areas_list(c),
                        }
                        certs_by_engineer.setdefault(eid, []).append(item)
                    except Exception:
                        continue
        except Exception:
            certs_by_engineer = {}

        items = []
        for e in engineers:
            try:
                eid = str(e.id)
                # Если в карточке инженера qualifications пустой — используем удостоверения из Certification
                q = e.qualifications if e.qualifications is not None else []
                if (not q) and certs_by_engineer.get(eid):
                    q = certs_by_engineer[eid]
                items.append({
                    "id": eid,
                    "full_name": e.full_name or "",
                    "position": e.position or "",
                    "email": e.email or "",
                    "phone": e.phone or "",
                    "qualifications": q,
                    "equipment_types": e.equipment_types if e.equipment_types is not None else [],
                })
            except Exception as item_error:
                import traceback
                print(f"Error processing engineer {e.id}: {item_error}")
                traceback.print_exc()
                continue
        
        response = {"items": items}
        _cache_set("engineers", response)
        return response
    except Exception as e:
        import traceback
        print(f"Error in get_engineers: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/users")
async def get_users(
    role: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список пользователей"""
    try:
        # Проверяем права доступа (только admin и chief_operator)
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        # Теперь is_active имеет тип INTEGER, можно использовать прямое сравнение
        query = select(User).where(User.is_active == 1)
        if role:
            query = query.where(User.role == role)
        
        result = await db.execute(query.order_by(User.username))
        users = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(u.id),
                    "username": u.username,
                    "email": u.email,
                    "full_name": u.full_name,
                    "role": u.role,
                    "engineer_id": str(u.engineer_id) if u.engineer_id else None,
                }
                for u in users
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get users: {str(e)}")

@app.post("/api/engineers")
async def create_engineer(engineer_data: dict, db: AsyncSession = Depends(get_db)):
    """Create engineer"""
    try:
        new_engineer = Engineer(
            full_name=engineer_data.get("full_name"),
            position=engineer_data.get("position"),
            email=engineer_data.get("email"),
            phone=engineer_data.get("phone"),
            qualifications=engineer_data.get("qualifications", []),
            equipment_types=engineer_data.get("equipment_types", []),
        )
        db.add(new_engineer)
        await db.commit()
        await db.refresh(new_engineer)
        
        # Если есть сертификаты, создаем их отдельно
        certifications_data = engineer_data.get("certifications", [])
        if certifications_data:
            from models import Certification
            for cert_data in certifications_data:
                cert = Certification(
                    engineer_id=new_engineer.id,
                    certification_type=cert_data.get("certification_type"),
                    method=cert_data.get("method"),
                    level=cert_data.get("level"),
                    number=cert_data.get("number"),
                    issued_by=cert_data.get("issued_by"),
                    issue_date=cert_data.get("issue_date"),
                    expiry_date=cert_data.get("expiry_date"),
                    is_active=1
                )
                db.add(cert)
            await db.commit()
        
        _cache_invalidate("engineers")
        return {"id": str(new_engineer.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Certifications endpoints
@app.get("/api/certifications")
async def get_certifications(
    engineer_id: Optional[str] = None,
    method_code: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get certifications (method_code — фильтр по виду НК для мобильной синхронизации)"""
    try:
        query = select(Certification).where(Certification.is_active == 1)
        if engineer_id:
            try:
                eng_uuid = uuid_lib.UUID(engineer_id)
                query = query.where(Certification.engineer_id == eng_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid engineer_id format")
        if method_code:
            query = query.where(Certification.method_code == method_code)
        
        result = await db.execute(query)
        certs = result.scalars().all()
        items = []
        for c in certs:
            try:
                items.append({
                    "id": str(c.id),
                    "engineer_id": str(c.engineer_id) if c.engineer_id else None,
                    "certification_type": c.certification_type or "",
                    "certificate_number": c.certificate_number or "",
                    "number": c.certificate_number or "",  # Для обратной совместимости
                    "issued_by": c.issuing_organization or "",
                    "issuing_organization": c.issuing_organization or "",
                    "issue_date": str(c.issue_date) if c.issue_date else None,
                    "expiry_date": str(c.expiry_date) if c.expiry_date else None,
                    "document_number": c.document_number or None,
                    "document_date": str(c.document_date) if c.document_date else None,
                    "method_code": c.method_code or None,
                    "certification_areas": _cert_areas_list(c),
                    "certification_area": (_cert_areas_list(c)[0] if _cert_areas_list(c) else None),
                    "equipment_type_id": str(c.equipment_type_id) if c.equipment_type_id else None,
                    "scan_file_name": getattr(c, "scan_file_name", None),
                    "scan_file_size": getattr(c, "scan_file_size", None),
                    "scan_mime_type": getattr(c, "scan_mime_type", None),
                })
            except Exception as item_error:
                import traceback
                print(f"Error processing certification {c.id if c else 'unknown'}: {item_error}")
                traceback.print_exc()
                continue
        
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/certifications")
async def create_certification(
    certification_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать сертификат"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        engineer_id = uuid_lib.UUID(certification_data.get("engineer_id"))
        
        method_code = certification_data.get("method_code") or None
        equipment_type_id = None
        if certification_data.get("equipment_type_id"):
            try:
                equipment_type_id = uuid_lib.UUID(certification_data.get("equipment_type_id"))
            except:
                pass
        areas_raw = certification_data.get("certification_areas")
        if not isinstance(areas_raw, list):
            areas_raw = [certification_data.get("certification_area")] if certification_data.get("certification_area") else []
        cert_areas = [str(a).strip() for a in areas_raw if a]
        
        certification = Certification(
            engineer_id=engineer_id,
            certification_type=certification_data.get("certification_type"),
            certificate_number=certification_data.get("certificate_number"),
            method_code=method_code,
            certification_areas=cert_areas if cert_areas else None,
            certification_area=cert_areas[0] if cert_areas else None,
            equipment_type_id=equipment_type_id,
            issue_date=datetime.strptime(certification_data.get("issue_date"), "%Y-%m-%d").date() if certification_data.get("issue_date") else None,
            expiry_date=datetime.strptime(certification_data.get("expiry_date"), "%Y-%m-%d").date() if certification_data.get("expiry_date") else None,
            issuing_organization=certification_data.get("issuing_organization"),
            document_number=certification_data.get("document_number"),
            document_date=datetime.strptime(certification_data.get("document_date"), "%Y-%m-%d").date() if certification_data.get("document_date") else None,
            is_active=1
        )
        
        db.add(certification)
        await db.commit()
        await db.refresh(certification)
        
        return {
            "id": str(certification.id),
            "engineer_id": str(certification.engineer_id),
            "certification_type": certification.certification_type,
            "certificate_number": certification.certificate_number,
            "method_code": certification.method_code,
            "certification_areas": getattr(certification, "certification_areas", None) or _cert_areas_list(certification),
            "certification_area": (getattr(certification, "certification_areas", None) or [])[0] if (getattr(certification, "certification_areas", None) or []) else getattr(certification, "certification_area", None),
            "equipment_type_id": str(certification.equipment_type_id) if certification.equipment_type_id else None,
            "issue_date": str(certification.issue_date) if certification.issue_date else None,
            "expiry_date": str(certification.expiry_date) if certification.expiry_date else None,
            "issuing_organization": certification.issuing_organization,
            "document_number": certification.document_number,
            "document_date": str(certification.document_date) if certification.document_date else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid date format: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create certification: {str(e)}")

@app.put("/api/certifications/{certification_id}")
async def update_certification(
    certification_id: str,
    certification_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Обновить сертификат"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(
            select(Certification).where(Certification.id == cert_uuid)
        )
        certification = result.scalar_one_or_none()
        
        if not certification:
            raise HTTPException(status_code=404, detail="Сертификат не найден")
        
        if "certification_type" in certification_data:
            certification.certification_type = certification_data["certification_type"]
        if "certificate_number" in certification_data:
            certification.certificate_number = certification_data["certificate_number"]
        if "issue_date" in certification_data:
            certification.issue_date = datetime.strptime(certification_data["issue_date"], "%Y-%m-%d").date() if certification_data["issue_date"] else None
        if "expiry_date" in certification_data:
            certification.expiry_date = datetime.strptime(certification_data["expiry_date"], "%Y-%m-%d").date() if certification_data["expiry_date"] else None
        if "issuing_organization" in certification_data:
            certification.issuing_organization = certification_data["issuing_organization"]
        if "document_number" in certification_data:
            certification.document_number = certification_data["document_number"]
        if "document_date" in certification_data:
            certification.document_date = datetime.strptime(certification_data["document_date"], "%Y-%m-%d").date() if certification_data["document_date"] else None
        if "method_code" in certification_data:
            certification.method_code = certification_data["method_code"] or None
        if "certification_areas" in certification_data:
            areas_raw = certification_data.get("certification_areas")
            cert_areas = [str(a).strip() for a in (areas_raw if isinstance(areas_raw, list) else []) if a]
            certification.certification_areas = cert_areas if cert_areas else None
            certification.certification_area = cert_areas[0] if cert_areas else None
        elif "certification_area" in certification_data:
            single = (certification_data.get("certification_area") or "").strip() or None
            certification.certification_area = single
            certification.certification_areas = [single] if single else None
        if "equipment_type_id" in certification_data:
            if certification_data["equipment_type_id"]:
                try:
                    certification.equipment_type_id = uuid_lib.UUID(certification_data["equipment_type_id"])
                except:
                    certification.equipment_type_id = None
            else:
                certification.equipment_type_id = None
        
        await db.commit()
        await db.refresh(certification)
        
        return {
            "id": str(certification.id),
            "engineer_id": str(certification.engineer_id),
            "certification_type": certification.certification_type,
            "certificate_number": certification.certificate_number,
            "method_code": certification.method_code,
            "certification_areas": getattr(certification, "certification_areas", None) or _cert_areas_list(certification),
            "certification_area": (_cert_areas_list(certification)[0] if _cert_areas_list(certification) else None),
            "equipment_type_id": str(certification.equipment_type_id) if certification.equipment_type_id else None,
            "issue_date": str(certification.issue_date) if certification.issue_date else None,
            "expiry_date": str(certification.expiry_date) if certification.expiry_date else None,
            "issuing_organization": certification.issuing_organization,
            "document_number": certification.document_number,
            "document_date": str(certification.document_date) if certification.document_date else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid date format: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update certification: {str(e)}")

@app.delete("/api/certifications/{certification_id}")
async def delete_certification(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить сертификат (мягкое удаление)"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(
            select(Certification).where(Certification.id == cert_uuid)
        )
        certification = result.scalar_one_or_none()
        
        if not certification:
            raise HTTPException(status_code=404, detail="Сертификат не найден")
        
        certification.is_active = 0
        await db.commit()
        
        return {"message": "Сертификат успешно удален"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete certification: {str(e)}")


@app.post("/api/certifications/{certification_id}/scan")
async def upload_certification_scan(
    certification_id: str,
    file: UploadFile = File(...),
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить скан сертификата (фото/PDF)"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        allowed = {
            "application/pdf",
            "image/jpeg",
            "image/png",
            "image/webp",
        }
        if file.content_type and file.content_type not in allowed:
            raise HTTPException(status_code=400, detail="Разрешены только фото (JPEG/PNG/WEBP) или PDF")

        uploads_dir = Path("/app/uploads/certification_scans") / str(cert.id)
        uploads_dir.mkdir(parents=True, exist_ok=True)

        safe_name = (file.filename or "scan").replace("\\", "_").replace("/", "_")
        stored_name = f"{uuid_lib.uuid4()}_{safe_name}"
        stored_path = uploads_dir / stored_name

        # Удаляем старый файл, если был
        old_path = getattr(cert, "scan_file_path", None)
        if old_path:
            try:
                old_p = Path(old_path)
                if old_p.exists():
                    old_p.unlink()
            except Exception:
                pass

        size = 0
        with stored_path.open("wb") as f:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                f.write(chunk)

        cert.scan_file_path = str(stored_path)
        cert.scan_file_name = file.filename
        cert.scan_file_size = size
        cert.scan_mime_type = file.content_type

        await db.commit()
        await db.refresh(cert)

        return {
            "id": str(cert.id),
            "scan_file_name": cert.scan_file_name,
            "scan_file_size": cert.scan_file_size,
            "scan_mime_type": cert.scan_mime_type,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to upload scan: {str(e)}")


@app.get("/api/certifications/{certification_id}/scan")
async def download_certification_scan(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Скачать скан сертификата"""
    try:
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        scan_path = getattr(cert, "scan_file_path", None)
        if not scan_path or not Path(scan_path).exists():
            raise HTTPException(status_code=404, detail="Скан не найден")

        return FileResponse(
            path=scan_path,
            filename=(getattr(cert, "scan_file_name", None) or "certificate-scan"),
            media_type=(getattr(cert, "scan_mime_type", None) or "application/octet-stream"),
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to download scan: {str(e)}")


@app.delete("/api/certifications/{certification_id}/scan")
async def delete_certification_scan(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить скан сертификата"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        scan_path = getattr(cert, "scan_file_path", None)
        if scan_path:
            try:
                p = Path(scan_path)
                if p.exists():
                    p.unlink()
            except Exception:
                pass

        cert.scan_file_path = None
        cert.scan_file_name = None
        cert.scan_file_size = None
        cert.scan_mime_type = None
        await db.commit()

        return {"message": "Скан удален"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete scan: {str(e)}")

# Reports endpoints
@app.get("/api/reports")
async def get_reports(
    inspection_id: Optional[str] = None,
    equipment_id: Optional[str] = None,
    project_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get reports (с учетом прав: инженер видит только свои отчеты)"""
    try:
        # Текущий пользователь и роль
        # Совместимость: username в токене может быть email (старые токены / ввод email)
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        query = select(Report)
        # Временно НЕ фильтруем по is_archived, чтобы показать все отчеты
        # Фильтрация будет добавлена позже, когда будет уверенность, что поле корректно работает
        # query = query.where(Report.is_archived == False)
        if inspection_id:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                query = query.where(Report.inspection_id == insp_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid inspection_id format")
        # Фильтрация по equipment_id и project_id через связанные инспекции
        if equipment_id:
            try:
                eq_uuid = uuid_lib.UUID(equipment_id)
                # Фильтруем через связанные инспекции
                insp_subquery = select(Inspection.id).where(Inspection.equipment_id == eq_uuid)
                query = query.where(Report.inspection_id.in_(insp_subquery))
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        if project_id:
            try:
                proj_uuid = uuid_lib.UUID(project_id)
                # Фильтруем через связанные инспекции
                insp_subquery = select(Inspection.id).where(Inspection.project_id == proj_uuid)
                query = query.where(Report.inspection_id.in_(insp_subquery))
            except:
                raise HTTPException(status_code=400, detail="Invalid project_id format")

        # Ограничиваем инженера только своими отчетами.
        # created_by хранится как UUID (users.id). Фолбэк для старых записей: если created_by пустой,
        # пытаемся определить по inspection.inspector_id.
        if current_user.role == "engineer":
            query = (
                query.join(Inspection, Report.inspection_id == Inspection.id, isouter=True)
                .where(
                    or_(
                        Report.created_by == current_user.id,
                        and_(
                            Report.created_by.is_(None),
                            or_(
                                Inspection.inspector_id == current_user.id,
                                Inspection.performed_by == current_user.id,
                            ),
                        ),
                    )
                )
            )
        
        result = await db.execute(query.order_by(Report.created_at.desc()))
        reports = result.scalars().all()
        
        # Получаем информацию об инженерах из связанных инспекций
        report_items = []
        for r in reports:
            inspector_name = None
            inspector_position = None
            equipment_id = None
            project_id = None
            inspection = None
            enterprise_id = None
            enterprise_name = None
            branch_id = None
            branch_name = None
            workshop_id = None
            workshop_name = None
            equipment_name = None
            
            # Пытаемся получить ФИО инженера из связанной инспекции
            if r.inspection_id:
                insp_result = await db.execute(
                    select(Inspection).where(Inspection.id == r.inspection_id)
                )
                inspection = insp_result.scalar_one_or_none()
                if inspection:
                    # Получаем equipment_id и project_id из инспекции
                    equipment_id = str(inspection.equipment_id) if inspection.equipment_id else None
                    project_id = str(inspection.project_id) if inspection.project_id else None
                    
                    # Получаем информацию об оборудовании и иерархии
                    if inspection.equipment_id:
                        eq_result = await db.execute(
                            select(Equipment).where(Equipment.id == inspection.equipment_id)
                        )
                        equipment = eq_result.scalar_one_or_none()
                        if equipment:
                            equipment_name = equipment.name
                            
                            # Получаем информацию о цехе, филиале и предприятии
                            if equipment.workshop_id:
                                try:
                                    workshop_result = await db.execute(
                                        select(Workshop).where(Workshop.id == equipment.workshop_id)
                                    )
                                    workshop = workshop_result.scalar_one_or_none()
                                    if workshop:
                                        workshop_id = str(workshop.id)
                                        workshop_name = workshop.name
                                        
                                        # Получаем филиал
                                        try:
                                            branch_result = await db.execute(
                                                select(Branch).where(Branch.id == workshop.branch_id)
                                            )
                                            branch = branch_result.scalar_one_or_none()
                                            if branch:
                                                branch_id = str(branch.id)
                                                branch_name = branch.name
                                                
                                                # Получаем предприятие
                                                try:
                                                    enterprise_result = await db.execute(
                                                        select(Enterprise).where(Enterprise.id == branch.enterprise_id)
                                                    )
                                                    enterprise = enterprise_result.scalar_one_or_none()
                                                    if enterprise:
                                                        enterprise_id = str(enterprise.id)
                                                        enterprise_name = enterprise.name
                                                except Exception as e:
                                                    await db.rollback()
                                                    print(f"⚠️ Error loading enterprise for report {r.id}: {e}")
                                        except Exception as e:
                                            await db.rollback()
                                            print(f"⚠️ Error loading branch for report {r.id}: {e}")
                                except Exception as e:
                                    await db.rollback()
                                    print(f"⚠️ Error loading workshop for report {r.id}: {e}")
                    
                    if inspection.inspector_id:
                        # Получаем информацию об инженере из users
                        user_result = await db.execute(
                            select(User).where(User.id == inspection.inspector_id)
                        )
                        user = user_result.scalar_one_or_none()
                        if user:
                            inspector_name = user.full_name or user.username
                            # Пытаемся получить должность из связанного engineer
                            if user.engineer_id:
                                eng_result = await db.execute(
                                    select(Engineer).where(Engineer.id == user.engineer_id)
                                )
                                engineer = eng_result.scalar_one_or_none()
                                if engineer:
                                    inspector_position = engineer.position
            
            report_items.append({
                "id": str(r.id),
                "inspection_id": str(r.inspection_id) if r.inspection_id else None,
                "equipment_id": equipment_id,
                "equipment_name": equipment_name,
                "project_id": project_id,
                "enterprise_id": enterprise_id,
                "enterprise_name": enterprise_name,
                "branch_id": branch_id,
                "branch_name": branch_name,
                "workshop_id": workshop_id,
                "workshop_name": workshop_name,
                "report_type": r.report_type,
                "title": f"{r.report_type} Report" if r.report_type else "Report",
                "file_path": r.file_path,
                "file_size": r.file_size,
                # Статус отчета берём из статуса инспекции, если она есть (DRAFT/SIGNED/APPROVED).
                # Фолбэк: если инспекции нет, считаем что файл -> GENERATED иначе DRAFT.
                "status": (inspection.status if inspection and getattr(inspection, "status", None) else ("GENERATED" if r.file_path else "DRAFT")),
                "inspector_name": inspector_name,
                "inspector_position": inspector_position,
                "created_by": str(r.created_by) if r.created_by else None,
                "is_archived": getattr(r, "is_archived", False),
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "word_file_path": getattr(r, "word_file_path", None),
                "word_file_size": getattr(r, "word_file_size", None),
            })
        
        return {
            "items": report_items
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_reports: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении отчетов: {error_detail}")

@app.get("/api/inspections/{inspection_id}/preview")
async def get_inspection_preview(inspection_id: str, db: AsyncSession = Depends(get_db)):
    """Получить данные инспекции для предпросмотра перед генерацией отчета"""
    try:
        inspection_uuid = uuid_lib.UUID(inspection_id)
        
        # Получаем данные инспекции
        result = await db.execute(
            select(Inspection).where(Inspection.id == inspection_uuid)
        )
        inspection = result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")
        
        # Получаем данные оборудования
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == inspection.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")

        # Данные ОПО (если оборудование привязано к ОПО)
        opo_info = None
        try:
            opo = None
            if getattr(equipment, "opo_id", None):
                opo_result = await db.execute(select(Opo).where(Opo.id == equipment.opo_id))
                opo = opo_result.scalar_one_or_none()
            if opo:
                workshop = None
                branch = None
                enterprise = None
                if getattr(opo, "workshop_id", None):
                    w_result = await db.execute(select(Workshop).where(Workshop.id == opo.workshop_id))
                    workshop = w_result.scalar_one_or_none()
                if workshop and getattr(workshop, "branch_id", None):
                    b_result = await db.execute(select(Branch).where(Branch.id == workshop.branch_id))
                    branch = b_result.scalar_one_or_none()
                if branch and getattr(branch, "enterprise_id", None):
                    e_result = await db.execute(select(Enterprise).where(Enterprise.id == branch.enterprise_id))
                    enterprise = e_result.scalar_one_or_none()

                opo_info = {
                    "id": str(opo.id),
                    "name": opo.name,
                    "code": opo.code,
                    "description": opo.description,
                    "survey_data": opo.survey_data or {},
                    "workshop_id": str(opo.workshop_id) if opo.workshop_id else None,
                    "workshop_name": workshop.name if workshop else None,
                    "branch_id": str(branch.id) if branch else None,
                    "branch_name": branch.name if branch else None,
                    "enterprise_id": str(enterprise.id) if enterprise else None,
                    "enterprise_name": enterprise.name if enterprise else None,
                }
        except Exception as e:
            print(f"Warning: Could not load OPO info for preview: {e}")
            opo_info = None
        
        # Questionnaire: приоритет — questionnaire_id инспекции, иначе последний по оборудованию
        questionnaire = None
        if getattr(inspection, "questionnaire_id", None):
            q_by_inspection = await db.execute(
                select(Questionnaire)
                .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                .where(Questionnaire.id == inspection.questionnaire_id)
            )
            questionnaire = q_by_inspection.scalar_one_or_none()
        if not questionnaire:
            questionnaire_result = await db.execute(
                select(Questionnaire)
                .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                .where(Questionnaire.equipment_id == equipment.id)
                .order_by(Questionnaire.created_at.desc()).limit(1)
            )
            questionnaire = questionnaire_result.scalar_one_or_none()

        # Методы НК: по inspection_id, затем по questionnaire (привязанному к инспекции)
        ndt_methods = []
        try:
            ndt_result = await db.execute(
                select(NDTMethod).where(NDTMethod.inspection_id == inspection.id)
            )
            ndt_methods = ndt_result.scalars().all()
        except Exception:
            ndt_methods = []
        if not ndt_methods and questionnaire:
            ndt_result = await db.execute(
                select(NDTMethod).where(NDTMethod.questionnaire_id == questionnaire.id)
            )
            ndt_methods = ndt_result.scalars().all()

        # Файлы документов/вложений (при наличии questionnaire_id у инспекции — берём его)
        document_files = []
        try:
            q_for_files = questionnaire
            if not q_for_files and getattr(inspection, "questionnaire_id", None):
                q_by_id = await db.execute(
                    select(Questionnaire)
                    .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                    .where(Questionnaire.id == inspection.questionnaire_id)
                )
                q_for_files = q_by_id.scalar_one_or_none()
            if not q_for_files:
                q_query = (
                    select(Questionnaire)
                    .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                    .where(Questionnaire.equipment_id == equipment.id)
                )
                if getattr(inspection, "created_at", None):
                    q_query = q_query.order_by(
                        func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
                    ).limit(1)
                else:
                    q_query = q_query.order_by(Questionnaire.created_at.desc()).limit(1)
                q_result = await db.execute(q_query)
                q_for_files = q_result.scalar_one_or_none()
            if q_for_files:
                questionnaire = q_for_files
                files_result = await db.execute(
                    select(QuestionnaireDocumentFile).where(
                        QuestionnaireDocumentFile.questionnaire_id == q_for_files.id
                    )
                )
                files = files_result.scalars().all()
                qid = str(q_for_files.id)
                document_files = [
                    {
                        "document_number": f.document_number,
                        "file_name": f.file_name,
                        "file_size": int(f.file_size or 0),
                        "file_type": f.file_type,
                        "mime_type": f.mime_type,
                        "view_url": f"/api/questionnaires/{qid}/documents/{f.document_number}/view",
                    }
                    for f in files
                ]
        except Exception:
            document_files = []
        
        # Получаем данные ресурса, если есть
        resource_data = None
        res_result = await db.execute(
            select(EquipmentResource).where(EquipmentResource.equipment_id == equipment.id)
            .order_by(EquipmentResource.created_at.desc()).limit(1)
        )
        resource = res_result.scalar_one_or_none()
        if resource:
            # Используем поля, которые есть в модели EquipmentResource
            resource_data = {
                "resource_type": resource.resource_type,
                "current_value": float(resource.current_value) if resource.current_value else None,
                "limit_value": float(resource.limit_value) if resource.limit_value else None,
                "unit": resource.unit,
                "last_updated": resource.last_updated.isoformat() if resource.last_updated else None,
            }
        
        return {
            "inspection": {
                "id": str(inspection.id),
                "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                "status": inspection.status,
                "conclusion": inspection.conclusion,
                "data": inspection.data,
            },
            "equipment": {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
                "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                "attributes": equipment.attributes or {},
            },
            "questionnaire": {
                "id": str(questionnaire.id) if questionnaire else None,
            },
            "document_files": document_files,
            "opo": opo_info,
            "ndt_methods": [
                {
                    "id": str(m.id),
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": m.photos or [],
                    "additional_data": m.additional_data or {},
                }
                for m in ndt_methods
            ],
            "resource": resource_data,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to get preview: {str(e)}")


@app.get("/api/inspections/{inspection_id}/questionnaire")
async def get_inspection_questionnaire_info(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """
    Получить привязанный к инспекции опросный лист (questionnaire_id) и файлы документов.
    Нужен для корректного отображения названий и вложений документов в веб-интерфейсе.
    """
    try:
        inspection_uuid = uuid_lib.UUID(inspection_id)

        ins_result = await db.execute(select(Inspection).where(Inspection.id == inspection_uuid))
        inspection = ins_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        # Ищем наиболее подходящий questionnaire (load_only — без assignment_id)
        q_query = (
            select(Questionnaire)
            .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
            .where(Questionnaire.equipment_id == inspection.equipment_id)
        )
        if getattr(inspection, "created_at", None):
            q_query = q_query.order_by(
                func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
            ).limit(1)
        else:
            q_query = q_query.order_by(Questionnaire.created_at.desc()).limit(1)

        q_result = await db.execute(q_query)
        questionnaire = q_result.scalar_one_or_none()

        if not questionnaire:
            return {"questionnaire_id": None, "document_files": []}

        files_result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == questionnaire.id
            )
        )
        files = files_result.scalars().all()

        qid = str(questionnaire.id)
        return {
            "questionnaire_id": qid,
            "document_files": [
                {
                    "id": str(f.id),
                    "document_number": f.document_number,
                    "file_name": f.file_name,
                    "file_size": int(f.file_size or 0),
                    "file_type": f.file_type,
                    "mime_type": f.mime_type,
                    "created_at": f.created_at.isoformat() if f.created_at else None,
                    "view_url": f"/api/questionnaires/{qid}/documents/{f.document_number}/view",
                }
                for f in files
            ],
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Failed to get inspection questionnaire info: {str(e)}")


@app.get("/api/reports/validate/{inspection_id}")
async def validate_report_inspection(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Проверка полноты данных обследования перед генерацией отчёта"""
    try:
        from report_utils import validate_inspection_completeness
        result = await validate_inspection_completeness(db, inspection_id)
        return result
    except Exception as e:
        return {
            "is_complete": False,
            "missing_fields": [f"Ошибка проверки: {str(e)}"],
            "warnings": [],
            "can_generate": False
        }


@app.post("/api/reports/generate")
async def generate_report(
    report_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Generate technical report or expertise"""
    try:
        # Текущий пользователь
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        inspection_id = None
        if report_data.get("inspection_id"):
            try:
                inspection_id = uuid_lib.UUID(report_data.get("inspection_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid inspection_id format")

        opo_info = None
        
        # Get inspection data
        if inspection_id:
            result = await db.execute(
                select(Inspection).where(Inspection.id == inspection_id)
            )
            inspection = result.scalar_one_or_none()
            if not inspection:
                raise HTTPException(status_code=404, detail="Inspection not found")
            # Роли и права на отчёты: инженер — только по своим обследованиям
            if getattr(current_user, "role", None) == "engineer":
                own = (
                    (getattr(inspection, "inspector_id", None) == current_user.id)
                    or (getattr(inspection, "performed_by", None) == current_user.id)
                    or (getattr(inspection, "created_by", None) == current_user.id)
                )
                if not own:
                    raise HTTPException(status_code=403, detail="Нет прав на генерацию отчёта по этому обследованию")
            
            # Get equipment data
            eq_result = await db.execute(
                select(Equipment).where(Equipment.id == inspection.equipment_id)
            )
            equipment = eq_result.scalar_one_or_none()
            if not equipment:
                raise HTTPException(status_code=404, detail="Equipment not found")
            
            # Get equipment type information
            equipment_type_code = None
            equipment_type_name = None
            if equipment.type_id:
                type_result = await db.execute(
                    select(EquipmentType).where(EquipmentType.id == equipment.type_id)
                )
                equipment_type = type_result.scalar_one_or_none()
                if equipment_type:
                    equipment_type_code = equipment_type.code
                    equipment_type_name = equipment_type.name

            # Данные ОПО для отчета (если оборудование привязано к ОПО)
            opo_info = None
            try:
                opo = None
                if getattr(equipment, "opo_id", None):
                    opo_result = await db.execute(select(Opo).where(Opo.id == equipment.opo_id))
                    opo = opo_result.scalar_one_or_none()
                if opo:
                    workshop = None
                    branch = None
                    enterprise = None
                    if getattr(opo, "workshop_id", None):
                        w_result = await db.execute(select(Workshop).where(Workshop.id == opo.workshop_id))
                        workshop = w_result.scalar_one_or_none()
                    if workshop and getattr(workshop, "branch_id", None):
                        b_result = await db.execute(select(Branch).where(Branch.id == workshop.branch_id))
                        branch = b_result.scalar_one_or_none()
                    if branch and getattr(branch, "enterprise_id", None):
                        e_result = await db.execute(select(Enterprise).where(Enterprise.id == branch.enterprise_id))
                        enterprise = e_result.scalar_one_or_none()

                    opo_info = {
                        "id": str(opo.id),
                        "name": opo.name,
                        "code": opo.code,
                        "description": opo.description,
                        "survey_data": opo.survey_data or {},
                        "workshop_id": str(opo.workshop_id) if opo.workshop_id else None,
                        "workshop_name": workshop.name if workshop else None,
                        "branch_id": str(branch.id) if branch else None,
                        "branch_name": branch.name if branch else None,
                        "enterprise_id": str(enterprise.id) if enterprise else None,
                        "enterprise_name": enterprise.name if enterprise else None,
                    }
            except Exception as e:
                print(f"Warning: Could not load OPO info: {e}")
                opo_info = None
            
            # Get resource data if expertise
            resource_data = None
            if report_data.get("report_type") == "EXPERTISE":
                res_result = await db.execute(
                    select(EquipmentResource).where(EquipmentResource.equipment_id == equipment.id)
                    .order_by(EquipmentResource.created_at.desc()).limit(1)
                )
                resource = res_result.scalar_one_or_none()
                if resource:
                    # Используем поля, которые есть в модели EquipmentResource
                    resource_data = {
                        "resource_type": resource.resource_type,
                        "current_value": float(resource.current_value) if resource.current_value else None,
                        "limit_value": float(resource.limit_value) if resource.limit_value else None,
                        "unit": resource.unit,
                        "last_updated": resource.last_updated.isoformat() if resource.last_updated else None,
                    }
            
            # Методы НК:
            # 1) Сначала пытаемся взять методы, привязанные напрямую к inspection_id (3.3.0+)
            # 2) Фолбэк: методы, привязанные к последнему questionnaire по этому оборудованию (историческая логика)
            ndt_methods = []
            try:
                ndt_result = await db.execute(
                    select(NDTMethod).where(NDTMethod.inspection_id == inspection.id)
                )
                ndt_methods = ndt_result.scalars().all()
            except Exception:
                ndt_methods = []

            if not ndt_methods:
                questionnaire_result = await db.execute(
                    select(Questionnaire)
                    .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                    .where(Questionnaire.equipment_id == equipment.id)
                    .order_by(Questionnaire.created_at.desc()).limit(1)
                )
                questionnaire = questionnaire_result.scalar_one_or_none()

                if questionnaire:
                    ndt_result = await db.execute(
                        select(NDTMethod).where(NDTMethod.questionnaire_id == questionnaire.id)
                    )
                    ndt_methods = ndt_result.scalars().all()

            # Вложения чек-листа (фото таблички/схема контроля/сканы документов) — привязаны к Questionnaire
            document_files = []
            try:
                q_for_files = None
                # Сначала берём questionnaire, привязанный к этой инспекции (если есть)
                if getattr(inspection, "questionnaire_id", None):
                    q_by_id = await db.execute(
                        select(Questionnaire)
                        .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                        .where(Questionnaire.id == inspection.questionnaire_id)
                    )
                    q_for_files = q_by_id.scalar_one_or_none()
                if not q_for_files:
                    q_query = (
                        select(Questionnaire)
                        .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                        .where(Questionnaire.equipment_id == equipment.id)
                    )
                    if getattr(inspection, "created_at", None):
                        q_query = q_query.order_by(
                            func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
                        ).limit(1)
                    else:
                        q_query = q_query.order_by(Questionnaire.created_at.desc()).limit(1)
                    q_result = await db.execute(q_query)
                    q_for_files = q_result.scalar_one_or_none()
                if q_for_files:
                    files_result = await db.execute(
                        select(QuestionnaireDocumentFile).where(
                            QuestionnaireDocumentFile.questionnaire_id == q_for_files.id
                        )
                    )
                    files = files_result.scalars().all()
                    document_files = [
                        {
                            "document_number": f.document_number,
                            "file_name": f.file_name,
                            "file_path": _resolve_report_file_path(f.file_path) or f.file_path,
                            "file_size": int(f.file_size or 0),
                            "file_type": f.file_type,
                            "mime_type": f.mime_type,
                        }
                        for f in files
                    ]
            except Exception:
                document_files = []
            # Дополняем из inspection.data (пути после синхронизации с мобильного)
            _existing_dn = {str(f.get("document_number")) for f in document_files if f.get("document_number")}
            _data = inspection.data if isinstance(getattr(inspection, "data", None), dict) else {}
            for _key in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
                if _key not in _existing_dn and _data.get(_key):
                    _p = (_data.get(_key) or "").strip()
                    if _p:
                        document_files.append({"document_number": _key, "file_name": os.path.basename(_p), "file_path": _resolve_report_file_path(_p) or _p})
                        _existing_dn.add(_key)
            _vd = _data.get("visual_defects")
            if isinstance(_vd, list):
                for _i, _d in enumerate(_vd):
                    if not isinstance(_d, dict):
                        continue
                    for _j, _ph in enumerate(_d.get("photos") or []):
                        if isinstance(_ph, str) and _ph.strip() and f"vd_{_i}_{_j}" not in _existing_dn:
                            document_files.append({"document_number": f"vd_{_i}_{_j}", "file_name": os.path.basename(_ph), "file_path": _resolve_report_file_path(_ph) or _ph})
                            _existing_dn.add(f"vd_{_i}_{_j}")
            _thickness = _data.get("thickness_measurements") or _data.get("thicknessMeasurements")
            if isinstance(_thickness, list):
                for _i, _t in enumerate(_thickness):
                    if not isinstance(_t, dict):
                        continue
                    for _j, _ph in enumerate(_t.get("photos") or []):
                        if isinstance(_ph, str) and _ph.strip() and f"uzt_point_{_i}_{_j}" not in _existing_dn:
                            document_files.append({"document_number": f"uzt_point_{_i}_{_j}", "file_name": os.path.basename(_ph), "file_path": _resolve_report_file_path(_ph) or _ph})
                            _existing_dn.add(f"uzt_point_{_i}_{_j}")

            # Проверка целостности вложений: логируем отсутствующие файлы
            _missing_att = []
            for _f in (document_files or []):
                if not isinstance(_f, dict):
                    continue
                _fp = _f.get("file_path")
                if isinstance(_fp, str) and _fp.strip():
                    _p = Path(_fp)
                    _candidate = _p if _p.is_absolute() and _p.exists() else None
                    if not _candidate:
                        for _base in ["/app/uploads/questionnaire_documents", "/app/uploads", "/app/reports"]:
                            _cand = Path(_base) / _fp
                            if _cand.exists():
                                _candidate = _cand
                                break
                    if not _candidate or not _candidate.exists():
                        _missing_att.append(_f.get("document_number") or _f.get("file_name") or _fp)
            if _missing_att:
                print(f"Report generation: missing attachment files (inspection_id={inspection.id}): {_missing_att}")

            # Получаем используемое оборудование для поверок
            verification_equipment_list = []
            try:
                # Ищем по inspection_id
                inspection_eq_result = await db.execute(
                    select(InspectionEquipment).where(InspectionEquipment.inspection_id == inspection.id)
                )
                inspection_equipment = inspection_eq_result.scalars().all()
                
                for ie in inspection_equipment:
                    ver_eq_result = await db.execute(
                        select(VerificationEquipment).where(VerificationEquipment.id == ie.verification_equipment_id)
                    )
                    ver_eq = ver_eq_result.scalar_one_or_none()
                    if ver_eq:
                        scan_path = _resolve_report_file_path(ver_eq.scan_file_path) if ver_eq.scan_file_path else ver_eq.scan_file_path
                        verification_equipment_list.append({
                            "id": str(ver_eq.id),
                            "name": ver_eq.name,
                            "equipment_type": ver_eq.equipment_type,
                            "serial_number": ver_eq.serial_number,
                            "manufacturer": ver_eq.manufacturer,
                            "model": ver_eq.model,
                            "verification_date": ver_eq.verification_date.isoformat() if ver_eq.verification_date else None,
                            "next_verification_date": ver_eq.next_verification_date.isoformat() if ver_eq.next_verification_date else None,
                            "verification_certificate_number": ver_eq.verification_certificate_number,
                            "verification_organization": ver_eq.verification_organization,
                            "scan_file_path": scan_path,
                            "scan_file_name": ver_eq.scan_file_name,
                        })
            except Exception as e:
                print(f"Warning: Could not load verification equipment: {e}")
                verification_equipment_list = []
            
            # Generate report
            reports_dir = Path("/app/reports")
            reports_dir.mkdir(exist_ok=True)
            
            report_type = report_data.get("report_type", "TECHNICAL_REPORT")
            # pdf или docx (поддерживаем также WORD/DOC)
            output_format = (report_data.get("format") or "pdf").strip().lower()
            is_docx = output_format in ["docx", "doc", "word"]

            # Подключаем макет отчета (definition) из report_templates.json (MVP без миграций БД)
            template_definition = None
            try:
                templates_path = _Path("/app/reports/report_templates.json")
                if templates_path.exists():
                    templates = _json.loads(templates_path.read_text(encoding="utf-8") or "[]")
                    # ищем шаблон по типу оборудования (type_id), report_type и format
                    eq_type_id = str(getattr(equipment, "type_id", "") or "")
                    def _match(t):
                        if not isinstance(t, dict) or not t.get("is_active"):
                            return False
                        if (t.get("equipment_type_id") or "") and (t.get("equipment_type_id") != eq_type_id):
                            return False
                        if (t.get("report_type") or "") and (t.get("report_type") != report_type):
                            return False
                        if (t.get("format") or "") and (t.get("format") != output_format):
                            return False
                        return True

                    chosen = next((t for t in templates if _match(t)), None)
                    if not chosen:
                        # fallback: любой активный по type_id
                        def _match2(t):
                            if not isinstance(t, dict) or not t.get("is_active"):
                                return False
                            if (t.get("equipment_type_id") or "") and (t.get("equipment_type_id") != eq_type_id):
                                return False
                            if (t.get("report_type") or "") and (t.get("report_type") != report_type):
                                return False
                            return True
                        chosen = next((t for t in templates if _match2(t)), None)
                    if not chosen:
                        # fallback: общий активный (equipment_type_id null/empty)
                        def _match3(t):
                            if not isinstance(t, dict) or not t.get("is_active"):
                                return False
                            if t.get("equipment_type_id") not in (None, "", "null"):
                                return False
                            if (t.get("report_type") or "") and (t.get("report_type") != report_type):
                                return False
                            return True
                        chosen = next((t for t in templates if _match3(t)), None)
                    if chosen:
                        template_definition = chosen.get("definition")
            except Exception:
                template_definition = None
            
            if is_docx:
                # Генерация Word документа
                from word_generator import WordGenerator
                word_generator = WordGenerator()
                filename = f"{report_type}_{inspection.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.docx"
                file_path = reports_dir / filename
            else:
                # Генерация PDF
                generator = ReportGenerator()
                filename = f"{report_type}_{inspection.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
                file_path = reports_dir / filename
            
            # Проверяем, что ndt_methods не None и является списком
            if ndt_methods is None:
                ndt_methods = []
            
            def _resolve_photo_list(lst):
                if not isinstance(lst, list):
                    return lst
                return [_resolve_report_file_path(x) or x for x in lst if isinstance(x, str)]

            ndt_methods_data = []
            for m in ndt_methods:
                ad = m.additional_data or {}
                if isinstance(ad, dict) and "annotated_images" in ad and isinstance(ad["annotated_images"], list):
                    ad = dict(ad)
                    ad["annotated_images"] = _resolve_photo_list(ad["annotated_images"])
                cert_num = (ad.get("certificate_number") if isinstance(ad, dict) else None) or None
                ndt_methods_data.append({
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "certificate_number": cert_num,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": _resolve_photo_list(m.photos or []),
                    "additional_data": ad,
                    "performed_date": m.performed_date.isoformat() if m.performed_date else None,
                })

            # Приложения: документы специалистов (удостоверения/сертификаты НК) по ФИО из методов НК
            specialist_docs = []
            try:
                inspector_names = sorted(
                    {str(m.get("inspector_name")).strip() for m in ndt_methods_data if m.get("inspector_name")},
                    key=lambda s: s.lower(),
                )
                for name in inspector_names:
                    # ищем пользователя по full_name или username (берём первого при совпадении нескольких)
                    ures = await db.execute(
                        select(User).where(or_(User.full_name == name, User.username == name)).limit(1)
                    )
                    u = ures.scalar_one_or_none()
                    if not u or not getattr(u, "engineer_id", None):
                        continue
                    certs_res = await db.execute(
                        select(Certification).where(
                            Certification.engineer_id == u.engineer_id,
                            Certification.scan_file_path.is_not(None),
                        )
                    )
                    certs = certs_res.scalars().all()
                    items = []
                    for c in certs:
                        sp = getattr(c, "scan_file_path", None)
                        if not sp:
                            continue
                        sp_resolved = _resolve_report_file_path(sp) or sp
                        items.append(
                            {
                                "certification_type": getattr(c, "certification_type", None),
                                "certificate_number": getattr(c, "certificate_number", None),
                                "method_code": getattr(c, "method_code", None),
                                "issuing_organization": getattr(c, "issuing_organization", None),
                                "issue_date": str(getattr(c, "issue_date", None)) if getattr(c, "issue_date", None) else None,
                                "expiry_date": str(getattr(c, "expiry_date", None)) if getattr(c, "expiry_date", None) else None,
                                "scan_file_path": sp_resolved,
                                "scan_file_name": getattr(c, "scan_file_name", None),
                                "scan_mime_type": getattr(c, "scan_mime_type", None),
                            }
                        )
                    if items:
                        specialist_docs.append({"inspector_name": name, "certifications": items})
            except Exception:
                specialist_docs = []

            # Подготавливаем данные для отчета и добавляем информацию об ОПО (если есть)
            inspection_payload = {
                "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                "data": inspection.data,
                "conclusion": inspection.conclusion,
                "status": inspection.status,
            }
            # Подставляем пути из загруженных document_files в data (фото таблички, схема, фото дефектов ВИК)
            try:
                dp = inspection_payload.get("data")
                if isinstance(dp, dict) and document_files:
                    dp = dict(dp)
                    for f in document_files:
                        dn = f.get("document_number")
                        fp = f.get("file_path")
                        if not dn or not fp:
                            continue
                        if dn in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
                            dp[dn] = fp
                        elif isinstance(dn, str) and dn.startswith("uzt_point_"):
                            parts = dn.split("_")
                            if len(parts) >= 4 and parts[0] == "uzt" and parts[1] == "point":
                                try:
                                    i, j = int(parts[2]), int(parts[3])
                                    tm = dp.get("thickness_measurements") or dp.get("thicknessMeasurements")
                                    if isinstance(tm, list) and 0 <= i < len(tm):
                                        t = tm[i]
                                        if isinstance(t, dict):
                                            t = dict(t)
                                            ph = list(t.get("photos") or [])
                                            while len(ph) <= j:
                                                ph.append("")
                                            ph[j] = fp
                                            t["photos"] = ph
                                            tm = list(tm)
                                            tm[i] = t
                                            dp["thickness_measurements"] = tm
                                except (ValueError, IndexError):
                                    pass
                        elif isinstance(dn, str) and dn.startswith("vd_"):
                            parts = dn.split("_")
                            if len(parts) == 3 and parts[0] == "vd":
                                try:
                                    i, j = int(parts[1]), int(parts[2])
                                    vd = dp.get("visual_defects")
                                    if isinstance(vd, list) and 0 <= i < len(vd):
                                        d = vd[i]
                                        if isinstance(d, dict):
                                            d = dict(d)
                                            ph = list(d.get("photos") or [])
                                            while len(ph) <= j:
                                                ph.append("")
                                            ph[j] = fp
                                            d["photos"] = ph
                                            vd = list(vd)
                                            vd[i] = d
                                            dp["visual_defects"] = vd
                                except (ValueError, IndexError):
                                    pass
                    inspection_payload["data"] = dp
            except Exception:
                pass
            # Разрешаем пути к фото таблички, схемы и фото дефектов в data (для вставки в отчёт)
            try:
                dp = inspection_payload.get("data")
                if isinstance(dp, dict):
                    dp = dict(dp)
                    for key in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
                        if dp.get(key) and isinstance(dp[key], str):
                            dp[key] = _resolve_report_file_path(dp[key]) or dp[key]
                    # Фото дефектов ВИК (синхронизация с мобильного)
                    vd = dp.get("visual_defects")
                    if isinstance(vd, list):
                        vd = list(vd)
                        for i, d in enumerate(vd):
                            if isinstance(d, dict):
                                d = dict(d)
                                ph = d.get("photos") or []
                                if isinstance(ph, list):
                                    d["photos"] = [_resolve_report_file_path(p) or p for p in ph if isinstance(p, str)]
                                vd[i] = d
                        dp["visual_defects"] = vd
                    # Фото замеров УЗТ
                    tm = dp.get("thickness_measurements") or dp.get("thicknessMeasurements")
                    if isinstance(tm, list):
                        tm = list(tm)
                        for i, t in enumerate(tm):
                            if isinstance(t, dict):
                                t = dict(t)
                                ph = t.get("photos") or []
                                if isinstance(ph, list):
                                    t["photos"] = [_resolve_report_file_path(p) or p for p in ph if isinstance(p, str)]
                                tm[i] = t
                        dp["thickness_measurements"] = tm
                    inspection_payload["data"] = dp
            except Exception:
                pass
            try:
                data_payload = inspection_payload.get("data")
                if isinstance(data_payload, dict) and opo_info:
                    data_payload = dict(data_payload)
                    survey = opo_info.get("survey_data") if isinstance(opo_info.get("survey_data"), dict) else {}
                    if isinstance(survey, dict):
                        docs_current = data_payload.get("documents") or {}
                        if isinstance(docs_current, dict) and isinstance(survey.get("documents"), dict):
                            merged_docs = dict(docs_current)
                            for k, v in survey.get("documents").items():
                                try:
                                    n = int(str(k))
                                except Exception:
                                    continue
                                if 1 <= n <= 9 and not merged_docs.get(str(k)):
                                    merged_docs[str(k)] = v
                            data_payload["documents"] = merged_docs
                        if not data_payload.get("organization") and survey.get("organization"):
                            data_payload["organization"] = survey.get("organization")
                        if not data_payload.get("executors") and survey.get("executors"):
                            data_payload["executors"] = survey.get("executors")
                        data_payload.setdefault("opo_survey", survey)

                    data_payload.setdefault("opo", opo_info)
                    if opo_info.get("id"):
                        data_payload.setdefault("opo_id", opo_info["id"])
                    if opo_info.get("name"):
                        data_payload.setdefault("opo_name", opo_info["name"])
                    if opo_info.get("code"):
                        data_payload.setdefault("opo_code", opo_info["code"])
                    if opo_info.get("description"):
                        data_payload.setdefault("opo_description", opo_info["description"])
                    if opo_info.get("enterprise_name"):
                        data_payload.setdefault("opo_enterprise", opo_info["enterprise_name"])
                    if opo_info.get("branch_name"):
                        data_payload.setdefault("opo_branch", opo_info["branch_name"])
                    if opo_info.get("workshop_name"):
                        data_payload.setdefault("opo_workshop", opo_info["workshop_name"])

                    inspection_payload["data"] = data_payload
            except Exception as e:
                print(f"Warning: Could not merge OPO data into report payload: {e}")

            _report_gen_t0 = time.time()
            if is_docx:
                # Генерация Word документа во временный файл, затем перемещение (восстановление после сбоя)
                import tempfile as _tf
                _fd, _tmp_path = _tf.mkstemp(suffix=".docx", prefix="report_", dir=str(reports_dir))
                try:
                    os.close(_fd)
                    word_generator.generate_report_word(
                        inspection_payload,
                        {
                            "id": str(equipment.id),
                            "name": equipment.name,
                            "serial_number": equipment.serial_number,
                            "location": equipment.location,
                            "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                            "attributes": equipment.attributes or {},
                            "type_code": equipment_type_code,
                            "type_name": equipment_type_name,
                        },
                        ndt_methods_data,
                        _tmp_path,
                        report_type,
                        document_files=document_files,
                        specialist_docs=specialist_docs,
                        verification_equipment=verification_equipment_list,
                        template_definition=template_definition,
                    )
                    os.replace(_tmp_path, str(file_path))
                except Exception:
                    if os.path.exists(_tmp_path):
                        try:
                            os.unlink(_tmp_path)
                        except OSError:
                            pass
                    raise
            else:
                # Генерация PDF
                if report_type == "EXPERTISE":
                    generator.generate_expertise_report(
                        inspection_payload,
                        {
                            "id": str(equipment.id),
                            "name": equipment.name,
                            "serial_number": equipment.serial_number,
                            "location": equipment.location,
                            "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                            "attributes": equipment.attributes or {},
                        },
                        resource_data,
                        str(file_path),
                        ndt_methods_data,
                        document_files=document_files,
                        specialist_docs=specialist_docs,
                        verification_equipment=verification_equipment_list,
                    )
                else:
                    generator.generate_technical_report(
                        inspection_payload,
                        {
                            "id": str(equipment.id),
                            "name": equipment.name,
                            "serial_number": equipment.serial_number,
                            "location": equipment.location,
                            "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                            "attributes": equipment.attributes or {},
                        },
                        str(file_path),
                        ndt_methods_data,
                        document_files=document_files,
                        specialist_docs=specialist_docs,
                        verification_equipment=verification_equipment_list,
                    )
            _metrics["report_generation_seconds_sum"] = _metrics.get("report_generation_seconds_sum", 0) + (time.time() - _report_gen_t0)
            _metrics["report_generation_count"] = _metrics.get("report_generation_count", 0) + 1
            
            # Генерируем номера отчета
            from report_utils import generate_report_number, generate_registration_number
            report_number = await generate_report_number(db, report_type)
            registration_number = await generate_registration_number(db)
            
            # Save report record
            new_report = Report(
                inspection_id=inspection_id,
                report_type=report_type,
                report_number=report_number,
                registration_number=registration_number,
                file_path=str(file_path),
                file_size=file_path.stat().st_size if file_path.exists() else 0,
                created_by=current_user.id,
                is_archived=False  # Явно устанавливаем значение
            )
            # Для DOCX также заполняем word_* поля (для единообразия и будущего расширения)
            if is_docx:
                new_report.word_file_path = str(file_path)
                new_report.word_file_size = new_report.file_size
            db.add(new_report)
            await db.commit()
            await db.refresh(new_report)
            
            return {
                "id": str(new_report.id),
                "report_number": new_report.report_number,
                "registration_number": new_report.registration_number,
                "file_path": str(file_path),
                "file_size": new_report.file_size,
                "format": "docx" if is_docx else "pdf",
                "status": "generated"
            }
        else:
            raise HTTPException(status_code=400, detail="inspection_id is required")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate report: {str(e)}")


@app.post("/api/reports/bulk-export", tags=["reports"])
async def bulk_export_reports(
    body: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Пакетная выгрузка отчётов: по списку inspection_ids генерируются DOCX и возвращаются в ZIP (макс. 15 шт)."""
    import tempfile
    inspection_ids = body.get("inspection_ids") or []
    if not isinstance(inspection_ids, list):
        raise HTTPException(status_code=400, detail="inspection_ids должен быть массивом")
    inspection_ids = [str(x).strip() for x in inspection_ids if x][:15]
    report_type = (body.get("report_type") or "TECHNICAL_REPORT").strip().upper()
    if not inspection_ids:
        raise HTTPException(status_code=400, detail="Укажите хотя бы один inspection_id")

    user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
    current_user = user_result.scalar_one_or_none()
    if not current_user:
        raise HTTPException(status_code=404, detail="User not found")

    from word_generator import WordGenerator
    word_generator = WordGenerator()
    temp_dir = tempfile.mkdtemp(prefix="bulk_report_")
    generated = []
    try:
        for insp_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(insp_id)
            except (ValueError, TypeError):
                continue
            insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
            inspection = insp_result.scalar_one_or_none()
            if not inspection:
                continue
            if current_user.role == "engineer" and getattr(inspection, "inspector_id", None) != current_user.id and getattr(inspection, "performed_by", None) != current_user.id:
                continue
            eq_result = await db.execute(select(Equipment).where(Equipment.id == inspection.equipment_id))
            equipment = eq_result.scalar_one_or_none()
            if not equipment:
                continue
            inspection_data = dict(inspection.data or {})
            inspection_data["id"] = str(inspection.id)
            inspection_data["status"] = getattr(inspection, "status", "DRAFT")
            inspection_data["conclusion"] = getattr(inspection, "conclusion", None)
            inspection_data["date_performed"] = inspection.date_performed.isoformat() if getattr(inspection, "date_performed", None) else None
            equipment_data = {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": getattr(equipment, "serial_number", None),
                "location": getattr(equipment, "location", None),
                "commissioning_date": str(equipment.commissioning_date) if getattr(equipment, "commissioning_date", None) else None,
                "attributes": equipment.attributes or {},
                "type_code": None,
                "type_name": None,
            }
            if equipment.type_id:
                t_res = await db.execute(select(EquipmentType).where(EquipmentType.id == equipment.type_id))
                t = t_res.scalar_one_or_none()
                if t:
                    equipment_data["type_code"] = t.code
                    equipment_data["type_name"] = t.name
            ndt_res = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
            ndt_list = ndt_res.scalars().all()
            ndt_methods_data = []
            for m in ndt_list:
                ndt_methods_data.append({
                    "method_code": getattr(m, "method_code", None),
                    "method_name": getattr(m, "method_name", None),
                    "is_performed": bool(getattr(m, "is_performed", False)),
                    "standard": getattr(m, "standard", None),
                    "equipment": getattr(m, "equipment", None),
                    "inspector_name": getattr(m, "inspector_name", None),
                    "inspector_level": getattr(m, "inspector_level", None),
                    "results": getattr(m, "results", None),
                    "defects": getattr(m, "defects", None),
                    "conclusion": getattr(m, "conclusion", None),
                    "photos": getattr(m, "photos", None) or [],
                    "additional_data": getattr(m, "additional_data", None) or {},
                    "performed_date": m.performed_date.isoformat() if getattr(m, "performed_date", None) else None,
                })
            document_files = []
            q_for_files = None
            if getattr(inspection, "questionnaire_id", None):
                q_res = await db.execute(select(Questionnaire).where(Questionnaire.id == inspection.questionnaire_id))
                q_for_files = q_res.scalar_one_or_none()
            if q_for_files:
                f_res = await db.execute(select(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.questionnaire_id == q_for_files.id))
                for f in f_res.scalars().all():
                    document_files.append({
                        "document_number": f.document_number,
                        "file_name": f.file_name,
                        "file_path": _resolve_report_file_path(f.file_path) or f.file_path,
                        "file_size": int(f.file_size or 0),
                    })
            out_path = os.path.join(temp_dir, f"report_{insp_id}.docx")
            try:
                word_generator.generate_report_word(
                    inspection_data,
                    equipment_data,
                    ndt_methods_data,
                    out_path,
                    report_type,
                    document_files=document_files,
                    specialist_docs=[],
                    verification_equipment=[],
                    template_definition=None,
                )
                generated.append((insp_id, out_path))
            except Exception as e:
                print(f"Bulk export: skip inspection {insp_id}: {e}")
        if not generated:
            raise HTTPException(status_code=400, detail="Не удалось сгенерировать ни одного отчёта")
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for _id, p in generated:
                zf.write(p, os.path.basename(p))
        buf.seek(0)
        return StreamingResponse(
            buf,
            media_type="application/zip",
            headers={"Content-Disposition": "attachment; filename=reports.zip"},
        )
    finally:
        try:
            for _id, p in generated:
                if os.path.exists(p):
                    os.unlink(p)
            if os.path.exists(temp_dir):
                os.rmdir(temp_dir)
        except OSError:
            pass


# Report Templates endpoints (работа с БД)
@app.get("/api/report-templates-db")
async def get_report_templates_db(
    client_id: Optional[str] = None,
    template_type: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список шаблонов отчетов из БД"""
    try:
        from models import ReportTemplate
        query = select(ReportTemplate).where(ReportTemplate.is_active == 1)
        
        if client_id:
            try:
                client_uuid = uuid_lib.UUID(client_id)
                query = query.where(ReportTemplate.client_id == client_uuid)
            except:
                pass
        
        if template_type:
            query = query.where(ReportTemplate.template_type == template_type)
        
        result = await db.execute(query)
        templates = result.scalars().all()
        
        items = []
        for t in templates:
            items.append({
                "id": str(t.id),
                "name": t.name,
                "description": t.description,
                "template_type": t.template_type,
                "client_id": str(t.client_id) if t.client_id else None,
                "template_config": t.template_config,
                "is_default": t.is_default,
                "is_active": t.is_active,
            })
        
        return {"items": items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/report-templates-db")
async def create_report_template_db(
    template_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать шаблон отчета в БД"""
    try:
        from models import ReportTemplate
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        
        client_id = None
        if template_data.get("client_id"):
            try:
                client_id = uuid_lib.UUID(template_data.get("client_id"))
            except:
                pass
        
        if template_data.get("is_default"):
            existing_defaults = await db.execute(
                select(ReportTemplate).where(
                    ReportTemplate.template_type == template_data.get("template_type"),
                    ReportTemplate.is_default == True
                )
            )
            for t in existing_defaults.scalars().all():
                t.is_default = False
        
        template = ReportTemplate(
            name=template_data.get("name"),
            description=template_data.get("description"),
            template_type=template_data.get("template_type", "TECHNICAL"),
            client_id=client_id,
            template_config=template_data.get("template_config", {}),
            is_default=template_data.get("is_default", False),
            created_by=current_user.id if current_user else None,
        )
        
        db.add(template)
        await db.commit()
        await db.refresh(template)
        
        return {"id": str(template.id), "name": template.name, "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/api/report-templates-db/{template_id}")
async def update_report_template_db(
    template_id: str,
    template_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Обновить шаблон отчета в БД"""
    try:
        from models import ReportTemplate
        template_uuid = uuid_lib.UUID(template_id)
        result = await db.execute(
            select(ReportTemplate).where(ReportTemplate.id == template_uuid)
        )
        template = result.scalar_one_or_none()
        
        if not template:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        
        if "name" in template_data:
            template.name = template_data["name"]
        if "description" in template_data:
            template.description = template_data["description"]
        if "template_type" in template_data:
            template.template_type = template_data["template_type"]
        if "template_config" in template_data:
            template.template_config = template_data["template_config"]
        if "client_id" in template_data:
            if template_data["client_id"]:
                try:
                    template.client_id = uuid_lib.UUID(template_data["client_id"])
                except:
                    template.client_id = None
            else:
                template.client_id = None
        
        if "is_default" in template_data:
            if template_data["is_default"]:
                existing_defaults = await db.execute(
                    select(ReportTemplate).where(
                        ReportTemplate.template_type == template.template_type,
                        ReportTemplate.is_default == True,
                        ReportTemplate.id != template_uuid
                    )
                )
                for t in existing_defaults.scalars().all():
                    t.is_default = False
            template.is_default = template_data["is_default"]
        
        await db.commit()
        await db.refresh(template)
        
        return {"id": str(template.id), "name": template.name, "status": "updated"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/report-templates-db/{template_id}")
async def delete_report_template_db(
    template_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить шаблон отчета из БД"""
    try:
        from models import ReportTemplate
        template_uuid = uuid_lib.UUID(template_id)
        result = await db.execute(
            select(ReportTemplate).where(ReportTemplate.id == template_uuid)
        )
        template = result.scalar_one_or_none()
        
        if not template:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        
        template.is_active = 0
        await db.commit()
        
        return {"status": "deleted"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/reports/{report_id}/sign")
async def sign_report(
    report_id: str,
    signature_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Подписать отчет электронной подписью"""
    try:
        from datetime import timezone
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")
        
        report_uuid = uuid_lib.UUID(report_id)
        result = await db.execute(
            select(Report).where(Report.id == report_uuid)
        )
        report = result.scalar_one_or_none()
        
        if not report:
            raise HTTPException(status_code=404, detail="Отчет не найден")
        
        report.is_signed = True
        report.signed_at = datetime.now(timezone.utc)
        report.signed_by = current_user.id
        
        await db.commit()
        await db.refresh(report)
        
        return {
            "id": str(report.id),
            "is_signed": report.is_signed,
            "signed_at": str(report.signed_at),
            "status": "signed"
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/reports/{report_id}")
async def delete_report(
    report_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удаление отчета (admin/operator — любой, engineer — только свой)"""
    try:
        report_uuid = uuid_lib.UUID(report_id)

        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
        report = rep_result.scalar_one_or_none()
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")

        # Проверка прав
        if current_user.role in ["admin", "chief_operator", "operator"]:
            allowed = True
        elif current_user.role == "engineer":
            allowed = False
            if report.created_by and report.created_by == current_user.id:
                allowed = True
            elif report.created_by is None and report.inspection_id:
                insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                insp = insp_result.scalar_one_or_none()
                if insp and insp.inspector_id == current_user.id:
                    allowed = True
        else:
            allowed = False

        if not allowed:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Удаляем файлы
        for p in [report.file_path, getattr(report, "word_file_path", None)]:
            if p:
                try:
                    fp = Path(p)
                    if fp.exists():
                        fp.unlink()
                except Exception:
                    pass

        await db.delete(report)
        await db.commit()
        return {"status": "deleted", "id": report_id}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid report_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete report: {str(e)}")

class BulkDeleteInspectionsRequest(BaseModel):
    inspection_ids: List[str]

@app.post("/api/inspections/bulk-delete")
async def bulk_delete_inspections(
    request: BulkDeleteInspectionsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое удаление чек-листов"""
    try:
        inspection_ids = request.inspection_ids
        if not inspection_ids:
            raise HTTPException(status_code=400, detail="No inspection IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        deleted_count = 0
        for inspection_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
                inspection = insp_result.scalar_one_or_none()
                
                if not inspection:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if inspection.inspector_id and inspection.inspector_id == user.id:
                        allowed = True
                
                if not allowed:
                    continue
                
                # ВАЖНО: НЕ удаляем связанные отчеты при удалении чек-листа!
                # Отчеты должны оставаться в системе даже если чек-лист удален.
                # Проверяем, есть ли связанные отчеты - если есть, не удаляем инспекцию
                rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
                related_reports = rep_result.scalars().all()
                
                if related_reports:
                    # Если есть связанные отчеты, пропускаем удаление этой инспекции
                    print(f"⚠️ Inspection {inspection_id} has {len(related_reports)} related reports. Skipping deletion to preserve reports.")
                    continue
                
                # Удаляем связанные методы НК
                try:
                    ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
                    ndt_methods = ndt_result.scalars().all()
                    for m in ndt_methods:
                        await db.delete(m)
                    if ndt_methods:
                        await db.flush()
                except Exception as e:
                    print(f"⚠️ Error deleting NDT methods for inspection {inspection_id}: {str(e)}")
                
                # Удаляем связанное оборудование для поверок
                try:
                    eq_result = await db.execute(select(InspectionEquipment).where(InspectionEquipment.inspection_id == inspection.id))
                    inspection_equipment = eq_result.scalars().all()
                    for eq in inspection_equipment:
                        await db.delete(eq)
                    if inspection_equipment:
                        await db.flush()
                except Exception as e:
                    print(f"⚠️ Error deleting inspection equipment for inspection {inspection_id}: {str(e)}")
                
                # Теперь можно безопасно удалить сам чек-лист
                await db.delete(inspection)
                deleted_count += 1
            except Exception as e:
                # Логируем ошибку для отладки, но продолжаем обработку других записей
                print(f"⚠️ Error deleting inspection {inspection_id}: {str(e)}")
                continue
        
        await db.commit()
        return {"deleted": deleted_count, "total": len(inspection_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete inspections: {str(e)}")

class BulkArchiveRequest(BaseModel):
    inspection_ids: List[str]
    archive: bool = True

@app.post("/api/inspections/bulk-archive")
async def bulk_archive_inspections(
    request: BulkArchiveRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое архивирование/разархивирование чек-листов"""
    try:
        inspection_ids = request.inspection_ids
        archive = request.archive
        if not inspection_ids:
            raise HTTPException(status_code=400, detail="No inspection IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        archived_count = 0
        for inspection_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
                inspection = insp_result.scalar_one_or_none()
                
                if not inspection:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if inspection.inspector_id and inspection.inspector_id == user.id:
                        allowed = True
                
                if not allowed:
                    continue
                
                inspection.is_archived = archive
                archived_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"archived": archived_count, "total": len(inspection_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to archive inspections: {str(e)}")

class BulkDeleteReportsRequest(BaseModel):
    report_ids: List[str]

@app.post("/api/reports/bulk-delete")
async def bulk_delete_reports(
    request: BulkDeleteReportsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое удаление отчетов"""
    try:
        report_ids = request.report_ids
        if not report_ids:
            raise HTTPException(status_code=400, detail="No report IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        deleted_count = 0
        for report_id in report_ids:
            try:
                report_uuid = uuid_lib.UUID(report_id)
                rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
                report = rep_result.scalar_one_or_none()
                
                if not report:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if report.created_by and report.created_by == user.id:
                        allowed = True
                    elif report.created_by is None and report.inspection_id:
                        insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                        insp = insp_result.scalar_one_or_none()
                        if insp and insp.inspector_id == user.id:
                            allowed = True
                
                if not allowed:
                    continue
                
                # Удаляем файлы
                for p in [report.file_path, getattr(report, "word_file_path", None)]:
                    if p:
                        try:
                            fp = Path(p)
                            if fp.exists():
                                fp.unlink()
                        except Exception:
                            pass
                
                await db.delete(report)
                deleted_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"deleted": deleted_count, "total": len(report_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete reports: {str(e)}")

class BulkArchiveReportsRequest(BaseModel):
    report_ids: List[str]
    archive: bool = True

@app.post("/api/reports/bulk-archive")
async def bulk_archive_reports(
    request: BulkArchiveReportsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое архивирование/разархивирование отчетов"""
    try:
        report_ids = request.report_ids
        archive = request.archive
        if not report_ids:
            raise HTTPException(status_code=400, detail="No report IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        archived_count = 0
        for report_id in report_ids:
            try:
                report_uuid = uuid_lib.UUID(report_id)
                rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
                report = rep_result.scalar_one_or_none()
                
                if not report:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if report.created_by and report.created_by == user.id:
                        allowed = True
                    elif report.created_by is None and report.inspection_id:
                        insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                        insp = insp_result.scalar_one_or_none()
                        if insp and insp.inspector_id == user.id:
                            allowed = True
                
                if not allowed:
                    continue
                
                report.is_archived = archive
                archived_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"archived": archived_count, "total": len(report_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to archive reports: {str(e)}")

@app.delete("/api/reports/cleanup")
async def cleanup_reports(
    older_than_days: int = 90,
    before: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Массовое удаление старых отчетов.
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои
    Параметры:
      - older_than_days: удалить старше N дней (по created_at)
      - before: ISO дата/время (например 2025-12-01 или 2025-12-01T00:00:00)
    """
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        cutoff = None
        if before:
            try:
                cutoff = datetime.fromisoformat(before.replace("Z", "+00:00"))
            except Exception:
                # fallback для формата YYYY-MM-DD
                try:
                    cutoff = datetime.strptime(before, "%Y-%m-%d")
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid 'before' format")
        else:
            if older_than_days < 1:
                raise HTTPException(status_code=400, detail="older_than_days must be >= 1")
            cutoff = datetime.now() - timedelta(days=int(older_than_days))

        query = select(Report).where(Report.created_at < cutoff)

        # Ограничение инженера только своими отчетами (как в get_reports)
        if current_user.role == "engineer":
            query = (
                query.join(Inspection, Report.inspection_id == Inspection.id, isouter=True)
                .where(
                    or_(
                        Report.created_by == current_user.id,
                        and_(Report.created_by.is_(None), Inspection.inspector_id == current_user.id),
                    )
                )
            )
        elif current_user.role not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        result = await db.execute(query)
        reports = result.scalars().all()

        deleted = 0
        for report in reports:
            # удаляем файлы
            for p in [report.file_path, getattr(report, "word_file_path", None)]:
                if p:
                    try:
                        fp = Path(p)
                        if fp.exists():
                            fp.unlink()
                    except Exception:
                        pass
            await db.delete(report)
            deleted += 1

        await db.commit()
        return {"status": "ok", "deleted": deleted, "cutoff": cutoff.isoformat()}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to cleanup reports: {str(e)}")

@app.get("/api/reports/{report_id}/download")
async def download_report(
    report_id: str,
    format: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Download report file (PDF/DOCX)"""
    try:
        # Текущий пользователь и права
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        result = await db.execute(
            select(Report).where(Report.id == uuid_lib.UUID(report_id))
        )
        report = result.scalar_one_or_none()
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")

        # Инженер может скачивать только свои отчеты
        if current_user.role == "engineer":
            allowed = False
            if report.created_by and report.created_by == current_user.id:
                allowed = True
            elif report.created_by is None and report.inspection_id:
                insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                insp = insp_result.scalar_one_or_none()
                if insp and insp.inspector_id == current_user.id:
                    allowed = True
            if not allowed:
                raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Выбор файла по формату (если указан), иначе по расширению/наличию
        fmt = (format or "").strip().lower()
        selected_path = None
        if fmt in ["docx", "doc", "word"]:
            if report.word_file_path and os.path.exists(report.word_file_path):
                selected_path = report.word_file_path
            elif report.file_path and str(report.file_path).lower().endswith(".docx") and os.path.exists(report.file_path):
                selected_path = report.file_path
        elif fmt in ["pdf"]:
            if report.file_path and str(report.file_path).lower().endswith(".pdf") and os.path.exists(report.file_path):
                selected_path = report.file_path

        if not selected_path:
            # auto
            if report.file_path and os.path.exists(report.file_path):
                selected_path = report.file_path
            elif report.word_file_path and os.path.exists(report.word_file_path):
                selected_path = report.word_file_path

        if not selected_path or not os.path.exists(selected_path):
            raise HTTPException(status_code=404, detail="Report file not found")

        filename = os.path.basename(selected_path)
        lower = filename.lower()
        if lower.endswith(".docx"):
            media_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        else:
            media_type = "application/pdf"

        return FileResponse(
            selected_path,
            media_type=media_type,
            filename=filename
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid report_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Questionnaire endpoints
@app.get("/api/questionnaires")
async def get_questionnaires(
    equipment_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Получить список опросных листов"""
    try:
        query = select(Questionnaire)
        
        if equipment_id:
            try:
                equipment_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(Questionnaire.equipment_id == equipment_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        query = query.order_by(Questionnaire.created_at.desc()).offset(skip).limit(limit)
        
        result = await db.execute(query)
        questionnaires = result.scalars().all()
        
        items = []
        for q in questionnaires:
            insp_date = getattr(q, "inspection_date", None) or getattr(q, "date_performed", None)
            items.append({
                "id": str(q.id),
                "equipment_id": str(q.equipment_id),
                "equipment_inventory_number": getattr(q, "equipment_inventory_number", None),
                "equipment_name": getattr(q, "equipment_name", None),
                "inspection_date": insp_date.isoformat() if insp_date else None,
                "inspector_name": getattr(q, "inspector_name", None),
                "inspector_position": getattr(q, "inspector_position", None),
                "file_path": getattr(q, "file_path", None),
                "file_size": getattr(q, "file_size", None) or 0,
                "word_file_path": getattr(q, "word_file_path", None),
                "word_file_size": getattr(q, "word_file_size", None) or 0,
                "created_by": str(q.created_by) if getattr(q, "created_by", None) else None,
                "created_at": q.created_at.isoformat() if q.created_at else None,
            })
        return {"items": items, "total": len(questionnaires)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}")
async def get_questionnaire(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Получить опросный лист по ID"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Получаем методы НК для этого опросного листа
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        insp_date = getattr(questionnaire, "inspection_date", None) or getattr(questionnaire, "date_performed", None)
        return {
            "id": str(questionnaire.id),
            "equipment_id": str(questionnaire.equipment_id),
            "equipment_inventory_number": getattr(questionnaire, "equipment_inventory_number", None),
            "equipment_name": getattr(questionnaire, "equipment_name", None),
            "inspection_date": insp_date.isoformat() if insp_date else None,
            "inspector_name": getattr(questionnaire, "inspector_name", None),
            "inspector_position": getattr(questionnaire, "inspector_position", None),
            "questionnaire_data": getattr(questionnaire, "questionnaire_data", None) or getattr(questionnaire, "data", None),
            "file_path": getattr(questionnaire, "file_path", None),
            "file_size": getattr(questionnaire, "file_size", None) or 0,
            "word_file_path": getattr(questionnaire, "word_file_path", None),
            "word_file_size": getattr(questionnaire, "word_file_size", None) or 0,
            "created_by": str(questionnaire.created_by) if getattr(questionnaire, "created_by", None) else None,
            "created_at": questionnaire.created_at.isoformat() if questionnaire.created_at else None,
            "updated_at": questionnaire.updated_at.isoformat() if questionnaire.updated_at else None,
            "ndt_methods": [
                {
                    "id": str(m.id),
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": m.photos or [],
                    "additional_data": m.additional_data or {},
                    "performed_date": m.performed_date.isoformat() if m.performed_date else None,
                }
                for m in ndt_methods
            ]
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/questionnaires/{questionnaire_id}/ndt-methods")
async def add_ndt_method(
    questionnaire_id: str,
    method_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Добавить метод НК к опросному листу"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Проверяем существование опросного листа
        q_result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = q_result.scalar_one_or_none()
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Создаем метод НК
        performed_date = None
        if method_data.get("performed_date"):
            try:
                performed_date = datetime.fromisoformat(method_data.get("performed_date").replace('Z', '+00:00'))
            except:
                pass
        
        # Обработка аннотированных изображений
        photos_list = method_data.get("photos", [])
        additional_data = method_data.get("additional_data", {})
        
        new_method = NDTMethod(
            questionnaire_id=q_uuid,
            equipment_id=questionnaire.equipment_id,
            method_code=method_data.get("method_code"),
            method_name=method_data.get("method_name"),
            is_performed=1 if method_data.get("is_performed", False) else 0,
            standard=method_data.get("standard"),
            equipment=method_data.get("equipment"),
            inspector_name=method_data.get("inspector_name"),
            inspector_level=method_data.get("inspector_level"),
            results=method_data.get("results"),
            defects=method_data.get("defects"),
            conclusion=method_data.get("conclusion"),
            photos=photos_list,
            additional_data=additional_data,
            performed_date=performed_date,
        )
        
        db.add(new_method)
        await db.commit()
        await db.refresh(new_method)
        
        return {
            "id": str(new_method.id),
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to add NDT method: {str(e)}")

@app.post("/api/questionnaires/{questionnaire_id}/ndt-methods/{method_id}/photos/upload")
async def upload_ndt_method_photo(
    questionnaire_id: str,
    method_id: str,
    file: UploadFile = File(...),
    annotated: Optional[bool] = Form(False),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить фото для метода НК (опросный лист)"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        m_uuid = uuid_lib.UUID(method_id)

        method_result = await db.execute(
            select(NDTMethod).where(
                NDTMethod.id == m_uuid,
                NDTMethod.questionnaire_id == q_uuid
            )
        )
        method = method_result.scalar_one_or_none()
        if not method:
            raise HTTPException(status_code=404, detail="NDT method not found")

        normalized_content_type = _normalize_image_content_type(file)
        if normalized_content_type not in ALLOWED_IMAGE_MIME_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Allowed: {', '.join(sorted(ALLOWED_IMAGE_MIME_TYPES))}"
            )

        upload_dir = Path("/app/uploads/ndt_photos") / "questionnaires" / str(q_uuid) / str(m_uuid)
        upload_dir.mkdir(parents=True, exist_ok=True)

        file_ext = Path(file.filename).suffix if file.filename else ".jpg"
        stored_name = f"{uuid_lib.uuid4()}{file_ext}"
        stored_path = upload_dir / stored_name

        content = await _read_upload_with_limit(file, MAX_NDT_UPLOAD_SIZE_BYTES)
        with open(stored_path, "wb") as f:
            f.write(content)

        photos = list(method.photos or [])
        photos.append(str(stored_path))
        method.photos = photos

        if annotated:
            additional = method.additional_data or {}
            annotated_images = list(additional.get("annotated_images") or [])
            annotated_images.append(str(stored_path))
            additional["annotated_images"] = annotated_images
            method.additional_data = additional

        await db.commit()
        await db.refresh(method)

        return {
            "status": "uploaded",
            "file_path": str(stored_path),
            "photos": method.photos,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to upload NDT photo: {str(e)}")

@app.get("/api/ndt-methods/{method_id}/photos/{file_name}")
async def get_ndt_method_photo(
    method_id: str,
    file_name: str,
    db: AsyncSession = Depends(get_db)
):
    """Получить фото метода НК по имени файла"""
    try:
        m_uuid = uuid_lib.UUID(method_id)
        method_result = await db.execute(select(NDTMethod).where(NDTMethod.id == m_uuid))
        method = method_result.scalar_one_or_none()
        if not method:
            raise HTTPException(status_code=404, detail="NDT method not found")

        photos = list(method.photos or [])
        target = None
        for p in photos:
            if p and Path(p).name == file_name:
                target = p
                break
        if not target or not os.path.exists(target):
            raise HTTPException(status_code=404, detail="Photo not found")

        return FileResponse(target)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid method_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get NDT photo: {str(e)}")

@app.post("/api/inspections/{inspection_id}/ndt-methods")
async def add_ndt_method_to_inspection(
    inspection_id: str,
    method_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Добавить метод НК к обследованию"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        
        # Проверяем существование обследования
        insp_result = await db.execute(
            select(Inspection).where(Inspection.id == insp_uuid)
        )
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")
        
        # Создаем метод НК
        performed_date = None
        if method_data.get("performed_date"):
            try:
                performed_date = datetime.fromisoformat(method_data.get("performed_date").replace('Z', '+00:00'))
            except:
                pass
        
        new_method = NDTMethod(
            inspection_id=insp_uuid,
            equipment_id=inspection.equipment_id,
            method_code=method_data.get("method_code"),
            method_name=method_data.get("method_name"),
            is_performed=1 if method_data.get("is_performed", False) else 0,
            standard=method_data.get("standard"),
            equipment=method_data.get("equipment"),
            inspector_name=method_data.get("inspector_name"),
            inspector_level=method_data.get("inspector_level"),
            results=method_data.get("results"),
            defects=method_data.get("defects"),
            conclusion=method_data.get("conclusion"),
            photos=method_data.get("photos", []),
            additional_data=method_data.get("additional_data", {}),
            performed_date=performed_date,
        )
        
        db.add(new_method)
        await db.commit()
        await db.refresh(new_method)
        
        return {
            "id": str(new_method.id),
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to add NDT method: {str(e)}")

@app.post("/api/inspections/{inspection_id}/ndt-methods/{method_id}/photos/upload")
async def upload_ndt_method_photo_for_inspection(
    inspection_id: str,
    method_id: str,
    file: UploadFile = File(...),
    annotated: Optional[bool] = Form(False),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить фото для метода НК (обследование)"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        m_uuid = uuid_lib.UUID(method_id)

        method_result = await db.execute(
            select(NDTMethod).where(
                NDTMethod.id == m_uuid,
                NDTMethod.inspection_id == insp_uuid
            )
        )
        method = method_result.scalar_one_or_none()
        if not method:
            raise HTTPException(status_code=404, detail="NDT method not found")

        normalized_content_type = _normalize_image_content_type(file)
        if normalized_content_type not in ALLOWED_IMAGE_MIME_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Allowed: {', '.join(sorted(ALLOWED_IMAGE_MIME_TYPES))}"
            )

        upload_dir = Path("/app/uploads/ndt_photos") / "inspections" / str(insp_uuid) / str(m_uuid)
        upload_dir.mkdir(parents=True, exist_ok=True)

        file_ext = Path(file.filename).suffix if file.filename else ".jpg"
        stored_name = f"{uuid_lib.uuid4()}{file_ext}"
        stored_path = upload_dir / stored_name

        content = await _read_upload_with_limit(file, MAX_NDT_UPLOAD_SIZE_BYTES)
        with open(stored_path, "wb") as f:
            f.write(content)

        photos = list(method.photos or [])
        photos.append(str(stored_path))
        method.photos = photos

        if annotated:
            additional = method.additional_data or {}
            annotated_images = list(additional.get("annotated_images") or [])
            annotated_images.append(str(stored_path))
            additional["annotated_images"] = annotated_images
            method.additional_data = additional

        await db.commit()
        await db.refresh(method)

        return {
            "status": "uploaded",
            "file_path": str(stored_path),
            "photos": method.photos,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to upload NDT photo: {str(e)}")

@app.post("/api/questionnaires/{questionnaire_id}/generate-pdf")
async def generate_questionnaire_pdf(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Сгенерировать PDF для опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Получаем данные об оборудовании
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == questionnaire.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Получаем методы НК
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        # Генерируем PDF
        generator = ReportGenerator()
        # Храним генерируемые файлы в /app/reports (примонтирован в docker-compose),
        # чтобы они не пропадали при пересборке контейнера.
        questionnaires_dir = Path("/app/reports/questionnaires")
        questionnaires_dir.mkdir(parents=True, exist_ok=True)
        
        filename = f"questionnaire_{questionnaire.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        file_path = questionnaires_dir / filename
        
        generator.generate_questionnaire_report(
            questionnaire.questionnaire_data or {},
            {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
            },
            {
                "inventory_number": questionnaire.equipment_inventory_number,
                "equipment_name": questionnaire.equipment_name,
                "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
                "inspector_name": questionnaire.inspector_name,
                "inspector_position": questionnaire.inspector_position,
            },
            str(file_path),
            [
                {
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                }
                for m in ndt_methods
            ]
        )
        
        # Обновляем запись опросного листа
        questionnaire.file_path = str(file_path)
        questionnaire.file_size = file_path.stat().st_size if file_path.exists() else 0
        await db.commit()
        
        return {
            "id": str(questionnaire.id),
            "file_path": str(file_path),
            "file_size": questionnaire.file_size,
            "status": "generated"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate PDF: {str(e)}")

@app.get("/api/questionnaires/{questionnaire_id}/download")
async def download_questionnaire(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать опросный лист (PDF)"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Если PDF еще не сгенерирован, генерируем его
        if not questionnaire.file_path or not Path(questionnaire.file_path).exists():
            await generate_questionnaire_pdf(questionnaire_id, db)
            result = await db.execute(
                select(Questionnaire).where(Questionnaire.id == q_uuid)
            )
            questionnaire = result.scalar_one_or_none()
        
        if not questionnaire.file_path:
            raise HTTPException(status_code=404, detail="PDF file not found")
        
        file_path = Path(questionnaire.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="PDF file not found on disk")
        
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type='application/pdf'
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/questionnaires/{questionnaire_id}/generate-word")
async def generate_questionnaire_word(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Сгенерировать Word документ для опросного листа"""
    try:
        from word_generator import WordGenerator
        
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Получаем данные об оборудовании
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == questionnaire.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Получаем методы НК
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        # Генерируем Word
        generator = WordGenerator()
        # Храним генерируемые файлы в /app/reports (примонтирован в docker-compose),
        # чтобы они не пропадали при пересборке контейнера.
        questionnaires_dir = Path("/app/reports/questionnaires")
        questionnaires_dir.mkdir(parents=True, exist_ok=True)
        
        filename = f"questionnaire_{questionnaire.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.docx"
        file_path = questionnaires_dir / filename
        
        generator.generate_questionnaire_word(
            questionnaire.questionnaire_data or {},
            {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
            },
            {
                "inventory_number": questionnaire.equipment_inventory_number,
                "equipment_name": questionnaire.equipment_name,
                "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
                "inspector_name": questionnaire.inspector_name,
                "inspector_position": questionnaire.inspector_position,
            },
            [
                {
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                }
                for m in ndt_methods
            ],
            str(file_path)
        )
        
        # Обновляем запись опросного листа
        questionnaire.word_file_path = str(file_path)
        questionnaire.word_file_size = file_path.stat().st_size if file_path.exists() else 0
        await db.commit()
        
        return {
            "id": str(questionnaire.id),
            "word_file_path": str(file_path),
            "word_file_size": questionnaire.word_file_size,
            "status": "generated"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate Word: {str(e)}")

@app.get("/api/questionnaires/{questionnaire_id}/download-word")
async def download_questionnaire_word(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать Word документ опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Если Word еще не сгенерирован, генерируем его
        if not questionnaire.word_file_path or not Path(questionnaire.word_file_path).exists():
            await generate_questionnaire_word(questionnaire_id, db)
            result = await db.execute(
                select(Questionnaire).where(Questionnaire.id == q_uuid)
            )
            questionnaire = result.scalar_one_or_none()
        
        if not questionnaire.word_file_path:
            raise HTTPException(status_code=404, detail="Word file not found")
        
        file_path = Path(questionnaire.word_file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="Word file not found on disk")
        
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Document files endpoints
@app.post("/api/questionnaires/{questionnaire_id}/documents/{document_number}/upload")
async def upload_document_file(
    questionnaire_id: str,
    document_number: str,
    file: UploadFile = File(...),
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить файл документа для чек-листа. Лимит: 25 МБ на файл, до 60 вложений на опросник."""
    try:
        # Проверяем формат questionnaire_id
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Проверяем существование опросного листа
        q_result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = q_result.scalar_one_or_none()
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Проверяем номер/ключ документа.
        # - Основной список (1..17) — "Перечень рассмотренных документов".
        # - Дополнительно разрешаем любые "безопасные" ключи для прочих вложений чек-листа:
        #   factory_plate_photo, control_scheme_image, photo_1, scheme_2025_12 и т.п.
        allowed_numbers = {str(i) for i in range(1, 18)}
        if document_number not in allowed_numbers:
            import re
            # безопасный ключ: латиница/цифры/подчерк/дефис, 1..64 символа
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", document_number):
                raise HTTPException(
                    status_code=400,
                    detail="Invalid document key. Use 1..17 or a safe key like factory_plate_photo/control_scheme_image/photo_1",
                )
        
        # Проверяем тип файла (только изображения и PDF). Если клиент не передал Content-Type — определяем по расширению.
        allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'application/pdf']
        content_type = file.content_type
        if not content_type or content_type not in allowed_types:
            ext = (Path(file.filename or "").suffix or "").lower()
            if ext in (".jpg", ".jpeg"):
                content_type = "image/jpeg"
            elif ext == ".png":
                content_type = "image/png"
            elif ext == ".pdf":
                content_type = "application/pdf"
            else:
                content_type = None
        if content_type not in allowed_types:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Allowed types: {', '.join(allowed_types)}",
            )
        
        # Получаем пользователя для uploaded_by
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        user_id = user.id if user else None
        
        # Создаем директорию для файлов документов в /app/uploads (примонтирован),
        # чтобы вложения чек-листа не пропадали при пересборке контейнера.
        documents_dir = Path("/app/uploads/questionnaire_documents") / str(q_uuid)
        documents_dir.mkdir(parents=True, exist_ok=True)
        
        # Генерируем уникальное имя файла
        file_extension = Path(file.filename).suffix if file.filename else '.bin'
        if content_type == 'application/pdf':
            file_extension = '.pdf'
        elif content_type and 'image' in content_type:
            file_extension = '.jpg' if 'jpeg' in content_type else '.png'
        
        file_id = uuid_lib.uuid4()
        file_name = f"doc_{document_number}_{file_id}{file_extension}"
        file_path = documents_dir / file_name
        
        # Лимит размера файла (25 МБ), читаем чанками
        MAX_FILE_SIZE_BYTES = 25 * 1024 * 1024
        file_content = b""
        while True:
            chunk = await file.read(1024 * 1024)
            if not chunk:
                break
            file_content += chunk
            if len(file_content) > MAX_FILE_SIZE_BYTES:
                raise HTTPException(
                    status_code=400,
                    detail=f"Файл слишком большой. Максимум {MAX_FILE_SIZE_BYTES // (1024*1024)} МБ.",
                )
        # Удаляем старый файл для этого документа, если есть (проверки до записи на диск)
        old_file_result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        old_file = old_file_result.scalar_one_or_none()
        if not old_file:
            MAX_DOCS = 60
            cnt = (await db.execute(select(func.count(QuestionnaireDocumentFile.id)).where(QuestionnaireDocumentFile.questionnaire_id == q_uuid))).scalar() or 0
            if cnt >= MAX_DOCS:
                raise HTTPException(status_code=400, detail=f"Превышен лимит вложений ({MAX_DOCS}).")
        if old_file:
            old_path = Path(old_file.file_path)
            if old_path.exists():
                old_path.unlink()
            await db.execute(delete(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.id == old_file.id))
        with open(file_path, 'wb') as f:
            f.write(file_content)
        file_size = len(file_content)
        
        # Создаем новую запись в БД
        new_file = QuestionnaireDocumentFile(
            questionnaire_id=q_uuid,
            document_number=document_number,
            file_name=file.filename or file_name,
            file_path=str(file_path),
            file_size=file_size,
            file_type=content_type.split('/')[0] if content_type else None,  # image или application
            mime_type=content_type,
            uploaded_by=user_id
        )
        
        db.add(new_file)
        await db.commit()
        await db.refresh(new_file)
        
        # Если загружено фото дефекта ВИК (vd_i_j) — обновляем inspection.data для отчётов
        if isinstance(document_number, str) and document_number.startswith("vd_"):
            try:
                parts = document_number.split("_")
                if len(parts) == 3 and parts[0] == "vd":
                    i, j = int(parts[1]), int(parts[2])
                    insp_result = await db.execute(
                        select(Inspection).where(Inspection.questionnaire_id == q_uuid)
                    )
                    insp = insp_result.scalar_one_or_none()
                    if insp and isinstance(insp.data, dict):
                        data = dict(insp.data)
                        vd = data.get("visual_defects")
                        if isinstance(vd, list) and 0 <= i < len(vd):
                            d = vd[i]
                            if isinstance(d, dict):
                                d = dict(d)
                                ph = d.get("photos") or []
                                if isinstance(ph, list) and 0 <= j < len(ph):
                                    ph = list(ph)
                                    ph[j] = str(file_path)
                                    d["photos"] = ph
                                    vd = list(vd)
                                    vd[i] = d
                                    data["visual_defects"] = vd
                                    insp.data = data
                                    await db.commit()
            except Exception:
                pass
        
        return {
            "id": str(new_file.id),
            "questionnaire_id": questionnaire_id,
            "document_number": document_number,
            "file_name": new_file.file_name,
            "file_size": new_file.file_size,
            "file_type": new_file.file_type,
            "mime_type": new_file.mime_type,
            "created_at": new_file.created_at.isoformat() if new_file.created_at else None
        }
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to upload file: {str(e)}")

@app.get("/api/questionnaires/{questionnaire_id}/documents/{document_number}/download")
async def download_document_file(
    questionnaire_id: str,
    document_number: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать файл документа чек-листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Ищем файл
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()
        
        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")
        
        file_path = Path(doc_file.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="File not found on disk")
        
        # Определяем media_type
        media_type = doc_file.mime_type or 'application/octet-stream'
        if doc_file.file_type == 'image':
            if 'jpeg' in doc_file.mime_type or 'jpg' in doc_file.mime_type:
                media_type = 'image/jpeg'
            elif 'png' in doc_file.mime_type:
                media_type = 'image/png'
        elif doc_file.file_type == 'application' or 'pdf' in doc_file.mime_type:
            media_type = 'application/pdf'
        
        return FileResponse(
            path=str(file_path),
            filename=doc_file.file_name,
            media_type=media_type
        )
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}/documents")
async def get_questionnaire_documents(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Получить список всех файлов документов для опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid
            ).order_by(QuestionnaireDocumentFile.document_number)
        )
        files = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(f.id),
                    "document_number": f.document_number,
                    "file_name": f.file_name,
                    "file_size": f.file_size,
                    "file_type": f.file_type,
                    "mime_type": f.mime_type,
                    "created_at": f.created_at.isoformat() if f.created_at else None
                }
                for f in files
            ],
            "total": len(files)
        }
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}/documents/{document_number}/view")
async def view_document_file(
    questionnaire_id: str,
    document_number: str,
    db: AsyncSession = Depends(get_db)
):
    """
    Просмотр файла документа чек-листа в браузере (Content-Disposition: inline).
    Поддерживает изображения и PDF.
    """
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)

        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()

        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")

        file_path = Path(doc_file.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="File not found on disk")

        media_type = doc_file.mime_type or 'application/octet-stream'
        if doc_file.file_type == 'image':
            if doc_file.mime_type and ('jpeg' in doc_file.mime_type or 'jpg' in doc_file.mime_type):
                media_type = 'image/jpeg'
            elif doc_file.mime_type and 'png' in doc_file.mime_type:
                media_type = 'image/png'
        elif (doc_file.file_type == 'application') or (doc_file.mime_type and 'pdf' in doc_file.mime_type):
            media_type = 'application/pdf'

        return FileResponse(
            path=str(file_path),
            media_type=media_type,
            headers={
                "Content-Disposition": f'inline; filename="{doc_file.file_name}"'
            }
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/questionnaires/{questionnaire_id}/documents/{document_number}")
async def delete_document_file(
    questionnaire_id: str,
    document_number: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить файл документа чек-листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Ищем файл
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()
        
        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")
        
        # Удаляем файл с диска
        file_path = Path(doc_file.file_path)
        if file_path.exists():
            file_path.unlink()
        
        # Удаляем запись из БД
        await db.execute(delete(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.id == doc_file.id))
        await db.commit()
        
        return {"status": "deleted", "document_number": document_number}
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# ========== API для управления поверками оборудования ==========

@app.get("/api/verification-equipment")
async def get_verification_equipment(
    days_before_expiry: Optional[int] = None,  # Предупреждение за N дней до истечения
    equipment_type: Optional[str] = None,  # Фильтр по типу
    is_active: Optional[bool] = True,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить список оборудования для поверок"""
    try:
        query = select(VerificationEquipment)
        
        if is_active is not None:
            query = query.where(VerificationEquipment.is_active == (1 if is_active else 0))
        
        if equipment_type:
            query = query.where(VerificationEquipment.equipment_type == equipment_type)
        
        if days_before_expiry is not None:
            today = date.today()
            warning_date = today + timedelta(days=days_before_expiry)
            query = query.where(
                VerificationEquipment.next_verification_date <= warning_date,
                VerificationEquipment.next_verification_date >= today
            )
        
        # Сортировка с учетом NULL значений (NULLS LAST)
        result = await db.execute(query.order_by(nulls_last(VerificationEquipment.next_verification_date)))
        items = result.scalars().all()
        
        return [{
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "category": item.category,
            "serial_number": item.serial_number,
            "manufacturer": item.manufacturer,
            "model": item.model,
            "inventory_number": item.inventory_number,
            "verification_date": item.verification_date.isoformat() if item.verification_date else None,
            "next_verification_date": item.next_verification_date.isoformat() if item.next_verification_date else None,
            "verification_certificate_number": item.verification_certificate_number,
            "verification_organization": item.verification_organization,
            "scan_file_path": item.scan_file_path,
            "scan_file_name": item.scan_file_name,
            "is_active": bool(item.is_active),
            "notes": item.notes,
            "days_until_expiry": (item.next_verification_date - date.today()).days if item.next_verification_date else None,
            "is_expired": item.next_verification_date < date.today() if item.next_verification_date else False,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        } for item in items]
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_verification_equipment: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении оборудования для поверок: {error_detail}")

@app.post("/api/verification-equipment")
async def create_verification_equipment(
    name: str = Form(...),
    equipment_type: str = Form(...),
    serial_number: str = Form(...),
    verification_date: str = Form(...),
    next_verification_date: str = Form(...),
    category: Optional[str] = Form(None),
    manufacturer: Optional[str] = Form(None),
    model: Optional[str] = Form(None),
    inventory_number: Optional[str] = Form(None),
    verification_certificate_number: Optional[str] = Form(None),
    verification_organization: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    scan_file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Создать новое оборудование для поверки"""
    try:
        # Проверка прав (только admin, chief_operator, operator)
        if current_user.get("role") not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        new_id = uuid_lib.uuid4()
        scan_file_path = None
        scan_file_name = None
        scan_file_size = None
        scan_mime_type = None
        
        if scan_file:
            upload_dir = Path("/app/uploads/verification_scans") / str(new_id)
            upload_dir.mkdir(parents=True, exist_ok=True)
            
            file_ext = Path(scan_file.filename).suffix
            file_name = f"{uuid_lib.uuid4()}{file_ext}"
            file_path = upload_dir / file_name
            
            content = await scan_file.read()
            with open(file_path, "wb") as f:
                f.write(content)
            
            scan_file_path = str(file_path)
            scan_file_name = scan_file.filename
            scan_file_size = len(content)
            scan_mime_type = scan_file.content_type
        
        verification_date_obj = datetime.strptime(verification_date, "%Y-%m-%d").date()
        next_verification_date_obj = datetime.strptime(next_verification_date, "%Y-%m-%d").date()
        
        new_equipment = VerificationEquipment(
            id=new_id,
            name=name,
            equipment_type=equipment_type,
            category=category,
            serial_number=serial_number,
            manufacturer=manufacturer,
            model=model,
            inventory_number=inventory_number,
            verification_date=verification_date_obj,
            next_verification_date=next_verification_date_obj,
            verification_certificate_number=verification_certificate_number,
            verification_organization=verification_organization,
            scan_file_path=scan_file_path,
            scan_file_name=scan_file_name,
            scan_file_size=scan_file_size,
            scan_mime_type=scan_mime_type,
            notes=notes
        )
        
        db.add(new_equipment)
        await db.commit()
        await db.refresh(new_equipment)
        
        return {
            "id": str(new_equipment.id),
            "name": new_equipment.name,
            "equipment_type": new_equipment.equipment_type,
            "serial_number": new_equipment.serial_number,
            "next_verification_date": new_equipment.next_verification_date.isoformat(),
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Неверный формат даты: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/verification-equipment/{equipment_id}")
async def get_verification_equipment_by_id(
    equipment_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить оборудование для поверки по ID"""
    try:
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Получить историю поверок
        history_result = await db.execute(
            select(VerificationHistory)
            .where(VerificationHistory.verification_equipment_id == item.id)
            .order_by(VerificationHistory.verification_date.desc())
        )
        history = history_result.scalars().all()
        
        return {
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "category": item.category,
            "serial_number": item.serial_number,
            "manufacturer": item.manufacturer,
            "model": item.model,
            "inventory_number": item.inventory_number,
            "verification_date": item.verification_date.isoformat() if item.verification_date else None,
            "next_verification_date": item.next_verification_date.isoformat() if item.next_verification_date else None,
            "verification_certificate_number": item.verification_certificate_number,
            "verification_organization": item.verification_organization,
            "scan_file_path": item.scan_file_path,
            "scan_file_name": item.scan_file_name,
            "scan_file_size": item.scan_file_size,
            "scan_mime_type": item.scan_mime_type,
            "is_active": bool(item.is_active),
            "notes": item.notes,
            "days_until_expiry": (item.next_verification_date - date.today()).days if item.next_verification_date else None,
            "is_expired": item.next_verification_date < date.today() if item.next_verification_date else False,
            "history": [{
                "id": str(h.id),
                "verification_date": h.verification_date.isoformat(),
                "next_verification_date": h.next_verification_date.isoformat(),
                "certificate_number": h.certificate_number,
                "verification_organization": h.verification_organization,
                "scan_file_path": h.scan_file_path,
                "scan_file_name": h.scan_file_name,
                "notes": h.notes,
                "created_at": h.created_at.isoformat() if h.created_at else None,
            } for h in history],
            "created_at": item.created_at.isoformat() if item.created_at else None,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/api/verification-equipment/{equipment_id}")
async def update_verification_equipment(
    equipment_id: str,
    name: Optional[str] = Form(None),
    equipment_type: Optional[str] = Form(None),
    serial_number: Optional[str] = Form(None),
    verification_date: Optional[str] = Form(None),
    next_verification_date: Optional[str] = Form(None),
    category: Optional[str] = Form(None),
    manufacturer: Optional[str] = Form(None),
    model: Optional[str] = Form(None),
    inventory_number: Optional[str] = Form(None),
    verification_certificate_number: Optional[str] = Form(None),
    verification_organization: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    is_active: Optional[bool] = Form(None),
    scan_file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Обновить оборудование для поверки"""
    try:
        if current_user.get("role") not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Сохранить старую запись в историю, если изменилась дата поверки
        if verification_date and item.verification_date:
            old_date = item.verification_date
            new_date = datetime.strptime(verification_date, "%Y-%m-%d").date()
            if old_date != new_date:
                history_entry = VerificationHistory(
                    verification_equipment_id=item.id,
                    verification_date=old_date,
                    next_verification_date=item.next_verification_date,
                    certificate_number=item.verification_certificate_number,
                    verification_organization=item.verification_organization,
                    scan_file_path=item.scan_file_path,
                    scan_file_name=item.scan_file_name,
                    notes=item.notes
                )
                if "id" in current_user:
                    history_entry.created_by = uuid_lib.UUID(current_user["id"])
                db.add(history_entry)
        
        if name is not None:
            item.name = name
        if equipment_type is not None:
            item.equipment_type = equipment_type
        if category is not None:
            item.category = category
        if serial_number is not None:
            item.serial_number = serial_number
        if manufacturer is not None:
            item.manufacturer = manufacturer
        if model is not None:
            item.model = model
        if inventory_number is not None:
            item.inventory_number = inventory_number
        if verification_date is not None:
            item.verification_date = datetime.strptime(verification_date, "%Y-%m-%d").date()
        if next_verification_date is not None:
            item.next_verification_date = datetime.strptime(next_verification_date, "%Y-%m-%d").date()
        if verification_certificate_number is not None:
            item.verification_certificate_number = verification_certificate_number
        if verification_organization is not None:
            item.verification_organization = verification_organization
        if notes is not None:
            item.notes = notes
        if is_active is not None:
            item.is_active = 1 if is_active else 0
        
        if scan_file:
            # Удалить старый файл, если есть
            if item.scan_file_path and os.path.exists(item.scan_file_path):
                try:
                    os.remove(item.scan_file_path)
                except:
                    pass
            
            upload_dir = Path("/app/uploads/verification_scans") / str(item.id)
            upload_dir.mkdir(parents=True, exist_ok=True)
            
            file_ext = Path(scan_file.filename).suffix
            file_name = f"{uuid_lib.uuid4()}{file_ext}"
            file_path = upload_dir / file_name
            
            content = await scan_file.read()
            with open(file_path, "wb") as f:
                f.write(content)
            
            item.scan_file_path = str(file_path)
            item.scan_file_name = scan_file.filename
            item.scan_file_size = len(content)
            item.scan_mime_type = scan_file.content_type
        
        await db.commit()
        await db.refresh(item)
        
        return {
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "next_verification_date": item.next_verification_date.isoformat(),
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Неверный формат: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/verification-equipment/{equipment_id}")
async def delete_verification_equipment(
    equipment_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Удалить оборудование для поверки"""
    try:
        if current_user.get("role") not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Удалить файл скана, если есть
        if item.scan_file_path and os.path.exists(item.scan_file_path):
            try:
                os.remove(item.scan_file_path)
            except:
                pass
        
        await db.delete(item)
        await db.commit()
        
        return {"status": "deleted", "id": equipment_id}
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/verification-equipment/{equipment_id}/scan")
async def get_verification_scan(
    equipment_id: str,
    inline: bool = False,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить скан свидетельства о поверке"""
    try:
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item or not item.scan_file_path:
            raise HTTPException(status_code=404, detail="Скан не найден")
        
        if not os.path.exists(item.scan_file_path):
            raise HTTPException(status_code=404, detail="Файл не найден на сервере")
        
        from fastapi.responses import StreamingResponse
        
        def iterfile():
            with open(item.scan_file_path, mode="rb") as file_like:
                yield from file_like
        
        headers = {}
        if inline:
            headers["Content-Disposition"] = f'inline; filename="{item.scan_file_name or "scan.pdf"}"'
        else:
            headers["Content-Disposition"] = f'attachment; filename="{item.scan_file_name or "scan.pdf"}"'
        
        return StreamingResponse(
            iterfile(),
            media_type=item.scan_mime_type or "application/pdf",
            headers=headers
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/inspections/{inspection_id}/equipment")
async def add_equipment_to_inspection(
    inspection_id: str,
    equipment_data: dict,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Добавить используемое оборудование для поверок к обследованию"""
    try:
        # Проверка существования обследования
        insp_uuid = uuid_lib.UUID(inspection_id)
        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        
        if not inspection:
            raise HTTPException(status_code=404, detail="Обследование не найдено")
        
        # Проверка прав
        user_result = await db.execute(select(User).where(User.username == current_user["username"]))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        
        if user.role not in ["admin", "chief_operator", "operator", "engineer"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        # Если engineer, проверяем, что это его обследование
        if user.role == "engineer" and inspection.inspector_id != user.id:
            raise HTTPException(status_code=403, detail="Можно добавлять оборудование только к своим обследованиям")
        
        # Получаем список ID оборудования для поверок
        equipment_ids = equipment_data.get("verification_equipment_ids", [])
        if not isinstance(equipment_ids, list):
            raise HTTPException(status_code=400, detail="verification_equipment_ids должен быть списком")
        
        added = []
        for eq_id in equipment_ids:
            try:
                eq_uuid = uuid_lib.UUID(eq_id)
                # Проверяем существование оборудования
                eq_result = await db.execute(
                    select(VerificationEquipment).where(VerificationEquipment.id == eq_uuid)
                )
                ver_eq = eq_result.scalar_one_or_none()
                
                if not ver_eq:
                    continue
                
                # Проверяем, не добавлено ли уже
                existing = await db.execute(
                    select(InspectionEquipment).where(
                        InspectionEquipment.inspection_id == insp_uuid,
                        InspectionEquipment.verification_equipment_id == eq_uuid
                    )
                )
                if existing.scalar_one_or_none():
                    continue
                
                # Создаем связь
                inspection_equipment = InspectionEquipment(
                    inspection_id=insp_uuid,
                    verification_equipment_id=eq_uuid
                )
                db.add(inspection_equipment)
                added.append(str(eq_id))
            except ValueError:
                continue
        
        await db.commit()
        
        return {
            "status": "success",
            "inspection_id": inspection_id,
            "equipment_added": len(added),
            "equipment_ids": added
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/inspections/{inspection_id}/equipment")
async def get_inspection_equipment(
    inspection_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить список используемого оборудования для обследования"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        
        result = await db.execute(
            select(InspectionEquipment, VerificationEquipment)
            .join(VerificationEquipment, InspectionEquipment.verification_equipment_id == VerificationEquipment.id)
            .where(InspectionEquipment.inspection_id == insp_uuid)
        )
        items = result.all()
        
        equipment_list = []
        for ie, ve in items:
            equipment_list.append({
                "id": str(ve.id),
                "name": ve.name,
                "equipment_type": ve.equipment_type,
                "serial_number": ve.serial_number,
                "manufacturer": ve.manufacturer,
                "model": ve.model,
                "verification_date": ve.verification_date.isoformat() if ve.verification_date else None,
                "next_verification_date": ve.next_verification_date.isoformat() if ve.next_verification_date else None,
                "verification_certificate_number": ve.verification_certificate_number,
                "verification_organization": ve.verification_organization,
                "scan_file_path": ve.scan_file_path,
                "scan_file_name": ve.scan_file_name,
                "is_expired": ve.next_verification_date < date.today() if ve.next_verification_date else False,
            })
        
        return equipment_list
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/verification-equipment/export")
async def export_verification_equipment(
    format: str = "csv",  # csv или excel
    days_before_expiry: Optional[int] = None,
    equipment_type: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Экспорт списка оборудования для поверок"""
    try:
        query = select(VerificationEquipment).where(VerificationEquipment.is_active == 1)
        
        if equipment_type:
            query = query.where(VerificationEquipment.equipment_type == equipment_type)
        
        if days_before_expiry is not None:
            today = date.today()
            warning_date = today + timedelta(days=days_before_expiry)
            query = query.where(
                VerificationEquipment.next_verification_date <= warning_date,
                VerificationEquipment.next_verification_date >= today
            )
        
        result = await db.execute(query.order_by(VerificationEquipment.next_verification_date))
        items = result.scalars().all()
        
        if format.lower() == "csv":
            import csv
            import io
            
            output = io.StringIO()
            writer = csv.writer(output)
            
            # Заголовки
            writer.writerow([
                'Название', 'Тип', 'Категория', 'Серийный номер', 'Производитель', 'Модель',
                'Инвентарный номер', 'Дата поверки', 'Следующая поверка', 'Номер свидетельства',
                'Организация поверки', 'Статус', 'Дней до истечения'
            ])
            
            # Данные
            for item in items:
                days = (item.next_verification_date - date.today()).days if item.next_verification_date else None
                status = "Просрочено" if (item.next_verification_date and item.next_verification_date < date.today()) else (
                    f"Предупреждение ({days} дн.)" if days and days <= 30 else "Активно"
                )
                writer.writerow([
                    item.name or '',
                    item.equipment_type or '',
                    item.category or '',
                    item.serial_number or '',
                    item.manufacturer or '',
                    item.model or '',
                    item.inventory_number or '',
                    item.verification_date.strftime('%d.%m.%Y') if item.verification_date else '',
                    item.next_verification_date.strftime('%d.%m.%Y') if item.next_verification_date else '',
                    item.verification_certificate_number or '',
                    item.verification_organization or '',
                    status,
                    str(days) if days is not None else '',
                ])
            
            csv_content = output.getvalue()
            output.close()
            
            from fastapi.responses import Response
            return Response(
                content='\ufeff' + csv_content,
                media_type='text/csv; charset=utf-8',
                headers={'Content-Disposition': f'attachment; filename="verification_equipment_{date.today().isoformat()}.csv"'}
            )
        else:
            raise HTTPException(status_code=400, detail="Неподдерживаемый формат экспорта")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

@app.patch("/api/inspections/{inspection_id}/status")
async def update_inspection_status(
    inspection_id: str,
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Изменить статус чек-листа/обследования (Inspection).
    Статусы: DRAFT, SIGNED, APPROVED
    - admin/chief_operator/operator: могут устанавливать любой из поддерживаемых статусов
    - engineer: может менять статус только своих инспекций и только на DRAFT/SIGNED
    """
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)

        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        new_status = (payload.get("status") or "").strip().upper()
        allowed_statuses = {"DRAFT", "SIGNED", "APPROVED"}
        if new_status not in allowed_statuses:
            raise HTTPException(status_code=400, detail="Invalid status. Allowed: DRAFT, SIGNED, APPROVED")

        # RBAC
        if current_user.role in ["admin", "chief_operator", "operator"]:
            pass
        elif current_user.role == "engineer":
            if not (inspection.inspector_id and inspection.inspector_id == current_user.id):
                raise HTTPException(status_code=403, detail="Доступ запрещен")
            if new_status not in {"DRAFT", "SIGNED"}:
                raise HTTPException(status_code=403, detail="Инженер не может утверждать (APPROVED)")
        else:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        inspection.status = new_status
        inspection.updated_by = current_user.id
        await db.commit()
        await db.refresh(inspection)

        return {"status": "ok", "id": inspection_id, "new_status": inspection.status}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update inspection status: {str(e)}")

@app.post("/api/inspections", tags=["inspections"])
async def create_inspection(
    inspection_data: dict,
    username: Optional[str] = Depends(verify_token_optional),
    db: AsyncSession = Depends(get_db)
):
    """Create new inspection. При авторизации заполняются created_by (аудит)."""
    try:
        created_by_id = None
        if username:
            user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
            u = user_result.scalar_one_or_none()
            if u:
                created_by_id = u.id
        _validate_create_inspection(inspection_data)
        # Parse equipment_id
        equipment_id = None
        if inspection_data.get("equipment_id"):
            try:
                equipment_id = uuid_lib.UUID(inspection_data.get("equipment_id"))
            except (ValueError, TypeError):
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        # Parse date_performed if provided
        date_performed = None
        if inspection_data.get("date_performed"):
            try:
                date_performed = datetime.fromisoformat(inspection_data.get("date_performed").replace('Z', '+00:00'))
            except:
                pass
        
        # Parse project_id if provided
        project_id = None
        if inspection_data.get("project_id"):
            try:
                project_id = uuid_lib.UUID(inspection_data.get("project_id"))
            except:
                pass

        # Если в data указано include_opo_data=false, а у оборудования есть opo_id —
        # подтягиваем сохранённые данные ОПО и сливаем документы 1..9.
        try:
            inspection_data_dict = inspection_data.get("data", {}) or {}
            if isinstance(inspection_data_dict, dict):
                include_opo_data = inspection_data_dict.get("include_opo_data", True)
                if include_opo_data is False and equipment_id:
                    eq_result = await db.execute(select(Equipment).where(Equipment.id == equipment_id))
                    equipment = eq_result.scalar_one_or_none()
                    opo_id = getattr(equipment, "opo_id", None) if equipment else None
                    if opo_id:
                        opo_result = await db.execute(select(Opo).where(Opo.id == opo_id))
                        opo = opo_result.scalar_one_or_none()
                        survey = (opo.survey_data or {}) if opo else {}

                        # Мерджим documents[1..9] из survey в текущий documents
                        docs_current = inspection_data_dict.get("documents") or {}
                        if isinstance(docs_current, dict) and isinstance(survey, dict) and isinstance(survey.get("documents"), dict):
                            merged_docs = dict(docs_current)
                            for k, v in survey.get("documents").items():
                                try:
                                    n = int(str(k))
                                except Exception:
                                    continue
                                if 1 <= n <= 9:
                                    merged_docs[str(k)] = v
                            inspection_data_dict["documents"] = merged_docs

                        # Подтягиваем organization/executors, если не заполнены в чек-листе оборудования
                        if isinstance(survey, dict):
                            if not inspection_data_dict.get("organization") and survey.get("organization"):
                                inspection_data_dict["organization"] = survey.get("organization")
                            if not inspection_data_dict.get("executors") and survey.get("executors"):
                                inspection_data_dict["executors"] = survey.get("executors")

                            # Сохраняем survey отдельным блоком (для отчетов/просмотра)
                            inspection_data_dict["opo_survey"] = survey

                        inspection_data["data"] = inspection_data_dict
        except Exception:
            # Не блокируем создание инспекции из-за мерджа ОПО
            pass
        
        inspection_payload_data = inspection_data.get("data", {}) if isinstance(inspection_data.get("data", {}), dict) else {}
        inspection_type_value = (
            inspection_data.get("inspection_type")
            or inspection_payload_data.get("inspection_type")
        )
        if not inspection_type_value:
            if inspection_payload_data.get("weld_inspections") or inspection_payload_data.get("thickness_measurements"):
                inspection_type_value = "NDT"
            elif inspection_payload_data.get("documents") or inspection_payload_data.get("questionnaire"):
                inspection_type_value = "QUESTIONNAIRE"
            else:
                inspection_type_value = "VISUAL"

        inspection_method_value = (
            inspection_data.get("inspection_method")
            or inspection_payload_data.get("inspection_method")
            or inspection_payload_data.get("method_code")
        )
        inspection_category_value = (
            inspection_data.get("inspection_category")
            or inspection_payload_data.get("inspection_category")
        )

        new_inspection = Inspection(
            equipment_id=equipment_id,
            project_id=project_id,
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT"),
            date_performed=date_performed,
            inspection_type=inspection_type_value,
            inspection_method=inspection_method_value,
            inspection_category=inspection_category_value,
            is_archived=False,  # Явно устанавливаем значение
            created_by=created_by_id,
        )
        db.add(new_inspection)
        await db.flush()
        await _log_audit(
            db, created_by_id, "CREATE", "inspection", new_inspection.id,
            {"equipment_id": str(equipment_id), "status": inspection_data.get("status", "DRAFT")},
        )
        await db.commit()
        await db.refresh(new_inspection)
        
        # Если это чек-лист сосуда (vessel checklist), создаем questionnaire (чтобы мобильное могло загрузить фото/сканы)
        questionnaire_id = None
        inspection_data_dict = inspection_data.get("data", {})
        if inspection_data_dict and isinstance(inspection_data_dict, dict):
            has_vessel_data = (
                inspection_data_dict.get("documents")
                or inspection_data_dict.get("vessel_name")
                or inspection_data_dict.get("factory_plate_photo")
                or inspection_data_dict.get("control_scheme_image")
                or (inspection_data_dict.get("visual_defects") and len(inspection_data_dict.get("visual_defects") or []) > 0)
                or (inspection_data_dict.get("thickness_measurements") and len(inspection_data_dict.get("thickness_measurements") or []) > 0)
            )
            if has_vessel_data:
                # Получаем информацию об оборудовании
                eq_result = await db.execute(
                    select(Equipment).where(Equipment.id == equipment_id)
                )
                equipment = eq_result.scalar_one_or_none()
                
                # Извлекаем данные из inspection_data
                inspection_date_str = inspection_data_dict.get("inspection_date")
                inspection_date_obj = None
                if inspection_date_str:
                    try:
                        if isinstance(inspection_date_str, str):
                            inspection_date_obj = datetime.fromisoformat(inspection_date_str.replace('Z', '+00:00')).date()
                    except:
                        pass
                
                # Создаем questionnaire (только поля из модели: equipment_id, data, date_performed, status, assignment_id)
                assignment_id_q = None
                if inspection_data.get("assignment_id"):
                    try:
                        assignment_id_q = uuid_lib.UUID(inspection_data.get("assignment_id"))
                    except Exception:
                        pass
                new_questionnaire = Questionnaire(
                    equipment_id=equipment_id,
                    data=inspection_data_dict,
                    date_performed=date_performed,
                    status=inspection_data.get("status", "DRAFT"),
                    assignment_id=assignment_id_q,
                    created_by=created_by_id,
                )
                db.add(new_questionnaire)
                await db.commit()
                await db.refresh(new_questionnaire)
                questionnaire_id = str(new_questionnaire.id)
                # Привязываем инспекцию к опросному листу (для отчётов и загрузки документов)
                new_inspection.questionnaire_id = new_questionnaire.id
                await db.commit()
                await db.refresh(new_inspection)
                _create_ndt_methods_from_mobile(
                    db, new_inspection, new_questionnaire, equipment_id, inspection_data_dict
                )
                await db.commit()
        
        # Создаем запись в истории обследований (версия 3.3.0)
        assignment_id = None
        if inspection_data.get("assignment_id"):
            try:
                assignment_id = uuid_lib.UUID(inspection_data.get("assignment_id"))
            except:
                pass
        
        # Определяем тип обследования
        inspection_type = "VISUAL"
        if inspection_data_dict:
            if inspection_data_dict.get("documents") or inspection_data_dict.get("vessel_name"):
                inspection_type = "QUESTIONNAIRE"
            elif inspection_data_dict.get("ndt_methods") or inspection_data_dict.get("method_code"):
                inspection_type = "NDT"
        
        # Получаем ID инженера из данных или из токена
        inspector_id = None
        if inspection_data_dict.get("inspector_id"):
            try:
                inspector_id = uuid_lib.UUID(inspection_data_dict.get("inspector_id"))
            except:
                pass
        
        # Создаем запись в истории
        history_entry = InspectionHistory(
            equipment_id=equipment_id,
            assignment_id=assignment_id,
            inspection_type=inspection_type,
            inspector_id=inspector_id,
            inspection_date=date_performed or datetime.now(),
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT")
        )
        db.add(history_entry)
        await db.commit()
        await db.refresh(history_entry)

        # Обновляем статус задания (чтобы у инженера отмечалось выполнено/не выполнено)
        if assignment_id:
            try:
                assignment_result = await db.execute(
                    select(Assignment).where(Assignment.id == assignment_id)
                )
                assignment = assignment_result.scalar_one_or_none()
                if assignment:
                    insp_status = (inspection_data.get("status") or "DRAFT").upper()
                    if insp_status == "SIGNED":
                        assignment.status = "COMPLETED"
                        assignment.completed_at = datetime.now()
                        # Обновляем equipment.attributes теххарактеристикой из обследования
                        try:
                            data_dict = inspection_data.get("data") or {}
                            if data_dict and isinstance(data_dict, dict):
                                await _update_equipment_attrs(db, equipment_id, data_dict)
                        except Exception:
                            pass
                    elif insp_status == "DRAFT":
                        # Черновик — это "в работе"
                        if assignment.status not in ["COMPLETED", "CANCELLED"]:
                            assignment.status = "IN_PROGRESS"
                    else:
                        # Прочие статусы не меняем, чтобы не ломать логику
                        pass
                    await db.commit()
            except Exception:
                # Не блокируем создание инспекции из-за статуса задания
                await db.rollback()
        
        return {
            "id": str(new_inspection.id),
            "equipment_id": str(new_inspection.equipment_id),
            "questionnaire_id": questionnaire_id,
            "history_id": str(history_entry.id),  # ID записи в истории (версия 3.3.0)
            "status": "created",
            "date_performed": new_inspection.date_performed.isoformat() if new_inspection.date_performed else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create inspection: {str(e)}")

# Clients endpoints
@app.get("/api/clients")
async def get_clients(
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get list of clients"""
    try:
        # Используем прямой SQL запрос, чтобы избежать проблем с отсутствующими колонками
        from sqlalchemy import text
        # Используем только базовые колонки, которые точно есть в БД
        query = text("""
            SELECT id, name, inn, address, contact_person
            FROM clients
            LIMIT :limit OFFSET :offset
        """)
        result = await db.execute(query, {"limit": limit, "offset": skip})
        clients = result.fetchall()
        items = []
        for row in clients:
            try:
                items.append({
                    "id": str(row[0]),  # id
                    "name": row[1] if row[1] else None,  # name
                    "inn": row[2] if row[2] else None,  # inn
                    "address": row[3] if row[3] else None,  # address
                    "contact_person": row[4] if row[4] else None,  # contact_person
                    "contact_phone": None,  # будет добавлено позже если нужно
                    "contact_email": None,  # будет добавлено позже если нужно
                })
            except Exception as e:
                # Если какое-то поле отсутствует, пропускаем его
                continue
        
        return {
            "items": items,
            "total": len(items)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/clients")
async def create_client(client_data: dict, db: AsyncSession = Depends(get_db)):
    """Create new client"""
    try:
        # Используем прямой SQL запрос, проверяя наличие колонок
        from sqlalchemy import text
        import uuid as uuid_lib
        
        # Проверяем какие колонки есть в таблице
        check_query = text("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'clients'
        """)
        result = await db.execute(check_query)
        columns = [row[0] for row in result.fetchall()]
        
        client_id = uuid_lib.uuid4()
        
        # Формируем список колонок и значений в зависимости от наличия колонок в БД
        insert_cols = ["id", "name", "created_at", "updated_at"]
        insert_vals = [":id", ":name", "NOW()", "NOW()"]
        params = {
            "id": client_id,
            "name": client_data.get("name"),
        }
        
        # Добавляем колонки только если они существуют
        if "inn" in columns:
            insert_cols.append("inn")
            insert_vals.append(":inn")
            params["inn"] = client_data.get("inn") or None
        
        if "address" in columns:
            insert_cols.append("address")
            insert_vals.append(":address")
            params["address"] = client_data.get("address") or None
        
        if "contact_person" in columns:
            insert_cols.append("contact_person")
            insert_vals.append(":contact_person")
            params["contact_person"] = client_data.get("contact_person") or None
        
        if "phone" in columns:
            insert_cols.append("phone")
            insert_vals.append(":phone")
            params["phone"] = client_data.get("contact_phone") or client_data.get("phone") or None
        
        if "email" in columns:
            insert_cols.append("email")
            insert_vals.append(":email")
            params["email"] = client_data.get("contact_email") or client_data.get("email") or None
        
        query = text(f"""
            INSERT INTO clients ({', '.join(insert_cols)})
            VALUES ({', '.join(insert_vals)})
            RETURNING id
        """)
        
        result = await db.execute(query, params)
        await db.commit()
        
        return {"id": str(client_id), "status": "created"}
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/inspections/{inspection_id}")
async def delete_inspection(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Удаление чек-листа (inspection).
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои (по inspector_id)
    При удалении также удаляются связанные отчеты (reports) и методы НК (ndt_methods) по inspection_id.
    """
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)

        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        # Права
        allowed = False
        if current_user.role in ["admin", "chief_operator", "operator"]:
            allowed = True
        elif current_user.role == "engineer":
            if inspection.inspector_id and inspection.inspector_id == current_user.id:
                allowed = True
        if not allowed:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Удаляем связанные отчеты и их файлы (сначала отчёты, иначе FK violation)
        rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
        related_reports = rep_result.scalars().all()
        for report in related_reports:
            for p in [report.file_path, getattr(report, "word_file_path", None)]:
                if p:
                    try:
                        fp = Path(p)
                        if fp.exists():
                            fp.unlink()
                    except Exception:
                        pass
            await db.delete(report)
        await db.flush()

        # Удаляем связанные методы НК (новая схема привязки к inspection_id)
        try:
            ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
            for m in ndt_result.scalars().all():
                await db.delete(m)
            await db.flush()
        except Exception:
            pass

        await db.delete(inspection)
        await db.commit()
        return {"status": "deleted", "id": inspection_id, "reports_deleted": len(related_reports)}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete inspection: {str(e)}")


@app.delete("/api/inspections/cleanup")
async def cleanup_inspections(
    older_than_days: int = 180,
    before: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Массовое удаление старых чек-листов (inspections) и связанных отчетов/методов НК.
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои
    """
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        cutoff = None
        if before:
            try:
                cutoff = datetime.fromisoformat(before.replace("Z", "+00:00"))
            except Exception:
                try:
                    cutoff = datetime.strptime(before, "%Y-%m-%d")
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid 'before' format")
        else:
            if older_than_days < 1:
                raise HTTPException(status_code=400, detail="older_than_days must be >= 1")
            cutoff = datetime.now() - timedelta(days=int(older_than_days))

        insp_query = select(Inspection).where(Inspection.created_at < cutoff)
        if current_user.role == "engineer":
            insp_query = insp_query.where(Inspection.inspector_id == current_user.id)
        elif current_user.role not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        insp_result = await db.execute(insp_query)
        inspections = insp_result.scalars().all()

        deleted = 0
        reports_deleted = 0
        for inspection in inspections:
            # связанные отчеты (сначала отчёты, иначе FK violation)
            rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
            related_reports = rep_result.scalars().all()
            for report in related_reports:
                for p in [report.file_path, getattr(report, "word_file_path", None)]:
                    if p:
                        try:
                            fp = Path(p)
                            if fp.exists():
                                fp.unlink()
                        except Exception:
                            pass
                await db.delete(report)
                reports_deleted += 1
            if related_reports:
                await db.flush()

            # методы НК
            try:
                ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
                for m in ndt_result.scalars().all():
                    await db.delete(m)
                await db.flush()
            except Exception:
                pass

            await db.delete(inspection)
            deleted += 1

        await db.commit()
        return {"status": "ok", "deleted": deleted, "reports_deleted": reports_deleted, "cutoff": cutoff.isoformat()}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to cleanup inspections: {str(e)}")

# Projects endpoints
@app.get("/api/projects")
async def get_projects(
    client_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get list of projects"""
    try:
        query = select(Project)
        if client_id:
            try:
                client_uuid = uuid_lib.UUID(client_id)
                query = query.where(Project.client_id == client_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid client_id format")
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        projects = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(p.id),
                    "client_id": str(p.client_id),
                    "name": p.name,
                    "description": p.description,
                    "status": p.status,
                    "start_date": str(p.start_date) if p.start_date else None,
                    "end_date": str(p.end_date) if p.end_date else None,
                    "deadline": str(p.deadline) if p.deadline else None,
                    "budget": float(p.budget) if p.budget else None,
                }
                for p in projects
            ],
            "total": len(projects)
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/projects")
async def create_project(project_data: dict, db: AsyncSession = Depends(get_db)):
    """Create new project"""
    try:
        client_id = None
        if project_data.get("client_id"):
            try:
                client_id = uuid_lib.UUID(project_data.get("client_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid client_id format")
        
        # Преобразуем deadline в end_date если deadline указан, иначе используем end_date
        deadline_date = None
        if project_data.get("deadline"):
            try:
                deadline_date = datetime.fromisoformat(project_data.get("deadline").replace('Z', '+00:00')).date()
            except:
                try:
                    deadline_date = datetime.fromisoformat(project_data.get("deadline")).date()
                except:
                    pass
        
        end_date_val = None
        if project_data.get("end_date"):
            try:
                end_date_val = datetime.fromisoformat(project_data.get("end_date").replace('Z', '+00:00')).date()
            except:
                try:
                    end_date_val = datetime.fromisoformat(project_data.get("end_date")).date()
                except:
                    pass
        
        new_project = Project(
            client_id=client_id,
            name=project_data.get("name"),
            description=project_data.get("description"),
            status=project_data.get("status", "PLANNED"),
            start_date=datetime.fromisoformat(project_data.get("start_date").replace('Z', '+00:00')).date() if project_data.get("start_date") else None,
            end_date=end_date_val,
            deadline=deadline_date,
            budget=float(project_data.get("budget")) if project_data.get("budget") else None
        )
        db.add(new_project)
        await db.commit()
        await db.refresh(new_project)
        return {"id": str(new_project.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Equipment Resource endpoints
@app.get("/api/equipment-resources")
async def get_equipment_resources(
    equipment_id: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Get equipment resources"""
    try:
        query = select(EquipmentResource)
        if equipment_id:
            try:
                eq_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(EquipmentResource.equipment_id == eq_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        result = await db.execute(query.order_by(EquipmentResource.created_at.desc()))
        resources = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(r.id),
                    "equipment_id": str(r.equipment_id),
                    "remaining_resource_years": float(r.remaining_resource_years) if r.remaining_resource_years else None,
                    "resource_end_date": str(r.resource_end_date) if r.resource_end_date else None,
                    "extension_years": float(r.extension_years) if r.extension_years else None,
                    "extension_date": str(r.extension_date) if r.extension_date else None,
                    "status": r.status,
                    "document_number": r.document_number,
                }
                for r in resources
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/equipment-resources")
async def create_equipment_resource(resource_data: dict, db: AsyncSession = Depends(get_db)):
    """Create equipment resource record"""
    try:
        equipment_id = None
        if resource_data.get("equipment_id"):
            try:
                equipment_id = uuid_lib.UUID(resource_data.get("equipment_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        new_resource = EquipmentResource(
            equipment_id=equipment_id,
            remaining_resource_years=resource_data.get("remaining_resource_years"),
            resource_end_date=datetime.fromisoformat(resource_data.get("resource_end_date")).date() if resource_data.get("resource_end_date") else None,
            extension_years=resource_data.get("extension_years"),
            extension_date=datetime.fromisoformat(resource_data.get("extension_date")).date() if resource_data.get("extension_date") else None,
            calculation_method=resource_data.get("calculation_method"),
            calculation_data=resource_data.get("calculation_data", {}),
            document_number=resource_data.get("document_number"),
            status=resource_data.get("status", "ACTIVE")
        )
        db.add(new_resource)
        await db.commit()
        await db.refresh(new_resource)
        return {"id": str(new_resource.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Regulatory Documents endpoints
@app.get("/api/regulatory-documents")
async def get_regulatory_documents(
    document_type: Optional[str] = None,
    equipment_type: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Get regulatory documents"""
    try:
        query = select(RegulatoryDocument).where(RegulatoryDocument.is_active == 1)
        if document_type:
            query = query.where(RegulatoryDocument.document_type == document_type)
        
        result = await db.execute(query)
        docs = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(d.id),
                    "document_type": d.document_type,
                    "number": d.number,
                    "name": d.name,
                    "description": d.description,
                    "equipment_types": d.equipment_types,
                    "effective_date": str(d.effective_date) if d.effective_date else None,
                    "expiry_date": str(d.expiry_date) if d.expiry_date else None,
                }
                for d in docs
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/regulatory-documents")
async def create_regulatory_document(doc_data: dict, db: AsyncSession = Depends(get_db)):
    """Create regulatory document"""
    try:
        new_doc = RegulatoryDocument(
            document_type=doc_data.get("document_type"),
            number=doc_data.get("number"),
            name=doc_data.get("name"),
            description=doc_data.get("description"),
            content=doc_data.get("content"),
            file_path=doc_data.get("file_path"),
            equipment_types=doc_data.get("equipment_types", []),
            requirements=doc_data.get("requirements", {}),
            effective_date=datetime.fromisoformat(doc_data.get("effective_date")).date() if doc_data.get("effective_date") else None,
            expiry_date=datetime.fromisoformat(doc_data.get("expiry_date")).date() if doc_data.get("expiry_date") else None,
        )
        db.add(new_doc)
        await db.commit()
        await db.refresh(new_doc)
        return {"id": str(new_doc.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Дубликат get_engineers удалён — используется реализация выше (с подтягиванием сертификатов и method_code)

@app.get("/api/users")
async def get_users(
    role: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список пользователей"""
    try:
        # Проверяем права доступа (только admin и chief_operator)
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        # Теперь is_active имеет тип INTEGER, можно использовать прямое сравнение
        query = select(User).where(User.is_active == 1)
        if role:
            query = query.where(User.role == role)
        
        result = await db.execute(query.order_by(User.username))
        users = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(u.id),
                    "username": u.username,
                    "email": u.email,
                    "full_name": u.full_name,
                    "role": u.role,
                    "engineer_id": str(u.engineer_id) if u.engineer_id else None,
                }
                for u in users
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get users: {str(e)}")

@app.post("/api/engineers")
async def create_engineer(engineer_data: dict, db: AsyncSession = Depends(get_db)):
    """Create engineer"""
    try:
        new_engineer = Engineer(
            full_name=engineer_data.get("full_name"),
            position=engineer_data.get("position"),
            email=engineer_data.get("email"),
            phone=engineer_data.get("phone"),
            qualifications=engineer_data.get("qualifications", []),
            equipment_types=engineer_data.get("equipment_types", []),
        )
        db.add(new_engineer)
        await db.commit()
        await db.refresh(new_engineer)
        
        # Если есть сертификаты, создаем их отдельно
        certifications_data = engineer_data.get("certifications", [])
        if certifications_data:
            from models import Certification
            for cert_data in certifications_data:
                cert = Certification(
                    engineer_id=new_engineer.id,
                    certification_type=cert_data.get("certification_type"),
                    method=cert_data.get("method"),
                    level=cert_data.get("level"),
                    number=cert_data.get("number"),
                    issued_by=cert_data.get("issued_by"),
                    issue_date=cert_data.get("issue_date"),
                    expiry_date=cert_data.get("expiry_date"),
                    is_active=1
                )
                db.add(cert)
            await db.commit()
        
        _cache_invalidate("engineers")
        return {"id": str(new_engineer.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Certifications endpoints
@app.get("/api/certifications")
async def get_certifications(
    engineer_id: Optional[str] = None,
    method_code: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get certifications (method_code — фильтр по виду НК для мобильной синхронизации)"""
    try:
        query = select(Certification).where(Certification.is_active == 1)
        if engineer_id:
            try:
                eng_uuid = uuid_lib.UUID(engineer_id)
                query = query.where(Certification.engineer_id == eng_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid engineer_id format")
        if method_code:
            query = query.where(Certification.method_code == method_code)
        
        result = await db.execute(query)
        certs = result.scalars().all()
        items = []
        for c in certs:
            try:
                items.append({
                    "id": str(c.id),
                    "engineer_id": str(c.engineer_id) if c.engineer_id else None,
                    "certification_type": c.certification_type or "",
                    "certificate_number": c.certificate_number or "",
                    "number": c.certificate_number or "",  # Для обратной совместимости
                    "issued_by": c.issuing_organization or "",
                    "issuing_organization": c.issuing_organization or "",
                    "issue_date": str(c.issue_date) if c.issue_date else None,
                    "expiry_date": str(c.expiry_date) if c.expiry_date else None,
                    "document_number": c.document_number or None,
                    "document_date": str(c.document_date) if c.document_date else None,
                    "method_code": c.method_code or None,
                    "certification_areas": _cert_areas_list(c),
                    "certification_area": (_cert_areas_list(c)[0] if _cert_areas_list(c) else None),
                    "equipment_type_id": str(c.equipment_type_id) if c.equipment_type_id else None,
                    "scan_file_name": getattr(c, "scan_file_name", None),
                    "scan_file_size": getattr(c, "scan_file_size", None),
                    "scan_mime_type": getattr(c, "scan_mime_type", None),
                })
            except Exception as item_error:
                import traceback
                print(f"Error processing certification {c.id if c else 'unknown'}: {item_error}")
                traceback.print_exc()
                continue
        
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/certifications")
async def create_certification(
    certification_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать сертификат"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        engineer_id = uuid_lib.UUID(certification_data.get("engineer_id"))
        
        method_code = certification_data.get("method_code") or None
        equipment_type_id = None
        if certification_data.get("equipment_type_id"):
            try:
                equipment_type_id = uuid_lib.UUID(certification_data.get("equipment_type_id"))
            except:
                pass
        areas_raw = certification_data.get("certification_areas")
        if not isinstance(areas_raw, list):
            areas_raw = [certification_data.get("certification_area")] if certification_data.get("certification_area") else []
        cert_areas = [str(a).strip() for a in areas_raw if a]
        
        certification = Certification(
            engineer_id=engineer_id,
            certification_type=certification_data.get("certification_type"),
            certificate_number=certification_data.get("certificate_number"),
            method_code=method_code,
            certification_areas=cert_areas if cert_areas else None,
            certification_area=cert_areas[0] if cert_areas else None,
            equipment_type_id=equipment_type_id,
            issue_date=datetime.strptime(certification_data.get("issue_date"), "%Y-%m-%d").date() if certification_data.get("issue_date") else None,
            expiry_date=datetime.strptime(certification_data.get("expiry_date"), "%Y-%m-%d").date() if certification_data.get("expiry_date") else None,
            issuing_organization=certification_data.get("issuing_organization"),
            document_number=certification_data.get("document_number"),
            document_date=datetime.strptime(certification_data.get("document_date"), "%Y-%m-%d").date() if certification_data.get("document_date") else None,
            is_active=1
        )
        
        db.add(certification)
        await db.commit()
        await db.refresh(certification)
        
        return {
            "id": str(certification.id),
            "engineer_id": str(certification.engineer_id),
            "certification_type": certification.certification_type,
            "certificate_number": certification.certificate_number,
            "method_code": certification.method_code,
            "certification_areas": getattr(certification, "certification_areas", None) or _cert_areas_list(certification),
            "certification_area": (getattr(certification, "certification_areas", None) or [])[0] if (getattr(certification, "certification_areas", None) or []) else getattr(certification, "certification_area", None),
            "equipment_type_id": str(certification.equipment_type_id) if certification.equipment_type_id else None,
            "issue_date": str(certification.issue_date) if certification.issue_date else None,
            "expiry_date": str(certification.expiry_date) if certification.expiry_date else None,
            "issuing_organization": certification.issuing_organization,
            "document_number": certification.document_number,
            "document_date": str(certification.document_date) if certification.document_date else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid date format: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create certification: {str(e)}")

@app.put("/api/certifications/{certification_id}")
async def update_certification(
    certification_id: str,
    certification_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Обновить сертификат"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(
            select(Certification).where(Certification.id == cert_uuid)
        )
        certification = result.scalar_one_or_none()
        
        if not certification:
            raise HTTPException(status_code=404, detail="Сертификат не найден")
        
        if "certification_type" in certification_data:
            certification.certification_type = certification_data["certification_type"]
        if "certificate_number" in certification_data:
            certification.certificate_number = certification_data["certificate_number"]
        if "issue_date" in certification_data:
            certification.issue_date = datetime.strptime(certification_data["issue_date"], "%Y-%m-%d").date() if certification_data["issue_date"] else None
        if "expiry_date" in certification_data:
            certification.expiry_date = datetime.strptime(certification_data["expiry_date"], "%Y-%m-%d").date() if certification_data["expiry_date"] else None
        if "issuing_organization" in certification_data:
            certification.issuing_organization = certification_data["issuing_organization"]
        if "document_number" in certification_data:
            certification.document_number = certification_data["document_number"]
        if "document_date" in certification_data:
            certification.document_date = datetime.strptime(certification_data["document_date"], "%Y-%m-%d").date() if certification_data["document_date"] else None
        if "method_code" in certification_data:
            certification.method_code = certification_data["method_code"] or None
        if "certification_areas" in certification_data:
            areas_raw = certification_data.get("certification_areas")
            cert_areas = [str(a).strip() for a in (areas_raw if isinstance(areas_raw, list) else []) if a]
            certification.certification_areas = cert_areas if cert_areas else None
            certification.certification_area = cert_areas[0] if cert_areas else None
        elif "certification_area" in certification_data:
            single = (certification_data.get("certification_area") or "").strip() or None
            certification.certification_area = single
            certification.certification_areas = [single] if single else None
        if "equipment_type_id" in certification_data:
            if certification_data["equipment_type_id"]:
                try:
                    certification.equipment_type_id = uuid_lib.UUID(certification_data["equipment_type_id"])
                except:
                    certification.equipment_type_id = None
            else:
                certification.equipment_type_id = None
        
        await db.commit()
        await db.refresh(certification)
        
        return {
            "id": str(certification.id),
            "engineer_id": str(certification.engineer_id),
            "certification_type": certification.certification_type,
            "certificate_number": certification.certificate_number,
            "method_code": certification.method_code,
            "certification_areas": getattr(certification, "certification_areas", None) or _cert_areas_list(certification),
            "certification_area": (_cert_areas_list(certification)[0] if _cert_areas_list(certification) else None),
            "equipment_type_id": str(certification.equipment_type_id) if certification.equipment_type_id else None,
            "issue_date": str(certification.issue_date) if certification.issue_date else None,
            "expiry_date": str(certification.expiry_date) if certification.expiry_date else None,
            "issuing_organization": certification.issuing_organization,
            "document_number": certification.document_number,
            "document_date": str(certification.document_date) if certification.document_date else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid date format: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update certification: {str(e)}")

@app.delete("/api/certifications/{certification_id}")
async def delete_certification(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить сертификат (мягкое удаление)"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(
            select(Certification).where(Certification.id == cert_uuid)
        )
        certification = result.scalar_one_or_none()
        
        if not certification:
            raise HTTPException(status_code=404, detail="Сертификат не найден")
        
        certification.is_active = 0
        await db.commit()
        
        return {"message": "Сертификат успешно удален"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete certification: {str(e)}")


@app.post("/api/certifications/{certification_id}/scan")
async def upload_certification_scan(
    certification_id: str,
    file: UploadFile = File(...),
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить скан сертификата (фото/PDF)"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        allowed = {
            "application/pdf",
            "image/jpeg",
            "image/png",
            "image/webp",
        }
        if file.content_type and file.content_type not in allowed:
            raise HTTPException(status_code=400, detail="Разрешены только фото (JPEG/PNG/WEBP) или PDF")

        uploads_dir = Path("/app/uploads/certification_scans") / str(cert.id)
        uploads_dir.mkdir(parents=True, exist_ok=True)

        safe_name = (file.filename or "scan").replace("\\", "_").replace("/", "_")
        stored_name = f"{uuid_lib.uuid4()}_{safe_name}"
        stored_path = uploads_dir / stored_name

        # Удаляем старый файл, если был
        old_path = getattr(cert, "scan_file_path", None)
        if old_path:
            try:
                old_p = Path(old_path)
                if old_p.exists():
                    old_p.unlink()
            except Exception:
                pass

        size = 0
        with stored_path.open("wb") as f:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                f.write(chunk)

        cert.scan_file_path = str(stored_path)
        cert.scan_file_name = file.filename
        cert.scan_file_size = size
        cert.scan_mime_type = file.content_type

        await db.commit()
        await db.refresh(cert)

        return {
            "id": str(cert.id),
            "scan_file_name": cert.scan_file_name,
            "scan_file_size": cert.scan_file_size,
            "scan_mime_type": cert.scan_mime_type,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to upload scan: {str(e)}")


@app.get("/api/certifications/{certification_id}/scan")
async def download_certification_scan(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Скачать скан сертификата"""
    try:
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        scan_path = getattr(cert, "scan_file_path", None)
        if not scan_path or not Path(scan_path).exists():
            raise HTTPException(status_code=404, detail="Скан не найден")

        return FileResponse(
            path=scan_path,
            filename=(getattr(cert, "scan_file_name", None) or "certificate-scan"),
            media_type=(getattr(cert, "scan_mime_type", None) or "application/octet-stream"),
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to download scan: {str(e)}")


@app.delete("/api/certifications/{certification_id}/scan")
async def delete_certification_scan(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить скан сертификата"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        scan_path = getattr(cert, "scan_file_path", None)
        if scan_path:
            try:
                p = Path(scan_path)
                if p.exists():
                    p.unlink()
            except Exception:
                pass

        cert.scan_file_path = None
        cert.scan_file_name = None
        cert.scan_file_size = None
        cert.scan_mime_type = None
        await db.commit()

        return {"message": "Скан удален"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete scan: {str(e)}")

# Reports endpoints
@app.get("/api/reports")
async def get_reports(
    inspection_id: Optional[str] = None,
    equipment_id: Optional[str] = None,
    project_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get reports (с учетом прав: инженер видит только свои отчеты)"""
    try:
        # Текущий пользователь и роль
        # Совместимость: username в токене может быть email (старые токены / ввод email)
        user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        query = select(Report)
        # Временно НЕ фильтруем по is_archived, чтобы показать все отчеты
        # Фильтрация будет добавлена позже, когда будет уверенность, что поле корректно работает
        # query = query.where(Report.is_archived == False)
        if inspection_id:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                query = query.where(Report.inspection_id == insp_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid inspection_id format")
        # Фильтрация по equipment_id и project_id через связанные инспекции
        if equipment_id:
            try:
                eq_uuid = uuid_lib.UUID(equipment_id)
                # Фильтруем через связанные инспекции
                insp_subquery = select(Inspection.id).where(Inspection.equipment_id == eq_uuid)
                query = query.where(Report.inspection_id.in_(insp_subquery))
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        if project_id:
            try:
                proj_uuid = uuid_lib.UUID(project_id)
                # Фильтруем через связанные инспекции
                insp_subquery = select(Inspection.id).where(Inspection.project_id == proj_uuid)
                query = query.where(Report.inspection_id.in_(insp_subquery))
            except:
                raise HTTPException(status_code=400, detail="Invalid project_id format")

        # Ограничиваем инженера только своими отчетами.
        # created_by хранится как UUID (users.id). Фолбэк для старых записей: если created_by пустой,
        # пытаемся определить по inspection.inspector_id.
        if current_user.role == "engineer":
            query = (
                query.join(Inspection, Report.inspection_id == Inspection.id, isouter=True)
                .where(
                    or_(
                        Report.created_by == current_user.id,
                        and_(Report.created_by.is_(None), Inspection.inspector_id == current_user.id),
                    )
                )
            )
        
        result = await db.execute(query.order_by(Report.created_at.desc()))
        reports = result.scalars().all()
        
        # Получаем информацию об инженерах из связанных инспекций
        report_items = []
        for r in reports:
            inspector_name = None
            inspector_position = None
            equipment_id = None
            project_id = None
            inspection = None
            enterprise_id = None
            enterprise_name = None
            branch_id = None
            branch_name = None
            workshop_id = None
            workshop_name = None
            equipment_name = None
            
            # Пытаемся получить ФИО инженера из связанной инспекции
            if r.inspection_id:
                insp_result = await db.execute(
                    select(Inspection).where(Inspection.id == r.inspection_id)
                )
                inspection = insp_result.scalar_one_or_none()
                if inspection:
                    # Получаем equipment_id и project_id из инспекции
                    equipment_id = str(inspection.equipment_id) if inspection.equipment_id else None
                    project_id = str(inspection.project_id) if inspection.project_id else None
                    
                    # Получаем информацию об оборудовании и иерархии
                    if inspection.equipment_id:
                        eq_result = await db.execute(
                            select(Equipment).where(Equipment.id == inspection.equipment_id)
                        )
                        equipment = eq_result.scalar_one_or_none()
                        if equipment:
                            equipment_name = equipment.name
                            
                            # Получаем информацию о цехе, филиале и предприятии
                            if equipment.workshop_id:
                                try:
                                    workshop_result = await db.execute(
                                        select(Workshop).where(Workshop.id == equipment.workshop_id)
                                    )
                                    workshop = workshop_result.scalar_one_or_none()
                                    if workshop:
                                        workshop_id = str(workshop.id)
                                        workshop_name = workshop.name
                                        
                                        # Получаем филиал
                                        try:
                                            branch_result = await db.execute(
                                                select(Branch).where(Branch.id == workshop.branch_id)
                                            )
                                            branch = branch_result.scalar_one_or_none()
                                            if branch:
                                                branch_id = str(branch.id)
                                                branch_name = branch.name
                                                
                                                # Получаем предприятие
                                                try:
                                                    enterprise_result = await db.execute(
                                                        select(Enterprise).where(Enterprise.id == branch.enterprise_id)
                                                    )
                                                    enterprise = enterprise_result.scalar_one_or_none()
                                                    if enterprise:
                                                        enterprise_id = str(enterprise.id)
                                                        enterprise_name = enterprise.name
                                                except Exception as e:
                                                    await db.rollback()
                                                    print(f"⚠️ Error loading enterprise for report {r.id}: {e}")
                                        except Exception as e:
                                            await db.rollback()
                                            print(f"⚠️ Error loading branch for report {r.id}: {e}")
                                except Exception as e:
                                    await db.rollback()
                                    print(f"⚠️ Error loading workshop for report {r.id}: {e}")
                    
                    if inspection.inspector_id:
                        # Получаем информацию об инженере из users
                        user_result = await db.execute(
                            select(User).where(User.id == inspection.inspector_id)
                        )
                        user = user_result.scalar_one_or_none()
                        if user:
                            inspector_name = user.full_name or user.username
                            # Пытаемся получить должность из связанного engineer
                            if user.engineer_id:
                                eng_result = await db.execute(
                                    select(Engineer).where(Engineer.id == user.engineer_id)
                                )
                                engineer = eng_result.scalar_one_or_none()
                                if engineer:
                                    inspector_position = engineer.position
            
            report_items.append({
                "id": str(r.id),
                "inspection_id": str(r.inspection_id) if r.inspection_id else None,
                "equipment_id": equipment_id,
                "equipment_name": equipment_name,
                "project_id": project_id,
                "enterprise_id": enterprise_id,
                "enterprise_name": enterprise_name,
                "branch_id": branch_id,
                "branch_name": branch_name,
                "workshop_id": workshop_id,
                "workshop_name": workshop_name,
                "report_type": r.report_type,
                "title": f"{r.report_type} Report" if r.report_type else "Report",
                "file_path": r.file_path,
                "file_size": r.file_size,
                # Статус отчета берём из статуса инспекции, если она есть (DRAFT/SIGNED/APPROVED).
                # Фолбэк: если инспекции нет, считаем что файл -> GENERATED иначе DRAFT.
                "status": (inspection.status if inspection and getattr(inspection, "status", None) else ("GENERATED" if r.file_path else "DRAFT")),
                "inspector_name": inspector_name,
                "inspector_position": inspector_position,
                "created_by": str(r.created_by) if r.created_by else None,
                "is_archived": getattr(r, "is_archived", False),
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "word_file_path": getattr(r, "word_file_path", None),
                "word_file_size": getattr(r, "word_file_size", None),
            })
        
        return {
            "items": report_items
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_reports: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении отчетов: {error_detail}")

@app.get("/api/inspections/{inspection_id}/preview")
async def get_inspection_preview(inspection_id: str, db: AsyncSession = Depends(get_db)):
    """Получить данные инспекции для предпросмотра перед генерацией отчета"""
    try:
        inspection_uuid = uuid_lib.UUID(inspection_id)
        
        # Получаем данные инспекции
        result = await db.execute(
            select(Inspection).where(Inspection.id == inspection_uuid)
        )
        inspection = result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")
        
        # Получаем данные оборудования
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == inspection.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")

        # Данные ОПО (если оборудование привязано к ОПО)
        opo_info = None
        try:
            opo = None
            if getattr(equipment, "opo_id", None):
                opo_result = await db.execute(select(Opo).where(Opo.id == equipment.opo_id))
                opo = opo_result.scalar_one_or_none()
            if opo:
                workshop = None
                branch = None
                enterprise = None
                if getattr(opo, "workshop_id", None):
                    w_result = await db.execute(select(Workshop).where(Workshop.id == opo.workshop_id))
                    workshop = w_result.scalar_one_or_none()
                if workshop and getattr(workshop, "branch_id", None):
                    b_result = await db.execute(select(Branch).where(Branch.id == workshop.branch_id))
                    branch = b_result.scalar_one_or_none()
                if branch and getattr(branch, "enterprise_id", None):
                    e_result = await db.execute(select(Enterprise).where(Enterprise.id == branch.enterprise_id))
                    enterprise = e_result.scalar_one_or_none()

                opo_info = {
                    "id": str(opo.id),
                    "name": opo.name,
                    "code": opo.code,
                    "description": opo.description,
                    "survey_data": opo.survey_data or {},
                    "workshop_id": str(opo.workshop_id) if opo.workshop_id else None,
                    "workshop_name": workshop.name if workshop else None,
                    "branch_id": str(branch.id) if branch else None,
                    "branch_name": branch.name if branch else None,
                    "enterprise_id": str(enterprise.id) if enterprise else None,
                    "enterprise_name": enterprise.name if enterprise else None,
                }
        except Exception as e:
            print(f"Warning: Could not load OPO info for preview: {e}")
            opo_info = None

        # Questionnaire: приоритет — questionnaire_id инспекции, иначе последний по оборудованию
        questionnaire = None
        if getattr(inspection, "questionnaire_id", None):
            q_by_inspection = await db.execute(
                select(Questionnaire)
                .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                .where(Questionnaire.id == inspection.questionnaire_id)
            )
            questionnaire = q_by_inspection.scalar_one_or_none()
        if not questionnaire:
            questionnaire_result = await db.execute(
                select(Questionnaire)
                .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                .where(Questionnaire.equipment_id == equipment.id)
                .order_by(Questionnaire.created_at.desc()).limit(1)
            )
            questionnaire = questionnaire_result.scalar_one_or_none()

        # Методы НК: по inspection_id, затем по questionnaire (привязанному к инспекции)
        ndt_methods = []
        try:
            ndt_result = await db.execute(
                select(NDTMethod).where(NDTMethod.inspection_id == inspection.id)
            )
            ndt_methods = ndt_result.scalars().all()
        except Exception:
            ndt_methods = []
        if not ndt_methods and questionnaire:
            ndt_result = await db.execute(
                select(NDTMethod).where(NDTMethod.questionnaire_id == questionnaire.id)
            )
            ndt_methods = ndt_result.scalars().all()

        # Файлы документов/вложений (при наличии questionnaire_id у инспекции — берём его)
        document_files = []
        try:
            q_for_files = questionnaire
            if not q_for_files and getattr(inspection, "questionnaire_id", None):
                q_by_id = await db.execute(
                    select(Questionnaire)
                    .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                    .where(Questionnaire.id == inspection.questionnaire_id)
                )
                q_for_files = q_by_id.scalar_one_or_none()
            if not q_for_files:
                q_query = (
                    select(Questionnaire)
                    .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                    .where(Questionnaire.equipment_id == equipment.id)
                )
                if getattr(inspection, "created_at", None):
                    q_query = q_query.order_by(
                        func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
                    ).limit(1)
                else:
                    q_query = q_query.order_by(Questionnaire.created_at.desc()).limit(1)
                q_result = await db.execute(q_query)
                q_for_files = q_result.scalar_one_or_none()
            if q_for_files:
                questionnaire = q_for_files
                files_result = await db.execute(
                    select(QuestionnaireDocumentFile).where(
                        QuestionnaireDocumentFile.questionnaire_id == q_for_files.id
                    )
                )
                files = files_result.scalars().all()
                qid = str(q_for_files.id)
                document_files = [
                    {
                        "document_number": f.document_number,
                        "file_name": f.file_name,
                        "file_size": int(f.file_size or 0),
                        "file_type": f.file_type,
                        "mime_type": f.mime_type,
                        "view_url": f"/api/questionnaires/{qid}/documents/{f.document_number}/view",
                    }
                    for f in files
                ]
        except Exception:
            document_files = []
        
        # Получаем данные ресурса, если есть
        resource_data = None
        res_result = await db.execute(
            select(EquipmentResource).where(EquipmentResource.equipment_id == equipment.id)
            .order_by(EquipmentResource.created_at.desc()).limit(1)
        )
        resource = res_result.scalar_one_or_none()
        if resource:
            # Используем поля, которые есть в модели EquipmentResource
            resource_data = {
                "resource_type": resource.resource_type,
                "current_value": float(resource.current_value) if resource.current_value else None,
                "limit_value": float(resource.limit_value) if resource.limit_value else None,
                "unit": resource.unit,
                "last_updated": resource.last_updated.isoformat() if resource.last_updated else None,
            }
        
        return {
            "inspection": {
                "id": str(inspection.id),
                "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                "status": inspection.status,
                "conclusion": inspection.conclusion,
                "data": inspection.data,
            },
            "equipment": {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
                "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                "attributes": equipment.attributes or {},
            },
            "questionnaire": {
                "id": str(questionnaire.id) if questionnaire else None,
            },
            "document_files": document_files,
            "opo": opo_info,
            "ndt_methods": [
                {
                    "id": str(m.id),
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": m.photos or [],
                    "additional_data": m.additional_data or {},
                }
                for m in ndt_methods
            ],
            "resource": resource_data,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to get preview: {str(e)}")


@app.get("/api/inspections/{inspection_id}/questionnaire")
async def get_inspection_questionnaire_info(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """
    Получить привязанный к инспекции опросный лист (questionnaire_id) и файлы документов.
    Нужен для корректного отображения названий и вложений документов в веб-интерфейсе.
    """
    try:
        inspection_uuid = uuid_lib.UUID(inspection_id)

        ins_result = await db.execute(select(Inspection).where(Inspection.id == inspection_uuid))
        inspection = ins_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        # Ищем наиболее подходящий questionnaire (load_only — без assignment_id)
        q_query = (
            select(Questionnaire)
            .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
            .where(Questionnaire.equipment_id == inspection.equipment_id)
        )
        if getattr(inspection, "created_at", None):
            q_query = q_query.order_by(
                func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
            ).limit(1)
        else:
            q_query = q_query.order_by(Questionnaire.created_at.desc()).limit(1)

        q_result = await db.execute(q_query)
        questionnaire = q_result.scalar_one_or_none()

        if not questionnaire:
            return {"questionnaire_id": None, "document_files": []}

        files_result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == questionnaire.id
            )
        )
        files = files_result.scalars().all()

        qid = str(questionnaire.id)
        return {
            "questionnaire_id": qid,
            "document_files": [
                {
                    "id": str(f.id),
                    "document_number": f.document_number,
                    "file_name": f.file_name,
                    "file_size": int(f.file_size or 0),
                    "file_type": f.file_type,
                    "mime_type": f.mime_type,
                    "created_at": f.created_at.isoformat() if f.created_at else None,
                    "view_url": f"/api/questionnaires/{qid}/documents/{f.document_number}/view",
                }
                for f in files
            ],
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Failed to get inspection questionnaire info: {str(e)}")


@app.get("/api/reports/validate/{inspection_id}")
async def validate_report_inspection(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Проверка полноты данных обследования перед генерацией отчёта"""
    try:
        from report_utils import validate_inspection_completeness
        result = await validate_inspection_completeness(db, inspection_id)
        return result
    except Exception as e:
        return {
            "is_complete": False,
            "missing_fields": [f"Ошибка проверки: {str(e)}"],
            "warnings": [],
            "can_generate": False
        }


@app.post("/api/reports/generate")
async def generate_report(
    report_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Generate technical report or expertise"""
    try:
        # Текущий пользователь
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        inspection_id = None
        if report_data.get("inspection_id"):
            try:
                inspection_id = uuid_lib.UUID(report_data.get("inspection_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid inspection_id format")
        
        # Get inspection data
        if inspection_id:
            result = await db.execute(
                select(Inspection).where(Inspection.id == inspection_id)
            )
            inspection = result.scalar_one_or_none()
            if not inspection:
                raise HTTPException(status_code=404, detail="Inspection not found")
            # Роли и права на отчёты: инженер — только по своим обследованиям
            if getattr(current_user, "role", None) == "engineer":
                own = (
                    (getattr(inspection, "inspector_id", None) == current_user.id)
                    or (getattr(inspection, "performed_by", None) == current_user.id)
                    or (getattr(inspection, "created_by", None) == current_user.id)
                )
                if not own:
                    raise HTTPException(status_code=403, detail="Нет прав на генерацию отчёта по этому обследованию")
            
            # Get equipment data
            eq_result = await db.execute(
                select(Equipment).where(Equipment.id == inspection.equipment_id)
            )
            equipment = eq_result.scalar_one_or_none()
            if not equipment:
                raise HTTPException(status_code=404, detail="Equipment not found")
            
            # Get equipment type information
            equipment_type_code = None
            equipment_type_name = None
            if equipment.type_id:
                type_result = await db.execute(
                    select(EquipmentType).where(EquipmentType.id == equipment.type_id)
                )
                equipment_type = type_result.scalar_one_or_none()
                if equipment_type:
                    equipment_type_code = equipment_type.code
                    equipment_type_name = equipment_type.name

            # Данные ОПО для отчета (если оборудование привязано к ОПО)
            opo_info = None
            try:
                opo = None
                if getattr(equipment, "opo_id", None):
                    opo_result = await db.execute(select(Opo).where(Opo.id == equipment.opo_id))
                    opo = opo_result.scalar_one_or_none()
                if opo:
                    workshop = None
                    branch = None
                    enterprise = None
                    if getattr(opo, "workshop_id", None):
                        w_result = await db.execute(select(Workshop).where(Workshop.id == opo.workshop_id))
                        workshop = w_result.scalar_one_or_none()
                    if workshop and getattr(workshop, "branch_id", None):
                        b_result = await db.execute(select(Branch).where(Branch.id == workshop.branch_id))
                        branch = b_result.scalar_one_or_none()
                    if branch and getattr(branch, "enterprise_id", None):
                        e_result = await db.execute(select(Enterprise).where(Enterprise.id == branch.enterprise_id))
                        enterprise = e_result.scalar_one_or_none()

                    opo_info = {
                        "id": str(opo.id),
                        "name": opo.name,
                        "code": opo.code,
                        "description": opo.description,
                        "survey_data": opo.survey_data or {},
                        "workshop_id": str(opo.workshop_id) if opo.workshop_id else None,
                        "workshop_name": workshop.name if workshop else None,
                        "branch_id": str(branch.id) if branch else None,
                        "branch_name": branch.name if branch else None,
                        "enterprise_id": str(enterprise.id) if enterprise else None,
                        "enterprise_name": enterprise.name if enterprise else None,
                    }
            except Exception as e:
                print(f"Warning: Could not load OPO info: {e}")
                opo_info = None
            
            # Get resource data if expertise
            resource_data = None
            if report_data.get("report_type") == "EXPERTISE":
                res_result = await db.execute(
                    select(EquipmentResource).where(EquipmentResource.equipment_id == equipment.id)
                    .order_by(EquipmentResource.created_at.desc()).limit(1)
                )
                resource = res_result.scalar_one_or_none()
                if resource:
                    # Используем поля, которые есть в модели EquipmentResource
                    resource_data = {
                        "resource_type": resource.resource_type,
                        "current_value": float(resource.current_value) if resource.current_value else None,
                        "limit_value": float(resource.limit_value) if resource.limit_value else None,
                        "unit": resource.unit,
                        "last_updated": resource.last_updated.isoformat() if resource.last_updated else None,
                    }
            
            # Методы НК:
            # 1) Сначала пытаемся взять методы, привязанные напрямую к inspection_id (3.3.0+)
            # 2) Фолбэк: методы, привязанные к последнему questionnaire по этому оборудованию (историческая логика)
            ndt_methods = []
            try:
                ndt_result = await db.execute(
                    select(NDTMethod).where(NDTMethod.inspection_id == inspection.id)
                )
                ndt_methods = ndt_result.scalars().all()
            except Exception:
                ndt_methods = []

            if not ndt_methods:
                questionnaire_result = await db.execute(
                    select(Questionnaire)
                    .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                    .where(Questionnaire.equipment_id == equipment.id)
                    .order_by(Questionnaire.created_at.desc()).limit(1)
                )
                questionnaire = questionnaire_result.scalar_one_or_none()

                if questionnaire:
                    ndt_result = await db.execute(
                        select(NDTMethod).where(NDTMethod.questionnaire_id == questionnaire.id)
                    )
                    ndt_methods = ndt_result.scalars().all()

            # Вложения чек-листа (фото таблички/схема контроля/сканы документов) — привязаны к Questionnaire
            document_files = []
            try:
                q_for_files = None
                # Сначала берём questionnaire, привязанный к этой инспекции (если есть)
                if getattr(inspection, "questionnaire_id", None):
                    q_by_id = await db.execute(
                        select(Questionnaire)
                        .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                        .where(Questionnaire.id == inspection.questionnaire_id)
                    )
                    q_for_files = q_by_id.scalar_one_or_none()
                if not q_for_files:
                    q_query = (
                        select(Questionnaire)
                        .options(load_only(Questionnaire.id, Questionnaire.equipment_id, Questionnaire.created_at))
                        .where(Questionnaire.equipment_id == equipment.id)
                    )
                    if getattr(inspection, "created_at", None):
                        q_query = q_query.order_by(
                            func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
                        ).limit(1)
                    else:
                        q_query = q_query.order_by(Questionnaire.created_at.desc()).limit(1)
                    q_result = await db.execute(q_query)
                    q_for_files = q_result.scalar_one_or_none()
                if q_for_files:
                    files_result = await db.execute(
                        select(QuestionnaireDocumentFile).where(
                            QuestionnaireDocumentFile.questionnaire_id == q_for_files.id
                        )
                    )
                    files = files_result.scalars().all()
                    document_files = [
                        {
                            "document_number": f.document_number,
                            "file_name": f.file_name,
                            "file_path": _resolve_report_file_path(f.file_path) or f.file_path,
                            "file_size": int(f.file_size or 0),
                            "file_type": f.file_type,
                            "mime_type": f.mime_type,
                        }
                        for f in files
                    ]
            except Exception:
                document_files = []
            # Дополняем из inspection.data (пути после синхронизации с мобильного)
            _existing_dn = {str(f.get("document_number")) for f in document_files if f.get("document_number")}
            _data = inspection.data if isinstance(getattr(inspection, "data", None), dict) else {}
            for _key in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
                if _key not in _existing_dn and _data.get(_key):
                    _p = (_data.get(_key) or "").strip()
                    if _p:
                        document_files.append({"document_number": _key, "file_name": os.path.basename(_p), "file_path": _resolve_report_file_path(_p) or _p})
                        _existing_dn.add(_key)
            _vd = _data.get("visual_defects")
            if isinstance(_vd, list):
                for _i, _d in enumerate(_vd):
                    if not isinstance(_d, dict):
                        continue
                    for _j, _ph in enumerate(_d.get("photos") or []):
                        if isinstance(_ph, str) and _ph.strip() and f"vd_{_i}_{_j}" not in _existing_dn:
                            document_files.append({"document_number": f"vd_{_i}_{_j}", "file_name": os.path.basename(_ph), "file_path": _resolve_report_file_path(_ph) or _ph})
                            _existing_dn.add(f"vd_{_i}_{_j}")
            _thickness = _data.get("thickness_measurements") or _data.get("thicknessMeasurements")
            if isinstance(_thickness, list):
                for _i, _t in enumerate(_thickness):
                    if not isinstance(_t, dict):
                        continue
                    for _j, _ph in enumerate(_t.get("photos") or []):
                        if isinstance(_ph, str) and _ph.strip() and f"uzt_point_{_i}_{_j}" not in _existing_dn:
                            document_files.append({"document_number": f"uzt_point_{_i}_{_j}", "file_name": os.path.basename(_ph), "file_path": _resolve_report_file_path(_ph) or _ph})
                            _existing_dn.add(f"uzt_point_{_i}_{_j}")

            # Проверка целостности вложений: логируем отсутствующие файлы
            _missing_att = []
            for _f in (document_files or []):
                if not isinstance(_f, dict):
                    continue
                _fp = _f.get("file_path")
                if isinstance(_fp, str) and _fp.strip():
                    _p = Path(_fp)
                    _candidate = _p if _p.is_absolute() and _p.exists() else None
                    if not _candidate:
                        for _base in ["/app/uploads/questionnaire_documents", "/app/uploads", "/app/reports"]:
                            _cand = Path(_base) / _fp
                            if _cand.exists():
                                _candidate = _cand
                                break
                    if not _candidate or not _candidate.exists():
                        _missing_att.append(_f.get("document_number") or _f.get("file_name") or _fp)
            if _missing_att:
                print(f"Report generation: missing attachment files (inspection_id={inspection.id}): {_missing_att}")

            # Получаем используемое оборудование для поверок
            verification_equipment_list = []
            try:
                # Ищем по inspection_id
                inspection_eq_result = await db.execute(
                    select(InspectionEquipment).where(InspectionEquipment.inspection_id == inspection.id)
                )
                inspection_equipment = inspection_eq_result.scalars().all()
                
                for ie in inspection_equipment:
                    ver_eq_result = await db.execute(
                        select(VerificationEquipment).where(VerificationEquipment.id == ie.verification_equipment_id)
                    )
                    ver_eq = ver_eq_result.scalar_one_or_none()
                    if ver_eq:
                        scan_path = _resolve_report_file_path(ver_eq.scan_file_path) if ver_eq.scan_file_path else ver_eq.scan_file_path
                        verification_equipment_list.append({
                            "id": str(ver_eq.id),
                            "name": ver_eq.name,
                            "equipment_type": ver_eq.equipment_type,
                            "serial_number": ver_eq.serial_number,
                            "manufacturer": ver_eq.manufacturer,
                            "model": ver_eq.model,
                            "verification_date": ver_eq.verification_date.isoformat() if ver_eq.verification_date else None,
                            "next_verification_date": ver_eq.next_verification_date.isoformat() if ver_eq.next_verification_date else None,
                            "verification_certificate_number": ver_eq.verification_certificate_number,
                            "verification_organization": ver_eq.verification_organization,
                            "scan_file_path": scan_path,
                            "scan_file_name": ver_eq.scan_file_name,
                        })
            except Exception as e:
                print(f"Warning: Could not load verification equipment: {e}")
                verification_equipment_list = []
            
            # Generate report
            reports_dir = Path("/app/reports")
            reports_dir.mkdir(exist_ok=True)
            
            report_type = report_data.get("report_type", "TECHNICAL_REPORT")
            # pdf или docx (поддерживаем также WORD/DOC)
            output_format = (report_data.get("format") or "pdf").strip().lower()
            is_docx = output_format in ["docx", "doc", "word"]

            # Подключаем макет отчета (definition) из report_templates.json (MVP без миграций БД)
            template_definition = None
            try:
                templates_path = _Path("/app/reports/report_templates.json")
                if templates_path.exists():
                    templates = _json.loads(templates_path.read_text(encoding="utf-8") or "[]")
                    # ищем шаблон по типу оборудования (type_id), report_type и format
                    eq_type_id = str(getattr(equipment, "type_id", "") or "")
                    def _match(t):
                        if not isinstance(t, dict) or not t.get("is_active"):
                            return False
                        if (t.get("equipment_type_id") or "") and (t.get("equipment_type_id") != eq_type_id):
                            return False
                        if (t.get("report_type") or "") and (t.get("report_type") != report_type):
                            return False
                        if (t.get("format") or "") and (t.get("format") != output_format):
                            return False
                        return True

                    chosen = next((t for t in templates if _match(t)), None)
                    if not chosen:
                        # fallback: любой активный по type_id
                        def _match2(t):
                            if not isinstance(t, dict) or not t.get("is_active"):
                                return False
                            if (t.get("equipment_type_id") or "") and (t.get("equipment_type_id") != eq_type_id):
                                return False
                            if (t.get("report_type") or "") and (t.get("report_type") != report_type):
                                return False
                            return True
                        chosen = next((t for t in templates if _match2(t)), None)
                    if not chosen:
                        # fallback: общий активный (equipment_type_id null/empty)
                        def _match3(t):
                            if not isinstance(t, dict) or not t.get("is_active"):
                                return False
                            if t.get("equipment_type_id") not in (None, "", "null"):
                                return False
                            if (t.get("report_type") or "") and (t.get("report_type") != report_type):
                                return False
                            return True
                        chosen = next((t for t in templates if _match3(t)), None)
                    if chosen:
                        template_definition = chosen.get("definition")
            except Exception:
                template_definition = None
            
            if is_docx:
                # Генерация Word документа
                from word_generator import WordGenerator
                word_generator = WordGenerator()
                filename = f"{report_type}_{inspection.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.docx"
                file_path = reports_dir / filename
            else:
                # Генерация PDF
                generator = ReportGenerator()
                filename = f"{report_type}_{inspection.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
                file_path = reports_dir / filename
            
            # Проверяем, что ndt_methods не None и является списком
            if ndt_methods is None:
                ndt_methods = []
            
            def _resolve_photo_list(lst):
                if not isinstance(lst, list):
                    return lst
                return [_resolve_report_file_path(x) or x for x in lst if isinstance(x, str)]

            ndt_methods_data = []
            for m in ndt_methods:
                ad = m.additional_data or {}
                if isinstance(ad, dict) and "annotated_images" in ad and isinstance(ad["annotated_images"], list):
                    ad = dict(ad)
                    ad["annotated_images"] = _resolve_photo_list(ad["annotated_images"])
                cert_num = (ad.get("certificate_number") if isinstance(ad, dict) else None) or None
                ndt_methods_data.append({
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "certificate_number": cert_num,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": _resolve_photo_list(m.photos or []),
                    "additional_data": ad,
                    "performed_date": m.performed_date.isoformat() if m.performed_date else None,
                })

            # Приложения: документы специалистов (удостоверения/сертификаты НК) по ФИО из методов НК
            specialist_docs = []
            try:
                inspector_names = sorted(
                    {str(m.get("inspector_name")).strip() for m in ndt_methods_data if m.get("inspector_name")},
                    key=lambda s: s.lower(),
                )
                for name in inspector_names:
                    # ищем пользователя по full_name или username (берём первого при совпадении нескольких)
                    ures = await db.execute(
                        select(User).where(or_(User.full_name == name, User.username == name)).limit(1)
                    )
                    u = ures.scalar_one_or_none()
                    if not u or not getattr(u, "engineer_id", None):
                        continue
                    certs_res = await db.execute(
                        select(Certification).where(
                            Certification.engineer_id == u.engineer_id,
                            Certification.scan_file_path.is_not(None),
                        )
                    )
                    certs = certs_res.scalars().all()
                    items = []
                    for c in certs:
                        sp = getattr(c, "scan_file_path", None)
                        if not sp:
                            continue
                        sp_resolved = _resolve_report_file_path(sp) or sp
                        items.append(
                            {
                                "certification_type": getattr(c, "certification_type", None),
                                "certificate_number": getattr(c, "certificate_number", None),
                                "method_code": getattr(c, "method_code", None),
                                "issuing_organization": getattr(c, "issuing_organization", None),
                                "issue_date": str(getattr(c, "issue_date", None)) if getattr(c, "issue_date", None) else None,
                                "expiry_date": str(getattr(c, "expiry_date", None)) if getattr(c, "expiry_date", None) else None,
                                "scan_file_path": sp_resolved,
                                "scan_file_name": getattr(c, "scan_file_name", None),
                                "scan_mime_type": getattr(c, "scan_mime_type", None),
                            }
                        )
                    if items:
                        specialist_docs.append({"inspector_name": name, "certifications": items})
            except Exception:
                specialist_docs = []

            # Подготавливаем данные для отчета и добавляем информацию об ОПО (если есть)
            inspection_payload = {
                "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                "data": inspection.data,
                "conclusion": inspection.conclusion,
                "status": inspection.status,
            }
            # Подставляем пути из загруженных document_files в data (фото таблички, схема, фото дефектов ВИК)
            try:
                dp = inspection_payload.get("data")
                if isinstance(dp, dict) and document_files:
                    dp = dict(dp)
                    for f in document_files:
                        dn = f.get("document_number")
                        fp = f.get("file_path")
                        if not dn or not fp:
                            continue
                        if dn in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
                            dp[dn] = fp
                        elif isinstance(dn, str) and dn.startswith("uzt_point_"):
                            parts = dn.split("_")
                            if len(parts) >= 4 and parts[0] == "uzt" and parts[1] == "point":
                                try:
                                    i, j = int(parts[2]), int(parts[3])
                                    tm = dp.get("thickness_measurements") or dp.get("thicknessMeasurements")
                                    if isinstance(tm, list) and 0 <= i < len(tm):
                                        t = tm[i]
                                        if isinstance(t, dict):
                                            t = dict(t)
                                            ph = list(t.get("photos") or [])
                                            while len(ph) <= j:
                                                ph.append("")
                                            ph[j] = fp
                                            t["photos"] = ph
                                            tm = list(tm)
                                            tm[i] = t
                                            dp["thickness_measurements"] = tm
                                except (ValueError, IndexError):
                                    pass
                        elif isinstance(dn, str) and dn.startswith("vd_"):
                            parts = dn.split("_")
                            if len(parts) == 3 and parts[0] == "vd":
                                try:
                                    i, j = int(parts[1]), int(parts[2])
                                    vd = dp.get("visual_defects")
                                    if isinstance(vd, list) and 0 <= i < len(vd):
                                        d = vd[i]
                                        if isinstance(d, dict):
                                            d = dict(d)
                                            ph = list(d.get("photos") or [])
                                            while len(ph) <= j:
                                                ph.append("")
                                            ph[j] = fp
                                            d["photos"] = ph
                                            vd = list(vd)
                                            vd[i] = d
                                            dp["visual_defects"] = vd
                                except (ValueError, IndexError):
                                    pass
                    inspection_payload["data"] = dp
            except Exception:
                pass
            # Разрешаем пути к фото таблички, схемы и фото дефектов в data (для вставки в отчёт)
            try:
                dp = inspection_payload.get("data")
                if isinstance(dp, dict):
                    dp = dict(dp)
                    for key in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
                        if dp.get(key) and isinstance(dp[key], str):
                            dp[key] = _resolve_report_file_path(dp[key]) or dp[key]
                    # Фото дефектов ВИК (синхронизация с мобильного)
                    vd = dp.get("visual_defects")
                    if isinstance(vd, list):
                        vd = list(vd)
                        for i, d in enumerate(vd):
                            if isinstance(d, dict):
                                d = dict(d)
                                ph = d.get("photos") or []
                                if isinstance(ph, list):
                                    d["photos"] = [_resolve_report_file_path(p) or p for p in ph if isinstance(p, str)]
                                vd[i] = d
                        dp["visual_defects"] = vd
                    # Фото замеров УЗТ
                    tm = dp.get("thickness_measurements") or dp.get("thicknessMeasurements")
                    if isinstance(tm, list):
                        tm = list(tm)
                        for i, t in enumerate(tm):
                            if isinstance(t, dict):
                                t = dict(t)
                                ph = t.get("photos") or []
                                if isinstance(ph, list):
                                    t["photos"] = [_resolve_report_file_path(p) or p for p in ph if isinstance(p, str)]
                                tm[i] = t
                        dp["thickness_measurements"] = tm
                    inspection_payload["data"] = dp
            except Exception:
                pass
            try:
                data_payload = inspection_payload.get("data")
                if isinstance(data_payload, dict) and opo_info:
                    data_payload = dict(data_payload)
                    survey = opo_info.get("survey_data") if isinstance(opo_info.get("survey_data"), dict) else {}
                    if isinstance(survey, dict):
                        docs_current = data_payload.get("documents") or {}
                        if isinstance(docs_current, dict) and isinstance(survey.get("documents"), dict):
                            merged_docs = dict(docs_current)
                            for k, v in survey.get("documents").items():
                                try:
                                    n = int(str(k))
                                except Exception:
                                    continue
                                if 1 <= n <= 9 and not merged_docs.get(str(k)):
                                    merged_docs[str(k)] = v
                            data_payload["documents"] = merged_docs
                        if not data_payload.get("organization") and survey.get("organization"):
                            data_payload["organization"] = survey.get("organization")
                        if not data_payload.get("executors") and survey.get("executors"):
                            data_payload["executors"] = survey.get("executors")
                        data_payload.setdefault("opo_survey", survey)

                    data_payload.setdefault("opo", opo_info)
                    if opo_info.get("id"):
                        data_payload.setdefault("opo_id", opo_info["id"])
                    if opo_info.get("name"):
                        data_payload.setdefault("opo_name", opo_info["name"])
                    if opo_info.get("code"):
                        data_payload.setdefault("opo_code", opo_info["code"])
                    if opo_info.get("description"):
                        data_payload.setdefault("opo_description", opo_info["description"])
                    if opo_info.get("enterprise_name"):
                        data_payload.setdefault("opo_enterprise", opo_info["enterprise_name"])
                    if opo_info.get("branch_name"):
                        data_payload.setdefault("opo_branch", opo_info["branch_name"])
                    if opo_info.get("workshop_name"):
                        data_payload.setdefault("opo_workshop", opo_info["workshop_name"])

                    inspection_payload["data"] = data_payload
            except Exception as e:
                print(f"Warning: Could not merge OPO data into report payload: {e}")

            _report_gen_t0 = time.time()
            if is_docx:
                # Генерация Word документа во временный файл, затем перемещение (восстановление после сбоя)
                import tempfile as _tf
                _fd, _tmp_path = _tf.mkstemp(suffix=".docx", prefix="report_", dir=str(reports_dir))
                try:
                    os.close(_fd)
                    word_generator.generate_report_word(
                        inspection_payload,
                        {
                            "id": str(equipment.id),
                            "name": equipment.name,
                            "serial_number": equipment.serial_number,
                            "location": equipment.location,
                            "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                            "attributes": equipment.attributes or {},
                            "type_code": equipment_type_code,
                            "type_name": equipment_type_name,
                        },
                        ndt_methods_data,
                        _tmp_path,
                        report_type,
                        document_files=document_files,
                        specialist_docs=specialist_docs,
                        verification_equipment=verification_equipment_list,
                        template_definition=template_definition,
                    )
                    os.replace(_tmp_path, str(file_path))
                except Exception:
                    if os.path.exists(_tmp_path):
                        try:
                            os.unlink(_tmp_path)
                        except OSError:
                            pass
                    raise
            else:
                # Генерация PDF
                if report_type == "EXPERTISE":
                    generator.generate_expertise_report(
                        inspection_payload,
                        {
                            "id": str(equipment.id),
                            "name": equipment.name,
                            "serial_number": equipment.serial_number,
                            "location": equipment.location,
                            "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                            "attributes": equipment.attributes or {},
                        },
                        resource_data,
                        str(file_path),
                        ndt_methods_data,
                        document_files=document_files,
                        specialist_docs=specialist_docs,
                        verification_equipment=verification_equipment_list,
                    )
                else:
                    generator.generate_technical_report(
                        inspection_payload,
                        {
                            "id": str(equipment.id),
                            "name": equipment.name,
                            "serial_number": equipment.serial_number,
                            "location": equipment.location,
                            "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                            "attributes": equipment.attributes or {},
                        },
                        str(file_path),
                        ndt_methods_data,
                        document_files=document_files,
                        specialist_docs=specialist_docs,
                        verification_equipment=verification_equipment_list,
                    )
            _metrics["report_generation_seconds_sum"] = _metrics.get("report_generation_seconds_sum", 0) + (time.time() - _report_gen_t0)
            _metrics["report_generation_count"] = _metrics.get("report_generation_count", 0) + 1
            
            # Генерируем номера отчета
            from report_utils import generate_report_number, generate_registration_number
            report_number = await generate_report_number(db, report_type)
            registration_number = await generate_registration_number(db)
            
            # Save report record
            new_report = Report(
                inspection_id=inspection_id,
                report_type=report_type,
                report_number=report_number,
                registration_number=registration_number,
                file_path=str(file_path),
                file_size=file_path.stat().st_size if file_path.exists() else 0,
                created_by=current_user.id,
                is_archived=False  # Явно устанавливаем значение
            )
            # Для DOCX также заполняем word_* поля (для единообразия и будущего расширения)
            if is_docx:
                new_report.word_file_path = str(file_path)
                new_report.word_file_size = new_report.file_size
            db.add(new_report)
            await db.commit()
            await db.refresh(new_report)
            
            return {
                "id": str(new_report.id),
                "report_number": new_report.report_number,
                "registration_number": new_report.registration_number,
                "file_path": str(file_path),
                "file_size": new_report.file_size,
                "format": "docx" if is_docx else "pdf",
                "status": "generated"
            }
        else:
            raise HTTPException(status_code=400, detail="inspection_id is required")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate report: {str(e)}")


@app.post("/api/reports/bulk-export", tags=["reports"])
async def bulk_export_reports(
    body: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Пакетная выгрузка отчётов: по списку inspection_ids генерируются DOCX и возвращаются в ZIP (макс. 15 шт)."""
    import tempfile
    inspection_ids = body.get("inspection_ids") or []
    if not isinstance(inspection_ids, list):
        raise HTTPException(status_code=400, detail="inspection_ids должен быть массивом")
    inspection_ids = [str(x).strip() for x in inspection_ids if x][:15]
    report_type = (body.get("report_type") or "TECHNICAL_REPORT").strip().upper()
    if not inspection_ids:
        raise HTTPException(status_code=400, detail="Укажите хотя бы один inspection_id")

    user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
    current_user = user_result.scalar_one_or_none()
    if not current_user:
        raise HTTPException(status_code=404, detail="User not found")

    from word_generator import WordGenerator
    word_generator = WordGenerator()
    temp_dir = tempfile.mkdtemp(prefix="bulk_report_")
    generated = []
    try:
        for insp_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(insp_id)
            except (ValueError, TypeError):
                continue
            insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
            inspection = insp_result.scalar_one_or_none()
            if not inspection:
                continue
            if current_user.role == "engineer" and getattr(inspection, "inspector_id", None) != current_user.id and getattr(inspection, "performed_by", None) != current_user.id:
                continue
            eq_result = await db.execute(select(Equipment).where(Equipment.id == inspection.equipment_id))
            equipment = eq_result.scalar_one_or_none()
            if not equipment:
                continue
            inspection_data = dict(inspection.data or {})
            inspection_data["id"] = str(inspection.id)
            inspection_data["status"] = getattr(inspection, "status", "DRAFT")
            inspection_data["conclusion"] = getattr(inspection, "conclusion", None)
            inspection_data["date_performed"] = inspection.date_performed.isoformat() if getattr(inspection, "date_performed", None) else None
            equipment_data = {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": getattr(equipment, "serial_number", None),
                "location": getattr(equipment, "location", None),
                "commissioning_date": str(equipment.commissioning_date) if getattr(equipment, "commissioning_date", None) else None,
                "attributes": equipment.attributes or {},
                "type_code": None,
                "type_name": None,
            }
            if equipment.type_id:
                t_res = await db.execute(select(EquipmentType).where(EquipmentType.id == equipment.type_id))
                t = t_res.scalar_one_or_none()
                if t:
                    equipment_data["type_code"] = t.code
                    equipment_data["type_name"] = t.name
            ndt_res = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
            ndt_list = ndt_res.scalars().all()
            ndt_methods_data = []
            for m in ndt_list:
                ndt_methods_data.append({
                    "method_code": getattr(m, "method_code", None),
                    "method_name": getattr(m, "method_name", None),
                    "is_performed": bool(getattr(m, "is_performed", False)),
                    "standard": getattr(m, "standard", None),
                    "equipment": getattr(m, "equipment", None),
                    "inspector_name": getattr(m, "inspector_name", None),
                    "inspector_level": getattr(m, "inspector_level", None),
                    "results": getattr(m, "results", None),
                    "defects": getattr(m, "defects", None),
                    "conclusion": getattr(m, "conclusion", None),
                    "photos": getattr(m, "photos", None) or [],
                    "additional_data": getattr(m, "additional_data", None) or {},
                    "performed_date": m.performed_date.isoformat() if getattr(m, "performed_date", None) else None,
                })
            document_files = []
            q_for_files = None
            if getattr(inspection, "questionnaire_id", None):
                q_res = await db.execute(select(Questionnaire).where(Questionnaire.id == inspection.questionnaire_id))
                q_for_files = q_res.scalar_one_or_none()
            if q_for_files:
                f_res = await db.execute(select(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.questionnaire_id == q_for_files.id))
                for f in f_res.scalars().all():
                    document_files.append({
                        "document_number": f.document_number,
                        "file_name": f.file_name,
                        "file_path": _resolve_report_file_path(f.file_path) or f.file_path,
                        "file_size": int(f.file_size or 0),
                    })
            out_path = os.path.join(temp_dir, f"report_{insp_id}.docx")
            try:
                word_generator.generate_report_word(
                    inspection_data,
                    equipment_data,
                    ndt_methods_data,
                    out_path,
                    report_type,
                    document_files=document_files,
                    specialist_docs=[],
                    verification_equipment=[],
                    template_definition=None,
                )
                generated.append((insp_id, out_path))
            except Exception as e:
                print(f"Bulk export: skip inspection {insp_id}: {e}")
        if not generated:
            raise HTTPException(status_code=400, detail="Не удалось сгенерировать ни одного отчёта")
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for _id, p in generated:
                zf.write(p, os.path.basename(p))
        buf.seek(0)
        return StreamingResponse(
            buf,
            media_type="application/zip",
            headers={"Content-Disposition": "attachment; filename=reports.zip"},
        )
    finally:
        try:
            for _id, p in generated:
                if os.path.exists(p):
                    os.unlink(p)
            if os.path.exists(temp_dir):
                os.rmdir(temp_dir)
        except OSError:
            pass


# Report Templates endpoints (работа с БД)
@app.get("/api/report-templates-db")
async def get_report_templates_db(
    client_id: Optional[str] = None,
    template_type: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список шаблонов отчетов из БД"""
    try:
        from models import ReportTemplate
        query = select(ReportTemplate).where(ReportTemplate.is_active == 1)
        
        if client_id:
            try:
                client_uuid = uuid_lib.UUID(client_id)
                query = query.where(ReportTemplate.client_id == client_uuid)
            except:
                pass
        
        if template_type:
            query = query.where(ReportTemplate.template_type == template_type)
        
        result = await db.execute(query)
        templates = result.scalars().all()
        
        items = []
        for t in templates:
            items.append({
                "id": str(t.id),
                "name": t.name,
                "description": t.description,
                "template_type": t.template_type,
                "client_id": str(t.client_id) if t.client_id else None,
                "template_config": t.template_config,
                "is_default": t.is_default,
                "is_active": t.is_active,
            })
        
        return {"items": items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/report-templates-db")
async def create_report_template_db(
    template_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать шаблон отчета в БД"""
    try:
        from models import ReportTemplate
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        
        client_id = None
        if template_data.get("client_id"):
            try:
                client_id = uuid_lib.UUID(template_data.get("client_id"))
            except:
                pass
        
        if template_data.get("is_default"):
            existing_defaults = await db.execute(
                select(ReportTemplate).where(
                    ReportTemplate.template_type == template_data.get("template_type"),
                    ReportTemplate.is_default == True
                )
            )
            for t in existing_defaults.scalars().all():
                t.is_default = False
        
        template = ReportTemplate(
            name=template_data.get("name"),
            description=template_data.get("description"),
            template_type=template_data.get("template_type", "TECHNICAL"),
            client_id=client_id,
            template_config=template_data.get("template_config", {}),
            is_default=template_data.get("is_default", False),
            created_by=current_user.id if current_user else None,
        )
        
        db.add(template)
        await db.commit()
        await db.refresh(template)
        
        return {"id": str(template.id), "name": template.name, "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/api/report-templates-db/{template_id}")
async def update_report_template_db(
    template_id: str,
    template_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Обновить шаблон отчета в БД"""
    try:
        from models import ReportTemplate
        template_uuid = uuid_lib.UUID(template_id)
        result = await db.execute(
            select(ReportTemplate).where(ReportTemplate.id == template_uuid)
        )
        template = result.scalar_one_or_none()
        
        if not template:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        
        if "name" in template_data:
            template.name = template_data["name"]
        if "description" in template_data:
            template.description = template_data["description"]
        if "template_type" in template_data:
            template.template_type = template_data["template_type"]
        if "template_config" in template_data:
            template.template_config = template_data["template_config"]
        if "client_id" in template_data:
            if template_data["client_id"]:
                try:
                    template.client_id = uuid_lib.UUID(template_data["client_id"])
                except:
                    template.client_id = None
            else:
                template.client_id = None
        
        if "is_default" in template_data:
            if template_data["is_default"]:
                existing_defaults = await db.execute(
                    select(ReportTemplate).where(
                        ReportTemplate.template_type == template.template_type,
                        ReportTemplate.is_default == True,
                        ReportTemplate.id != template_uuid
                    )
                )
                for t in existing_defaults.scalars().all():
                    t.is_default = False
            template.is_default = template_data["is_default"]
        
        await db.commit()
        await db.refresh(template)
        
        return {"id": str(template.id), "name": template.name, "status": "updated"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/report-templates-db/{template_id}")
async def delete_report_template_db(
    template_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить шаблон отчета из БД"""
    try:
        from models import ReportTemplate
        template_uuid = uuid_lib.UUID(template_id)
        result = await db.execute(
            select(ReportTemplate).where(ReportTemplate.id == template_uuid)
        )
        template = result.scalar_one_or_none()
        
        if not template:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        
        template.is_active = 0
        await db.commit()
        
        return {"status": "deleted"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/reports/{report_id}/sign")
async def sign_report(
    report_id: str,
    signature_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Подписать отчет электронной подписью"""
    try:
        from datetime import timezone
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")
        
        report_uuid = uuid_lib.UUID(report_id)
        result = await db.execute(
            select(Report).where(Report.id == report_uuid)
        )
        report = result.scalar_one_or_none()
        
        if not report:
            raise HTTPException(status_code=404, detail="Отчет не найден")
        
        report.is_signed = True
        report.signed_at = datetime.now(timezone.utc)
        report.signed_by = current_user.id
        
        await db.commit()
        await db.refresh(report)
        
        return {
            "id": str(report.id),
            "is_signed": report.is_signed,
            "signed_at": str(report.signed_at),
            "status": "signed"
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/reports/{report_id}")
async def delete_report(
    report_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удаление отчета (admin/operator — любой, engineer — только свой)"""
    try:
        report_uuid = uuid_lib.UUID(report_id)

        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
        report = rep_result.scalar_one_or_none()
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")

        # Проверка прав
        if current_user.role in ["admin", "chief_operator", "operator"]:
            allowed = True
        elif current_user.role == "engineer":
            allowed = False
            if report.created_by and report.created_by == current_user.id:
                allowed = True
            elif report.created_by is None and report.inspection_id:
                insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                insp = insp_result.scalar_one_or_none()
                if insp and insp.inspector_id == current_user.id:
                    allowed = True
        else:
            allowed = False

        if not allowed:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Удаляем файлы
        for p in [report.file_path, getattr(report, "word_file_path", None)]:
            if p:
                try:
                    fp = Path(p)
                    if fp.exists():
                        fp.unlink()
                except Exception:
                    pass

        await db.delete(report)
        await db.commit()
        return {"status": "deleted", "id": report_id}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid report_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete report: {str(e)}")

class BulkDeleteInspectionsRequest(BaseModel):
    inspection_ids: List[str]

@app.post("/api/inspections/bulk-delete")
async def bulk_delete_inspections(
    request: BulkDeleteInspectionsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое удаление чек-листов"""
    try:
        inspection_ids = request.inspection_ids
        if not inspection_ids:
            raise HTTPException(status_code=400, detail="No inspection IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        deleted_count = 0
        for inspection_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
                inspection = insp_result.scalar_one_or_none()
                
                if not inspection:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if inspection.inspector_id and inspection.inspector_id == user.id:
                        allowed = True
                
                if not allowed:
                    continue
                
                # ВАЖНО: НЕ удаляем связанные отчеты при удалении чек-листа!
                # Отчеты должны оставаться в системе даже если чек-лист удален.
                # Проверяем, есть ли связанные отчеты - если есть, не удаляем инспекцию
                rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
                related_reports = rep_result.scalars().all()
                
                if related_reports:
                    # Если есть связанные отчеты, пропускаем удаление этой инспекции
                    print(f"⚠️ Inspection {inspection_id} has {len(related_reports)} related reports. Skipping deletion to preserve reports.")
                    continue
                
                # Удаляем связанные методы НК
                try:
                    ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
                    ndt_methods = ndt_result.scalars().all()
                    for m in ndt_methods:
                        await db.delete(m)
                    if ndt_methods:
                        await db.flush()
                except Exception as e:
                    print(f"⚠️ Error deleting NDT methods for inspection {inspection_id}: {str(e)}")
                
                # Удаляем связанное оборудование для поверок
                try:
                    eq_result = await db.execute(select(InspectionEquipment).where(InspectionEquipment.inspection_id == inspection.id))
                    inspection_equipment = eq_result.scalars().all()
                    for eq in inspection_equipment:
                        await db.delete(eq)
                    if inspection_equipment:
                        await db.flush()
                except Exception as e:
                    print(f"⚠️ Error deleting inspection equipment for inspection {inspection_id}: {str(e)}")
                
                # Теперь можно безопасно удалить сам чек-лист
                await db.delete(inspection)
                deleted_count += 1
            except Exception as e:
                # Логируем ошибку для отладки, но продолжаем обработку других записей
                print(f"⚠️ Error deleting inspection {inspection_id}: {str(e)}")
                continue
        
        await db.commit()
        return {"deleted": deleted_count, "total": len(inspection_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete inspections: {str(e)}")

class BulkArchiveRequest(BaseModel):
    inspection_ids: List[str]
    archive: bool = True

@app.post("/api/inspections/bulk-archive")
async def bulk_archive_inspections(
    request: BulkArchiveRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое архивирование/разархивирование чек-листов"""
    try:
        inspection_ids = request.inspection_ids
        archive = request.archive
        if not inspection_ids:
            raise HTTPException(status_code=400, detail="No inspection IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        archived_count = 0
        for inspection_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
                inspection = insp_result.scalar_one_or_none()
                
                if not inspection:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if inspection.inspector_id and inspection.inspector_id == user.id:
                        allowed = True
                
                if not allowed:
                    continue
                
                inspection.is_archived = archive
                archived_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"archived": archived_count, "total": len(inspection_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to archive inspections: {str(e)}")

class BulkDeleteReportsRequest(BaseModel):
    report_ids: List[str]

@app.post("/api/reports/bulk-delete")
async def bulk_delete_reports(
    request: BulkDeleteReportsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое удаление отчетов"""
    try:
        report_ids = request.report_ids
        if not report_ids:
            raise HTTPException(status_code=400, detail="No report IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        deleted_count = 0
        for report_id in report_ids:
            try:
                report_uuid = uuid_lib.UUID(report_id)
                rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
                report = rep_result.scalar_one_or_none()
                
                if not report:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if report.created_by and report.created_by == user.id:
                        allowed = True
                    elif report.created_by is None and report.inspection_id:
                        insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                        insp = insp_result.scalar_one_or_none()
                        if insp and insp.inspector_id == user.id:
                            allowed = True
                
                if not allowed:
                    continue
                
                # Удаляем файлы
                for p in [report.file_path, getattr(report, "word_file_path", None)]:
                    if p:
                        try:
                            fp = Path(p)
                            if fp.exists():
                                fp.unlink()
                        except Exception:
                            pass
                
                await db.delete(report)
                deleted_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"deleted": deleted_count, "total": len(report_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete reports: {str(e)}")

class BulkArchiveReportsRequest(BaseModel):
    report_ids: List[str]
    archive: bool = True

@app.post("/api/reports/bulk-archive")
async def bulk_archive_reports(
    request: BulkArchiveReportsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое архивирование/разархивирование отчетов"""
    try:
        report_ids = request.report_ids
        archive = request.archive
        if not report_ids:
            raise HTTPException(status_code=400, detail="No report IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        archived_count = 0
        for report_id in report_ids:
            try:
                report_uuid = uuid_lib.UUID(report_id)
                rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
                report = rep_result.scalar_one_or_none()
                
                if not report:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if report.created_by and report.created_by == user.id:
                        allowed = True
                    elif report.created_by is None and report.inspection_id:
                        insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                        insp = insp_result.scalar_one_or_none()
                        if insp and insp.inspector_id == user.id:
                            allowed = True
                
                if not allowed:
                    continue
                
                report.is_archived = archive
                archived_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"archived": archived_count, "total": len(report_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to archive reports: {str(e)}")

@app.delete("/api/reports/cleanup")
async def cleanup_reports(
    older_than_days: int = 90,
    before: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Массовое удаление старых отчетов.
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои
    Параметры:
      - older_than_days: удалить старше N дней (по created_at)
      - before: ISO дата/время (например 2025-12-01 или 2025-12-01T00:00:00)
    """
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        cutoff = None
        if before:
            try:
                cutoff = datetime.fromisoformat(before.replace("Z", "+00:00"))
            except Exception:
                # fallback для формата YYYY-MM-DD
                try:
                    cutoff = datetime.strptime(before, "%Y-%m-%d")
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid 'before' format")
        else:
            if older_than_days < 1:
                raise HTTPException(status_code=400, detail="older_than_days must be >= 1")
            cutoff = datetime.now() - timedelta(days=int(older_than_days))

        query = select(Report).where(Report.created_at < cutoff)

        # Ограничение инженера только своими отчетами (как в get_reports)
        if current_user.role == "engineer":
            query = (
                query.join(Inspection, Report.inspection_id == Inspection.id, isouter=True)
                .where(
                    or_(
                        Report.created_by == current_user.id,
                        and_(Report.created_by.is_(None), Inspection.inspector_id == current_user.id),
                    )
                )
            )
        elif current_user.role not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        result = await db.execute(query)
        reports = result.scalars().all()

        deleted = 0
        for report in reports:
            # удаляем файлы
            for p in [report.file_path, getattr(report, "word_file_path", None)]:
                if p:
                    try:
                        fp = Path(p)
                        if fp.exists():
                            fp.unlink()
                    except Exception:
                        pass
            await db.delete(report)
            deleted += 1

        await db.commit()
        return {"status": "ok", "deleted": deleted, "cutoff": cutoff.isoformat()}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to cleanup reports: {str(e)}")

@app.get("/api/reports/{report_id}/download")
async def download_report(
    report_id: str,
    format: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Download report file (PDF/DOCX)"""
    try:
        # Текущий пользователь и права
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        result = await db.execute(
            select(Report).where(Report.id == uuid_lib.UUID(report_id))
        )
        report = result.scalar_one_or_none()
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")

        # Инженер может скачивать только свои отчеты
        if current_user.role == "engineer":
            allowed = False
            if report.created_by and report.created_by == current_user.id:
                allowed = True
            elif report.created_by is None and report.inspection_id:
                insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                insp = insp_result.scalar_one_or_none()
                if insp and insp.inspector_id == current_user.id:
                    allowed = True
            if not allowed:
                raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Выбор файла по формату (если указан), иначе по расширению/наличию
        fmt = (format or "").strip().lower()
        selected_path = None
        if fmt in ["docx", "doc", "word"]:
            if report.word_file_path and os.path.exists(report.word_file_path):
                selected_path = report.word_file_path
            elif report.file_path and str(report.file_path).lower().endswith(".docx") and os.path.exists(report.file_path):
                selected_path = report.file_path
        elif fmt in ["pdf"]:
            if report.file_path and str(report.file_path).lower().endswith(".pdf") and os.path.exists(report.file_path):
                selected_path = report.file_path

        if not selected_path:
            # auto
            if report.file_path and os.path.exists(report.file_path):
                selected_path = report.file_path
            elif report.word_file_path and os.path.exists(report.word_file_path):
                selected_path = report.word_file_path

        if not selected_path or not os.path.exists(selected_path):
            raise HTTPException(status_code=404, detail="Report file not found")

        filename = os.path.basename(selected_path)
        lower = filename.lower()
        if lower.endswith(".docx"):
            media_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        else:
            media_type = "application/pdf"

        return FileResponse(
            selected_path,
            media_type=media_type,
            filename=filename
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid report_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Questionnaire endpoints
@app.get("/api/questionnaires")
async def get_questionnaires(
    equipment_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Получить список опросных листов"""
    try:
        query = select(Questionnaire)
        
        if equipment_id:
            try:
                equipment_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(Questionnaire.equipment_id == equipment_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        query = query.order_by(Questionnaire.created_at.desc()).offset(skip).limit(limit)
        
        result = await db.execute(query)
        questionnaires = result.scalars().all()
        
        items = []
        for q in questionnaires:
            insp_date = getattr(q, "inspection_date", None) or getattr(q, "date_performed", None)
            items.append({
                "id": str(q.id),
                "equipment_id": str(q.equipment_id),
                "equipment_inventory_number": getattr(q, "equipment_inventory_number", None),
                "equipment_name": getattr(q, "equipment_name", None),
                "inspection_date": insp_date.isoformat() if insp_date else None,
                "inspector_name": getattr(q, "inspector_name", None),
                "inspector_position": getattr(q, "inspector_position", None),
                "file_path": getattr(q, "file_path", None),
                "file_size": getattr(q, "file_size", None) or 0,
                "word_file_path": getattr(q, "word_file_path", None),
                "word_file_size": getattr(q, "word_file_size", None) or 0,
                "created_by": str(q.created_by) if getattr(q, "created_by", None) else None,
                "created_at": q.created_at.isoformat() if q.created_at else None,
            })
        return {"items": items, "total": len(questionnaires)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}")
async def get_questionnaire(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Получить опросный лист по ID"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Получаем методы НК для этого опросного листа
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        insp_date = getattr(questionnaire, "inspection_date", None) or getattr(questionnaire, "date_performed", None)
        return {
            "id": str(questionnaire.id),
            "equipment_id": str(questionnaire.equipment_id),
            "equipment_inventory_number": getattr(questionnaire, "equipment_inventory_number", None),
            "equipment_name": getattr(questionnaire, "equipment_name", None),
            "inspection_date": insp_date.isoformat() if insp_date else None,
            "inspector_name": getattr(questionnaire, "inspector_name", None),
            "inspector_position": getattr(questionnaire, "inspector_position", None),
            "questionnaire_data": getattr(questionnaire, "questionnaire_data", None) or getattr(questionnaire, "data", None),
            "file_path": getattr(questionnaire, "file_path", None),
            "file_size": getattr(questionnaire, "file_size", None) or 0,
            "word_file_path": getattr(questionnaire, "word_file_path", None),
            "word_file_size": getattr(questionnaire, "word_file_size", None) or 0,
            "created_by": str(questionnaire.created_by) if getattr(questionnaire, "created_by", None) else None,
            "created_at": questionnaire.created_at.isoformat() if questionnaire.created_at else None,
            "updated_at": questionnaire.updated_at.isoformat() if questionnaire.updated_at else None,
            "ndt_methods": [
                {
                    "id": str(m.id),
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": m.photos or [],
                    "additional_data": m.additional_data or {},
                    "performed_date": m.performed_date.isoformat() if m.performed_date else None,
                }
                for m in ndt_methods
            ]
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/questionnaires/{questionnaire_id}/ndt-methods")
async def add_ndt_method(
    questionnaire_id: str,
    method_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Добавить метод НК к опросному листу"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Проверяем существование опросного листа
        q_result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = q_result.scalar_one_or_none()
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Создаем метод НК
        performed_date = None
        if method_data.get("performed_date"):
            try:
                performed_date = datetime.fromisoformat(method_data.get("performed_date").replace('Z', '+00:00'))
            except:
                pass
        
        # Обработка аннотированных изображений
        photos_list = method_data.get("photos", [])
        additional_data = method_data.get("additional_data", {})
        
        new_method = NDTMethod(
            questionnaire_id=q_uuid,
            equipment_id=questionnaire.equipment_id,
            method_code=method_data.get("method_code"),
            method_name=method_data.get("method_name"),
            is_performed=1 if method_data.get("is_performed", False) else 0,
            standard=method_data.get("standard"),
            equipment=method_data.get("equipment"),
            inspector_name=method_data.get("inspector_name"),
            inspector_level=method_data.get("inspector_level"),
            results=method_data.get("results"),
            defects=method_data.get("defects"),
            conclusion=method_data.get("conclusion"),
            photos=photos_list,
            additional_data=additional_data,
            performed_date=performed_date,
        )
        
        db.add(new_method)
        await db.commit()
        await db.refresh(new_method)
        
        return {
            "id": str(new_method.id),
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to add NDT method: {str(e)}")

@app.post("/api/inspections/{inspection_id}/ndt-methods")
async def add_ndt_method_to_inspection(
    inspection_id: str,
    method_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Добавить метод НК к обследованию"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        
        # Проверяем существование обследования
        insp_result = await db.execute(
            select(Inspection).where(Inspection.id == insp_uuid)
        )
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")
        
        # Создаем метод НК
        performed_date = None
        if method_data.get("performed_date"):
            try:
                performed_date = datetime.fromisoformat(method_data.get("performed_date").replace('Z', '+00:00'))
            except:
                pass
        
        new_method = NDTMethod(
            inspection_id=insp_uuid,
            equipment_id=inspection.equipment_id,
            method_code=method_data.get("method_code"),
            method_name=method_data.get("method_name"),
            is_performed=1 if method_data.get("is_performed", False) else 0,
            standard=method_data.get("standard"),
            equipment=method_data.get("equipment"),
            inspector_name=method_data.get("inspector_name"),
            inspector_level=method_data.get("inspector_level"),
            results=method_data.get("results"),
            defects=method_data.get("defects"),
            conclusion=method_data.get("conclusion"),
            photos=method_data.get("photos", []),
            additional_data=method_data.get("additional_data", {}),
            performed_date=performed_date,
        )
        
        db.add(new_method)
        await db.commit()
        await db.refresh(new_method)
        
        return {
            "id": str(new_method.id),
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to add NDT method: {str(e)}")

@app.post("/api/questionnaires/{questionnaire_id}/generate-pdf")
async def generate_questionnaire_pdf(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Сгенерировать PDF для опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Получаем данные об оборудовании
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == questionnaire.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Получаем методы НК
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        # Генерируем PDF
        generator = ReportGenerator()
        # Храним генерируемые файлы в /app/reports (примонтирован в docker-compose),
        # чтобы они не пропадали при пересборке контейнера.
        questionnaires_dir = Path("/app/reports/questionnaires")
        questionnaires_dir.mkdir(parents=True, exist_ok=True)
        
        filename = f"questionnaire_{questionnaire.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        file_path = questionnaires_dir / filename
        
        generator.generate_questionnaire_report(
            questionnaire.questionnaire_data or {},
            {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
            },
            {
                "inventory_number": questionnaire.equipment_inventory_number,
                "equipment_name": questionnaire.equipment_name,
                "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
                "inspector_name": questionnaire.inspector_name,
                "inspector_position": questionnaire.inspector_position,
            },
            str(file_path),
            [
                {
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                }
                for m in ndt_methods
            ]
        )
        
        # Обновляем запись опросного листа
        questionnaire.file_path = str(file_path)
        questionnaire.file_size = file_path.stat().st_size if file_path.exists() else 0
        await db.commit()
        
        return {
            "id": str(questionnaire.id),
            "file_path": str(file_path),
            "file_size": questionnaire.file_size,
            "status": "generated"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate PDF: {str(e)}")

@app.get("/api/questionnaires/{questionnaire_id}/download")
async def download_questionnaire(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать опросный лист (PDF)"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Если PDF еще не сгенерирован, генерируем его
        if not questionnaire.file_path or not Path(questionnaire.file_path).exists():
            await generate_questionnaire_pdf(questionnaire_id, db)
            result = await db.execute(
                select(Questionnaire).where(Questionnaire.id == q_uuid)
            )
            questionnaire = result.scalar_one_or_none()
        
        if not questionnaire.file_path:
            raise HTTPException(status_code=404, detail="PDF file not found")
        
        file_path = Path(questionnaire.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="PDF file not found on disk")
        
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type='application/pdf'
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/questionnaires/{questionnaire_id}/generate-word")
async def generate_questionnaire_word(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Сгенерировать Word документ для опросного листа"""
    try:
        from word_generator import WordGenerator
        
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Получаем данные об оборудовании
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == questionnaire.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Получаем методы НК
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        # Генерируем Word
        generator = WordGenerator()
        # Храним генерируемые файлы в /app/reports (примонтирован в docker-compose),
        # чтобы они не пропадали при пересборке контейнера.
        questionnaires_dir = Path("/app/reports/questionnaires")
        questionnaires_dir.mkdir(parents=True, exist_ok=True)
        
        filename = f"questionnaire_{questionnaire.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.docx"
        file_path = questionnaires_dir / filename
        
        generator.generate_questionnaire_word(
            questionnaire.questionnaire_data or {},
            {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
            },
            {
                "inventory_number": questionnaire.equipment_inventory_number,
                "equipment_name": questionnaire.equipment_name,
                "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
                "inspector_name": questionnaire.inspector_name,
                "inspector_position": questionnaire.inspector_position,
            },
            [
                {
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                }
                for m in ndt_methods
            ],
            str(file_path)
        )
        
        # Обновляем запись опросного листа
        questionnaire.word_file_path = str(file_path)
        questionnaire.word_file_size = file_path.stat().st_size if file_path.exists() else 0
        await db.commit()
        
        return {
            "id": str(questionnaire.id),
            "word_file_path": str(file_path),
            "word_file_size": questionnaire.word_file_size,
            "status": "generated"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate Word: {str(e)}")

@app.get("/api/questionnaires/{questionnaire_id}/download-word")
async def download_questionnaire_word(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать Word документ опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Если Word еще не сгенерирован, генерируем его
        if not questionnaire.word_file_path or not Path(questionnaire.word_file_path).exists():
            await generate_questionnaire_word(questionnaire_id, db)
            result = await db.execute(
                select(Questionnaire).where(Questionnaire.id == q_uuid)
            )
            questionnaire = result.scalar_one_or_none()
        
        if not questionnaire.word_file_path:
            raise HTTPException(status_code=404, detail="Word file not found")
        
        file_path = Path(questionnaire.word_file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="Word file not found on disk")
        
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Document files endpoints
@app.post("/api/questionnaires/{questionnaire_id}/documents/{document_number}/upload")
async def upload_document_file(
    questionnaire_id: str,
    document_number: str,
    file: UploadFile = File(...),
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить файл документа для чек-листа. Лимит: 25 МБ на файл, до 60 вложений на опросник."""
    try:
        # Проверяем формат questionnaire_id
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Проверяем существование опросного листа
        q_result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = q_result.scalar_one_or_none()
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Проверяем номер/ключ документа.
        # - Основной список (1..17) — "Перечень рассмотренных документов".
        # - Дополнительно разрешаем любые "безопасные" ключи для прочих вложений чек-листа:
        #   factory_plate_photo, control_scheme_image, photo_1, scheme_2025_12 и т.п.
        allowed_numbers = {str(i) for i in range(1, 18)}
        if document_number not in allowed_numbers:
            import re
            # безопасный ключ: латиница/цифры/подчерк/дефис, 1..64 символа
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", document_number):
                raise HTTPException(
                    status_code=400,
                    detail="Invalid document key. Use 1..17 or a safe key like factory_plate_photo/control_scheme_image/photo_1",
                )
        
        # Проверяем тип файла (только изображения и PDF). Если клиент не передал Content-Type — определяем по расширению.
        allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'application/pdf']
        content_type = file.content_type
        if not content_type or content_type not in allowed_types:
            ext = (Path(file.filename or "").suffix or "").lower()
            if ext in (".jpg", ".jpeg"):
                content_type = "image/jpeg"
            elif ext == ".png":
                content_type = "image/png"
            elif ext == ".pdf":
                content_type = "application/pdf"
            else:
                content_type = None
        if content_type not in allowed_types:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Allowed types: {', '.join(allowed_types)}",
            )
        
        # Получаем пользователя для uploaded_by
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        user_id = user.id if user else None
        
        # Создаем директорию для файлов документов в /app/uploads (примонтирован),
        # чтобы вложения чек-листа не пропадали при пересборке контейнера.
        documents_dir = Path("/app/uploads/questionnaire_documents") / str(q_uuid)
        documents_dir.mkdir(parents=True, exist_ok=True)
        
        # Генерируем уникальное имя файла
        file_extension = Path(file.filename).suffix if file.filename else '.bin'
        if content_type == 'application/pdf':
            file_extension = '.pdf'
        elif content_type and 'image' in content_type:
            file_extension = '.jpg' if 'jpeg' in content_type else '.png'
        
        file_id = uuid_lib.uuid4()
        file_name = f"doc_{document_number}_{file_id}{file_extension}"
        file_path = documents_dir / file_name
        
        # Лимит размера файла (25 МБ), читаем чанками
        MAX_FILE_SIZE_BYTES = 25 * 1024 * 1024
        file_content = b""
        while True:
            chunk = await file.read(1024 * 1024)
            if not chunk:
                break
            file_content += chunk
            if len(file_content) > MAX_FILE_SIZE_BYTES:
                raise HTTPException(
                    status_code=400,
                    detail=f"Файл слишком большой. Максимум {MAX_FILE_SIZE_BYTES // (1024*1024)} МБ.",
                )
        # Удаляем старый файл для этого документа, если есть (проверки до записи на диск)
        old_file_result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        old_file = old_file_result.scalar_one_or_none()
        if not old_file:
            MAX_DOCS = 60
            cnt = (await db.execute(select(func.count(QuestionnaireDocumentFile.id)).where(QuestionnaireDocumentFile.questionnaire_id == q_uuid))).scalar() or 0
            if cnt >= MAX_DOCS:
                raise HTTPException(status_code=400, detail=f"Превышен лимит вложений ({MAX_DOCS}).")
        if old_file:
            old_path = Path(old_file.file_path)
            if old_path.exists():
                old_path.unlink()
            await db.execute(delete(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.id == old_file.id))
        with open(file_path, 'wb') as f:
            f.write(file_content)
        file_size = len(file_content)
        
        # Создаем новую запись в БД
        new_file = QuestionnaireDocumentFile(
            questionnaire_id=q_uuid,
            document_number=document_number,
            file_name=file.filename or file_name,
            file_path=str(file_path),
            file_size=file_size,
            file_type=content_type.split('/')[0] if content_type else None,  # image или application
            mime_type=content_type,
            uploaded_by=user_id
        )
        
        db.add(new_file)
        await db.commit()
        await db.refresh(new_file)
        
        # Если загружено фото дефекта ВИК (vd_i_j) — обновляем inspection.data для отчётов
        if isinstance(document_number, str) and document_number.startswith("vd_"):
            try:
                parts = document_number.split("_")
                if len(parts) == 3 and parts[0] == "vd":
                    i, j = int(parts[1]), int(parts[2])
                    insp_result = await db.execute(
                        select(Inspection).where(Inspection.questionnaire_id == q_uuid)
                    )
                    insp = insp_result.scalar_one_or_none()
                    if insp and isinstance(insp.data, dict):
                        data = dict(insp.data)
                        vd = data.get("visual_defects")
                        if isinstance(vd, list) and 0 <= i < len(vd):
                            d = vd[i]
                            if isinstance(d, dict):
                                d = dict(d)
                                ph = d.get("photos") or []
                                if isinstance(ph, list) and 0 <= j < len(ph):
                                    ph = list(ph)
                                    ph[j] = str(file_path)
                                    d["photos"] = ph
                                    vd = list(vd)
                                    vd[i] = d
                                    data["visual_defects"] = vd
                                    insp.data = data
                                    await db.commit()
            except Exception:
                pass
        
        return {
            "id": str(new_file.id),
            "questionnaire_id": questionnaire_id,
            "document_number": document_number,
            "file_name": new_file.file_name,
            "file_size": new_file.file_size,
            "file_type": new_file.file_type,
            "mime_type": new_file.mime_type,
            "created_at": new_file.created_at.isoformat() if new_file.created_at else None
        }
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to upload file: {str(e)}")

@app.get("/api/questionnaires/{questionnaire_id}/documents/{document_number}/download")
async def download_document_file(
    questionnaire_id: str,
    document_number: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать файл документа чек-листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Ищем файл
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()
        
        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")
        
        file_path = Path(doc_file.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="File not found on disk")
        
        # Определяем media_type
        media_type = doc_file.mime_type or 'application/octet-stream'
        if doc_file.file_type == 'image':
            if 'jpeg' in doc_file.mime_type or 'jpg' in doc_file.mime_type:
                media_type = 'image/jpeg'
            elif 'png' in doc_file.mime_type:
                media_type = 'image/png'
        elif doc_file.file_type == 'application' or 'pdf' in doc_file.mime_type:
            media_type = 'application/pdf'
        
        return FileResponse(
            path=str(file_path),
            filename=doc_file.file_name,
            media_type=media_type
        )
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}/documents")
async def get_questionnaire_documents(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Получить список всех файлов документов для опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid
            ).order_by(QuestionnaireDocumentFile.document_number)
        )
        files = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(f.id),
                    "document_number": f.document_number,
                    "file_name": f.file_name,
                    "file_size": f.file_size,
                    "file_type": f.file_type,
                    "mime_type": f.mime_type,
                    "created_at": f.created_at.isoformat() if f.created_at else None
                }
                for f in files
            ],
            "total": len(files)
        }
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}/documents/{document_number}/view")
async def view_document_file(
    questionnaire_id: str,
    document_number: str,
    db: AsyncSession = Depends(get_db)
):
    """
    Просмотр файла документа чек-листа в браузере (Content-Disposition: inline).
    Поддерживает изображения и PDF.
    """
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)

        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()

        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")

        file_path = Path(doc_file.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="File not found on disk")

        media_type = doc_file.mime_type or 'application/octet-stream'
        if doc_file.file_type == 'image':
            if doc_file.mime_type and ('jpeg' in doc_file.mime_type or 'jpg' in doc_file.mime_type):
                media_type = 'image/jpeg'
            elif doc_file.mime_type and 'png' in doc_file.mime_type:
                media_type = 'image/png'
        elif (doc_file.file_type == 'application') or (doc_file.mime_type and 'pdf' in doc_file.mime_type):
            media_type = 'application/pdf'

        return FileResponse(
            path=str(file_path),
            media_type=media_type,
            headers={
                "Content-Disposition": f'inline; filename="{doc_file.file_name}"'
            }
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/questionnaires/{questionnaire_id}/documents/{document_number}")
async def delete_document_file(
    questionnaire_id: str,
    document_number: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить файл документа чек-листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Ищем файл
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()
        
        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")
        
        # Удаляем файл с диска
        file_path = Path(doc_file.file_path)
        if file_path.exists():
            file_path.unlink()
        
        # Удаляем запись из БД
        await db.execute(delete(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.id == doc_file.id))
        await db.commit()
        
        return {"status": "deleted", "document_number": document_number}
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# ========== API для управления поверками оборудования ==========

@app.get("/api/verification-equipment")
async def get_verification_equipment(
    days_before_expiry: Optional[int] = None,  # Предупреждение за N дней до истечения
    equipment_type: Optional[str] = None,  # Фильтр по типу
    is_active: Optional[bool] = True,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить список оборудования для поверок"""
    try:
        query = select(VerificationEquipment)
        
        if is_active is not None:
            query = query.where(VerificationEquipment.is_active == (1 if is_active else 0))
        
        if equipment_type:
            query = query.where(VerificationEquipment.equipment_type == equipment_type)
        
        if days_before_expiry is not None:
            today = date.today()
            warning_date = today + timedelta(days=days_before_expiry)
            query = query.where(
                VerificationEquipment.next_verification_date <= warning_date,
                VerificationEquipment.next_verification_date >= today
            )
        
        # Сортировка с учетом NULL значений (NULLS LAST)
        result = await db.execute(query.order_by(nulls_last(VerificationEquipment.next_verification_date)))
        items = result.scalars().all()
        
        return [{
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "category": item.category,
            "serial_number": item.serial_number,
            "manufacturer": item.manufacturer,
            "model": item.model,
            "inventory_number": item.inventory_number,
            "verification_date": item.verification_date.isoformat() if item.verification_date else None,
            "next_verification_date": item.next_verification_date.isoformat() if item.next_verification_date else None,
            "verification_certificate_number": item.verification_certificate_number,
            "verification_organization": item.verification_organization,
            "scan_file_path": item.scan_file_path,
            "scan_file_name": item.scan_file_name,
            "is_active": bool(item.is_active),
            "notes": item.notes,
            "days_until_expiry": (item.next_verification_date - date.today()).days if item.next_verification_date else None,
            "is_expired": item.next_verification_date < date.today() if item.next_verification_date else False,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        } for item in items]
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_verification_equipment: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении оборудования для поверок: {error_detail}")

@app.post("/api/verification-equipment")
async def create_verification_equipment(
    name: str = Form(...),
    equipment_type: str = Form(...),
    serial_number: str = Form(...),
    verification_date: str = Form(...),
    next_verification_date: str = Form(...),
    category: Optional[str] = Form(None),
    manufacturer: Optional[str] = Form(None),
    model: Optional[str] = Form(None),
    inventory_number: Optional[str] = Form(None),
    verification_certificate_number: Optional[str] = Form(None),
    verification_organization: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    scan_file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Создать новое оборудование для поверки"""
    try:
        # Проверка прав (только admin, chief_operator, operator)
        if current_user.get("role") not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        new_id = uuid_lib.uuid4()
        scan_file_path = None
        scan_file_name = None
        scan_file_size = None
        scan_mime_type = None
        
        if scan_file:
            upload_dir = Path("/app/uploads/verification_scans") / str(new_id)
            upload_dir.mkdir(parents=True, exist_ok=True)
            
            file_ext = Path(scan_file.filename).suffix
            file_name = f"{uuid_lib.uuid4()}{file_ext}"
            file_path = upload_dir / file_name
            
            content = await scan_file.read()
            with open(file_path, "wb") as f:
                f.write(content)
            
            scan_file_path = str(file_path)
            scan_file_name = scan_file.filename
            scan_file_size = len(content)
            scan_mime_type = scan_file.content_type
        
        verification_date_obj = datetime.strptime(verification_date, "%Y-%m-%d").date()
        next_verification_date_obj = datetime.strptime(next_verification_date, "%Y-%m-%d").date()
        
        new_equipment = VerificationEquipment(
            id=new_id,
            name=name,
            equipment_type=equipment_type,
            category=category,
            serial_number=serial_number,
            manufacturer=manufacturer,
            model=model,
            inventory_number=inventory_number,
            verification_date=verification_date_obj,
            next_verification_date=next_verification_date_obj,
            verification_certificate_number=verification_certificate_number,
            verification_organization=verification_organization,
            scan_file_path=scan_file_path,
            scan_file_name=scan_file_name,
            scan_file_size=scan_file_size,
            scan_mime_type=scan_mime_type,
            notes=notes
        )
        
        db.add(new_equipment)
        await db.commit()
        await db.refresh(new_equipment)
        
        return {
            "id": str(new_equipment.id),
            "name": new_equipment.name,
            "equipment_type": new_equipment.equipment_type,
            "serial_number": new_equipment.serial_number,
            "next_verification_date": new_equipment.next_verification_date.isoformat(),
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Неверный формат даты: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/verification-equipment/{equipment_id}")
async def get_verification_equipment_by_id(
    equipment_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить оборудование для поверки по ID"""
    try:
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Получить историю поверок
        history_result = await db.execute(
            select(VerificationHistory)
            .where(VerificationHistory.verification_equipment_id == item.id)
            .order_by(VerificationHistory.verification_date.desc())
        )
        history = history_result.scalars().all()
        
        return {
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "category": item.category,
            "serial_number": item.serial_number,
            "manufacturer": item.manufacturer,
            "model": item.model,
            "inventory_number": item.inventory_number,
            "verification_date": item.verification_date.isoformat() if item.verification_date else None,
            "next_verification_date": item.next_verification_date.isoformat() if item.next_verification_date else None,
            "verification_certificate_number": item.verification_certificate_number,
            "verification_organization": item.verification_organization,
            "scan_file_path": item.scan_file_path,
            "scan_file_name": item.scan_file_name,
            "scan_file_size": item.scan_file_size,
            "scan_mime_type": item.scan_mime_type,
            "is_active": bool(item.is_active),
            "notes": item.notes,
            "days_until_expiry": (item.next_verification_date - date.today()).days if item.next_verification_date else None,
            "is_expired": item.next_verification_date < date.today() if item.next_verification_date else False,
            "history": [{
                "id": str(h.id),
                "verification_date": h.verification_date.isoformat(),
                "next_verification_date": h.next_verification_date.isoformat(),
                "certificate_number": h.certificate_number,
                "verification_organization": h.verification_organization,
                "scan_file_path": h.scan_file_path,
                "scan_file_name": h.scan_file_name,
                "notes": h.notes,
                "created_at": h.created_at.isoformat() if h.created_at else None,
            } for h in history],
            "created_at": item.created_at.isoformat() if item.created_at else None,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/api/verification-equipment/{equipment_id}")
async def update_verification_equipment(
    equipment_id: str,
    name: Optional[str] = Form(None),
    equipment_type: Optional[str] = Form(None),
    serial_number: Optional[str] = Form(None),
    verification_date: Optional[str] = Form(None),
    next_verification_date: Optional[str] = Form(None),
    category: Optional[str] = Form(None),
    manufacturer: Optional[str] = Form(None),
    model: Optional[str] = Form(None),
    inventory_number: Optional[str] = Form(None),
    verification_certificate_number: Optional[str] = Form(None),
    verification_organization: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    is_active: Optional[bool] = Form(None),
    scan_file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Обновить оборудование для поверки"""
    try:
        if current_user.get("role") not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Сохранить старую запись в историю, если изменилась дата поверки
        if verification_date and item.verification_date:
            old_date = item.verification_date
            new_date = datetime.strptime(verification_date, "%Y-%m-%d").date()
            if old_date != new_date:
                history_entry = VerificationHistory(
                    verification_equipment_id=item.id,
                    verification_date=old_date,
                    next_verification_date=item.next_verification_date,
                    certificate_number=item.verification_certificate_number,
                    verification_organization=item.verification_organization,
                    scan_file_path=item.scan_file_path,
                    scan_file_name=item.scan_file_name,
                    notes=item.notes
                )
                if "id" in current_user:
                    history_entry.created_by = uuid_lib.UUID(current_user["id"])
                db.add(history_entry)
        
        if name is not None:
            item.name = name
        if equipment_type is not None:
            item.equipment_type = equipment_type
        if category is not None:
            item.category = category
        if serial_number is not None:
            item.serial_number = serial_number
        if manufacturer is not None:
            item.manufacturer = manufacturer
        if model is not None:
            item.model = model
        if inventory_number is not None:
            item.inventory_number = inventory_number
        if verification_date is not None:
            item.verification_date = datetime.strptime(verification_date, "%Y-%m-%d").date()
        if next_verification_date is not None:
            item.next_verification_date = datetime.strptime(next_verification_date, "%Y-%m-%d").date()
        if verification_certificate_number is not None:
            item.verification_certificate_number = verification_certificate_number
        if verification_organization is not None:
            item.verification_organization = verification_organization
        if notes is not None:
            item.notes = notes
        if is_active is not None:
            item.is_active = 1 if is_active else 0
        
        if scan_file:
            # Удалить старый файл, если есть
            if item.scan_file_path and os.path.exists(item.scan_file_path):
                try:
                    os.remove(item.scan_file_path)
                except:
                    pass
            
            upload_dir = Path("/app/uploads/verification_scans") / str(item.id)
            upload_dir.mkdir(parents=True, exist_ok=True)
            
            file_ext = Path(scan_file.filename).suffix
            file_name = f"{uuid_lib.uuid4()}{file_ext}"
            file_path = upload_dir / file_name
            
            content = await scan_file.read()
            with open(file_path, "wb") as f:
                f.write(content)
            
            item.scan_file_path = str(file_path)
            item.scan_file_name = scan_file.filename
            item.scan_file_size = len(content)
            item.scan_mime_type = scan_file.content_type
        
        await db.commit()
        await db.refresh(item)
        
        return {
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "next_verification_date": item.next_verification_date.isoformat(),
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Неверный формат: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/verification-equipment/{equipment_id}")
async def delete_verification_equipment(
    equipment_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Удалить оборудование для поверки"""
    try:
        if current_user.get("role") not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Удалить файл скана, если есть
        if item.scan_file_path and os.path.exists(item.scan_file_path):
            try:
                os.remove(item.scan_file_path)
            except:
                pass
        
        await db.delete(item)
        await db.commit()
        
        return {"status": "deleted", "id": equipment_id}
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/verification-equipment/{equipment_id}/scan")
async def get_verification_scan(
    equipment_id: str,
    inline: bool = False,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить скан свидетельства о поверке"""
    try:
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item or not item.scan_file_path:
            raise HTTPException(status_code=404, detail="Скан не найден")
        
        if not os.path.exists(item.scan_file_path):
            raise HTTPException(status_code=404, detail="Файл не найден на сервере")
        
        from fastapi.responses import StreamingResponse
        
        def iterfile():
            with open(item.scan_file_path, mode="rb") as file_like:
                yield from file_like
        
        headers = {}
        if inline:
            headers["Content-Disposition"] = f'inline; filename="{item.scan_file_name or "scan.pdf"}"'
        else:
            headers["Content-Disposition"] = f'attachment; filename="{item.scan_file_name or "scan.pdf"}"'
        
        return StreamingResponse(
            iterfile(),
            media_type=item.scan_mime_type or "application/pdf",
            headers=headers
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/inspections/{inspection_id}/equipment")
async def add_equipment_to_inspection(
    inspection_id: str,
    equipment_data: dict,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Добавить используемое оборудование для поверок к обследованию"""
    try:
        # Проверка существования обследования
        insp_uuid = uuid_lib.UUID(inspection_id)
        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        
        if not inspection:
            raise HTTPException(status_code=404, detail="Обследование не найдено")
        
        # Проверка прав
        user_result = await db.execute(select(User).where(User.username == current_user["username"]))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        
        if user.role not in ["admin", "chief_operator", "operator", "engineer"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        # Если engineer, проверяем, что это его обследование
        if user.role == "engineer" and inspection.inspector_id != user.id:
            raise HTTPException(status_code=403, detail="Можно добавлять оборудование только к своим обследованиям")
        
        # Получаем список ID оборудования для поверок
        equipment_ids = equipment_data.get("verification_equipment_ids", [])
        if not isinstance(equipment_ids, list):
            raise HTTPException(status_code=400, detail="verification_equipment_ids должен быть списком")
        
        added = []
        for eq_id in equipment_ids:
            try:
                eq_uuid = uuid_lib.UUID(eq_id)
                # Проверяем существование оборудования
                eq_result = await db.execute(
                    select(VerificationEquipment).where(VerificationEquipment.id == eq_uuid)
                )
                ver_eq = eq_result.scalar_one_or_none()
                
                if not ver_eq:
                    continue
                
                # Проверяем, не добавлено ли уже
                existing = await db.execute(
                    select(InspectionEquipment).where(
                        InspectionEquipment.inspection_id == insp_uuid,
                        InspectionEquipment.verification_equipment_id == eq_uuid
                    )
                )
                if existing.scalar_one_or_none():
                    continue
                
                # Создаем связь
                inspection_equipment = InspectionEquipment(
                    inspection_id=insp_uuid,
                    verification_equipment_id=eq_uuid
                )
                db.add(inspection_equipment)
                added.append(str(eq_id))
            except ValueError:
                continue
        
        await db.commit()
        
        return {
            "status": "success",
            "inspection_id": inspection_id,
            "equipment_added": len(added),
            "equipment_ids": added
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/inspections/{inspection_id}/equipment")
async def get_inspection_equipment(
    inspection_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить список используемого оборудования для обследования"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        
        result = await db.execute(
            select(InspectionEquipment, VerificationEquipment)
            .join(VerificationEquipment, InspectionEquipment.verification_equipment_id == VerificationEquipment.id)
            .where(InspectionEquipment.inspection_id == insp_uuid)
        )
        items = result.all()
        
        equipment_list = []
        for ie, ve in items:
            equipment_list.append({
                "id": str(ve.id),
                "name": ve.name,
                "equipment_type": ve.equipment_type,
                "serial_number": ve.serial_number,
                "manufacturer": ve.manufacturer,
                "model": ve.model,
                "verification_date": ve.verification_date.isoformat() if ve.verification_date else None,
                "next_verification_date": ve.next_verification_date.isoformat() if ve.next_verification_date else None,
                "verification_certificate_number": ve.verification_certificate_number,
                "verification_organization": ve.verification_organization,
                "scan_file_path": ve.scan_file_path,
                "scan_file_name": ve.scan_file_name,
                "is_expired": ve.next_verification_date < date.today() if ve.next_verification_date else False,
            })
        
        return equipment_list
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/verification-equipment/export")
async def export_verification_equipment(
    format: str = "csv",  # csv или excel
    days_before_expiry: Optional[int] = None,
    equipment_type: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Экспорт списка оборудования для поверок"""
    try:
        query = select(VerificationEquipment).where(VerificationEquipment.is_active == 1)
        
        if equipment_type:
            query = query.where(VerificationEquipment.equipment_type == equipment_type)
        
        if days_before_expiry is not None:
            today = date.today()
            warning_date = today + timedelta(days=days_before_expiry)
            query = query.where(
                VerificationEquipment.next_verification_date <= warning_date,
                VerificationEquipment.next_verification_date >= today
            )
        
        result = await db.execute(query.order_by(VerificationEquipment.next_verification_date))
        items = result.scalars().all()
        
        if format.lower() == "csv":
            import csv
            import io
            
            output = io.StringIO()
            writer = csv.writer(output)
            
            # Заголовки
            writer.writerow([
                'Название', 'Тип', 'Категория', 'Серийный номер', 'Производитель', 'Модель',
                'Инвентарный номер', 'Дата поверки', 'Следующая поверка', 'Номер свидетельства',
                'Организация поверки', 'Статус', 'Дней до истечения'
            ])
            
            # Данные
            for item in items:
                days = (item.next_verification_date - date.today()).days if item.next_verification_date else None
                status = "Просрочено" if (item.next_verification_date and item.next_verification_date < date.today()) else (
                    f"Предупреждение ({days} дн.)" if days and days <= 30 else "Активно"
                )
                writer.writerow([
                    item.name or '',
                    item.equipment_type or '',
                    item.category or '',
                    item.serial_number or '',
                    item.manufacturer or '',
                    item.model or '',
                    item.inventory_number or '',
                    item.verification_date.strftime('%d.%m.%Y') if item.verification_date else '',
                    item.next_verification_date.strftime('%d.%m.%Y') if item.next_verification_date else '',
                    item.verification_certificate_number or '',
                    item.verification_organization or '',
                    status,
                    str(days) if days is not None else '',
                ])
            
            csv_content = output.getvalue()
            output.close()
            
            from fastapi.responses import Response
            return Response(
                content='\ufeff' + csv_content,
                media_type='text/csv; charset=utf-8',
                headers={'Content-Disposition': f'attachment; filename="verification_equipment_{date.today().isoformat()}.csv"'}
            )
        else:
            raise HTTPException(status_code=400, detail="Неподдерживаемый формат экспорта")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)




