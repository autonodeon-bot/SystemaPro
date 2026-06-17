"""
Шаблоны протоколов «Быстрый контроль» (структура диагностических данных.xlsx).
Идемпотентная загрузка в protocol_templates с полем quick_control_code.
"""
from __future__ import annotations

import json
import logging
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)

# Стабильные id — не менять после выкладки (мобильное кэширование по code).
QC_TEMPLATE_IDS: dict[str, str] = {
    "qc_emergency": "qc-template-emergency",
    "qc_vik": "qc-template-vik",
    "qc_uzt": "qc-template-uzt",
    "qc_uzk": "qc-template-uzk",
    "qc_pvk": "qc-template-pvk",
    "qc_gi": "qc-template-gi",
    "qc_pi": "qc-template-pi",
    "qc_ps_gpm": "qc-template-ps-gpm",
}


def _bid(suffix: str) -> str:
    return f"qc-blk-{suffix}"


def _header_blocks() -> list[dict[str, Any]]:
    return [
        {
            "id": _bid("hdr"),
            "block_type": "section_header",
            "label": "Общие сведения",
            "required": False,
        },
        {
            "id": _bid("date"),
            "block_type": "date_field",
            "label": "Дата",
            "field_key": "date",
            "required": True,
        },
        {
            "id": _bid("location"),
            "block_type": "text_field",
            "label": "Место проведения",
            "field_key": "location",
            "required": False,
            "placeholder": "Площадка, цех, позиция",
        },
        {
            "id": _bid("object"),
            "block_type": "text_field",
            "label": "Объект контроля",
            "field_key": "object_name",
            "required": True,
            "placeholder": "Наименование оборудования",
        },
        {
            "id": _bid("customer"),
            "block_type": "text_field",
            "label": "Заказчик",
            "field_key": "customer",
            "required": False,
        },
        {
            "id": _bid("executor"),
            "block_type": "text_field",
            "label": "Исполнитель",
            "field_key": "executor",
            "required": False,
        },
        {
            "id": _bid("instruments"),
            "block_type": "instruments_field",
            "label": "Средства контроля / приборы",
            "field_key": "instruments",
            "required": False,
        },
    ]


