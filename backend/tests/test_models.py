"""Тесты моделей SQLAlchemy — defaults, constraints, структура таблиц"""
import uuid
import pytest
from models import (
    EquipmentType, Enterprise, Branch, Workshop, OPO, Equipment,
    EquipmentResource, PipelineSegment, Client, Project, ProjectInvoice, ProjectInvoicePayment, ProjectContract, Engineer,
    Certification, RegulatoryDocument, User, HierarchyEngineerAssignment,
    Assignment, Inspection, InspectionHistory, RepairJournal,
    ReportTemplate, Report, Questionnaire, QuestionnaireDocumentFile,
    NDTMethod, UserEquipmentAccess, VerificationEquipment,
    VerificationHistory, InspectionEquipment, AuditLog, UserDevice, Opo,
)


class TestModelDefaults:
    """Проверка значений по умолчанию в моделях"""

    def test_equipment_type_is_active_default(self):
        col = EquipmentType.__table__.columns['is_active']
        assert col.default.arg is True

    def test_enterprise_is_active_default(self):
        col = Enterprise.__table__.columns['is_active']
        assert col.default.arg is True

    def test_branch_is_active_default(self):
        col = Branch.__table__.columns['is_active']
        assert col.default.arg is True

    def test_workshop_is_active_default(self):
        col = Workshop.__table__.columns['is_active']
        assert col.default.arg is True

    def test_opo_is_active_default(self):
        col = OPO.__table__.columns['is_active']
        assert col.default.arg is True

    def test_equipment_is_active_default(self):
        col = Equipment.__table__.columns['is_active']
        assert col.default.arg is True

    def test_user_role_default(self):
        col = User.__table__.columns['role']
        assert col.default.arg == 'engineer'

    def test_user_is_active_default(self):
        col = User.__table__.columns['is_active']
        assert col.default.arg is True

    def test_assignment_status_default(self):
        col = Assignment.__table__.columns['status']
        assert col.default.arg == 'PENDING'

    def test_assignment_priority_default(self):
        col = Assignment.__table__.columns['priority']
        assert col.default.arg == 'NORMAL'

    def test_assignment_type_default(self):
        col = Assignment.__table__.columns['assignment_type']
        assert col.default.arg == 'DIAGNOSTICS'

    def test_inspection_status_default(self):
        col = Inspection.__table__.columns['status']
        assert col.default.arg == 'DRAFT'

    def test_inspection_is_archived_default(self):
        col = Inspection.__table__.columns['is_archived']
        assert col.default.arg is False

    def test_project_status_default(self):
        col = Project.__table__.columns['status']
        assert col.default.arg == 'PLANNED'

    def test_project_invoice_status_default(self):
        col = ProjectInvoice.__table__.columns['status']
        assert col.default.arg == 'DRAFT'

    def test_project_contract_status_default(self):
        col = ProjectContract.__table__.columns['status']
        assert col.default.arg == 'ACTIVE'

    def test_questionnaire_status_default(self):
        col = Questionnaire.__table__.columns['status']
        assert col.default.arg == 'DRAFT'

    def test_equipment_resource_status_default(self):
        col = EquipmentResource.__table__.columns['status']
        assert col.default.arg == 'ACTIVE'

    def test_report_is_signed_default(self):
        col = Report.__table__.columns['is_signed']
        assert col.default.arg is False

    def test_report_is_archived_default(self):
        col = Report.__table__.columns['is_archived']
        assert col.default.arg is False

    def test_verification_equipment_is_active_default(self):
        col = VerificationEquipment.__table__.columns['is_active']
        assert col.default.arg is True

    def test_user_device_platform_default(self):
        col = UserDevice.__table__.columns['platform']
        assert col.default.arg == 'android'

    def test_user_device_is_active_default(self):
        col = UserDevice.__table__.columns['is_active']
        assert col.default.arg is True

    def test_inspection_history_status_default(self):
        col = InspectionHistory.__table__.columns['status']
        assert col.default.arg == 'DRAFT'

    def test_ndt_method_is_performed_default(self):
        col = NDTMethod.__table__.columns['is_performed']
        assert col.default.arg == 0


