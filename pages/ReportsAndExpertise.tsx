import React, { useMemo, useState, useEffect } from 'react';
import { Download, FileText, Search, Filter, Calendar, User, AlertCircle, Upload, X, File, Image as ImageIcon, Trash2, CheckCircle2 } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

const API_BASE = 'http://5.129.203.182:8000';

interface Report {
  id: string;
  inspection_id?: string;
  equipment_id: string;
  equipment_name?: string;
  equipment_location?: string;
  project_id?: string;
  report_type: string;
  title: string;
  file_path?: string;
  file_size?: number;
  status: string;
  created_at?: string;
  created_by?: string;
}

interface NDTMethod {
  id: string;
  method_code: string;
  method_name: string;
  is_performed: boolean;
  standard?: string;
  equipment?: string;
  inspector_name?: string;
  inspector_level?: string;
  results?: string;
  defects?: string;
  conclusion?: string;
}

interface DocumentFile {
  id: string;
  document_number: string;
  file_name: string;
  file_size: number;
  file_type?: string;
  mime_type?: string;
  created_at?: string;
}

interface Questionnaire {
  id: string;
  equipment_id: string;
  equipment_name?: string;
  equipment_inventory_number?: string;
  inspection_date?: string;
  inspector_name?: string;
  inspector_position?: string;
  file_path?: string;
  file_size?: number;
  word_file_path?: string;
  word_file_size?: number;
  ndt_methods?: NDTMethod[];
  document_files?: DocumentFile[];
  created_by?: string;
  created_at?: string;
}

