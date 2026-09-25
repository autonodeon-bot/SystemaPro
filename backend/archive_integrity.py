"""Validate the archive completely before extracting or creating database records."""
import hashlib
import uuid
import json
from pathlib import PurePosixPath


def verify_inspection_archive(archive):
    infos = archive.infolist()
    if len(infos) > 5000 or sum(item.file_size for item in infos) > 500 * 1024 * 1024:
        raise ValueError("Распакованный архив слишком большой")
    names = set()
    for item in infos:
        name = item.filename
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name:
            raise ValueError("Недопустимый путь в архиве")
        if name in names or (item.external_attr >> 16) & 0o170000 == 0o120000:
            raise ValueError("Повторяющийся файл или ссылка в архиве")
        names.add(name)
    if not {'manifest.json', 'checklist.json'} <= names:
        raise ValueError("В архиве отсутствуют manifest.json или checklist.json")
    manifest = json.loads(archive.read('manifest.json'))
    if not isinstance(manifest, dict):
        raise ValueError("Неверный формат manifest.json")
    version = manifest.get('version', 1)
    if type(version) is not int or version not in (1, 2):
        raise ValueError("Неподдерживаемая версия архива")
    if version >= 2:
        hashes = manifest.get('checksums')
        expected = {item.filename for item in infos if not item.is_dir() and item.filename != 'manifest.json'}
        if not isinstance(hashes, dict) or set(hashes) != expected:
            raise ValueError("Контрольные суммы не соответствуют составу архива")
        for name, expected_hash in hashes.items():
            if hashlib.sha256(archive.read(name)).hexdigest() != expected_hash:
                raise ValueError(f"Повреждено вложение: {name}")
    return manifest
def archive_upload_identity(archive, owner):
    """Stable across ZIP container timestamps; distinct for another owner or revision."""
    parts = [(item.filename, hashlib.sha256(archive.read(item)).hexdigest())
             for item in archive.infolist() if not item.is_dir()]
    digest = hashlib.sha256(repr(sorted(parts)).encode('utf-8')).hexdigest()
    return uuid.uuid5(uuid.NAMESPACE_URL, f'systemapro-upload:{owner}:{digest}')
