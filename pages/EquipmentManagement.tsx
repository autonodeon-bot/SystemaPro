import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { API_BASE } from '../constants';
import EquipmentHierarchySearch from '../components/equipment/EquipmentHierarchySearch';
import EquipmentHierarchyTree from '../components/equipment/EquipmentHierarchyTree';
import EquipmentCreateModal from '../components/equipment/EquipmentCreateModal';
import EquipmentAssignEngineersModal from '../components/equipment/EquipmentAssignEngineersModal';
import EquipmentInfoCard from '../components/equipment/EquipmentInfoCard';
import type {
  AssignedEngineerRecord,
  Branch,
  CreateEntityType,
  CreateFormData,
  CreateModalState,
  EngineerUserListItem,
  Enterprise,
  Equipment,
  EquipmentType,
  HierarchyInfoType,
  InfoModalState,
  Workshop,
} from '../components/equipment/types';

const parseApiDetail = (detail: unknown): string => {
  if (typeof detail === 'string') return detail;
  if (detail && typeof detail === 'object' && 'message' in detail) {
    return String((detail as { message: string }).message);
  }
  return 'Неизвестная ошибка';
};

const emptyFormData = (): CreateFormData => ({
  name: '',
  code: '',
  description: '',
  director: '',
  phone: '',
  email: '',
  legal_address: '',
  enterprise_id: '',
  branch_id: '',
  workshop_id: '',
  type_id: '',
  serial_number: '',
  location: '',
  commissioning_date: '',
});

