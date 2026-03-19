import uuid

import pytest
from pydantic import ValidationError

from equipment_crud_api import EquipmentCreate, EquipmentUpdate, router


class TestEquipmentRouter:
    def test_router_should_have_equipment_tag(self):
        assert router.tags == ["equipment"]


class TestEquipmentCreateSchema:
    def test_equipment_create_should_require_name(self):
        with pytest.raises(ValidationError):
            EquipmentCreate()

    def test_equipment_create_should_accept_name_only(self):
        m = EquipmentCreate(name="Vessel-1")
        assert m.name == "Vessel-1"
        assert m.type_id is None
        assert m.workshop_id is None

    def test_equipment_create_should_accept_optional_ids(self):
        tid = str(uuid.uuid4())
        wid = str(uuid.uuid4())
        oid = str(uuid.uuid4())
        m = EquipmentCreate(
            name="Pump",
            type_id=tid,
            workshop_id=wid,
            opo_id=oid,
            serial_number="SN-1",
            location="Hall A",
            commissioning_date="2020-01-01",
            attributes={"pressure_mpa": 1.2},
        )
        assert m.type_id == tid
        assert m.workshop_id == wid
        assert m.opo_id == oid
        assert m.attributes == {"pressure_mpa": 1.2}


class TestEquipmentUpdateSchema:
    def test_equipment_update_should_allow_empty_patch(self):
        m = EquipmentUpdate()
        assert m.model_dump(exclude_unset=True) == {}

    def test_equipment_update_should_accept_partial_fields(self):
        m = EquipmentUpdate(name="New name", location="Yard")
        d = m.model_dump(exclude_unset=True)
        assert d == {"name": "New name", "location": "Yard"}


class TestEquipmentModelDefaults:
    def test_equipment_model_should_default_is_active(self):
        from models import Equipment

        col = Equipment.__table__.columns["is_active"]
        assert col.default.arg is True
