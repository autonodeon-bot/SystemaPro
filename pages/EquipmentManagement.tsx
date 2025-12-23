import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, ChevronRight, ChevronDown, Building2, Network, Factory, Box, Edit, Trash2, MapPin, Search, X, Users, UserCheck, Info, FileText, Wrench, Calendar, Settings } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

interface Enterprise {
  id: string;
  name: string;
  code?: string;
  description?: string;
}

interface Branch {
  id: string;
  enterprise_id: string;
  name: string;
  code?: string;
  description?: string;
}

interface Workshop {
  id: string;
  branch_id: string;
  name: string;
  code?: string;
  description?: string;
}

interface EquipmentType {
  id: string;
  name: string;
  code?: string;
}

interface Equipment {
  id: string;
  name: string;
  type_id?: string;
  serial_number?: string;
  location?: string;
  workshop_id?: string;
  attributes?: any;
  commissioning_date?: string;
}

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
  const [usersList, setUsersList] = useState<any[]>([]);
  
  // Модальные окна для создания
  const [showCreateModal, setShowCreateModal] = useState<{
    type: 'enterprise' | 'branch' | 'workshop' | 'equipment_type' | 'equipment';
    parentId?: string;
    parentName?: string;
  } | null>(null);
  
  // Модальное окно для назначения инженеров
  const [showAssignModal, setShowAssignModal] = useState<{
    type: 'enterprise' | 'branch' | 'workshop' | 'equipment_type' | 'equipment';
    id: string;
    name: string;
  } | null>(null);
  
  // Модальное окно для просмотра карточки объекта
  const [showInfoModal, setShowInfoModal] = useState<{
    type: 'enterprise' | 'branch' | 'workshop' | 'equipment';
    id: string;
    name: string;
  } | null>(null);
  
  const [assignedEngineers, setAssignedEngineers] = useState<any[]>([]);
  const [selectedEngineers, setSelectedEngineers] = useState<string[]>([]);
  
  // Формы для создания
  const [formData, setFormData] = useState({
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

  const API_BASE = 'http://5.129.203.182:8000';

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
    await Promise.all([
      loadEnterprises(),
      loadEquipmentTypes()
    ]);
  };

  const loadUsers = async () => {
    try {
      const token = getToken();
      const headers: HeadersInit = {};
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/users?role=engineer`, {
        headers
      });
      if (response.ok) {
        const data = await response.json();
        setUsersList(data.items || []);
      } else if (response.status === 401 || response.status === 403) {
        // Если нет доступа, просто не загружаем пользователей
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
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (response.ok) {
        const data = await response.json();
        setAssignedEngineers(data.items || []);
        setSelectedEngineers(data.items.map((e: any) => e.user_id));
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
      
      console.log('Загрузка предприятий...', { API_BASE, token: token.substring(0, 20) + '...' });
      
      const response = await fetch(`${API_BASE}/api/hierarchy/enterprises`, {
        headers: { 
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      });
      
      console.log('Ответ сервера:', { status: response.status, statusText: response.statusText, ok: response.ok });
      
      if (!response.ok) {
        const errorText = await response.text();
        console.error('Ошибка загрузки предприятий:', response.status, response.statusText, errorText);
        
        if (response.status === 401) {
          // Токен недействителен, перенаправляем на страницу входа
          localStorage.removeItem('token');
          alert('Сессия истекла. Необходимо войти снова.');
          window.location.href = '/#/login';
          return;
        }
        
        // Показываем ошибку пользователю
        alert(`Ошибка загрузки предприятий: ${response.status} ${response.statusText}\n${errorText}`);
        return;
      }
      
      const data = await response.json();
      console.log('Загружены предприятия (raw):', data);
      
      // API возвращает {items: [...]}, но может быть и просто массив
      const enterprisesList = Array.isArray(data.items) ? data.items : (Array.isArray(data) ? data : []);
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
      const response = await fetch(`${API_BASE}/api/hierarchy/branches?enterprise_id=${enterpriseId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await response.json();
      setBranches(prev => ({ ...prev, [enterpriseId]: data.items || [] }));
    } catch (error) {
      console.error('Ошибка загрузки филиалов:', error);
    }
  };

  const loadWorkshops = async (branchId: string) => {
    try {
      const token = getToken();
      const response = await fetch(`${API_BASE}/api/hierarchy/workshops?branch_id=${branchId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await response.json();
      setWorkshops(prev => ({ ...prev, [branchId]: data.items || [] }));
    } catch (error) {
      console.error('Ошибка загрузки цехов:', error);
    }
  };

  const loadEquipment = async (workshopId: string) => {
    try {
      const token = getToken();
      const response = await fetch(`${API_BASE}/api/equipment?workshop_id=${workshopId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await response.json();
      setEquipment(prev => ({ ...prev, [workshopId]: data.items || [] }));
    } catch (error) {
      console.error('Ошибка загрузки оборудования:', error);
    }
  };

  const loadEquipmentTypes = async () => {
    try {
      const response = await fetch(`${API_BASE}/api/equipment-types`);
      const data = await response.json();
      setEquipmentTypes(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки типов оборудования:', error);
    }
  };

  const toggleExpand = (key: string) => {
    setExpanded(prev => ({ ...prev, [key]: !prev[key] }));
    
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

  const handleCreateClick = (type: 'enterprise' | 'branch' | 'workshop' | 'equipment_type' | 'equipment', parentId?: string, parentName?: string) => {
    setShowCreateModal({ type, parentId, parentName });
    setFormData({
      name: '',
      code: '',
      description: '',
      enterprise_id: parentId || '',
      branch_id: parentId || '',
      workshop_id: parentId || '',
      type_id: '',
      serial_number: '',
      location: '',
      commissioning_date: '',
    });
  };

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!showCreateModal) return;

    try {
      const token = getToken();
      let endpoint = '';
      let body: any = {};

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
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify(body)
      });

      if (response.ok) {
        alert(`${showCreateModal.type === 'enterprise' ? 'Предприятие' : 
               showCreateModal.type === 'branch' ? 'Филиал' :
               showCreateModal.type === 'workshop' ? 'Цех' :
               showCreateModal.type === 'equipment_type' ? 'Тип оборудования' : 'Оборудование'} успешно создано`);
        setShowCreateModal(null);
        setFormData({
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
        
        // Перезагружаем данные
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

  const handleAssignEngineers = (type: 'enterprise' | 'branch' | 'workshop' | 'equipment_type' | 'equipment', id: string, name: string) => {
    setShowAssignModal({ type, id, name });
    // Загружаем уже назначенных инженеров
    const tempInfoModal = { type, id, name };
    setShowInfoModal(tempInfoModal);
    setTimeout(() => {
      loadAssignedEngineers();
    }, 100);
  };

  const handleShowInfo = (type: 'enterprise' | 'branch' | 'workshop' | 'equipment', id: string, name: string) => {
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
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          user_ids: selectedEngineers
        })
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
          'Authorization': `Bearer ${token}`
        }
      });

      if (response.ok) {
        alert('Оборудование удалено');
        // Перезагружаем все данные
        loadData();
      } else {
        alert('Ошибка удаления оборудования');
      }
    } catch (error) {
      console.error('Ошибка удаления:', error);
      alert('Ошибка удаления оборудования');
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">Управление оборудованием</h1>
      </div>

      {/* Поиск */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
        <input
          type="text"
          placeholder="Поиск по названию..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full bg-slate-800 border border-slate-700 rounded-lg pl-10 pr-4 py-2 text-white placeholder-slate-500"
        />
      </div>

      {/* Иерархия */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        {/* Кнопка создания предприятия */}
        <div className="mb-4">
          <button
            onClick={() => handleCreateClick('enterprise')}
            className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20"
          >
            <Plus size={16} /> Создать предприятие
          </button>
        </div>

        {enterprises.map((enterprise) => (
          <div key={enterprise.id} className="mb-4">
            <div className="flex items-center justify-between p-3 bg-slate-900 rounded-lg hover:bg-slate-800 transition-colors">
              <div className="flex items-center gap-3 flex-1">
                <button
                  onClick={() => toggleExpand(`enterprise_${enterprise.id}`)}
                  className="text-slate-400 hover:text-white"
                >
                  {expanded[`enterprise_${enterprise.id}`] ? (
                    <ChevronDown size={20} />
                  ) : (
                    <ChevronRight size={20} />
                  )}
                </button>
                <Building2 className="text-accent" size={20} />
                <span className="text-white font-bold">{enterprise.name}</span>
                {enterprise.code && (
                  <span className="text-slate-400 text-sm">({enterprise.code})</span>
                )}
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => handleShowInfo('enterprise', enterprise.id, enterprise.name)}
                  className="text-blue-400 hover:text-blue-300 p-2 rounded hover:bg-slate-700"
                  title="Информация"
                >
                  <Info size={18} />
                </button>
                <button
                  onClick={() => handleAssignEngineers('enterprise', enterprise.id, enterprise.name)}
                  className="text-green-400 hover:text-green-300 p-2 rounded hover:bg-slate-700"
                  title="Назначить инженеров"
                >
                  <Users size={18} />
                </button>
                <button
                  onClick={() => handleCreateClick('branch', enterprise.id, enterprise.name)}
                  className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                  title="Создать филиал"
                >
                  <Plus size={18} />
                </button>
              </div>
            </div>

            {expanded[`enterprise_${enterprise.id}`] && (
              <div className="ml-8 mt-2 space-y-2">
                {(branches[enterprise.id] || []).map((branch) => (
                  <div key={branch.id} className="mb-2">
                    <div className="flex items-center justify-between p-2 bg-slate-900/50 rounded-lg hover:bg-slate-800 transition-colors">
                      <div className="flex items-center gap-3 flex-1">
                        <button
                          onClick={() => toggleExpand(`branch_${branch.id}`)}
                          className="text-slate-400 hover:text-white"
                        >
                          {expanded[`branch_${branch.id}`] ? (
                            <ChevronDown size={18} />
                          ) : (
                            <ChevronRight size={18} />
                          )}
                        </button>
                        <Network className="text-blue-400" size={18} />
                        <span className="text-slate-200">{branch.name}</span>
                        {branch.code && (
                          <span className="text-slate-500 text-sm">({branch.code})</span>
                        )}
                      </div>
                              <div className="flex items-center gap-2">
                                <button
                                  onClick={() => handleShowInfo('branch', branch.id, branch.name)}
                                  className="text-blue-400 hover:text-blue-300 p-2 rounded hover:bg-slate-700"
                                  title="Информация"
                                >
                                  <Info size={16} />
                                </button>
                                <button
                                  onClick={() => handleAssignEngineers('branch', branch.id, branch.name)}
                                  className="text-green-400 hover:text-green-300 p-2 rounded hover:bg-slate-700"
                                  title="Назначить инженеров"
                                >
                                  <Users size={16} />
                                </button>
                                <button
                                  onClick={() => handleCreateClick('workshop', branch.id, branch.name)}
                                  className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                                  title="Создать цех"
                                >
                                  <Plus size={16} />
                                </button>
                              </div>
                    </div>

                    {expanded[`branch_${branch.id}`] && (
                      <div className="ml-6 mt-2 space-y-2">
                        {(workshops[branch.id] || []).map((workshop) => (
                          <div key={workshop.id} className="mb-2">
                            <div className="flex items-center justify-between p-2 bg-slate-900/30 rounded-lg hover:bg-slate-800 transition-colors">
                              <div className="flex items-center gap-3 flex-1">
                                <button
                                  onClick={() => toggleExpand(`workshop_${workshop.id}`)}
                                  className="text-slate-400 hover:text-white"
                                >
                                  {expanded[`workshop_${workshop.id}`] ? (
                                    <ChevronDown size={16} />
                                  ) : (
                                    <ChevronRight size={16} />
                                  )}
                                </button>
                                <Factory className="text-green-400" size={16} />
                                <span className="text-slate-300 text-sm">{workshop.name}</span>
                                {workshop.code && (
                                  <span className="text-slate-500 text-xs">({workshop.code})</span>
                                )}
                              </div>
                              <div className="flex items-center gap-2">
                                <button
                                  onClick={() => handleShowInfo('workshop', workshop.id, workshop.name)}
                                  className="text-blue-400 hover:text-blue-300 p-2 rounded hover:bg-slate-700"
                                  title="Информация"
                                >
                                  <Info size={14} />
                                </button>
                                <button
                                  onClick={() => handleAssignEngineers('workshop', workshop.id, workshop.name)}
                                  className="text-green-400 hover:text-green-300 p-2 rounded hover:bg-slate-700"
                                  title="Назначить инженеров"
                                >
                                  <Users size={14} />
                                </button>
                                <button
                                  onClick={() => handleCreateClick('equipment', workshop.id, workshop.name)}
                                  className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                                  title="Создать оборудование"
                                >
                                  <Plus size={14} />
                                </button>
                              </div>
                            </div>

                            {expanded[`workshop_${workshop.id}`] && (
                              <div className="ml-6 mt-2 space-y-2">
                                {/* Типы оборудования */}
                                {equipmentTypes.map((type) => (
                                  <div key={type.id} className="mb-2">
                                    <div className="flex items-center justify-between p-2 bg-slate-900/20 rounded-lg hover:bg-slate-800 transition-colors">
                                      <div className="flex items-center gap-3 flex-1">
                                        <button
                                          onClick={() => toggleExpand(`type_${workshop.id}_${type.id}`)}
                                          className="text-slate-400 hover:text-white"
                                        >
                                          {expanded[`type_${workshop.id}_${type.id}`] ? (
                                            <ChevronDown size={14} />
                                          ) : (
                                            <ChevronRight size={14} />
                                          )}
                                        </button>
                                        <Box className="text-yellow-400" size={14} />
                                        <span className="text-slate-300 text-sm">{type.name}</span>
                                      </div>
                                    </div>

                                    {expanded[`type_${workshop.id}_${type.id}`] && (
                                      <div className="ml-6 mt-2 space-y-1">
                                        {(equipment[workshop.id] || [])
                                          .filter(eq => eq.type_id === type.id)
                                          .map((eq) => (
                                            <div key={eq.id} className="flex items-center justify-between p-2 bg-slate-950 rounded hover:bg-slate-900 transition-colors">
                                              <div className="flex items-center gap-2 flex-1">
                                                <MapPin className="text-slate-500" size={12} />
                                                <button
                                                  type="button"
                                                  onClick={() => navigate(`/equipment/${eq.id}`)}
                                                  className="text-slate-200 hover:text-white text-xs underline-offset-2 hover:underline text-left"
                                                  title="Открыть карточку оборудования"
                                                >
                                                  {eq.name}
                                                </button>
                                                {eq.serial_number && (
                                                  <span className="text-slate-500 text-xs">№{eq.serial_number}</span>
                                                )}
                                              </div>
                                              <div className="flex items-center gap-1">
                                                <button
                                                  onClick={() => handleShowInfo('equipment', eq.id, eq.name)}
                                                  className="text-blue-400 hover:text-blue-300 p-1"
                                                  title="Информация"
                                                >
                                                  <Info size={12} />
                                                </button>
                                                <button
                                                  onClick={() => handleAssignEngineers('equipment', eq.id, eq.name)}
                                                  className="text-green-400 hover:text-green-300 p-1"
                                                  title="Назначить инженеров"
                                                >
                                                  <Users size={12} />
                                                </button>
                                                <button
                                                  onClick={() => handleDeleteEquipment(eq.id)}
                                                  className="text-red-400 hover:text-red-300 p-1"
                                                  title="Удалить"
                                                >
                                                  <Trash2 size={12} />
                                                </button>
                                              </div>
                                            </div>
                                          ))}
                                      </div>
                                    )}
                                  </div>
                                ))}
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}

        {enterprises.length === 0 && (
          <div className="text-center text-slate-400 py-10">
            Предприятия не добавлены. Нажмите "Создать предприятие" для начала.
          </div>
        )}
      </div>

      {/* Модальное окно создания */}
      {showCreateModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowCreateModal(null)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-md w-full mx-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">
                Создать {
                  showCreateModal.type === 'enterprise' ? 'предприятие' :
                  showCreateModal.type === 'branch' ? 'филиал' :
                  showCreateModal.type === 'workshop' ? 'цех' :
                  showCreateModal.type === 'equipment_type' ? 'тип оборудования' : 'оборудование'
                }
              </h2>
              <button onClick={() => setShowCreateModal(null)} className="text-slate-400 hover:text-white">
                <X size={24} />
              </button>
            </div>
            
            {showCreateModal.parentName && (
              <p className="text-slate-400 text-sm mb-4">
                Родитель: {showCreateModal.parentName}
              </p>
            )}

            <form onSubmit={handleCreateSubmit} className="space-y-4">
              <div>
                <label className="text-sm text-slate-400 block mb-1">Название *</label>
                <input
                  type="text"
                  required
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Введите название"
                />
              </div>

              {(showCreateModal.type === 'enterprise' || showCreateModal.type === 'branch' || showCreateModal.type === 'workshop' || showCreateModal.type === 'equipment_type') && (
                <>
                  <div>
                    <label className="text-sm text-slate-400 block mb-1">Код</label>
                    <input
                      type="text"
                      value={formData.code}
                      onChange={(e) => setFormData({ ...formData, code: e.target.value })}
                      className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                      placeholder="Введите код (необязательно)"
                    />
                  </div>
                  <div>
                    <label className="text-sm text-slate-400 block mb-1">Описание</label>
                    <textarea
                      value={formData.description}
                      onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                      className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                      placeholder="Введите описание (необязательно)"
                      rows={3}
                    />
                  </div>
                </>
              )}

              {showCreateModal.type === 'equipment' && (
                <>
                  <div>
                    <label className="text-sm text-slate-400 block mb-1">Тип оборудования</label>
                    <select
                      value={formData.type_id}
                      onChange={(e) => setFormData({ ...formData, type_id: e.target.value })}
                      className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    >
                      <option value="">Выберите тип</option>
                      {equipmentTypes.map(type => (
                        <option key={type.id} value={type.id}>{type.name}</option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="text-sm text-slate-400 block mb-1">Заводской номер</label>
                    <input
                      type="text"
                      value={formData.serial_number}
                      onChange={(e) => setFormData({ ...formData, serial_number: e.target.value })}
                      className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                      placeholder="Введите заводской номер"
                    />
                  </div>
                  <div>
                    <label className="text-sm text-slate-400 block mb-1">Место расположения</label>
                    <input
                      type="text"
                      value={formData.location}
                      onChange={(e) => setFormData({ ...formData, location: e.target.value })}
                      className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                      placeholder="Введите место расположения"
                    />
                  </div>
                  <div>
                    <label className="text-sm text-slate-400 block mb-1">Дата ввода в эксплуатацию</label>
                    <input
                      type="date"
                      value={formData.commissioning_date}
                      onChange={(e) => setFormData({ ...formData, commissioning_date: e.target.value })}
                      className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    />
                  </div>
                </>
              )}

              <div className="flex gap-2">
                <button
                  type="submit"
                  className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600"
                >
                  Создать
                </button>
                <button
                  type="button"
                  onClick={() => setShowCreateModal(null)}
                  className="flex-1 bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
                >
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Модальное окно назначения инженеров */}
      {showAssignModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowAssignModal(null)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-md w-full mx-4 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">
                Назначить инженеров: {showAssignModal.name}
              </h2>
              <button onClick={() => setShowAssignModal(null)} className="text-slate-400 hover:text-white">
                <X size={24} />
              </button>
            </div>

            <form onSubmit={handleAssignSubmit} className="space-y-4">
              <div className="max-h-64 overflow-y-auto space-y-2">
                {usersList.map((user) => {
                  const isSelected = selectedEngineers.includes(user.id);
                  const isAlreadyAssigned = assignedEngineers.some(e => e.user_id === user.id);
                  return (
                    <label key={user.id} className={`flex items-center gap-3 p-3 rounded-lg border cursor-pointer ${
                      isSelected ? 'bg-accent/20 border-accent' : 'bg-slate-900 border-slate-700'
                    } ${isAlreadyAssigned ? 'opacity-75' : ''}`}>
                      <input
                        type="checkbox"
                        checked={isSelected}
                        onChange={(e) => {
                          if (e.target.checked) {
                            setSelectedEngineers([...selectedEngineers, user.id]);
                          } else {
                            setSelectedEngineers(selectedEngineers.filter(id => id !== user.id));
                          }
                        }}
                        className="w-4 h-4 text-accent rounded"
                      />
                      <div className="flex-1">
                        <div className="text-white font-medium">{user.full_name || user.username}</div>
                        {isAlreadyAssigned && (
                          <div className="text-xs text-green-400 flex items-center gap-1">
                            <UserCheck size={12} />
                            Уже назначен
                          </div>
                        )}
                      </div>
                    </label>
                  );
                })}
              </div>

              <div className="flex gap-2">
                <button
                  type="submit"
                  className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600"
                  disabled={selectedEngineers.length === 0}
                >
                  Назначить ({selectedEngineers.length})
                </button>
                <button
                  type="button"
                  onClick={() => setShowAssignModal(null)}
                  className="flex-1 bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
                >
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Модальное окно информации об объекте */}
      {showInfoModal && (
        <EquipmentInfoCard 
          modal={showInfoModal}
          onClose={() => setShowInfoModal(null)}
          onAssignEngineers={handleAssignEngineers}
          assignedEngineers={assignedEngineers}
          API_BASE={API_BASE}
        />
      )}
    </div>
  );
};

// Компонент карточки оборудования с полной информацией
interface EquipmentInfoCardProps {
  modal: {
    type: 'enterprise' | 'branch' | 'workshop' | 'equipment';
    id: string;
    name: string;
  };
  onClose: () => void;
  onAssignEngineers: (type: string, id: string, name: string) => void;
  assignedEngineers: any[];
  API_BASE: string;
}

const EquipmentInfoCard: React.FC<EquipmentInfoCardProps> = ({ modal, onClose, onAssignEngineers, assignedEngineers, API_BASE }) => {
  const [equipmentData, setEquipmentData] = useState<any>(null);
  const [inspectionHistory, setInspectionHistory] = useState<any[]>([]);
  const [repairJournal, setRepairJournal] = useState<any[]>([]);
  const [reports, setReports] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (modal.type === 'equipment') {
      loadEquipmentData();
    } else {
      setLoading(false);
    }
  }, [modal.id]);

  const loadEquipmentData = async () => {
    try {
      const token = getToken();
      const headers: HeadersInit = { 'Authorization': `Bearer ${token}` };
      
      // Загружаем данные оборудования
      const [eqRes, historyRes, repairRes, reportsRes] = await Promise.all([
        fetch(`${API_BASE}/api/equipment/${modal.id}`, { headers }).catch(() => null),
        fetch(`${API_BASE}/api/equipment/${modal.id}/inspection-history`, { headers }).catch(() => null),
        fetch(`${API_BASE}/api/equipment/${modal.id}/repair-journal`, { headers }).catch(() => null),
        fetch(`${API_BASE}/api/reports?equipment_id=${modal.id}`, { headers }).catch(() => null)
      ]);

      if (eqRes && eqRes.ok) {
        const eqData = await eqRes.json();
        setEquipmentData(eqData);
      }

      if (historyRes && historyRes.ok) {
        const historyData = await historyRes.json();
        setInspectionHistory(historyData.items || []);
      }

      if (repairRes && repairRes.ok) {
        const repairData = await repairRes.json();
        setRepairJournal(repairData.items || []);
      }

      if (reportsRes && reportsRes.ok) {
        const reportsData = await reportsRes.json();
        setReports(reportsData.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки данных оборудования:', error);
    } finally {
      setLoading(false);
    }
  };

  if (modal.type !== 'equipment') {
    // Для предприятий, филиалов, цехов - простая карточка
    return (
      <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={onClose}>
        <div className="bg-slate-800 rounded-xl p-6 max-w-lg w-full mx-4 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
          <div className="flex justify-between items-center mb-4">
            <h2 className="text-xl font-bold text-white">
              {modal.type === 'enterprise' ? 'Предприятие' :
               modal.type === 'branch' ? 'Филиал' :
               'Цех'}: {modal.name}
            </h2>
            <button onClick={onClose} className="text-slate-400 hover:text-white">
              <X size={24} />
            </button>
          </div>

          <div className="space-y-4">
            <div>
              <h3 className="text-lg font-semibold text-white mb-3 flex items-center gap-2">
                <Users className="text-accent" size={20} />
                Назначенные инженеры ({assignedEngineers.length})
              </h3>
              {assignedEngineers.length === 0 ? (
                <p className="text-slate-400">Инженеры не назначены</p>
              ) : (
                <div className="space-y-2">
                  {assignedEngineers.map((engineer) => (
                    <div key={engineer.user_id} className="bg-slate-900 rounded-lg p-3 border border-slate-700">
                      <div className="text-white font-medium">{engineer.full_name || engineer.username}</div>
                      {engineer.email && (
                        <div className="text-sm text-slate-400">{engineer.email}</div>
                      )}
                      {engineer.granted_at && (
                        <div className="text-xs text-slate-500 mt-1">
                          Назначен: {new Date(engineer.granted_at).toLocaleDateString('ru-RU')}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="flex gap-2">
              <button
                onClick={() => {
                  onClose();
                  onAssignEngineers(modal.type, modal.id, modal.name);
                }}
                className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600 flex items-center justify-center gap-2"
              >
                <Users size={18} />
                Назначить инженеров
              </button>
              <button
                onClick={onClose}
                className="flex-1 bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
              >
                Закрыть
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Для оборудования - полная карточка
  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={onClose}>
      <div className="bg-slate-800 rounded-xl p-6 max-w-4xl w-full mx-4 max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold text-white flex items-center gap-2">
            <Settings className="text-accent" size={24} />
            {modal.name}
          </h2>
          <button onClick={onClose} className="text-slate-400 hover:text-white">
            <X size={24} />
          </button>
        </div>

        {loading ? (
          <div className="text-center text-slate-400 py-10">Загрузка...</div>
        ) : (
          <div className="space-y-6">
            {/* Характеристики оборудования */}
            {equipmentData && (
              <div className="bg-slate-900 rounded-lg p-4 border border-slate-700">
                <h3 className="text-lg font-semibold text-white mb-3 flex items-center gap-2">
                  <Settings className="text-accent" size={20} />
                  Характеристики
                </h3>
                <div className="grid grid-cols-2 gap-4">
                  {equipmentData.serial_number && (
                    <div>
                      <p className="text-sm text-slate-400">Серийный номер</p>
                      <p className="text-white font-medium">{equipmentData.serial_number}</p>
                    </div>
                  )}
                  {equipmentData.location && (
                    <div>
                      <p className="text-sm text-slate-400">Местоположение</p>
                      <p className="text-white font-medium">{equipmentData.location}</p>
                    </div>
                  )}
                  {equipmentData.commissioning_date && (
                    <div>
                      <p className="text-sm text-slate-400">Дата ввода в эксплуатацию</p>
                      <p className="text-white font-medium">{new Date(equipmentData.commissioning_date).toLocaleDateString('ru-RU')}</p>
                    </div>
                  )}
                  {equipmentData.type_name && (
                    <div>
                      <p className="text-sm text-slate-400">Тип оборудования</p>
                      <p className="text-white font-medium">{equipmentData.type_name}</p>
                    </div>
                  )}
                </div>
                {equipmentData.attributes && Object.keys(equipmentData.attributes).length > 0 && (
                  <div className="mt-4">
                    <p className="text-sm text-slate-400 mb-2">Дополнительные характеристики</p>
                    <div className="bg-slate-950 rounded p-3">
                      <pre className="text-xs text-slate-300 whitespace-pre-wrap">
                        {JSON.stringify(equipmentData.attributes, null, 2)}
                      </pre>
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* История обследований */}
            <div className="bg-slate-900 rounded-lg p-4 border border-slate-700">
              <h3 className="text-lg font-semibold text-white mb-3 flex items-center gap-2">
                <FileText className="text-accent" size={20} />
                История обследований ({inspectionHistory.length})
              </h3>
              {inspectionHistory.length === 0 ? (
                <p className="text-slate-400">Обследования не проводились</p>
              ) : (
                <div className="space-y-2">
                  {inspectionHistory.slice(0, 10).map((inspection: any) => (
                    <div key={inspection.id} className="bg-slate-950 rounded p-3 border border-slate-700">
                      <div className="flex justify-between items-start">
                        <div>
                          <p className="text-white font-medium">{inspection.inspection_type || 'Обследование'}</p>
                          {inspection.inspection_date && (
                            <p className="text-sm text-slate-400">
                              {new Date(inspection.inspection_date).toLocaleDateString('ru-RU')}
                            </p>
                          )}
                          {inspection.inspector_name && (
                            <p className="text-xs text-slate-500 mt-1">Инженер: {inspection.inspector_name}</p>
                          )}
                        </div>
                        {inspection.status && (
                          <span className={`px-2 py-1 rounded text-xs ${
                            inspection.status === 'COMPLETED' ? 'bg-green-500/20 text-green-400' :
                            inspection.status === 'IN_PROGRESS' ? 'bg-blue-500/20 text-blue-400' :
                            'bg-yellow-500/20 text-yellow-400'
                          }`}>
                            {inspection.status}
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Журнал ремонтов */}
            <div className="bg-slate-900 rounded-lg p-4 border border-slate-700">
              <h3 className="text-lg font-semibold text-white mb-3 flex items-center gap-2">
                <Wrench className="text-accent" size={20} />
                Журнал ремонтов ({repairJournal.length})
              </h3>
              {repairJournal.length === 0 ? (
                <p className="text-slate-400">Ремонты не проводились</p>
              ) : (
                <div className="space-y-2">
                  {repairJournal.slice(0, 10).map((repair: any) => (
                    <div key={repair.id} className="bg-slate-950 rounded p-3 border border-slate-700">
                      <div className="flex justify-between items-start">
                        <div>
                          <p className="text-white font-medium">{repair.repair_type || 'Ремонт'}</p>
                          {repair.repair_date && (
                            <p className="text-sm text-slate-400">
                              {new Date(repair.repair_date).toLocaleDateString('ru-RU')}
                            </p>
                          )}
                          {repair.description && (
                            <p className="text-sm text-slate-300 mt-1">{repair.description}</p>
                          )}
                        </div>
                        {repair.cost && (
                          <span className="text-accent font-semibold">{repair.cost} ₽</span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Документы по диагностике */}
            <div className="bg-slate-900 rounded-lg p-4 border border-slate-700">
              <h3 className="text-lg font-semibold text-white mb-3 flex items-center gap-2">
                <FileText className="text-accent" size={20} />
                Документы по диагностике ({reports.length})
              </h3>
              {reports.length === 0 ? (
                <p className="text-slate-400">Документы отсутствуют</p>
              ) : (
                <div className="space-y-2">
                  {reports.map((report: any) => (
                    <div key={report.id} className="bg-slate-950 rounded p-3 border border-slate-700 flex items-center justify-between">
                      <div>
                        <p className="text-white font-medium">{report.title || report.report_type}</p>
                        {report.inspector_name && (
                          <p className="text-sm text-slate-400">Инженер: {report.inspector_name}</p>
                        )}
                        {report.created_at && (
                          <p className="text-xs text-slate-500">
                            {new Date(report.created_at).toLocaleDateString('ru-RU')}
                          </p>
                        )}
                      </div>
                      <div className="flex gap-2">
                        {report.file_path && (
                          <a
                            href={`${API_BASE}/${report.file_path}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="bg-accent px-3 py-1 rounded text-white text-sm hover:bg-blue-600"
                          >
                            Скачать PDF
                          </a>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Назначенные инженеры */}
            <div className="bg-slate-900 rounded-lg p-4 border border-slate-700">
              <h3 className="text-lg font-semibold text-white mb-3 flex items-center gap-2">
                <Users className="text-accent" size={20} />
                Назначенные инженеры ({assignedEngineers.length})
              </h3>
              {assignedEngineers.length === 0 ? (
                <p className="text-slate-400">Инженеры не назначены</p>
              ) : (
                <div className="space-y-2">
                  {assignedEngineers.map((engineer) => (
                    <div key={engineer.user_id} className="bg-slate-950 rounded p-3 border border-slate-700">
                      <div className="text-white font-medium">{engineer.full_name || engineer.username}</div>
                      {engineer.email && (
                        <div className="text-sm text-slate-400">{engineer.email}</div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="flex gap-2">
              <button
                onClick={() => {
                  onClose();
                  onAssignEngineers(modal.type, modal.id, modal.name);
                }}
                className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600 flex items-center justify-center gap-2"
              >
                <Users size={18} />
                Назначить инженеров
              </button>
              <button
                onClick={onClose}
                className="flex-1 bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
              >
                Закрыть
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default EquipmentManagement;
