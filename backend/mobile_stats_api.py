"""Mobile app endpoints and platform statistics."""

import os
from datetime import datetime, date
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from auth import verify_token, verify_token_optional
from database import get_db
from models import (
    Certification, Engineer, User,
    Inspection, Report, Assignment,
)
from shared import cert_areas_list

router = APIRouter(tags=["mobile"])

MOBILE_APP_VERSION = os.getenv("MOBILE_APP_VERSION", "3.7.13")
MOBILE_APP_BUILD = os.getenv("MOBILE_APP_BUILD", "49")
MOBILE_APP_DOWNLOAD_URL = os.getenv(
    "MOBILE_APP_DOWNLOAD_URL",
    f"https://neftcontrol.ru/mobile/es-td-ngo-{MOBILE_APP_VERSION}-{MOBILE_APP_BUILD}.apk",
)


@router.get("/api/mobile/version")
async def get_mobile_version():
    """Получить информацию о версии мобильного приложения"""
    return {
        "version": MOBILE_APP_VERSION,
        "build": MOBILE_APP_BUILD,
        "download_url": MOBILE_APP_DOWNLOAD_URL,
        "release_date": datetime.now().isoformat()
    }


@router.get("/api/mobile/sync/engineers-by-ndt")
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
            .where(Certification.is_active == True)
            .where(Engineer.is_active == True)
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
                "certification_areas": cert_areas_list(c),
                "issue_date": str(c.issue_date) if c.issue_date else None,
                "expiry_date": str(c.expiry_date) if c.expiry_date else None,
                "issuing_organization": c.issuing_organization or "",
            })
        return {"items": items, "total": len(items)}
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/vessel-templates/{template_name}")
async def get_vessel_template(
    template_name: str,
    username: str = Depends(verify_token_optional)
):
    """
    Получить шаблон чертежа сосуда.
    template_name: название шаблона (например, 'vessel_template.png')
    """
    try:
        if not template_name.endswith(('.png', '.jpg', '.jpeg')):
            raise HTTPException(status_code=400, detail="Invalid file type")
        
        safe_name = Path(template_name).name
        
        template_path = Path(f"/app/reports/assets/{safe_name}")
        
        if not template_path.exists():
            raise HTTPException(status_code=404, detail="Template not found")
        
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

@router.get("/api/vessel-templates")
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

@router.get("/api/mobile/check-update")
async def check_mobile_update(current_version: str, current_build: str):
    """Проверить наличие обновления для мобильного приложения"""
    try:
        current_v_parts = current_version.split('.')
        server_v_parts = MOBILE_APP_VERSION.split('.')
        
        has_update = False
        version_different = False
        
        for i in range(max(len(current_v_parts), len(server_v_parts))):
            current_v = int(current_v_parts[i]) if i < len(current_v_parts) else 0
            server_v = int(server_v_parts[i]) if i < len(server_v_parts) else 0
            
            if server_v > current_v:
                has_update = True
                version_different = True
                break
            elif server_v < current_v:
                version_different = True
                break
        
        if not version_different:
            try:
                current_b = int(current_build)
                server_b = int(MOBILE_APP_BUILD)
                has_update = server_b > current_b
            except (ValueError, TypeError):
                has_update = False
        
        return {
            "has_update": has_update,
            "current_version": current_version,
            "current_build": current_build,
            "latest_version": MOBILE_APP_VERSION,
            "latest_build": MOBILE_APP_BUILD,
            "download_url": MOBILE_APP_DOWNLOAD_URL if has_update else None,
            "is_latest": not has_update
        }
    except Exception as e:
        return {
            "has_update": False,
            "error": str(e),
            "is_latest": True
        }


@router.get("/api/stats")
async def api_stats(
    days: int = 30,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Панель статистики: обследования, отчёты, задания по периодам."""
    from datetime import timedelta
    cutoff = date.today() - timedelta(days=days)
    ins_res = await db.execute(
        select(func.count(Inspection.id)).where(Inspection.created_at >= cutoff)
    )
    inspections_count = ins_res.scalar() or 0
    rep_res = await db.execute(
        select(func.count(Report.id)).where(Report.created_at >= cutoff)
    )
    reports_count = rep_res.scalar() or 0
    ass_res = await db.execute(
        select(func.count(Assignment.id)).where(Assignment.created_at >= cutoff)
    )
    assignments_count = ass_res.scalar() or 0
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
