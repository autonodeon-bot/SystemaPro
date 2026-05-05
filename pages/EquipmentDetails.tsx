import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Calendar, FileText, Info, MapPin, Package, Users, Wrench, Eye, X, Sparkles, Download, Trash2, CheckCircle2, Image as ImageIcon, Target, Upload, Plus } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { API_BASE } from '../constants';

const EquipmentDetails = () => {
  const { id } = useParams();
  const navigate = useNavigate();
  const { getToken, user } = useAuth();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [equipment, setEquipment] = useState<any>(null);
  const [inspectionHistory, setInspectionHistory] = useState<any[]>([]);
  const [inspections, setInspections] = useState<any[]>([]);
  const [repairJournal, setRepairJournal] = useState<any[]>([]);
  const [reports, setReports] = useState<any[]>([]);
  const [assignedEngineers, setAssignedEngineers] = useState<any[]>([]);
  const [assignments, setAssignments] = useState<any[]>([]);

  const [previewData, setPreviewData] = useState<any | null>(null);
  const [previewType, setPreviewType] = useState<'TECHNICAL_REPORT' | 'EXPERTISE'>('TECHNICAL_REPORT');
  const [loadingPreview, setLoadingPreview] = useState(false);
  const [generating, setGenerating] = useState(false);

  const headers = useMemo(() => {
    const token = getToken();
    if (!token) return null;
    return { 'Authorization': `Bearer ${token}` } as HeadersInit;
  }, [getToken]);

  const canApprove = useMemo(() => {
    const role = (user?.role || '').toLowerCase();
    return ['admin', 'chief_operator', 'operator'].includes(role);
  }, [user]);

  const reloadReportsAndInspections = useCallback(async () => {
    if (!id || !headers) return;
    try {
      const [inspRes, reportsRes] = await Promise.all([
        fetch(`${API_BASE}/api/inspections?equipment_id=${id}&limit=1000`, { headers }).catch(() => null as any),
        fetch(`${API_BASE}/api/reports?equipment_id=${id}`, { headers }).catch(() => null as any),
      ]);

      if (inspRes && inspRes.ok) {
        const idata = await inspRes.json();
        setInspections(idata.items || []);
      }
      if (reportsRes && reportsRes.ok) {
        const rd = await reportsRes.json();
        setReports(rd.items || []);
      }
    } catch {
      // ignore
    }
  }, [id, headers]);

  useEffect(() => {
    const load = async () => {
      if (!id) return;
      setLoading(true);
      setError(null);
      try {
        if (!headers) {
          alert('Необходимо авторизоваться.');
          window.location.href = '/#/login';
          return;
        }

        const [eqRes, historyRes, inspRes, repairRes, reportsRes, assignedRes, assignmentsRes] = await Promise.all([
          fetch(`${API_BASE}/api/equipment/${id}`, { headers }),
          fetch(`${API_BASE}/api/equipment/${id}/history`, { headers }),
          fetch(`${API_BASE}/api/inspections?equipment_id=${id}&limit=1000`, { headers }).catch(() => null as any),
          fetch(`${API_BASE}/api/equipment/${id}/repairs`, { headers }),
          fetch(`${API_BASE}/api/reports?equipment_id=${id}`, { headers }).catch(() => null as any),
          fetch(`${API_BASE}/api/hierarchy/equipment/${id}/assigned-engineers`, { headers }).catch(() => null as any),
          fetch(`${API_BASE}/api/assignments?equipment_id=${id}`, { headers }).catch(() => null as any),
        ]);

        if (!eqRes.ok) {
          const t = await eqRes.text();
          throw new Error(`Оборудование не найдено: ${t}`);
        }
        const eqData = await eqRes.json();
        setEquipment(eqData);

        if (historyRes.ok) setInspectionHistory(await historyRes.json());
        if (inspRes && inspRes.ok) {
          const idata = await inspRes.json();
          setInspections(idata.items || []);
        } else {
          setInspections([]);
        }
        if (repairRes.ok) setRepairJournal(await repairRes.json());

        if (reportsRes && reportsRes.ok) {
          const rd = await reportsRes.json();
          setReports(rd.items || []);
        } else {
          setReports([]);
        }

        if (assignedRes && assignedRes.ok) {
          const ad = await assignedRes.json();
          setAssignedEngineers(ad.items || []);
        } else {
          setAssignedEngineers([]);
        }

        if (assignmentsRes && assignmentsRes.ok) {
          const a = await assignmentsRes.json();
          setAssignments(Array.isArray(a) ? a : (a.items || []));
        } else {
          setAssignments([]);
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [id, headers]);

  const updateInspectionStatus = async (inspectionId: string, status: 'DRAFT' | 'SIGNED' | 'APPROVED') => {
    if (!headers) return;
    try {
      const res = await fetch(`${API_BASE}/api/inspections/${inspectionId}/status`, {
        method: 'PATCH',
        headers: { ...(headers as any), 'Content-Type': 'application/json' },
        body: JSON.stringify({ status }),
      });
      if (!res.ok) {
        const t = await res.text();
        throw new Error(t);
      }
      await reloadReportsAndInspections();
    } catch (e) {
      alert(`Ошибка смены статуса: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const deleteInspection = async (inspectionId: string) => {
    if (!headers) return;
    const ok = window.confirm('Удалить чек-лист? Также будут удалены связанные отчеты и файлы. Действие необратимо.');
    if (!ok) return;
    try {
      const res = await fetch(`${API_BASE}/api/inspections/${inspectionId}`, { method: 'DELETE', headers });
      if (!res.ok) {
        const t = await res.text();
        throw new Error(t);
      }
      await reloadReportsAndInspections();
      if (previewData?.inspection?.id === inspectionId) setPreviewData(null);
    } catch (e) {
      alert(`Ошибка удаления чек-листа: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const deleteReport = async (reportId: string) => {
    if (!headers) return;
    const ok = window.confirm('Удалить отчет? Файл будет удален без возможности восстановления.');
    if (!ok) return;
    try {
      const res = await fetch(`${API_BASE}/api/reports/${reportId}`, { method: 'DELETE', headers });
      if (!res.ok) {
        const t = await res.text();
        throw new Error(t);
      }
      await reloadReportsAndInspections();
    } catch (e) {
      alert(`Ошибка удаления отчета: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const loadPreview = async (inspectionId: string, type: 'TECHNICAL_REPORT' | 'EXPERTISE') => {
    if (!headers) return;
    setLoadingPreview(true);
    try {
      const res = await fetch(`${API_BASE}/api/inspections/${inspectionId}/preview`, { headers });
      if (!res.ok) {
        const t = await res.text();
        throw new Error(t);
      }
      const data = await res.json();
      setPreviewData(data);
      setPreviewType(type);
    } catch (e) {
      alert(`Ошибка загрузки предпросмотра: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setLoadingPreview(false);
    }
  };

  const generateReportFromPreview = async (format: 'pdf' | 'docx') => {
    if (!previewData?.inspection?.id || !headers) return;
    setGenerating(true);
    try {
      const res = await fetch(`${API_BASE}/api/reports/generate`, {
        method: 'POST',
        headers: { ...(headers as any), 'Content-Type': 'application/json' },
        body: JSON.stringify({
          inspection_id: previewData.inspection.id,
          report_type: previewType,
          format,
          title: `${previewType === 'TECHNICAL_REPORT' ? 'Технический отчет' : 'Экспертиза ПБ'} (из карточки оборудования)`
        }),
      });
      if (!res.ok) {
        const t = await res.text();
        throw new Error(t);
      }
      alert(`Отчет сгенерирован (${format.toUpperCase()})`);
      setPreviewData(null);
      await reloadReportsAndInspections();
    } catch (e) {
      alert(`Ошибка генерации: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setGenerating(false);
    }
  };

  const statusBadge = (status: string) => {
    const s = (status || '').toUpperCase();
    const cls =
      s === 'COMPLETED' || s === 'SIGNED' || s === 'APPROVED'
        ? 'bg-green-500/20 text-green-400 border-green-500/30'
        : s === 'IN_PROGRESS'
        ? 'bg-blue-500/20 text-blue-400 border-blue-500/30'
        : s === 'PENDING' || s === 'DRAFT'
        ? 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30'
        : 'bg-app-text3/20 text-app-text3 border-app-text3/30';
    return <span className={`inline-flex px-2 py-1 rounded text-xs font-medium border ${cls}`}>{status}</span>;
  };

  if (loading) {
    return <div className="text-center text-app-text3 mt-10">Загрузка карточки оборудования...</div>;
  }

  if (error) {
    return (
      <div className="space-y-4">
        <button
          onClick={() => navigate(-1)}
          className="inline-flex items-center gap-2 text-app-text2 hover:text-white"
        >
          <ArrowLeft size={18} /> Назад
        </button>
        <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-4 text-red-300">
          {error}
        </div>
      </div>
    );
  }

  const eqName = equipment?.name || 'Оборудование';
  const eqCode = equipment?.equipment_code || equipment?.code || '';

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <button
            onClick={() => navigate(-1)}
            className="inline-flex items-center gap-2 text-app-text2 hover:text-white"
          >
            <ArrowLeft size={18} /> Назад
          </button>
          <h1 className="text-2xl font-bold text-white">{eqName}</h1>
          {eqCode && <span className="text-xs text-app-text3">({eqCode})</span>}
        </div>
      </div>

      {/* Основные данные */}
      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Info className="text-accent" size={20} />
          Общая информация
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="bg-app-deep rounded-lg p-4 border border-app-line">
            <div className="flex items-center gap-2 text-app-text2">
              <Package size={16} className="text-accent" />
              <span className="font-semibold">Наименование:</span>
              <span>{eqName}</span>
            </div>
            {equipment?.serial_number && (
              <div className="mt-2 text-sm text-app-text3">Зав. № {equipment.serial_number}</div>
            )}
            {equipment?.location && (
              <div className="mt-2 flex items-center gap-2 text-sm text-app-text3">
                <MapPin size={14} className="text-app-text3" />
                <span>{equipment.location}</span>
              </div>
            )}
            {equipment?.commissioning_date && (
              <div className="mt-2 flex items-center gap-2 text-sm text-app-text3">
                <Calendar size={14} className="text-app-text3" />
                <span>
                  Ввод в эксплуатацию: {new Date(equipment.commissioning_date).toLocaleDateString('ru-RU')}
                </span>
              </div>
            )}
          </div>

          <div className="bg-app-deep rounded-lg p-4 border border-app-line">
            <div className="text-sm text-app-text2 font-semibold mb-2">Характеристики</div>
            <pre className="text-xs text-app-text3 whitespace-pre-wrap">
              {JSON.stringify(equipment?.attributes || {}, null, 2)}
            </pre>
          </div>
        </div>
      </div>

      {/* Чертежи и схемы */}
      {equipment && (
        <EquipmentDrawingTemplatesSection
          equipmentId={String(id)}
          equipmentTypeId={equipment.type_id || equipment.equipment_type_id || null}
          headers={headers}
          canEdit={canApprove}
        />
      )}

      {/* История обследований */}
      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Calendar className="text-accent" size={20} />
          История обследований ({inspectionHistory.length})
        </h2>
        {inspectionHistory.length === 0 ? (
          <p className="text-app-text3">История отсутствует</p>
        ) : (
          <div className="space-y-2">
            {inspectionHistory.slice(0, 20).map((inspection: any) => (
              <div key={inspection.id} className="bg-app-deep rounded-lg p-4 border border-app-line">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="text-white font-semibold">{inspection.inspection_type || 'Обследование'}</div>
                    <div className="text-xs text-app-text3 mt-1">
                      {inspection.inspection_date ? new Date(inspection.inspection_date).toLocaleDateString('ru-RU') : '—'}
                      {inspection.inspector_name ? ` · Инженер: ${inspection.inspector_name}` : ''}
                    </div>
                    {inspection.conclusion && (
                      <div className="text-sm text-app-text2 mt-2">{inspection.conclusion}</div>
                    )}
                  </div>
                  <div className="flex gap-2">
                    {inspection.report_path && (
                      <a
                        href={`${API_BASE}/${inspection.report_path}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="bg-accent px-3 py-1 rounded text-white text-sm hover:bg-blue-600"
                      >
                        PDF
                      </a>
                    )}
                    {inspection.word_report_path && (
                      <a
                        href={`${API_BASE}/${inspection.word_report_path}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="bg-app-soft px-3 py-1 rounded text-app-text text-sm hover:bg-app-softer"
                      >
                        DOCX
                      </a>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Обследования инженера (сырые данные + предпросмотр перед генерацией) */}
      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Sparkles className="text-accent" size={20} />
          Данные обследований (перед генерацией) ({inspections.length})
        </h2>
        {inspections.length === 0 ? (
          <p className="text-app-text3">Обследований пока нет</p>
        ) : (
          <div className="space-y-2">
            {inspections.slice(0, 20).map((insp: any) => {
              const inspectorName =
                insp?.data?.inspector_name ||
                insp?.data?.executors ||
                insp?.data?.inspectorName ||
                '';
              return (
                <div key={insp.id} className="bg-app-deep rounded-lg p-4 border border-app-line">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="text-white font-semibold">
                        Обследование
                        <span className="ml-2">{statusBadge(insp.status)}</span>
                      </div>
                      <div className="text-xs text-app-text3 mt-1">
                        {insp.date_performed ? new Date(insp.date_performed).toLocaleDateString('ru-RU') : '—'}
                        {inspectorName ? ` · Инженер: ${inspectorName}` : ''}
                      </div>
                      {insp.conclusion && <div className="text-sm text-app-text2 mt-2">{insp.conclusion}</div>}
                    </div>
                    <div className="flex gap-2">
                      <button
                        onClick={() => loadPreview(insp.id, 'TECHNICAL_REPORT')}
                        disabled={loadingPreview}
                        className="bg-app-soft px-3 py-1 rounded text-app-text text-sm hover:bg-app-softer inline-flex items-center gap-2 disabled:opacity-50"
                        title="Предпросмотр тех. отчета"
                      >
                        <Eye size={16} /> Предпросмотр
                      </button>
                      {canApprove && String(insp.status || '').toUpperCase() !== 'APPROVED' && (
                        <button
                          onClick={() => updateInspectionStatus(insp.id, 'APPROVED')}
                          className="bg-green-600 px-3 py-1 rounded text-white text-sm hover:bg-green-700 inline-flex items-center gap-2"
                          title="Утвердить чек-лист/обследование"
                        >
                          <CheckCircle2 size={16} /> Утвердить
                        </button>
                      )}
                      <button
                        onClick={() => deleteInspection(insp.id)}
                        className="bg-red-600 px-3 py-1 rounded text-white text-sm hover:bg-red-700 inline-flex items-center gap-2"
                        title="Удалить чек-лист"
                      >
                        <Trash2 size={16} /> Удалить
                      </button>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Задания по этому оборудованию (выполнено/не выполнено) */}
      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Users className="text-accent" size={20} />
          Задания по оборудованию ({assignments.length})
        </h2>
        {assignments.length === 0 ? (
          <p className="text-app-text3">Задания не назначены</p>
        ) : (
          <div className="space-y-2">
            {assignments.slice(0, 20).map((a: any) => (
              <div key={a.id} className="bg-app-deep rounded-lg p-4 border border-app-line flex items-start justify-between gap-3">
                <div>
                  <div className="text-white font-semibold">{a.assignment_type}</div>
                  <div className="text-xs text-app-text3 mt-1">
                    {a.assigned_to_name ? `Инженер: ${a.assigned_to_name}` : ''}
                    {a.due_date ? ` · Срок: ${new Date(a.due_date).toLocaleDateString('ru-RU')}` : ''}
                  </div>
                  {a.description && <div className="text-sm text-app-text2 mt-2">{a.description}</div>}
                </div>
                <div className="shrink-0">{statusBadge(a.status)}</div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Журнал ремонтов */}
      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Wrench className="text-accent" size={20} />
          Журнал ремонтов ({repairJournal.length})
        </h2>
        {repairJournal.length === 0 ? (
          <p className="text-app-text3">Ремонты не проводились</p>
        ) : (
          <div className="space-y-2">
            {repairJournal.slice(0, 20).map((repair: any) => (
              <div key={repair.id} className="bg-app-deep rounded-lg p-4 border border-app-line">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="text-white font-semibold">{repair.repair_type || 'Ремонт'}</div>
                    <div className="text-xs text-app-text3 mt-1">
                      {repair.repair_date ? new Date(repair.repair_date).toLocaleDateString('ru-RU') : '—'}
                      {repair.performed_by_name ? ` · Исполнитель: ${repair.performed_by_name}` : ''}
                    </div>
                    {repair.description && <div className="text-sm text-app-text2 mt-2">{repair.description}</div>}
                  </div>
                  {repair.cost && <div className="text-accent font-semibold">{repair.cost} ₽</div>}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Документы */}
      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <FileText className="text-accent" size={20} />
          Документы по диагностике ({reports.length})
        </h2>
        {reports.length === 0 ? (
          <p className="text-app-text3">Документы отсутствуют</p>
        ) : (
          <div className="space-y-2">
            {reports.map((report: any) => (
              <div key={report.id} className="bg-app-deep rounded-lg p-4 border border-app-line flex items-center justify-between gap-3">
                <div>
                  <div className="text-white font-semibold">{report.title || report.report_type}</div>
                  <div className="mt-1">{statusBadge(report.status)}</div>
                  {report.inspector_name && (
                    <div className="text-xs text-app-text3 mt-1">Инженер: {report.inspector_name}</div>
                  )}
                  {report.created_at && (
                    <div className="text-xs text-app-text3 mt-1">
                      {new Date(report.created_at).toLocaleDateString('ru-RU')}
                    </div>
                  )}
                </div>
                <div className="flex gap-2">
                  {(report.file_path || report.word_file_path) && (
                    <>
                      {report.file_path && (
                        <a
                          href={`${API_BASE}/api/reports/${report.id}/download?format=pdf`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="bg-accent px-3 py-1 rounded text-white text-sm hover:bg-blue-600 inline-flex items-center gap-2"
                          title="Скачать PDF"
                        >
                          <Download size={14} /> PDF
                        </a>
                      )}
                      {report.word_file_path && (
                        <a
                          href={`${API_BASE}/api/reports/${report.id}/download?format=docx`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="bg-app-soft px-3 py-1 rounded text-app-text text-sm hover:bg-app-softer inline-flex items-center gap-2"
                          title="Скачать DOCX"
                        >
                          <Download size={14} /> DOCX
                        </a>
                      )}
                    </>
                  )}
                  {canApprove && report.inspection_id && String(report.status || '').toUpperCase() !== 'APPROVED' && (
                    <button
                      onClick={() => updateInspectionStatus(report.inspection_id, 'APPROVED')}
                      className="bg-green-600 px-3 py-1 rounded text-white text-sm hover:bg-green-700 inline-flex items-center gap-2"
                      title="Утвердить отчет"
                    >
                      <CheckCircle2 size={14} /> Утвердить
                    </button>
                  )}
                  <button
                    onClick={() => deleteReport(report.id)}
                    className="bg-red-600 px-3 py-1 rounded text-white text-sm hover:bg-red-700 inline-flex items-center gap-2"
                    title="Удалить отчет"
                  >
                    <Trash2 size={14} /> Удалить
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Назначенные инженеры */}
      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Users className="text-accent" size={20} />
          Назначенные инженеры ({assignedEngineers.length})
        </h2>
        {assignedEngineers.length === 0 ? (
          <p className="text-app-text3">Инженеры не назначены</p>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {assignedEngineers.map((e: any) => (
              <div key={e.user_id} className="bg-app-deep rounded-lg p-4 border border-app-line">
                <div className="text-white font-semibold">{e.full_name || e.username}</div>
                {e.email && <div className="text-xs text-app-text3 mt-1">{e.email}</div>}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Модалка предпросмотра перед генерацией */}
      {previewData && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50" onClick={() => setPreviewData(null)}>
          <div className="bg-app-panel rounded-xl border border-app-line w-full max-w-4xl mx-4 max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="p-4 border-b border-app-line flex items-center justify-between">
              <div className="text-white font-bold">
                Предпросмотр данных перед генерацией
              </div>
              <button onClick={() => setPreviewData(null)} className="text-app-text2 hover:text-white">
                <X size={20} />
              </button>
            </div>
            <div className="p-4 space-y-4">
              <div className="bg-app-deep rounded-lg border border-app-line p-4">
                <div className="text-app-text2 text-sm mb-2">Оборудование</div>
                <div className="text-white font-semibold">{previewData?.equipment?.name}</div>
                {previewData?.equipment?.serial_number && <div className="text-xs text-app-text3 mt-1">№ {previewData.equipment.serial_number}</div>}
                {previewData?.equipment?.location && <div className="text-xs text-app-text3 mt-1">Место: {previewData.equipment.location}</div>}
              </div>

              <div className="bg-app-deep rounded-lg border border-app-line p-4">
                <div className="text-app-text2 text-sm mb-2">Обследование</div>
                <div className="text-xs text-app-text3">
                  {previewData?.inspection?.date_performed ? new Date(previewData.inspection.date_performed).toLocaleString('ru-RU') : '—'} · {previewData?.inspection?.status}
                </div>
                {previewData?.inspection?.conclusion && <div className="text-sm text-app-text mt-2">{previewData.inspection.conclusion}</div>}
              </div>

              {previewData?.document_files && previewData.document_files.length > 0 && (
                <div className="bg-app-deep rounded-lg border border-app-line p-4">
                  <div className="text-app-text2 text-sm mb-2">Приложенные файлы (документы, сканы, фото НК)</div>
                  <div className="flex flex-wrap gap-2">
                    {previewData.document_files.map((f: { document_number: string; file_name?: string; view_url?: string }) => (
                      <a
                        key={f.document_number}
                        href={f.view_url ? `${API_BASE}${f.view_url}` : undefined}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-app-soft hover:bg-app-softer text-app-text text-sm"
                      >
                        <FileText size={16} />
                        {f.file_name || f.document_number}
                      </a>
                    ))}
                  </div>
                </div>
              )}

              <div className="bg-app-deep rounded-lg border border-app-line p-4">
                <div className="text-app-text2 text-sm mb-2">Сырые данные (JSON)</div>
                <pre className="text-xs text-app-text2 whitespace-pre-wrap">{JSON.stringify(previewData?.inspection?.data || {}, null, 2)}</pre>
              </div>

              <div className="flex flex-col sm:flex-row gap-2 justify-end">
                <button
                  onClick={() => setPreviewType('TECHNICAL_REPORT')}
                  className={`px-4 py-2 rounded-lg text-sm font-bold ${previewType === 'TECHNICAL_REPORT' ? 'bg-accent text-white' : 'bg-app-soft text-app-text hover:bg-app-softer'}`}
                >
                  Технический отчет
                </button>
                <button
                  onClick={() => setPreviewType('EXPERTISE')}
                  className={`px-4 py-2 rounded-lg text-sm font-bold ${previewType === 'EXPERTISE' ? 'bg-accent text-white' : 'bg-app-soft text-app-text hover:bg-app-softer'}`}
                >
                  Экспертиза ПБ
                </button>
                <button
                  onClick={() => generateReportFromPreview('pdf')}
                  disabled={generating}
                  className="px-4 py-2 rounded-lg text-sm font-bold bg-green-600 text-white hover:bg-green-500 disabled:opacity-50 inline-flex items-center gap-2"
                >
                  <Download size={16} /> Сгенерировать PDF
                </button>
                <button
                  onClick={() => generateReportFromPreview('docx')}
                  disabled={generating}
                  className="px-4 py-2 rounded-lg text-sm font-bold bg-app-soft text-app-text hover:bg-app-softer disabled:opacity-50 inline-flex items-center gap-2"
                >
                  <Download size={16} /> Сгенерировать DOCX
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

// ─── Секция «Чертежи и схемы оборудования» ───────────────────────────────
// Работает с API /api/drawing-templates: список для этой единицы (свои + общие по типу).

interface DrawingItem {
  id: string;
  name: string;
  description?: string | null;
  category?: string | null;
  equipment_id?: string | null;
  equipment_type_id?: string | null;
  equipment_name?: string | null;
  equipment_type_name?: string | null;
  image_width?: number | null;
  image_height?: number | null;
  version: number;
  points_count?: number;
  updated_at?: string;
}

const CATEGORY_RU: Record<string, string> = {
  vessel: 'Сосуды',
  pipeline: 'Трубопроводы',
  ndt_scheme: 'Схема НК',
  thickness_scheme: 'Схема УЗТ',
  other: 'Прочее',
};

const EquipmentDrawingTemplatesSection: React.FC<{
  equipmentId: string;
  equipmentTypeId: string | null;
  headers: HeadersInit | null;
  canEdit: boolean;
}> = ({ equipmentId, equipmentTypeId: _equipmentTypeId, headers, canEdit }) => {
  const [items, setItems] = useState<DrawingItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const navigate = useNavigate();
  const fileInputRef = useMemo(() => ({ current: null as HTMLInputElement | null }), []);

  const load = useCallback(async () => {
    if (!headers) return;
    setLoading(true);
    try {
      const res = await fetch(
        `${API_BASE}/api/drawing-templates?equipment_id=${equipmentId}&active_only=true`,
        { headers },
      );
      if (res.ok) {
        const data = await res.json();
        setItems(data.items || []);
      }
    } catch (e) {
      console.error('load drawings', e);
    } finally {
      setLoading(false);
    }
  }, [equipmentId, headers]);

  useEffect(() => { load(); }, [load]);

  const quickUpload = async (file: File) => {
    if (!headers) return;
    setUploading(true);
    try {
      const fd = new FormData();
      fd.append('file', file);
      fd.append('name', file.name.replace(/\.[^.]+$/, ''));
      fd.append('category', 'vessel');
      fd.append('equipment_id', equipmentId);
      const res = await fetch(`${API_BASE}/api/drawing-templates`, {
        method: 'POST',
        headers,
        body: fd,
      });
      if (!res.ok) throw new Error(String(res.status));
      const created: DrawingItem = await res.json();
      setItems((prev) => [created, ...prev]);
    } catch (e) {
      alert(`Ошибка загрузки: ${(e as Error).message}`);
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="bg-app-panel rounded-xl border border-app-line p-6">
      <div className="flex items-center justify-between gap-3 mb-4 flex-wrap">
        <h2 className="text-lg font-semibold text-white flex items-center gap-2">
          <ImageIcon className="text-accent" size={20} />
          Чертежи и схемы ({items.length})
        </h2>
        {canEdit && (
          <div className="flex items-center gap-2">
            <label className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-app-soft hover:bg-app-softer text-app-text text-sm font-semibold cursor-pointer">
              <Upload size={14} />
              {uploading ? 'Загрузка...' : 'Загрузить чертёж'}
              <input
                ref={(el) => (fileInputRef.current = el)}
                type="file"
                accept="image/png,image/jpeg"
                className="hidden"
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  if (f) quickUpload(f);
                  e.target.value = '';
                }}
              />
            </label>
            <button
              onClick={() => navigate('/drawing-templates')}
              className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-accent text-white text-sm font-semibold hover:bg-accent/80"
            >
              <Plus size={14} /> Менеджер шаблонов
            </button>
          </div>
        )}
      </div>

      {loading ? (
        <div className="text-app-text3 text-sm">Загрузка...</div>
      ) : items.length === 0 ? (
        <div className="text-app-text3 text-sm text-center py-6 border border-dashed border-app-line rounded-lg">
          <ImageIcon size={32} className="mx-auto mb-2 opacity-40" />
          Для этого оборудования пока нет чертежей.
          {canEdit && (
            <div className="text-xs mt-1">Загрузите схему с точками замера — инженеры смогут использовать её в мобильном приложении.</div>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {items.map((t) => {
            const isOwn = t.equipment_id === equipmentId;
            return (
              <button
                key={t.id}
                onClick={() => navigate('/drawing-templates')}
                className="text-left bg-app-deep hover:bg-app-soft/50 border border-app-line hover:border-accent rounded-lg p-3 transition-colors"
              >
                <div className="flex items-start justify-between gap-2 mb-2">
                  <div className="text-white font-semibold text-sm truncate">{t.name}</div>
                  <span className="shrink-0 text-[10px] font-bold px-1.5 py-0.5 rounded bg-app-soft text-app-text2 font-mono">
                    v{t.version}
                  </span>
                </div>
                <div className="flex items-center gap-2 text-xs text-app-text3 flex-wrap">
                  <span className="inline-flex items-center gap-1 bg-app-panel px-2 py-0.5 rounded border border-app-line">
                    {CATEGORY_RU[t.category || ''] || t.category || '—'}
                  </span>
                  {isOwn ? (
                    <span className="inline-flex items-center gap-1 text-blue-400">
                      <Target size={10} /> Своя
                    </span>
                  ) : (
                    <span className="text-app-text3">Общий</span>
                  )}
                  <span className="ml-auto font-mono">{t.points_count ?? 0} точек</span>
                </div>
                {t.image_width && t.image_height && (
                  <div className="text-[10px] text-app-text3 mt-1 font-mono">
                    {t.image_width}×{t.image_height}
                  </div>
                )}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default EquipmentDetails;


