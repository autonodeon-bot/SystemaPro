import { useMemo, useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ChevronRight } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { API_BASE } from '../constants';
import ReportCard from '../components/reports/ReportCard';
import ReportTableRow from '../components/reports/ReportTableRow';
import ReportFilters from '../components/reports/ReportFilters';
import ReportUploadModal from '../components/reports/ReportUploadModal';
import ReportsList from '../components/reports/ReportsList';
import { getGroupKey } from '../components/reports/reportUtils';
import type {
  Branch,
  DocumentFile,
  Enterprise,
  Questionnaire,
  Report,
  UnifiedListItem,
  Workshop,
} from '../components/reports/types';

const ReportsAndExpertise = () => {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [reports, setReports] = useState<Report[]>([]);
  const [questionnaires, setQuestionnaires] = useState<Questionnaire[]>([]);
  const [_equipment, setEquipment] = useState<unknown[]>([]);
  const [_clients, setClients] = useState<unknown[]>([]);
  const [enterprises, setEnterprises] = useState<Enterprise[]>([]);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [workshops, setWorkshops] = useState<Workshop[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterType, setFilterType] = useState<string>('all');
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [selectedEnterpriseId, setSelectedEnterpriseId] = useState<string>('');
  const [selectedBranchId, setSelectedBranchId] = useState<string>('');
  const [selectedWorkshopId, setSelectedWorkshopId] = useState<string>('');
  const [selectedQuestionnaire, setSelectedQuestionnaire] = useState<Questionnaire | null>(null);
  const [documentFiles, setDocumentFiles] = useState<Record<string, DocumentFile[]>>({});
  const [uploadingFile, setUploadingFile] = useState<string | null>(null);
  const [cleanupReportsDays, setCleanupReportsDays] = useState<number>(180);
  const [showMineOnly, setShowMineOnly] = useState<boolean>(false);
  const [selectedReports, setSelectedReports] = useState<Set<string>>(new Set());
  const [isProcessing, setIsProcessing] = useState<boolean>(false);
  const [groupBy, setGroupBy] = useState<string>('none');
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set());
  const [listLayout, setListLayout] = useState<'cards' | 'table'>('cards');

  const loadEnterprises = async () => {
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = {};
      if (token) headers['Authorization'] = `Bearer ${token}`;
      const res = await fetch(`${API_BASE}/api/hierarchy/enterprises`, { headers });
      const data = await res.json().catch(() => ({}));
      setEnterprises(data.items || data || []);
    } catch (e) {
      console.error('Ошибка загрузки предприятий:', e);
    }
  };

  const loadBranches = async (enterpriseId: string) => {
    if (!enterpriseId) {
      setBranches([]);
      return;
    }
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = {};
      if (token) headers['Authorization'] = `Bearer ${token}`;
      const res = await fetch(
        `${API_BASE}/api/hierarchy/branches?enterprise_id=${encodeURIComponent(enterpriseId)}`,
        { headers }
      );
      const data = await res.json().catch(() => ({}));
      setBranches(data.items || data || []);
    } catch (e) {
      console.error('Ошибка загрузки филиалов:', e);
    }
  };

  const loadWorkshops = async (branchId: string) => {
    if (!branchId) {
      setWorkshops([]);
      return;
    }
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = {};
      if (token) headers['Authorization'] = `Bearer ${token}`;
      const res = await fetch(
        `${API_BASE}/api/hierarchy/workshops?branch_id=${encodeURIComponent(branchId)}`,
        { headers }
      );
      const data = await res.json().catch(() => ({}));
      setWorkshops(data.items || data || []);
    } catch (e) {
      console.error('Ошибка загрузки цехов:', e);
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
        fetch(`${API_BASE}/api/questionnaires`, { headers }).catch(() => null),
      ]);

      const reportsData = await reportsRes.json();
      const equipmentData = await equipmentRes.json();
      const clientsData = await clientsRes.json();

      let reportsList = reportsData.items || [];

      let questionnairesList: Questionnaire[] = [];
      if (questionnairesRes && questionnairesRes.ok) {
        try {
          const questionnairesData = await questionnairesRes.json();
          questionnairesList = questionnairesData.items || [];

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

            try {
              const filesRes = await fetch(`${API_BASE}/api/questionnaires/${q.id}/documents`, { headers });
              if (filesRes.ok) {
                const filesData = await filesRes.json();
                setDocumentFiles((prev) => ({
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

      const equipmentMap = new Map((equipmentData.items || []).map((eq: { id: string }) => [eq.id, eq]));

      reportsList = reportsList.map((r: Report) => {
        const eq = equipmentMap.get(r.equipment_id) as { name?: string; location?: string } | undefined;
        return {
          ...r,
          equipment_name: eq?.name || r.equipment_name || 'Неизвестное оборудование',
          equipment_location: eq?.location || r.equipment_location || 'Не указано',
        };
      });

      questionnairesList = questionnairesList.map((q: Questionnaire) => {
        const eq = equipmentMap.get(q.equipment_id) as { name?: string; location?: string } | undefined;
        return {
          ...q,
          equipment_name: eq?.name || q.equipment_name || 'Неизвестное оборудование',
          equipment_location: eq?.location || 'Не указано',
        };
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

  useEffect(() => {
    void loadEnterprises();
    void loadData();
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
    const confirm = window.confirm(
      `Удалить ${selectedReports.size} выбранных отчетов? Файлы будут удалены без возможности восстановления.`
    );
    if (!confirm) return;

    setIsProcessing(true);
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/reports/bulk-delete`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ report_ids: Array.from(selectedReports) }),
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
            errorMessage = text || errorMessage;
          }
        } catch {
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
        errorMessage = (e as { message?: string; detail?: string }).message || (e as { detail?: string }).detail || String(e);
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
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ report_ids: Array.from(selectedReports), archive: true }),
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
      const errorMessage =
        e instanceof Error ? e.message : typeof e === 'string' ? e : JSON.stringify(e);
      alert(`Ошибка архивирования: ${errorMessage}`);
    } finally {
      setIsProcessing(false);
    }
  };

  const cleanupOldReports = async () => {
    const confirm = window.confirm(
      `Удалить отчеты старше ${cleanupReportsDays} дней? Файлы будут удалены без возможности восстановления.`
    );
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
      const data = await res.json().catch(() => null as { deleted?: number } | null);
      alert(`Удалено отчетов: ${data?.deleted ?? 'OK'}`);
      await loadData();
    } catch (e) {
      alert(`Ошибка очистки: ${e instanceof Error ? e.message : String(e)}`);
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
        headers,
      });

      if (response.ok) {
        await loadData();
        window.open(`${API_BASE}/api/questionnaires/${questionnaireId}/download`, '_blank');
      } else {
        alert('Ошибка генерации PDF');
      }
    } catch (error) {
      console.error('Ошибка генерации PDF:', error);
      alert('Ошибка генерации PDF');
    }
  };

  const generateQuestionnaireWord = async (questionnaireId: string) => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/questionnaires/${questionnaireId}/generate-word`, {
        method: 'POST',
        headers,
      });
      if (response.ok) {
        await loadData();
        window.open(`${API_BASE}/api/questionnaires/${questionnaireId}/download-word`, '_blank');
      } else {
        alert('Ошибка генерации Word');
      }
    } catch (error) {
      console.error('Ошибка генерации Word:', error);
      alert('Ошибка генерации Word');
    }
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
        const filesRes = await fetch(`${API_BASE}/api/questionnaires/${questionnaireId}/documents`, { headers });
        if (filesRes.ok) {
          const filesData = await filesRes.json();
          setDocumentFiles((prev) => ({
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
        const filesRes = await fetch(`${API_BASE}/api/questionnaires/${questionnaireId}/documents`, { headers });
        if (filesRes.ok) {
          const filesData = await filesRes.json();
          setDocumentFiles((prev) => ({
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

  const allItems: UnifiedListItem[] = [
    ...reports.map((r) => ({ ...r, itemType: 'report' as const })),
    ...questionnaires.map((q) => ({
      ...q,
      itemType: 'questionnaire' as const,
      report_type: 'QUESTIONNAIRE',
      title: `Опросный лист: ${q.equipment_name || 'Неизвестное оборудование'}`,
      status: 'DRAFT',
      equipment_location: q.equipment_location || 'Не указано',
    })),
  ];

  const filteredItems = allItems.filter((item) => {
    const matchesSearch =
      !searchTerm ||
      item.title?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      item.equipment_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      item.equipment_location?.toLowerCase().includes(searchTerm.toLowerCase());

    const matchesType =
      filterType === 'all' ||
      (filterType === 'questionnaire' && item.itemType === 'questionnaire') ||
      (filterType !== 'questionnaire' && item.itemType === 'report' && item.report_type === filterType);

    const matchesStatus = filterStatus === 'all' || item.status === filterStatus;

    let matchesMine = true;
    if (showMineOnly && user) {
      const createdBy = item.created_by;
      const inspectorName = item.inspector_name;
      const fullName = user.full_name || user.username;
      matchesMine =
        Boolean((createdBy && createdBy === user.id) || (inspectorName && fullName && inspectorName === fullName));
    }

    const matchesEnterprise = !selectedEnterpriseId || item.enterprise_id === selectedEnterpriseId;
    const matchesBranch = !selectedBranchId || item.branch_id === selectedBranchId;
    const matchesWorkshop = !selectedWorkshopId || item.workshop_id === selectedWorkshopId;

    return (
      matchesSearch &&
      matchesType &&
      matchesStatus &&
      matchesMine &&
      matchesEnterprise &&
      matchesBranch &&
      matchesWorkshop
    );
  });

  const groupedItems = useMemo(() => {
    if (groupBy === 'none') {
      return { all: filteredItems };
    }

    const groups: Record<string, UnifiedListItem[]> = {};
    filteredItems.forEach((item) => {
      const key = getGroupKey(item, groupBy);
      if (key) {
        if (!groups[key]) {
          groups[key] = [];
        }
        groups[key].push(item);
      }
    });

    return groups;
  }, [filteredItems, groupBy]);

  const handleGroupByChange = (value: string) => {
    setGroupBy(value);
    if (value !== 'none') {
      const allGroupKeys = new Set<string>();
      filteredItems.forEach((item) => {
        const key = getGroupKey(item, value);
        if (key) allGroupKeys.add(key);
      });
      setExpandedGroups(allGroupKeys);
    } else {
      setExpandedGroups(new Set());
    }
  };

  const handleToggleSelectAll = () => {
    if (selectedReports.size === filteredItems.length && filteredItems.length > 0) {
      setSelectedReports(new Set());
    } else {
      setSelectedReports(new Set(filteredItems.map((item) => item.id)));
    }
  };

  const handleToggleReportSelect = (id: string, checked: boolean) => {
    setSelectedReports((prev) => {
      const next = new Set(prev);
      if (checked) {
        next.add(id);
      } else {
        next.delete(id);
      }
      return next;
    });
  };

  const handleEnterpriseChange = (v: string) => {
    setSelectedEnterpriseId(v);
    setSelectedBranchId('');
    setSelectedWorkshopId('');
    setBranches([]);
    setWorkshops([]);
    if (v) void loadBranches(v);
  };

  const handleBranchChange = (v: string) => {
    setSelectedBranchId(v);
    setSelectedWorkshopId('');
    setWorkshops([]);
    if (v) void loadWorkshops(v);
  };

  if (loading) {
    return (
      <div className="p-6">
        <div className="sp-surface flex flex-col items-center justify-center py-16">
          <div className="animate-spin rounded-full h-8 w-8 border-2 border-transparent" style={{ borderTopColor: 'var(--accent)', borderRightColor: 'var(--accent)' }}></div>
          <p className="mt-4 text-sm" style={{ color: 'var(--text-muted)' }}>Загрузка...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-4 sm:p-6 sp-animate-in">
      <nav className="flex items-center gap-2 text-xs mb-3 flex-wrap" style={{ color: 'var(--text-muted)' }}>
        <span className="font-medium" style={{ color: 'var(--text-primary)' }}>Отчёты и экспертизы</span>
        {selectedEnterpriseId && enterprises.find((e) => e.id === selectedEnterpriseId) && (
          <>
            <ChevronRight size={14} />
            <span style={{ color: 'var(--text-secondary)' }}>
              {enterprises.find((e) => e.id === selectedEnterpriseId)?.name}
            </span>
          </>
        )}
        {selectedBranchId && branches.find((b) => b.id === selectedBranchId) && (
          <>
            <ChevronRight size={14} />
            <span style={{ color: 'var(--text-secondary)' }}>{branches.find((b) => b.id === selectedBranchId)?.name}</span>
          </>
        )}
        {selectedWorkshopId && workshops.find((w) => w.id === selectedWorkshopId) && (
          <>
            <ChevronRight size={14} />
            <span style={{ color: 'var(--text-secondary)' }}>{workshops.find((w) => w.id === selectedWorkshopId)?.name}</span>
          </>
        )}
      </nav>

      <div className="mb-5">
        <h1 className="text-2xl sm:text-3xl font-bold mb-1" style={{ color: 'var(--text-primary)', letterSpacing: '-0.02em' }}>
          Отчёты и экспертизы
        </h1>
        <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
          Управление техническими отчётами, экспертизами и опросными листами по предприятиям, филиалам и цехам
        </p>
      </div>

      <ReportFilters
        selectedReports={selectedReports}
        filteredItemsCount={filteredItems.length}
        onToggleSelectAll={handleToggleSelectAll}
        onClearSelection={() => setSelectedReports(new Set())}
        onBulkArchive={handleBulkArchiveReports}
        onBulkDelete={handleBulkDeleteReports}
        isProcessing={isProcessing}
        searchTerm={searchTerm}
        onSearchTermChange={setSearchTerm}
        filterType={filterType}
        onFilterTypeChange={setFilterType}
        filterStatus={filterStatus}
        onFilterStatusChange={setFilterStatus}
        showMineOnly={showMineOnly}
        onShowMineOnlyChange={setShowMineOnly}
        showMineOnlyVisible={user?.role === 'engineer'}
        enterprises={enterprises}
        branches={branches}
        workshops={workshops}
        selectedEnterpriseId={selectedEnterpriseId}
        selectedBranchId={selectedBranchId}
        selectedWorkshopId={selectedWorkshopId}
        onEnterpriseChange={handleEnterpriseChange}
        onBranchChange={handleBranchChange}
        onWorkshopChange={setSelectedWorkshopId}
        groupBy={groupBy}
        onGroupByChange={handleGroupByChange}
        listLayout={listLayout}
        onListLayoutChange={setListLayout}
        cleanupReportsDays={cleanupReportsDays}
        onCleanupReportsDaysChange={setCleanupReportsDays}
        onCleanupOldReports={cleanupOldReports}
      />

      <ReportsList
        groupedItems={groupedItems}
        filteredItems={filteredItems}
        groupBy={groupBy}
        expandedGroups={expandedGroups}
        onExpandedGroupsChange={setExpandedGroups}
        searchTerm={searchTerm}
        filterType={filterType}
        filterStatus={filterStatus}
        layout={listLayout}
        renderTableRow={(item) => (
          <ReportTableRow
            item={item}
            selected={selectedReports.has(item.id)}
            onToggleSelect={handleToggleReportSelect}
            documentFiles={documentFiles[item.id]}
            canApprove={canApprove}
            onNavigateReportViewer={(inspectionId) => navigate(`/report-viewer/${inspectionId}`)}
            onApproveReport={approveReport}
            onDeleteReport={deleteReport}
            onGenerateQuestionnairePdf={generateQuestionnairePDF}
            onGenerateQuestionnaireWord={generateQuestionnaireWord}
            onOpenFileManager={setSelectedQuestionnaire}
          />
        )}
        renderItem={(item) => (
          <ReportCard
            item={item}
            selected={selectedReports.has(item.id)}
            onToggleSelect={handleToggleReportSelect}
            documentFiles={documentFiles[item.id]}
            canApprove={canApprove}
            onNavigateReportViewer={(inspectionId) => navigate(`/report-viewer/${inspectionId}`)}
            onApproveReport={approveReport}
            onDeleteReport={deleteReport}
            onGenerateQuestionnairePdf={generateQuestionnairePDF}
            onGenerateQuestionnaireWord={generateQuestionnaireWord}
            onOpenFileManager={setSelectedQuestionnaire}
          />
        )}
      />

      {selectedQuestionnaire && (
        <ReportUploadModal
          questionnaire={selectedQuestionnaire}
          documentFiles={documentFiles[selectedQuestionnaire.id]}
          uploadingFile={uploadingFile}
          onClose={() => setSelectedQuestionnaire(null)}
          onUpload={handleFileUpload}
          onDelete={handleDeleteFile}
        />
      )}
    </div>
  );
};

export default ReportsAndExpertise;