class TestModelTableNames:
    """Проверка имён таблиц"""

    @pytest.mark.parametrize('model,expected', [
        (EquipmentType, 'equipment_types'),
        (Enterprise, 'enterprises'),
        (Branch, 'branches'),
        (Workshop, 'workshops'),
        (OPO, 'opos'),
        (Equipment, 'equipment'),
        (EquipmentResource, 'equipment_resources'),
        (PipelineSegment, 'pipeline_segments'),
        (Client, 'clients'),
        (Project, 'projects'),
        (ProjectInvoice, 'project_invoices'),
        (ProjectInvoicePayment, 'project_invoice_payments'),
        (ProjectContract, 'project_contracts'),
        (Engineer, 'engineers'),
        (Certification, 'certifications'),
        (RegulatoryDocument, 'regulatory_documents'),
        (User, 'users'),
        (HierarchyEngineerAssignment, 'hierarchy_engineer_assignments'),
        (Assignment, 'assignments'),
        (Inspection, 'inspections'),
        (InspectionHistory, 'inspection_history'),
        (RepairJournal, 'repair_journal'),
        (ReportTemplate, 'report_templates'),
        (Report, 'reports'),
        (Questionnaire, 'questionnaires'),
        (QuestionnaireDocumentFile, 'questionnaire_document_files'),
        (NDTMethod, 'ndt_methods'),
        (UserEquipmentAccess, 'user_equipment_access'),
        (VerificationEquipment, 'verification_equipment'),
        (VerificationHistory, 'verification_history'),
        (InspectionEquipment, 'inspection_equipment'),
        (AuditLog, 'audit_log'),
        (UserDevice, 'user_devices'),
    ])
    def test_tablename(self, model, expected):
        assert model.__tablename__ == expected


class TestModelPrimaryKeys:
    """Все модели используют UUID PK"""

    @pytest.mark.parametrize('model', [
        EquipmentType, Enterprise, Branch, Workshop, OPO, Equipment,
        EquipmentResource, PipelineSegment, Client, Project, ProjectInvoice, ProjectInvoicePayment, ProjectContract, Engineer,
        Certification, RegulatoryDocument, User, HierarchyEngineerAssignment,
        Assignment, Inspection, InspectionHistory, RepairJournal,
        ReportTemplate, Report, Questionnaire, QuestionnaireDocumentFile,
        NDTMethod, UserEquipmentAccess, VerificationEquipment,
        VerificationHistory, InspectionEquipment, AuditLog, UserDevice,
    ])
    def test_uuid_primary_key(self, model):
        pk = model.__table__.columns['id']
        assert pk.primary_key
        assert pk.default is not None
        assert callable(pk.default.arg)
        assert pk.default.arg.__name__ == 'uuid4'


class TestModelNullability:
    """Проверка NOT NULL ограничений"""

    def test_enterprise_name_not_nullable(self):
        col = Enterprise.__table__.columns['name']
        assert col.nullable is False

    def test_equipment_name_not_nullable(self):
        col = Equipment.__table__.columns['name']
        assert col.nullable is False

    def test_user_username_not_nullable(self):
        col = User.__table__.columns['username']
        assert col.nullable is False

    def test_user_password_hash_not_nullable(self):
        col = User.__table__.columns['password_hash']
        assert col.nullable is False

    def test_assignment_equipment_id_not_nullable(self):
        col = Assignment.__table__.columns['equipment_id']
        assert col.nullable is False

    def test_assignment_assigned_to_not_nullable(self):
        col = Assignment.__table__.columns['assigned_to']
        assert col.nullable is False

    def test_inspection_equipment_id_not_nullable(self):
        col = Inspection.__table__.columns['equipment_id']
        assert col.nullable is False

    def test_branch_enterprise_id_not_nullable(self):
        col = Branch.__table__.columns['enterprise_id']
        assert col.nullable is False

    def test_workshop_branch_id_not_nullable(self):
        col = Workshop.__table__.columns['branch_id']
        assert col.nullable is False

    def test_audit_log_action_not_nullable(self):
        col = AuditLog.__table__.columns['action']
        assert col.nullable is False

    def test_audit_log_entity_type_not_nullable(self):
        col = AuditLog.__table__.columns['entity_type']
        assert col.nullable is False

    def test_verification_equipment_serial_not_nullable(self):
        col = VerificationEquipment.__table__.columns['serial_number']
        assert col.nullable is False

    def test_verification_equipment_type_not_nullable(self):
        col = VerificationEquipment.__table__.columns['equipment_type']
        assert col.nullable is False


