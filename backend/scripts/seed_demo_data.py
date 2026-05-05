"""
Демо-данные для стенда «Монитор»: иерархия, ОПО, оборудование, люди, задания,
обследования с дефектами для ведомости, поверочные приборы, реестр приборов,
шаблоны чертежей, шаблон отчёта в БД, опционально протокол.

Запуск (из каталога backend, с настроенным .env / переменными БД):
  python scripts/seed_demo_data.py

Идемпотентность: повторный запуск обновляет те же сущности по стабильным UUID (uuid5).
"""
from __future__ import annotations

import asyncio
import os
import sys
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path

# корень backend в PYTHONPATH
_ROOT = Path(__file__).resolve().parents[1]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from auth import hash_password
from database import AsyncSessionLocal
from models import (
    Assignment,
    Branch,
    Certification,
    Client,
    DrawingTemplate,
    DrawingTemplatePoint,
    Engineer,
    Enterprise,
    Equipment,
    EquipmentType,
    Inspection,
    NDTMethod,
    Opo,
    PipelineSegment,
    Project,
    Questionnaire,
    RegulatoryDocument,
    Report,
    ReportTemplate,
    User,
    UserEquipmentAccess,
    VerificationEquipment,
    Workshop,
)

_NS = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")


def _u(key: str) -> uuid.UUID:
    return uuid.uuid5(_NS, f"demo:{key}")


def _png_bytes() -> bytes:
    """Минимальный валидный PNG 1×1 (прозрачный)."""
    return (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
        b"\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01"
        b"\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
    )


def _drawing_upload_path() -> Path:
    """Совпадает с логикой drawing_templates_api (Docker / локально)."""
    primary = Path("/app/uploads/equipment_drawings")
    try:
        primary.mkdir(parents=True, exist_ok=True)
        return primary
    except Exception:
        fallback = Path.cwd() / "uploads" / "equipment_drawings"
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


async def _merge(session: AsyncSession, obj) -> None:
    await session.merge(obj)