def _build_structures() -> dict[str, dict[str, Any]]:
    """Метаданные и structure для каждого quick_control_code."""
    emergency = {
        "name": "Протокол аварийной ситуации",
        "description": "Аварийный, внеплановый контроль (осмотр). Быстрый контроль.",
        "category": "Аварийный",
        "structure": [
            {
                "id": _bid("em-hdr"),
                "block_type": "section_header",
                "label": "Аварийный протокол",
                "required": False,
            },
            {
                "id": _bid("em-date"),
                "block_type": "date_field",
                "label": "Дата",
                "field_key": "date",
                "required": True,
            },
            {
                "id": _bid("em-loc"),
                "block_type": "text_field",
                "label": "Место",
                "field_key": "location",
                "required": False,
            },
            {
                "id": _bid("em-obj"),
                "block_type": "text_field",
                "label": "Объект",
                "field_key": "object_name",
                "required": True,
            },
            {
                "id": _bid("em-sit"),
                "block_type": "textarea",
                "label": "Описание ситуации",
                "field_key": "situation",
                "required": True,
                "placeholder": "Обстоятельства, характер повреждений",
            },
            {
                "id": _bid("em-act"),
                "block_type": "textarea",
                "label": "Принятые меры",
                "field_key": "actions_taken",
                "required": False,
            },
            {
                "id": _bid("em-ph"),
                "block_type": "photo_section",
                "label": "Фотофиксация",
                "field_key": "photos",
                "required": False,
            },
        ],
    }

    vik_structure = _header_blocks() + [
        {
            "id": _bid("vik-sec"),
            "block_type": "section_header",
            "label": "Визуальный и измерительный контроль (ВИК)",
            "required": False,
        },
        {
            "id": _bid("vik-def"),
            "block_type": "table",
            "label": "Дефекты",
            "field_key": "vik_defects",
            "required": False,
            "columns": [
                {"key": "type", "label": "Тип", "col_type": "text", "required": False},
                {"key": "location", "label": "Место", "col_type": "text", "required": False},
                {"key": "size", "label": "Размер", "col_type": "text", "required": False},
                {"key": "description", "label": "Описание", "col_type": "text", "required": False},
            ],
        },
        {
            "id": _bid("vik-ph"),
            "block_type": "photo_section",
            "label": "Фото / схема ВИК",
            "field_key": "vik_photos",
            "required": False,
        },
        {
            "id": _bid("vik-conc"),
            "block_type": "textarea",
            "label": "Заключение",
            "field_key": "conclusion",
            "required": False,
        },
    ]

    uzt_structure = _header_blocks() + [
        {
            "id": _bid("uzt-sec"),
            "block_type": "section_header",
            "label": "Ультразвуковая толщинометрия (УЗТ)",
            "required": False,
        },
        {
            "id": _bid("uzt-tbl"),
            "block_type": "table",
            "label": "Замеры толщины",
            "field_key": "uzt_measurements",
            "required": False,
            "columns": [
                {"key": "location", "label": "Узел / зона", "col_type": "text", "required": False},
                {"key": "section", "label": "Сечение", "col_type": "text", "required": False},
                {"key": "nominal", "label": "Номинал, мм", "col_type": "text", "required": False},
                {"key": "measured", "label": "Факт, мм", "col_type": "text", "required": False},
            ],
        },
        {
            "id": _bid("uzt-ph"),
            "block_type": "photo_section",
            "label": "Схема / фото замеров",
            "field_key": "uzt_photos",
            "required": False,
        },
        {
            "id": _bid("uzt-conc"),
            "block_type": "textarea",
            "label": "Заключение",
            "field_key": "conclusion",
            "required": False,
        },
    ]

    ndt_method_structure = (
        _header_blocks()
        + [
            {
                "id": _bid("ndt-sec"),
                "block_type": "section_header",
                "label": "Результаты контроля",
                "required": False,
            },
            {
                "id": _bid("ndt-std"),
                "block_type": "text_field",
                "label": "Нормативная документация",
                "field_key": "standard",
                "required": False,
            },
            {
                "id": _bid("ndt-res"),
                "block_type": "textarea",
                "label": "Результаты",
                "field_key": "results",
                "required": False,
            },
            {
                "id": _bid("ndt-def"),
                "block_type": "textarea",
                "label": "Выявленные дефекты",
                "field_key": "defects",
                "required": False,
            },
            {
                "id": _bid("ndt-conc"),
                "block_type": "textarea",
                "label": "Заключение",
                "field_key": "conclusion",
                "required": True,
            },
            {
                "id": _bid("ndt-ph"),
                "block_type": "photo_section",
                "label": "Фото / снимки",
                "field_key": "ndt_photos",
                "required": False,
            },
        ]
    )

    def pressure_structure(test_label: str, test_key: str) -> list[dict[str, Any]]:
        return [
            {
                "id": _bid(f"{test_key}-hdr"),
                "block_type": "section_header",
                "label": test_label,
                "required": False,
            },
            {
                "id": _bid(f"{test_key}-date"),
                "block_type": "date_field",
                "label": "Дата",
                "field_key": "date",
                "required": True,
            },
            {
                "id": _bid(f"{test_key}-loc"),
                "block_type": "text_field",
                "label": "Место",
                "field_key": "location",
                "required": False,
            },
            {
                "id": _bid(f"{test_key}-obj"),
                "block_type": "text_field",
                "label": "Объект",
                "field_key": "object_name",
                "required": True,
            },
            {
                "id": _bid(f"{test_key}-med"),
                "block_type": "text_field",
                "label": "Среда",
                "field_key": "medium",
                "required": False,
            },
            {
                "id": _bid(f"{test_key}-press"),
                "block_type": "number_field",
                "label": "Давление, МПа",
                "field_key": "pressure_mpa",
                "required": False,
            },
            {
                "id": _bid(f"{test_key}-dur"),
                "block_type": "text_field",
                "label": "Длительность выдержки",
                "field_key": "duration",
                "required": False,
            },
            {
                "id": _bid(f"{test_key}-res"),
                "block_type": "textarea",
                "label": "Результат испытания",
                "field_key": "test_result",
                "required": True,
            },
            {
                "id": _bid(f"{test_key}-ph"),
                "block_type": "photo_section",
                "label": "Фотофиксация",
                "field_key": "photos",
                "required": False,
            },
        ]

    ps_gpm = pressure_structure("Испытание ПС и ГПМ", "ps") + [
        {
            "id": _bid("ps-mode"),
            "block_type": "checkbox_list",
            "label": "Режим испытания",
            "field_key": "test_mode",
            "required": False,
            "items": ["Статика", "Динамика"],
        },
    ]

    return {
        "qc_emergency": emergency,
        "qc_vik": {
            "name": "Протокол экспресс-диагностики · ВИК",
            "description": "Быстрый контроль: визуальный и измерительный контроль.",
            "category": "ВИК",
            "structure": vik_structure,
        },
        "qc_uzt": {
            "name": "Протокол экспресс-диагностики · УЗТ",
            "description": "Быстрый контроль: ультразвуковая толщинометрия.",
            "category": "УЗТ",
            "structure": uzt_structure,
        },
        "qc_uzk": {
            "name": "Протокол экспресс-диагностики · УЗК",
            "description": "Быстрый контроль: ультразвуковой контроль.",
            "category": "УЗК",
            "structure": ndt_method_structure,
        },
        "qc_pvk": {
            "name": "Протокол экспресс-диагностики · ПВК",
            "description": "Быстрый контроль: капиллярный / проникающий контроль.",
            "category": "ПВК(МПД)",
            "structure": ndt_method_structure,
        },
        "qc_gi": {
            "name": "Протокол гидравлических испытаний (ГИ)",
            "description": "Быстрый контроль: опрессовка — гидравлические испытания.",
            "category": "ГИ",
            "structure": pressure_structure("Гидравлические испытания (ГИ)", "gi"),
        },
        "qc_pi": {
            "name": "Протокол пневматических испытаний (ПИ)",
            "description": "Быстрый контроль: опрессовка — пневматические испытания.",
            "category": "ПИ",
            "structure": pressure_structure("Пневматические испытания (ПИ)", "pi"),
        },
        "qc_ps_gpm": {
            "name": "Протокол испытания ПС и ГПМ",
            "description": "Быстрый контроль: испытание предохранительных систем и ГПМ.",
            "category": "Испытания",
            "structure": ps_gpm,
        },
    }


