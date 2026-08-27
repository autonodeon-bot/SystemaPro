"""
Сбор и нормализация вложений для генерации отчётов (фото документов, чертежи, замеры).
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set

_VIEW_URL_RE = re.compile(
    r"^/api/questionnaires/([0-9a-fA-F-]{36})/documents/([^/]+)/view$"
)


def _append_file(
    files: List[Dict[str, Any]],
    existing_dn: Set[str],
    document_number: str,
    file_path: str,
    file_name: Optional[str] = None,
    resolve_fn: Optional[Callable[[str], Optional[str]]] = None,
) -> None:
    dn = str(document_number or "").strip()
    fp = str(file_path or "").strip()
    if not dn or not fp or dn in existing_dn:
        return
    if resolve_fn:
        fp = resolve_fn(fp) or fp
    files.append(
        {
            "document_number": dn,
            "file_name": file_name or os.path.basename(fp),
            "file_path": fp,
        }
    )
    existing_dn.add(dn)


def _alias_doc_number_keys(files: List[Dict[str, Any]]) -> None:
    """Дублируем ключи вида 15_0 -> 15 для вставки сканов в отчёт."""
    extra: List[Dict[str, Any]] = []
    have = {str(f.get("document_number")) for f in files if f.get("document_number")}
    for f in files:
        dn = str(f.get("document_number") or "")
        if not dn:
            continue
        base = dn.split("_", 1)[0]
        if base.isdigit() and base not in have:
            extra.append({**f, "document_number": base})
            have.add(base)
        if dn.startswith("doc_"):
            alt = dn[4:]
            if alt and alt not in have:
                extra.append({**f, "document_number": alt})
                have.add(alt)
    files.extend(extra)


def enrich_document_files_from_inspection(
    document_files: List[Dict[str, Any]],
    inspection_data: Optional[Dict[str, Any]],
    *,
    resolve_fn: Optional[Callable[[str], Optional[str]]] = None,
    questionnaire_id: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Дополнить список вложений данными из inspection.data (мобильная синхронизация)."""
    result = list(document_files or [])
    existing_dn = {str(f.get("document_number")) for f in result if f.get("document_number")}
    data = inspection_data if isinstance(inspection_data, dict) else {}

    structured = data.get("document_files")
    if isinstance(structured, dict):
        for key, val in structured.items():
            if isinstance(val, dict):
                fp = val.get("file_path") or val.get("path")
                fn = val.get("file_name")
            else:
                fp = val
                fn = None
            if isinstance(fp, str) and fp.strip():
                _append_file(result, existing_dn, str(key), fp, fn, resolve_fn)

    add = data.get("additional_data")
    if isinstance(add, dict):
        for i, path in enumerate(add.get("object_photos") or []):
            if isinstance(path, str) and path.strip():
                _append_file(result, existing_dn, f"object_photo_{i}", path, resolve_fn=resolve_fn)

    for key in ("factory_plate_photo", "control_scheme_image", "factory_plate", "control_scheme"):
        if key not in existing_dn and data.get(key):
            _append_file(result, existing_dn, key, str(data[key]), resolve_fn=resolve_fn)

    vd = data.get("visual_defects")
    if isinstance(vd, list):
        for i, d in enumerate(vd):
            if not isinstance(d, dict):
                continue
            for j, ph in enumerate(d.get("photos") or []):
                if isinstance(ph, str) and ph.strip():
                    _append_file(result, existing_dn, f"vd_{i}_{j}", ph, resolve_fn=resolve_fn)

    thickness = data.get("thickness_measurements") or data.get("thicknessMeasurements")
    if isinstance(thickness, list):
        for i, t in enumerate(thickness):
            if not isinstance(t, dict):
                continue
            for j, ph in enumerate(t.get("photos") or []):
                if isinstance(ph, str) and ph.strip():
                    _append_file(result, existing_dn, f"uzt_point_{i}_{j}", ph, resolve_fn=resolve_fn)

    uzt_schemes = data.get("uzt_schemes")
    if isinstance(uzt_schemes, list):
        for i, scheme in enumerate(uzt_schemes):
            if not isinstance(scheme, dict):
                continue
            sp = scheme.get("scheme_image_path")
            if isinstance(sp, str) and sp.strip():
                _append_file(result, existing_dn, f"uzt_scheme_{i}", sp, resolve_fn=resolve_fn)
            measurements = scheme.get("measurements") or []
            if isinstance(measurements, list):
                for j, m in enumerate(measurements):
                    if not isinstance(m, dict):
                        continue
                    for k, ph in enumerate(m.get("photos") or []):
                        if isinstance(ph, str) and ph.strip():
                            _append_file(
                                result,
                                existing_dn,
                                f"uzt_scheme_{i}_point_{j}_{k}",
                                ph,
                                resolve_fn=resolve_fn,
                            )

    if questionnaire_id:
        q_root = Path("/app/uploads/questionnaire_documents") / questionnaire_id
        if q_root.is_dir():
            for f in result:
                fp = f.get("file_path")
                if not isinstance(fp, str) or not fp.strip():
                    continue
                m = _VIEW_URL_RE.match(fp.strip())
                if m:
                    doc_num = m.group(2)
                    for hit in q_root.glob(f"doc_{doc_num}_*"):
                        if hit.is_file():
                            f["file_path"] = str(hit.resolve())
                            break

    _alias_doc_number_keys(result)
    return result


