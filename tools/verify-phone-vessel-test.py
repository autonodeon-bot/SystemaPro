"""Read back only the marked test vessel uploaded by the connected engineer."""
import asyncio
import json
from pathlib import Path
from uuid import UUID
from sqlalchemy import select
from database import AsyncSessionLocal, engine
from models import Inspection, User, Report
from form_media_helpers import collect_scheme_paths

async def main():
    state=json.loads(Path('/app/uploads/vessel_v2_acceptance/state.json').read_text())
    async with AsyncSessionLocal() as db:
        user=(await db.execute(select(User).where(User.username=='engineer'))).scalar_one()
        record=(await db.execute(select(Inspection).where(
            Inspection.equipment_id==UUID(state['equipment_id']),
            Inspection.performed_by==user.id).order_by(Inspection.created_at.desc()).limit(1))).scalar_one()
        data=record.data
        g=data['base_vessel_scheme']['geometry']
        assert g['schema_version']==2
        assert len(g['control_points'])==12
        nozzle=next(e for e in g['elements'] if e['kind']=='nozzle')
        assert nozzle['placement']['theta_deg']==45.5
        assert nozzle['placement']['z_local_mm']==500.5
        paths=collect_scheme_paths(data,{})
        assert paths and all(Path(p['path']).is_file() for p in paths), paths
        measured = [m for m in data.get('thickness_measurements',[]) if m.get('thickness') is not None]
        assert len(measured) == 1 and measured[0]['thickness'] == 10.7, measured
        assert len({(m.get('x_percent'),m.get('y_percent')) for m in data['thickness_measurements']}) == 12
        report=(await db.execute(select(Report).where(Report.inspection_id==record.id).order_by(Report.created_at.desc()).limit(1))).scalar_one()
        assert Path(report.file_path).is_file()
        result={'inspection_id':str(record.id),'status':record.status,'points':len(g['control_points']),
                'nozzle_placement':nozzle['placement'],'scheme_files':len(paths),'report':report.file_path,
                'point_ids':[p['id'] for p in g['control_points']],
                'measurement_rows':len(data.get('thickness_measurements',[])),
                'measured_value':measured[0]['thickness'],
                'measured_point_id':measured[0]['scheme_point_id']}
        Path('/app/uploads/vessel_v2_acceptance/phone-result.json').write_text(json.dumps(result,ensure_ascii=False))
        Path('/app/uploads/vessel_v2_acceptance/phone-snapshot.json').write_text(json.dumps(data,ensure_ascii=False))
        print(json.dumps(result,ensure_ascii=False))
    await engine.dispose()

asyncio.run(main())
