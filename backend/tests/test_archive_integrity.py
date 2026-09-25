import hashlib
import io
import json
import zipfile
import pytest
from archive_integrity import verify_inspection_archive
from archive_integrity import archive_upload_identity


def test_upload_identity_ignores_container_but_scopes_owner_and_contents():
    files = {'checklist.json': b'{"status":"DRAFT"}', 'photos/doc.pdf': b'%PDF-1.7'}
    with make_archive(files) as first, make_archive(files) as second:
        assert archive_upload_identity(first, 'user') == archive_upload_identity(second, 'user')
        assert archive_upload_identity(first, 'user') != archive_upload_identity(second, 'other-user')
    with make_archive(files) as first, make_archive({**files, 'checklist.json': b'{"status":"SIGNED"}'}) as changed:
        assert archive_upload_identity(first, 'user') != archive_upload_identity(changed, 'user')


def make_archive(files, hashes=None):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as archive:
        for name, value in files.items():
            archive.writestr(name, value)
        archive.writestr('manifest.json', json.dumps({'version': 2, 'checksums': hashes if hashes is not None else {
            name: hashlib.sha256(value).hexdigest() for name, value in files.items()
        }}))
    stream.seek(0)
    return zipfile.ZipFile(stream)


def test_pdf_and_checklist_checksums():
    with make_archive({'checklist.json': b'{}', 'photos/doc_1.pdf': b'%PDF-1.7'}) as archive:
        assert verify_inspection_archive(archive)['version'] == 2


@pytest.mark.parametrize('name', ['../outside', '/absolute', 'C:/outside', 'photos\\outside'])
def test_unsafe_archive_names_are_rejected(name):
    with make_archive({'checklist.json': b'{}', name: b'bad'}) as archive:
        with pytest.raises(ValueError):
            verify_inspection_archive(archive)


def test_missing_or_changed_file_is_rejected():
    with make_archive({'checklist.json': b'{}'}, {'checklist.json': 'incorrect'}) as archive:
        with pytest.raises(ValueError, match='Повреждено'):
            verify_inspection_archive(archive)

    with make_archive({'checklist.json': b'{}'}, {}) as archive:
        with pytest.raises(ValueError, match='составу'):
            verify_inspection_archive(archive)
