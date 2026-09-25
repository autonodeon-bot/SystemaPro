"""Restore a dedicated local audit database into a new, unique database."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from backup import backup_db, backup_dir, get_db_env
from restore import restore_db, restore_dir


def main():
    db = get_db_env()
    if db['host'] not in {'127.0.0.1', 'localhost'} or not db['name'].startswith('systemapro_audit'):
        raise RuntimeError('Only a dedicated local audit database is allowed')
    reports = Path(os.environ['REPORTS_DIR']).resolve()
    root = Path(__file__).resolve().parents[2] / '.venv-audit' / ('restore-smoke-' + uuid.uuid4().hex)
    root.mkdir(parents=True)
    restored_db = {**db, 'name': 'systemapro_audit_restored_' + uuid.uuid4().hex[:10]}
    args = ['-h', db['host'], '-p', db['port'], '-U', db['user']]
    env = {**os.environ, 'PGPASSWORD': db['password']}
    assert backup_db(root, db)
    assert backup_dir(reports, root, 'reports')
    subprocess.run(['createdb', *args, restored_db['name']], check=True, env=env)
    assert restore_db(root, restored_db, False)
    assert restore_dir(root, 'reports', root / 'restored-reports', False)
    query = "SELECT 'equipment', count(*) FROM equipment UNION ALL SELECT 'reports', count(*) FROM reports UNION ALL SELECT 'inspections', count(*) FROM inspections ORDER BY 1"
    def counts(name):
        return subprocess.check_output(['psql', '-X', *args, '-d', name, '-Atc', query], env=env)
    assert counts(db['name']) == counts(restored_db['name'])
    def hashes(directory):
        return {p.relative_to(directory).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in directory.rglob('*') if p.is_file()}
    assert hashes(reports) == hashes(root / 'restored-reports')
    if os.getenv('UPLOADS_DIR'):
        uploads = Path(os.environ['UPLOADS_DIR']).resolve()
        assert backup_dir(uploads, root, 'uploads')
        assert restore_dir(root, 'uploads', root / 'restored-uploads', False)
        assert hashes(uploads) == hashes(root / 'restored-uploads')
        print('PASS: every uploaded attachment SHA256 matches after restoration')
    print('PASS: PostgreSQL dump/restore row counts and every report file SHA256 match')
    print('Isolated restored database:', restored_db['name'])


if __name__ == '__main__':
    main()
