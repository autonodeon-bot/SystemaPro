"""Базовые тесты API заданий"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
import uuid


class TestAssignmentValidation:
    """Тесты валидации заданий"""

    def test_valid_assignment_types(self):
        """Проверка допустимых типов заданий"""
        from assignments_api import VALID_ASSIGNMENT_TYPES
        assert 'DIAGNOSTICS' in VALID_ASSIGNMENT_TYPES
        assert 'EXPERTISE' in VALID_ASSIGNMENT_TYPES
        assert 'INSPECTION' in VALID_ASSIGNMENT_TYPES
        assert len(VALID_ASSIGNMENT_TYPES) == 7
        assert 'CHTO' in VALID_ASSIGNMENT_TYPES
        assert 'PTO' in VALID_ASSIGNMENT_TYPES
        assert 'NVO' in VALID_ASSIGNMENT_TYPES
        assert 'NVO_GI' in VALID_ASSIGNMENT_TYPES

    def test_valid_statuses(self):
        """Проверка допустимых статусов"""
        from assignments_api import VALID_STATUSES
        assert 'PENDING' in VALID_STATUSES
        assert 'IN_PROGRESS' in VALID_STATUSES
        assert 'COMPLETED' in VALID_STATUSES
        assert 'CANCELLED' in VALID_STATUSES

    def test_valid_priorities(self):
        """Проверка допустимых приоритетов"""
        from assignments_api import VALID_PRIORITIES
        assert 'LOW' in VALID_PRIORITIES
        assert 'NORMAL' in VALID_PRIORITIES
        assert 'HIGH' in VALID_PRIORITIES
        assert 'URGENT' in VALID_PRIORITIES

    def test_operator_roles_defined(self):
        """Проверка ролей операторов"""
        from assignments_api import OPERATOR_ROLES
        assert 'admin' in OPERATOR_ROLES
        assert 'chief_operator' in OPERATOR_ROLES
        assert 'operator' in OPERATOR_ROLES
        assert 'engineer' not in OPERATOR_ROLES


class TestAssignmentModels:
    """Тесты моделей заданий"""

    def test_assignment_default_status(self):
        """Проверка статуса по умолчанию"""
        from models import Assignment
        assert Assignment.status.property.columns[0].default.arg == "PENDING"

    def test_assignment_has_indexes(self):
        """Проверка наличия индексов"""
        from models import Assignment
        columns = {c.name: c for c in Assignment.__table__.columns}
        assert columns['assigned_to'].index or any(
            idx for idx in Assignment.__table__.indexes if 'assigned_to' in [c.name for c in idx.columns]
        )
