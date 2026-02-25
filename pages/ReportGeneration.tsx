import React, { useState, useEffect } from 'react';
import { FileText, FileCode, Download, FileCheck, Sparkles, Search, Eye, X, CheckCircle, AlertCircle, Trash2, Archive, ArchiveRestore, ChevronDown, ChevronRight, Building2, Factory } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { API_BASE } from '../constants';

interface Inspection {
  id: string;
  equipment_id: string;
  date_performed?: string;
  status: string;
  conclusion?: string;
  enterprise_id?: string;
  enterprise_name?: string;
  branch_id?: string;
  branch_name?: string;
  workshop_id?: string;
  workshop_name?: string;
  is_archived?: boolean;
}

interface Equipment {
  id: string;
  name: string;
  serial_number?: string;
  location?: string;
}

interface Report {
  id: string;
  inspection_id: string;
  equipment_id: string;
  equipment_name?: string;
  report_type: string;
  title: string;
  file_path: string;
  word_file_path?: string | null;
  status: string;
  created_at: string;
  enterprise_id?: string;
  enterprise_name?: string;
  branch_id?: string;
  branch_name?: string;
  workshop_id?: string;
  workshop_name?: string;
  is_archived?: boolean;
}

interface PreviewData {
  inspection: {
    id: string;
    date_performed?: string;
    status: string;
    conclusion?: string;
    data?: any;
  };
  equipment: {
    id: string;
    name: string;
    serial_number?: string;
    location?: string;
    commissioning_date?: string;
    attributes?: any;
  };
  questionnaire?: {
    id?: string | null;
  };
  document_files?: Array<{
    document_number: string;
    file_name?: string;
    file_size?: number;
    file_type?: string;
    mime_type?: string;
  }>;
  opo?: {
    id?: string;
    name?: string;
    code?: string;
    description?: string;
    enterprise_name?: string;
    branch_name?: string;
    workshop_name?: string;
    survey_data?: any;
  };
  ndt_methods: Array<{
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
  }>;
  resource?: {
    remaining_resource_years?: number;
    resource_end_date?: string;
    extension_years?: number;
    extension_date?: string;
  };
}

interface GroupedItem {
  key: string;
  enterprise_name?: string;
  branch_name?: string;
  workshop_name?: string;
  inspections: Inspection[];
  reports: Report[];
}

interface ReportValidationResult {
  is_complete: boolean;
  missing_fields: string[];
  warnings: string[];
  can_generate?: boolean;
}

const REPORT_FILTERS_STORAGE_KEY = 'report_generation_filters_v1';

