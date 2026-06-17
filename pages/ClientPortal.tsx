import { useState, useEffect, useMemo, useCallback } from 'react';
import { Download, FileText, MapPin, Search, RefreshCw, Building2, ClipboardList } from 'lucide-react';
import { API_BASE } from '../constants';
import { useAuth } from '../contexts/AuthContext';
import { useToast } from '../contexts/ToastContext';

interface Equipment {
  id: string;
  name: string;
  equipment_code?: string;
  serial_number?: string;
  location?: string;
}

interface Inspection {
  id: string;
  equipment_id: string;
  date_performed?: string;
  status: string;
  conclusion?: string;
}

interface Report {
  id: string;
  inspection_id: string;
  equipment_id: string;
  report_type: string;
  title: string;
  file_path: string;
  status: string;
  created_at: string;
}

const ClientPortal = () => {
  const { user, getToken } = useAuth();
  const toast = useToast();
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [selectedEquipment, setSelectedEquipment] = useState<Equipment | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedSearch(searchTerm), 320);
    return () => window.clearTimeout(t);
  }, [searchTerm]);

  const authHeaders = useCallback((): HeadersInit => {
    const headers: HeadersInit = { 'Content-Type': 'application/json' };
    const token = getToken();
    if (token) headers['Authorization'] = `Bearer ${token}`;
    return headers;
  }, [getToken]);

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const headers = authHeaders();

      const [eqResponse, inspResponse, repResponse] = await Promise.all([
        fetch(`${API_BASE}/api/equipment?limit=500`, { headers }),
        fetch(`${API_BASE}/api/inspections?limit=500`, { headers }),
        fetch(`${API_BASE}/api/reports`, { headers }),
      ]);

      if (eqResponse.ok) {
        const eqData = await eqResponse.json();
        setEquipment(eqData.items || []);
      } else {
        setEquipment([]);
      }

      if (inspResponse.ok) {
        const inspData = await inspResponse.json();
        setInspections(inspData.items || []);
      } else {
        setInspections([]);
      }

      if (repResponse.ok) {
        const repData = await repResponse.json();
        setReports(repData.items || []);
      } else {
        setReports([]);
      }
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
      toast.error('Не удалось обновить данные портала');
    } finally {
      setLoading(false);
    }
  }, [authHeaders, toast]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleDownloadReport = async (reportId: string, filename: string) => {
    try {
      const headers: HeadersInit = {};
      const token = getToken();
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const response = await fetch(`${API_BASE}/api/reports/${reportId}/download`, { headers });
      if (response.ok) {
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename || 'report.pdf';
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
        toast.success('Файл скачан');
      } else if (response.status === 403) {
        toast.error('Нет прав на скачивание этого отчёта');
      } else {
        toast.error('Не удалось скачать отчёт');
      }
    } catch (error) {
      console.error('Ошибка скачивания отчета:', error);
      toast.error('Ошибка скачивания отчёта');
    }
  };

  const getEquipmentInspections = (equipmentId: string) => {
    return inspections.filter((ins) => ins.equipment_id === equipmentId);
  };

  const getEquipmentReports = (equipmentId: string) => {
    return reports.filter((rep) => rep.equipment_id === equipmentId);
  };

  const filteredEquipment = useMemo(() => {
    const q = debouncedSearch.trim().toLowerCase();
    if (!q) return equipment;
    return equipment.filter(
      (eq) =>
        eq.name.toLowerCase().includes(q) ||
        (eq.equipment_code && eq.equipment_code.toLowerCase().includes(q)) ||
        (eq.location && eq.location.toLowerCase().includes(q)) ||
        (eq.serial_number && eq.serial_number.toLowerCase().includes(q)),
    );
  }, [equipment, debouncedSearch]);

  const summary = useMemo(() => {
    const inspSet = new Set(inspections.map((i) => i.id));
    return {
      equipmentCount: equipment.length,
      inspectionCount: inspSet.size,
      reportCount: reports.length,
    };
  }, [equipment.length, inspections, reports.length]);

  if (loading) {
    return <div className="text-center text-app-text3 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:justify-between lg:items-start">
        <div>
          <h1 className="text-2xl font-bold text-white">Клиентский портал</h1>
          <p className="text-sm text-app-text3 mt-1">
            {user?.username ? `Вы вошли как ${user.username}` : 'Просмотр оборудования и отчётов'}
            {user?.role === 'client' ? ' · роль «Клиент»' : ''}
          </p>
        </div>
        <div className="flex flex-col sm:flex-row gap-3 sm:items-center">
          <div className="relative w-full sm:w-64">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-app-text3" size={20} />
            <input
              type="text"
              placeholder="Поиск: наименование, код, место…"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full bg-app-panel border border-app-line rounded-lg pl-10 pr-4 py-2 text-app-text placeholder-app-text3"
            />
          </div>
          <button
            type="button"
            onClick={() => loadData()}
            className="inline-flex items-center justify-center gap-2 px-3 py-2 rounded-lg border border-app-line bg-app-panel text-app-text text-sm hover:border-accent/40"
          >
            <RefreshCw size={16} />
            Обновить
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div className="bg-app-panel rounded-xl border border-app-line p-4 flex items-center gap-3">
          <Building2 className="text-accent shrink-0" size={22} />
          <div>
            <p className="text-xs text-app-text3">Оборудование</p>
            <p className="text-xl font-bold text-app-text">{summary.equipmentCount}</p>
          </div>
        </div>
        <div className="bg-app-panel rounded-xl border border-app-line p-4 flex items-center gap-3">
          <ClipboardList className="text-amber-400 shrink-0" size={22} />
          <div>
            <p className="text-xs text-app-text3">Обследований (в выборке)</p>
            <p className="text-xl font-bold text-app-text">{summary.inspectionCount}</p>
          </div>
        </div>
        <div className="bg-app-panel rounded-xl border border-app-line p-4 flex items-center gap-3">
          <FileText className="text-green-400 shrink-0" size={22} />
          <div>
            <p className="text-xs text-app-text3">Отчётов доступно</p>
            <p className="text-xl font-bold text-app-text">{summary.reportCount}</p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredEquipment.map((eq) => {
          const eqInspections = getEquipmentInspections(eq.id);
          const eqReports = getEquipmentReports(eq.id);

          return (
            <div
              key={eq.id}
              className="bg-app-panel p-4 rounded-xl border border-app-line hover:border-accent/50 transition-colors cursor-pointer"
              onClick={() => setSelectedEquipment(eq)}
            >
              <div className="flex justify-between items-start mb-2">
                <h3 className="text-lg font-bold text-app-text">{eq.name}</h3>
                <span className="text-xs text-app-text3 bg-app-soft px-2 py-1 rounded whitespace-nowrap">
                  {eqInspections.length} диагностик
                </span>
              </div>

              {eq.equipment_code && (
                <p className="text-xs font-mono text-app-text2 mb-1">Код: {eq.equipment_code}</p>
              )}

              {eq.location && (
                <div className="flex items-center gap-2 text-accent mb-2">
                  <MapPin size={14} />
                  <span className="text-sm">{eq.location}</span>
                </div>
              )}

              {eq.serial_number && <p className="text-sm text-app-text3 mb-2">№ {eq.serial_number}</p>}

              <div className="mt-3 pt-3 border-t border-app-line">
                <p className="text-xs text-app-text3 mb-1">Отчетов: {eqReports.length}</p>
                {eqReports.length > 0 && (
                  <div className="flex gap-2 flex-wrap">
                    {eqReports.slice(0, 2).map((report) => (
                      <button
                        key={report.id}
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleDownloadReport(report.id, report.title);
                        }}
                        className="text-xs text-accent hover:underline flex items-center gap-1"
                      >
                        <FileText size={12} />
                        {report.report_type === 'TECHNICAL_REPORT' ? 'Отчет' : 'Экспертиза'}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {filteredEquipment.length === 0 && (
        <div className="text-center text-app-text3 py-20 max-w-lg mx-auto space-y-2">
          {equipment.length === 0 && debouncedSearch.trim() === '' ? (
            <>
              <p>Для вашей учётной записи пока нет доступного оборудования.</p>
              <p className="text-sm text-app-text3">
                Администратор должен указать организацию клиента в профиле пользователя и привязать предприятие
                (поле «Клиент» у предприятия) или проекты с заданиями/обследованиями по вашему оборудованию.
              </p>
            </>
          ) : (
            <p>Оборудование не найдено по запросу</p>
          )}
        </div>
      )}

      {selectedEquipment && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={() => setSelectedEquipment(null)}
        >
          <div
            className="bg-app-panel rounded-xl p-6 max-w-4xl w-full max-h-[80vh] overflow-y-auto border border-app-line"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">{selectedEquipment.name}</h2>
              <button
                type="button"
                onClick={() => setSelectedEquipment(null)}
                className="text-app-text3 hover:text-app-text"
              >
                ✕
              </button>
            </div>

            {selectedEquipment.equipment_code && (
              <p className="text-sm font-mono text-app-text2 mb-2">Код: {selectedEquipment.equipment_code}</p>
            )}

            {selectedEquipment.location && (
              <div className="flex items-center gap-2 text-accent mb-4">
                <MapPin size={16} />
                <span>{selectedEquipment.location}</span>
              </div>
            )}

            <div className="mb-6">
              <h3 className="text-lg font-bold text-app-text mb-3">История диагностик</h3>
              {getEquipmentInspections(selectedEquipment.id).length === 0 ? (
                <p className="text-app-text3">Диагностики не найдены</p>
              ) : (
                <div className="space-y-3">
                  {getEquipmentInspections(selectedEquipment.id).map((insp) => (
                    <div key={insp.id} className="bg-app-deep p-4 rounded-lg border border-app-line">
                      <div className="flex justify-between items-start mb-2">
                        <div>
                          <p className="text-white font-bold">
                            {insp.date_performed
                              ? new Date(insp.date_performed).toLocaleDateString('ru-RU')
                              : 'Дата не указана'}
                          </p>
                          <p className="text-sm text-app-text3">Статус: {insp.status}</p>
                        </div>
                      </div>
                      {insp.conclusion && (
                        <p className="text-app-text2 mt-2 text-sm">{insp.conclusion}</p>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div>
              <h3 className="text-lg font-bold text-app-text mb-3">Отчеты и экспертизы</h3>
              {getEquipmentReports(selectedEquipment.id).length === 0 ? (
                <p className="text-app-text3">Отчеты не найдены</p>
              ) : (
                <div className="space-y-2">
                  {getEquipmentReports(selectedEquipment.id).map((report) => (
                    <div
                      key={report.id}
                      className="bg-app-deep p-3 rounded-lg border border-app-line flex flex-col sm:flex-row sm:justify-between sm:items-center gap-3"
                    >
                      <div>
                        <p className="text-white font-bold">{report.title}</p>
                        <p className="text-sm text-app-text3">
                          {report.report_type === 'TECHNICAL_REPORT'
                            ? 'Технический отчет'
                            : report.report_type === 'EXPERTISE'
                              ? 'Экспертиза ПБ'
                              : 'Отчет'}
                          {' • '}
                          {new Date(report.created_at).toLocaleDateString('ru-RU')}
                        </p>
                      </div>
                      <button
                        type="button"
                        onClick={() => handleDownloadReport(report.id, report.title)}
                        className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center justify-center gap-2 hover:bg-accent/20 shrink-0"
                      >
                        <Download size={16} />
                        Скачать
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ClientPortal;
