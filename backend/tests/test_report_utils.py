import uuid
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock

import pytest

import report_utils as ru
from report_generator import ReportGenerator, _escape_para


class TestHasValue:
    def test_has_value_should_false_for_none(self):
        assert ru._has_value(None) is False

    def test_has_value_should_false_for_blank_string(self):
        assert ru._has_value("") is False
        assert ru._has_value("   ") is False

    def test_has_value_should_true_for_non_empty_string(self):
        assert ru._has_value("x") is True

    def test_has_value_should_false_for_empty_collection(self):
        assert ru._has_value([]) is False
        assert ru._has_value({}) is False

    def test_has_value_should_true_for_non_empty_collection(self):
        assert ru._has_value([1]) is True
        assert ru._has_value({"a": 1}) is True

    def test_has_value_should_true_for_number(self):
        assert ru._has_value(0) is True


class TestGenerateReportNumber:
    @pytest.mark.asyncio
    async def test_generate_report_number_should_start_sequence_when_no_prior(self):
        mock_db = AsyncMock()
        res = MagicMock()
        res.scalar_one_or_none.return_value = None
        mock_db.execute = AsyncMock(return_value=res)

        num = await ru.generate_report_number(mock_db, "TECHNICAL")
        year = datetime.now().year
        assert num == f"ТР-{year}-0001"

    @pytest.mark.asyncio
    async def test_generate_report_number_should_increment_from_last(self):
        year = datetime.now().year
        last = MagicMock()
        last.report_number = f"ТР-{year}-0007"

        mock_db = AsyncMock()
        res = MagicMock()
        res.scalar_one_or_none.return_value = last
        mock_db.execute = AsyncMock(return_value=res)

        num = await ru.generate_report_number(mock_db, "TECHNICAL")
        assert num == f"ТР-{year}-0008"

    @pytest.mark.asyncio
    async def test_generate_report_number_should_use_expertise_prefix(self):
        mock_db = AsyncMock()
        res = MagicMock()
        res.scalar_one_or_none.return_value = None
        mock_db.execute = AsyncMock(return_value=res)

        num = await ru.generate_report_number(mock_db, "EXPERTISE")
        year = datetime.now().year
        assert num == f"ЭР-{year}-0001"

    @pytest.mark.asyncio
    async def test_generate_report_number_should_fallback_on_execute_error(self):
        mock_db = AsyncMock()
        mock_db.execute = AsyncMock(side_effect=RuntimeError("db down"))

        num = await ru.generate_report_number(mock_db, "TECHNICAL")
        year = datetime.now().year
        assert num.startswith(f"ТР-{year}-")


class TestGenerateRegistrationNumber:
    @pytest.mark.asyncio
    async def test_generate_registration_number_should_start_at_one(self):
        mock_db = AsyncMock()
        res = MagicMock()
        res.scalar_one_or_none.return_value = None
        mock_db.execute = AsyncMock(return_value=res)

        num = await ru.generate_registration_number(mock_db)
        year = datetime.now().year
        assert num == f"РЕГ-{year}-0001"


class TestValidateInspectionCompleteness:
    @pytest.mark.asyncio
    async def test_validate_inspection_should_fail_for_invalid_uuid(self):
        mock_db = AsyncMock()
        out = await ru.validate_inspection_completeness(mock_db, "not-uuid")
        assert out["is_complete"] is False
        assert any("Ошибка" in x for x in out["missing_fields"])

    @pytest.mark.asyncio
    async def test_validate_inspection_should_fail_when_missing(self):
        iid = str(uuid.uuid4())
        mock_db = AsyncMock()
        res = MagicMock()
        res.scalar_one_or_none.return_value = None
        mock_db.execute = AsyncMock(return_value=res)

        out = await ru.validate_inspection_completeness(mock_db, iid)
        assert out["is_complete"] is False
        assert "Обследование не найдено" in out["missing_fields"]


class TestCompareInspections:
    @pytest.mark.asyncio
    async def test_compare_inspections_should_error_when_current_missing(self):
        mock_db = AsyncMock()
        res = MagicMock()
        res.scalar_one_or_none.return_value = None
        mock_db.execute = AsyncMock(return_value=res)

        out = await ru.compare_inspections(mock_db, str(uuid.uuid4()))
        assert "error" in out


class TestReportGeneratorEscape:
    def test_escape_para_should_escape_html_entities(self):
        assert _escape_para("a & b < c > d") == "a &amp; b &lt; c &gt; d"

    def test_escape_para_should_return_empty_for_falsy(self):
        assert _escape_para("") == ""
        assert _escape_para(None) == ""

    def test_report_generator_should_init_without_error(self):
        gen = ReportGenerator()
        assert gen.default_font in ("Helvetica", "DejaVuSans", "LiberationSans")