const ReportGeneration = () => {
  const navigate = useNavigate();
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [previewData, setPreviewData] = useState<PreviewData | null>(null);
  const [previewType, setPreviewType] = useState<string>('');
  const [loadingPreview, setLoadingPreview] = useState(false);
  const [validationResult, setValidationResult] = useState<ReportValidationResult | null>(null);
  const [validatingPreview, setValidatingPreview] = useState(false);
  const [expandedGroups, setExpandedGroups] = useState<Record<string, boolean>>({});
  const [showArchived, setShowArchived] = useState(false);
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterReportType, setFilterReportType] = useState<string>('all');
  const [filterDateFrom, setFilterDateFrom] = useState<string>('');
  const [filterDateTo, setFilterDateTo] = useState<string>('');

  const formatDateRu = (value?: string | null) => {
    if (!value) return '—';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '—';
    return new Intl.DateTimeFormat('ru-RU').format(date);
  };

  useEffect(() => {
    loadData();
  }, [showArchived]);

  const loadData = async () => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const [inspRes, eqRes, repRes] = await Promise.all([
        fetch(`${API_BASE}/api/inspections`, { headers }),
        fetch(`${API_BASE}/api/equipment`, { headers }),
        fetch(`${API_BASE}/api/reports`, { headers })
      ]);
      
      const toItems = (res: Response, data: unknown): unknown[] => {
        if (!res.ok) return [];
        if (Array.isArray(data)) return data;
        if (data && typeof data === 'object' && 'items' in data && Array.isArray((data as { items: unknown[] }).items))
          return (data as { items: unknown[] }).items;
        return [];
      };
      const inspData = await inspRes.json().catch(() => ({}));
      const eqData = await eqRes.json().catch(() => ({}));
      const repData = await repRes.json().catch(() => ({}));
      
      let filteredInspections = toItems(inspRes, inspData) as Inspection[];
      let filteredReports = toItems(repRes, repData) as Report[];
      const equipmentList = toItems(eqRes, eqData);
      
      if (!showArchived) {
        filteredInspections = filteredInspections.filter((i: Inspection) => !i.is_archived);
        filteredReports = filteredReports.filter((r: Report) => !r.is_archived);
      }
      
      setInspections(filteredInspections);
      setEquipment(equipmentList);
      setReports(filteredReports);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    try {
      const raw = localStorage.getItem(REPORT_FILTERS_STORAGE_KEY);
      if (!raw) return;
      const saved = JSON.parse(raw) as {
        searchTerm?: string;
        filterStatus?: string;
        filterReportType?: string;
        filterDateFrom?: string;
        filterDateTo?: string;
        showArchived?: boolean;
      };
      if (typeof saved.searchTerm === 'string') setSearchTerm(saved.searchTerm);
      if (typeof saved.filterStatus === 'string') setFilterStatus(saved.filterStatus);
      if (typeof saved.filterReportType === 'string') setFilterReportType(saved.filterReportType);
      if (typeof saved.filterDateFrom === 'string') setFilterDateFrom(saved.filterDateFrom);
      if (typeof saved.filterDateTo === 'string') setFilterDateTo(saved.filterDateTo);
      if (typeof saved.showArchived === 'boolean') setShowArchived(saved.showArchived);
    } catch {
      // ignore malformed storage
    }
  }, []);

  useEffect(() => {
    localStorage.setItem(
      REPORT_FILTERS_STORAGE_KEY,
      JSON.stringify({
        searchTerm,
        filterStatus,
        filterReportType,
        filterDateFrom,
        filterDateTo,
        showArchived,
      }),
    );
  }, [searchTerm, filterStatus, filterReportType, filterDateFrom, filterDateTo, showArchived]);

  const groupItems = (inspectionsSource: Inspection[], reportsSource: Report[]): GroupedItem[] => {
    const groupsMap = new Map<string, GroupedItem>();
    
    // Группируем инспекции
    inspectionsSource.forEach((inspection) => {
      const key = `${inspection.enterprise_id || 'no-enterprise'}_${inspection.branch_id || 'no-branch'}_${inspection.workshop_id || 'no-workshop'}`;
      if (!groupsMap.has(key)) {
        groupsMap.set(key, {
          key,
          enterprise_name: inspection.enterprise_name,
          branch_name: inspection.branch_name,
          workshop_name: inspection.workshop_name,
          inspections: [],
          reports: [],
        });
      }
      groupsMap.get(key)!.inspections.push(inspection);
    });
    
    // Группируем отчеты
    reportsSource.forEach((report) => {
      const key = `${report.enterprise_id || 'no-enterprise'}_${report.branch_id || 'no-branch'}_${report.workshop_id || 'no-workshop'}`;
      if (!groupsMap.has(key)) {
        groupsMap.set(key, {
          key,
          enterprise_name: report.enterprise_name,
          branch_name: report.branch_name,
          workshop_name: report.workshop_name,
          inspections: [],
          reports: [],
        });
      }
      groupsMap.get(key)!.reports.push(report);
    });
    
    return Array.from(groupsMap.values()).sort((a, b) => {
      const aName = a.enterprise_name || a.branch_name || a.workshop_name || '';
      const bName = b.enterprise_name || b.branch_name || b.workshop_name || '';
      return aName.localeCompare(bName);
    });
  };

  const toggleGroup = (key: string) => {
    setExpandedGroups(prev => ({
      ...prev,
      [key]: !prev[key]
    }));
  };

  const loadPreview = async (inspectionId: string, reportType: string) => {
    setLoadingPreview(true);
    setValidationResult(null);
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const [previewResponse, validationResponse] = await Promise.all([
        fetch(`${API_BASE}/api/inspections/${inspectionId}/preview`, { headers }),
        fetch(`${API_BASE}/api/reports/validate/${inspectionId}`, { headers }),
      ]);

      if (previewResponse.ok) {
        const data = await previewResponse.json();
        setPreviewData(data);
        setPreviewType(reportType);
      } else {
        const errorData = await previewResponse.json().catch(() => ({ detail: 'Неизвестная ошибка' }));
        alert(`Ошибка загрузки данных для предпросмотра: ${errorData.detail || previewResponse.statusText}`);
      }

      if (validationResponse.ok) {
        const validationData = await validationResponse.json();
        setValidationResult(validationData);
      }
    } catch (error) {
      console.error('Ошибка загрузки предпросмотра:', error);
      alert(`Ошибка загрузки предпросмотра: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
    } finally {
      setLoadingPreview(false);
    }
  };

  const validateReportData = async (inspectionId: string): Promise<{is_complete: boolean, missing_fields: string[], warnings: string[]}> => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const response = await fetch(`${API_BASE}/api/reports/validate/${inspectionId}`, { headers });
      if (response.ok) {
        return await response.json();
      }
      const errData = await response.json().catch(() => ({}));
      const detail = errData.detail || `Сервер вернул ${response.status}`;
      return { is_complete: false, missing_fields: [detail], warnings: [] };
    } catch (error) {
      const msg = error instanceof Error ? error.message : 'Нет связи с сервером';
      return { is_complete: false, missing_fields: [msg], warnings: [] };
    }
  };

  const refreshPreviewValidation = async (inspectionId: string) => {
    try {
      setValidatingPreview(true);
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/reports/validate/${inspectionId}`, { headers });
      if (response.ok) {
        const data = await response.json();
        setValidationResult(data);
      }
    } finally {
      setValidatingPreview(false);
    }
  };

  const generateReport = async (inspectionId: string, reportType: string, format: string = 'pdf', skipValidation: boolean = false) => {
    // Проверка полноты данных перед генерацией
    if (!skipValidation) {
      const validation = await validateReportData(inspectionId);
      if (!validation.is_complete) {
        const missingText = validation.missing_fields.length > 0 
          ? `\nОтсутствуют обязательные поля:\n${validation.missing_fields.map(f => `• ${f}`).join('\n')}`
          : '';
        const warningsText = validation.warnings.length > 0
          ? `\nПредупреждения:\n${validation.warnings.map(w => `• ${w}`).join('\n')}`
          : '';
        
        const shouldContinue = window.confirm(
          `Данные обследования неполные.${missingText}${warningsText}\n\nПродолжить генерацию отчета?`
        );
        if (!shouldContinue) {
          return;
        }
      }
    }

    setGenerating(inspectionId);
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const response = await fetch(`${API_BASE}/api/reports/generate`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          inspection_id: inspectionId,
          report_type: reportType,
          format: format,
          skip_validation: skipValidation,
          title: `${
            reportType === 'DIAGNOSTICS'
              ? 'Диагностический отчет'
              : reportType === 'TECHNICAL_REPORT'
                ? 'Технический отчет'
                : 'Экспертиза ПБ'
          }`
        })
      });

      if (response.ok) {
        const data = await response.json();
        const reportInfo = data.report_number ? `\nНомер отчета: ${data.report_number}\nРегистрационный номер: ${data.registration_number}` : '';
        alert(`Отчет успешно сгенерирован в формате ${format.toUpperCase()}!${reportInfo}`);
        await loadData(); // Обновляем данные после генерации
        setPreviewData(null);
      } else {
        const error = await response.json().catch(() => ({ detail: 'Неизвестная ошибка' }));
        alert(`Ошибка: ${error.detail || 'Не удалось сгенерировать отчет'}`);
      }
    } catch (error) {
      console.error('Ошибка генерации отчета:', error);
      alert(`Ошибка генерации отчета: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
    } finally {
      setGenerating(null);
    }
  };

  const archiveInspection = async (inspectionId: string, archive: boolean) => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const response = await fetch(`${API_BASE}/api/inspections/bulk-archive`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          inspection_ids: [inspectionId],
          archive: archive
        })
      });
      
      if (response.ok) {
        await loadData();
        alert(archive ? 'Чек-лист перемещен в архив' : 'Чек-лист восстановлен из архива');
      } else {
        const error = await response.json().catch(() => ({ detail: 'Ошибка' }));
        alert(`Ошибка: ${error.detail || 'Не удалось архивировать'}`);
      }
    } catch (error) {
      alert(`Ошибка: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
    }
  };

  const deleteInspection = async (inspectionId: string) => {
    if (!window.confirm('Удалить чек-лист? Это действие нельзя отменить.')) {
      return;
    }
    
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const response = await fetch(`${API_BASE}/api/inspections/${inspectionId}`, {
        method: 'DELETE',
        headers
      });
      
      if (response.ok) {
        await loadData();
        alert('Чек-лист удален');
      } else {
        const error = await response.json().catch(() => ({ detail: 'Ошибка' }));
        alert(`Ошибка: ${error.detail || 'Не удалось удалить'}`);
      }
    } catch (error) {
      alert(`Ошибка: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
    }
  };

  const archiveReport = async (reportId: string, archive: boolean) => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const response = await fetch(`${API_BASE}/api/reports/bulk-archive`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          report_ids: [reportId],
          archive: archive
        })
      });
      
      if (response.ok) {
        await loadData();
        alert(archive ? 'Отчет перемещен в архив' : 'Отчет восстановлен из архива');
      } else {
        const error = await response.json().catch(() => ({ detail: 'Ошибка' }));
        alert(`Ошибка: ${error.detail || 'Не удалось архивировать'}`);
      }
    } catch (error) {
      alert(`Ошибка: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
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

  const handleGenerateFromPreview = (format: string = 'pdf') => {
    if (previewData) {
      generateReport(previewData.inspection.id, previewType, format);
    }
  };

  const handleGenerateDirectly = async (inspectionId: string, reportType: string, format: string = 'pdf') => {
    await generateReport(inspectionId, reportType, format);
  };

  const handleDownloadReport = async (reportId: string, format: 'pdf' | 'docx' = 'pdf') => {
    try {
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const url = `${API_BASE}/api/reports/${reportId}/download${format === 'docx' ? '?format=docx' : ''}`;
      const response = await fetch(url, { headers });
      if (response.ok) {
        const blob = await response.blob();
        const objectUrl = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = objectUrl;
        const ct = response.headers.get('content-type') || '';
        const ext = ct.includes('wordprocessingml') ? '.docx' : '.pdf';
        a.download = `report${ext}`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(objectUrl);
        document.body.removeChild(a);
      }
    } catch (error) {
      console.error('Ошибка скачивания отчета:', error);
      alert('Ошибка скачивания отчета');
    }
  };

  const handlePreviewReport = async (reportId: string, format: 'pdf' | 'docx' = 'pdf') => {
    try {
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const url = `${API_BASE}/api/reports/${reportId}/download${format === 'docx' ? '?format=docx' : ''}`;
      const response = await fetch(url, { headers });
      if (!response.ok) {
        alert('Не удалось открыть предпросмотр отчета');
        return;
      }
      const blob = await response.blob();
      const objectUrl = window.URL.createObjectURL(blob);
      window.open(objectUrl, '_blank', 'noopener,noreferrer');
      setTimeout(() => window.URL.revokeObjectURL(objectUrl), 60_000);
    } catch (error) {
      console.error('Ошибка предпросмотра отчета:', error);
      alert('Ошибка открытия предпросмотра отчета');
    }
  };

  const resetFilters = () => {
    setSearchTerm('');
    setFilterStatus('all');
    setFilterReportType('all');
    setFilterDateFrom('');
    setFilterDateTo('');
  };

  const getEquipmentName = (equipmentId: string) => {
    const eq = equipment.find(e => e.id === equipmentId);
    return eq?.name || 'Неизвестное оборудование';
  };

  const getInspectionReport = (inspectionId: string) => {
    return reports.find(r => r.inspection_id === inspectionId);
  };

  const getGroupDisplayName = (group: GroupedItem): string => {
    const parts: string[] = [];
    if (group.enterprise_name) parts.push(group.enterprise_name);
    if (group.branch_name) parts.push(group.branch_name);
    if (group.workshop_name) parts.push(group.workshop_name);
    return parts.length > 0 ? parts.join(' → ') : 'Без привязки';
  };

  const filteredInspections = inspections.filter(ins => {
    const eqName = getEquipmentName(ins.equipment_id);
    const matchesSearch = eqName.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         (ins.enterprise_name && ins.enterprise_name.toLowerCase().includes(searchTerm.toLowerCase())) ||
                         (ins.workshop_name && ins.workshop_name.toLowerCase().includes(searchTerm.toLowerCase()));
    
    if (!matchesSearch) return false;
    
    if (filterStatus !== 'all' && ins.status !== filterStatus) return false;
    
    if (filterDateFrom) {
      const insDate = ins.date_performed ? new Date(ins.date_performed) : null;
      if (!insDate || insDate < new Date(filterDateFrom)) return false;
    }
    
    if (filterDateTo) {
      const insDate = ins.date_performed ? new Date(ins.date_performed) : null;
      if (!insDate || insDate > new Date(filterDateTo)) return false;
    }
    
    return true;
  });

  const filteredReports = reports.filter((rep) => {
    if (filterReportType === 'all') return true;
    return rep.report_type === filterReportType;
  });

  const groupedItems = groupItems(filteredInspections, filteredReports);

  const previewDocs = previewData?.document_files ?? [];
  const questionnaireId = previewData?.questionnaire?.id;
  const buildDocUrl = (docNumber: string) => {
    if (!questionnaireId) return null;
    return `${API_BASE}/api/questionnaires/${encodeURIComponent(questionnaireId)}/documents/${encodeURIComponent(docNumber)}/view`;
  };
  const isImageDoc = (mime?: string) => (mime || '').toLowerCase().startsWith('image/');
  const isPdfDoc = (mime?: string) => (mime || '').toLowerCase().includes('pdf');

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-4 md:space-y-6">
      <div className="flex flex-col md:flex-row md:justify-between md:items-center gap-4">
        <div className="flex items-center gap-3">
          <h1 className="text-xl md:text-2xl font-bold text-white">Генерация отчетов и экспертиз</h1>
          <button
            onClick={() => navigate('/report-templates')}
            className="px-3 py-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-white text-xs md:text-sm font-bold"
            title="Перейти в редактор макетов отчетов"
          >
            Редактор отчетов
          </button>
        </div>
        <div className="flex flex-col md:flex-row items-start md:items-center gap-4">
          <label className="flex items-center gap-2 text-sm text-slate-300 cursor-pointer">
            <input
              type="checkbox"
              checked={showArchived}
              onChange={(e) => setShowArchived(e.target.checked)}
              className="w-4 h-4 rounded border-slate-600 bg-slate-700 text-accent focus:ring-accent"
            />
            <span>Показать архивные</span>
          </label>
          
          {/* Расширенные фильтры */}
          <div className="flex flex-wrap gap-2">
            <select
              value={filterReportType}
              onChange={(e) => setFilterReportType(e.target.value)}
              className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white text-sm"
            >
              <option value="all">Все типы отчетов</option>
              <option value="DIAGNOSTICS">Диагностические</option>
              <option value="TECHNICAL_REPORT">Технические</option>
              <option value="EXPERTISE">Экспертиза ПБ</option>
            </select>

            <select
              value={filterStatus}
              onChange={(e) => setFilterStatus(e.target.value)}
              className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white text-sm"
            >
              <option value="all">Все статусы</option>
              <option value="DRAFT">Черновик</option>
              <option value="SIGNED">Подписан</option>
              <option value="APPROVED">Утверждён</option>
              <option value="SUBMITTED">Отправлен</option>
              <option value="COMPLETED">Завершен</option>
            </select>
            
            <input
              type="date"
              value={filterDateFrom}
              onChange={(e) => setFilterDateFrom(e.target.value)}
              placeholder="Дата от"
              className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white text-sm"
            />
            
            <input
              type="date"
              value={filterDateTo}
              onChange={(e) => setFilterDateTo(e.target.value)}
              placeholder="Дата до"
              className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white text-sm"
            />
            <button
              type="button"
              onClick={resetFilters}
              className="px-3 py-2 bg-slate-700 hover:bg-slate-600 border border-slate-600 rounded-lg text-white text-sm"
            >
              Сбросить фильтры
            </button>
          </div>
          
          <div className="relative w-full md:w-64">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
            <input
              type="text"
              placeholder="Поиск по оборудованию..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full bg-slate-800 border border-slate-700 rounded-lg pl-10 pr-4 py-2 text-white placeholder-slate-500 text-sm md:text-base"
            />
          </div>
        </div>
      </div>

      {/* Группированный список */}
      <div className="space-y-2">
        {groupedItems.map((group) => {
          const isExpanded = expandedGroups[group.key] ?? true;
          const totalItems = group.inspections.length + group.reports.length;
          
          return (
            <div key={group.key} className="sp-card-soft rounded-xl">
              {/* Заголовок группы */}
              <button
                onClick={() => toggleGroup(group.key)}
                className="w-full p-4 flex items-center justify-between hover:bg-slate-700/50 transition-colors rounded-t-xl"
              >
                <div className="flex items-center gap-3">
                  {isExpanded ? (
                    <ChevronDown className="text-slate-400" size={20} />
                  ) : (
                    <ChevronRight className="text-slate-400" size={20} />
                  )}
                  {group.enterprise_name && <Building2 className="text-slate-400" size={18} />}
                  {group.workshop_name && <Factory className="text-slate-400" size={18} />}
                  <span className="text-white font-bold">{getGroupDisplayName(group)}</span>
                  <span className="text-sm text-slate-400">
                    ({totalItems} {totalItems === 1 ? 'элемент' : totalItems < 5 ? 'элемента' : 'элементов'})
                  </span>
                </div>
              </button>
              
              {/* Содержимое группы */}
              {isExpanded && (
                <div className="p-4 space-y-4 border-t border-slate-700">
                  {/* Чек-листы */}
                  {group.inspections.length > 0 && (
                    <div>
                      <h3 className="text-sm font-bold text-slate-400 mb-2">Чек-листы ({group.inspections.length})</h3>
                      <div className="space-y-3">
                        {group.inspections.map((inspection) => {
                          const existingReport = getInspectionReport(inspection.id);
                          const eqName = getEquipmentName(inspection.equipment_id);
                          
                          return (
                            <div
                              key={inspection.id}
                              className="sp-card"
                            >
                              <div className="flex justify-between items-start mb-4">
                                <div className="flex-1">
                                  <h3 className="text-lg font-bold text-white mb-1">{eqName}</h3>
                                  <p className="text-sm text-slate-400">
                                    {inspection.date_performed 
                                      ? formatDateRu(inspection.date_performed)
                                      : 'Дата не указана'}
                                    {' • '}
                                    Статус: {inspection.status}
                                  </p>
                                </div>
                                <div className="flex items-center gap-2">
                                  {existingReport && (
                                    <span className="text-xs text-green-400 bg-green-500/10 px-2 py-1 rounded border border-green-500/20">
                                      Отчет создан
                                    </span>
                                  )}
                                  <button
                                    onClick={() => archiveInspection(inspection.id, !inspection.is_archived)}
                                    className="p-2 text-slate-400 hover:text-yellow-400 hover:bg-slate-800 rounded"
                                    title={inspection.is_archived ? 'Восстановить из архива' : 'Переместить в архив'}
                                  >
                                    {inspection.is_archived ? <ArchiveRestore size={16} /> : <Archive size={16} />}
                                  </button>
                                  <button
                                    onClick={() => deleteInspection(inspection.id)}
                                    className="p-2 text-slate-400 hover:text-red-400 hover:bg-slate-800 rounded"
                                    title="Удалить"
                                  >
                                    <Trash2 size={16} />
                                  </button>
                                </div>
                              </div>

                              {inspection.conclusion && (
                                <p className="text-sm text-slate-300 mb-4 line-clamp-2">{inspection.conclusion}</p>
                              )}

                              <div className="flex flex-col sm:flex-row gap-2 flex-wrap">
                                <button
                                  onClick={() => loadPreview(inspection.id, 'TECHNICAL_REPORT')}
                                  disabled={loadingPreview || generating === inspection.id}
                                  className="bg-purple-500/10 text-purple-400 border border-purple-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-purple-500/20 disabled:opacity-50"
                                >
                                  <Eye size={14} className="md:w-4 md:h-4" />
                                  <span className="hidden sm:inline">Предпросмотр технического отчета</span>
                                  <span className="sm:hidden">Предпросмотр (PDF)</span>
                                </button>
                                <button
                                  onClick={() => loadPreview(inspection.id, 'EXPERTISE')}
                                  disabled={loadingPreview || generating === inspection.id}
                                  className="bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-indigo-500/20 disabled:opacity-50"
                                >
                                  <Eye size={14} className="md:w-4 md:h-4" />
                                  <span className="hidden sm:inline">Предпросмотр экспертизы ПБ</span>
                                  <span className="sm:hidden">Предпросмотр (ЭПБ)</span>
                                </button>
                                <button
                                  onClick={() => handleGenerateDirectly(inspection.id, 'DIAGNOSTICS', 'docx')}
                                  disabled={generating === inspection.id}
                                  className="bg-amber-500/10 text-amber-300 border border-amber-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-amber-500/20 disabled:opacity-50"
                                >
                                  <FileText size={14} className="md:w-4 md:h-4" />
                                  <span className="hidden sm:inline">Диагностический отчет (DOCX)</span>
                                  <span className="sm:hidden">Диагн. DOCX</span>
                                </button>
                                <button
                                  onClick={() => handleGenerateDirectly(inspection.id, 'TECHNICAL_REPORT', 'pdf')}
                                  disabled={generating === inspection.id}
                                  className="bg-blue-500/10 text-blue-400 border border-blue-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-blue-500/20 disabled:opacity-50"
                                >
                                  <FileText size={14} className="md:w-4 md:h-4" />
                                  <span className="hidden sm:inline">Сгенерировать новый отчет (PDF)</span>
                                  <span className="sm:hidden">PDF</span>
                                </button>
                                <button
                                  onClick={() => handleGenerateDirectly(inspection.id, 'TECHNICAL_REPORT', 'docx')}
                                  disabled={generating === inspection.id}
                                  className="bg-green-500/10 text-green-400 border border-green-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-green-500/20 disabled:opacity-50"
                                >
                                  <FileText size={14} className="md:w-4 md:h-4" />
                                  <span className="hidden sm:inline">Сгенерировать новый отчет (DOCX)</span>
                                  <span className="sm:hidden">DOCX</span>
                                </button>
                                {existingReport && (
                                  <button
                                    onClick={() => handleDownloadReport(existingReport.id, 'pdf')}
                                    className="bg-green-500/10 text-green-400 border border-green-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-green-500/20"
                                  >
                                    <Download size={14} className="md:w-4 md:h-4" />
                                    <span className="hidden sm:inline">Скачать {existingReport.report_type === 'TECHNICAL_REPORT' ? 'отчет' : 'экспертизу'}</span>
                                    <span className="sm:hidden">Скачать</span>
                                  </button>
                                )}
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  )}
                  
                  {/* Отчеты */}
                  {group.reports.length > 0 && (
                    <div>
                      <h3 className="text-sm font-bold text-slate-400 mb-2">Отчеты ({group.reports.length})</h3>
                      <div className="space-y-2">
                        {group.reports.map((report) => (
                          <div
                            key={report.id}
                            className="bg-slate-900 p-3 rounded-lg border border-slate-700 flex justify-between items-center"
                          >
                            <div className="flex-1">
                              <p className="text-white font-bold">{report.title}</p>
                              {report.equipment_name && (
                                <p className="text-sm text-slate-400">Оборудование: {report.equipment_name}</p>
                              )}
                              <p className="text-sm text-slate-400">
                                {report.report_type === 'TECHNICAL_REPORT' ? 'Технический отчет' : 
                                 report.report_type === 'EXPERTISE' ? 'Экспертиза ПБ' : 'Отчет'}
                                {' • '}
                                {formatDateRu(report.created_at)}
                                {' • '}
                                Статус: {report.status}
                              </p>
                            </div>
                            <div className="flex items-center gap-2">
                              {report.file_path && (
                                <button
                                  onClick={() => handlePreviewReport(report.id, 'pdf')}
                                  className="bg-slate-500/10 text-slate-200 border border-slate-500/30 px-3 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-slate-500/20"
                                  title="Открыть PDF в браузере"
                                >
                                  <Eye size={16} />
                                  Просмотр
                                </button>
                              )}
                              {report.file_path && (
                                <button
                                  onClick={() => handleDownloadReport(report.id, 'pdf')}
                                  className="bg-red-500/10 text-red-400 border border-red-500/30 px-3 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-red-500/20"
                                  title="Скачать PDF"
                                >
                                  <FileText size={16} />
                                  PDF
                                </button>
                              )}
                              {report.word_file_path && (
                                <button
                                  onClick={() => handlePreviewReport(report.id, 'docx')}
                                  className="bg-slate-500/10 text-slate-200 border border-slate-500/30 px-3 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-slate-500/20"
                                  title="Открыть DOCX в браузере"
                                >
                                  <Eye size={16} />
                                  DOCX
                                </button>
                              )}
                              {report.word_file_path && (
                                <button
                                  onClick={() => handleDownloadReport(report.id, 'docx')}
                                  className="bg-blue-500/10 text-blue-400 border border-blue-500/30 px-3 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-blue-500/20"
                                  title="Скачать DOCX"
                                >
                                  <FileCode size={16} />
                                  DOCX
                                </button>
                              )}
                              {!report.file_path && !report.word_file_path && (
                                <span className="text-slate-500 text-sm">Файл не сгенерирован</span>
                              )}
                              <button
                                onClick={() => archiveReport(report.id, !report.is_archived)}
                                className="p-2 text-slate-400 hover:text-yellow-400 hover:bg-slate-800 rounded"
                                title={report.is_archived ? 'Восстановить из архива' : 'Переместить в архив'}
                              >
                                {report.is_archived ? <ArchiveRestore size={16} /> : <Archive size={16} />}
                              </button>
                              <button
                                onClick={() => deleteReport(report.id)}
                                className="p-2 text-slate-400 hover:text-red-400 hover:bg-slate-800 rounded"
                                title="Удалить"
                              >
                                <Trash2 size={16} />
                              </button>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {groupedItems.length === 0 && (
        <div className="text-center text-slate-400 py-20">
          {showArchived ? 'Архивные элементы не найдены' : 'Диагностики не найдены'}
        </div>
      )}

      {/* Модальное окно предпросмотра */}
      {previewData && (
        <div className="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-2 md:p-4">
          <div className="sp-card-soft rounded-xl w-full max-w-4xl max-h-[95vh] md:max-h-[90vh] overflow-hidden flex flex-col">
            <div className="flex items-center justify-between p-6 border-b border-slate-700">
              <h2 className="text-xl font-bold text-white">
                Предпросмотр {previewType === 'TECHNICAL_REPORT' ? 'технического отчета' : 'экспертизы ПБ'}
              </h2>
              <button
                onClick={() => setPreviewData(null)}
                className="text-slate-400 hover:text-white"
              >
                <X size={24} />
              </button>
            </div>
            
            <div className="flex-1 overflow-y-auto p-4 md:p-6 space-y-4 md:space-y-6">
              {/* Оборудование */}
              <div className="bg-slate-900 p-3 md:p-4 rounded-lg">
                <h3 className="sp-section-title text-base md:text-lg mb-3 flex items-center gap-2">
                  <CheckCircle size={18} className="md:w-5 md:h-5 text-green-400" />
                  Оборудование
                </h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
                  <div>
                    <span className="text-slate-400">Название:</span>
                    <p className="text-white font-bold">{previewData.equipment.name}</p>
                  </div>
                  {previewData.equipment.serial_number && (
                    <div>
                      <span className="text-slate-400">Серийный номер:</span>
                      <p className="text-white">{previewData.equipment.serial_number}</p>
                    </div>
                  )}
                  {previewData.equipment.location && (
                    <div>
                      <span className="text-slate-400">Местоположение:</span>
                      <p className="text-white">{previewData.equipment.location}</p>
                    </div>
                  )}
                  {previewData.equipment.commissioning_date && (
                    <div>
                      <span className="text-slate-400">Дата ввода в эксплуатацию:</span>
                        <p className="text-white">{formatDateRu(previewData.equipment.commissioning_date)}</p>
                    </div>
                  )}
                </div>
              </div>

              {/* Инспекция */}
              <div className="sp-card">
                <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
                  <CheckCircle size={20} className="text-green-400" />
                  Данные диагностики
                </h3>
                <div className="space-y-2 text-sm">
                  {previewData.inspection.date_performed && (
                    <div>
                      <span className="text-slate-400">Дата проведения:</span>
                      <p className="text-white">{formatDateRu(previewData.inspection.date_performed)}</p>
                    </div>
                  )}
                  <div>
                    <span className="text-slate-400">Статус:</span>
                    <p className="text-white">{previewData.inspection.status}</p>
                  </div>
                  {previewData.inspection.conclusion && (
                    <div>
                      <span className="text-slate-400">Заключение:</span>
                      <p className="text-white">{previewData.inspection.conclusion}</p>
                    </div>
                  )}
                </div>
              </div>

              {/* Проверка полноты перед генерацией */}
              {validationResult && (
                <div className="sp-card">
                  <div className="flex items-center justify-between mb-3">
                    <h3 className="text-lg font-bold text-white">Проверка полноты</h3>
                    <span
                      className={`px-2 py-1 rounded text-xs font-semibold ${
                        validationResult.is_complete
                          ? 'bg-green-500/20 text-green-300'
                          : 'bg-yellow-500/20 text-yellow-300'
                      }`}
                    >
                      {validationResult.is_complete ? 'Готово к генерации' : 'Требуется заполнение'}
                    </span>
                  </div>
                  {validationResult.missing_fields.length > 0 && (
                    <div className="mb-3">
                      <p className="text-red-300 text-sm mb-1">Обязательные поля:</p>
                      <ul className="text-sm text-red-200 space-y-1">
                        {validationResult.missing_fields.map((item, idx) => (
                          <li key={`missing-${idx}`}>• {item}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                  {validationResult.warnings.length > 0 && (
                    <div>
                      <p className="text-amber-300 text-sm mb-1">Предупреждения:</p>
                      <ul className="text-sm text-amber-200 space-y-1">
                        {validationResult.warnings.map((item, idx) => (
                          <li key={`warning-${idx}`}>• {item}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                  {validationResult.missing_fields.length === 0 &&
                    validationResult.warnings.length === 0 && (
                      <p className="text-sm text-green-300">Критичных замечаний не найдено.</p>
                    )}
                </div>
              )}

              {/* ОПО */}
              {previewData.opo && (
                <div className="sp-card">
                  <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
                    <Factory size={20} className="text-blue-400" />
                    Сведения об ОПО
                  </h3>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
                    {previewData.opo.name && (
                      <div>
                        <span className="text-slate-400">Наименование:</span>
                        <p className="text-white">{previewData.opo.name}</p>
                      </div>
                    )}
                    {previewData.opo.code && (
                      <div>
                        <span className="text-slate-400">Код:</span>
                        <p className="text-white">{previewData.opo.code}</p>
                      </div>
                    )}
                    {previewData.opo.enterprise_name && (
                      <div>
                        <span className="text-slate-400">Предприятие:</span>
                        <p className="text-white">{previewData.opo.enterprise_name}</p>
                      </div>
                    )}
                    {previewData.opo.branch_name && (
                      <div>
                        <span className="text-slate-400">Филиал:</span>
                        <p className="text-white">{previewData.opo.branch_name}</p>
                      </div>
                    )}
                    {previewData.opo.workshop_name && (
                      <div>
                        <span className="text-slate-400">Цех:</span>
                        <p className="text-white">{previewData.opo.workshop_name}</p>
                      </div>
                    )}
                    {previewData.opo.description && (
                      <div className="sm:col-span-2">
                        <span className="text-slate-400">Описание:</span>
                        <p className="text-white">{previewData.opo.description}</p>
                      </div>
                    )}
                    {previewData.opo.survey_data?.organization && (
                      <div>
                        <span className="text-slate-400">Организация (опросный лист):</span>
                        <p className="text-white">{previewData.opo.survey_data.organization}</p>
                      </div>
                    )}
                    {previewData.opo.survey_data?.executors && (
                      <div>
                        <span className="text-slate-400">Исполнители (опросный лист):</span>
                        <p className="text-white">{previewData.opo.survey_data.executors}</p>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Вложения/фото/чертежи */}
              {previewDocs.length > 0 && (
                <div className="sp-card">
                  <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
                    <FileText size={20} className="text-purple-400" />
                    Фото, чертежи и документы ({previewDocs.length})
                  </h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {previewDocs.map((doc, idx) => {
                      const docUrl = buildDocUrl(String(doc.document_number));
                      const label = doc.file_name || doc.document_number;
                      if (isImageDoc(doc.mime_type)) {
                        return (
                          <div key={`${doc.document_number}-${idx}`} className="sp-card-soft p-3">
                            <p className="text-xs text-slate-400 mb-2">{label}</p>
                            {docUrl ? (
                              <a href={docUrl} target="_blank" rel="noreferrer">
                                <img
                                  src={docUrl}
                                  alt={label}
                                  className="w-full max-h-64 object-contain rounded bg-slate-950"
                                />
                              </a>
                            ) : (
                              <div className="text-slate-500 text-sm">Ссылка недоступна</div>
                            )}
                          </div>
                        );
                      }
                      return (
                        <div key={`${doc.document_number}-${idx}`} className="sp-card-soft p-3 flex items-center justify-between">
                          <div>
                            <p className="text-white text-sm">{label}</p>
                            {doc.mime_type && (
                              <p className="text-xs text-slate-500">{doc.mime_type}</p>
                            )}
                          </div>
                          {docUrl && (
                            <a
                              href={docUrl}
                              target="_blank"
                              rel="noreferrer"
                              className="text-xs text-accent hover:text-accent-light"
                            >
                              {isPdfDoc(doc.mime_type) ? 'Открыть PDF' : 'Открыть файл'}
                            </a>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Методы НК */}
              <div className="sp-card">
                <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
                  {previewData.ndt_methods.length > 0 ? (
                    <CheckCircle size={20} className="text-green-400" />
                  ) : (
                    <AlertCircle size={20} className="text-yellow-400" />
                  )}
                  Методы неразрушающего контроля ({previewData.ndt_methods.length})
                </h3>
                {previewData.ndt_methods.length > 0 ? (
                  <div className="space-y-3">
                    {previewData.ndt_methods.map((method, idx) => (
                      <div key={idx} className="sp-card-soft p-3">
                        <div className="flex items-center gap-2 mb-2">
                          <span className={`px-2 py-1 rounded text-xs ${method.is_performed ? 'bg-green-500/20 text-green-400' : 'bg-slate-700 text-slate-400'}`}>
                            {method.is_performed ? 'Выполнен' : 'Не выполнен'}
                          </span>
                          <span className="text-white font-bold">{method.method_name}</span>
                          {method.method_code && (
                            <span className="text-slate-400 text-xs">({method.method_code})</span>
                          )}
                        </div>
                        {method.inspector_name && (
                          <p className="text-sm text-slate-300">Инженер: {method.inspector_name}</p>
                        )}
                        {method.results && (
                          <p className="text-sm text-slate-300 mt-1">Результаты: {method.results}</p>
                        )}
                        {method.defects && (
                          <p className="text-sm text-red-300 mt-1">Дефекты: {method.defects}</p>
                        )}
                        {method.conclusion && (
                          <p className="text-sm text-slate-300 mt-1">Заключение: {method.conclusion}</p>
                        )}
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="text-slate-400 text-sm">Методы НК не указаны</p>
                )}
              </div>

              {/* Ресурс (только для экспертизы) */}
              {previewType === 'EXPERTISE' && previewData.resource && (
                <div className="sp-card">
                  <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
                    <CheckCircle size={20} className="text-green-400" />
                    Данные ресурса
                  </h3>
                  <div className="grid grid-cols-2 gap-3 text-sm">
                    {previewData.resource.remaining_resource_years !== null && (
                      <div>
                        <span className="text-slate-400">Остаточный ресурс (лет):</span>
                        <p className="text-white">{previewData.resource.remaining_resource_years}</p>
                      </div>
                    )}
                    {previewData.resource.resource_end_date && (
                      <div>
                        <span className="text-slate-400">Дата окончания ресурса:</span>
                        <p className="text-white">{formatDateRu(previewData.resource.resource_end_date)}</p>
                      </div>
                    )}
                    {previewData.resource.extension_years !== null && (
                      <div>
                        <span className="text-slate-400">Продление (лет):</span>
                        <p className="text-white">{previewData.resource.extension_years}</p>
                      </div>
                    )}
                    {previewData.resource.extension_date && (
                      <div>
                        <span className="text-slate-400">Дата продления:</span>
                        <p className="text-white">{formatDateRu(previewData.resource.extension_date)}</p>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>

            <div className="flex flex-col sm:flex-row justify-end gap-2 md:gap-3 p-4 md:p-6 border-t border-slate-700">
              <button
                onClick={() => setPreviewData(null)}
                className="px-3 md:px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg text-sm md:text-base"
              >
                Отмена
              </button>
              <button
                onClick={async () => {
                  if (previewData?.inspection?.id) {
                    await refreshPreviewValidation(previewData.inspection.id);
                  }
                }}
                disabled={validatingPreview}
                className="px-3 md:px-4 py-2 bg-yellow-600 hover:bg-yellow-700 text-white rounded-lg text-sm md:text-base"
              >
                {validatingPreview ? 'Проверка...' : 'Проверить полноту'}
              </button>
              <button
                onClick={() => {
                  const id = previewData?.inspection?.id;
                  if (id) {
                    setPreviewData(null);
                    navigate(`/report-viewer/${id}`);
                  }
                }}
                className="px-3 md:px-4 py-2 bg-slate-800 hover:bg-slate-700 text-white rounded-lg text-sm md:text-base"
              >
                Полный просмотр
              </button>
              <div className="flex flex-wrap gap-2">
                <button
                  onClick={() => handleGenerateFromPreview('pdf')}
                  disabled={generating === previewData.inspection.id}
                  className="px-3 md:px-4 py-2 bg-accent hover:bg-blue-600 text-white rounded-lg font-bold flex items-center justify-center gap-2 disabled:opacity-50 text-sm md:text-base"
                >
                  {generating === previewData.inspection.id ? (
                    <>
                      <Sparkles size={14} className="md:w-4 md:h-4 animate-spin" />
                      <span>Генерация...</span>
                    </>
                  ) : (
                    <>
                      <FileText size={14} className="md:w-4 md:h-4" />
                      <span className="hidden sm:inline">PDF</span>
                      <span className="sm:hidden">PDF</span>
                    </>
                  )}
                </button>
                <button
                  onClick={() => handleGenerateFromPreview('docx')}
                  disabled={generating === previewData.inspection.id}
                  className="px-3 md:px-4 py-2 bg-green-500/10 text-green-400 border border-green-500/20 hover:bg-green-500/20 rounded-lg font-bold flex items-center justify-center gap-2 disabled:opacity-50 text-sm md:text-base"
                >
                {generating === previewData.inspection.id ? (
                  <>
                    <Sparkles size={14} className="md:w-4 md:h-4 animate-spin" />
                    <span>Генерация...</span>
                  </>
                ) : (
                  <>
                    <FileText size={14} className="md:w-4 md:h-4" />
                    <span className="hidden sm:inline">Сгенерировать Word (DOCX)</span>
                    <span className="sm:hidden">Word</span>
                  </>
                )}
              </button>
              <button
                onClick={async () => {
                  try {
                    const headers: HeadersInit = { 'Content-Type': 'application/json' };
                    const token = localStorage.getItem('token');
                    if (token) headers['Authorization'] = `Bearer ${token}`;
                    const response = await fetch(`${API_BASE}/api/reports/export/${previewData.inspection.id}?format=excel`, { headers });
                    if (response.ok) {
                      const blob = await response.blob();
                      const url = window.URL.createObjectURL(blob);
                      const a = document.createElement('a');
                      a.href = url;
                      a.download = `report_${previewData.inspection.id}.xlsx`;
                      a.click();
                      window.URL.revokeObjectURL(url);
                    }
                  } catch (e) {
                    alert('Экспорт в Excel пока не реализован');
                  }
                }}
                className="px-3 md:px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg font-bold flex items-center justify-center gap-2 text-sm md:text-base"
              >
                <FileText size={14} className="md:w-4 md:h-4" />
                <span className="hidden sm:inline">Excel</span>
                <span className="sm:hidden">XLSX</span>
              </button>
            </div>
          </div>
        </div>
        </div>
      )}
    </div>
  );
};

export default ReportGeneration;