async def seed(session: AsyncSession) -> None:
    pwd = os.getenv("SEED_DEMO_PASSWORD", "Demo2026!Seed")
    ph = hash_password(pwd)

    # --- Клиент / предприятие / филиал / цех / ОПО ---
    client = Client(
        id=_u("client"),
        name="Демо-клиент ООО «ТестНефть»",
        inn="7700000000",
        address="г. Тюмень, ул. Демо, 1",
        contact_person="Иванов И.И.",
        phone="+7 (3452) 00-00-00",
        email="demo.client@example.com",
    )
    await _merge(session, client)

    ent = Enterprise(
        id=_u("enterprise"),
        name="Демо предприятие «ЕС ТД НГО»",
        code="DEMO-ENT",
        description="Синтетические данные для проверки UI и мобильного клиента",
        client_id=client.id,
    )
    await _merge(session, ent)

    br = Branch(
        id=_u("branch"),
        enterprise_id=ent.id,
        name="Демо-филиал Запад",
        code="DEMO-BR-01",
    )
    await _merge(session, br)

    ws = Workshop(
        id=_u("workshop"),
        branch_id=br.id,
        name="Цех диагностики №1",
        code="DEMO-WS-01",
    )
    await _merge(session, ws)

    opo = Opo(
        id=_u("opo"),
        enterprise_id=ent.id,
        branch_id=br.id,
        workshop_id=ws.id,
        name="Демо ОПО «Установка подготовки газа»",
        code="DEMO-OPO-001",
        hazard_class="II",
        registration_number="РН-ДЕМО-001",
        survey_data={"organization": {"name": ent.name}, "documents": {"1": "Паспорт ОПО"}},
    )
    await _merge(session, opo)

    # --- Типы оборудования ---
    et_vessel = EquipmentType(
        id=_u("etype_vessel"),
        name="Сосуд под давлением (демо)",
        code="DEMO_VESSEL",
        description="Тип для демо-сосуда",
    )
    et_pipe = EquipmentType(
        id=_u("etype_pipeline"),
        name="Трубопровод (демо)",
        code="DEMO_PIPELINE",
        description="Тип для демо-трубопровода",
    )
    await _merge(session, et_vessel)
    await _merge(session, et_pipe)

    regdoc = RegulatoryDocument(
        id=_u("regdoc_gost"),
        document_type="GOST",
        number="14249-2014",
        name="ГОСТ 14249-2014 (демо в сидере)",
        description="Нормативный документ для проверки справочников",
        is_active=True,
    )
    await _merge(session, regdoc)

    # --- Оборудование ---
    eq_vessel = Equipment(
        id=_u("equipment_vessel"),
        equipment_code="DEMO-EQ-V-001",
        type_id=et_vessel.id,
        workshop_id=ws.id,
        opo_id=opo.id,
        name="Сосуд демо-001 (ВКГ)",
        serial_number="SN-V-2026-001",
        location="Площадка А, поз. 3",
        manufacturer="ОМЗ",
        model="ВКГ-25",
        commissioning_date=date(2018, 6, 1),
        attributes={"coordinates": [65.0, 55.0], "object_type": "vessel"},
    )
    eq_pipe = Equipment(
        id=_u("equipment_pipeline"),
        equipment_code="DEMO-EQ-P-001",
        type_id=et_pipe.id,
        workshop_id=ws.id,
        opo_id=opo.id,
        name="Трубопровод демо-001",
        serial_number="SN-P-2026-001",
        location="Эстакада Б",
        manufacturer="—",
        model="—",
        commissioning_date=date(2015, 3, 15),
        attributes={
            "coordinates": [[65.01, 55.01], [65.02, 55.02]],
            "object_type": "pipeline",
        },
    )
    await _merge(session, eq_vessel)
    await _merge(session, eq_pipe)

    # --- Инженеры и пользователи ---
    eng1 = Engineer(
        id=_u("engineer1"),
        full_name="Петров Пётр Петрович",
        position="Инженер НК II уровня",
        phone="+7 900 111-22-33",
        email="demo.engineer@example.com",
        qualifications={"vik": "II", "uzt": "II"},
        equipment_types={"codes": ["DEMO_VESSEL", "DEMO_PIPELINE"]},
    )
    eng2 = Engineer(
        id=_u("engineer2"),
        full_name="Сидоров Сидор Сидорович",
        position="Инженер НК III уровня",
        phone="+7 900 444-55-66",
        email="demo.engineer2@example.com",
    )
    await _merge(session, eng1)
    await _merge(session, eng2)

    u_eng = User(
        id=_u("user_engineer"),
        username="demo.engineer",
        password_hash=ph,
        email="demo.engineer@example.com",
        full_name=eng1.full_name,
        role="engineer",
        engineer_id=eng1.id,
        is_active=True,
    )
    u_eng2 = User(
        id=_u("user_engineer2"),
        username="demo.engineer2",
        password_hash=ph,
        email="demo.engineer2@example.com",
        full_name=eng2.full_name,
        role="engineer",
        engineer_id=eng2.id,
        is_active=True,
    )
    u_chief = User(
        id=_u("user_chief"),
        username="demo.chief",
        password_hash=ph,
        email="demo.chief@example.com",
        full_name="Старший оператор Демо",
        role="chief_operator",
        is_active=True,
    )
    u_op = User(
        id=_u("user_operator"),
        username="demo.operator",
        password_hash=ph,
        email="demo.operator@example.com",
        full_name="Оператор Демо",
        role="operator",
        is_active=True,
    )
    u_client = User(
        id=_u("user_client"),
        username="demo.client",
        password_hash=ph,
        email="demo.client@example.com",
        full_name="Клиент Демо",
        role="client",
        client_id=client.id,
        is_active=True,
    )
    await _merge(session, u_eng)
    await _merge(session, u_eng2)
    await _merge(session, u_chief)
    await _merge(session, u_op)
    await _merge(session, u_client)

    uea_v = UserEquipmentAccess(
        id=_u("uea_client_vessel"),
        user_id=u_client.id,
        equipment_id=eq_vessel.id,
        access_type="READ",
        granted_by=u_chief.id,
    )
    uea_p = UserEquipmentAccess(
        id=_u("uea_client_pipe"),
        user_id=u_client.id,
        equipment_id=eq_pipe.id,
        access_type="READ",
        granted_by=u_chief.id,
    )
    await _merge(session, uea_v)
    await _merge(session, uea_p)

    # Сертификат для ведомости специалистов / отчёта
    cert = Certification(
        id=_u("cert1"),
        engineer_id=eng1.id,
        certification_type="НК",
        certificate_number="НК-II-ДЕМО-001",
        method_code="VIK",
        issue_date=date(2024, 1, 10),
        expiry_date=date(2029, 1, 10),
        issuing_organization="АЦ НК Демо",
        equipment_type_id=et_vessel.id,
        is_active=True,
    )
    await _merge(session, cert)

    # --- Проект ---
    proj = Project(
        id=_u("project"),
        client_id=client.id,
        name="Демо-проект диагностики 2026",
        description="Полный набор заданий и обследований",
        start_date=date(2026, 1, 1),
        end_date=date(2026, 12, 31),
        status="IN_PROGRESS",
    )
    await _merge(session, proj)

    # --- Поверочное оборудование ---
    ve1 = VerificationEquipment(
        id=_u("ver_eq1"),
        equipment_type="УЗТ",
        category="Ультразвук",
        serial_number="VE-UZT-001",
        manufacturer="Olympus",
        model="38DL PLUS",
        verification_date=date(2025, 6, 1),
        next_verification_date=date(2026, 6, 1),
        verification_certificate_number="ПОВ-2025-001",
        verification_organization="Росаккредитация Демо",
        name="Толщиномер УЗТ",
        is_active=True,
    )
    ve2 = VerificationEquipment(
        id=_u("ver_eq2"),
        equipment_type="ВИК",
        category="Визуальный",
        serial_number="VE-VIK-002",
        manufacturer="—",
        model="Набор ВИК",
        verification_date=date(2025, 8, 1),
        next_verification_date=date(2026, 8, 1),
        verification_certificate_number="ПОВ-2025-002",
        verification_organization="Организация Демо",
        name="Комплект ВИК",
        is_active=True,
    )
    await _merge(session, ve1)
    await _merge(session, ve2)

    # --- Реестр приборов (таблица через raw SQL — нет ORM-модели) ---
    await session.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS instrument_registry (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name VARCHAR(255) NOT NULL,
                type VARCHAR(100),
                serial_number VARCHAR(150),
                verification_until VARCHAR(20),
                condition VARCHAR(50) DEFAULT 'ok',
                condition_notes TEXT,
                specialist_id UUID REFERENCES users(id) ON DELETE SET NULL,
                created_by UUID REFERENCES users(id) ON DELETE SET NULL,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                is_deleted BOOLEAN DEFAULT FALSE,
                verification_equipment_id UUID REFERENCES verification_equipment(id) ON DELETE SET NULL
            )
            """
        )
    )
    await session.execute(
        text(
            """
            INSERT INTO instrument_registry (
                id, name, type, serial_number, verification_until, condition,
                specialist_id, created_by, verification_equipment_id, is_deleted
            ) VALUES (
                :id, :name, :type, :sn, :vu, 'ok',
                :spec, :cb, :ve, FALSE
            )
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                type = EXCLUDED.type,
                serial_number = EXCLUDED.serial_number,
                verification_until = EXCLUDED.verification_until,
                specialist_id = EXCLUDED.specialist_id,
                verification_equipment_id = EXCLUDED.verification_equipment_id,
                updated_at = NOW()
            """
        ),
        {
            "id": str(_u("instr1")),
            "name": "Демо-прибор УЗТ-1",
            "type": "УЗТ",
            "sn": "INST-UZT-001",
            "vu": "2026-12",
            "spec": str(u_eng.id),
            "cb": str(u_chief.id),
            "ve": str(ve1.id),
        },
    )

    # --- Задания (все типы из VALID_ASSIGNMENT_TYPES) ---
    types = [
        "DIAGNOSTICS",
        "EXPERTISE",
        "INSPECTION",
        "CHTO",
        "PTO",
        "NVO",
        "NVO_GI",
    ]
    for i, atype in enumerate(types):
        aid = _u(f"assignment_{atype}")
        # Чередуем оборудование
        eq_id = eq_vessel.id if i % 2 == 0 else eq_pipe.id
        a = Assignment(
            id=aid,
            project_id=proj.id,
            equipment_id=eq_id,
            assigned_to=u_eng.id,
            assigned_by=u_chief.id,
            assignment_type=atype,
            due_date=date.today() + timedelta(days=14 + i),
            priority=["LOW", "NORMAL", "HIGH", "URGENT"][i % 4],
            status="IN_PROGRESS" if i < 4 else "PENDING",
            description=f"Демо-задание типа {atype} для проверки списков и мобильного клиента",
        )
        await _merge(session, a)

    q_main = Questionnaire(
        id=_u("questionnaire_main"),
        equipment_id=eq_vessel.id,
        assignment_id=_u("assignment_DIAGNOSTICS"),
        date_performed=datetime.now(timezone.utc),
        performed_by=u_eng.id,
        status="SIGNED",
        data={"demo": True, "section_1": {"object_name": eq_vessel.name}},
        created_by=u_chief.id,
    )
    await _merge(session, q_main)

    # --- Обследование с данными для ведомости дефектов ---
    insp_data = {
        "vessel_name": eq_vessel.name,
        "object_name": eq_vessel.name,
        "equipment_type": "VESSEL",
        "inspection_date": datetime.now(timezone.utc).date().isoformat(),
        "defects": [
            {
                "type": "Коррозия",
                "name": "Коррозия локальная",
                "location": "Шов Б, зона 120°",
                "size": "S = 12 мм",
                "severity": "significant",
                "recommendation": "Зачистка и контроль УЗТ после ремонта",
                "notes": "Демо-запись сида",
            },
            {
                "type": "Риск",
                "name": "Поверхностный риск",
                "location": "Опорный пояс",
                "size": "L = 40 мм",
                "severity": "minor",
                "recommendation": "Контроль на следующем ТО",
                "notes": "",
            },
        ],
        "visual_defects": [
            {
                "defect_type": "Вмятина",
                "location": "Корпус верх",
                "size": "2 мм",
                "description": "Демо для мобильного/отчёта",
                "photos": [],
            }
        ],
    }
    inspection = Inspection(
        id=_u("inspection_main"),
        project_id=proj.id,
        equipment_id=eq_vessel.id,
        assignment_id=_u("assignment_DIAGNOSTICS"),
        questionnaire_id=q_main.id,
        inspector_id=u_eng.id,
        performed_by=u_eng.id,
        date_performed=datetime.now(timezone.utc),
        inspection_type="NDT",
        inspection_method="VIK",
        inspection_category="Демо",
        status="SIGNED",
        conclusion="Демо: выявлены дефекты, эксплуатация с ограничениями не рассматривается (тестовые данные).",
        data=insp_data,
    )
    await _merge(session, inspection)

    # --- Методы НК привязка к обследованию ---
    ndt1 = NDTMethod(
        id=_u("ndt_vik"),
        inspection_id=inspection.id,
        equipment_id=eq_vessel.id,
        method_code="VIK",
        method_name="Визуально-измерительный контроль",
        is_performed=1,
        standard="ГОСТ Р 55614-2013",
        equipment="Лупа 10×, шаблон сварного шва",
        inspector_name=eng1.full_name,
        inspector_level="II",
        results="Зафиксированы дефекты согласно ведомости",
        defects="Коррозия, риск",
        conclusion="Требуется ремонт зоны коррозии",
        photos=[],
        additional_data={"certificate_number": cert.certificate_number},
        performed_date=datetime.now(timezone.utc),
    )
    ndt2 = NDTMethod(
        id=_u("ndt_uzt"),
        inspection_id=inspection.id,
        equipment_id=eq_vessel.id,
        method_code="UZT",
        method_name="Ультразвуковая толщинометрия",
        is_performed=1,
        standard="ГОСТ Р ИСО 16809",
        equipment="Olympus 38DL PLUS",
        inspector_name=eng1.full_name,
        inspector_level="II",
        results="Толщины в пределах нормы (демо)",
        defects="",
        conclusion="Годен",
        photos=[],
        additional_data={},
        performed_date=datetime.now(timezone.utc),
    )
    await _merge(session, ndt1)
    await _merge(session, ndt2)

    # --- Сегмент трубопровода (карта) ---
    seg = PipelineSegment(
        id=_u("pipe_segment"),
        equipment_id=eq_pipe.id,
        name="Участок демо-001",
        segment_type="main",
        corrosion_rate=Decimal("0.12"),
        thickness=Decimal("8.5"),
        last_inspection_date=date.today() - timedelta(days=30),
        remaining_life=Decimal("12.5"),
    )
    await _merge(session, seg)

    # --- Шаблон чертежа + точки ---
    upload_dir = _drawing_upload_path()
    img_name = f"{_u('drawing_file')}.png"
    img_path = upload_dir / img_name
    img_path.write_bytes(_png_bytes())
    db_image_path = str(img_path).replace("\\", "/")

    dtpl = DrawingTemplate(
        id=_u("drawing_template"),
        name="Демо-схема сосуда (точки УЗТ)",
        description="Сидер: шаблон для проверки web/mobile синхронизации",
        category="vessel",
        equipment_type_id=et_vessel.id,
        equipment_id=None,
        image_file_path=db_image_path,
        image_width=1,
        image_height=1,
        mime_type="image/png",
        file_size=len(_png_bytes()),
        version=1,
        is_active=True,
        created_by=u_chief.id,
    )
    await _merge(session, dtpl)

    p1 = DrawingTemplatePoint(
        id=_u("dt_point1"),
        template_id=dtpl.id,
        label="T1",
        point_type="thickness",
        x_percent=Decimal("25.0"),
        y_percent=Decimal("40.0"),
        expected_value=Decimal("10.0"),
        notes="Демо-точка 1",
        sort_order=0,
    )
    p2 = DrawingTemplatePoint(
        id=_u("dt_point2"),
        template_id=dtpl.id,
        label="T2",
        point_type="thickness",
        x_percent=Decimal("75.0"),
        y_percent=Decimal("55.0"),
        expected_value=Decimal("9.5"),
        notes="Демо-точка 2",
        sort_order=1,
    )
    await _merge(session, p1)
    await _merge(session, p2)

    # --- Шаблон отчёта (БД) ---
    rt = ReportTemplate(
        id=_u("report_template"),
        name="Демо: технический отчёт (все разделы)",
        description="Сидер для страницы «Шаблоны отчётов»",
        template_type="TECHNICAL",
        client_id=None,
        template_config={
            "include_sections": {
                "equipment_info": True,
                "opo_info": True,
                "ndt_methods": True,
                "specialists": True,
                "verification_equipment": True,
                "documents": True,
                "photos": True,
                "control_scheme": True,
            },
            "styles": {"font_family": "Arial", "font_size": 11, "header_color": "#1e40af"},
        },
        is_default=True,
        is_active=True,
        created_by=u_chief.id,
    )
    await _merge(session, rt)

    demo_report = Report(
        id=_u("report_main"),
        inspection_id=inspection.id,
        report_type="TECHNICAL",
        report_number="DEMO-RPT-2026-SEED-001",
        file_path="/demo/reports/placeholder.pdf",
        file_size=1024,
        template_id=rt.id,
        is_signed=True,
        signed_at=datetime.now(timezone.utc),
        signed_by=u_eng.id,
        created_by=u_eng.id,
    )
    await _merge(session, demo_report)

    # --- Протокол (таблица создаётся API при первом обращении; здесь — явно) ---
    await session.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS protocol_templates (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT,
                category TEXT,
                structure JSONB NOT NULL DEFAULT '[]'::JSONB,
                created_by TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                is_active BOOLEAN DEFAULT TRUE,
                status TEXT NOT NULL DEFAULT 'draft',
                version INTEGER NOT NULL DEFAULT 1
            )
            """
        )
    )
    structure = [
        {
            "id": str(_u("proto_block1")),
            "block_type": "section_header",
            "label": "Общие сведения",
            "required": False,
        },
        {
            "id": str(_u("proto_block2")),
            "block_type": "text_field",
            "label": "Объект контроля",
            "field_key": "object_name",
            "required": True,
            "placeholder": "Наименование",
        },
    ]
    import json as _json

    await session.execute(
        text(
            """
            INSERT INTO protocol_templates (id, name, description, category, structure, created_by, is_active, status, version)
            VALUES (:id, :name, :desc, :cat, :structure::jsonb, :cb, TRUE, 'published', 1)
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                description = EXCLUDED.description,
                category = EXCLUDED.category,
                structure = EXCLUDED.structure,
                is_active = TRUE,
                status = 'published',
                updated_at = NOW()
            """
        ),
        {
            "id": str(_u("protocol_template")),
            "name": "Демо-протокол ВИК (сидер)",
            "desc": "Универсальный короткий шаблон для мобильного конструктора",
            "cat": "ВИК",
            "structure": _json.dumps(structure, ensure_ascii=False),
            "cb": "demo.chief",
        },
    )

    await session.commit()


