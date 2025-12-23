import React, { useState, useEffect, useMemo } from 'react';
import { ClipboardList, Plus, Filter, CheckCircle, Clock, XCircle, AlertCircle, Search, ChevronDown, ChevronRight, List, Layers, Download, Edit, Trash2, ArrowUpDown, Calendar, User, Building2, MapPin, Settings } from 'lucide-react';

interface Assignment {
  id: string;
  equipment_id: string;
  equipment_code: string;
  equipment_name: string;
  assignment_type: string;
  assigned_by: string | null;
  assigned_to: string;
  assigned_to_name: string | null;
  status: string;
  priority: string;
  due_date: string | null;
  description: string | null;
  created_at: string;
  updated_at: string | null;
  completed_at: string | null;
  enterprise_id?: string | null;
  enterprise_name?: string | null;
  branch_id?: string | null;
  branch_name?: string | null;
  workshop_id?: string | null;
  workshop_name?: string | null;
}

const AssignmentsManagement = () => {
  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterType, setFilterType] = useState<string>('all');
  const [filterPriority, setFilterPriority] = useState<string>('all');
  const [filterEngineer, setFilterEngineer] = useState<string>('all');
  const [filterEnterprise, setFilterEnterprise] = useState<string>('all');
  const [sortBy, setSortBy] = useState<string>('created_at');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');
  const [viewMode, setViewMode] = useState<'list' | 'hierarchy'>('hierarchy');
  const [expandedHierarchy, setExpandedHierarchy] = useState<Record<string, boolean>>({});
  const [searchQuery, setSearchQuery] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [equipmentList, setEquipmentList] = useState<any[]>([]);
  const [engineersList, setEngineersList] = useState<any[]>([]);
  const [statistics, setStatistics] = useState<any[]>([]);
  const [showStatistics, setShowStatistics] = useState(false);
  const [objectStats, setObjectStats] = useState<any[]>([]);
  const [showObjectStats, setShowObjectStats] = useState(false);
  const [selectedAssignments, setSelectedAssignments] = useState<Set<string>>(new Set());
  const [showFilters, setShowFilters] = useState(true);
  const [groupBy, setGroupBy] = useState<'none' | 'enterprise' | 'branch' | 'workshop' | 'engineer' | 'status' | 'priority'>('enterprise');

  useEffect(() => {
    loadAssignments();
    loadEquipment();
    loadEngineers();
    loadStatistics();
    loadObjectStatistics();
  }, []);

  const loadStatistics = async () => {
    try {
      const token = localStorage.getItem('token');
      const API_BASE = 'http://5.129.203.182:8000';
      const response = await fetch(`${API_BASE}/api/assignments/statistics/engineers`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      if (response.ok) {
        const data = await response.json();
        setStatistics(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки статистики:', error);
    }
  };

  const loadAssignments = async () => {
    try {
      const token = localStorage.getItem('token');
      const API_BASE = 'http://5.129.203.182:8000';
      const response = await fetch(`${API_BASE}/api/assignments`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      if (response.ok) {
        const data = await response.json();
        // Логируем для отладки
        if (data.length > 0 && !data[0].enterprise_name) {
          console.log('⚠️ Assignment without enterprise_name:', data[0]);
        }
        setAssignments(data);
      }
    } catch (error) {
      console.error('Ошибка загрузки заданий:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadEquipment = async () => {
    try {
      const token = localStorage.getItem('token');
      const API_BASE = 'http://5.129.203.182:8000';
      const response = await fetch(`${API_BASE}/api/equipment?limit=1000`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      if (response.ok) {
        const data = await response.json();
        setEquipmentList(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки оборудования:', error);
    }
  };

  const loadEngineers = async () => {
    try {
      const token = localStorage.getItem('token');
      const API_BASE = 'http://5.129.203.182:8000';
      const response = await fetch(`${API_BASE}/api/users?role=engineer`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      if (response.ok) {
        const data = await response.json();
        setEngineersList(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки инженеров:', error);
    }
  };

  const loadObjectStatistics = async () => {
    try {
      const token = localStorage.getItem('token');
      const API_BASE = 'http://5.129.203.182:8000';
      const response = await fetch(`${API_BASE}/api/assignments/statistics/objects`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      if (response.ok) {
        const data = await response.json();
        setObjectStats(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки статистики по объектам:', error);
    }
  };

  const getObjectTypeLabel = (t: string) => {
    const labels: { [key: string]: string } = {
      'enterprise': 'Предприятие',
      'branch': 'Филиал',
      'workshop': 'Цех',
      'equipment_type': 'Тип оборудования',
      'equipment': 'Оборудование',
    };
    return labels[t] || t;
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'COMPLETED':
        return <CheckCircle className="text-green-400" size={20} />;
      case 'IN_PROGRESS':
        return <Clock className="text-blue-400" size={20} />;
      case 'CANCELLED':
        return <XCircle className="text-red-400" size={20} />;
      default:
        return <AlertCircle className="text-yellow-400" size={20} />;
    }
  };

  const getStatusLabel = (status: string) => {
    const labels: { [key: string]: string } = {
      'PENDING': 'Ожидает',
      'IN_PROGRESS': 'В работе',
      'COMPLETED': 'Завершено',
      'CANCELLED': 'Отменено'
    };
    return labels[status] || status;
  };

  const getTypeLabel = (type: string) => {
    const labels: { [key: string]: string } = {
      'DIAGNOSTICS': 'Диагностика',
      'EXPERTISE': 'Экспертиза ПБ',
      'INSPECTION': 'Обследование'
    };
    return labels[type] || type;
  };

  const getPriorityColor = (priority: string) => {
    const colors: { [key: string]: string } = {
      'LOW': 'bg-slate-500',
      'NORMAL': 'bg-blue-500',
      'HIGH': 'bg-orange-500',
      'URGENT': 'bg-red-500'
    };
    return colors[priority] || 'bg-slate-500';
  };

  const filteredAssignments = useMemo(() => {
    return assignments.filter(assignment => {
      const matchesStatus = filterStatus === 'all' || assignment.status === filterStatus;
      const matchesType = filterType === 'all' || assignment.assignment_type === filterType;
      const matchesPriority = filterPriority === 'all' || assignment.priority === filterPriority;
      const matchesEngineer = filterEngineer === 'all' || assignment.assigned_to === filterEngineer;
      const matchesEnterprise = filterEnterprise === 'all' || assignment.enterprise_id === filterEnterprise;
      const matchesSearch = searchQuery === '' || 
        assignment.equipment_code.toLowerCase().includes(searchQuery.toLowerCase()) ||
        assignment.equipment_name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        (assignment.assigned_to_name && assignment.assigned_to_name.toLowerCase().includes(searchQuery.toLowerCase())) ||
        (assignment.enterprise_name && assignment.enterprise_name.toLowerCase().includes(searchQuery.toLowerCase())) ||
        (assignment.branch_name && assignment.branch_name.toLowerCase().includes(searchQuery.toLowerCase())) ||
        (assignment.workshop_name && assignment.workshop_name.toLowerCase().includes(searchQuery.toLowerCase()));
      
      return matchesStatus && matchesType && matchesPriority && matchesEngineer && matchesEnterprise && matchesSearch;
    }).sort((a, b) => {
      let comparison = 0;
      switch (sortBy) {
        case 'created_at':
          comparison = new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
          break;
        case 'due_date':
          const aDate = a.due_date ? new Date(a.due_date).getTime() : 0;
          const bDate = b.due_date ? new Date(b.due_date).getTime() : 0;
          comparison = aDate - bDate;
          break;
        case 'priority':
          const priorityOrder = { 'URGENT': 4, 'HIGH': 3, 'NORMAL': 2, 'LOW': 1 };
          comparison = (priorityOrder[a.priority as keyof typeof priorityOrder] || 0) - (priorityOrder[b.priority as keyof typeof priorityOrder] || 0);
          break;
        case 'status':
          const statusOrder = { 'PENDING': 1, 'IN_PROGRESS': 2, 'COMPLETED': 3, 'CANCELLED': 4 };
          comparison = (statusOrder[a.status as keyof typeof statusOrder] || 0) - (statusOrder[b.status as keyof typeof statusOrder] || 0);
          break;
        case 'equipment_name':
          comparison = a.equipment_name.localeCompare(b.equipment_name);
          break;
        default:
          comparison = 0;
      }
      return sortOrder === 'asc' ? comparison : -comparison;
    });
  }, [assignments, filterStatus, filterType, filterPriority, filterEngineer, filterEnterprise, searchQuery, sortBy, sortOrder]);

  // Группировка заданий для иерархического вида
  const groupedAssignments = useMemo(() => {
    if (groupBy === 'none' || viewMode === 'list') {
      return { 'all': filteredAssignments };
    }

    const groups: Record<string, Assignment[]> = {};
    
    filteredAssignments.forEach(assignment => {
      let key = 'other';
      switch (groupBy) {
        case 'enterprise':
          // Для группировки по предприятию: если есть предприятие - используем его, иначе филиал, иначе цех
          if (assignment.enterprise_name) {
            key = assignment.enterprise_name;
          } else if (assignment.branch_name) {
            key = `[Филиал] ${assignment.branch_name}`;
          } else if (assignment.workshop_name) {
            key = `[Цех] ${assignment.workshop_name}`;
          } else {
            key = 'Без предприятия';
          }
          break;
        case 'branch':
          // Для группировки по филиалу: если есть филиал - используем его, иначе цех
          if (assignment.branch_name) {
            key = assignment.branch_name;
          } else if (assignment.workshop_name) {
            key = `[Цех] ${assignment.workshop_name}`;
          } else {
            key = 'Без филиала';
          }
          break;
        case 'workshop':
          key = assignment.workshop_name || 'Без цеха';
          break;
        case 'engineer':
          key = assignment.assigned_to_name || 'Не назначено';
          break;
        case 'status':
          key = getStatusLabel(assignment.status);
          break;
        case 'priority':
          key = assignment.priority;
          break;
      }
      
      if (!groups[key]) {
        groups[key] = [];
      }
      groups[key].push(assignment);
    });

    return groups;
  }, [filteredAssignments, groupBy, viewMode]);

  const enterprises = useMemo(() => {
    const entSet = new Set<string>();
    assignments.forEach(a => {
      if (a.enterprise_id && a.enterprise_name) {
        entSet.add(a.enterprise_id);
      }
    });
    return Array.from(entSet).map(id => {
      const assignment = assignments.find(a => a.enterprise_id === id);
      return { id, name: assignment?.enterprise_name || '' };
    });
  }, [assignments]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-slate-400">Загрузка заданий...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <ClipboardList className="text-accent" size={32} />
          <h1 className="text-3xl font-bold text-white">Управление заданиями</h1>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setShowObjectStats(!showObjectStats)}
            className="flex items-center gap-2 bg-slate-700 hover:bg-slate-600 text-white px-4 py-2 rounded-lg transition-colors"
          >
            <span>Назначения по объектам</span>
          </button>
          <button
            onClick={() => setShowStatistics(!showStatistics)}
            className="flex items-center gap-2 bg-slate-700 hover:bg-slate-600 text-white px-4 py-2 rounded-lg transition-colors"
          >
            <span>Статистика по инженерам</span>
          </button>
          <button
            onClick={() => setShowCreateModal(true)}
            className="flex items-center gap-2 bg-accent hover:bg-blue-600 text-white px-4 py-2 rounded-lg transition-colors"
          >
            <Plus size={20} />
            <span>Создать задание</span>
          </button>
        </div>
      </div>

      {/* Назначения инженеров по объектам + прогресс */}
      {showObjectStats && (
        <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
          <h2 className="text-xl font-bold text-white mb-4">Назначения по объектам и прогресс</h2>
          {objectStats.length === 0 ? (
            <div className="text-slate-400">Нет данных по назначениям</div>
          ) : (
            <div className="space-y-3">
              {objectStats.map((obj: any) => (
                <div key={`${obj.object_type}-${obj.object_id}`} className="bg-slate-900 rounded-lg p-4 border border-slate-700">
                  <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-2">
                    <div>
                      <div className="text-white font-semibold">{obj.object_name}</div>
                      <div className="text-xs text-slate-500">{getObjectTypeLabel(obj.object_type)}</div>
                    </div>
                  </div>

                  <div className="mt-3 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                    {(obj.engineers || []).map((eng: any) => (
                      <div key={eng.user_id} className="bg-slate-800 rounded-lg p-3 border border-slate-700">
                        <div className="text-white font-semibold">{eng.full_name || eng.username}</div>
                        <div className="text-xs text-slate-400 mt-1">
                          Выполнено: <span className="text-green-400 font-bold">{eng.completed}</span> /{' '}
                          <span className="text-white font-bold">{eng.total}</span>
                          {' '}· Осталось: <span className="text-yellow-400 font-bold">{eng.remaining}</span>
                        </div>
                        <div className="mt-2 w-full bg-slate-700 rounded-full h-2 overflow-hidden">
                          <div
                            className="bg-green-500 h-2"
                            style={{ width: `${Math.min(Math.max(eng.progress_pct || 0, 0), 100)}%` }}
                          />
                        </div>
                        <div className="text-xs text-slate-500 mt-1">{eng.progress_pct || 0}%</div>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Статистика по инженерам */}
      {showStatistics && (
        <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
          <h2 className="text-xl font-bold text-white mb-4">Статистика по инженерам</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {statistics.map((stat) => (
              <div key={stat.engineer_id} className="bg-slate-900 rounded-lg p-4 border border-slate-700">
                <h3 className="text-lg font-semibold text-white mb-2">{stat.engineer_name}</h3>
                <div className="space-y-1 text-sm">
                  <div className="flex justify-between">
                    <span className="text-slate-400">Всего заданий:</span>
                    <span className="text-white font-bold">{stat.total}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-yellow-400">Ожидает:</span>
                    <span className="text-yellow-400 font-bold">{stat.pending}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-blue-400">В работе:</span>
                    <span className="text-blue-400 font-bold">{stat.in_progress}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-green-400">Завершено:</span>
                    <span className="text-green-400 font-bold">{stat.completed}</span>
                  </div>
                  {stat.cancelled > 0 && (
                    <div className="flex justify-between">
                      <span className="text-red-400">Отменено:</span>
                      <span className="text-red-400 font-bold">{stat.cancelled}</span>
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Расширенные фильтры и настройки */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-4">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setShowFilters(!showFilters)}
              className="flex items-center gap-2 px-3 py-1 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition"
            >
              <Filter size={16} />
              {showFilters ? 'Скрыть фильтры' : 'Показать фильтры'}
            </button>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setViewMode('list')}
                className={`p-2 rounded-lg transition ${viewMode === 'list' ? 'bg-accent text-white' : 'bg-slate-700 text-slate-300 hover:bg-slate-600'}`}
                title="Список"
              >
                <List size={18} />
              </button>
              <button
                onClick={() => setViewMode('hierarchy')}
                className={`p-2 rounded-lg transition ${viewMode === 'hierarchy' ? 'bg-accent text-white' : 'bg-slate-700 text-slate-300 hover:bg-slate-600'}`}
                title="Иерархия"
              >
                <Layers size={18} />
              </button>
            </div>
            {viewMode === 'hierarchy' && (
              <select
                value={groupBy}
                onChange={(e) => setGroupBy(e.target.value as any)}
                className="px-3 py-1 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent"
              >
                <option value="enterprise">Группировать по предприятию</option>
                <option value="branch">Группировать по филиалу</option>
                <option value="workshop">Группировать по цеху</option>
                <option value="engineer">Группировать по инженеру</option>
                <option value="status">Группировать по статусу</option>
                <option value="priority">Группировать по приоритету</option>
                <option value="none">Без группировки</option>
              </select>
            )}
          </div>
          <div className="flex items-center gap-2">
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value)}
              className="px-3 py-1 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent"
            >
              <option value="created_at">По дате создания</option>
              <option value="due_date">По сроку выполнения</option>
              <option value="priority">По приоритету</option>
              <option value="status">По статусу</option>
              <option value="equipment_name">По названию оборудования</option>
            </select>
            <button
              onClick={() => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')}
              className="p-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition"
              title={sortOrder === 'asc' ? 'По убыванию' : 'По возрастанию'}
            >
              <ArrowUpDown size={16} />
            </button>
          </div>
        </div>

        {showFilters && (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-6 gap-3 pt-4 border-t border-slate-700">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={18} />
              <input
                type="text"
                placeholder="Поиск..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm placeholder-slate-400 focus:outline-none focus:border-accent"
              />
            </div>
            
            <select
              value={filterStatus}
              onChange={(e) => setFilterStatus(e.target.value)}
              className="px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent"
            >
              <option value="all">Все статусы</option>
              <option value="PENDING">Ожидает</option>
              <option value="IN_PROGRESS">В работе</option>
              <option value="COMPLETED">Завершено</option>
              <option value="CANCELLED">Отменено</option>
            </select>
            
            <select
              value={filterType}
              onChange={(e) => setFilterType(e.target.value)}
              className="px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent"
            >
              <option value="all">Все типы</option>
              <option value="DIAGNOSTICS">Диагностика</option>
              <option value="EXPERTISE">Экспертиза ПБ</option>
              <option value="INSPECTION">Обследование</option>
            </select>

            <select
              value={filterPriority}
              onChange={(e) => setFilterPriority(e.target.value)}
              className="px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent"
            >
              <option value="all">Все приоритеты</option>
              <option value="LOW">Низкий</option>
              <option value="NORMAL">Обычный</option>
              <option value="HIGH">Высокий</option>
              <option value="URGENT">Срочный</option>
            </select>

            <select
              value={filterEngineer}
              onChange={(e) => setFilterEngineer(e.target.value)}
              className="px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent"
            >
              <option value="all">Все инженеры</option>
              {engineersList.map(eng => (
                <option key={eng.id} value={eng.id}>{eng.full_name || eng.username}</option>
              ))}
            </select>

            <select
              value={filterEnterprise}
              onChange={(e) => setFilterEnterprise(e.target.value)}
              className="px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent"
            >
              <option value="all">Все предприятия</option>
              {enterprises.map(ent => (
                <option key={ent.id} value={ent.id}>{ent.name}</option>
              ))}
            </select>
          </div>
        )}

        <div className="flex items-center justify-between mt-4 pt-4 border-t border-slate-700 text-sm">
          <div className="text-slate-400">
            Найдено: <span className="text-white font-bold">{filteredAssignments.length}</span> заданий
            {selectedAssignments.size > 0 && (
              <span className="ml-3 text-accent">
                Выбрано: {selectedAssignments.size}
              </span>
            )}
          </div>
          {selectedAssignments.size > 0 && (
            <div className="flex items-center gap-2">
              <button
                onClick={() => setSelectedAssignments(new Set())}
                className="px-3 py-1 bg-slate-700 hover:bg-slate-600 text-white rounded-lg text-sm transition"
              >
                Снять выделение
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Список заданий */}
      <div className="space-y-4">
        {filteredAssignments.length === 0 ? (
          <div className="bg-slate-800 rounded-xl border border-slate-700 p-8 text-center">
            <ClipboardList className="mx-auto text-slate-600 mb-4" size={48} />
            <p className="text-slate-400">Задания не найдены</p>
          </div>
        ) : viewMode === 'hierarchy' ? (
          // Иерархический вид
          Object.entries(groupedAssignments).map(([groupKey, groupAssignments]) => (
            <div key={groupKey} className="bg-slate-800 rounded-xl border border-slate-700 overflow-hidden">
              <div
                className="flex items-center justify-between p-4 bg-slate-900/50 cursor-pointer hover:bg-slate-900 transition"
                onClick={() => setExpandedHierarchy(prev => ({ ...prev, [groupKey]: !prev[groupKey] }))}
              >
                <div className="flex items-center gap-3">
                  {expandedHierarchy[groupKey] ? <ChevronDown size={20} className="text-slate-400" /> : <ChevronRight size={20} className="text-slate-400" />}
                  <div className="flex items-center gap-2">
                    {groupBy === 'enterprise' && <Building2 size={18} className="text-blue-400" />}
                    {groupBy === 'branch' && <MapPin size={18} className="text-green-400" />}
                    {groupBy === 'workshop' && <Settings size={18} className="text-purple-400" />}
                    {groupBy === 'engineer' && <User size={18} className="text-yellow-400" />}
                    <span className="text-lg font-semibold text-white">{groupKey}</span>
                    <span className="px-2 py-1 bg-slate-700 rounded text-xs text-slate-300">
                      {groupAssignments.length}
                    </span>
                  </div>
                </div>
                <div className="flex items-center gap-4 text-sm text-slate-400">
                  <span>Ожидает: {groupAssignments.filter(a => a.status === 'PENDING').length}</span>
                  <span>В работе: {groupAssignments.filter(a => a.status === 'IN_PROGRESS').length}</span>
                  <span className="text-green-400">Завершено: {groupAssignments.filter(a => a.status === 'COMPLETED').length}</span>
                </div>
              </div>
              {expandedHierarchy[groupKey] && (
                <div className="p-4 space-y-3">
                  {groupAssignments.map((assignment) => (
                    <AssignmentCard
                      key={assignment.id}
                      assignment={assignment}
                      isSelected={selectedAssignments.has(assignment.id)}
                      onSelect={(id) => {
                        setSelectedAssignments(prev => {
                          const newSet = new Set(prev);
                          if (newSet.has(id)) {
                            newSet.delete(id);
                          } else {
                            newSet.add(id);
                          }
                          return newSet;
                        });
                      }}
                      getStatusIcon={getStatusIcon}
                      getStatusLabel={getStatusLabel}
                      getTypeLabel={getTypeLabel}
                      getPriorityColor={getPriorityColor}
                    />
                  ))}
                </div>
              )}
            </div>
          ))
        ) : (
          // Обычный список
          filteredAssignments.map((assignment) => (
            <AssignmentCard
              key={assignment.id}
              assignment={assignment}
              isSelected={selectedAssignments.has(assignment.id)}
              onSelect={(id) => {
                setSelectedAssignments(prev => {
                  const newSet = new Set(prev);
                  if (newSet.has(id)) {
                    newSet.delete(id);
                  } else {
                    newSet.add(id);
                  }
                  return newSet;
                });
              }}
              getStatusIcon={getStatusIcon}
              getStatusLabel={getStatusLabel}
              getTypeLabel={getTypeLabel}
              getPriorityColor={getPriorityColor}
            />
          ))
        )}
      </div>

      {/* Модальное окно создания задания */}
      {showCreateModal && (
        <CreateAssignmentModal
          onClose={() => setShowCreateModal(false)}
          onSuccess={() => {
            setShowCreateModal(false);
            loadAssignments();
            loadStatistics();
            loadObjectStatistics();
          }}
          equipmentList={equipmentList}
          engineersList={engineersList}
        />
      )}
    </div>
  );
};

// Компонент модального окна для создания задания
const CreateAssignmentModal: React.FC<{
  onClose: () => void;
  onSuccess: () => void;
  equipmentList: any[];
  engineersList: any[];
}> = ({ onClose, onSuccess, equipmentList, engineersList }) => {
  const [formData, setFormData] = useState({
    selectedEquipmentIds: [] as string[],
    assignment_type: 'DIAGNOSTICS',
    assigned_to: '',
    priority: 'NORMAL',
    due_date: '',
    description: ''
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [enterprises, setEnterprises] = useState<any[]>([]);
  const [branches, setBranches] = useState<Record<string, any[]>>({});
  const [workshops, setWorkshops] = useState<Record<string, any[]>>({});
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [equipmentByWorkshop, setEquipmentByWorkshop] = useState<Record<string, any[]>>({});
  const [loadingHierarchy, setLoadingHierarchy] = useState(true);
  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadHierarchy();
  }, []);

  const loadHierarchy = async () => {
    try {
      const token = localStorage.getItem('token');
      const [enterprisesRes, equipmentRes] = await Promise.all([
        fetch(`${API_BASE}/api/hierarchy/enterprises`, {
          headers: { 'Authorization': `Bearer ${token}` }
        }),
        fetch(`${API_BASE}/api/equipment?limit=10000`, {
          headers: { 'Authorization': `Bearer ${token}` }
        })
      ]);

      if (enterprisesRes.ok) {
        const entData = await enterprisesRes.json();
        setEnterprises(entData.items || []);
      }

      if (equipmentRes.ok) {
        const eqData = await equipmentRes.json();
        // Группируем оборудование по цехам
        const equipmentByWorkshopMap: Record<string, any[]> = {};
        (eqData.items || []).forEach((eq: any) => {
          if (eq.workshop_id) {
            if (!equipmentByWorkshopMap[eq.workshop_id]) {
              equipmentByWorkshopMap[eq.workshop_id] = [];
            }
            equipmentByWorkshopMap[eq.workshop_id].push(eq);
          }
        });
        setEquipmentByWorkshop(equipmentByWorkshopMap);
      }
    } catch (error) {
      console.error('Ошибка загрузки иерархии:', error);
    } finally {
      setLoadingHierarchy(false);
    }
  };

  const loadBranches = async (enterpriseId: string) => {
    if (branches[enterpriseId]) return;
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/hierarchy/branches?enterprise_id=${enterpriseId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (response.ok) {
        const data = await response.json();
        setBranches(prev => ({ ...prev, [enterpriseId]: data.items || [] }));
      }
    } catch (error) {
      console.error('Ошибка загрузки филиалов:', error);
    }
  };

  const loadWorkshops = async (branchId: string) => {
    if (workshops[branchId]) return;
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/hierarchy/workshops?branch_id=${branchId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (response.ok) {
        const data = await response.json();
        setWorkshops(prev => ({ ...prev, [branchId]: data.items || [] }));
      }
    } catch (error) {
      console.error('Ошибка загрузки цехов:', error);
    }
  };

  const getEquipmentForWorkshop = (workshopId: string) => {
    return equipmentByWorkshop[workshopId] || [];
  };

  const toggleExpand = (key: string) => {
    setExpanded(prev => ({ ...prev, [key]: !prev[key] }));
    if (key.startsWith('enterprise-')) {
      const enterpriseId = key.replace('enterprise-', '');
      loadBranches(enterpriseId);
    } else if (key.startsWith('branch-')) {
      const branchId = key.replace('branch-', '');
      loadWorkshops(branchId);
    }
  };

  const toggleEquipment = (equipmentId: string) => {
    setFormData(prev => ({
      ...prev,
      selectedEquipmentIds: prev.selectedEquipmentIds.includes(equipmentId)
        ? prev.selectedEquipmentIds.filter(id => id !== equipmentId)
        : [...prev.selectedEquipmentIds, equipmentId]
    }));
  };

  // Проверка, все ли оборудование выбрано в предприятии
  const isEnterpriseSelected = (enterpriseId: string): boolean => {
    // Если филиалы не загружены, возвращаем false
    if (!branches[enterpriseId] || branches[enterpriseId].length === 0) return false;
    
    const entBranches = branches[enterpriseId];
    const allEquipmentIds: string[] = [];
    
    entBranches.forEach((branch: any) => {
      // Если цехи не загружены, пропускаем
      if (!workshops[branch.id]) return;
      const branchWorkshops = workshops[branch.id];
      branchWorkshops.forEach((workshop: any) => {
        const workshopEquipment = getEquipmentForWorkshop(workshop.id);
        workshopEquipment.forEach((eq: any) => {
          allEquipmentIds.push(eq.id);
        });
      });
    });

    if (allEquipmentIds.length === 0) return false;
    return allEquipmentIds.every(id => formData.selectedEquipmentIds.includes(id));
  };

  // Проверка, все ли оборудование выбрано в филиале
  const isBranchSelected = (branchId: string): boolean => {
    // Если цехи не загружены, возвращаем false
    if (!workshops[branchId] || workshops[branchId].length === 0) return false;
    
    const branchWorkshops = workshops[branchId];
    const allEquipmentIds: string[] = [];
    
    branchWorkshops.forEach((workshop: any) => {
      const workshopEquipment = getEquipmentForWorkshop(workshop.id);
      workshopEquipment.forEach((eq: any) => {
        allEquipmentIds.push(eq.id);
      });
    });

    if (allEquipmentIds.length === 0) return false;
    return allEquipmentIds.every(id => formData.selectedEquipmentIds.includes(id));
  };

  // Проверка, все ли оборудование выбрано в цехе
  const isWorkshopSelected = (workshopId: string): boolean => {
    const workshopEquipment = getEquipmentForWorkshop(workshopId);
    const allEquipmentIds = workshopEquipment.map((eq: any) => eq.id);

    if (allEquipmentIds.length === 0) return false;
    return allEquipmentIds.every(id => formData.selectedEquipmentIds.includes(id));
  };

  const selectAllInEnterprise = async (enterpriseId: string, isChecked: boolean) => {
    const enterprise = enterprises.find(e => e.id === enterpriseId);
    if (!enterprise) return;

    // Загружаем филиалы, если они не загружены
    if (!branches[enterpriseId]) {
      await loadBranches(enterpriseId);
      // Ждем немного для обновления состояния
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    const allEquipmentIds: string[] = [];
    const entBranches = branches[enterpriseId] || [];
    
    // Загружаем цехи для всех филиалов
    for (const branch of entBranches) {
      if (!workshops[branch.id]) {
        await loadWorkshops(branch.id);
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      const branchWorkshops = workshops[branch.id] || [];
      branchWorkshops.forEach((workshop: any) => {
        const workshopEquipment = getEquipmentForWorkshop(workshop.id);
        workshopEquipment.forEach((eq: any) => {
          allEquipmentIds.push(eq.id);
        });
      });
    }

    setFormData(prev => {
      if (isChecked) {
        // Добавляем все
        return {
          ...prev,
          selectedEquipmentIds: [...new Set([...prev.selectedEquipmentIds, ...allEquipmentIds])]
        };
      } else {
        // Удаляем все
        return {
          ...prev,
          selectedEquipmentIds: prev.selectedEquipmentIds.filter(id => !allEquipmentIds.includes(id))
        };
      }
    });
  };

  const selectAllInBranch = async (branchId: string, isChecked: boolean) => {
    // Загружаем цехи, если они не загружены
    if (!workshops[branchId]) {
      await loadWorkshops(branchId);
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    const branchWorkshops = workshops[branchId] || [];
    const allEquipmentIds: string[] = [];
    
    branchWorkshops.forEach((workshop: any) => {
      const workshopEquipment = getEquipmentForWorkshop(workshop.id);
      workshopEquipment.forEach((eq: any) => {
        allEquipmentIds.push(eq.id);
      });
    });

    setFormData(prev => {
      if (isChecked) {
        // Добавляем все
        return {
          ...prev,
          selectedEquipmentIds: [...new Set([...prev.selectedEquipmentIds, ...allEquipmentIds])]
        };
      } else {
        // Удаляем все
        return {
          ...prev,
          selectedEquipmentIds: prev.selectedEquipmentIds.filter(id => !allEquipmentIds.includes(id))
        };
      }
    });
  };

  const selectAllInWorkshop = (workshopId: string, isChecked: boolean) => {
    const workshopEquipment = getEquipmentForWorkshop(workshopId);
    const allEquipmentIds = workshopEquipment.map((eq: any) => eq.id);

    setFormData(prev => {
      if (isChecked) {
        // Добавляем все
        return {
          ...prev,
          selectedEquipmentIds: [...new Set([...prev.selectedEquipmentIds, ...allEquipmentIds])]
        };
      } else {
        // Удаляем все
        return {
          ...prev,
          selectedEquipmentIds: prev.selectedEquipmentIds.filter(id => !allEquipmentIds.includes(id))
        };
      }
    });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (formData.selectedEquipmentIds.length === 0) {
      setError('Необходимо выбрать хотя бы одно оборудование');
      return;
    }

    setSaving(true);
    setError(null);

    try {
      const token = localStorage.getItem('token');
      
      // Создаем задания для каждого выбранного оборудования
      const promises = formData.selectedEquipmentIds.map(equipmentId => {
        const payload = {
          equipment_id: equipmentId,
          assignment_type: formData.assignment_type,
          assigned_to: formData.assigned_to,
          priority: formData.priority,
          due_date: formData.due_date ? `${formData.due_date}T23:59:59` : null,
          description: formData.description || null
        };

        return fetch(`${API_BASE}/api/assignments`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify(payload)
        });
      });

      const results = await Promise.all(promises);
      const failed = results.filter(r => !r.ok);
      
      if (failed.length > 0) {
        const errorData = await failed[0].json();
        setError(`Ошибка при создании заданий: ${errorData.detail || 'Неизвестная ошибка'}`);
      } else {
        onSuccess();
      }
    } catch (err) {
      setError('Ошибка при создании заданий');
      console.error('Ошибка:', err);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-slate-800 rounded-lg max-w-2xl w-full max-h-[90vh] overflow-auto">
        <div className="p-6 border-b border-slate-700">
          <h2 className="text-xl font-semibold text-white">Создать задание</h2>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {error && (
            <div className="bg-red-500/20 border border-red-500 rounded-lg p-3 text-red-400 text-sm">
              {error}
            </div>
          )}

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">
              Оборудование * ({formData.selectedEquipmentIds.length} выбрано)
            </label>
            {loadingHierarchy ? (
              <div className="text-slate-400 text-sm">Загрузка иерархии...</div>
            ) : (
              <div className="bg-slate-900 border border-slate-700 rounded-lg p-4 max-h-96 overflow-y-auto">
                {enterprises.length === 0 ? (
                  <div className="text-slate-400 text-sm">Нет доступных предприятий</div>
                ) : (
                  enterprises.map((enterprise) => (
                    <div key={enterprise.id} className="mb-2">
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => toggleExpand(`enterprise-${enterprise.id}`)}
                          className="text-slate-400 hover:text-white"
                        >
                          {expanded[`enterprise-${enterprise.id}`] ? '▼' : '▶'}
                        </button>
                        <input
                          type="checkbox"
                          checked={isEnterpriseSelected(enterprise.id)}
                          onChange={(e) => {
                            e.stopPropagation();
                            selectAllInEnterprise(enterprise.id, e.target.checked);
                          }}
                          onClick={(e) => e.stopPropagation()}
                          className="rounded"
                        />
                        <span className="text-white font-semibold">{enterprise.name}</span>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            selectAllInEnterprise(enterprise.id, !isEnterpriseSelected(enterprise.id));
                          }}
                          className="ml-auto text-xs text-accent hover:underline"
                        >
                          {isEnterpriseSelected(enterprise.id) ? 'Снять все' : 'Выбрать все'}
                        </button>
                      </div>
                      {expanded[`enterprise-${enterprise.id}`] && (branches[enterprise.id] || []).map((branch: any) => (
                        <div key={branch.id} className="ml-6 mt-2">
                          <div className="flex items-center gap-2">
                            <button
                              type="button"
                              onClick={() => toggleExpand(`branch-${branch.id}`)}
                              className="text-slate-400 hover:text-white"
                            >
                              {expanded[`branch-${branch.id}`] ? '▼' : '▶'}
                            </button>
                            <input
                              type="checkbox"
                              checked={isBranchSelected(branch.id)}
                              onChange={(e) => {
                                e.stopPropagation();
                                selectAllInBranch(branch.id, e.target.checked);
                              }}
                              onClick={(e) => e.stopPropagation()}
                              className="rounded"
                            />
                            <span className="text-slate-300">{branch.name}</span>
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                selectAllInBranch(branch.id, !isBranchSelected(branch.id));
                              }}
                              className="ml-auto text-xs text-accent hover:underline"
                            >
                              {isBranchSelected(branch.id) ? 'Снять все' : 'Выбрать все'}
                            </button>
                          </div>
                          {expanded[`branch-${branch.id}`] && (workshops[branch.id] || []).map((workshop: any) => (
                            <div key={workshop.id} className="ml-6 mt-2">
                              <div className="flex items-center gap-2">
                                <button
                                  type="button"
                                  onClick={() => toggleExpand(`workshop-${workshop.id}`)}
                                  className="text-slate-400 hover:text-white"
                                >
                                  {expanded[`workshop-${workshop.id}`] ? '▼' : '▶'}
                                </button>
                                <input
                                  type="checkbox"
                                  checked={isWorkshopSelected(workshop.id)}
                                  onChange={(e) => {
                                    e.stopPropagation();
                                    selectAllInWorkshop(workshop.id, e.target.checked);
                                  }}
                                  onClick={(e) => e.stopPropagation()}
                                  className="rounded"
                                />
                                <span className="text-slate-400">{workshop.name}</span>
                                <button
                                  type="button"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    selectAllInWorkshop(workshop.id, !isWorkshopSelected(workshop.id));
                                  }}
                                  className="ml-auto text-xs text-accent hover:underline"
                                >
                                  {isWorkshopSelected(workshop.id) ? 'Снять все' : 'Выбрать все'}
                                </button>
                              </div>
                              {expanded[`workshop-${workshop.id}`] && getEquipmentForWorkshop(workshop.id).map((eq: any) => (
                                <div key={eq.id} className="ml-6 mt-1">
                                  <label className="flex items-center gap-2 cursor-pointer">
                                    <input
                                      type="checkbox"
                                      checked={formData.selectedEquipmentIds.includes(eq.id)}
                                      onChange={() => toggleEquipment(eq.id)}
                                      className="rounded"
                                    />
                                    <span className="text-slate-400 text-sm">
                                      {eq.equipment_code} - {eq.name}
                                    </span>
                                  </label>
                                </div>
                              ))}
                            </div>
                          ))}
                        </div>
                      ))}
                    </div>
                  ))
                )}
              </div>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Тип задания *
            </label>
            <select
              required
              value={formData.assignment_type}
              onChange={(e) => setFormData({ ...formData, assignment_type: e.target.value })}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="DIAGNOSTICS">Диагностика</option>
              <option value="EXPERTISE">Экспертиза ПБ</option>
              <option value="INSPECTION">Обследование</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Назначить инженеру *
            </label>
            <select
              required
              value={formData.assigned_to}
              onChange={(e) => setFormData({ ...formData, assigned_to: e.target.value })}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="">Выберите инженера</option>
              {engineersList.map((eng) => (
                <option key={eng.id} value={eng.id}>
                  {eng.full_name || eng.username}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Приоритет *
            </label>
            <select
              required
              value={formData.priority}
              onChange={(e) => setFormData({ ...formData, priority: e.target.value })}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="LOW">Низкий</option>
              <option value="NORMAL">Обычный</option>
              <option value="HIGH">Высокий</option>
              <option value="URGENT">Срочный</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Срок выполнения
            </label>
            <input
              type="date"
              value={formData.due_date}
              onChange={(e) => setFormData({ ...formData, due_date: e.target.value })}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Описание
            </label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              rows={4}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              placeholder="Дополнительная информация о задании..."
            />
          </div>

          <div className="flex justify-end gap-3 pt-4 border-t border-slate-700">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-slate-400 hover:text-white transition"
              disabled={saving}
            >
              Отмена
            </button>
            <button
              type="submit"
              disabled={saving}
              className="px-4 py-2 bg-accent text-white rounded-lg hover:bg-accent/90 transition disabled:opacity-50"
            >
              {saving ? `Создание ${formData.selectedEquipmentIds.length} заданий...` : `Создать ${formData.selectedEquipmentIds.length} заданий`}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

// Компонент карточки задания
const AssignmentCard: React.FC<{
  assignment: Assignment;
  isSelected: boolean;
  onSelect: (id: string) => void;
  getStatusIcon: (status: string) => React.ReactNode;
  getStatusLabel: (status: string) => string;
  getTypeLabel: (type: string) => string;
  getPriorityColor: (priority: string) => string;
}> = ({ assignment, isSelected, onSelect, getStatusIcon, getStatusLabel, getTypeLabel, getPriorityColor }) => {
  const isOverdue = assignment.due_date && new Date(assignment.due_date) < new Date() && assignment.status !== 'COMPLETED';
  
  return (
    <div
      className={`bg-slate-800 rounded-xl border-2 p-4 hover:border-accent/50 transition-colors cursor-pointer ${
        isSelected ? 'border-accent' : 'border-slate-700'
      } ${isOverdue ? 'border-red-500/50' : ''}`}
      onClick={() => onSelect(assignment.id)}
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex-1">
          <div className="flex items-center gap-3 mb-2">
            <input
              type="checkbox"
              checked={isSelected}
              onChange={() => onSelect(assignment.id)}
              onClick={(e) => e.stopPropagation()}
              className="rounded"
            />
            <span className="px-2 py-1 bg-slate-700 rounded text-xs font-mono text-accent">
              {assignment.equipment_code}
            </span>
            <h3 className="text-lg font-bold text-white flex-1">{assignment.equipment_name}</h3>
            <span className={`px-2 py-1 rounded text-xs font-semibold ${getPriorityColor(assignment.priority)} text-white`}>
              {assignment.priority}
            </span>
          </div>
          <div className="flex flex-wrap items-center gap-3 text-xs text-slate-400 ml-7">
            {assignment.enterprise_name && (
              <span className="flex items-center gap-1">
                <Building2 size={14} />
                {assignment.enterprise_name}
              </span>
            )}
            {assignment.branch_name && (
              <span className="flex items-center gap-1">
                <MapPin size={14} />
                {assignment.branch_name}
              </span>
            )}
            {assignment.workshop_name && (
              <span className="flex items-center gap-1">
                <Settings size={14} />
                {assignment.workshop_name}
              </span>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-4 text-sm text-slate-400 ml-7 mt-2">
            <span className="flex items-center gap-1">
              <ClipboardList size={14} />
              {getTypeLabel(assignment.assignment_type)}
            </span>
            <span className="flex items-center gap-1">
              <User size={14} />
              {assignment.assigned_to_name || 'N/A'}
            </span>
            {assignment.due_date && (
              <span className={`flex items-center gap-1 ${isOverdue ? 'text-red-400 font-semibold' : ''}`}>
                <Calendar size={14} />
                {new Date(assignment.due_date).toLocaleDateString('ru-RU')}
                {isOverdue && ' (Просрочено!)'}
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          {getStatusIcon(assignment.status)}
          <span className="text-sm font-semibold text-slate-300">
            {getStatusLabel(assignment.status)}
          </span>
        </div>
      </div>
      
      {assignment.description && (
        <p className="text-slate-300 text-sm mb-3 ml-7">{assignment.description}</p>
      )}
      
      <div className="flex items-center justify-between text-xs text-slate-500 ml-7">
        <span>Создано: {new Date(assignment.created_at).toLocaleDateString('ru-RU')}</span>
        {assignment.completed_at && (
          <span className="text-green-400">Завершено: {new Date(assignment.completed_at).toLocaleDateString('ru-RU')}</span>
        )}
      </div>
    </div>
  );
};

export default AssignmentsManagement;

