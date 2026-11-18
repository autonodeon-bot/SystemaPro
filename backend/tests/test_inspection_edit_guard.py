from datetime import datetime, timezone, timedelta
from types import SimpleNamespace
from uuid import uuid4
import pytest
from fastapi import HTTPException
from inspection_edit_guard import assert_mobile_edit_allowed, inspection_revision


@pytest.fixture
def state():
    owner, equipment = uuid4(), uuid4()
    inspection = SimpleNamespace(equipment_id=equipment, is_deleted=False, status='DRAFT',
        created_by=owner, inspector_id=owner, performed_by=owner,
        created_at=datetime(2026, 11, 13, tzinfo=timezone.utc), updated_at=None)
    user = SimpleNamespace(id=owner, role='engineer')
    return inspection, equipment, user


def test_edit_accepts_current_revision_and_timezone_equivalent(state):
    inspection, equipment, user = state
    assert_mobile_edit_allowed(inspection, equipment, user, inspection_revision(inspection))
    assert_mobile_edit_allowed(inspection, equipment, user, '2026-11-13T03:00:00+03:00')


@pytest.mark.parametrize('revision', [None, 'invalid', '2026-11-12T00:00:00Z'])
def test_stale_or_missing_revision_is_retained_as_local_conflict(state, revision):
    inspection, equipment, user = state
    with pytest.raises(HTTPException) as error:
        assert_mobile_edit_allowed(inspection, equipment, user, revision)
    assert error.value.status_code == 409


@pytest.mark.parametrize('status', ['APPROVED', 'COMPLETED'])
def test_non_drafts_cannot_be_overwritten(state, status):
    inspection, equipment, user = state
    inspection.status = status
    with pytest.raises(HTTPException) as error:
        assert_mobile_edit_allowed(inspection, equipment, user, inspection_revision(inspection))
    assert error.value.status_code == 409


def test_completed_mobile_checklist_can_be_corrected_with_current_revision(state):
    inspection, equipment, user = state
    inspection.status = 'SIGNED'
    assert_mobile_edit_allowed(inspection, equipment, user, inspection_revision(inspection))


def test_other_engineer_cannot_edit_inspection(state):
    inspection, equipment, user = state
    user.id = uuid4()
    with pytest.raises(HTTPException) as error:
        assert_mobile_edit_allowed(inspection, equipment, user, inspection_revision(inspection))
    assert error.value.status_code == 403


@pytest.mark.parametrize('change', ['deleted', 'equipment'])
def test_deleted_or_wrong_equipment_is_rejected(state, change):
    inspection, equipment, user = state
    if change == 'deleted': inspection.is_deleted = True
    else: equipment = uuid4()
    with pytest.raises(HTTPException) as error:
        assert_mobile_edit_allowed(inspection, equipment, user, inspection_revision(inspection))
    assert error.value.status_code == 409
