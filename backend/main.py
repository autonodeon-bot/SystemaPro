from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
from typing import List, Optional
import os
from database import get_db, engine, Base
from models import Equipment, EquipmentType, PipelineSegment, Inspection

app = FastAPI(
    title="ES TD NGO Platform API",
    description="API для системы учета оборудования и диагностирования",
    version="1.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # В продакшене указать конкретные домены
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    """Initialize database on startup"""
    try:
        # Test database connection
        async with engine.begin() as conn:
            await conn.execute(text("SELECT 1"))
        print("✅ Database connection successful")
    except Exception as e:
        print(f"❌ Database connection failed: {e}")

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

# Equipment endpoints
@app.get("/api/equipment")
async def get_equipment(
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get list of equipment"""
    try:
        result = await db.execute(
            select(Equipment).offset(skip).limit(limit)
        )
        equipment = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(eq.id),
                    "name": eq.name,
                    "type_id": eq.type_id,
                    "serial_number": eq.serial_number,
                    "attributes": eq.attributes,
                }
                for eq in equipment
            ],
            "total": len(equipment)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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
            "type_id": eq.type_id,
            "serial_number": eq.serial_number,
            "attributes": eq.attributes,
            "commissioning_date": str(eq.commissioning_date) if eq.commissioning_date else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get inspections"""
    try:
        query = select(Inspection)
        if equipment_id:
            query = query.where(Inspection.equipment_id == equipment_id)
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        inspections = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(ins.id),
                    "equipment_id": str(ins.equipment_id),
                    "date_performed": ins.date_performed.isoformat() if ins.date_performed else None,
                    "data": ins.data,
                    "conclusion": ins.conclusion,
                    "status": ins.status,
                }
                for ins in inspections
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/inspections")
async def create_inspection(
    inspection_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Create new inspection"""
    try:
        new_inspection = Inspection(
            equipment_id=inspection_data.get("equipment_id"),
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT")
        )
        db.add(new_inspection)
        await db.commit()
        await db.refresh(new_inspection)
        return {
            "id": str(new_inspection.id),
            "status": "created"
        }
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

