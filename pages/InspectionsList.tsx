import { useEffect, useMemo, useState } from 'react';
import { FileText, ChevronRight } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { API_BASE } from '../constants';
import type {
  Branch,
  Enterprise,
  Equipment,
  Inspection,
  InspectionQuestionnaireInfo,
  Workshop,
} from '../components/inspections/types';
import InspectionsFiltersBar, { type InspectionsGroupBy } from '../components/inspections/InspectionsFiltersBar';
import InspectionsListView from '../components/inspections/InspectionsListView';
import InspectionDetailModal from '../components/inspections/InspectionDetailModal';

const InspectionsList = () => {
  const { user } = useAuth();
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [enterprises, setEnterprises] = useState<Enterprise[]>([]);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [workshops, setWorkshops] = useState<Workshop[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedEquipment, setSelectedEquipment] = useState<string>('all');
  const [selectedStatus, setSelectedStatus] = useState<string>('all');
  const [selectedInspectionType, setSelectedInspectionType] = useState<string>('all');
  const [selectedEnterpriseId, setSelectedEnterpriseId] = useState<string>('');
  const [selectedBranchId, setSelectedBranchId] = useState<string>('');
  const [selectedWorkshopId, setSelectedWorkshopId] = useState<string>('');
  const [groupBy, setGroupBy] = useState<InspectionsGroupBy>('none');
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set());
  const [selectedInspection, setSelectedInspection] = useState<Inspection | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [questionnaireInfo, setQuestionnaireInfo] = useState<Record<string, InspectionQuestionnaireInfo>>({});
  const [loadingQuestionnaire, setLoadingQuestionnaire] = useState(false);
  const [cleanupInspectionsDays, setCleanupInspectionsDays] = useState<number>(180);
  const [selectedInspections, setSelectedInspections] = useState<Set<string>>(new Set());
  const [isProcessing, setIsProcessing] = useState(false);

  useEffect(() => {
    const init = async () => {
      try {
        const saved = localStorage.getItem('inspections_filters_v1');
        if (saved) {
          const parsed = JSON.parse(saved);
          if (parsed.selectedEquipment) setSelectedEquipment(parsed.selectedEquipment);
          if (parsed.selectedStatus) setSelectedStatus(parsed.selectedStatus);
          if (parsed.selectedInspectionType) setSelectedInspectionType(parsed.selectedInspectionType);
          if (parsed.groupBy) setGroupBy(parsed.groupBy);
        }
      } catch (_) {
        // ignore bad local storage payload
      }
      await loadEnterprises();
      await loadEquipment();
      await loadInspections();
    };
    init();
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem(
        'inspections_filters_v1',
        JSON.stringify({
          selectedEquipment,
          selectedStatus,
          selectedInspectionType,
          groupBy,
        }),
      );
    } catch (_) {
      // ignore
    }
  }, [selectedEquipment, selectedStatus, selectedInspectionType, groupBy]);

  useEffect(() => {
    loadInspections();
  }, [selectedEquipment, selectedStatus, selectedInspectionType, selectedEnterpriseId, selectedBranchId, selectedWorkshopId]);

  useEffect(() => {
    if (selectedEnterpriseId) {
      loadBranches(selectedEnterpriseId);
    } else {
      setBranches([]);
      setSelectedBranchId('');
    }
    setSelectedWorkshopId('');
    setWorkshops([]);
  }, [selectedEnterpriseId]);

  useEffect(() => {
    if (selectedBranchId) {
      loadWorkshops(selectedBranchId);
    } else {
      setWorkshops([]);
    }
    setSelectedWorkshopId('');
  }, [selectedBranchId]);

  const loadEnterprises = async () => {
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/hierarchy/enterprises`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
      const data = await res.json();
      setEnterprises(data.items || data || []);
    } catch (e) {
      console.error('Ошибка загрузки предприятий:', e);
    }
  };

  const loadBranches = async (enterpriseId: string) => {
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/hierarchy/branches?enterprise_id=${enterpriseId}`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
      const data = await res.json();
      setBranches(data.items || data || []);
    } catch (e) {
      console.error('Ошибка загрузки филиалов:', e);
    }
  };

  const loadWorkshops = async (branchId: string) => {
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/hierarchy/workshops?branch_id=${branchId}`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
      const data = await res.json();
      setWorkshops(data.items || data || []);
    } catch (e) {
      console.error('Ошибка загрузки цехов:', e);
    }
  };

  const loadEquipment = async () => {
    try {
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const response = await fetch(`${API_BASE}/api/equipment`, { headers });
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
      } else if (selectedWorkshopId) {
        url += `&workshop_id=${selectedWorkshopId}`;
      } else if (selectedBranchId) {
        url += `&branch_id=${selectedBranchId}`;
      } else if (selectedEnterpriseId) {
        url += `&enterprise_id=${selectedEnterpriseId}`;
      }
      if (selectedInspectionType !== 'all') {
        url += `&inspection_type=${encodeURIComponent(selectedInspectionType)}`;
      }

      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const response = await fetch(url, { headers });
      const data = await response.json();
      let inspectionsList: Inspection[] = data.items || [];

      if (selectedStatus !== 'all') {
        inspectionsList = inspectionsList.filter((insp) => insp.status === selectedStatus);
      }

      for (const insp of inspectionsList) {
        if (!insp.equipment_name || !insp.equipment_location) {
          const eq = equipment.find((e) => e.id === insp.equipment_id);
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

  const canApprove = useMemo(() => {
    const role = (user?.role || '').toLowerCase();
    return ['admin', 'chief_operator', 'operator'].includes(role);
  }, [user]);

  const approveInspection = async (inspectionId: string) => {
    const confirm = window.confirm('Утвердить чек-лист? Действие изменит статус на APPROVED.');
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
      await loadInspections();
      if (selectedInspection?.id === inspectionId) {
        setSelectedInspection((prev) => (prev ? { ...prev, status: 'APPROVED' } : prev));
      }
    } catch (e) {
      alert(`Ошибка утверждения: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const deleteInspection = async (inspectionId: string) => {
    const confirm = window.confirm('Удалить чек-лист? Также будут удалены связанные отчеты и файлы. Действие необратимо.');
    if (!confirm) return;
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const res = await fetch(`${API_BASE}/api/inspections/${inspectionId}`, {
        method: 'DELETE',
        headers,
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }));
        alert(`Ошибка удаления: ${err.detail || res.statusText}`);
        return;
      }
      await loadInspections();
      if (selectedInspection?.id === inspectionId) {
        setShowDetails(false);
        setSelectedInspection(null);
      }
    } catch (e) {
      alert(`Ошибка удаления: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const handleBulkDelete = async () => {
    if (selectedInspections.size === 0) {
      alert('Выберите чек-листы для удаления');
      return;
    }
    const confirm = window.confirm(`Удалить ${selectedInspections.size} выбранных чек-листов? Также будут удалены связанные отчеты и файлы. Действие необратимо.`);
    if (!confirm) return;

    setIsProcessing(true);
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/inspections/bulk-delete`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ inspection_ids: Array.from(selectedInspections) }),
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
        console.error('Ошибка удаления чек-листов:', errorMessage);
        alert(`Ошибка удаления: ${errorMessage}`);
        return;
      }

      const data = await response.json();
      alert(`Удалено: ${data.deleted} из ${data.total} чек-листов`);
      setSelectedInspections(new Set());
      await loadInspections();
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

  const handleBulkArchive = async () => {
    if (selectedInspections.size === 0) {
      alert('Выберите чек-листы для архивирования');
      return;
    }
    const confirm = window.confirm(`Отправить ${selectedInspections.size} выбранных чек-листов в архив?`);
    if (!confirm) return;

    setIsProcessing(true);
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/inspections/bulk-archive`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ inspection_ids: Array.from(selectedInspections), archive: true }),
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
      alert(`Отправлено в архив: ${data.archived} из ${data.total} чек-листов`);
      setSelectedInspections(new Set());
      await loadInspections();
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : typeof e === 'string' ? e : JSON.stringify(e);
      alert(`Ошибка архивирования: ${errorMessage}`);
    } finally {
      setIsProcessing(false);
    }
  };

  const cleanupOldInspections = async () => {
    const confirm = window.confirm(`Удалить чек-листы старше ${cleanupInspectionsDays} дней? Также будут удалены связанные отчеты и файлы. Действие необратимо.`);
    if (!confirm) return;
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const res = await fetch(`${API_BASE}/api/inspections/cleanup?older_than_days=${cleanupInspectionsDays}`, {
        method: 'DELETE',
        headers,
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }));
        alert(`Ошибка очистки: ${err.detail || res.statusText}`);
        return;
      }
      const data = await res.json().catch(() => null as { deleted?: number; reports_deleted?: number } | null);
      alert(`Удалено чек-листов: ${data?.deleted ?? 'OK'} (и отчетов: ${data?.reports_deleted ?? 0})`);
      await loadInspections();
    } catch (e) {
      alert(`Ошибка очистки: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const loadInspectionQuestionnaireInfo = async (inspectionId: string) => {
    if (questionnaireInfo[inspectionId]) return;

    setLoadingQuestionnaire(true);
    try {
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const response = await fetch(`${API_BASE}/api/inspections/${inspectionId}/questionnaire`, { headers });
      if (!response.ok) return;

      const data = await response.json();
      setQuestionnaireInfo((prev) => ({
        ...prev,
        [inspectionId]: {
          questionnaire_id: data.questionnaire_id ?? null,
          document_files: data.document_files ?? [],
        },
      }));
    } catch {
      // не блокируем UI
    } finally {
      setLoadingQuestionnaire(false);
    }
  };

  const filteredInspections = inspections.filter((insp) => {
    if (!searchTerm.trim()) return true;
    const term = searchTerm.toLowerCase();
    return (
      insp.equipment_name?.toLowerCase().includes(term) ||
      insp.equipment_location?.toLowerCase().includes(term) ||
      insp.enterprise_name?.toLowerCase().includes(term) ||
      insp.branch_name?.toLowerCase().includes(term) ||
      insp.workshop_name?.toLowerCase().includes(term) ||
      insp.conclusion?.toLowerCase().includes(term) ||
      insp.id.toLowerCase().includes(term)
    );
  });

  const exportFilteredToCsv = () => {
    const rows = filteredInspections.map((insp) => ({
      id: insp.id,
      equipment: insp.equipment_name ?? '',
      location: insp.equipment_location ?? '',
      enterprise: insp.enterprise_name ?? '',
      branch: insp.branch_name ?? '',
      workshop: insp.workshop_name ?? '',
      status: insp.status ?? '',
      inspection_type: insp.inspection_type ?? '',
      method: insp.inspection_method ?? '',
      category: insp.inspection_category ?? '',
      date_performed: insp.date_performed ?? '',
      created_at: insp.created_at ?? '',
      conclusion: (insp.conclusion ?? '').replaceAll('\n', ' ').replaceAll(';', ','),
    }));

    if (rows.length === 0) {
      alert('Нет данных для экспорта');
      return;
    }

    const csvHeaders = Object.keys(rows[0]);
    const csv = [
      csvHeaders.join(';'),
      ...rows.map((row) =>
        csvHeaders
          .map((header) => `"${String((row as Record<string, string>)[header] ?? '').replaceAll('"', '""')}"`)
          .join(';'),
      ),
    ].join('\n');

    const blob = new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    const now = new Date();
    const datePart = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    link.href = url;
    link.download = `inspections-${datePart}.csv`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  const getGroupKey = (insp: Inspection): string => {
    if (groupBy === 'enterprise') return insp.enterprise_name || 'Без предприятия';
    if (groupBy === 'branch') return [insp.enterprise_name, insp.branch_name].filter(Boolean).join(' / ') || 'Без филиала';
    if (groupBy === 'workshop') return [insp.enterprise_name, insp.branch_name, insp.workshop_name].filter(Boolean).join(' / ') || 'Без цеха';
    if (groupBy === 'inspection_type') return insp.inspection_type || 'UNSPECIFIED';
    return '';
  };

  const groupedInspections = useMemo(() => {
    if (groupBy === 'none') return null;
    const map = new Map<string, Inspection[]>();
    for (const insp of filteredInspections) {
      const key = getGroupKey(insp);
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(insp);
    }
    return Array.from(map.entries()).sort((a, b) => a[0].localeCompare(b[0]));
  }, [groupBy, filteredInspections]);

  const toggleGroup = (key: string) => {
    setExpandedGroups((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const handleEnterpriseChange = (v: string) => {
    setSelectedEnterpriseId(v);
    setSelectedBranchId('');
    setSelectedWorkshopId('');
    setBranches([]);
    setWorkshops([]);
    if (v) loadBranches(v);
  };

  const handleBranchChange = (v: string) => {
    setSelectedBranchId(v);
    setSelectedWorkshopId('');
    setWorkshops([]);
    if (v) loadWorkshops(v);
  };

  const handleToggleSelect = (id: string) => {
    setSelectedInspections((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleOpenDetails = (insp: Inspection) => {
    setSelectedInspection(insp);
    setShowDetails(true);
    loadInspectionQuestionnaireInfo(insp.id);
  };

  return (
    <div className="space-y-6">
      <nav className="flex items-center gap-2 text-sm" style={{ color: 'var(--text-muted)' }}>
        <span className="font-medium" style={{ color: 'var(--text-primary)' }}>Чек-листы</span>
        {selectedEnterpriseId && enterprises.find((e) => e.id === selectedEnterpriseId) && (
          <>
            <ChevronRight size={14} style={{ color: 'var(--text-muted)' }} />
            <span style={{ color: 'var(--text-secondary)' }}>{enterprises.find((e) => e.id === selectedEnterpriseId)?.name}</span>
          </>
        )}
        {selectedBranchId && branches.find((b) => b.id === selectedBranchId) && (
          <>
            <ChevronRight size={14} style={{ color: 'var(--text-muted)' }} />
            <span style={{ color: 'var(--text-secondary)' }}>{branches.find((b) => b.id === selectedBranchId)?.name}</span>
          </>
        )}
        {selectedWorkshopId && workshops.find((w) => w.id === selectedWorkshopId) && (
          <>
            <ChevronRight size={14} style={{ color: 'var(--text-muted)' }} />
            <span style={{ color: 'var(--text-secondary)' }}>{workshops.find((w) => w.id === selectedWorkshopId)?.name}</span>
          </>
        )}
      </nav>

      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2" style={{ color: 'var(--text-primary)', letterSpacing: '-0.02em' }}>
            <FileText className="text-[var(--accent)]" size={26} />
            Чек-листы диагностики
          </h1>
          <p className="mt-1" style={{ color: 'var(--text-muted)', fontSize: 13 }}>
            Просмотр и управление чек-листами по предприятиям, филиалам и цехам
          </p>
        </div>
      </div>

      <InspectionsFiltersBar
        selectedCount={selectedInspections.size}
        isProcessing={isProcessing}
        onBulkArchive={handleBulkArchive}
        onBulkDelete={handleBulkDelete}
        onClearSelection={() => setSelectedInspections(new Set())}
        searchTerm={searchTerm}
        onSearchTermChange={setSearchTerm}
        equipment={equipment}
        selectedEquipment={selectedEquipment}
        onSelectedEquipmentChange={setSelectedEquipment}
        selectedStatus={selectedStatus}
        onSelectedStatusChange={setSelectedStatus}
        selectedInspectionType={selectedInspectionType}
        onSelectedInspectionTypeChange={setSelectedInspectionType}
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
        onGroupByChange={setGroupBy}
        onExportCsv={exportFilteredToCsv}
        cleanupInspectionsDays={cleanupInspectionsDays}
        onCleanupDaysChange={setCleanupInspectionsDays}
        onCleanupOldInspections={cleanupOldInspections}
      />

      <InspectionsListView
        loading={loading}
        filteredInspections={filteredInspections}
        groupBy={groupBy}
        groupedInspections={groupedInspections}
        expandedGroups={expandedGroups}
        onToggleGroup={toggleGroup}
        selectedInspectionIds={selectedInspections}
        onToggleSelect={handleToggleSelect}
        onOpenDetails={handleOpenDetails}
        canApprove={canApprove}
        onApprove={approveInspection}
        onDelete={deleteInspection}
      />

      {showDetails && selectedInspection && (
        <InspectionDetailModal
          inspection={selectedInspection}
          questionnaireInfo={questionnaireInfo}
          loadingQuestionnaire={loadingQuestionnaire}
          onClose={() => setShowDetails(false)}
        />
      )}
    </div>
  );
};

export default InspectionsList;
