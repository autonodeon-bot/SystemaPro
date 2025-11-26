import React, { useState, useEffect } from 'react';
import { Search, Filter, FileText, Package, Calendar, User, MapPin, Eye, Download } from 'lucide-react';

interface Inspection {
  id: string;
  equipment_id: string;
  equipment_name?: string;
  equipment_location?: string;
  data: any;
  conclusion?: string;
  status: string;
  date_performed?: string;
  created_at: string;
  inspector_id?: string;
  inspector_name?: string;
}

interface Equipment {
  id: string;
  name: string;
  location?: string;
}

const InspectionsList = () => {
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedEquipment, setSelectedEquipment] = useState<string>('all');
  const [selectedStatus, setSelectedStatus] = useState<string>('all');
  const [selectedInspection, setSelectedInspection] = useState<Inspection | null>(null);
  const [showDetails, setShowDetails] = useState(false);

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    const init = async () => {
      await loadEquipment();
      await loadInspections();
    };
    init();
  }, []);

  useEffect(() => {
    loadInspections();
  }, [selectedEquipment, selectedStatus]);

  const loadEquipment = async () => {
    try {
      const response = await fetch(`${API_BASE}/api/equipment`);
      const data = await response.json();
      setEquipment(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки оборудования:', error);
    }
  };

  const loadInspections = async () => {
    setLoading(true);
    try {
      let url = `${API_BASE}/api/inspections?limit=1000`;
      if (selectedEquipment !== 'all') {
        url += `&equipment_id=${selectedEquipment}`;
      }

      const response = await fetch(url);
      const data = await response.json();
      let inspectionsList = data.items || [];

      // Фильтрация по статусу
      if (selectedStatus !== 'all') {
        inspectionsList = inspectionsList.filter((insp: Inspection) => insp.status === selectedStatus);
      }

      // Обогащение данными об оборудовании (API уже возвращает equipment_name и equipment_location)
      // Но если их нет, используем локальный кэш
      for (const insp of inspectionsList) {
        if (!insp.equipment_name || !insp.equipment_location) {
          const eq = equipment.find(e => e.id === insp.equipment_id);
          if (eq) {
            insp.equipment_name = eq.name;
            insp.equipment_location = eq.location;
          }
        }
      }

      setInspections(inspectionsList);
    } catch (error) {
      console.error('Ошибка загрузки диагностик:', error);
    } finally {
      setLoading(false);
    }
  };

  const filteredInspections = inspections.filter(insp => {
    const matchesSearch = 
      insp.equipment_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      insp.conclusion?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      insp.id.toLowerCase().includes(searchTerm.toLowerCase());
    return matchesSearch;
  });

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'SIGNED':
        return 'bg-green-500/20 text-green-400 border-green-500/30';
      case 'DRAFT':
        return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30';
      case 'REJECTED':
        return 'bg-red-500/20 text-red-400 border-red-500/30';
      default:
        return 'bg-slate-500/20 text-slate-400 border-slate-500/30';
    }
  };

  const getStatusLabel = (status: string) => {
    switch (status) {
      case 'SIGNED':
        return 'Подписан';
      case 'DRAFT':
        return 'Черновик';
      case 'REJECTED':
        return 'Отклонен';
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

  const renderInspectionDetails = (insp: Inspection) => {
    const data = insp.data || {};
    
    return (
      <div className="space-y-6">
        {/* Основная информация */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Оборудование</label>
            <div className="flex items-center gap-2">
              <Package size={16} className="text-accent" />
              <span className="font-medium">{insp.equipment_name || 'Не указано'}</span>
            </div>
          </div>
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Местоположение</label>
            <div className="flex items-center gap-2">
              <MapPin size={16} className="text-accent" />
              <span>{insp.equipment_location || 'Не указано'}</span>
            </div>
          </div>
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Дата обследования</label>
            <div className="flex items-center gap-2">
              <Calendar size={16} className="text-accent" />
              <span>{formatDate(insp.date_performed)}</span>
            </div>
          </div>
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Статус</label>
            <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium border ${getStatusColor(insp.status)}`}>
              {getStatusLabel(insp.status)}
            </span>
          </div>
        </div>

        {/* Данные чек-листа */}
        {data.executors && (
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Исполнители</label>
            <p className="text-white">{data.executors}</p>
          </div>
        )}

        {data.organization && (
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Организация</label>
            <p className="text-white">{data.organization}</p>
          </div>
        )}

        {/* Документы */}
        {data.documents && (
          <div>
            <label className="text-xs text-slate-400 mb-2 block">Перечень рассмотренных документов</label>
            <div className="space-y-2">
              {Object.entries(data.documents).map(([key, value]: [string, any]) => (
                <div key={key} className="flex items-center justify-between p-2 bg-secondary/50 rounded">
                  <span className="text-sm text-slate-300">Документ {key}</span>
                  <span className={`px-2 py-1 rounded text-xs ${value ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
                    {value ? 'Да' : 'Нет'}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Карта обследования */}
        {data.vesselName && (
          <div>
            <label className="text-xs text-slate-400 mb-2 block">Карта обследования</label>
            <div className="grid grid-cols-2 gap-4 p-4 bg-secondary/50 rounded">
              <div>
                <span className="text-xs text-slate-400">Наименование сосуда</span>
                <p className="text-white font-medium">{data.vesselName}</p>
              </div>
              {data.serialNumber && (
                <div>
                  <span className="text-xs text-slate-400">Заводской номер</span>
                  <p className="text-white font-medium">{data.serialNumber}</p>
                </div>
              )}
              {data.regNumber && (
                <div>
                  <span className="text-xs text-slate-400">Регистрационный номер</span>
                  <p className="text-white font-medium">{data.regNumber}</p>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Заключение */}
        {insp.conclusion && (
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Заключение</label>
            <div className="p-4 bg-secondary/50 rounded">
              <p className="text-white whitespace-pre-wrap">{insp.conclusion}</p>
            </div>
          </div>
        )}

        {/* Дополнительные данные */}
        {Object.keys(data).length > 0 && (
          <details className="mt-4">
            <summary className="cursor-pointer text-sm text-slate-400 hover:text-white">
              Показать все данные
            </summary>
            <pre className="mt-2 p-4 bg-secondary/50 rounded text-xs overflow-auto text-slate-300">
              {JSON.stringify(data, null, 2)}
            </pre>
          </details>
        )}
      </div>
    );
  };

  return (
    <div className="space-y-6">
      {/* Заголовок */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <FileText className="text-accent" size={28} />
            Чек-листы диагностики
          </h1>
          <p className="text-slate-400 mt-1">Просмотр всех чек-листов, отправленных из мобильного приложения</p>
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
                placeholder="Поиск по оборудованию, заключению..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full pl-10 pr-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
              />
            </div>
          </div>

          {/* Фильтр по оборудованию */}
          <div className="min-w-[200px]">
            <select
              value={selectedEquipment}
              onChange={(e) => setSelectedEquipment(e.target.value)}
              className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="all">Все оборудование</option>
              {equipment.map((eq) => (
                <option key={eq.id} value={eq.id}>
                  {eq.name}
                </option>
              ))}
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
              <option value="REJECTED">Отклонен</option>
            </select>
          </div>
        </div>
      </div>

      {/* Список чек-листов */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-accent"></div>
          <p className="text-slate-400 mt-4">Загрузка чек-листов...</p>
        </div>
      ) : filteredInspections.length === 0 ? (
        <div className="text-center py-12 bg-secondary/50 rounded-lg">
          <FileText className="mx-auto text-slate-400 mb-4" size={48} />
          <p className="text-slate-400">Чек-листы не найдены</p>
        </div>
      ) : (
        <div className="space-y-3">
          {filteredInspections.map((insp) => (
            <div
              key={insp.id}
              className="bg-secondary/50 rounded-lg p-4 hover:bg-secondary/70 transition-colors cursor-pointer border border-slate-700"
              onClick={() => {
                setSelectedInspection(insp);
                setShowDetails(true);
              }}
            >
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <div className="flex items-center gap-3 mb-2">
                    <Package className="text-accent" size={20} />
                    <h3 className="font-semibold text-white">{insp.equipment_name || 'Неизвестное оборудование'}</h3>
                    <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium border ${getStatusColor(insp.status)}`}>
                      {getStatusLabel(insp.status)}
                    </span>
                  </div>
                  
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                    {insp.equipment_location && (
                      <div className="flex items-center gap-2 text-slate-400">
                        <MapPin size={14} />
                        <span>{insp.equipment_location}</span>
                      </div>
                    )}
                    <div className="flex items-center gap-2 text-slate-400">
                      <Calendar size={14} />
                      <span>{formatDate(insp.date_performed)}</span>
                    </div>
                    <div className="flex items-center gap-2 text-slate-400">
                      <FileText size={14} />
                      <span>ID: {insp.id.substring(0, 8)}...</span>
                    </div>
                    {insp.conclusion && (
                      <div className="text-slate-300 truncate">
                        {insp.conclusion.substring(0, 50)}...
                      </div>
                    )}
                  </div>
                </div>
                
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setSelectedInspection(insp);
                    setShowDetails(true);
                  }}
                  className="ml-4 p-2 text-slate-400 hover:text-accent hover:bg-secondary rounded transition-colors"
                >
                  <Eye size={20} />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Модальное окно с деталями */}
      {showDetails && selectedInspection && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setShowDetails(false)}>
          <div
            className="bg-secondary rounded-lg max-w-4xl w-full max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-secondary border-b border-slate-700 p-6 flex items-center justify-between">
              <h2 className="text-xl font-bold text-white flex items-center gap-2">
                <FileText className="text-accent" size={24} />
                Детали чек-листа
              </h2>
              <button
                onClick={() => setShowDetails(false)}
                className="text-slate-400 hover:text-white transition-colors"
              >
                ✕
              </button>
            </div>
            <div className="p-6">
              {renderInspectionDetails(selectedInspection)}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default InspectionsList;

