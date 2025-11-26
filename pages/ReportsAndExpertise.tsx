import React, { useState, useEffect } from 'react';
import { 
  FileText, Download, Search, Filter, Building2, Factory, 
  Package, MapPin, Calendar, User, Eye, ChevronRight, 
  ChevronDown, Folder, FolderOpen, Network, Plus, FileCheck,
  AlertCircle, CheckCircle, Clock, X
} from 'lucide-react';

interface Report {
  id: string;
  inspection_id?: string;
  equipment_id: string;
  equipment_name?: string;
  equipment_location?: string;
  project_id?: string;
  report_type: string;
  title: string;
  file_path: string;
  file_size: number;
  status: string;
  created_at: string;
  created_by?: string;
}

interface Equipment {
  id: string;
  name: string;
  location?: string;
  type_id?: string;
  serial_number?: string;
}

interface Client {
  id: string;
  name: string;
  address?: string;
}

interface HierarchyNode {
  id: string;
  name: string;
  type: 'client' | 'location' | 'equipment' | 'report';
  children?: HierarchyNode[];
  data?: Equipment | Client | Report;
}

const ReportsAndExpertise = () => {
  const [reports, setReports] = useState<Report[]>([]);
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [clients, setClients] = useState<Client[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedReportType, setSelectedReportType] = useState<string>('all');
  const [selectedStatus, setSelectedStatus] = useState<string>('all');
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set());
  const [selectedReport, setSelectedReport] = useState<Report | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [viewMode, setViewMode] = useState<'list' | 'tree'>('tree');

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadData();
  }, []);

  useEffect(() => {
    loadData();
  }, [selectedReportType, selectedStatus]);

  const loadData = async () => {
    setLoading(true);
    try {
      const [reportsRes, equipmentRes, clientsRes] = await Promise.all([
        fetch(`${API_BASE}/api/reports`),
        fetch(`${API_BASE}/api/equipment`),
        fetch(`${API_BASE}/api/clients`)
      ]);

      const reportsData = await reportsRes.json();
      const equipmentData = await equipmentRes.json();
      const clientsData = await clientsRes.json();

      let reportsList = reportsData.items || [];
      
      // Обогащение данными об оборудовании
      const equipmentMap = new Map(
        (equipmentData.items || []).map((eq: Equipment) => [eq.id, eq])
      );

      reportsList = reportsList.map((r: Report) => {
        const eq = equipmentMap.get(r.equipment_id);
        return {
          ...r,
          equipment_name: eq?.name || 'Неизвестное оборудование',
          equipment_location: eq?.location || 'Не указано'
        };
      });

      setReports(reportsList);
      setEquipment(equipmentData.items || []);
      setClients(clientsData.items || []);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
    }
  };

  const buildHierarchy = (): HierarchyNode[] => {
    const hierarchy: HierarchyNode[] = [];
    const clientMap = new Map<string, HierarchyNode>();
    const locationMap = new Map<string, HierarchyNode>();

    // Группируем отчеты по клиентам и локациям
    reports.forEach(report => {
      const location = report.equipment_location || 'Не указано';
      const clientName = location.split(',')[0] || 'Не указано';

      // Находим или создаем клиента
      let clientNode = clientMap.get(clientName);
      if (!clientNode) {
        const client = clients.find(c => c.name.includes(clientName) || clientName.includes(c.name));
        clientNode = {
          id: `client-${clientName}`,
          name: client?.name || clientName,
          type: 'client',
          children: [],
          data: client
        };
        clientMap.set(clientName, clientNode);
        hierarchy.push(clientNode);
      }

      // Находим или создаем локацию
      let locationNode = locationMap.get(location);
      if (!locationNode) {
        locationNode = {
          id: `location-${location}`,
          name: location,
          type: 'location',
          children: [],
          data: undefined
        };
        locationMap.set(location, locationNode);
        if (!clientNode.children) clientNode.children = [];
        clientNode.children.push(locationNode);
      }

      // Находим оборудование
      const eq = equipment.find(e => e.id === report.equipment_id);
      let equipmentNode = locationNode.children?.find(
        n => n.type === 'equipment' && n.id === `equipment-${report.equipment_id}`
      );

      if (!equipmentNode) {
        equipmentNode = {
          id: `equipment-${report.equipment_id}`,
          name: report.equipment_name || 'Неизвестное оборудование',
          type: 'equipment',
          children: [],
          data: eq
        };
        if (!locationNode.children) locationNode.children = [];
        locationNode.children.push(equipmentNode);
      }

      // Добавляем отчет
      if (!equipmentNode.children) equipmentNode.children = [];
      equipmentNode.children.push({
        id: report.id,
        name: report.title,
        type: 'report',
        data: report
      });
    });

    return hierarchy;
  };

  const filteredReports = reports.filter(r => {
    const matchesSearch = 
      r.title.toLowerCase().includes(searchTerm.toLowerCase()) ||
      r.equipment_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      r.equipment_location?.toLowerCase().includes(searchTerm.toLowerCase());
    
    const matchesType = selectedReportType === 'all' || r.report_type === selectedReportType;
    const matchesStatus = selectedStatus === 'all' || r.status === selectedStatus;

    return matchesSearch && matchesType && matchesStatus;
  });

  const getReportTypeLabel = (type: string) => {
    switch (type) {
      case 'TECHNICAL_REPORT':
        return 'Технический отчет';
      case 'EXPERTISE':
        return 'Экспертиза ПБ';
      case 'RESOURCE_EXTENSION':
        return 'Продление ресурса';
      default:
        return type;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'SIGNED':
      case 'APPROVED':
        return 'bg-green-500/20 text-green-400 border-green-500/30';
      case 'DRAFT':
        return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30';
      case 'SENT':
        return 'bg-blue-500/20 text-blue-400 border-blue-500/30';
      default:
        return 'bg-slate-500/20 text-slate-400 border-slate-500/30';
    }
  };

  const getStatusLabel = (status: string) => {
    switch (status) {
      case 'DRAFT':
        return 'Черновик';
      case 'SIGNED':
        return 'Подписан';
      case 'APPROVED':
        return 'Утвержден';
      case 'SENT':
        return 'Отправлен клиенту';
      default:
        return status;
    }
  };

  const formatDate = (dateString?: string) => {
    if (!dateString) return 'Не указана';
    try {
      const date = new Date(dateString);
      return date.toLocaleDateString('ru-RU', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch {
      return dateString;
    }
  };

  const formatFileSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} Б`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} КБ`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} МБ`;
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

    const getIcon = () => {
      switch (node.type) {
        case 'client':
          return <Building2 size={16} className="text-indigo-400" />;
        case 'location':
          return <MapPin size={16} className="text-blue-400" />;
        case 'equipment':
          return <Package size={16} className="text-green-400" />;
        case 'report':
          return <FileText size={16} className="text-accent" />;
        default:
          return <Folder size={16} />;
      }
    };

    return (
      <div key={node.id}>
        <div
          className={`flex items-center gap-2 py-2 px-3 cursor-pointer transition-colors ${
            node.type === 'report' 
              ? 'hover:bg-secondary/70 text-white' 
              : 'hover:bg-secondary/50 text-slate-300'
          }`}
          style={{ paddingLeft: `${level * 20 + 12}px` }}
          onClick={() => {
            if (hasChildren) toggleNode(node.id);
            if (node.type === 'report' && node.data) {
              setSelectedReport(node.data as Report);
              setShowDetails(true);
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
          {node.type === 'report' && node.data && (
            <span className={`px-2 py-0.5 rounded text-xs border ${getStatusColor((node.data as Report).status)}`}>
              {getStatusLabel((node.data as Report).status)}
            </span>
          )}
        </div>
        {isExpanded && hasChildren && node.children!.map(child => renderTreeNode(child, level + 1))}
      </div>
    );
  };

  const hierarchy = buildHierarchy();

  return (
    <div className="space-y-6">
      {/* Заголовок */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <FileCheck className="text-accent" size={28} />
            Отчеты и Экспертизы
          </h1>
          <p className="text-slate-400 mt-1">
            Просмотр всех отчетов и экспертиз, созданных через мобильное приложение
          </p>
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => setViewMode(viewMode === 'list' ? 'tree' : 'list')}
            className="px-4 py-2 bg-secondary/50 hover:bg-secondary rounded-lg text-white text-sm transition-colors"
          >
            {viewMode === 'list' ? 'Дерево' : 'Список'}
          </button>
        </div>
      </div>

      {/* Фильтры и поиск */}
      <div className="bg-secondary/50 rounded-lg p-4 space-y-4">
        <div className="flex flex-wrap gap-4">
          {/* Поиск */}
          <div className="flex-1 min-w-[200px]">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={18} />
              <input
                type="text"
                placeholder="Поиск по названию, оборудованию, локации..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full pl-10 pr-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
              />
            </div>
          </div>

          {/* Фильтр по типу */}
          <div className="min-w-[200px]">
            <select
              value={selectedReportType}
              onChange={(e) => setSelectedReportType(e.target.value)}
              className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="all">Все типы</option>
              <option value="TECHNICAL_REPORT">Технический отчет</option>
              <option value="EXPERTISE">Экспертиза ПБ</option>
              <option value="RESOURCE_EXTENSION">Продление ресурса</option>
            </select>
          </div>

          {/* Фильтр по статусу */}
          <div className="min-w-[150px]">
            <select
              value={selectedStatus}
              onChange={(e) => setSelectedStatus(e.target.value)}
              className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="all">Все статусы</option>
              <option value="DRAFT">Черновик</option>
              <option value="SIGNED">Подписан</option>
              <option value="APPROVED">Утвержден</option>
              <option value="SENT">Отправлен</option>
            </select>
          </div>
        </div>
      </div>

      {/* Список отчетов */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-accent"></div>
          <p className="text-slate-400 mt-4">Загрузка отчетов...</p>
        </div>
      ) : viewMode === 'tree' ? (
        <div className="bg-secondary/50 rounded-lg border border-slate-700 overflow-hidden">
          {hierarchy.length === 0 ? (
            <div className="text-center py-12">
              <FileText className="mx-auto text-slate-400 mb-4" size={48} />
              <p className="text-slate-400">Отчеты не найдены</p>
            </div>
          ) : (
            <div className="max-h-[600px] overflow-y-auto">
              {hierarchy.map(node => renderTreeNode(node))}
            </div>
          )}
        </div>
      ) : (
        <div className="space-y-3">
          {filteredReports.length === 0 ? (
            <div className="text-center py-12 bg-secondary/50 rounded-lg">
              <FileText className="mx-auto text-slate-400 mb-4" size={48} />
              <p className="text-slate-400">Отчеты не найдены</p>
            </div>
          ) : (
            filteredReports.map((report) => (
              <div
                key={report.id}
                className="bg-secondary/50 rounded-lg p-4 hover:bg-secondary/70 transition-colors cursor-pointer border border-slate-700"
                onClick={() => {
                  setSelectedReport(report);
                  setShowDetails(true);
                }}
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-3 mb-2">
                      <FileText className="text-accent" size={20} />
                      <h3 className="font-semibold text-white">{report.title}</h3>
                      <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium border ${getStatusColor(report.status)}`}>
                        {getStatusLabel(report.status)}
                      </span>
                      <span className="px-2 py-1 bg-slate-700 rounded text-xs text-slate-300">
                        {getReportTypeLabel(report.report_type)}
                      </span>
                    </div>
                    
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                      <div className="flex items-center gap-2 text-slate-400">
                        <Package size={14} />
                        <span>{report.equipment_name}</span>
                      </div>
                      {report.equipment_location && (
                        <div className="flex items-center gap-2 text-slate-400">
                          <MapPin size={14} />
                          <span>{report.equipment_location}</span>
                        </div>
                      )}
                      <div className="flex items-center gap-2 text-slate-400">
                        <Calendar size={14} />
                        <span>{formatDate(report.created_at)}</span>
                      </div>
                      <div className="flex items-center gap-2 text-slate-400">
                        <FileText size={14} />
                        <span>{formatFileSize(report.file_size)}</span>
                      </div>
                    </div>
                  </div>
                  
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setSelectedReport(report);
                      setShowDetails(true);
                    }}
                    className="ml-4 p-2 text-slate-400 hover:text-accent hover:bg-secondary rounded transition-colors"
                  >
                    <Eye size={20} />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Модальное окно с деталями */}
      {showDetails && selectedReport && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setShowDetails(false)}>
          <div
            className="bg-secondary rounded-lg max-w-4xl w-full max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-secondary border-b border-slate-700 p-6 flex items-center justify-between">
              <h2 className="text-xl font-bold text-white flex items-center gap-2">
                <FileText className="text-accent" size={24} />
                Детали отчета
              </h2>
              <button
                onClick={() => setShowDetails(false)}
                className="text-slate-400 hover:text-white transition-colors"
              >
                <X size={24} />
              </button>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Название</label>
                  <p className="text-white font-medium">{selectedReport.title}</p>
                </div>
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Тип отчета</label>
                  <p className="text-white">{getReportTypeLabel(selectedReport.report_type)}</p>
                </div>
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Оборудование</label>
                  <div className="flex items-center gap-2">
                    <Package size={16} className="text-accent" />
                    <span className="font-medium">{selectedReport.equipment_name || 'Не указано'}</span>
                  </div>
                </div>
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Местоположение</label>
                  <div className="flex items-center gap-2">
                    <MapPin size={16} className="text-accent" />
                    <span>{selectedReport.equipment_location || 'Не указано'}</span>
                  </div>
                </div>
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Дата создания</label>
                  <div className="flex items-center gap-2">
                    <Calendar size={16} className="text-accent" />
                    <span>{formatDate(selectedReport.created_at)}</span>
                  </div>
                </div>
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Статус</label>
                  <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium border ${getStatusColor(selectedReport.status)}`}>
                    {getStatusLabel(selectedReport.status)}
                  </span>
                </div>
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Размер файла</label>
                  <p className="text-white">{formatFileSize(selectedReport.file_size)}</p>
                </div>
              </div>

              <div className="flex gap-3 pt-4 border-t border-slate-700">
                <a
                  href={`${API_BASE}/api/reports/${selectedReport.id}/download`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="px-4 py-2 bg-accent hover:bg-accent/80 rounded-lg text-white font-medium flex items-center gap-2 transition-colors"
                >
                  <Download size={18} />
                  Скачать отчет
                </a>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ReportsAndExpertise;