async def ensure_quick_control_templates(
    db: AsyncSession,
    created_by: str = "system",
) -> int:
    """
    Создать/обновить опубликованные шаблоны быстрого контроля.
    Возвращает число обработанных записей.
    """
    await db.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS protocol_templates (
                id          TEXT PRIMARY KEY,
                name        TEXT NOT NULL,
                description TEXT,
                category    TEXT,
                structure   JSONB NOT NULL DEFAULT '[]'::JSONB,
                created_by  TEXT,
                created_at  TIMESTAMPTZ DEFAULT NOW(),
                updated_at  TIMESTAMPTZ DEFAULT NOW(),
                is_active   BOOLEAN DEFAULT TRUE,
                status      TEXT NOT NULL DEFAULT 'draft',
                version     INTEGER NOT NULL DEFAULT 1
            )
            """
        )
    )
    await db.execute(
        text(
            "ALTER TABLE protocol_templates "
            "ADD COLUMN IF NOT EXISTS quick_control_code TEXT"
        )
    )
    await db.execute(
        text(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS ux_protocol_templates_qc_code
            ON protocol_templates (quick_control_code)
            WHERE quick_control_code IS NOT NULL
            """
        )
    )

    meta = _build_structures()
    count = 0
    for code, tpl_id in QC_TEMPLATE_IDS.items():
        item = meta.get(code)
        if not item:
            continue
        structure_json = json.dumps(item["structure"], ensure_ascii=False)
        await db.execute(
            text(
                """
                INSERT INTO protocol_templates (
                    id, name, description, category, structure,
                    created_by, is_active, status, version, quick_control_code, updated_at
                )
                VALUES (
                    :id, :name, :description, :category, CAST(:structure AS jsonb),
                    :created_by, TRUE, 'published', 1, :qc_code, NOW()
                )
                ON CONFLICT (id) DO UPDATE SET
                    name = EXCLUDED.name,
                    description = EXCLUDED.description,
                    category = EXCLUDED.category,
                    structure = EXCLUDED.structure,
                    is_active = TRUE,
                    status = 'published',
                    quick_control_code = EXCLUDED.quick_control_code,
                    updated_at = NOW()
                """
            ),
            {
                "id": tpl_id,
                "name": item["name"],
                "description": item["description"],
                "category": item["category"],
                "structure": structure_json,
                "created_by": created_by,
                "qc_code": code,
            },
        )
        count += 1

    await db.commit()
    logger.info("Quick control protocol templates ensured: %s", count)
    return count


async def list_quick_control_codes(db: AsyncSession) -> list[str]:
    result = await db.execute(
        text(
            """
            SELECT quick_control_code FROM protocol_templates
            WHERE quick_control_code IS NOT NULL AND is_active = TRUE
              AND status = 'published'
            ORDER BY quick_control_code
            """
        )
    )
    return [str(r[0]) for r in result.fetchall() if r[0]]