const EquipmentManagement = () => {
  const { getToken } = useAuth();
  const navigate = useNavigate();
  const [enterprises, setEnterprises] = useState<Enterprise[]>([]);
  const [branches, setBranches] = useState<Record<string, Branch[]>>({});
  const [workshops, setWorkshops] = useState<Record<string, Workshop[]>>({});
  const [equipmentTypes, setEquipmentTypes] = useState<EquipmentType[]>([]);
  const [equipment, setEquipment] = useState<Record<string, Equipment[]>>({});
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [searchTerm, setSearchTerm] = useState('');
  const [usersList, setUsersList] = useState<EngineerUserListItem[]>([]);

  const [showCreateModal, setShowCreateModal] = useState<CreateModalState | null>(null);

  const [showAssignModal, setShowAssignModal] = useState<{
    type: CreateEntityType;
    id: string;
    name: string;
  } | null>(null);

  const [showInfoModal, setShowInfoModal] = useState<InfoModalState | null>(null);

  const [assignedEngineers, setAssignedEngineers] = useState<AssignedEngineerRecord[]>([]);
  const [selectedEngineers, setSelectedEngineers] = useState<string[]>([]);

  const [formData, setFormData] = useState<CreateFormData>(emptyFormData());

  useEffect(() => {
    loadData();
    loadUsers();
  }, []);

  useEffect(() => {
    if (showInfoModal) {
      loadAssignedEngineers();
    }
  }, [showInfoModal]);

  const loadData = async () => {
    await Promise.all([loadEnterprises(), loadEquipmentTypes()]);
  };

  const loadUsers = async () => {
    try {
      const token = getToken();
      const headers: HeadersInit = {};
      if (token) {
        headers.Authorization = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/users?role=engineer`, {
        headers,
      });
      if (response.ok) {
        const data = (await response.json()) as { items?: EngineerUserListItem[] };
        setUsersList(data.items || []);
      } else if (response.status === 401 || response.status === 403) {
        console.warn('Нет доступа к списку пользователей');
        setUsersList([]);
      }
    } catch (error) {
      console.error('Ошибка загрузки пользователей:', error);
      setUsersList([]);
    }
  };

  const loadAssignedEngineers = async () => {
    if (!showInfoModal) return;
    try {
      const token = getToken();
      let endpoint = '';
      switch (showInfoModal.type) {
        case 'enterprise':
          endpoint = `${API_BASE}/api/hierarchy/enterprises/${showInfoModal.id}/assigned-engineers`;
          break;
        case 'branch':
          endpoint = `${API_BASE}/api/hierarchy/branches/${showInfoModal.id}/assigned-engineers`;
          break;
        case 'workshop':
          endpoint = `${API_BASE}/api/hierarchy/workshops/${showInfoModal.id}/assigned-engineers`;
          break;
        case 'equipment':
          endpoint = `${API_BASE}/api/hierarchy/equipment/${showInfoModal.id}/assigned-engineers`;
          break;
        default:
          return;
      }
      const response = await fetch(endpoint, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (response.ok) {
        const data = (await response.json()) as { items?: AssignedEngineerRecord[] };
        const items = data.items || [];
        setAssignedEngineers(items);
        setSelectedEngineers(items.map((e) => e.user_id));
      }
    } catch (error) {
      console.error('Ошибка загрузки назначенных инженеров:', error);
    }
  };

  const loadEnterprises = async () => {
    try {
      const token = getToken();
      if (!token) {
        console.error('Токен авторизации не найден');
        alert('Необходимо авторизоваться. Перенаправление на страницу входа...');
        window.location.href = '/#/login';
        return;
      }

      console.log('Загрузка предприятий...', { API_BASE, token: `${token.substring(0, 20)}...` });

      const response = await fetch(`${API_BASE}/api/hierarchy/enterprises`, {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      });

      console.log('Ответ сервера:', {
        status: response.status,
        statusText: response.statusText,
        ok: response.ok,
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error('Ошибка загрузки предприятий:', response.status, response.statusText, errorText);

        if (response.status === 401) {
          localStorage.removeItem('token');
          alert('Сессия истекла. Необходимо войти снова.');
          window.location.href = '/#/login';
          return;
        }

        alert(`Ошибка загрузки предприятий: ${response.status} ${response.statusText}\n${errorText}`);
        return;
      }

      const data = await response.json();
      console.log('Загружены предприятия (raw):', data);

      const enterprisesList = Array.isArray(data.items)
        ? data.items
        : Array.isArray(data)
          ? data
          : [];
      console.log('Список предприятий для отображения:', enterprisesList);

      if (enterprisesList.length === 0) {
        console.warn('Предприятия не найдены в базе данных');
      }

      setEnterprises(enterprisesList);
    } catch (error) {
      console.error('Ошибка загрузки предприятий:', error);
      alert(`Ошибка загрузки предприятий: ${error instanceof Error ? error.message : String(error)}`);
    }
  };

  const loadBranches = async (enterpriseId: string) => {
    try {
      const token = getToken();
      const response = await fetch(
        `${API_BASE}/api/hierarchy/branches?enterprise_id=${enterpriseId}`,
        {
          headers: { Authorization: `Bearer ${token}` },
        }
      );
      const data = (await response.json()) as { items?: Branch[] };
      setBranches((prev) => ({ ...prev, [enterpriseId]: data.items || [] }));
    } catch (error) {
      console.error('Ошибка загрузки филиалов:', error);
    }
  };

  const loadWorkshops = async (branchId: string) => {
    try {
      const token = getToken();
      const response = await fetch(`${API_BASE}/api/hierarchy/workshops?branch_id=${branchId}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = (await response.json()) as { items?: Workshop[] };
      setWorkshops((prev) => ({ ...prev, [branchId]: data.items || [] }));
    } catch (error) {
      console.error('Ошибка загрузки цехов:', error);
    }
  };

  const loadEquipment = async (workshopId: string) => {
    try {
      const token = getToken();
      const response = await fetch(`${API_BASE}/api/equipment?workshop_id=${workshopId}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = (await response.json()) as { items?: Equipment[] };
      setEquipment((prev) => ({ ...prev, [workshopId]: data.items || [] }));
    } catch (error) {
      console.error('Ошибка загрузки оборудования:', error);
    }
  };

  const loadEquipmentTypes = async () => {
    try {
      const response = await fetch(`${API_BASE}/api/equipment-types`);
      const data = (await response.json()) as { items?: EquipmentType[] };
      setEquipmentTypes(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки типов оборудования:', error);
    }
  };

  const toggleExpand = (key: string) => {
    setExpanded((prev) => ({ ...prev, [key]: !prev[key] }));

    if (!expanded[key]) {
      if (key.startsWith('enterprise_')) {
        const enterpriseId = key.replace('enterprise_', '');
        loadBranches(enterpriseId);
      } else if (key.startsWith('branch_')) {
        const branchId = key.replace('branch_', '');
        loadWorkshops(branchId);
      } else if (key.startsWith('workshop_')) {
        const workshopId = key.replace('workshop_', '');
        loadEquipment(workshopId);
      }
    }
  };

  const handleCreateClick = (
    type: CreateEntityType,
    parentId?: string,
    parentName?: string
  ) => {
    setShowCreateModal({ type, mode: 'create', parentId, parentName });
    setFormData({
      ...emptyFormData(),
      enterprise_id: parentId || '',
      branch_id: parentId || '',
      workshop_id: parentId || '',
    });
  };

  const handleEditEnterprise = (enterprise: Enterprise) => {
    setShowCreateModal({
      type: 'enterprise',
      mode: 'edit',
      entityId: enterprise.id,
    });
    setFormData({
      ...emptyFormData(),
      name: enterprise.name,
      code: enterprise.code || '',
      description: enterprise.description || '',
      director: enterprise.director || '',
      phone: enterprise.phone || '',
      email: enterprise.email || '',
      legal_address: enterprise.legal_address || '',
    });
  };

  const handleEditBranch = (branch: Branch) => {
    setShowCreateModal({
      type: 'branch',
      mode: 'edit',
      entityId: branch.id,
      parentId: branch.enterprise_id,
    });
    setFormData({
      ...emptyFormData(),
      name: branch.name,
      code: branch.code || '',
      description: branch.description || '',
      enterprise_id: branch.enterprise_id,
    });
  };

  const handleEditWorkshop = (workshop: Workshop) => {
    setShowCreateModal({
      type: 'workshop',
      mode: 'edit',
      entityId: workshop.id,
      parentId: workshop.branch_id,
    });
    setFormData({
      ...emptyFormData(),
      name: workshop.name,
      code: workshop.code || '',
      description: workshop.description || '',
      branch_id: workshop.branch_id,
    });
  };

  const handleEditEquipmentType = (type: EquipmentType) => {
    setShowCreateModal({
      type: 'equipment_type',
      mode: 'edit',
      entityId: type.id,
    });
    setFormData({
      ...emptyFormData(),
      name: type.name,
      code: type.code || '',
      description: type.description || '',
    });
  };

  const handleEditEquipment = (eq: Equipment, workshopId: string) => {
    setShowCreateModal({
      type: 'equipment',
      mode: 'edit',
      entityId: eq.id,
      parentId: workshopId,
    });
    setFormData({
      ...emptyFormData(),
      name: eq.name,
      type_id: eq.type_id || '',
      serial_number: eq.serial_number || '',
      location: eq.location || '',
      workshop_id: workshopId,
      commissioning_date: eq.commissioning_date || '',
    });
  };

  const handleDeleteEnterprise = async (enterprise: Enterprise) => {
    if (
      !confirm(
        `Удалить предприятие «${enterprise.name}»?\n\nДействие необратимо для отображения в списке. Удаление возможно только если нет активных филиалов.`
      )
    ) {
      return;
    }

    try {
      const token = getToken();
      const response = await fetch(
        `${API_BASE}/api/hierarchy/enterprises/${enterprise.id}`,
        {
          method: 'DELETE',
          headers: { Authorization: `Bearer ${token}` },
        }
      );

      if (response.ok) {
        alert('Предприятие удалено');
        setEnterprises((prev) => prev.filter((e) => e.id !== enterprise.id));
        setBranches((prev) => {
          const next = { ...prev };
          delete next[enterprise.id];
          return next;
        });
        setExpanded((prev) => {
          const next = { ...prev };
          delete next[`enterprise_${enterprise.id}`];
          return next;
        });
      } else {
        const error = await response.json();
        const detail = error.detail;
        alert(
          typeof detail === 'string'
            ? detail
            : detail?.message || 'Не удалось удалить предприятие'
        );
      }
    } catch (error) {
      console.error('Ошибка удаления предприятия:', error);
      alert('Ошибка удаления предприятия');
    }
  };

  const handleDeleteBranch = async (branch: Branch) => {
    if (
      !confirm(
        `Удалить филиал «${branch.name}»?\n\nУдаление возможно только если нет активных цехов.`
      )
    ) {
      return;
    }
    try {
      const token = getToken();
      const response = await fetch(`${API_BASE}/api/hierarchy/branches/${branch.id}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      });
      if (response.ok) {
        alert('Филиал удалён');
        setBranches((prev) => ({
          ...prev,
          [branch.enterprise_id]: (prev[branch.enterprise_id] || []).filter(
            (b) => b.id !== branch.id
          ),
        }));
      } else {
        const error = await response.json();
        alert(parseApiDetail(error.detail));
      }
    } catch (error) {
      console.error('Ошибка удаления филиала:', error);
      alert('Ошибка удаления филиала');
    }
  };

  const handleDeleteWorkshop = async (workshop: Workshop) => {
    if (
      !confirm(
        `Удалить цех «${workshop.name}»?\n\nУдаление возможно только если в цехе нет оборудования.`
      )
    ) {
      return;
    }
    try {
      const token = getToken();
      const response = await fetch(`${API_BASE}/api/hierarchy/workshops/${workshop.id}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      });
      if (response.ok) {
        alert('Цех удалён');
        setWorkshops((prev) => ({
          ...prev,
          [workshop.branch_id]: (prev[workshop.branch_id] || []).filter(
            (w) => w.id !== workshop.id
          ),
        }));
        setEquipment((prev) => {
          const next = { ...prev };
          delete next[workshop.id];
          return next;
        });
      } else {
        const error = await response.json();
        alert(parseApiDetail(error.detail));
      }
    } catch (error) {
      console.error('Ошибка удаления цеха:', error);
      alert('Ошибка удаления цеха');
    }
  };

  const handleDeleteEquipmentType = async (type: EquipmentType) => {
    if (
      !confirm(
        `Удалить тип «${type.name}»?\n\nНельзя удалить, если к типу привязано активное оборудование.`
      )
    ) {
      return;
    }
    try {
      const token = getToken();
      const response = await fetch(`${API_BASE}/api/equipment-types/${type.id}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      });
      if (response.ok) {
        alert('Тип оборудования удалён');
        await loadEquipmentTypes();
      } else {
        const error = await response.json();
        alert(parseApiDetail(error.detail));
      }
    } catch (error) {
      console.error('Ошибка удаления типа:', error);
      alert('Ошибка удаления типа оборудования');
    }
  };

  const handlePrepareEquipmentCreateFromType = (
    workshopId: string,
    workshopName: string,
    typeId: string
  ) => {
    setShowCreateModal({
      type: 'equipment',
      mode: 'create',
      parentId: workshopId,
      parentName: workshopName,
    });
    setFormData({
      ...emptyFormData(),
      workshop_id: workshopId,
      type_id: typeId,
    });
  };

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!showCreateModal) return;

    try {
      const token = getToken();
      const isEdit = showCreateModal.mode === 'edit' && showCreateModal.entityId;
      let endpoint = '';
      let method: 'POST' | 'PUT' = 'POST';
      let body: Record<string, unknown> = {};

      switch (showCreateModal.type) {
        case 'enterprise':
          if (isEdit) {
            method = 'PUT';
            endpoint = `${API_BASE}/api/hierarchy/enterprises/${showCreateModal.entityId}`;
          } else {
            endpoint = `${API_BASE}/api/hierarchy/enterprises`;
          }
          body = {
            name: formData.name,
            code: formData.code || undefined,
            description: formData.description || undefined,
            director: formData.director || undefined,
            phone: formData.phone || undefined,
            email: formData.email || undefined,
            legal_address: formData.legal_address || undefined,
          };
          break;
        case 'branch':
          if (isEdit) {
            method = 'PUT';
            endpoint = `${API_BASE}/api/hierarchy/branches/${showCreateModal.entityId}`;
          } else {
            endpoint = `${API_BASE}/api/hierarchy/branches`;
          }
          body = isEdit
            ? {
                name: formData.name,
                code: formData.code || undefined,
                description: formData.description || undefined,
              }
            : {
                enterprise_id: showCreateModal.parentId,
                name: formData.name,
                code: formData.code || undefined,
                description: formData.description || undefined,
              };
          break;
        case 'workshop':
          if (isEdit) {
            method = 'PUT';
            endpoint = `${API_BASE}/api/hierarchy/workshops/${showCreateModal.entityId}`;
          } else {
            endpoint = `${API_BASE}/api/hierarchy/workshops`;
          }
          body = isEdit
            ? {
                name: formData.name,
                code: formData.code || undefined,
                description: formData.description || undefined,
              }
            : {
                branch_id: showCreateModal.parentId,
                name: formData.name,
                code: formData.code || undefined,
                description: formData.description || undefined,
              };
          break;
        case 'equipment_type':
          if (isEdit) {
            method = 'PUT';
            endpoint = `${API_BASE}/api/equipment-types/${showCreateModal.entityId}`;
          } else {
            endpoint = `${API_BASE}/api/equipment-types`;
          }
          body = {
            name: formData.name,
            code: formData.code || undefined,
            description: formData.description || undefined,
          };
          break;
        case 'equipment':
          if (isEdit) {
            method = 'PUT';
            endpoint = `${API_BASE}/api/equipment/${showCreateModal.entityId}`;
          } else {
            endpoint = `${API_BASE}/api/equipment`;
          }
          body = {
            name: formData.name,
            type_id: formData.type_id || undefined,
            serial_number: formData.serial_number || undefined,
            location: formData.location || undefined,
            commissioning_date: formData.commissioning_date || undefined,
            attributes: {},
            ...(isEdit ? {} : { workshop_id: showCreateModal.parentId }),
          };
          break;
      }

      const response = await fetch(endpoint, {
        method,
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(body),
      });

      if (response.ok) {
        const entityLabel =
          showCreateModal.type === 'enterprise'
            ? 'Предприятие'
            : showCreateModal.type === 'branch'
              ? 'Филиал'
              : showCreateModal.type === 'workshop'
                ? 'Цех'
                : showCreateModal.type === 'equipment_type'
                  ? 'Тип оборудования'
                  : 'Оборудование';
        alert(isEdit ? `${entityLabel} успешно обновлено` : `${entityLabel} успешно создано`);
        setShowCreateModal(null);
        setFormData(emptyFormData());

        if (showCreateModal.type === 'enterprise') {
          loadEnterprises();
        } else if (showCreateModal.type === 'equipment_type') {
          loadEquipmentTypes();
        } else if (showCreateModal.type === 'branch') {
          const enterpriseId =
            formData.enterprise_id || showCreateModal.parentId || '';
          if (enterpriseId) loadBranches(enterpriseId);
        } else if (showCreateModal.type === 'workshop') {
          const branchId = formData.branch_id || showCreateModal.parentId || '';
          if (branchId) loadWorkshops(branchId);
        } else if (showCreateModal.type === 'equipment' && showCreateModal.parentId) {
          loadEquipment(showCreateModal.parentId);
        }
      } else {
        const error = await response.json();
        alert(`Ошибка: ${parseApiDetail(error.detail) || 'Не удалось сохранить'}`);
      }
    } catch (error) {
      console.error('Ошибка создания:', error);
      alert('Ошибка создания');
    }
  };

  const handleAssignEngineers = (
    type: CreateEntityType,
    id: string,
    name: string
  ) => {
    setShowAssignModal({ type, id, name });
    setShowInfoModal({ type: type as HierarchyInfoType, id, name });
    setTimeout(() => {
      loadAssignedEngineers();
    }, 100);
  };

  const handleShowInfo = (type: HierarchyInfoType, id: string, name: string) => {
    setShowInfoModal({ type, id, name });
  };

  const handleAssignSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!showAssignModal || selectedEngineers.length === 0) return;

    try {
      const token = getToken();
      let endpoint = '';
      switch (showAssignModal.type) {
        case 'enterprise':
          endpoint = `${API_BASE}/api/hierarchy/enterprises/${showAssignModal.id}/assign-engineers`;
          break;
        case 'branch':
          endpoint = `${API_BASE}/api/hierarchy/branches/${showAssignModal.id}/assign-engineers`;
          break;
        case 'workshop':
          endpoint = `${API_BASE}/api/hierarchy/workshops/${showAssignModal.id}/assign-engineers`;
          break;
        case 'equipment_type':
          endpoint = `${API_BASE}/api/hierarchy/equipment-types/${showAssignModal.id}/assign-engineers`;
          break;
        case 'equipment':
          endpoint = `${API_BASE}/api/hierarchy/equipment/${showAssignModal.id}/assign-engineers`;
          break;
        default:
          return;
      }

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          user_ids: selectedEngineers,
        }),
      });

      if (response.ok) {
        alert('Инженеры успешно назначены');
        setShowAssignModal(null);
        setSelectedEngineers([]);
        if (showInfoModal) {
          loadAssignedEngineers();
        }
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось назначить инженеров'}`);
      }
    } catch (error) {
      console.error('Ошибка назначения инженеров:', error);
      alert('Ошибка назначения инженеров');
    }
  };

  const handleDeleteEquipment = async (id: string, workshopId?: string) => {
    if (!confirm('Вы уверены, что хотите удалить это оборудование?')) return;

    try {
      const token = getToken();
      const response = await fetch(`${API_BASE}/api/equipment/${id}`, {
        method: 'DELETE',
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (response.ok) {
        alert('Оборудование удалено');
        if (workshopId) {
          loadEquipment(workshopId);
        } else {
          loadData();
        }
      } else {
        const error = await response.json().catch(() => ({}));
        alert(parseApiDetail((error as { detail?: unknown }).detail) || 'Ошибка удаления оборудования');
      }
    } catch (error) {
      console.error('Ошибка удаления:', error);
      alert('Ошибка удаления оборудования');
    }
  };

  const handleInfoAssignEngineers = (
    type: HierarchyInfoType,
    id: string,
    name: string
  ) => {
    handleAssignEngineers(type, id, name);
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)', letterSpacing: '-0.02em' }}>
          Управление оборудованием
        </h1>
      </div>

      <EquipmentHierarchySearch searchTerm={searchTerm} onSearchTermChange={setSearchTerm} />

      <EquipmentHierarchyTree
        enterprises={enterprises}
        branches={branches}
        workshops={workshops}
        equipment={equipment}
        equipmentTypes={equipmentTypes}
        expanded={expanded}
        navigate={navigate}
        onToggleExpand={toggleExpand}
        onCreateEnterprise={() => handleCreateClick('enterprise')}
        onCreateClick={handleCreateClick}
        onPrepareEquipmentCreateFromType={handlePrepareEquipmentCreateFromType}
        onShowInfo={handleShowInfo}
        onAssignEngineers={handleAssignEngineers}
        onDeleteEquipment={handleDeleteEquipment}
        onEditEnterprise={handleEditEnterprise}
        onDeleteEnterprise={handleDeleteEnterprise}
        onEditBranch={handleEditBranch}
        onDeleteBranch={handleDeleteBranch}
        onEditWorkshop={handleEditWorkshop}
        onDeleteWorkshop={handleDeleteWorkshop}
        onEditEquipmentType={handleEditEquipmentType}
        onDeleteEquipmentType={handleDeleteEquipmentType}
        onEditEquipment={handleEditEquipment}
      />

      {showCreateModal && (
        <EquipmentCreateModal
          modal={showCreateModal}
          formData={formData}
          equipmentTypes={equipmentTypes}
          onClose={() => setShowCreateModal(null)}
          onSubmit={handleCreateSubmit}
          onFormDataChange={setFormData}
        />
      )}

      {showAssignModal && (
        <EquipmentAssignEngineersModal
          modal={showAssignModal}
          usersList={usersList}
          selectedEngineers={selectedEngineers}
          assignedEngineers={assignedEngineers}
          onClose={() => setShowAssignModal(null)}
          onSubmit={handleAssignSubmit}
          onSelectedEngineersChange={setSelectedEngineers}
        />
      )}

      {showInfoModal && (
        <EquipmentInfoCard
          modal={showInfoModal}
          onClose={() => setShowInfoModal(null)}
          onAssignEngineers={handleInfoAssignEngineers}
          assignedEngineers={assignedEngineers}
        />
      )}
    </div>
  );
};

export default EquipmentManagement;
