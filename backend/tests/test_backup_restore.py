from scripts.backup import backup_db, backup_dir
from scripts.restore import restore_dir, restore_db


def test_roundtrip_files_and_preserve_previous_target(tmp_path):
    source = tmp_path / 'source'
    source.mkdir()
    (source / 'отчет.pdf').write_bytes(b'%PDF-complete')
    backup = tmp_path / 'backup'
    backup.mkdir()
    assert backup_dir(source, backup, 'reports')
    target = tmp_path / 'restored'
    target.mkdir()
    (target / 'previous.txt').write_text('keep')
    assert restore_dir(backup, 'reports', target, False)
    assert (target / 'отчет.pdf').read_bytes() == b'%PDF-complete'
    assert len(list(tmp_path.glob('restored.previous-*/previous.txt'))) == 1


def test_failed_copy_does_not_remove_existing_data(tmp_path, monkeypatch):
    source = tmp_path / 'backup' / 'reports'
    source.mkdir(parents=True)
    target = tmp_path / 'live'
    target.mkdir()
    (target / 'important').write_text('retained')
    def fail(*args, **kwargs):
        raise OSError('disk full')
    monkeypatch.setattr('scripts.restore.shutil.copytree', fail)
    assert not restore_dir(source.parent, 'reports', target, False)
    assert (target / 'important').read_text() == 'retained'


def test_missing_pg_dump_is_failure(tmp_path, monkeypatch):
    def missing(*args, **kwargs):
        raise FileNotFoundError()
    monkeypatch.setattr('scripts.backup.subprocess.run', missing)
    assert not backup_db(tmp_path, {'password': '', 'host': 'local', 'port': '5432', 'user': 'test', 'name': 'test'})


def test_restore_uses_transaction_and_stops_on_sql_errors(tmp_path, monkeypatch):
    (tmp_path / 'database_dump.sql').write_text('invalid SQL')
    commands = []
    monkeypatch.setattr('scripts.restore.subprocess.run', lambda args, **kw: commands.append(args))
    assert restore_db(tmp_path, {'password': '', 'host': 'local', 'port': '5432', 'user': 'test', 'name': 'test'}, False)
    assert '--single-transaction' in commands[0] and 'ON_ERROR_STOP=1' in commands[0]
