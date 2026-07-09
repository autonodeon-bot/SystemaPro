import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Smartphone } from 'lucide-react';
import { API_BASE } from '../constants';
import ReportGenerationToolbar from '../components/report-generation/ReportGenerationToolbar';
import GroupedReportList from '../components/report-generation/GroupedReportList';
import ReportPreviewModal from '../components/report-generation/ReportPreviewModal';
import type {
  Inspection,
  Equipment,
  Report,
  PreviewData,
  GroupedItem,
  ReportValidationResult,
} from '../components/report-generation/types';

const REPORT_FILTERS_STORAGE_KEY = 'report_generation_filters_v1';

interface StandaloneProtocolRow {
  id: string;
  title?: string | null;
  kind?: string | null;
  template_name?: string | null;
  created_by?: string | null;
  created_at?: string | null;
}

const standaloneKindRu = (kind?: string | null) => {
  switch (kind) {
    case 'ndk_protocol':
      return 'Протокол НК';
    case 'quick_control':
      return 'Быстрый контроль ВИК/УЗТ';
    case 'custom_template':
      return 'Шаблон (конструктор)';
    default:
      return kind && kind.length > 0 ? kind : 'Протокол';
  }
};

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
  const [standaloneProtocols, setStandaloneProtocols] = useState<StandaloneProtocolRow[]>([]);

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

      const [inspRes, eqRes, repRes, standaloneRes] = await Promise.all([
        fetch(`${API_BASE}/api/inspections`, { headers }),
        fetch(`${API_BASE}/api/equipment`, { headers }),
        fetch(`${API_BASE}/api/reports`, { headers }),
        fetch(`${API_BASE}/api/standalone-protocols`, { headers }),
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
      const standaloneData = await standaloneRes.json().catch(() => ({}));

      let filteredInspections = toItems(inspRes, inspData) as Inspection[];
      let filteredReports = toItems(repRes, repData) as Report[];
      const equipmentList = toItems(eqRes, eqData);

      if (!showArchived) {
        filteredInspections = filteredInspections.filter((i: Inspection) => !i.is_archived);
        filteredReports = filteredReports.filter((r: Report) => !r.is_archived);
      }

      setInspections(filteredInspections);
      setEquipment(equipmentList as Equipment[]);
      setReports(filteredReports);

      let standaloneList: StandaloneProtocolRow[] = [];
      if (standaloneRes.ok && standaloneData && typeof standaloneData === 'object') {
        const raw = (standaloneData as { items?: unknown }).items;
        if (Array.isArray(raw)) {
          standaloneList = raw.filter(
            (x): x is StandaloneProtocolRow =>
              !!x &&
              typeof x === 'object' &&
              typeof (x as StandaloneProtocolRow).id === 'string',
          ) as StandaloneProtocolRow[];
        }
      }
      setStandaloneProtocols(standaloneList);
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
    setExpandedGroups((prev) => ({
      ...prev,
      [key]: !prev[key],
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

  const validateReportData = async (
    inspectionId: string,
  ): Promise<{ is_complete: boolean; missing_fields: string[]; warnings: string[] }> => {
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

  const generateReport = async (
    inspectionId: string,
    reportType: string,
    format: string = 'pdf',
    skipValidation: boolean = false,
  ) => {
    // Проверка полноты данных перед генерацией
    if (!skipValidation) {
      const validation = await validateReportData(inspectionId);
      if (!validation.is_complete) {
        const missingText =
          validation.missing_fields.length > 0
            ? `\nОтсутствуют обязательные поля:\n${validation.missing_fields.map((f) => `• ${f}`).join('\n')}`
            : '';
        const warningsText =
          validation.warnings.length > 0
            ? `\nПредупреждения:\n${validation.warnings.map((w) => `• ${w}`).join('\n')}`
            : '';

        const shouldContinue = window.confirm(
          `Данные обследования неполные.${missingText}${warningsText}\n\nПродолжить генерацию отчета?`,
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
          }`,
        }),
      });

      if (response.ok) {
        const data = await response.json();
        const reportInfo = data.report_number
          ? `\nНомер отчета: ${data.report_number}\nРегистрационный номер: ${data.registration_number}`
          : '';
        alert(`Отчет успешно сгенерирован в формате ${format.toUpperCase()}!${reportInfo}`);
        await loadData();
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
          archive: archive,
        }),
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
        headers,
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
          archive: archive,
        }),
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
    const confirmDelete = window.confirm('Удалить отчет? Файл будет удален без возможности восстановления.');
    if (!confirmDelete) return;
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
      void generateReport(previewData.inspection.id, previewType, format);
    }
  };

  const handleGenerateDirectly = async (inspectionId: string, reportType: string, format: string = 'pdf') => {
    await generateReport(inspectionId, reportType, format);
  };

  const handleDownloadStandaloneProtocol = async (protocolId: string, titleFallback: string) => {
    try {
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const response = await fetch(`${API_BASE}/api/standalone-protocols/${protocolId}/download`, { headers });
      if (!response.ok) {
        const err = await response.json().catch(() => ({ detail: response.statusText }));
        alert(`Ошибка: ${typeof err.detail === 'string' ? err.detail : 'Не удалось скачать протокол'}`);
        return;
      }
      const blob = await response.blob();
      const objectUrl = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = objectUrl;
      const safe = (titleFallback || 'protocol').replace(/[^\w\s\-]+/g, '').trim().slice(0, 80);
      a.download = `${safe || 'protocol'}.docx`;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(objectUrl);
      document.body.removeChild(a);
    } catch (error) {
      console.error('standalone protocol download', error);
      alert(`Ошибка скачивания: ${error instanceof Error ? error.message : String(error)}`);
    }
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

  const handleExportPreviewExcel = async () => {
    if (!previewData?.inspection?.id) return;
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;
      const response = await fetch(
        `${API_BASE}/api/reports/export/${previewData.inspection.id}?format=excel`,
        { headers },
      );
      if (response.ok) {
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `report_${previewData.inspection.id}.xlsx`;
        a.click();
        window.URL.revokeObjectURL(url);
      }
    } catch {
      alert('Экспорт в Excel пока не реализован');
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
    const eq = equipment.find((e) => e.id === equipmentId);
    return eq?.name || 'Неизвестное оборудование';
  };

  const getInspectionReports = (inspectionId: string) => {
    const forInsp = reports.filter((r) => r.inspection_id === inspectionId);
    return {
      technical: forInsp.find((r) => r.report_type === 'TECHNICAL_REPORT'),
      expertise: forInsp.find((r) => r.report_type === 'EXPERTISE'),
    };
  };

  const getGroupDisplayName = (group: GroupedItem): string => {
    const parts: string[] = [];
    if (group.enterprise_name) parts.push(group.enterprise_name);
    if (group.branch_name) parts.push(group.branch_name);
    if (group.workshop_name) parts.push(group.workshop_name);
    return parts.length > 0 ? parts.join(' → ') : 'Без привязки';
  };

  const filteredInspections = inspections.filter((ins) => {
    const eqName = getEquipmentName(ins.equipment_id);
    const matchesSearch =
      eqName.toLowerCase().includes(searchTerm.toLowerCase()) ||
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

  if (loading) {
    return <div className="text-center text-app-text3 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-4 md:space-y-6">
      <ReportGenerationToolbar
        navigate={navigate}
        showArchived={showArchived}
        onShowArchivedChange={setShowArchived}
        filterReportType={filterReportType}
        onFilterReportTypeChange={setFilterReportType}
        filterStatus={filterStatus}
        onFilterStatusChange={setFilterStatus}
        filterDateFrom={filterDateFrom}
        onFilterDateFromChange={setFilterDateFrom}
        filterDateTo={filterDateTo}
        onFilterDateToChange={setFilterDateTo}
        searchTerm={searchTerm}
        onSearchTermChange={setSearchTerm}
        onResetFilters={resetFilters}
      />

      <div className="rounded-xl border border-app-border bg-app-surface-alt/40 p-4 md:p-5">
        <div className="flex flex-wrap items-center gap-2 mb-2">
          <Smartphone className="h-5 w-5 text-teal-500 shrink-0" aria-hidden />
          <h2 className="text-base md:text-lg font-semibold text-app-text tracking-tight">
            Протоколы только с телефона
          </h2>
        </div>
        <p className="text-sm text-app-text3 mb-4 max-w-3xl">
          Записи без привязки к чек-листу в вебе: быстрый контроль, протокол НК и протоколы по вашему шаблону из мобильного приложения. Доступен один файл DOCX — полный отчёт по обследованию не требуется.
        </p>
        {standaloneProtocols.length === 0 ? (
          <p className="text-sm text-app-text3">Пока нет сохранённых протоколов с мобильного приложения.</p>
        ) : (
          <ul className="divide-y divide-app-border rounded-lg border border-app-border overflow-hidden bg-app-surface">
            {standaloneProtocols.map((row) => {
              const t = row.title?.trim() || 'Без названия';
              return (
                <li
                  key={row.id}
                  className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between px-4 py-3 hover:bg-white/5"
                >
                  <div className="min-w-0">
                    <p className="text-app-text font-medium truncate" title={t}>
                      {t}
                    </p>
                    <p className="text-xs text-app-text3 mt-0.5">
                      {standaloneKindRu(row.kind)}
                      {row.template_name ? ` — ${row.template_name}` : ''}
                      {' · '}
                      {formatDateRu(row.created_at)}
                      {row.created_by ? ` · ${row.created_by}` : ''}
                    </p>
                  </div>
                  <button
                    type="button"
                    className="shrink-0 rounded-lg bg-teal-600 hover:bg-teal-500 text-white text-sm font-medium px-4 py-2 transition-colors"
                    onClick={() => void handleDownloadStandaloneProtocol(row.id, t)}
                  >
                    Скачать DOCX
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <GroupedReportList
        groupedItems={groupedItems}
        expandedGroups={expandedGroups}
        onToggleGroup={toggleGroup}
        getGroupDisplayName={getGroupDisplayName}
        formatDateRu={formatDateRu}
        getEquipmentName={getEquipmentName}
        getInspectionReports={getInspectionReports}
        loadingPreview={loadingPreview}
        generatingId={generating}
        onLoadPreview={loadPreview}
        onGenerateDirectly={handleGenerateDirectly}
        onDownloadReport={handleDownloadReport}
        onPreviewReport={handlePreviewReport}
        onArchiveInspection={archiveInspection}
        onDeleteInspection={deleteInspection}
        onArchiveReport={archiveReport}
        onDeleteReport={deleteReport}
        showArchived={showArchived}
      />

      {previewData && (
        <ReportPreviewModal
          previewData={previewData}
          previewType={previewType}
          validationResult={validationResult}
          validatingPreview={validatingPreview}
          generatingId={generating}
          onClose={() => setPreviewData(null)}
          formatDateRu={formatDateRu}
          onRefreshValidation={refreshPreviewValidation}
          navigate={navigate}
          onGenerateFromPreview={handleGenerateFromPreview}
          onExportExcel={handleExportPreviewExcel}
          hasTechnicalReport={Boolean(
            getInspectionReports(previewData.inspection.id).technical,
          )}
        />
      )}
    </div>
  );
};

export default ReportGeneration;
