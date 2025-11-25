import React, { useState, useEffect } from 'react';
import { FileText, Download, FileCheck, Sparkles, Search } from 'lucide-react';

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

const ReportGeneration = () => {
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      const [inspRes, eqRes, repRes] = await Promise.all([
        fetch(`${API_BASE}/api/inspections`),
        fetch(`${API_BASE}/api/equipment`),
        fetch(`${API_BASE}/api/reports`)
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

  const generateReport = async (inspectionId: string, reportType: string) => {
    setGenerating(inspectionId);
    try {
      const response = await fetch(`${API_BASE}/api/reports/generate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          inspection_id: inspectionId,
          report_type: reportType,
          title: `${reportType === 'TECHNICAL_REPORT' ? 'Технический отчет' : 'Экспертиза ПБ'} для диагностики`
        })
      });

      if (response.ok) {
        const data = await response.json();
        alert('Отчет успешно сгенерирован!');
        loadData();
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось сгенерировать отчет'}`);
      }
    } catch (error) {
      console.error('Ошибка генерации отчета:', error);
      alert('Ошибка генерации отчета');
    } finally {
      setGenerating(null);
    }
  };

  const handleDownloadReport = async (reportId: string, filename: string) => {
    try {
      const response = await fetch(`${API_BASE}/api/reports/${reportId}/download`);
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
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">Генерация отчетов и экспертиз</h1>
        <div className="relative w-64">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
          <input
            type="text"
            placeholder="Поиск по оборудованию..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full bg-slate-800 border border-slate-700 rounded-lg pl-10 pr-4 py-2 text-white placeholder-slate-500"
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

              <div className="flex gap-2">
                {!existingReport ? (
                  <>
                    <button
                      onClick={() => generateReport(inspection.id, 'TECHNICAL_REPORT')}
                      disabled={generating === inspection.id}
                      className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20 disabled:opacity-50"
                    >
                      {generating === inspection.id ? (
                        <>
                          <Sparkles size={16} className="animate-spin" />
                          Генерация...
                        </>
                      ) : (
                        <>
                          <FileText size={16} />
                          Создать технический отчет
                        </>
                      )}
                    </button>
                    <button
                      onClick={() => generateReport(inspection.id, 'EXPERTISE')}
                      disabled={generating === inspection.id}
                      className="bg-blue-500/10 text-blue-400 border border-blue-500/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-blue-500/20 disabled:opacity-50"
                    >
                      {generating === inspection.id ? (
                        <>
                          <Sparkles size={16} className="animate-spin" />
                          Генерация...
                        </>
                      ) : (
                        <>
                          <FileCheck size={16} />
                          Создать экспертизу ПБ
                        </>
                      )}
                    </button>
                  </>
                ) : (
                  <button
                    onClick={() => handleDownloadReport(existingReport.id, existingReport.title)}
                    className="bg-green-500/10 text-green-400 border border-green-500/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-green-500/20"
                  >
                    <Download size={16} />
                    Скачать {existingReport.report_type === 'TECHNICAL_REPORT' ? 'отчет' : 'экспертизу'}
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
                onClick={() => handleDownloadReport(report.id, report.title)}
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



