import React, { useState, useEffect } from 'react';
import { Download, FileText, Calendar, MapPin, Search, Filter } from 'lucide-react';

interface Equipment {
  id: string;
  name: string;
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
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [selectedEquipment, setSelectedEquipment] = useState<Equipment | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [loading, setLoading] = useState(true);

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      // Загрузка оборудования
      const eqResponse = await fetch(`${API_BASE}/api/equipment`);
      const eqData = await eqResponse.json();
      setEquipment(eqData.items || []);

      // Загрузка диагностик
      const inspResponse = await fetch(`${API_BASE}/api/inspections`);
      const inspData = await inspResponse.json();
      setInspections(inspData.items || []);

      // Загрузка отчетов
      const repResponse = await fetch(`${API_BASE}/api/reports`);
      const repData = await repResponse.json();
      setReports(repData.items || []);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
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

  const getEquipmentInspections = (equipmentId: string) => {
    return inspections.filter(ins => ins.equipment_id === equipmentId);
  };

  const getEquipmentReports = (equipmentId: string) => {
    return reports.filter(rep => rep.equipment_id === equipmentId);
  };

  const filteredEquipment = equipment.filter(eq =>
    eq.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    (eq.location && eq.location.toLowerCase().includes(searchTerm.toLowerCase())) ||
    (eq.serial_number && eq.serial_number.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">Клиентский портал</h1>
        <div className="relative w-64">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
          <input
            type="text"
            placeholder="Поиск оборудования..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full bg-slate-800 border border-slate-700 rounded-lg pl-10 pr-4 py-2 text-white placeholder-slate-500"
          />
        </div>
      </div>

      {/* Список оборудования */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredEquipment.map((eq) => {
          const eqInspections = getEquipmentInspections(eq.id);
          const eqReports = getEquipmentReports(eq.id);
          
          return (
            <div
              key={eq.id}
              className="bg-slate-800 p-4 rounded-xl border border-slate-700 hover:border-accent/50 transition-colors cursor-pointer"
              onClick={() => setSelectedEquipment(eq)}
            >
              <div className="flex justify-between items-start mb-2">
                <h3 className="text-lg font-bold text-white">{eq.name}</h3>
                <span className="text-xs text-slate-400 bg-slate-700 px-2 py-1 rounded">
                  {eqInspections.length} диагностик
                </span>
              </div>
              
              {eq.location && (
                <div className="flex items-center gap-2 text-accent mb-2">
                  <MapPin size={14} />
                  <span className="text-sm">{eq.location}</span>
                </div>
              )}
              
              {eq.serial_number && (
                <p className="text-sm text-slate-400 mb-2">№ {eq.serial_number}</p>
              )}

              <div className="mt-3 pt-3 border-t border-slate-700">
                <p className="text-xs text-slate-400 mb-1">Отчетов: {eqReports.length}</p>
                {eqReports.length > 0 && (
                  <div className="flex gap-2 flex-wrap">
                    {eqReports.slice(0, 2).map((report) => (
                      <button
                        key={report.id}
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
        <div className="text-center text-slate-400 py-20">
          Оборудование не найдено
        </div>
      )}

      {/* Модальное окно с деталями */}
      {selectedEquipment && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setSelectedEquipment(null)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-4xl w-full mx-4 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">{selectedEquipment.name}</h2>
              <button onClick={() => setSelectedEquipment(null)} className="text-slate-400 hover:text-white">✕</button>
            </div>

            {selectedEquipment.location && (
              <div className="flex items-center gap-2 text-accent mb-4">
                <MapPin size={16} />
                <span>{selectedEquipment.location}</span>
              </div>
            )}

            {/* Диагностики */}
            <div className="mb-6">
              <h3 className="text-lg font-bold text-white mb-3">История диагностик</h3>
              {getEquipmentInspections(selectedEquipment.id).length === 0 ? (
                <p className="text-slate-400">Диагностики не найдены</p>
              ) : (
                <div className="space-y-3">
                  {getEquipmentInspections(selectedEquipment.id).map((insp) => (
                    <div key={insp.id} className="bg-slate-900 p-4 rounded-lg border border-slate-700">
                      <div className="flex justify-between items-start mb-2">
                        <div>
                          <p className="text-white font-bold">
                            {insp.date_performed ? new Date(insp.date_performed).toLocaleDateString('ru-RU') : 'Дата не указана'}
                          </p>
                          <p className="text-sm text-slate-400">Статус: {insp.status}</p>
                        </div>
                      </div>
                      {insp.conclusion && (
                        <p className="text-slate-300 mt-2 text-sm">{insp.conclusion}</p>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Отчеты */}
            <div>
              <h3 className="text-lg font-bold text-white mb-3">Отчеты и экспертизы</h3>
              {getEquipmentReports(selectedEquipment.id).length === 0 ? (
                <p className="text-slate-400">Отчеты не найдены</p>
              ) : (
                <div className="space-y-2">
                  {getEquipmentReports(selectedEquipment.id).map((report) => (
                    <div key={report.id} className="bg-slate-900 p-3 rounded-lg border border-slate-700 flex justify-between items-center">
                      <div>
                        <p className="text-white font-bold">{report.title}</p>
                        <p className="text-sm text-slate-400">
                          {report.report_type === 'TECHNICAL_REPORT' ? 'Технический отчет' : 
                           report.report_type === 'EXPERTISE' ? 'Экспертиза ПБ' : 'Отчет'}
                          {' • '}
                          {new Date(report.created_at).toLocaleDateString('ru-RU')}
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
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ClientPortal;



