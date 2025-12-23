import React, { useState, useEffect } from 'react';
import { FileText, Download, FileCheck, Sparkles, Search, Eye, X, CheckCircle, AlertCircle, Trash2 } from 'lucide-react';

interface Inspection {
  id: string;
  equipment_id: string;
  date_performed?: string;
  status: string;
  conclusion?: string;
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
  report_type: string;
  title: string;
  file_path: string;
  status: string;
  created_at: string;
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

const ReportGeneration = () => {
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [previewData, setPreviewData] = useState<PreviewData | null>(null);
  const [previewType, setPreviewType] = useState<string>('');
  const [loadingPreview, setLoadingPreview] = useState(false);

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadData();
  }, []);

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
      
      const inspData = await inspRes.json();
      const eqData = await eqRes.json();
      const repData = await repRes.json();
      
      setInspections(inspData.items || []);
      setEquipment(eqData.items || []);
      setReports(repData.items || []);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadPreview = async (inspectionId: string, reportType: string) => {
    setLoadingPreview(true);
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const response = await fetch(`${API_BASE}/api/inspections/${inspectionId}/preview`, { headers });
      if (response.ok) {
        const data = await response.json();
        setPreviewData(data);
        setPreviewType(reportType);
      } else {
        const errorData = await response.json().catch(() => ({ detail: 'Неизвестная ошибка' }));
        alert(`Ошибка загрузки данных для предпросмотра: ${errorData.detail || response.statusText}`);
      }
    } catch (error) {
      console.error('Ошибка загрузки предпросмотра:', error);
      alert(`Ошибка загрузки предпросмотра: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
    } finally {
      setLoadingPreview(false);
    }
  };

  const generateReport = async (inspectionId: string, reportType: string, format: string = 'pdf') => {
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
          title: `${reportType === 'TECHNICAL_REPORT' ? 'Технический отчет' : 'Экспертиза ПБ'} для диагностики`
        })
      });

      if (response.ok) {
        const data = await response.json();
        alert(`Отчет успешно сгенерирован в формате ${format.toUpperCase()}!`);
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

  const handleDownloadReport = async (reportId: string, filePath?: string) => {
    try {
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const response = await fetch(`${API_BASE}/api/reports/${reportId}/download`, { headers });
      if (response.ok) {
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        const inferredName =
          filePath && filePath.includes('/') ? filePath.split('/').pop() : undefined;
        const ct = response.headers.get('content-type') || '';
        const ext = ct.includes('wordprocessingml') ? '.docx' : '.pdf';
        a.download = inferredName || `report${ext}`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
      }
    } catch (error) {
      console.error('Ошибка скачивания отчета:', error);
      alert('Ошибка скачивания отчета');
    }
  };

  const getEquipmentName = (equipmentId: string) => {
    const eq = equipment.find(e => e.id === equipmentId);
    return eq?.name || 'Неизвестное оборудование';
  };

  const getInspectionReport = (inspectionId: string) => {
    return reports.find(r => r.inspection_id === inspectionId);
  };

  const filteredInspections = inspections.filter(ins => {
    const eqName = getEquipmentName(ins.equipment_id);
    return eqName.toLowerCase().includes(searchTerm.toLowerCase());
  });

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-4 md:space-y-6">
      <div className="flex flex-col md:flex-row md:justify-between md:items-center gap-4">
        <h1 className="text-xl md:text-2xl font-bold text-white">Генерация отчетов и экспертиз</h1>
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

      {/* Список диагностик */}
      <div className="space-y-4">
        {filteredInspections.map((inspection) => {
          const existingReport = getInspectionReport(inspection.id);
          const eqName = getEquipmentName(inspection.equipment_id);
          
          return (
            <div
              key={inspection.id}
              className="bg-slate-800 p-4 rounded-xl border border-slate-700"
            >
              <div className="flex justify-between items-start mb-4">
                <div>
                  <h3 className="text-lg font-bold text-white mb-1">{eqName}</h3>
                  <p className="text-sm text-slate-400">
                    {inspection.date_performed 
                      ? new Date(inspection.date_performed).toLocaleDateString('ru-RU')
                      : 'Дата не указана'}
                    {' • '}
                    Статус: {inspection.status}
                  </p>
                </div>
                {existingReport && (
                  <span className="text-xs text-green-400 bg-green-500/10 px-2 py-1 rounded border border-green-500/20">
                    Отчет создан
                  </span>
                )}
              </div>

              {inspection.conclusion && (
                <p className="text-sm text-slate-300 mb-4 line-clamp-2">{inspection.conclusion}</p>
              )}

              <div className="flex flex-col sm:flex-row gap-2 flex-wrap">
                {/* Всегда показываем кнопки предпросмотра */}
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
                {/* Всегда показываем кнопки генерации, даже если отчет уже создан */}
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
                {/* Показываем кнопку скачивания, если отчет уже создан */}
                {existingReport && (
                  <button
                    onClick={() => handleDownloadReport(existingReport.id, existingReport.file_path)}
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

      {filteredInspections.length === 0 && (
        <div className="text-center text-slate-400 py-20">
          Диагностики не найдены
        </div>
      )}

      {/* Модальное окно предпросмотра */}
      {previewData && (
        <div className="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-2 md:p-4">
          <div className="bg-slate-800 rounded-xl border border-slate-700 w-full max-w-4xl max-h-[95vh] md:max-h-[90vh] overflow-hidden flex flex-col">
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
                <h3 className="text-base md:text-lg font-bold text-white mb-3 flex items-center gap-2">
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
                      <p className="text-white">{new Date(previewData.equipment.commissioning_date).toLocaleDateString('ru-RU')}</p>
                    </div>
                  )}
                </div>
              </div>

              {/* Инспекция */}
              <div className="bg-slate-900 p-4 rounded-lg">
                <h3 className="text-lg font-bold text-white mb-3 flex items-center gap-2">
                  <CheckCircle size={20} className="text-green-400" />
                  Данные диагностики
                </h3>
                <div className="space-y-2 text-sm">
                  {previewData.inspection.date_performed && (
                    <div>
                      <span className="text-slate-400">Дата проведения:</span>
                      <p className="text-white">{new Date(previewData.inspection.date_performed).toLocaleDateString('ru-RU')}</p>
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

              {/* Методы НК */}
              <div className="bg-slate-900 p-4 rounded-lg">
                <h3 className="text-lg font-bold text-white mb-3 flex items-center gap-2">
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
                      <div key={idx} className="bg-slate-800 p-3 rounded border border-slate-700">
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
                <div className="bg-slate-900 p-4 rounded-lg">
                  <h3 className="text-lg font-bold text-white mb-3 flex items-center gap-2">
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
                        <p className="text-white">{new Date(previewData.resource.resource_end_date).toLocaleDateString('ru-RU')}</p>
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
                        <p className="text-white">{new Date(previewData.resource.extension_date).toLocaleDateString('ru-RU')}</p>
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
                    <span className="hidden sm:inline">Сгенерировать PDF</span>
                    <span className="sm:hidden">PDF</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Список всех отчетов */}
      <div className="mt-8">
        <h2 className="text-xl font-bold text-white mb-4">Все отчеты</h2>
        <div className="space-y-2">
          {reports.map((report) => (
            <div
              key={report.id}
              className="bg-slate-800 p-3 rounded-lg border border-slate-700 flex justify-between items-center"
            >
              <div>
                <p className="text-white font-bold">{report.title}</p>
                <p className="text-sm text-slate-400">
                  {report.report_type === 'TECHNICAL_REPORT' ? 'Технический отчет' : 
                   report.report_type === 'EXPERTISE' ? 'Экспертиза ПБ' : 'Отчет'}
                  {' • '}
                  {new Date(report.created_at).toLocaleDateString('ru-RU')}
                  {' • '}
                  Статус: {report.status}
                </p>
              </div>
              <button
                onClick={() => handleDownloadReport(report.id, report.file_path)}
                className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20"
              >
                <Download size={16} />
                Скачать
              </button>
            </div>
          ))}
        </div>
        {reports.length === 0 && (
          <p className="text-slate-400 text-center py-8">Отчеты не найдены</p>
        )}
      </div>
    </div>
  );
};

export default ReportGeneration;



