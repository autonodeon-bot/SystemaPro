"""Тесты для shared.py — кэш, утилиты, файловые хелперы."""

import time
from unittest.mock import MagicMock
from types import SimpleNamespace

import pytest

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from shared import (
    cache_get,
    cache_set,
    cache_invalidate,
    normalize_image_content_type,
    cert_areas_list,
    _ref_cache,
    _CACHE_TTL_SEC,
)


@pytest.fixture(autouse=True)
def clear_cache():
    """Очищает кэш перед каждым тестом."""
    _ref_cache.clear()
    yield
    _ref_cache.clear()


# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------
class TestCache:

    def test_cache_set_and_get(self):
        """cache_set/cache_get — сохраняет и возвращает значение."""
        cache_set("key1", {"data": 42})
        result = cache_get("key1")
        assert result == {"data": 42}

    def test_cache_get_missing_key(self):
        """cache_get — возвращает None для несуществующего ключа."""
        assert cache_get("nonexistent") is None

    def test_cache_expiry(self):
        """Просроченные записи возвращают None."""
        cache_set("expiring_key", "value")
        _ref_cache["expiring_key"] = (time.time() - 1, "value")
        assert cache_get("expiring_key") is None

    def test_cache_not_expired(self):
        """Ещё не истёкшие записи возвращаются корректно."""
        cache_set("fresh_key", [1, 2, 3])
        assert cache_get("fresh_key") == [1, 2, 3]

    def test_cache_invalidate(self):
        """cache_invalidate — удаляет все ключи с указанным префиксом."""
        cache_set("engineers", [1])
        cache_set("engineers:active", [2])
        cache_set("reports", [3])

        cache_invalidate("engineers")

        assert cache_get("engineers") is None
        assert cache_get("engineers:active") is None
        assert cache_get("reports") == [3]

    def test_cache_invalidate_no_match(self):
        """cache_invalidate — не удаляет ключи без совпадения."""
        cache_set("key_a", "a")
        cache_invalidate("no_match_prefix")
        assert cache_get("key_a") == "a"

    def test_cache_overwrite(self):
        """Повторный cache_set перезаписывает значение."""
        cache_set("key", "old")
        cache_set("key", "new")
        assert cache_get("key") == "new"


# ---------------------------------------------------------------------------
# normalize_image_content_type
# ---------------------------------------------------------------------------
class TestNormalizeImageContentType:

    def _make_upload(self, content_type: str, filename: str) -> MagicMock:
        upload = MagicMock()
        upload.content_type = content_type
        upload.filename = filename
        return upload

    def test_jpeg_content_type(self):
        """Файл с content_type image/jpeg распознаётся."""
        f = self._make_upload("image/jpeg", "photo.jpg")
        assert normalize_image_content_type(f) == "image/jpeg"

    def test_png_content_type(self):
        """Файл с content_type image/png распознаётся."""
        f = self._make_upload("image/png", "photo.png")
        assert normalize_image_content_type(f) == "image/png"

    def test_detect_jpg_by_extension(self):
        """Если content_type неизвестный, определяем по расширению .jpg."""
        f = self._make_upload("application/octet-stream", "image.jpg")
        assert normalize_image_content_type(f) == "image/jpeg"

    def test_detect_jpeg_by_extension(self):
        """Если content_type неизвестный, определяем по расширению .jpeg."""
        f = self._make_upload("application/octet-stream", "image.jpeg")
        assert normalize_image_content_type(f) == "image/jpeg"

    def test_detect_png_by_extension(self):
        """Если content_type неизвестный, определяем по расширению .png."""
        f = self._make_upload("application/octet-stream", "image.png")
        assert normalize_image_content_type(f) == "image/png"

    def test_unsupported_returns_none(self):
        """Неподдерживаемый формат возвращает None."""
        f = self._make_upload("application/pdf", "file.pdf")
        assert normalize_image_content_type(f) is None

    def test_no_content_type_no_extension(self):
        """Без content_type и расширения возвращает None."""
        f = self._make_upload("", "file")
        assert normalize_image_content_type(f) is None


# ---------------------------------------------------------------------------
# cert_areas_list
# ---------------------------------------------------------------------------
class TestCertAreasList:

    def test_list_areas(self):
        """Возвращает список из certification_areas."""
        obj = SimpleNamespace(certification_areas=["Сосуды", "Трубопроводы"], certification_area=None)
        result = cert_areas_list(obj)
        assert result == ["Сосуды", "Трубопроводы"]

    def test_single_area_fallback(self):
        """Если certification_areas нет, использует certification_area."""
        obj = SimpleNamespace(certification_area="Сосуды")
        result = cert_areas_list(obj)
        assert result == ["Сосуды"]

    def test_empty_areas(self):
        """Пустой список certification_areas."""
        obj = SimpleNamespace(certification_areas=[], certification_area=None)
        result = cert_areas_list(obj)
        assert result == []

    def test_no_attributes(self):
        """Объект без атрибутов возвращает пустой список."""
        obj = SimpleNamespace()
        result = cert_areas_list(obj)
        assert result == []

    def test_filters_none_values(self):
        """None значения в certification_areas отфильтровываются."""
        obj = SimpleNamespace(certification_areas=["Сосуды", None, "Трубопроводы"], certification_area=None)
        result = cert_areas_list(obj)
        assert result == ["Сосуды", "Трубопроводы"]