class TestModelIndexes:
    """Проверка индексов на часто используемых полях"""

    def test_user_username_indexed(self):
        col = User.__table__.columns['username']
        assert col.index is True

    def test_equipment_code_indexed(self):
        col = Equipment.__table__.columns['equipment_code']
        assert col.index is True

    def test_branch_enterprise_id_indexed(self):
        col = Branch.__table__.columns['enterprise_id']
        assert col.index is True

    def test_workshop_branch_id_indexed(self):
        col = Workshop.__table__.columns['branch_id']
        assert col.index is True

    def test_assignment_equipment_id_indexed(self):
        col = Assignment.__table__.columns['equipment_id']
        assert col.index is True

    def test_assignment_assigned_to_indexed(self):
        col = Assignment.__table__.columns['assigned_to']
        assert col.index is True

    def test_inspection_equipment_id_indexed(self):
        col = Inspection.__table__.columns['equipment_id']
        assert col.index is True

    def test_report_inspection_id_indexed(self):
        col = Report.__table__.columns['inspection_id']
        assert col.index is True


class TestModelUniques:
    """Проверка уникальных ограничений"""

    def test_user_username_unique(self):
        col = User.__table__.columns['username']
        assert col.unique is True

    def test_equipment_type_code_unique(self):
        col = EquipmentType.__table__.columns['code']
        assert col.unique is True

    def test_equipment_code_unique(self):
        col = Equipment.__table__.columns['equipment_code']
        assert col.unique is True

    def test_report_number_unique(self):
        col = Report.__table__.columns['report_number']
        assert col.unique is True

    def test_user_device_fcm_token_unique(self):
        col = UserDevice.__table__.columns['fcm_token']
        assert col.unique is True


class TestModelForeignKeys:
    """Проверка внешних ключей"""

    def _fk_targets(self, model, column_name):
        col = model.__table__.columns[column_name]
        return {fk.target_fullname for fk in col.foreign_keys}

    def test_branch_references_enterprise(self):
        assert 'enterprises.id' in self._fk_targets(Branch, 'enterprise_id')

    def test_workshop_references_branch(self):
        assert 'branches.id' in self._fk_targets(Workshop, 'branch_id')

    def test_equipment_references_workshop(self):
        assert 'workshops.id' in self._fk_targets(Equipment, 'workshop_id')

    def test_equipment_references_type(self):
        assert 'equipment_types.id' in self._fk_targets(Equipment, 'type_id')

    def test_assignment_references_equipment(self):
        assert 'equipment.id' in self._fk_targets(Assignment, 'equipment_id')

    def test_assignment_references_user(self):
        assert 'users.id' in self._fk_targets(Assignment, 'assigned_to')

    def test_inspection_references_equipment(self):
        assert 'equipment.id' in self._fk_targets(Inspection, 'equipment_id')

    def test_report_references_inspection(self):
        assert 'inspections.id' in self._fk_targets(Report, 'inspection_id')

    def test_certification_references_engineer(self):
        assert 'engineers.id' in self._fk_targets(Certification, 'engineer_id')

    def test_user_device_references_user(self):
        assert 'users.id' in self._fk_targets(UserDevice, 'user_id')


class TestOpoAlias:
    """Проверка алиаса Opo == OPO"""

    def test_opo_alias(self):
        assert Opo is OPO
