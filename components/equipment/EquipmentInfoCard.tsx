import React, { useEffect, useState } from 'react';
import {
  X,
  Users,
  Settings,
  FileText,
  Wrench,
} from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { API_BASE } from '../../constants';
import type { AssignedEngineerRecord, HierarchyInfoType, InfoModalState } from './types';

export interface EquipmentInfoCardProps {
  modal: InfoModalState;
  onClose: () => void;
  onAssignEngineers: (type: HierarchyInfoType, id: string, name: string) => void;
  assignedEngineers: AssignedEngineerRecord[];
}

interface EquipmentDetail {
  serial_number?: string;
  location?: string;
  commissioning_date?: string;
  type_name?: string;
  attributes?: Record<string, unknown>;
}

interface InspectionHistoryItem {
  id: string;
  inspection_type?: string;
  inspection_date?: string;
  inspector_name?: string;
  status?: string;
}

interface RepairJournalItem {
  id: string;
  repair_type?: string;
  repair_date?: string;
  description?: string;
  cost?: string | number;
}

interface ReportItem {
  id: string;
  title?: string;
  report_type?: string;
  inspector_name?: string;
  created_at?: string;
  file_path?: string;
}

const EquipmentInfoCard: React.FC<EquipmentInfoCardProps> = ({
  modal,
  onClose,
  onAssignEngineers,
  assignedEngineers,
}) => {
  const { getToken } = useAuth();
  const [equipmentData, setEquipmentData] = useState<EquipmentDetail | null>(null);
  const [inspectionHistory, setInspectionHistory] = useState<InspectionHistoryItem[]>([]);
  const [repairJournal, setRepairJournal] = useState<RepairJournalItem[]>([]);
  const [reports, setReports] = useState<ReportItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (modal.type === 'equipment') {
      loadEquipmentData();
    } else {
      setLoading(false);
    }
  }, [modal.id, modal.type]);

  const loadEquipmentData = async () => {
    try {
      const token = getToken();
      const headers: HeadersInit = { Authorization: `Bearer ${token}` };

      const [eqRes, historyRes, repairRes, reportsRes] = await Promise.all([
        fetch(`${API_BASE}/api/equipment/${modal.id}`, { headers }).catch(() => null),
        fetch(`${API_BASE}/api/equipment/${modal.id}/inspection-history`, { headers }).catch(
          () => null
        ),
        fetch(`${API_BASE}/api/equipment/${modal.id}/repair-journal`, { headers }).catch(
          () => null
        ),
        fetch(`${API_BASE}/api/reports?equipment_id=${modal.id}`, { headers }).catch(() => null),
      ]);

      if (eqRes && eqRes.ok) {
        const eqData = (await eqRes.json()) as EquipmentDetail;
        setEquipmentData(eqData);
      }

      if (historyRes && historyRes.ok) {
        const historyData = (await historyRes.json()) as { items?: InspectionHistoryItem[] };
        setInspectionHistory(historyData.items || []);
      }

      if (repairRes && repairRes.ok) {
        const repairData = (await repairRes.json()) as { items?: RepairJournalItem[] };
        setRepairJournal(repairData.items || []);
      }

      if (reportsRes && reportsRes.ok) {
        const reportsData = (await reportsRes.json()) as { items?: ReportItem[] };
        setReports(reportsData.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки данных оборудования:', error);
    } finally {
      setLoading(false);
    }
  };

  if (modal.type !== 'equipment') {
    return (
      <div
        className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
        onClick={onClose}
        role="presentation"
      >
        <div
          className="bg-app-panel rounded-xl p-6 max-w-lg w-full mx-4 max-h-[80vh] overflow-y-auto"
          onClick={(e) => e.stopPropagation()}
          role="dialog"
          aria-modal="true"
        >
          <div className="flex justify-between items-center mb-4">
            <h2 className="text-xl font-bold text-app-text">
              {modal.type === 'enterprise'
                ? 'Предприятие'
                : modal.type === 'branch'
                  ? 'Филиал'
                  : 'Цех'}
              : {modal.name}
            </h2>
            <button type="button" onClick={onClose} className="text-app-text3 hover:text-app-text">
              <X size={24} />
            </button>
          </div>

          <div className="space-y-4">
            <div>
              <h3 className="text-lg font-semibold text-app-text mb-3 flex items-center gap-2">
                <Users className="text-accent" size={20} />
                Назначенные инженеры ({assignedEngineers.length})
              </h3>
              {assignedEngineers.length === 0 ? (
                <p className="text-app-text3">Инженеры не назначены</p>
              ) : (
                <div className="space-y-2">
                  {assignedEngineers.map((engineer) => (
                    <div
                      key={engineer.user_id}
                      className="bg-app-deep rounded-lg p-3 border border-app-line"
                    >
                      <div className="text-white font-medium">
                        {engineer.full_name || engineer.username}
                      </div>
                      {engineer.email && (
                        <div className="text-sm text-app-text3">{engineer.email}</div>
                      )}
                      {engineer.granted_at && (
                        <div className="text-xs text-app-text3 mt-1">
                          Назначен: {new Date(engineer.granted_at).toLocaleDateString('ru-RU')}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => {
                  onClose();
                  onAssignEngineers(modal.type, modal.id, modal.name);
                }}
                className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600 flex items-center justify-center gap-2"
              >
                <Users size={18} />
                Назначить инженеров
              </button>
              <button
                type="button"
                onClick={onClose}
                className="flex-1 bg-app-soft px-4 py-2 rounded-lg text-app-text font-bold hover:bg-app-softer"
              >
                Закрыть
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      onClick={onClose}
      role="presentation"
    >
      <div
        className="bg-app-panel rounded-xl p-6 max-w-4xl w-full mx-4 max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
      >
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold text-app-text flex items-center gap-2">
            <Settings className="text-accent" size={24} />
            {modal.name}
          </h2>
          <button type="button" onClick={onClose} className="text-app-text3 hover:text-app-text">
            <X size={24} />
          </button>
        </div>

        {loading ? (
          <div className="text-center text-app-text3 py-10">Загрузка...</div>
        ) : (
          <div className="space-y-6">
            {equipmentData && (
              <div className="bg-app-deep rounded-lg p-4 border border-app-line">
                <h3 className="text-lg font-semibold text-app-text mb-3 flex items-center gap-2">
                  <Settings className="text-accent" size={20} />
                  Характеристики
                </h3>
                <div className="grid grid-cols-2 gap-4">
                  {equipmentData.serial_number && (
                    <div>
                      <p className="text-sm text-app-text3">Серийный номер</p>
                      <p className="text-white font-medium">{equipmentData.serial_number}</p>
                    </div>
                  )}
                  {equipmentData.location && (
                    <div>
                      <p className="text-sm text-app-text3">Местоположение</p>
                      <p className="text-white font-medium">{equipmentData.location}</p>
                    </div>
                  )}
                  {equipmentData.commissioning_date && (
                    <div>
                      <p className="text-sm text-app-text3">Дата ввода в эксплуатацию</p>
                      <p className="text-white font-medium">
                        {new Date(equipmentData.commissioning_date).toLocaleDateString('ru-RU')}
                      </p>
                    </div>
                  )}
                  {equipmentData.type_name && (
                    <div>
                      <p className="text-sm text-app-text3">Тип оборудования</p>
                      <p className="text-white font-medium">{equipmentData.type_name}</p>
                    </div>
                  )}
                </div>
                {equipmentData.attributes &&
                  Object.keys(equipmentData.attributes).length > 0 && (
                    <div className="mt-4">
                      <p className="text-sm text-app-text3 mb-2">Дополнительные характеристики</p>
                      <div className="bg-app-deep rounded p-3">
                        <pre className="text-xs text-app-text2 whitespace-pre-wrap">
                          {JSON.stringify(equipmentData.attributes, null, 2)}
                        </pre>
                      </div>
                    </div>
                  )}
              </div>
            )}

            <div className="bg-app-deep rounded-lg p-4 border border-app-line">
              <h3 className="text-lg font-semibold text-app-text mb-3 flex items-center gap-2">
                <FileText className="text-accent" size={20} />
                История обследований ({inspectionHistory.length})
              </h3>
              {inspectionHistory.length === 0 ? (
                <p className="text-app-text3">Обследования не проводились</p>
              ) : (
                <div className="space-y-2">
                  {inspectionHistory.slice(0, 10).map((inspection) => (
                    <div key={inspection.id} className="bg-app-deep rounded p-3 border border-app-line">
                      <div className="flex justify-between items-start">
                        <div>
                          <p className="text-white font-medium">
                            {inspection.inspection_type || 'Обследование'}
                          </p>
                          {inspection.inspection_date && (
                            <p className="text-sm text-app-text3">
                              {new Date(inspection.inspection_date).toLocaleDateString('ru-RU')}
                            </p>
                          )}
                          {inspection.inspector_name && (
                            <p className="text-xs text-app-text3 mt-1">
                              Инженер: {inspection.inspector_name}
                            </p>
                          )}
                        </div>
                        {inspection.status && (
                          <span
                            className={`px-2 py-1 rounded text-xs ${
                              inspection.status === 'COMPLETED'
                                ? 'bg-green-500/20 text-green-400'
                                : inspection.status === 'IN_PROGRESS'
                                  ? 'bg-blue-500/20 text-blue-400'
                                  : 'bg-yellow-500/20 text-yellow-400'
                            }`}
                          >
                            {inspection.status}
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="bg-app-deep rounded-lg p-4 border border-app-line">
              <h3 className="text-lg font-semibold text-app-text mb-3 flex items-center gap-2">
                <Wrench className="text-accent" size={20} />
                Журнал ремонтов ({repairJournal.length})
              </h3>
              {repairJournal.length === 0 ? (
                <p className="text-app-text3">Ремонты не проводились</p>
              ) : (
                <div className="space-y-2">
                  {repairJournal.slice(0, 10).map((repair) => (
                    <div key={repair.id} className="bg-app-deep rounded p-3 border border-app-line">
                      <div className="flex justify-between items-start">
                        <div>
                          <p className="text-white font-medium">{repair.repair_type || 'Ремонт'}</p>
                          {repair.repair_date && (
                            <p className="text-sm text-app-text3">
                              {new Date(repair.repair_date).toLocaleDateString('ru-RU')}
                            </p>
                          )}
                          {repair.description && (
                            <p className="text-sm text-app-text2 mt-1">{repair.description}</p>
                          )}
                        </div>
                        {repair.cost != null && (
                          <span className="text-accent font-semibold">{repair.cost} ₽</span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="bg-app-deep rounded-lg p-4 border border-app-line">
              <h3 className="text-lg font-semibold text-app-text mb-3 flex items-center gap-2">
                <FileText className="text-accent" size={20} />
                Документы по диагностике ({reports.length})
              </h3>
              {reports.length === 0 ? (
                <p className="text-app-text3">Документы отсутствуют</p>
              ) : (
                <div className="space-y-2">
                  {reports.map((report) => (
                    <div
                      key={report.id}
                      className="bg-app-deep rounded p-3 border border-app-line flex items-center justify-between"
                    >
                      <div>
                        <p className="text-white font-medium">
                          {report.title || report.report_type}
                        </p>
                        {report.inspector_name && (
                          <p className="text-sm text-app-text3">
                            Инженер: {report.inspector_name}
                          </p>
                        )}
                        {report.created_at && (
                          <p className="text-xs text-app-text3">
                            {new Date(report.created_at).toLocaleDateString('ru-RU')}
                          </p>
                        )}
                      </div>
                      <div className="flex gap-2">
                        {report.file_path && (
                          <a
                            href={`${API_BASE}/${report.file_path}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="bg-accent px-3 py-1 rounded text-white text-sm hover:bg-blue-600"
                          >
                            Скачать PDF
                          </a>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="bg-app-deep rounded-lg p-4 border border-app-line">
              <h3 className="text-lg font-semibold text-app-text mb-3 flex items-center gap-2">
                <Users className="text-accent" size={20} />
                Назначенные инженеры ({assignedEngineers.length})
              </h3>
              {assignedEngineers.length === 0 ? (
                <p className="text-app-text3">Инженеры не назначены</p>
              ) : (
                <div className="space-y-2">
                  {assignedEngineers.map((engineer) => (
                    <div
                      key={engineer.user_id}
                      className="bg-app-deep rounded p-3 border border-app-line"
                    >
                      <div className="text-white font-medium">
                        {engineer.full_name || engineer.username}
                      </div>
                      {engineer.email && (
                        <div className="text-sm text-app-text3">{engineer.email}</div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => {
                  onClose();
                  onAssignEngineers(modal.type, modal.id, modal.name);
                }}
                className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600 flex items-center justify-center gap-2"
              >
                <Users size={18} />
                Назначить инженеров
              </button>
              <button
                type="button"
                onClick={onClose}
                className="flex-1 bg-app-soft px-4 py-2 rounded-lg text-app-text font-bold hover:bg-app-softer"
              >
                Закрыть
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default EquipmentInfoCard;
