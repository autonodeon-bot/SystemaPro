import { useState, useEffect, useMemo } from 'react';
import { ClipboardList, Plus, Filter, CheckCircle, Clock, XCircle, AlertCircle, Search, ChevronDown, ChevronRight, List, Layers, ArrowUpDown, User, Building2, MapPin, Settings } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { API_BASE, getAssignmentTypeLabel, ASSIGNMENT_TYPE_SELECT_OPTIONS } from '../constants';
import { useToast } from '../contexts/ToastContext';
import { useAuth } from '../contexts/AuthContext';
import CreateAssignmentModal from '../components/CreateAssignmentModal';
import EditAssignmentModal from '../components/EditAssignmentModal';
import AssignmentCard from '../components/AssignmentCard';
import type { Assignment, AssignmentServerSummary } from '../components/AssignmentCard';

function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);
  useEffect(() => {
    const handler = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(handler);
  }, [value, delay]);
  return debouncedValue;
}

const AssignmentsManagement = () => {
  const navigate = useNavigate();
  const toast = useToast();
  const { user } = useAuth();
  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterType, setFilterType] = useState<string>('all');
  const [filterPriority, setFilterPriority] = useState<string>('all');
  const [filterEngineer, setFilterEngineer] = useState<string>('all');
  const [filterEnterprise, setFilterEnterprise] = useState<string>('all');
  const [showArchived, setShowArchived] = useState<boolean>(false);
  const [sortBy, setSortBy] = useState<string>('created_at');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');
  const [viewMode, setViewMode] = useState<'list' | 'hierarchy'>('hierarchy');
  const [expandedHierarchy, setExpandedHierarchy] = useState<Record<string, boolean>>({});
  const [searchQuery, setSearchQuery] = useState('');
  const debouncedSearch = useDebounce(searchQuery, 300);
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
  const [generatingReport, setGeneratingReport] = useState<string | null>(null);
  const [serverSummary, setServerSummary] = useState<Record<string, AssignmentServerSummary>>({});
  const [editingAssignment, setEditingAssignment] = useState<Assignment | null>(null);

  useEffect(() => {
    loadEquipment();
    loadEngineers();
    loadStatistics();
    loadObjectStatistics();
  }, []);

  const loadStatistics = async () => {
    try {
      const token = localStorage.getItem('token');
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
      const response = await fetch(`${API_BASE}/api/assignments?include_cancelled=${showArchived}`, {
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
        // Подтягиваем сводку: есть ли данные/отчет на сервере
        loadServerSummary(data);
      }
    } catch (error) {
      console.error('Ошибка загрузки заданий:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadAssignments();
  }, [showArchived]);

  const handleArchiveAssignment = async (assignmentId: string) => {
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/assignments/${assignmentId}/archive`, {
        method: 'PATCH',
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (res.ok) {
        setAssignments(prev => prev.map(a => a.id === assignmentId ? { ...a, status: 'CANCELLED' } : a));
        toast.success('Задание перемещено в архив');
      } else {
        const err = await res.json();
        toast.error(err.detail || 'Ошибка архивации');
      }
    } catch (e) {
      console.error(e);
      toast.error('Ошибка архивации задания');
    }
  };

  const handleDeleteAssignment = async (assignmentId: string) => {
    if (!window.confirm('Удалить задание безвозвратно? Связи с обследованиями будут сняты.')) return;
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/assignments/${assignmentId}`, {
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (res.ok) {
        setAssignments(prev => prev.filter(a => a.id !== assignmentId));
        toast.success('Задание удалено');
      } else {
        const err = await res.json();
        toast.error(err.detail || 'Ошибка удаления');
      }
    } catch (e) {
      console.error(e);
      toast.error('Ошибка удаления задания');
    }
  };

  const loadServerSummary = async (items: Assignment[]) => {
    try {
      if (!items || items.length === 0) return;
      const token = localStorage.getItem('token');
      const ids = items.map((a) => a.id);
      const response = await fetch(`${API_BASE}/api/assignments/status-summary`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ assignment_ids: ids }),
      });
      if (response.ok) {
        const data = await response.json();
        setServerSummary(data || {});
      }
    } catch (e) {
      console.error('Ошибка загрузки сводки по заданиям:', e);
    }
  };

  const loadEquipment = async () => {
    try {
      const token = localStorage.getItem('token');
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

  const handleViewChecklist = async (assignmentId: string) => {
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/assignments/${assignmentId}/inspection`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      if (response.ok) {
        const inspectionData = await response.json();
        if (inspectionData.inspection_id) {
          navigate(`/equipment/${inspectionData.equipment_id}?inspection=${inspectionData.inspection_id}`);
        } else if (inspectionData.inspection_history_id) {
          toast.info(`Чек-лист найден в истории обследований. Дата: ${inspectionData.date_performed || 'N/A'}`);
          navigate(`/equipment/${inspectionData.equipment_id}`);
        } else {
          toast.warning('Чек-лист не найден для этого задания');
        }
      } else {
        const error = await response.json();
        toast.error(error.detail || 'Не удалось загрузить чек-лист');
      }
    } catch (error) {
      console.error('Ошибка просмотра чек-листа:', error);
      toast.error('Ошибка при загрузке чек-листа');
    }
  };

  const handleGenerateReport = async (assignmentId: string) => {
    try {
      setGeneratingReport(assignmentId);
      const token = localStorage.getItem('token');
      // Подбираем шаблон (MVP): по типу оборудования, иначе дефолт
      let resolvedReportType = 'DIAGNOSTICS';
      let resolvedFormat = 'docx';
      try {
        const a = assignments.find((x) => x.id === assignmentId);
        const eq = equipmentList.find((e: any) => e.id === a?.equipment_id);
        const typeId = eq?.type_id as string | undefined;
        const tplRes = await fetch(
          `${API_BASE}/api/report-templates/resolve?equipment_type_id=${encodeURIComponent(typeId || '')}&fallback_report_type=DIAGNOSTICS&fallback_format=docx`,
          { headers: { 'Authorization': `Bearer ${token}` } }
        );
        if (tplRes.ok) {
          const tpl = await tplRes.json();
          resolvedReportType = tpl.report_type || resolvedReportType;
          resolvedFormat = tpl.format || resolvedFormat;
        }
      } catch (_) {}
      
      // Сначала получаем inspection_id по assignment_id
      const inspectionResponse = await fetch(`${API_BASE}/api/assignments/${assignmentId}/inspection`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      if (!inspectionResponse.ok) {
        throw new Error('Не удалось получить чек-лист для задания');
      }
      
      const inspectionData = await inspectionResponse.json();
      const inspectionId = inspectionData.inspection_id;
      
      if (!inspectionId) {
        toast.warning('Чек-лист не найден для этого задания. Невозможно сгенерировать отчет.');
        return;
      }
      
      // Генерируем отчет
      const reportResponse = await fetch(`${API_BASE}/api/reports/generate`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          inspection_id: inspectionId,
          report_type: resolvedReportType,
          format: resolvedFormat
        })
      });
      
      if (reportResponse.ok) {
        const reportData = await reportResponse.json();
        toast.success('Отчет успешно сгенерирован!');
        if (reportData.id) {
          await downloadReport(reportData.id as string, resolvedFormat);
        }
        loadServerSummary(assignments);
      } else {
        const error = await reportResponse.json();
        toast.error(`Ошибка генерации отчета: ${error.detail || 'Неизвестная ошибка'}`);
      }
    } catch (error) {
      console.error('Ошибка генерации отчета:', error);
      toast.error('Ошибка при генерации отчета');
    } finally {
      setGeneratingReport(null);
    }
  };

  const downloadReport = async (reportId: string, format: string = 'docx') => {
    const token = localStorage.getItem('token');
    const url = `${API_BASE}/api/reports/${reportId}/download?format=${encodeURIComponent(format)}`;
    const res = await fetch(url, {
      headers: {
        'Authorization': `Bearer ${token}`,
      }
    });
    if (!res.ok) {
      const t = await res.text();
      throw new Error(t || `Ошибка скачивания: ${res.status}`);
    }
    const blob = await res.blob();
    const blobUrl = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = blobUrl;
    // пробуем взять имя из заголовка
    const cd = res.headers.get('Content-Disposition') || res.headers.get('content-disposition');
    const filename = cd?.match(/filename="?([^"]+)"?/i)?.[1] || `report_${reportId}.${format}`;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(blobUrl);
  };

  const handleDownloadReport = async (assignmentId: string) => {
    try {
      const s = serverSummary[assignmentId];
      if (!s?.report_id) {
        toast.warning('Отчет еще не сформирован');
        return;
      }
      await downloadReport(s.report_id, 'docx');
    } catch (e) {
      console.error('Ошибка скачивания отчета:', e);
      toast.error('Ошибка скачивания отчета');
    }
  };

  const loadObjectStatistics = async () => {
    try {
      const token = localStorage.getItem('token');
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

  const getTypeLabel = (type: string) => getAssignmentTypeLabel(type);

  const getPriorityColor = (priority: string) => {
    const colors: { [key: string]: string } = {
      'LOW': 'bg-app-text3',
      'NORMAL': 'bg-blue-500',
      'HIGH': 'bg-orange-500',
      'URGENT': 'bg-red-500'
    };
    return colors[priority] || 'bg-app-text3';
  };

  const filteredAssignments = useMemo(() => {
    return assignments.filter(assignment => {
      const matchesStatus = filterStatus === 'all' || assignment.status === filterStatus;
      const matchesType = filterType === 'all' || assignment.assignment_type === filterType;
      const matchesPriority = filterPriority === 'all' || assignment.priority === filterPriority;
      const matchesEngineer = filterEngineer === 'all' || assignment.assigned_to === filterEngineer;
      const matchesEnterprise = filterEnterprise === 'all' || assignment.enterprise_id === filterEnterprise;
      const matchesSearch = debouncedSearch === '' || 
        assignment.equipment_code.toLowerCase().includes(debouncedSearch.toLowerCase()) ||
        assignment.equipment_name.toLowerCase().includes(debouncedSearch.toLowerCase()) ||
        (assignment.assigned_to_name && assignment.assigned_to_name.toLowerCase().includes(debouncedSearch.toLowerCase())) ||
        (assignment.enterprise_name && assignment.enterprise_name.toLowerCase().includes(debouncedSearch.toLowerCase())) ||
        (assignment.branch_name && assignment.branch_name.toLowerCase().includes(debouncedSearch.toLowerCase())) ||
        (assignment.workshop_name && assignment.workshop_name.toLowerCase().includes(debouncedSearch.toLowerCase()));
      
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
  }, [assignments, filterStatus, filterType, filterPriority, filterEngineer, filterEnterprise, debouncedSearch, sortBy, sortOrder]);

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
        <div className="flex flex-col items-center gap-3" style={{ color: 'var(--text-muted)' }}>
          <div className="w-8 h-8 rounded-full border-2 border-transparent border-t-[var(--accent)] border-r-[var(--accent)] animate-spin" />
          <span className="text-sm">Загрузка заданий...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <ClipboardList className="text-[var(--accent)]" size={28} />
          <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)', letterSpacing: '-0.02em' }}>
            Управление заданиями
          </h1>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowObjectStats(!showObjectStats)}
            className={`ind-btn ${showObjectStats ? 'ind-btn--primary' : ''}`}
          >
            Назначения по объектам
          </button>
          <button
            onClick={() => setShowStatistics(!showStatistics)}
            className={`ind-btn ${showStatistics ? 'ind-btn--primary' : ''}`}
          >
            Статистика по инженерам
          </button>
          <button
            onClick={() => setShowCreateModal(true)}
            className="ind-btn ind-btn--primary"
          >
            <Plus size={16} />
            <span>Создать задание</span>
          </button>
        </div>
      </div>

      {/* Назначения инженеров по объектам + прогресс */}
      {showObjectStats && (
        <div className="sp-surface p-5 sp-animate-in">
          <h2 className="sp-section-title">Назначения по объектам и прогресс</h2>
          {objectStats.length === 0 ? (
            <div style={{ color: 'var(--text-muted)' }}>Нет данных по назначениям</div>
          ) : (
            <div className="space-y-3">
              {objectStats.map((obj: any) => (
                <div key={`${obj.object_type}-${obj.object_id}`} className="sp-surface-flat p-4">
                  <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-2">
                    <div>
                      <div className="font-semibold" style={{ color: 'var(--text-primary)' }}>{obj.object_name}</div>
                      <div className="text-xs" style={{ color: 'var(--text-muted)' }}>{getObjectTypeLabel(obj.object_type)}</div>
                    </div>
                  </div>

                  <div className="mt-3 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                    {(obj.engineers || []).map((eng: any) => (
                      <div key={eng.user_id} className="sp-surface-flat p-3">
                        <div className="font-semibold truncate" style={{ color: 'var(--text-primary)' }}>{eng.full_name || eng.username}</div>
                        <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>
                          Выполнено: <span className="font-bold tabular-nums" style={{ color: 'var(--success)' }}>{eng.completed}</span> /{' '}
                          <span className="font-bold tabular-nums" style={{ color: 'var(--text-primary)' }}>{eng.total}</span>
                          {' '}· Осталось: <span className="font-bold tabular-nums" style={{ color: 'var(--warning)' }}>{eng.remaining}</span>
                        </div>
                        <div className="sp-progress mt-2">
                          <div
                            className="sp-progress__bar"
                            style={{
                              width: `${Math.min(Math.max(eng.progress_pct || 0, 0), 100)}%`,
                              background: 'var(--success)',
                            }}
                          />
                        </div>
                        <div className="text-xs mt-1 ind-mono" style={{ color: 'var(--text-muted)' }}>{eng.progress_pct || 0}%</div>
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
        <div className="sp-surface p-5 sp-animate-in">
          <h2 className="sp-section-title">Статистика по инженерам</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {statistics.map((stat) => (
              <div key={stat.engineer_id} className="sp-surface-flat p-4">
                <h3 className="text-base font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>{stat.engineer_name}</h3>
                <div className="space-y-1 text-sm">
                  <div className="flex justify-between">
                    <span style={{ color: 'var(--text-muted)' }}>Всего заданий:</span>
                    <span className="font-bold tabular-nums" style={{ color: 'var(--text-primary)' }}>{stat.total}</span>
                  </div>
                  <div className="flex justify-between">
                    <span style={{ color: 'var(--warning)' }}>Ожидает:</span>
                    <span className="font-bold tabular-nums" style={{ color: 'var(--warning)' }}>{stat.pending}</span>
                  </div>
                  <div className="flex justify-between">
                    <span style={{ color: 'var(--accent)' }}>В работе:</span>
                    <span className="font-bold tabular-nums" style={{ color: 'var(--accent)' }}>{stat.in_progress}</span>
                  </div>
                  <div className="flex justify-between">
                    <span style={{ color: 'var(--success)' }}>Завершено:</span>
                    <span className="font-bold tabular-nums" style={{ color: 'var(--success)' }}>{stat.completed}</span>
                  </div>
                  {stat.cancelled > 0 && (
                    <div className="flex justify-between">
                      <span style={{ color: 'var(--danger)' }}>Отменено:</span>
                      <span className="font-bold tabular-nums" style={{ color: 'var(--danger)' }}>{stat.cancelled}</span>
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Расширенные фильтры и настройки */}
      <div className="sp-surface p-4">
        <div className="flex items-center justify-between mb-4 flex-wrap gap-2">
          <div className="flex items-center gap-2 flex-wrap">
            <button
              onClick={() => setShowFilters(!showFilters)}
              className="ind-btn"
            >
              <Filter size={14} />
              {showFilters ? 'Скрыть фильтры' : 'Показать фильтры'}
            </button>
            <div className="sp-pill-nav">
              <button
                onClick={() => setViewMode('list')}
                className={viewMode === 'list' ? 'active' : ''}
                title="Список"
              >
                <List size={14} /> Список
              </button>
              <button
                onClick={() => setViewMode('hierarchy')}
                className={viewMode === 'hierarchy' ? 'active' : ''}
                title="Иерархия"
              >
                <Layers size={14} /> Иерархия
              </button>
            </div>
            {viewMode === 'hierarchy' && (
              <select
                value={groupBy}
                onChange={(e) => setGroupBy(e.target.value as any)}
                className="ind-input"
                style={{ width: 'auto' }}
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
              className="ind-input"
              style={{ width: 'auto' }}
            >
              <option value="created_at">По дате создания</option>
              <option value="due_date">По сроку выполнения</option>
              <option value="priority">По приоритету</option>
              <option value="status">По статусу</option>
              <option value="equipment_name">По названию оборудования</option>
            </select>
            <button
              onClick={() => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')}
              className="ind-btn"
              title={sortOrder === 'asc' ? 'По убыванию' : 'По возрастанию'}
            >
              <ArrowUpDown size={14} />
            </button>
          </div>
        </div>

        {showFilters && (
          <div
            className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-6 gap-3 pt-4 sp-animate-in"
            style={{ borderTop: '1px solid var(--border-subtle)' }}
          >
            <div className="relative">
              <Search
                className="absolute left-3 top-1/2 transform -translate-y-1/2"
                size={16}
                style={{ color: 'var(--text-muted)' }}
              />
              <input
                type="text"
                placeholder="Поиск..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="ind-input"
                style={{ paddingLeft: '34px' }}
              />
            </div>

            <select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} className="ind-input">
              <option value="all">Все статусы</option>
              <option value="PENDING">Ожидает</option>
              <option value="IN_PROGRESS">В работе</option>
              <option value="COMPLETED">Завершено</option>
              <option value="CANCELLED">Отменено</option>
            </select>

            <select value={filterType} onChange={(e) => setFilterType(e.target.value)} className="ind-input">
              <option value="all">Все типы</option>
              {ASSIGNMENT_TYPE_SELECT_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>

            <select value={filterPriority} onChange={(e) => setFilterPriority(e.target.value)} className="ind-input">
              <option value="all">Все приоритеты</option>
              <option value="LOW">Низкий</option>
              <option value="NORMAL">Обычный</option>
              <option value="HIGH">Высокий</option>
              <option value="URGENT">Срочный</option>
            </select>

            <select value={filterEngineer} onChange={(e) => setFilterEngineer(e.target.value)} className="ind-input">
              <option value="all">Все инженеры</option>
              {engineersList.map((eng) => (
                <option key={eng.id} value={eng.id}>{eng.full_name || eng.username}</option>
              ))}
            </select>

            <select value={filterEnterprise} onChange={(e) => setFilterEnterprise(e.target.value)} className="ind-input">
              <option value="all">Все предприятия</option>
              {enterprises.map((ent) => (
                <option key={ent.id} value={ent.id}>{ent.name}</option>
              ))}
            </select>

            <label className="flex items-center gap-2 cursor-pointer" style={{ color: 'var(--text-secondary)' }}>
              <input
                type="checkbox"
                checked={showArchived}
                onChange={(e) => setShowArchived(e.target.checked)}
                className="accent-[var(--accent)]"
              />
              <span className="text-sm">Показать архивные</span>
            </label>
          </div>
        )}

        <div
          className="flex items-center justify-between mt-4 pt-4 text-sm"
          style={{ borderTop: '1px solid var(--border-subtle)' }}
        >
          <div style={{ color: 'var(--text-muted)' }}>
            Найдено:{' '}
            <span className="font-bold tabular-nums" style={{ color: 'var(--text-primary)' }}>
              {filteredAssignments.length}
            </span>{' '}
            заданий
            {selectedAssignments.size > 0 && (
              <span className="ml-3" style={{ color: 'var(--accent)' }}>
                Выбрано: {selectedAssignments.size}
              </span>
            )}
          </div>
          {selectedAssignments.size > 0 && (
            <div className="flex items-center gap-2">
              <button onClick={() => setSelectedAssignments(new Set())} className="ind-btn ind-btn--sm">
                Снять выделение
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Список заданий */}
      <div className="space-y-4">
        {filteredAssignments.length === 0 ? (
          <div className="sp-surface p-8 text-center">
            <ClipboardList className="mx-auto mb-4" size={48} style={{ color: 'var(--text-muted)', opacity: 0.4 }} />
            <p style={{ color: 'var(--text-muted)' }}>Задания не найдены</p>
          </div>
        ) : viewMode === 'hierarchy' ? (
          // Иерархический вид
          Object.entries(groupedAssignments).map(([groupKey, groupAssignments]) => (
            <div key={groupKey} className="bg-app-panel rounded-xl border border-app-line overflow-hidden">
              <div
                className="flex items-center justify-between p-4 bg-app-deep/50 cursor-pointer hover:bg-app-deep transition"
                onClick={() => setExpandedHierarchy(prev => ({ ...prev, [groupKey]: !prev[groupKey] }))}
              >
                <div className="flex items-center gap-3">
                  {expandedHierarchy[groupKey] ? <ChevronDown size={20} className="text-app-text3" /> : <ChevronRight size={20} className="text-app-text3" />}
                  <div className="flex items-center gap-2">
                    {groupBy === 'enterprise' && <Building2 size={18} className="text-blue-400" />}
                    {groupBy === 'branch' && <MapPin size={18} className="text-green-400" />}
                    {groupBy === 'workshop' && <Settings size={18} className="text-purple-400" />}
                    {groupBy === 'engineer' && <User size={18} className="text-yellow-400" />}
                    <span className="text-lg font-semibold text-white">{groupKey}</span>
                    <span className="px-2 py-1 bg-app-soft rounded text-xs text-app-text2">
                      {groupAssignments.length}
                    </span>
                  </div>
                </div>
                <div className="flex items-center gap-4 text-sm text-app-text3">
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
                      onViewChecklist={handleViewChecklist}
                      onGenerateReport={handleGenerateReport}
                      onDownloadReport={handleDownloadReport}
                      onArchive={handleArchiveAssignment}
                      onDelete={handleDeleteAssignment}
                      onEdit={setEditingAssignment}
                      generatingReport={generatingReport}
                      serverSummary={serverSummary[assignment.id]}
                      userRole={user?.role}
                    />
                  ))}
                </div>
              )}
            </div>
          ))
        ) : (
          <div className="overflow-x-auto rounded-xl border border-app-line">
            <table className="w-full text-sm text-left">
              <thead className="bg-app-deep text-app-text3 uppercase text-xs">
                <tr>
                  <th className="px-3 py-2">Оборудование</th>
                  <th className="px-3 py-2 hidden md:table-cell">Инженер</th>
                  <th className="px-3 py-2">Статус</th>
                  <th className="px-3 py-2 hidden lg:table-cell">Срок</th>
                  <th className="px-3 py-2">Действия</th>
                </tr>
              </thead>
              <tbody>
                {filteredAssignments.map((assignment) => (
                  <tr key={assignment.id} className="border-t border-app-line hover:bg-app-surface-alt/50">
                    <td className="px-3 py-2">
                      <div className="font-medium text-app-text">{assignment.equipment_name}</div>
                      <div className="text-xs text-app-text3">{assignment.equipment_code}</div>
                    </td>
                    <td className="px-3 py-2 hidden md:table-cell text-app-text2">
                      {assignment.assigned_to_name || '—'}
                    </td>
                    <td className="px-3 py-2">
                      <span className="text-xs font-bold">{getStatusLabel(assignment.status)}</span>
                    </td>
                    <td className="px-3 py-2 hidden lg:table-cell text-app-text3">
                      {assignment.due_date
                        ? new Date(assignment.due_date).toLocaleDateString('ru-RU')
                        : '—'}
                    </td>
                    <td className="px-3 py-2">
                      <div className="flex flex-wrap gap-1">
                        <button
                          type="button"
                          onClick={() => handleViewChecklist(assignment.id)}
                          className="px-2 py-1 text-xs rounded bg-app-soft hover:bg-app-softer"
                        >
                          Чек-лист
                        </button>
                        <button
                          type="button"
                          onClick={() => setEditingAssignment(assignment)}
                          className="px-2 py-1 text-xs rounded bg-app-soft hover:bg-app-softer"
                        >
                          Изменить
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

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

      {editingAssignment && (
        <EditAssignmentModal
          assignment={editingAssignment}
          isOpen={true}
          onClose={() => setEditingAssignment(null)}
          onSaved={() => {
            loadAssignments();
            loadStatistics();
            loadObjectStatistics();
          }}
        />
      )}
    </div>
  );
};

export default AssignmentsManagement;