const ReportsAndExpertise = () => {
  const { user } = useAuth();
  const [reports, setReports] = useState<Report[]>([]);
  const [questionnaires, setQuestionnaires] = useState<Questionnaire[]>([]);
  const [equipment, setEquipment] = useState<any[]>([]);
  const [clients, setClients] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterType, setFilterType] = useState<string>('all');
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [selectedQuestionnaire, setSelectedQuestionnaire] = useState<Questionnaire | null>(null);
  const [documentFiles, setDocumentFiles] = useState<Record<string, DocumentFile[]>>({});
  const [uploadingFile, setUploadingFile] = useState<string | null>(null);
  const [cleanupReportsDays, setCleanupReportsDays] = useState<number>(180);

  useEffect(() => {
    loadData();
  }, []);

  const canApprove = useMemo(() => {
    const role = (user?.role || '').toLowerCase();
    return ['admin', 'chief_operator', 'operator'].includes(role);
  }, [user]);

  const approveReport = async (inspectionId?: string) => {
    if (!inspectionId) return;
    const confirm = window.confirm('Утвердить отчет/обследование? Статус станет APPROVED.');
    if (!confirm) return;
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;
      const res = await fetch(`${API_BASE}/api/inspections/${inspectionId}/status`, {
        method: 'PATCH',
        headers,
        body: JSON.stringify({ status: 'APPROVED' }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }));
        alert(`Ошибка утверждения: ${err.detail || res.statusText}`);
        return;
      }
      await loadData();
    } catch (e) {
      alert(`Ошибка утверждения: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const deleteReport = async (reportId: string) => {
    const confirm = window.confirm('Удалить отчет? Файл будет удален без возможности восстановления.');
    if (!confirm) return;
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const res = await fetch(`${API_BASE}/api/reports/${reportId}`, {
        method: 'DELETE',
        headers,
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }));
        alert(`Ошибка удаления: ${err.detail || res.statusText}`);
        return;
      }
      await loadData();
    } catch (e) {
      alert(`Ошибка удаления: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const handleBulkDeleteReports = async () => {
    if (selectedReports.size === 0) {
      alert('Выберите отчеты для удаления');
      return;
    }
    const confirm = window.confirm(`Удалить ${selectedReports.size} выбранных отчетов? Файлы будут удалены без возможности восстановления.`);
    if (!confirm) return;
    
    setIsProcessing(true);
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/reports/bulk-delete`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ report_ids: Array.from(selectedReports) })
      });
      
      if (!response.ok) {
        let errorMessage = `HTTP ${response.status}: ${response.statusText}`;
        try {
          const text = await response.text();
          try {
            const err = JSON.parse(text);
            if (typeof err === 'string') {
              errorMessage = err;
            } else if (err && typeof err === 'object') {
              errorMessage = err.detail || err.message || err.error || String(err) || errorMessage;
            }
          } catch {
            // Если не JSON, используем текст ответа
            errorMessage = text || errorMessage;
          }
        } catch (parseError) {
          // Если не удалось прочитать ответ, используем статус
          errorMessage = `HTTP ${response.status}: ${response.statusText}`;
        }
        console.error('Ошибка удаления отчетов:', errorMessage);
        alert(`Ошибка удаления: ${errorMessage}`);
        return;
      }
      
      const data = await response.json();
      alert(`Удалено: ${data.deleted} из ${data.total} отчетов`);
      setSelectedReports(new Set());
      await loadData();
    } catch (e) {
      let errorMessage = 'Неизвестная ошибка';
      if (e instanceof Error) {
        errorMessage = e.message;
      } else if (typeof e === 'string') {
        errorMessage = e;
      } else if (e && typeof e === 'object') {
        errorMessage = (e as any).message || (e as any).detail || String(e);
      }
      alert(`Ошибка удаления: ${errorMessage}`);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleBulkArchiveReports = async () => {
    if (selectedReports.size === 0) {
      alert('Выберите отчеты для архивирования');
      return;
    }
    const confirm = window.confirm(`Отправить ${selectedReports.size} выбранных отчетов в архив?`);
    if (!confirm) return;
    
    setIsProcessing(true);
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/reports/bulk-archive`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ report_ids: Array.from(selectedReports), archive: true })
      });
      
      if (!response.ok) {
        let errorMessage = response.statusText;
        try {
          const err = await response.json();
          errorMessage = err.detail || err.message || JSON.stringify(err) || response.statusText;
        } catch {
          errorMessage = response.statusText;
        }
        alert(`Ошибка архивирования: ${errorMessage}`);
        return;
      }
      
      const data = await response.json();
      alert(`Отправлено в архив: ${data.archived} из ${data.total} отчетов`);
      setSelectedReports(new Set());
      await loadData();
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : (typeof e === 'string' ? e : JSON.stringify(e));
      alert(`Ошибка архивирования: ${errorMessage}`);
    } finally {
      setIsProcessing(false);
    }
  };

  // Удален дубликат функций handleBulkDeleteReportsDuplicate и handleBulkArchiveReports

  const cleanupOldReports = async () => {
    const confirm = window.confirm(`Удалить отчеты старше ${cleanupReportsDays} дней? Файлы будут удалены без возможности восстановления.`);
    if (!confirm) return;
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const res = await fetch(`${API_BASE}/api/reports/cleanup?older_than_days=${cleanupReportsDays}`, {
        method: 'DELETE',
        headers,
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }));
        alert(`Ошибка очистки: ${err.detail || res.statusText}`);
        return;
      }
      const data = await res.json().catch(() => null as any);
      alert(`Удалено отчетов: ${data?.deleted ?? 'OK'}`);
      await loadData();
    } catch (e) {
      alert(`Ошибка очистки: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const loadData = async () => {
    setLoading(true);
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const [reportsRes, equipmentRes, clientsRes, questionnairesRes] = await Promise.all([
        fetch(`${API_BASE}/api/reports`, { headers }),
        fetch(`${API_BASE}/api/equipment`, { headers }),
        fetch(`${API_BASE}/api/clients`, { headers }),
        fetch(`${API_BASE}/api/questionnaires`, { headers }).catch(() => null)
      ]);

      const reportsData = await reportsRes.json();
      const equipmentData = await equipmentRes.json();
      const clientsData = await clientsRes.json();
      
      let reportsList = reportsData.items || [];
      
      // Загружаем опросные листы, если доступны
      let questionnairesList: Questionnaire[] = [];
      if (questionnairesRes && questionnairesRes.ok) {
        try {
          const questionnairesData = await questionnairesRes.json();
          questionnairesList = questionnairesData.items || [];
          
          // Для каждого опросного листа загружаем методы НК и файлы документов
          for (const q of questionnairesList) {
            try {
              const qDetailRes = await fetch(`${API_BASE}/api/questionnaires/${q.id}`, { headers });
              if (qDetailRes.ok) {
                const qDetail = await qDetailRes.json();
                q.ndt_methods = qDetail.ndt_methods || [];
                q.word_file_path = qDetail.word_file_path;
                q.word_file_size = qDetail.word_file_size || 0;
              }
            } catch (e) {
              console.error(`Ошибка загрузки деталей опросного листа ${q.id}:`, e);
            }
            
            // Загружаем файлы документов
            try {
              const filesRes = await fetch(`${API_BASE}/api/questionnaires/${q.id}/documents`, { headers });
              if (filesRes.ok) {
                const filesData = await filesRes.json();
                setDocumentFiles(prev => ({
                  ...prev,
                  [q.id]: filesData.items || [],
                }));
              }
            } catch (e) {
              console.error(`Ошибка загрузки файлов документов для ${q.id}:`, e);
            }
          }
        } catch (e) {
          console.error('Ошибка загрузки опросных листов:', e);
        }
      }
      
      // Обогащение данными об оборудовании
      const equipmentMap = new Map(
        (equipmentData.items || []).map((eq: any) => [eq.id, eq])
      );

      reportsList = reportsList.map((r: Report) => {
        const eq: any = equipmentMap.get(r.equipment_id);
        return {
          ...r,
          equipment_name: eq?.name || r.equipment_name || 'Неизвестное оборудование',
          equipment_location: eq?.location || r.equipment_location || 'Не указано'
        };
      });

      // Обогащаем опросные листы данными об оборудовании
      questionnairesList = questionnairesList.map((q: Questionnaire) => {
        const eq: any = equipmentMap.get(q.equipment_id);
        return {
          ...q,
          equipment_name: eq?.name || q.equipment_name || 'Неизвестное оборудование',
          equipment_location: eq?.location || 'Не указано'
        } as Questionnaire & { equipment_location?: string };
      });

      setReports(reportsList);
      setQuestionnaires(questionnairesList);
      setEquipment(equipmentData.items || []);
      setClients(clientsData.items || []);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
    }
  };

  const generateQuestionnairePDF = async (questionnaireId: string) => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const response = await fetch(`${API_BASE}/api/questionnaires/${questionnaireId}/generate-pdf`, {
        method: 'POST',
        headers
      });

      if (response.ok) {
        // После генерации обновляем данные
        await loadData();
        // Скачиваем файл
        window.open(`${API_BASE}/api/questionnaires/${questionnaireId}/download`, '_blank');
      } else {
        alert('Ошибка генерации PDF');
      }
    } catch (error) {
      console.error('Ошибка генерации PDF:', error);
      alert('Ошибка генерации PDF');
    }
  };

  const downloadQuestionnaire = (questionnaireId: string) => {
    window.open(`${API_BASE}/api/questionnaires/${questionnaireId}/download`, '_blank');
  };

  const getReportTypeLabel = (type: string) => {
    switch (type) {
      case 'TECHNICAL_REPORT':
        return 'Технический отчет';
      case 'EXPERTISE':
        return 'Экспертиза ПБ';
      case 'RESOURCE_EXTENSION':
        return 'Продление ресурса';
      case 'QUESTIONNAIRE':
        return 'Опросный лист';
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
    if (!bytes || bytes === 0) return '0 Б';
    if (bytes < 1024) return `${bytes} Б`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} КБ`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} МБ`;
  };

  // Объединяем отчеты и опросные листы для отображения
  const allItems = [
    ...reports.map(r => ({ ...r, itemType: 'report' as const })),
    ...questionnaires.map(q => ({ 
      ...q, 
      itemType: 'questionnaire' as const, 
      report_type: 'QUESTIONNAIRE', 
      title: `Опросный лист: ${q.equipment_name || 'Неизвестное оборудование'}`, 
      status: 'DRAFT',
      equipment_location: (q as any).equipment_location || 'Не указано'
    }))
  ];

  // Фильтрация
  const filteredItems = allItems.filter(item => {
    const matchesSearch = !searchTerm || 
      item.title?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      item.equipment_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      item.equipment_location?.toLowerCase().includes(searchTerm.toLowerCase());
    
    const matchesType = filterType === 'all' || 
      (filterType === 'questionnaire' && item.itemType === 'questionnaire') ||
      (filterType !== 'questionnaire' && item.itemType === 'report' && item.report_type === filterType);
    
    const matchesStatus = filterStatus === 'all' || item.status === filterStatus;
    
    return matchesSearch && matchesType && matchesStatus;
  });

  if (loading) {
    return (
      <div className="p-6">
        <div className="text-center text-slate-400">Загрузка...</div>
      </div>
    );
  }

  return (
    <div className="p-4 sm:p-6">
      <div className="mb-6">
        <h1 className="text-2xl sm:text-3xl font-bold text-white mb-2">Отчеты и Экспертизы</h1>
        <p className="text-slate-400 text-sm sm:text-base">
          Управление техническими отчетами, экспертизами и опросными листами
        </p>
      </div>

      {/* Фильтры и поиск */}
      <div className="mb-6 space-y-4">
        <div className="flex items-center justify-between p-3 bg-slate-800/50 border border-slate-700 rounded-lg">
          <div className="flex items-center gap-3">
            <button
              onClick={() => {
                if (selectedReports.size === filteredItems.length) {
                  setSelectedReports(new Set());
                } else {
                  setSelectedReports(new Set(filteredItems.map(item => item.id)));
                }
              }}
              className="px-3 py-1.5 bg-slate-700 hover:bg-slate-600 text-white rounded-lg text-sm font-semibold"
            >
              {selectedReports.size === filteredItems.length ? 'Снять все' : 'Выделить все'}
            </button>
            {selectedReports.size > 0 && (
              <span className="text-white font-semibold">Выбрано: {selectedReports.size}</span>
            )}
          </div>
          {selectedReports.size > 0 && (
            <div className="flex gap-2">
              <button
                onClick={handleBulkArchiveReports}
                disabled={isProcessing}
                className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm font-semibold disabled:opacity-50"
              >
                Отправить в архив
              </button>
              <button
                onClick={handleBulkDeleteReports}
                disabled={isProcessing}
                className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-sm font-semibold disabled:opacity-50"
              >
                Удалить выбранные
              </button>
              <button
                onClick={() => setSelectedReports(new Set())}
                className="px-4 py-2 bg-slate-600 hover:bg-slate-700 text-white rounded-lg text-sm font-semibold"
              >
                Снять выделение
              </button>
            </div>
          )}
        </div>
        <div className="flex flex-col sm:flex-row gap-3">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
            <input
              type="text"
              placeholder="Поиск по названию, оборудованию, локации..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white placeholder-slate-500"
            />
          </div>
        </div>

        <div className="flex flex-wrap gap-3 items-center">
          <select
            value={filterType}
            onChange={(e) => setFilterType(e.target.value)}
            className="px-4 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white"
          >
            <option value="all">Все типы</option>
            <option value="TECHNICAL_REPORT">Технические отчеты</option>
            <option value="EXPERTISE">Экспертизы</option>
            <option value="RESOURCE_EXTENSION">Продление ресурса</option>
            <option value="questionnaire">Опросные листы</option>
          </select>

          <select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
            className="px-4 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white"
          >
            <option value="all">Все статусы</option>
            <option value="DRAFT">Черновик</option>
            <option value="SIGNED">Подписан</option>
            <option value="APPROVED">Утвержден</option>
            <option value="SENT">Отправлен</option>
          </select>

          <div className="flex items-center gap-2 sm:ml-auto">
            <span className="text-slate-400 text-sm hidden sm:inline">Очистка:</span>
            <select
              value={cleanupReportsDays}
              onChange={(e) => setCleanupReportsDays(parseInt(e.target.value, 10))}
              className="px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm"
              title="Удалить отчеты старше N дней"
            >
              <option value={30}>Старше 30 дней</option>
              <option value={90}>Старше 90 дней</option>
              <option value={180}>Старше 180 дней</option>
              <option value={365}>Старше 365 дней</option>
            </select>
            <button
              onClick={cleanupOldReports}
              className="flex items-center gap-2 px-3 py-2 bg-red-500/10 hover:bg-red-500/20 border border-red-500/20 text-red-300 rounded-lg text-sm font-semibold"
              title="Удалить старые отчеты"
            >
              <Trash2 size={16} />
              <span className="hidden sm:inline">Удалить старые отчеты</span>
              <span className="sm:hidden">Очистить</span>
            </button>
          </div>
        </div>
      </div>

      {/* Список отчетов и опросных листов */}
      <div className="space-y-4">
        {filteredItems.length === 0 ? (
          <div className="text-center text-slate-400 py-20">
            {searchTerm || filterType !== 'all' || filterStatus !== 'all' 
              ? 'Ничего не найдено' 
              : 'Отчеты и опросные листы не найдены'}
          </div>
        ) : (
          filteredItems.map((item) => (
            <div
              key={item.id}
              className="bg-slate-900 border border-slate-700 rounded-lg p-4 sm:p-6 hover:border-slate-600 transition-colors"
            >
              <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
                <div className="flex-1">
                  <div className="flex items-start gap-3 mb-3">
                    <FileText className="text-accent mt-1 flex-shrink-0" size={24} />
                    <div className="flex-1 min-w-0">
                      <h3 className="text-lg font-bold text-white mb-2 break-words">
                        {item.title}
                      </h3>
                      <div className="flex flex-wrap gap-2 mb-2">
                        <span className={`px-2 py-1 rounded text-xs font-semibold border ${getStatusColor(item.status)}`}>
                          {getStatusLabel(item.status)}
                        </span>
                        <span className="px-2 py-1 rounded text-xs font-semibold bg-blue-500/20 text-blue-400 border border-blue-500/30">
                          {getReportTypeLabel(item.report_type)}
                        </span>
                      </div>
                    </div>
                  </div>

                  <div className="space-y-2 text-sm text-slate-300">
                    <div className="flex items-center gap-2">
                      <span className="text-slate-400">Оборудование:</span>
                      <span className="font-medium">{item.equipment_name || 'Не указано'}</span>
                    </div>
                    {item.equipment_location && (
                      <div className="flex items-center gap-2">
                        <span className="text-slate-400">Местоположение:</span>
                        <span>{item.equipment_location}</span>
                      </div>
                    )}
                    {((item.itemType === 'questionnaire' || item.itemType === 'report') && (item as any).inspector_name) && (
                      <div className="flex items-center gap-2">
                        <User size={16} className="text-slate-400" />
                        <span className="text-slate-400">Инженер:</span>
                        <span className="font-medium">{(item as any).inspector_name}</span>
                        {(item as any).inspector_position && (
                          <span className="text-slate-500">({(item as any).inspector_position})</span>
                        )}
                      </div>
                    )}
                    {item.itemType === 'questionnaire' && (item as any).inspection_date && (
                      <div className="flex items-center gap-2">
                        <Calendar size={16} className="text-slate-400" />
                        <span className="text-slate-400">Дата обследования:</span>
                        <span>{formatDate((item as any).inspection_date)}</span>
                      </div>
                    )}
                    {item.created_at && (
                      <div className="flex items-center gap-2">
                        <span className="text-slate-400">Создан:</span>
                        <span>{formatDate(item.created_at)}</span>
                      </div>
                    )}
                    {item.file_size !== undefined && (
                      <div className="flex items-center gap-2">
                        <span className="text-slate-400">Размер PDF:</span>
                        <span>{formatFileSize(item.file_size)}</span>
                        {item.file_size === 0 && item.itemType === 'questionnaire' && (
                          <span className="text-yellow-400 text-xs flex items-center gap-1">
                            <AlertCircle size={14} />
                            PDF не сгенерирован
                          </span>
                        )}
                      </div>
                    )}
                    {item.itemType === 'questionnaire' && (item as any).word_file_size !== undefined && (
                      <div className="flex items-center gap-2">
                        <span className="text-slate-400">Размер Word:</span>
                        <span>{formatFileSize((item as any).word_file_size || 0)}</span>
                        {(item as any).word_file_size === 0 && (
                          <span className="text-yellow-400 text-xs flex items-center gap-1">
                            <AlertCircle size={14} />
                            Word не сгенерирован
                          </span>
                        )}
                      </div>
                    )}
                    {item.itemType === 'questionnaire' && (item as any).ndt_methods && (item as any).ndt_methods.length > 0 && (
                      <div className="mt-3 pt-3 border-t border-slate-700">
                        <div className="text-slate-400 text-sm mb-2">Методы неразрушающего контроля:</div>
                        <div className="flex flex-wrap gap-2">
                          {(item as any).ndt_methods.map((method: NDTMethod) => (
                            <span
                              key={method.id}
                              className="px-2 py-1 rounded text-xs bg-purple-500/20 text-purple-400 border border-purple-500/30"
                              title={`${method.method_name}${method.standard ? ` (${method.standard})` : ''}`}
                            >
                              {method.method_code}
                            </span>
                          ))}
                        </div>
                      </div>
                    )}
                    {item.itemType === 'questionnaire' && documentFiles[item.id] && documentFiles[item.id].length > 0 && (
                      <div className="mt-3 pt-3 border-t border-slate-700">
                        <div className="flex items-center gap-2 mb-2">
                          <File size={16} className="text-slate-400" />
                          <span className="text-slate-400 font-semibold">Прикрепленные документы:</span>
                        </div>
                        <div className="flex flex-wrap gap-2">
                          {documentFiles[item.id].map((file) => (
                            <a
                              key={file.id}
                              href={`${API_BASE}/api/questionnaires/${item.id}/documents/${file.document_number}/view`}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="flex items-center gap-2 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 rounded-lg text-sm text-white transition-colors"
                            >
                              {file.file_type === 'image' ? (
                                <ImageIcon size={14} className="text-green-400" />
                              ) : (
                                <FileText size={14} className="text-red-400" />
                              )}
                              <span className="max-w-[200px] truncate" title={getDocumentName(Number(file.document_number))}>
                                {getDocumentName(Number(file.document_number))}
                              </span>
                              <span className="text-slate-400 text-xs">({formatFileSize(file.file_size)})</span>
                            </a>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                </div>

                <div className="flex flex-col gap-2 flex-shrink-0">
                  {item.itemType === 'questionnaire' ? (
                    <>
                      <div className="flex gap-2">
                        {item.file_size === 0 || !item.file_path ? (
                          <button
                            onClick={() => generateQuestionnairePDF(item.id)}
                            className="px-3 py-2 bg-accent hover:bg-accent/80 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
                          >
                            <FileText size={16} />
                            <span className="hidden sm:inline">PDF</span>
                          </button>
                        ) : (
                          <a
                            href={`${API_BASE}/api/questionnaires/${item.id}/download`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="px-3 py-2 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
                          >
                            <Download size={16} />
                            <span className="hidden sm:inline">PDF</span>
                          </a>
                        )}
                        {(item as any).word_file_size === 0 || !(item as any).word_file_path ? (
                          <button
                            onClick={async () => {
                              try {
                                const headers: HeadersInit = { 'Content-Type': 'application/json' };
                                const token = localStorage.getItem('token');
                                if (token) {
                                  headers['Authorization'] = `Bearer ${token}`;
                                }
                                const response = await fetch(`${API_BASE}/api/questionnaires/${item.id}/generate-word`, {
                                  method: 'POST',
                                  headers
                                });
                                if (response.ok) {
                                  await loadData();
                                  window.open(`${API_BASE}/api/questionnaires/${item.id}/download-word`, '_blank');
                                } else {
                                  alert('Ошибка генерации Word');
                                }
                              } catch (error) {
                                console.error('Ошибка генерации Word:', error);
                                alert('Ошибка генерации Word');
                              }
                            }}
                            className="px-3 py-2 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
                          >
                            <FileText size={16} />
                            <span className="hidden sm:inline">Word</span>
                          </button>
                        ) : (
                          <a
                            href={`${API_BASE}/api/questionnaires/${item.id}/download-word`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="px-3 py-2 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
                          >
                            <Download size={16} />
                            <span className="hidden sm:inline">Word</span>
                          </a>
                        )}
                        <button
                          onClick={() => setSelectedQuestionnaire(item as Questionnaire)}
                          className="px-3 py-2 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
                        >
                          <Upload size={16} />
                          <span className="hidden sm:inline">Управление файлами</span>
                          <span className="sm:hidden">Файлы</span>
                        </button>
                      </div>
                    </>
                  ) : (
                    item.file_path && (
                      <div className="flex items-center gap-2">
                        <a
                          href={`${API_BASE}/api/reports/${item.id}/download`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="px-4 py-2 bg-accent hover:bg-accent/80 text-white font-semibold rounded-lg transition-colors flex items-center gap-2"
                        >
                          <Download size={18} />
                          <span className="hidden sm:inline">Скачать</span>
                          <span className="sm:hidden">PDF</span>
                        </a>
                        {canApprove && (item as any).inspection_id && item.status !== 'APPROVED' && (
                          <button
                            onClick={() => approveReport((item as any).inspection_id)}
                            className="px-4 py-2 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2"
                            title="Утвердить отчет"
                          >
                            <CheckCircle2 size={18} />
                            <span className="hidden sm:inline">Утвердить</span>
                          </button>
                        )}
                        <button
                          onClick={() => deleteReport(item.id)}
                          className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2"
                          title="Удалить отчет"
                        >
                          <Trash2 size={18} />
                          <span className="hidden sm:inline">Удалить</span>
                        </button>
                      </div>
                    )
                  )}
                </div>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Модальное окно управления файлами документов */}
      {selectedQuestionnaire && (
        <div className="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-4">
          <div className="bg-slate-800 rounded-xl border border-slate-700 w-full max-w-3xl max-h-[90vh] overflow-hidden flex flex-col">
            <div className="flex items-center justify-between p-6 border-b border-slate-700">
              <h2 className="text-xl font-bold text-white">
                Файлы документов: {selectedQuestionnaire.equipment_name}
              </h2>
              <button
                onClick={() => setSelectedQuestionnaire(null)}
                className="text-slate-400 hover:text-white"
              >
                <X size={24} />
              </button>
            </div>
            
            <div className="flex-1 overflow-y-auto p-6">
              <div className="space-y-4">
                {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17].map((docNum) => {
                  const docFile = documentFiles[selectedQuestionnaire.id]?.find(
                    f => f.document_number === String(docNum)
                  );
                  const docName = getDocumentName(docNum);
                  
                  return (
                    <div
                      key={docNum}
                      className="bg-slate-900 rounded-lg p-4 border border-slate-700"
                    >
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex-1">
                          <h4 className="text-white font-semibold">
                            {docNum}. {docName}
                          </h4>
                        </div>
                        <div className="flex items-center gap-2">
                          {docFile ? (
                            <>
                              <a
                                href={`${API_BASE}/api/questionnaires/${selectedQuestionnaire.id}/documents/${docNum}/view`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white text-sm rounded-lg flex items-center gap-2"
                              >
                                <Download size={14} />
                                Просмотр
                              </a>
                              <button
                                onClick={() => handleDeleteFile(selectedQuestionnaire.id, String(docNum))}
                                className="px-3 py-1.5 bg-red-600 hover:bg-red-700 text-white text-sm rounded-lg flex items-center gap-2"
                              >
                                <X size={14} />
                                Удалить
                              </button>
                            </>
                          ) : (
                            <label className="px-3 py-1.5 bg-green-600 hover:bg-green-700 text-white text-sm rounded-lg cursor-pointer flex items-center gap-2">
                              <Upload size={14} />
                              Загрузить
                              <input
                                type="file"
                                accept="image/*,.pdf"
                                className="hidden"
                                onChange={(e) => handleFileUpload(selectedQuestionnaire.id, String(docNum), e.target.files?.[0])}
                                disabled={uploadingFile === `${selectedQuestionnaire.id}-${docNum}`}
                              />
                            </label>
                          )}
                        </div>
                      </div>
                      {docFile && (
                        <div className="mt-2 text-sm text-slate-400">
                          <div className="flex items-center gap-2">
                            {docFile.file_type === 'image' ? (
                              <ImageIcon size={14} className="text-green-400" />
                            ) : (
                              <FileText size={14} className="text-red-400" />
                            )}
                            <span>{docFile.file_name}</span>
                            <span className="text-slate-500">({formatFileSize(docFile.file_size)})</span>
                          </div>
                        </div>
                      )}
                      {uploadingFile === `${selectedQuestionnaire.id}-${docNum}` && (
                        <div className="mt-2 text-sm text-blue-400">Загрузка...</div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );

  const getDocumentName = (number: number): string => {
    const names: Record<number, string> = {
      1: 'Лицензия на осуществление деятельности по эксплуатации взрывопожароопасных и химически опасных производственных объектов I, II и III классов опасности',
      2: 'Свидетельство о регистрации в государственном реестре ОПО, включая сведения характеризующие ОПО',
      3: 'Технологический регламент объектов опасных производственных объектов',
      4: 'План мероприятий по локализации и ликвидации последствий аварий на опасном производственном объекте',
      5: 'Положение о производственном контроле за соблюдением требований промышленной безопасности на опасных производственных объектах',
      6: 'Журнал учета аварий и инцидентов на ОПО',
      7: 'Страховой полис страхования гражданской ответственности владельца опасного объекта за причинение вреда в результате аварии на опасном объекте',
      8: 'Приказ о назначении ответственного лица за исправное состояние и безопасную эксплуатацию сосудов',
      9: 'Приказ о назначении ответственного лица за осуществление производственного контроля и соблюдение требований промышленной безопасности на опасном производственном объекте',
      10: 'Паспорт сосуда заводской (удостоверение о качестве монтажа, сертификат соответствия, сборочный чертёж и схема включения сосуда, расчёт на прочность)',
      11: 'Инструкция по монтажу и эксплуатации',
      12: 'Паспорта на предохранительные клапаны',
      13: 'Паспорта на запорную арматуру',
      14: 'Документация на контрольно-измерительные приборы',
      15: 'Ремонтная (исполнительная) документация',
      16: 'Заключение экспертизы промышленной безопасности',
      17: 'Акты проведения УЗТ',
    };
    return names[number] || `Документ ${number}`;
  };

  const handleFileUpload = async (questionnaireId: string, documentNumber: string, file: File | undefined) => {
    if (!file) return;

    setUploadingFile(`${questionnaireId}-${documentNumber}`);
    try {
      const formData = new FormData();
      formData.append('file', file);

      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const response = await fetch(
        `${API_BASE}/api/questionnaires/${questionnaireId}/documents/${documentNumber}/upload`,
        {
          method: 'POST',
          headers,
          body: formData,
        }
      );

      if (response.ok) {
        // Обновляем список файлов
        const filesRes = await fetch(`${API_BASE}/api/questionnaires/${questionnaireId}/documents`, { headers });
        if (filesRes.ok) {
          const filesData = await filesRes.json();
          setDocumentFiles(prev => ({
            ...prev,
            [questionnaireId]: filesData.items || [],
          }));
        }
      } else {
        const error = await response.json();
        alert(`Ошибка загрузки файла: ${error.detail || 'Неизвестная ошибка'}`);
      }
    } catch (e) {
      alert(`Ошибка загрузки файла: ${e}`);
    } finally {
      setUploadingFile(null);
    }
  };

  const handleDeleteFile = async (questionnaireId: string, documentNumber: string) => {
    if (!confirm('Вы уверены, что хотите удалить этот файл?')) return;

    try {
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const response = await fetch(
        `${API_BASE}/api/questionnaires/${questionnaireId}/documents/${documentNumber}`,
        {
          method: 'DELETE',
          headers,
        }
      );

      if (response.ok) {
        // Обновляем список файлов
        const filesRes = await fetch(`${API_BASE}/api/questionnaires/${questionnaireId}/documents`, { headers });
        if (filesRes.ok) {
          const filesData = await filesRes.json();
          setDocumentFiles(prev => ({
            ...prev,
            [questionnaireId]: filesData.items || [],
          }));
        }
      } else {
        const error = await response.json();
        alert(`Ошибка удаления файла: ${error.detail || 'Неизвестная ошибка'}`);
      }
    } catch (e) {
      alert(`Ошибка удаления файла: ${e}`);
    }
  };
};

export default ReportsAndExpertise;