async def verify(session: AsyncSession) -> list[str]:
    """Проверки согласованности FK и обязательных связей."""
    errors: list[str] = []

    r = await session.execute(select(Equipment).where(Equipment.id == _u("equipment_vessel")))
    eq = r.scalar_one_or_none()
    if not eq or eq.workshop_id != _u("workshop"):
        errors.append("equipment_vessel / workshop")

    r = await session.execute(select(Assignment).where(Assignment.id == _u("assignment_DIAGNOSTICS")))
    a = r.scalar_one_or_none()
    if not a or a.equipment_id != _u("equipment_vessel"):
        errors.append("assignment DIAGNOSTICS / equipment")

    r = await session.execute(select(Inspection).where(Inspection.id == _u("inspection_main")))
    ins = r.scalar_one_or_none()
    if not ins or ins.assignment_id != _u("assignment_DIAGNOSTICS"):
        errors.append("inspection / assignment")

    r = await session.execute(select(NDTMethod).where(NDTMethod.inspection_id == _u("inspection_main")))
    if len(r.scalars().all()) < 2:
        errors.append("ndt_methods count")

    r = await session.execute(
        text("SELECT COUNT(*) FROM instrument_registry WHERE id = :id AND is_deleted = FALSE"),
        {"id": str(_u("instr1"))},
    )
    if (r.scalar() or 0) < 1:
        errors.append("instrument_registry")

    r = await session.execute(select(DrawingTemplatePoint).where(DrawingTemplatePoint.template_id == _u("drawing_template")))
    if len(r.scalars().all()) < 2:
        errors.append("drawing_template_points")

    r = await session.execute(select(PipelineSegment).where(PipelineSegment.equipment_id == _u("equipment_pipeline")))
    if not r.scalar_one_or_none():
        errors.append("pipeline_segment")

    r = await session.execute(select(Questionnaire).where(Questionnaire.id == _u("questionnaire_main")))
    if not r.scalar_one_or_none():
        errors.append("questionnaire_main")

    r = await session.execute(select(Report).where(Report.id == _u("report_main")))
    rep = r.scalar_one_or_none()
    if not rep or rep.inspection_id != _u("inspection_main"):
        errors.append("report_main")

    r = await session.execute(select(RegulatoryDocument).where(RegulatoryDocument.id == _u("regdoc_gost")))
    if not r.scalar_one_or_none():
        errors.append("regulatory_document")

    r = await session.execute(
        select(func.count())
        .select_from(UserEquipmentAccess)
        .where(UserEquipmentAccess.user_id == _u("user_client"))
    )
    if (r.scalar() or 0) < 2:
        errors.append("user_equipment_access client")

    return errors


async def _async_main() -> None:
    async with AsyncSessionLocal() as session:
        await seed(session)
        bad = await verify(session)
        if bad:
            print("VERIFY FAILED:", "; ".join(bad))
            raise SystemExit(1)
        print("OK: демо-данные загружены и проверены.")
        print("Учётные записи (пароль из SEED_DEMO_PASSWORD или по умолчанию Demo2026!Seed):")
        print("  demo.engineer / demo.engineer2 / demo.chief / demo.operator / demo.client")


def main() -> None:
    asyncio.run(_async_main())


if __name__ == "__main__":
    main()
