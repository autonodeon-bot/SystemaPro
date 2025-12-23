import React, { useState, useEffect } from 'react';
import { Plus, ChevronRight, ChevronDown, UserPlus, Users, Building2, Network, Factory, Box } from 'lucide-react';

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
  workshop_id?: string;
}

interface User {
  id: string;
  username: string;
  full_name?: string;
  role: string;
}

const EquipmentHierarchy = () => {
  const [enterprises, setEnterprises] = useState<Enterprise[]>([]);
  const [branches, setBranches] = useState<Record<string, Branch[]>>({});
  const [workshops, setWorkshops] = useState<Record<string, Workshop[]>>({});
  const [equipmentTypes, setEquipmentTypes] = useState<EquipmentType[]>([]);
  const [equipment, setEquipment] = useState<Record<string, Equipment[]>>({});
  const [users, setUsers] = useState<User[]>([]);
  
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [showAssignModal, setShowAssignModal] = useState<{
    type: 'enterprise' | 'branch' | 'workshop' | 'equipment_type' | 'equipment';
    id: string;
    name: string;
  } | null>(null);
  const [selectedEngineers, setSelectedEngineers] = useState<string[]>([]);

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    await Promise.all([
      loadEnterprises(),
      loadEquipmentTypes(),
      loadUsers()
    ]);
  };

  const loadEnterprises = async () => {
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/hierarchy/enterprises`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await response.json();
      setEnterprises(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки предприятий:', error);
    }
  };

  const loadBranches = async (enterpriseId: string) => {
    try {
      const token = localStorage.getItem('token');
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
      const token = localStorage.getItem('token');
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
      const token = localStorage.getItem('token');
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

  const loadUsers = async () => {
    try {
      const token = localStorage.getItem('token');
      if (!token) {
        console.error('Токен авторизации отсутствует');
        return;
      }
      const response = await fetch(`${API_BASE}/api/users`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (!response.ok) {
        console.error('Ошибка загрузки пользователей:', response.status, response.statusText);
        return;
      }
      const data = await response.json();
      console.log('Загружены пользователи:', data);
      const engineers = (data.items || []).filter((u: User) => u.role === 'engineer');
      console.log('Отфильтрованы инженеры:', engineers);
      setUsers(engineers);
    } catch (error) {
      console.error('Ошибка загрузки пользователей:', error);
    }
  };

  const toggleExpand = (key: string) => {
    setExpanded(prev => ({ ...prev, [key]: !prev[key] }));
    
    // Загружаем данные при раскрытии
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

  const handleAssignEngineers = (type: 'enterprise' | 'branch' | 'workshop' | 'equipment_type' | 'equipment', id: string, name: string) => {
    setShowAssignModal({ type, id, name });
    setSelectedEngineers([]);
    // Перезагружаем список пользователей при открытии модального окна
    if (users.length === 0) {
      loadUsers();
    }
  };

  const submitAssignment = async () => {
    if (!showAssignModal || selectedEngineers.length === 0) {
      alert('Выберите хотя бы одного инженера');
      return;
    }

    try {
      const token = localStorage.getItem('token');
      if (!token) {
        alert('Ошибка: Токен авторизации отсутствует. Пожалуйста, войдите в систему заново.');
        return;
      }

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
          alert('Неизвестный тип назначения');
          return;
      }

      console.log('Отправка запроса на:', endpoint);
      console.log('Данные:', { user_ids: selectedEngineers });

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

      console.log('Ответ сервера:', response.status, response.statusText);

      if (response.ok) {
        const result = await response.json();
        alert('Инженеры успешно назначены');
        setShowAssignModal(null);
        setSelectedEngineers([]);
      } else {
        const error = await response.json().catch(() => ({ detail: 'Неизвестная ошибка' }));
        console.error('Ошибка сервера:', error);
        alert(`Ошибка: ${error.detail || 'Не удалось назначить инженеров'}`);
      }
    } catch (error: any) {
      console.error('Ошибка назначения инженеров:', error);
      alert(`Ошибка назначения инженеров: ${error.message || 'Неизвестная ошибка'}`);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">Оборудование для диагностики</h1>
      </div>

      {/* Иерархия */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
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
              <button
                onClick={() => handleAssignEngineers('enterprise', enterprise.id, enterprise.name)}
                className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                title="Назначить инженеров"
              >
                <UserPlus size={18} />
              </button>
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
                      <button
                        onClick={() => handleAssignEngineers('branch', branch.id, branch.name)}
                        className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                        title="Назначить инженеров"
                      >
                        <UserPlus size={16} />
                      </button>
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
                              <button
                                onClick={() => handleAssignEngineers('workshop', workshop.id, workshop.name)}
                                className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                                title="Назначить инженеров"
                              >
                                <UserPlus size={14} />
                              </button>
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
                                      <button
                                        onClick={() => handleAssignEngineers('equipment_type', type.id, type.name)}
                                        className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                                        title="Назначить инженеров"
                                      >
                                        <UserPlus size={12} />
                                      </button>
                                    </div>

                                    {expanded[`type_${workshop.id}_${type.id}`] && (
                                      <div className="ml-6 mt-2 space-y-1">
                                        {(equipment[workshop.id] || [])
                                          .filter(eq => eq.type_id === type.id)
                                          .map((eq) => (
                                            <div key={eq.id} className="flex items-center justify-between p-2 bg-slate-950 rounded hover:bg-slate-900 transition-colors">
                                              <span className="text-slate-400 text-xs">{eq.name}</span>
                                              <button
                                                onClick={() => handleAssignEngineers('equipment', eq.id, eq.name)}
                                                className="text-accent hover:text-blue-400 p-1 rounded hover:bg-slate-800"
                                                title="Назначить инженеров"
                                              >
                                                <UserPlus size={12} />
                                              </button>
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
            Предприятия не добавлены. Обратитесь к администратору.
          </div>
        )}
      </div>

      {/* Модальное окно назначения инженеров */}
      {showAssignModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowAssignModal(null)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-md w-full mx-4" onClick={(e) => e.stopPropagation()}>
            <h2 className="text-xl font-bold text-white mb-4">
              Назначить инженеров: {showAssignModal.name}
            </h2>
            {users.length === 0 ? (
              <div className="text-slate-400 text-sm mb-4">
                Загрузка списка инженеров... Если список не загружается, проверьте консоль браузера (F12).
              </div>
            ) : (
              <div className="space-y-2 max-h-64 overflow-y-auto mb-4">
                {users.map((user) => (
                  <label key={user.id} className="flex items-center gap-2 p-2 bg-slate-900 rounded hover:bg-slate-800 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={selectedEngineers.includes(user.id)}
                      onChange={(e) => {
                        if (e.target.checked) {
                          setSelectedEngineers([...selectedEngineers, user.id]);
                        } else {
                          setSelectedEngineers(selectedEngineers.filter(id => id !== user.id));
                        }
                      }}
                      className="rounded"
                    />
                    <span className="text-white text-sm">
                      {user.full_name || user.username}
                    </span>
                  </label>
                ))}
              </div>
            )}
            <div className="flex gap-2">
              <button
                onClick={(e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  submitAssignment();
                }}
                disabled={selectedEngineers.length === 0}
                className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Назначить {selectedEngineers.length > 0 ? `(${selectedEngineers.length})` : '(0)'}
              </button>
              <button
                onClick={(e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  setShowAssignModal(null);
                }}
                className="flex-1 bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
              >
                Отмена
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default EquipmentHierarchy;

