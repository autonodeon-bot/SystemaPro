import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Calendar, FileText, Info, MapPin, Package, Users, Wrench, Eye, X, Sparkles, Download, Trash2, CheckCircle2 } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

const API_BASE = 'http://5.129.203.182:8000';

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
        : 'bg-slate-500/20 text-slate-400 border-slate-500/30';
    return <span className={`inline-flex px-2 py-1 rounded text-xs font-medium border ${cls}`}>{status}</span>;
  };

  if (loading) {
    return <div className="text-center text-slate-400 mt-10">Загрузка карточки оборудования...</div>;
  }

  if (error) {
    return (
      <div className="space-y-4">
        <button
          onClick={() => navigate(-1)}
          className="inline-flex items-center gap-2 text-slate-300 hover:text-white"
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
            className="inline-flex items-center gap-2 text-slate-300 hover:text-white"
          >
            <ArrowLeft size={18} /> Назад
          </button>
          <h1 className="text-2xl font-bold text-white">{eqName}</h1>
          {eqCode && <span className="text-xs text-slate-400">({eqCode})</span>}
        </div>
      </div>

      {/* Основные данные */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Info className="text-accent" size={20} />
          Общая информация
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="bg-slate-900 rounded-lg p-4 border border-slate-700">
            <div className="flex items-center gap-2 text-slate-300">
              <Package size={16} className="text-accent" />
              <span className="font-semibold">Наименование:</span>
              <span>{eqName}</span>
            </div>
            {equipment?.serial_number && (
              <div className="mt-2 text-sm text-slate-400">Зав. № {equipment.serial_number}</div>
            )}
            {equipment?.location && (
              <div className="mt-2 flex items-center gap-2 text-sm text-slate-400">
                <MapPin size={14} className="text-slate-500" />
                <span>{equipment.location}</span>
              </div>
            )}
            {equipment?.commissioning_date && (
              <div className="mt-2 flex items-center gap-2 text-sm text-slate-400">
                <Calendar size={14} className="text-slate-500" />
                <span>
                  Ввод в эксплуатацию: {new Date(equipment.commissioning_date).toLocaleDateString('ru-RU')}
                </span>
              </div>
            )}
          </div>

          <div className="bg-slate-900 rounded-lg p-4 border border-slate-700">
            <div className="text-sm text-slate-300 font-semibold mb-2">Характеристики</div>
            <pre className="text-xs text-slate-400 whitespace-pre-wrap">
              {JSON.stringify(equipment?.attributes || {}, null, 2)}
            </pre>
          </div>
        </div>
      </div>

      {/* История обследований */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Calendar className="text-accent" size={20} />
          История обследований ({inspectionHistory.length})
        </h2>
        {inspectionHistory.length === 0 ? (
          <p className="text-slate-400">История отсутствует</p>
        ) : (
          <div className="space-y-2">
            {inspectionHistory.slice(0, 20).map((inspection: any) => (
              <div key={inspection.id} className="bg-slate-900 rounded-lg p-4 border border-slate-700">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="text-white font-semibold">{inspection.inspection_type || 'Обследование'}</div>
                    <div className="text-xs text-slate-500 mt-1">
                      {inspection.inspection_date ? new Date(inspection.inspection_date).toLocaleDateString('ru-RU') : '—'}
                      {inspection.inspector_name ? ` · Инженер: ${inspection.inspector_name}` : ''}
                    </div>
                    {inspection.conclusion && (
                      <div className="text-sm text-slate-300 mt-2">{inspection.conclusion}</div>
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
                        className="bg-slate-700 px-3 py-1 rounded text-white text-sm hover:bg-slate-600"
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
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Sparkles className="text-accent" size={20} />
          Данные обследований (перед генерацией) ({inspections.length})
        </h2>
        {inspections.length === 0 ? (
          <p className="text-slate-400">Обследований пока нет</p>
        ) : (
          <div className="space-y-2">
            {inspections.slice(0, 20).map((insp: any) => {
              const inspectorName =
                insp?.data?.inspector_name ||
                insp?.data?.executors ||
                insp?.data?.inspectorName ||
                '';
              return (
                <div key={insp.id} className="bg-slate-900 rounded-lg p-4 border border-slate-700">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="text-white font-semibold">
                        Обследование
                        <span className="ml-2">{statusBadge(insp.status)}</span>
                      </div>
                      <div className="text-xs text-slate-500 mt-1">
                        {insp.date_performed ? new Date(insp.date_performed).toLocaleDateString('ru-RU') : '—'}
                        {inspectorName ? ` · Инженер: ${inspectorName}` : ''}
                      </div>
                      {insp.conclusion && <div className="text-sm text-slate-300 mt-2">{insp.conclusion}</div>}
                    </div>
                    <div className="flex gap-2">
                      <button
                        onClick={() => loadPreview(insp.id, 'TECHNICAL_REPORT')}
                        disabled={loadingPreview}
                        className="bg-slate-700 px-3 py-1 rounded text-white text-sm hover:bg-slate-600 inline-flex items-center gap-2 disabled:opacity-50"
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
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Users className="text-accent" size={20} />
          Задания по оборудованию ({assignments.length})
        </h2>
        {assignments.length === 0 ? (
          <p className="text-slate-400">Задания не назначены</p>
        ) : (
          <div className="space-y-2">
            {assignments.slice(0, 20).map((a: any) => (
              <div key={a.id} className="bg-slate-900 rounded-lg p-4 border border-slate-700 flex items-start justify-between gap-3">
                <div>
                  <div className="text-white font-semibold">{a.assignment_type}</div>
                  <div className="text-xs text-slate-500 mt-1">
                    {a.assigned_to_name ? `Инженер: ${a.assigned_to_name}` : ''}
                    {a.due_date ? ` · Срок: ${new Date(a.due_date).toLocaleDateString('ru-RU')}` : ''}
                  </div>
                  {a.description && <div className="text-sm text-slate-300 mt-2">{a.description}</div>}
                </div>
                <div className="shrink-0">{statusBadge(a.status)}</div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Журнал ремонтов */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Wrench className="text-accent" size={20} />
          Журнал ремонтов ({repairJournal.length})
        </h2>
        {repairJournal.length === 0 ? (
          <p className="text-slate-400">Ремонты не проводились</p>
        ) : (
          <div className="space-y-2">
            {repairJournal.slice(0, 20).map((repair: any) => (
              <div key={repair.id} className="bg-slate-900 rounded-lg p-4 border border-slate-700">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="text-white font-semibold">{repair.repair_type || 'Ремонт'}</div>
                    <div className="text-xs text-slate-500 mt-1">
                      {repair.repair_date ? new Date(repair.repair_date).toLocaleDateString('ru-RU') : '—'}
                      {repair.performed_by_name ? ` · Исполнитель: ${repair.performed_by_name}` : ''}
                    </div>
                    {repair.description && <div className="text-sm text-slate-300 mt-2">{repair.description}</div>}
                  </div>
                  {repair.cost && <div className="text-accent font-semibold">{repair.cost} ₽</div>}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Документы */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <FileText className="text-accent" size={20} />
          Документы по диагностике ({reports.length})
        </h2>
        {reports.length === 0 ? (
          <p className="text-slate-400">Документы отсутствуют</p>
        ) : (
          <div className="space-y-2">
            {reports.map((report: any) => (
              <div key={report.id} className="bg-slate-900 rounded-lg p-4 border border-slate-700 flex items-center justify-between gap-3">
                <div>
                  <div className="text-white font-semibold">{report.title || report.report_type}</div>
                  <div className="mt-1">{statusBadge(report.status)}</div>
                  {report.inspector_name && (
                    <div className="text-xs text-slate-500 mt-1">Инженер: {report.inspector_name}</div>
                  )}
                  {report.created_at && (
                    <div className="text-xs text-slate-500 mt-1">
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
                          className="bg-slate-700 px-3 py-1 rounded text-white text-sm hover:bg-slate-600 inline-flex items-center gap-2"
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
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <Users className="text-accent" size={20} />
          Назначенные инженеры ({assignedEngineers.length})
        </h2>
        {assignedEngineers.length === 0 ? (
          <p className="text-slate-400">Инженеры не назначены</p>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {assignedEngineers.map((e: any) => (
              <div key={e.user_id} className="bg-slate-900 rounded-lg p-4 border border-slate-700">
                <div className="text-white font-semibold">{e.full_name || e.username}</div>
                {e.email && <div className="text-xs text-slate-500 mt-1">{e.email}</div>}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Модалка предпросмотра перед генерацией */}
      {previewData && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50" onClick={() => setPreviewData(null)}>
          <div className="bg-slate-800 rounded-xl border border-slate-700 w-full max-w-4xl mx-4 max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="p-4 border-b border-slate-700 flex items-center justify-between">
              <div className="text-white font-bold">
                Предпросмотр данных перед генерацией
              </div>
              <button onClick={() => setPreviewData(null)} className="text-slate-300 hover:text-white">
                <X size={20} />
              </button>
            </div>
            <div className="p-4 space-y-4">
              <div className="bg-slate-900 rounded-lg border border-slate-700 p-4">
                <div className="text-slate-300 text-sm mb-2">Оборудование</div>
                <div className="text-white font-semibold">{previewData?.equipment?.name}</div>
                {previewData?.equipment?.serial_number && <div className="text-xs text-slate-400 mt-1">№ {previewData.equipment.serial_number}</div>}
                {previewData?.equipment?.location && <div className="text-xs text-slate-400 mt-1">Место: {previewData.equipment.location}</div>}
              </div>

              <div className="bg-slate-900 rounded-lg border border-slate-700 p-4">
                <div className="text-slate-300 text-sm mb-2">Обследование</div>
                <div className="text-xs text-slate-400">
                  {previewData?.inspection?.date_performed ? new Date(previewData.inspection.date_performed).toLocaleString('ru-RU') : '—'} · {previewData?.inspection?.status}
                </div>
                {previewData?.inspection?.conclusion && <div className="text-sm text-slate-200 mt-2">{previewData.inspection.conclusion}</div>}
              </div>

              <div className="bg-slate-900 rounded-lg border border-slate-700 p-4">
                <div className="text-slate-300 text-sm mb-2">Сырые данные (JSON)</div>
                <pre className="text-xs text-slate-300 whitespace-pre-wrap">{JSON.stringify(previewData?.inspection?.data || {}, null, 2)}</pre>
              </div>

              <div className="flex flex-col sm:flex-row gap-2 justify-end">
                <button
                  onClick={() => setPreviewType('TECHNICAL_REPORT')}
                  className={`px-4 py-2 rounded-lg text-sm font-bold ${previewType === 'TECHNICAL_REPORT' ? 'bg-accent text-white' : 'bg-slate-700 text-white hover:bg-slate-600'}`}
                >
                  Технический отчет
                </button>
                <button
                  onClick={() => setPreviewType('EXPERTISE')}
                  className={`px-4 py-2 rounded-lg text-sm font-bold ${previewType === 'EXPERTISE' ? 'bg-accent text-white' : 'bg-slate-700 text-white hover:bg-slate-600'}`}
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
                  className="px-4 py-2 rounded-lg text-sm font-bold bg-slate-700 text-white hover:bg-slate-600 disabled:opacity-50 inline-flex items-center gap-2"
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

export default EquipmentDetails;