def build_attachments_index(document_files: Optional[List[Dict[str, Any]]]) -> Dict[str, str]:
    """Индекс document_number -> file_path с алиасами для номеров документов."""
    attachments: Dict[str, str] = {}
    if not document_files:
        return attachments
    for f in document_files:
        if not isinstance(f, dict):
            continue
        dn = str(f.get("document_number") or "")
        fp = f.get("file_path")
        if dn and isinstance(fp, str) and fp:
            attachments[dn] = fp
    for dn, fp in list(attachments.items()):
        base = dn.split("_", 1)[0]
        if base.isdigit() and base not in attachments:
            attachments[base] = fp
        if dn.startswith("doc_"):
            alt = dn[4:]
            if alt and alt not in attachments:
                attachments[alt] = fp
    return attachments


def pick_equipment_drawing_path(
    rows: List[Dict[str, Any]],
) -> Optional[str]:
    """Выбрать путь к схеме оборудования: приоритет — схема из конструктора."""
    if not rows:
        return None
    constructor: List[str] = []
    others: List[str] = []
    for row in rows:
        path = row.get("image_file_path") or row.get("path")
        if not isinstance(path, str) or not path.strip():
            continue
        desc = str(row.get("description") or "")
        if "vessel_geometry" in desc or "constructor_geometry" in desc:
            constructor.append(path.strip())
        else:
            others.append(path.strip())
    for path in constructor + others:
        p = Path(path)
        if p.is_file():
            return str(p)
        # Docker / локальные варианты
        for base in (
            Path("/app/uploads/equipment_drawings"),
            Path.cwd() / "uploads" / "equipment_drawings",
        ):
            cand = base / p.name
            if cand.is_file():
                return str(cand)
    return (constructor or others or [None])[0]


async def enrich_scheme_from_equipment_templates(
    document_files: List[Dict[str, Any]],
    equipment_id: Optional[str],
    db: Any,
    *,
    resolve_fn: Optional[Callable[[str], Optional[str]]] = None,
    inspection_data: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    """Если в обследовании нет control_scheme_image — взять чертёж оборудования (конструктор)."""
    result = list(document_files or [])
    existing_dn = {str(f.get("document_number")) for f in result if f.get("document_number")}
    scheme_keys = ("control_scheme_image", "control_scheme", "base_vessel_scheme_image")
    if any(k in existing_dn for k in scheme_keys):
        return result

    data = inspection_data if isinstance(inspection_data, dict) else {}
    if any(isinstance(data.get(k), str) and data.get(k).strip() for k in scheme_keys):
        return result
    base = data.get("base_vessel_scheme")
    if isinstance(base, dict):
        bp = base.get("image_path") or base.get("scheme_image_path") or base.get("path")
        if isinstance(bp, str) and bp.strip():
            return result

    if not equipment_id or db is None:
        return result

    try:
        from sqlalchemy import text

        q = await db.execute(
            text(
                """
                SELECT image_file_path, description, updated_at
                FROM drawing_templates
                WHERE equipment_id = CAST(:eid AS uuid)
                  AND is_active = TRUE
                  AND image_file_path IS NOT NULL
                ORDER BY
                  CASE WHEN description LIKE '%%vessel_geometry%%'
                         OR description LIKE '%%constructor_geometry%%'
                       THEN 0 ELSE 1 END,
                  updated_at DESC NULLS LAST
                LIMIT 10
                """
            ),
            {"eid": str(equipment_id)},
        )
        rows = [dict(r) for r in q.mappings().all()]
    except Exception:
        return result

    path = pick_equipment_drawing_path(rows)
    if not path:
        return result
    _append_file(result, existing_dn, "control_scheme_image", path, resolve_fn=resolve_fn)
    return result
