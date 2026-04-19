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
  EngineerUserListItem,
  Enterprise,
  Equipment,
  EquipmentType,
  HierarchyInfoType,
  InfoModalState,
  Workshop,
} from '../components/equipment/types';

const emptyFormData = (): CreateFormData => ({
  name: '',
  code: '',
  description: '',
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

  const [showCreateModal, setShowCreateModal] = useState<{
    type: CreateEntityType;
    parentId?: string;
    parentName?: string;
  } | null>(null);

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
    setShowCreateModal({ type, parentId, parentName });
    setFormData({
      ...emptyFormData(),
      enterprise_id: parentId || '',
      branch_id: parentId || '',
      workshop_id: parentId || '',
    });
  };

  const handlePrepareEquipmentCreateFromType = (
    workshopId: string,
    workshopName: string,
    typeId: string
  ) => {
    setShowCreateModal({
      type: 'equipment',
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
      let endpoint = '';
      let body: Record<string, unknown> = {};

      switch (showCreateModal.type) {
        case 'enterprise':
          endpoint = `${API_BASE}/api/hierarchy/enterprises`;
          body = {
            name: formData.name,
            code: formData.code || undefined,
            description: formData.description || undefined,
          };
          break;
        case 'branch':
          endpoint = `${API_BASE}/api/hierarchy/branches`;
          body = {
            enterprise_id: showCreateModal.parentId,
            name: formData.name,
            code: formData.code || undefined,
            description: formData.description || undefined,
          };
          break;
        case 'workshop':
          endpoint = `${API_BASE}/api/hierarchy/workshops`;
          body = {
            branch_id: showCreateModal.parentId,
            name: formData.name,
            code: formData.code || undefined,
            description: formData.description || undefined,
          };
          break;
        case 'equipment_type':
          endpoint = `${API_BASE}/api/equipment-types`;
          body = {
            name: formData.name,
            code: formData.code || undefined,
          };
          break;
        case 'equipment':
          endpoint = `${API_BASE}/api/equipment`;
          body = {
            name: formData.name,
            type_id: formData.type_id || undefined,
            serial_number: formData.serial_number || undefined,
            location: formData.location || undefined,
            workshop_id: showCreateModal.parentId,
            commissioning_date: formData.commissioning_date || undefined,
            attributes: {},
          };
          break;
      }

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(body),
      });

      if (response.ok) {
        alert(
          `${
            showCreateModal.type === 'enterprise'
              ? 'Предприятие'
              : showCreateModal.type === 'branch'
                ? 'Филиал'
                : showCreateModal.type === 'workshop'
                  ? 'Цех'
                  : showCreateModal.type === 'equipment_type'
                    ? 'Тип оборудования'
                    : 'Оборудование'
          } успешно создано`
        );
        setShowCreateModal(null);
        setFormData(emptyFormData());

        if (showCreateModal.type === 'enterprise' || showCreateModal.type === 'equipment_type') {
          loadData();
        } else if (showCreateModal.type === 'branch') {
          loadBranches(showCreateModal.parentId!);
        } else if (showCreateModal.type === 'workshop') {
          loadWorkshops(showCreateModal.parentId!);
        } else if (showCreateModal.type === 'equipment') {
          loadEquipment(showCreateModal.parentId!);
        }
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось создать'}`);
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

  const handleDeleteEquipment = async (id: string) => {
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
        loadData();
      } else {
        alert('Ошибка удаления оборудования');
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
