import React, { useState, useEffect } from 'react';
import { Plus, Edit, Trash2, MapPin, Search, Building2, ChevronRight, ChevronDown, Package, Factory, UserPlus } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

interface Equipment {
  id: string;
  name: string;
  type_id?: string;
  workshop_id?: string;
  serial_number?: string;
  location?: string;
  attributes?: any;
  commissioning_date?: string;
}

interface EquipmentType {
  id: string;
  name: string;
  code?: string;
}

interface Workshop {
  id: string;
  name: string;
  code?: string;
  client_id?: string;
  branch_id?: string;
  location?: string;
}

interface Client {
  id: string;
  name: string;
}

interface Branch {
  id: string;
  name: string;
  code?: string;
  client_id: string;
  location?: string;
  description?: string;
}

interface HierarchyNode {
  id: string;
  name: string;
  type: 'client' | 'branch' | 'workshop' | 'equipment_type' | 'equipment';
  children?: HierarchyNode[];
  data?: Client | Branch | Workshop | EquipmentType | Equipment;
}

const EquipmentManagement = () => {
  const { token } = useAuth();
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [equipmentTypes, setEquipmentTypes] = useState<EquipmentType[]>([]);
  const [workshops, setWorkshops] = useState<Workshop[]>([]);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [clients, setClients] = useState<Client[]>([]);
  const [engineers, setEngineers] = useState<any[]>([]);
  const [users, setUsers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddForm, setShowAddForm] = useState(false);
  const [showWorkshopForm, setShowWorkshopForm] = useState(false);
  const [showBranchForm, setShowBranchForm] = useState(false);
  const [showAccessForm, setShowAccessForm] = useState(false);
  const [showEquipmentAccessForm, setShowEquipmentAccessForm] = useState(false);
  const [selectedWorkshop, setSelectedWorkshop] = useState<Workshop | null>(null);
  const [selectedBranch, setSelectedBranch] = useState<Branch | null>(null);
  const [selectedClient, setSelectedClient] = useState<Client | null>(null);
  const [selectedEquipmentType, setSelectedEquipmentType] = useState<EquipmentType | null>(null);
  const [selectedEquipmentForAccess, setSelectedEquipmentForAccess] = useState<Equipment | null>(null);
  const [selectedNodeForAccess, setSelectedNodeForAccess] = useState<HierarchyNode | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedEquipment, setSelectedEquipment] = useState<Equipment | null>(null);
  const [showInspections, setShowInspections] = useState(false);
  const [inspections, setInspections] = useState<any[]>([]);
  const [equipmentInspectionsCount, setEquipmentInspectionsCount] = useState<Record<string, number>>({});
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set());
  const [selectedNode, setSelectedNode] = useState<HierarchyNode | null>(null);

  const [formData, setFormData] = useState({
    name: '',
    type_id: '',
    workshop_id: '',
    serial_number: '',
    location: '',
    commissioning_date: '',
    attributes: {}
  });

  const [workshopFormData, setWorkshopFormData] = useState({
    name: '',
    code: '',
    client_id: '',
    branch_id: '',
    location: '',
    description: ''
  });

  const [branchFormData, setBranchFormData] = useState({
    name: '',
    code: '',
    client_id: '',
    location: '',
    description: ''
  });

  const [accessFormData, setAccessFormData] = useState({
    engineer_id: '',
    access_type: 'read_write'
  });

  const [equipmentAccessFormData, setEquipmentAccessFormData] = useState({
    user_id: '',
    access_type: 'read_write'
  });

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadEquipment();
    loadEquipmentTypes();
    loadWorkshops();
    loadBranches();
    loadClients();
    loadEngineers();
    loadUsers();
  }, []);

  useEffect(() => {
    // Загружаем количество диагностик для каждого оборудования
    equipment.forEach(eq => {
      fetch(`${API_BASE}/api/inspections?equipment_id=${eq.id}`)
        .then(res => res.json())
        .then(data => {
          setEquipmentInspectionsCount(prev => ({
            ...prev,
            [eq.id]: data.items?.length || 0
          }));
        })
        .catch(() => {});
    });
  }, [equipment]);

  const loadEquipment = async () => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/equipment`, { headers });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      const data = await response.json();
      setEquipment(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки оборудования:', error);
      alert('Ошибка загрузки оборудования. Проверьте авторизацию.');
    } finally {
      setLoading(false);
    }
  };

  const loadWorkshops = async () => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/workshops`, { headers });
      if (response.ok) {
        const data = await response.json();
        setWorkshops(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки цехов:', error);
    }
  };

  const loadBranches = async () => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/branches`, { headers });
      if (response.ok) {
        const data = await response.json();
        setBranches(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки филиалов:', error);
    }
  };

  const loadClients = async () => {
    try {
      const response = await fetch(`${API_BASE}/api/clients`);
      if (response.ok) {
        const data = await response.json();
        setClients(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки предприятий:', error);
    }
  };

  const loadEngineers = async () => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/engineers`, { headers });
      if (response.ok) {
        const data = await response.json();
        setEngineers(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки инженеров:', error);
    }
  };

  const loadUsers = async () => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/users`, { headers });
      if (response.ok) {
        const data = await response.json();
        // Фильтруем только инженеров
        const engineers = (data.items || []).filter((u: any) => u.role === 'engineer');
        setUsers(engineers);
      }
    } catch (error) {
      console.error('Ошибка загрузки пользователей:', error);
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

  const loadInspections = async (equipmentId: string) => {
    try {
      const response = await fetch(`${API_BASE}/api/inspections?equipment_id=${equipmentId}`);
      const data = await response.json();
      setInspections(data.items || []);
      setShowInspections(true);
    } catch (error) {
      console.error('Ошибка загрузки диагностик:', error);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/equipment`, {
        method: 'POST',
        headers,
        body: JSON.stringify(formData)
      });

      if (response.ok) {
        setShowAddForm(false);
        setFormData({
          name: '',
          type_id: '',
          workshop_id: '',
          serial_number: '',
          location: '',
          commissioning_date: '',
          attributes: {}
        });
        loadEquipment();
        alert('Оборудование успешно добавлено');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось добавить оборудование'}`);
      }
    } catch (error) {
      console.error('Ошибка создания оборудования:', error);
      alert('Ошибка создания оборудования');
    }
  };

  const handleBranchSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/branches`, {
        method: 'POST',
        headers,
        body: JSON.stringify(branchFormData)
      });
      if (response.ok) {
        setShowBranchForm(false);
        setBranchFormData({
          name: '',
          code: '',
          client_id: '',
          location: '',
          description: ''
        });
        loadBranches();
        alert('Филиал успешно добавлен');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось добавить филиал'}`);
      }
    } catch (error) {
      console.error('Ошибка создания филиала:', error);
      alert('Ошибка создания филиала');
    }
  };

  const handleWorkshopSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/workshops`, {
        method: 'POST',
        headers,
        body: JSON.stringify(workshopFormData)
      });

      if (response.ok) {
        setShowWorkshopForm(false);
        setWorkshopFormData({
          name: '',
          code: '',
          client_id: '',
          branch_id: '',
          location: '',
          description: ''
        });
        loadWorkshops();
        alert('Цех успешно добавлен');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось добавить цех'}`);
      }
    } catch (error) {
      console.error('Ошибка создания цеха:', error);
      alert('Ошибка создания цеха');
    }
  };

  const handleAccessSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedWorkshop) return;
    
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/workshops/${selectedWorkshop.id}/engineer-access`, {
        method: 'POST',
        headers,
        body: JSON.stringify(accessFormData)
      });

      if (response.ok) {
        setShowAccessForm(false);
        setAccessFormData({
          engineer_id: '',
          access_type: 'read_write'
        });
        setSelectedWorkshop(null);
        alert('Разрешение успешно предоставлено');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось предоставить разрешение'}`);
      }
    } catch (error) {
      console.error('Ошибка предоставления разрешения:', error);
      alert('Ошибка предоставления разрешения');
    }
  };

  const handleEquipmentAccessSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedEquipmentForAccess) return;
    
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/users/${equipmentAccessFormData.user_id}/equipment-access`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          equipment_id: selectedEquipmentForAccess.id,
          access_type: equipmentAccessFormData.access_type
        })
      });

      if (response.ok) {
        setShowEquipmentAccessForm(false);
        setEquipmentAccessFormData({
          user_id: '',
          access_type: 'read_write'
        });
        setSelectedEquipmentForAccess(null);
        alert('Доступ к оборудованию успешно предоставлен');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось предоставить доступ'}`);
      }
    } catch (error) {
      console.error('Ошибка предоставления доступа:', error);
      alert('Ошибка предоставления доступа');
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Вы уверены, что хотите удалить это оборудование?')) return;

    try {
      const response = await fetch(`${API_BASE}/api/equipment/${id}`, {
        method: 'DELETE'
      });

      if (response.ok) {
        loadEquipment();
        alert('Оборудование удалено');
      } else {
        alert('Ошибка удаления оборудования');
      }
    } catch (error) {
      console.error('Ошибка удаления:', error);
      alert('Ошибка удаления оборудования');
    }
  };

  const buildHierarchy = (): HierarchyNode[] => {
    const hierarchy: HierarchyNode[] = [];
    const clientMap = new Map<string, HierarchyNode>();
    const branchMap = new Map<string, HierarchyNode>();
    const workshopMap = new Map<string, HierarchyNode>();
    const equipmentTypeMap = new Map<string, HierarchyNode>();

    // Группируем оборудование по иерархии: Client -> Branch -> Workshop -> EquipmentType -> Equipment
    equipment.forEach(eq => {
      if (!eq.workshop_id) return; // Пропускаем оборудование без цеха
      
      const workshop = workshops.find(w => w.id === eq.workshop_id);
      if (!workshop) return;
      
      // Определяем клиента (через branch или напрямую через workshop)
      let clientId = 'no-client';
      let branch: Branch | undefined;
      
      if (workshop.branch_id) {
        branch = branches.find(b => b.id === workshop.branch_id);
        if (branch) {
          clientId = branch.client_id;
        }
      } else if (workshop.client_id) {
        clientId = workshop.client_id;
      }
      
      const client = clients.find(c => c.id === clientId);
      
      // Находим или создаем клиента
      let clientNode = clientMap.get(clientId);
      if (!clientNode) {
        clientNode = {
          id: `client-${clientId}`,
          name: client?.name || 'Без предприятия',
          type: 'client',
          children: [],
          data: client
        };
        clientMap.set(clientId, clientNode);
        hierarchy.push(clientNode);
      }

      // Находим или создаем филиал (если есть)
      let branchNode: HierarchyNode | null = null;
      if (branch) {
        branchNode = branchMap.get(branch.id) || null;
        if (!branchNode) {
          branchNode = {
            id: `branch-${branch.id}`,
            name: branch.name,
            type: 'branch',
            children: [],
            data: branch
          };
          branchMap.set(branch.id, branchNode);
          if (!clientNode.children) clientNode.children = [];
          clientNode.children.push(branchNode);
        }
      }

      // Находим или создаем цех
      const parentNode = branchNode || clientNode;
      let workshopNode = workshopMap.get(workshop.id);
      if (!workshopNode) {
        workshopNode = {
          id: `workshop-${workshop.id}`,
          name: workshop.name,
          type: 'workshop',
          children: [],
          data: workshop
        };
        workshopMap.set(workshop.id, workshopNode);
        if (!parentNode.children) parentNode.children = [];
        parentNode.children.push(workshopNode);
      }

      // Группируем по типам оборудования
      const typeId = eq.type_id || 'no-type';
      const equipmentType = equipmentTypes.find(et => et.id === typeId);
      
      let typeNode = equipmentTypeMap.get(`${workshop.id}-${typeId}`);
      if (!typeNode) {
        typeNode = {
          id: `equipment-type-${workshop.id}-${typeId}`,
          name: equipmentType?.name || 'Без типа',
          type: 'equipment_type',
          children: [],
          data: equipmentType
        };
        equipmentTypeMap.set(`${workshop.id}-${typeId}`, typeNode);
        if (!workshopNode.children) workshopNode.children = [];
        workshopNode.children.push(typeNode);
      }

      // Добавляем оборудование
      if (!typeNode.children) typeNode.children = [];
      typeNode.children.push({
        id: `equipment-${eq.id}`,
        name: eq.name,
        type: 'equipment',
        data: eq
      });
    });

    // Добавляем оборудование без цеха в отдельную группу
    const equipmentWithoutWorkshop = equipment.filter(eq => !eq.workshop_id);
    if (equipmentWithoutWorkshop.length > 0) {
      const noWorkshopNode: HierarchyNode = {
        id: 'no-workshop',
        name: 'Оборудование без цеха',
        type: 'workshop',
        children: equipmentWithoutWorkshop.map(eq => ({
          id: `equipment-${eq.id}`,
          name: eq.name,
          type: 'equipment',
          data: eq
        }))
      };
      hierarchy.push(noWorkshopNode);
    }

    return hierarchy;
  };

  const toggleNode = (nodeId: string) => {
    const newExpanded = new Set(expandedNodes);
    if (newExpanded.has(nodeId)) {
      newExpanded.delete(nodeId);
    } else {
      newExpanded.add(nodeId);
    }
    setExpandedNodes(newExpanded);
  };

  const renderTreeNode = (node: HierarchyNode, level: number = 0): React.ReactNode => {
    const isExpanded = expandedNodes.has(node.id);
    const hasChildren = node.children && node.children.length > 0;
    const isEquipment = node.type === 'equipment';
    const equipment = node.data as Equipment | undefined;

    const getIcon = () => {
      switch (node.type) {
        case 'client':
          return <Building2 size={16} className="text-indigo-400" />;
        case 'branch':
          return <MapPin size={16} className="text-purple-400" />;
        case 'workshop':
          return <Factory size={16} className="text-blue-400" />;
        case 'equipment_type':
          return <Package size={16} className="text-yellow-400" />;
        case 'equipment':
          return <Package size={16} className="text-green-400" />;
        default:
          return null;
      }
    };

    return (
      <div key={node.id}>
        <div
          className={`flex items-center gap-2 py-2 px-3 cursor-pointer transition-colors ${
            isEquipment
              ? 'hover:bg-slate-700/50 text-white'
              : 'hover:bg-slate-700/30 text-slate-300'
          }`}
          style={{ paddingLeft: `${level * 20 + 12}px` }}
          onClick={() => {
            if (hasChildren) toggleNode(node.id);
            if (isEquipment && equipment) {
              setSelectedEquipment(equipment);
              loadInspections(equipment.id);
            }
          }}
        >
          {hasChildren && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                toggleNode(node.id);
              }}
              className="p-0.5 hover:bg-white/10 rounded"
            >
              {isExpanded ? (
                <ChevronDown size={14} className="text-slate-400" />
              ) : (
                <ChevronRight size={14} className="text-slate-400" />
              )}
            </button>
          )}
          {!hasChildren && <div className="w-5" />}
          {getIcon()}
          <span className="flex-1 truncate">{node.name}</span>
          <div className="flex gap-1 items-center">
            {/* Кнопка назначения доступа для всех уровней кроме equipment */}
            {node.type !== 'equipment' && (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setSelectedNodeForAccess(node);
                  // Определяем тип узла и устанавливаем соответствующий selected объект
                  if (node.type === 'client') {
                    setSelectedClient(node.data as Client);
                    setSelectedBranch(null);
                    setSelectedWorkshop(null);
                    setSelectedEquipmentType(null);
                  } else if (node.type === 'branch') {
                    setSelectedBranch(node.data as Branch);
                    setSelectedClient(null);
                    setSelectedWorkshop(null);
                    setSelectedEquipmentType(null);
                  } else if (node.type === 'workshop') {
                    setSelectedWorkshop(node.data as Workshop);
                    setSelectedClient(null);
                    setSelectedBranch(null);
                    setSelectedEquipmentType(null);
                  } else if (node.type === 'equipment_type') {
                    setSelectedEquipmentType(node.data as EquipmentType);
                    setSelectedClient(null);
                    setSelectedBranch(null);
                    setSelectedWorkshop(null);
                  }
                  setShowAccessForm(true);
                }}
                className="text-blue-400 hover:text-blue-300 p-1"
                title="Назначить доступ инженеру"
              >
                <UserPlus size={14} />
              </button>
            )}
            {isEquipment && equipment && (
              <>
                {equipmentInspectionsCount[equipment.id] > 0 && (
                  <span className="text-xs text-slate-400">
                    {equipmentInspectionsCount[equipment.id]} диаг.
                  </span>
                )}
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setSelectedEquipmentForAccess(equipment);
                    setShowEquipmentAccessForm(true);
                  }}
                  className="text-blue-400 hover:text-blue-300 p-1"
                  title="Назначить доступ инженеру"
                >
                  <Edit size={14} />
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleDelete(equipment.id);
                  }}
                  className="text-red-400 hover:text-red-300 p-1"
                  title="Удалить оборудование"
                >
                  <Trash2 size={14} />
                </button>
              </>
            )}
          </div>
        </div>
        {isExpanded && hasChildren && node.children!.map(child => renderTreeNode(child, level + 1))}
      </div>
    );
  };

  const filteredEquipment = equipment.filter(eq =>
    eq.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    (eq.location && eq.location.toLowerCase().includes(searchTerm.toLowerCase())) ||
    (eq.serial_number && eq.serial_number.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-4 sm:space-y-6 px-2 sm:px-0">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 sm:gap-0">
        <h1 className="text-xl sm:text-2xl font-bold text-white">Управление оборудованием</h1>
        <div className="flex gap-2 w-full sm:w-auto">
          <button
            onClick={() => setShowBranchForm(true)}
            className="bg-purple-600/20 text-purple-400 border border-purple-600/30 px-3 sm:px-4 py-2 rounded-lg text-xs sm:text-sm font-bold flex items-center gap-2 hover:bg-purple-600/30 w-full sm:w-auto justify-center"
          >
            <MapPin size={16} /> Добавить филиал
          </button>
          <button
            onClick={() => setShowWorkshopForm(true)}
            className="bg-green-600/20 text-green-400 border border-green-600/30 px-3 sm:px-4 py-2 rounded-lg text-xs sm:text-sm font-bold flex items-center gap-2 hover:bg-green-600/30 w-full sm:w-auto justify-center"
          >
            <Building2 size={16} /> Добавить цех
          </button>
          <button
            onClick={() => setShowAddForm(true)}
            className="bg-accent/10 text-accent border border-accent/20 px-3 sm:px-4 py-2 rounded-lg text-xs sm:text-sm font-bold flex items-center gap-2 hover:bg-accent/20 w-full sm:w-auto justify-center"
          >
            <Plus size={16} /> Добавить оборудование
          </button>
        </div>
      </div>

      {/* Форма добавления */}
      {showAddForm && (
        <div className="bg-slate-800 p-4 sm:p-6 rounded-xl border border-slate-600">
          <h2 className="text-lg sm:text-xl font-bold text-white mb-3 sm:mb-4">Добавить оборудование</h2>
          <form onSubmit={handleSubmit} className="space-y-3 sm:space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
              <div>
                <label className="text-sm text-slate-400 block mb-1">Название *</label>
                <input
                  type="text"
                  required
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Например: Сосуд В-101"
                />
              </div>
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
                <label className="text-sm text-slate-400 block mb-1">Цех</label>
                <select
                  value={formData.workshop_id}
                  onChange={(e) => setFormData({ ...formData, workshop_id: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                >
                  <option value="">Выберите цех</option>
                  {workshops.map(workshop => (
                    <option key={workshop.id} value={workshop.id}>{workshop.name}</option>
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
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Место расположения *</label>
                <input
                  type="text"
                  required
                  value={formData.location}
                  onChange={(e) => setFormData({ ...formData, location: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="НГДУ, цех, месторождение"
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
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80"
              >
                Сохранить
              </button>
              <button
                type="button"
                onClick={() => setShowAddForm(false)}
                className="bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
              >
                Отмена
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Форма добавления филиала */}
      {showBranchForm && (
        <div className="bg-slate-800 p-4 sm:p-6 rounded-xl border border-slate-600">
          <h2 className="text-lg sm:text-xl font-bold text-white mb-3 sm:mb-4">Добавить филиал</h2>
          <form onSubmit={handleBranchSubmit} className="space-y-3 sm:space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
              <div>
                <label className="text-sm text-slate-400 block mb-1">Название филиала *</label>
                <input
                  type="text"
                  required
                  value={branchFormData.name}
                  onChange={(e) => setBranchFormData({ ...branchFormData, name: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Например: Сургутский ЗСК"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Код филиала</label>
                <input
                  type="text"
                  value={branchFormData.code}
                  onChange={(e) => setBranchFormData({ ...branchFormData, code: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Например: BR-1"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Предприятие *</label>
                <select
                  required
                  value={branchFormData.client_id}
                  onChange={(e) => setBranchFormData({ ...branchFormData, client_id: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                >
                  <option value="">Выберите предприятие</option>
                  {clients.map(client => (
                    <option key={client.id} value={client.id}>{client.name}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Местоположение</label>
                <input
                  type="text"
                  value={branchFormData.location}
                  onChange={(e) => setBranchFormData({ ...branchFormData, location: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Адрес филиала"
                />
              </div>
              <div className="sm:col-span-2">
                <label className="text-sm text-slate-400 block mb-1">Описание</label>
                <textarea
                  value={branchFormData.description}
                  onChange={(e) => setBranchFormData({ ...branchFormData, description: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  rows={3}
                  placeholder="Дополнительная информация о филиале"
                />
              </div>
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-purple-600 px-4 py-2 rounded-lg text-white font-bold hover:bg-purple-700"
              >
                Сохранить
              </button>
              <button
                type="button"
                onClick={() => setShowBranchForm(false)}
                className="bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
              >
                Отмена
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Форма добавления цеха */}
      {showWorkshopForm && (
        <div className="bg-slate-800 p-4 sm:p-6 rounded-xl border border-slate-600">
          <h2 className="text-lg sm:text-xl font-bold text-white mb-3 sm:mb-4">Добавить цех</h2>
          <form onSubmit={handleWorkshopSubmit} className="space-y-3 sm:space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
              <div>
                <label className="text-sm text-slate-400 block mb-1">Название цеха *</label>
                <input
                  type="text"
                  required
                  value={workshopFormData.name}
                  onChange={(e) => setWorkshopFormData({ ...workshopFormData, name: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Например: Цех подготовки нефти №1"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Код цеха</label>
                <input
                  type="text"
                  value={workshopFormData.code}
                  onChange={(e) => setWorkshopFormData({ ...workshopFormData, code: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Например: CPN-1"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Предприятие</label>
                <select
                  value={workshopFormData.client_id}
                  onChange={(e) => setWorkshopFormData({ ...workshopFormData, client_id: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                >
                  <option value="">Выберите предприятие</option>
                  {clients.map(client => (
                    <option key={client.id} value={client.id}>{client.name}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Местоположение</label>
                <input
                  type="text"
                  value={workshopFormData.location}
                  onChange={(e) => setWorkshopFormData({ ...workshopFormData, location: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Площадка, месторождение и т.д."
                />
              </div>
              <div className="sm:col-span-2">
                <label className="text-sm text-slate-400 block mb-1">Описание</label>
                <textarea
                  value={workshopFormData.description}
                  onChange={(e) => setWorkshopFormData({ ...workshopFormData, description: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  rows={3}
                />
              </div>
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-green-600 px-4 py-2 rounded-lg text-white font-bold hover:bg-green-700"
              >
                Сохранить
              </button>
              <button
                type="button"
                onClick={() => setShowWorkshopForm(false)}
                className="bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
              >
                Отмена
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Список цехов с управлением разрешениями */}
      {workshops.length > 0 && (
        <div className="bg-slate-800 p-4 sm:p-6 rounded-xl border border-slate-600">
          <h2 className="text-lg sm:text-xl font-bold text-white mb-4">Цеха и разрешения</h2>
          <div className="space-y-3">
            {workshops.map(workshop => (
              <div key={workshop.id} className="bg-slate-900 p-3 rounded-lg border border-slate-700">
                <div className="flex justify-between items-start">
                  <div>
                    <h3 className="text-white font-bold">{workshop.name}</h3>
                    {workshop.code && <p className="text-slate-400 text-sm">Код: {workshop.code}</p>}
                    {workshop.location && <p className="text-slate-400 text-sm">{workshop.location}</p>}
                  </div>
                  <button
                    onClick={() => {
                      setSelectedWorkshop(workshop);
                      setShowAccessForm(true);
                    }}
                    className="bg-blue-600 px-3 py-1 rounded text-white text-sm hover:bg-blue-700"
                  >
                    Настроить доступ
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Форма назначения доступа к конкретному оборудованию */}
      {showEquipmentAccessForm && selectedEquipmentForAccess && (
        <div className="bg-slate-800 p-4 sm:p-6 rounded-xl border border-slate-600">
          <h2 className="text-lg sm:text-xl font-bold text-white mb-3 sm:mb-4">
            Назначить доступ к оборудованию: {selectedEquipmentForAccess.name}
          </h2>
          <form onSubmit={handleEquipmentAccessSubmit} className="space-y-3 sm:space-y-4">
            <div>
              <label className="text-sm text-slate-400 block mb-1">Инженер (пользователь) *</label>
              <select
                required
                value={equipmentAccessFormData.user_id}
                onChange={(e) => setEquipmentAccessFormData({ ...equipmentAccessFormData, user_id: e.target.value })}
                className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
              >
                <option value="">Выберите инженера</option>
                {users.map(user => (
                  <option key={user.id} value={user.id}>
                    {user.full_name || user.username} {user.username ? `(${user.username})` : ''}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="text-sm text-slate-400 block mb-1">Тип доступа *</label>
              <select
                required
                value={equipmentAccessFormData.access_type}
                onChange={(e) => setEquipmentAccessFormData({ ...equipmentAccessFormData, access_type: e.target.value })}
                className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
              >
                <option value="read_only">Только просмотр</option>
                <option value="read_write">Просмотр и редактирование</option>
              </select>
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-blue-600 px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-700"
              >
                Сохранить доступ
              </button>
              <button
                type="button"
                onClick={() => {
                  setShowEquipmentAccessForm(false);
                  setSelectedEquipmentForAccess(null);
                }}
                className="bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
              >
                Отмена
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Форма настройки разрешений для всех уровней иерархии */}
      {showAccessForm && selectedNodeForAccess && (
        <div className="bg-slate-800 p-4 sm:p-6 rounded-xl border border-slate-600">
          <h2 className="text-lg sm:text-xl font-bold text-white mb-3 sm:mb-4">
            Настройка доступа: {selectedNodeForAccess.name}
            {selectedNodeForAccess.type === 'client' && ' (Предприятие)'}
            {selectedNodeForAccess.type === 'branch' && ' (Филиал)'}
            {selectedNodeForAccess.type === 'workshop' && ' (Цех)'}
            {selectedNodeForAccess.type === 'equipment_type' && ' (Тип оборудования)'}
          </h2>
          <form onSubmit={handleAccessSubmit} className="space-y-3 sm:space-y-4">
            <div>
              <label className="text-sm text-slate-400 block mb-1">Инженер (специалист) *</label>
              <select
                required
                value={accessFormData.engineer_id}
                onChange={(e) => setAccessFormData({ ...accessFormData, engineer_id: e.target.value })}
                className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
              >
                <option value="">Выберите инженера</option>
                {engineers.map(engineer => {
                  // Находим пользователя, связанного с этим инженером
                  const user = users.find(u => u.engineer_id === engineer.id);
                  return (
                    <option key={engineer.id} value={engineer.id}>
                      {engineer.full_name} {user?.username ? `(${user.username})` : ''}
                    </option>
                  );
                })}
              </select>
            </div>
            <div>
              <label className="text-sm text-slate-400 block mb-1">Тип доступа *</label>
              <select
                required
                value={accessFormData.access_type}
                onChange={(e) => setAccessFormData({ ...accessFormData, access_type: e.target.value })}
                className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
              >
                <option value="read">Только просмотр</option>
                <option value="read_write">Просмотр и редактирование</option>
                <option value="create_equipment">Создание оборудования</option>
              </select>
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-blue-600 px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-700"
              >
                Сохранить разрешение
              </button>
              <button
                type="button"
                onClick={() => {
                  setShowAccessForm(false);
                  setSelectedWorkshop(null);
                }}
                className="bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
              >
                Отмена
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Поиск */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
        <input
          type="text"
          placeholder="Поиск по названию, местоположению, номеру..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full bg-slate-800 border border-slate-700 rounded-lg pl-10 pr-4 py-2 text-white placeholder-slate-500"
        />
      </div>

      {/* Иерархический список оборудования */}
      <div className="bg-slate-800 rounded-xl border border-slate-600 overflow-hidden">
        <div className="p-4 border-b border-slate-700">
          <h2 className="text-lg font-bold text-white">Оборудование</h2>
        </div>
        <div className="max-h-[600px] overflow-y-auto">
          {loading ? (
            <div className="text-center text-slate-400 py-20">Загрузка...</div>
          ) : searchTerm ? (
            // При поиске показываем плоский список
            <div className="p-4 space-y-2">
              {filteredEquipment.map((eq) => (
                <div
                  key={eq.id}
                  className="bg-slate-900 p-3 rounded-lg border border-slate-700 hover:border-accent/50 transition-colors cursor-pointer"
                  onClick={() => {
                    setSelectedEquipment(eq);
                    loadInspections(eq.id);
                  }}
                >
                  <div className="flex justify-between items-start mb-2">
                    <div className="flex items-center gap-2">
                      <Package size={16} className="text-green-400" />
                      <h3 className="font-bold text-white">{eq.name}</h3>
                    </div>
                    <div className="flex gap-2">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          setSelectedEquipmentForAccess(eq);
                          setShowEquipmentAccessForm(true);
                        }}
                        className="text-blue-400 hover:text-blue-300"
                        title="Назначить доступ инженеру"
                      >
                        <Edit size={14} />
                      </button>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleDelete(eq.id);
                        }}
                        className="text-red-400 hover:text-red-300"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </div>
                  {eq.workshop_id && (
                    <div className="flex items-center gap-2 text-blue-400 mb-1 text-sm">
                      <Factory size={14} />
                      <span>{workshops.find(w => w.id === eq.workshop_id)?.name || 'Цех не найден'}</span>
                    </div>
                  )}
                  {eq.location && (
                    <div className="flex items-center gap-2 text-accent mb-1 text-sm">
                      <MapPin size={14} />
                      <span>{eq.location}</span>
                    </div>
                  )}
                  {eq.serial_number && (
                    <p className="text-sm text-slate-400">№ {eq.serial_number}</p>
                  )}
                </div>
              ))}
              {filteredEquipment.length === 0 && (
                <div className="text-center text-slate-400 py-10">Оборудование не найдено</div>
              )}
            </div>
          ) : (
            // Иерархическое дерево
            <div className="p-4">
              {buildHierarchy().map(node => renderTreeNode(node))}
              {buildHierarchy().length === 0 && (
                <div className="text-center text-slate-400 py-20">Оборудование не добавлено</div>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Модальное окно с диагностиками */}
      {showInspections && selectedEquipment && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowInspections(false)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-4xl w-full mx-4 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">Диагностики: {selectedEquipment.name}</h2>
              <button onClick={() => setShowInspections(false)} className="text-slate-400 hover:text-white">✕</button>
            </div>
            {inspections.length === 0 ? (
              <p className="text-slate-400">Диагностики не найдены</p>
            ) : (
              <div className="space-y-4">
                {inspections.map((insp) => (
                  <div key={insp.id} className="bg-slate-900 p-4 rounded-lg border border-slate-700">
                    <div className="flex justify-between items-start mb-2">
                      <div>
                        <p className="text-white font-bold">{insp.date_performed ? new Date(insp.date_performed).toLocaleDateString('ru-RU') : 'Дата не указана'}</p>
                        <p className="text-sm text-slate-400">Статус: {insp.status}</p>
                      </div>
                    </div>
                    {insp.conclusion && (
                      <p className="text-slate-300 mt-2">{insp.conclusion}</p>
                    )}
                    {insp.data && (
                      <details className="mt-2">
                        <summary className="text-sm text-accent cursor-pointer">Детали диагностики</summary>
                        <pre className="mt-2 text-xs text-slate-400 overflow-auto bg-slate-950 p-2 rounded">
                          {JSON.stringify(insp.data, null, 2)}
                        </pre>
                      </details>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default EquipmentManagement;

