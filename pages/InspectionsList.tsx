import React, { useEffect, useMemo, useState } from 'react';
import { Search, Filter, FileText, Package, Calendar, User, MapPin, Eye, Download, Trash2, CheckCircle2 } from 'lucide-react';
import { checklistDocumentNames } from './checklistDocumentNames';
import { useAuth } from '../contexts/AuthContext';

interface Inspection {
  id: string;
  equipment_id: string;
  equipment_name?: string;
  equipment_location?: string;
  data: any;
  conclusion?: string;
  status: string;
  date_performed?: string;
  created_at: string;
  inspector_id?: string;
  inspector_name?: string;
}

interface DocumentFile {
  id: string;
  document_number: string;
  file_name: string;
  file_size: number;
  file_type?: string;
  mime_type?: string;
  created_at?: string;
}

interface InspectionQuestionnaireInfo {
  questionnaire_id: string | null;
  document_files: DocumentFile[];
}

interface Equipment {
  id: string;
  name: string;
  location?: string;
}

const InspectionsList = () => {
  const { user } = useAuth();
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedEquipment, setSelectedEquipment] = useState<string>('all');
  const [selectedStatus, setSelectedStatus] = useState<string>('all');
  const [selectedInspection, setSelectedInspection] = useState<Inspection | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [questionnaireInfo, setQuestionnaireInfo] = useState<Record<string, InspectionQuestionnaireInfo>>({});
  const [loadingQuestionnaire, setLoadingQuestionnaire] = useState(false);
  const [cleanupInspectionsDays, setCleanupInspectionsDays] = useState<number>(180);
  const [selectedInspections, setSelectedInspections] = useState<Set<string>>(new Set());
  const [isProcessing, setIsProcessing] = useState(false);

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    const init = async () => {
      await loadEquipment();
      await loadInspections();
    };
    init();
  }, []);

  useEffect(() => {
    loadInspections();
  }, [selectedEquipment, selectedStatus]);

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
      }

      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const response = await fetch(url, { headers });
      const data = await response.json();
      let inspectionsList = data.items || [];

      // Фильтрация по статусу
      if (selectedStatus !== 'all') {
        inspectionsList = inspectionsList.filter((insp: Inspection) => insp.status === selectedStatus);
      }

      // Обогащение данными об оборудовании (API уже возвращает equipment_name и equipment_location)
      // Но если их нет, используем локальный кэш
      for (const insp of inspectionsList) {
        if (!insp.equipment_name || !insp.equipment_location) {
          const eq = equipment.find(e => e.id === insp.equipment_id);
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
        setSelectedInspection((prev) => (prev ? ({ ...prev, status: 'APPROVED' } as any) : prev));
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
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ inspection_ids: Array.from(selectedInspections) })
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
            // Если не JSON, используем текст ответа
            errorMessage = text || errorMessage;
          }
        } catch (parseError) {
          // Если не удалось прочитать ответ, используем статус
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
        errorMessage = (e as any).message || (e as any).detail || String(e);
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
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ inspection_ids: Array.from(selectedInspections), archive: true })
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
      const errorMessage = e instanceof Error ? e.message : (typeof e === 'string' ? e : JSON.stringify(e));
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
      const data = await res.json().catch(() => null as any);
      alert(`Удалено чек-листов: ${data?.deleted ?? 'OK'} (и отчетов: ${data?.reports_deleted ?? 0})`);
      await loadInspections();
    } catch (e) {
      alert(`Ошибка очистки: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const loadInspectionQuestionnaireInfo = async (inspectionId: string) => {
    // Кэшируем, чтобы не дергать API повторно при каждом открытии
    if (questionnaireInfo[inspectionId]) return;

    setLoadingQuestionnaire(true);
    try {
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const response = await fetch(`${API_BASE}/api/inspections/${inspectionId}/questionnaire`, { headers });
      if (!response.ok) return;

      const data = await response.json();
      setQuestionnaireInfo(prev => ({
        ...prev,
        [inspectionId]: {
          questionnaire_id: data.questionnaire_id ?? null,
          document_files: data.document_files ?? [],
        }
      }));
    } catch (e) {
      // не блокируем UI
    } finally {
      setLoadingQuestionnaire(false);
    }
  };

  const filteredInspections = inspections.filter(insp => {
    const matchesSearch = 
      insp.equipment_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      insp.conclusion?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      insp.id.toLowerCase().includes(searchTerm.toLowerCase());
    return matchesSearch;
  });

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'SIGNED':
        return 'bg-green-500/20 text-green-400 border-green-500/30';
      case 'DRAFT':
        return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30';
      case 'REJECTED':
        return 'bg-red-500/20 text-red-400 border-red-500/30';
      default:
        return 'bg-slate-500/20 text-slate-400 border-slate-500/30';
    }
  };

  const getStatusLabel = (status: string) => {
    switch (status) {
      case 'SIGNED':
        return 'Подписан';
      case 'DRAFT':
        return 'Черновик';
      case 'REJECTED':
        return 'Отклонен';
      default:
        return status;
    }
  };

  const formatDate = (dateString?: string) => {
    if (!dateString) return 'Не указана';
    try {
      const date = new Date(dateString);
      return date.toLocaleDateString('ru-RU', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch {
      return dateString;
    }
  };

  const renderInspectionDetails = (insp: Inspection) => {
    const data = insp.data || {};
    const docsInfo = questionnaireInfo[insp.id];
    const docsFilesByNumber: Record<string, DocumentFile[]> = {};
    if (docsInfo?.document_files) {
      for (const f of docsInfo.document_files) {
        const k = String(f.document_number);
        if (!docsFilesByNumber[k]) docsFilesByNumber[k] = [];
        docsFilesByNumber[k].push(f);
      }
    }

    // Вложения (не входят в перечень документов 1..17)
    const attachmentLabels: Record<string, string> = {
      factory_plate_photo: 'Фото заводской таблички',
      control_scheme_image: 'Схема контроля / карта обследования',
    };
    const attachmentKeys = Object.keys(docsFilesByNumber).filter((k) => k in attachmentLabels);

    // Прочие вложения: все ключи, которые НЕ относятся к 1..17 и НЕ являются системными (табличка/схема).
    const otherAttachmentKeys = Object.keys(docsFilesByNumber)
      .filter((k) => {
        if (k in attachmentLabels) return false;
        const n = Number(k);
        // 1..17 считаем "документами"
        if (!Number.isNaN(n) && Number.isFinite(n) && n >= 1 && n <= 17) return false;
        return true;
      })
      .sort((a, b) => a.localeCompare(b, 'en'));
    
    return (
      <div className="space-y-6">
        {/* Основная информация */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Оборудование</label>
            <div className="flex items-center gap-2">
              <Package size={16} className="text-accent" />
              <span className="font-medium">{insp.equipment_name || 'Не указано'}</span>
            </div>
          </div>
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Местоположение</label>
            <div className="flex items-center gap-2">
              <MapPin size={16} className="text-accent" />
              <span>{insp.equipment_location || 'Не указано'}</span>
            </div>
          </div>
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Дата обследования</label>
            <div className="flex items-center gap-2">
              <Calendar size={16} className="text-accent" />
              <span>{formatDate(insp.date_performed)}</span>
            </div>
          </div>
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Статус</label>
            <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium border ${getStatusColor(insp.status)}`}>
              {getStatusLabel(insp.status)}
            </span>
          </div>
        </div>

        {/* Данные чек-листа */}
        {data.executors && (
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Исполнители</label>
            <p className="text-white">{data.executors}</p>
          </div>
        )}

        {data.organization && (
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Организация</label>
            <p className="text-white">{data.organization}</p>
          </div>
        )}

        {/* Документы */}
        {data.documents && (
          <div>
            <label className="text-xs text-slate-400 mb-2 block">Перечень рассмотренных документов</label>
            <div className="space-y-2">
              {Object.entries(data.documents).map(([key, value]: [string, any]) => (
                <div key={key} className="flex items-center justify-between p-2 bg-secondary/50 rounded">
                  <div className="flex-1 pr-3">
                    <div className="text-sm text-slate-300">
                      {checklistDocumentNames[String(key)] ?? `Документ ${key}`}
                    </div>
                    {docsFilesByNumber[String(key)]?.length ? (
                      <div className="mt-1 flex flex-wrap gap-2">
                        {docsFilesByNumber[String(key)].map((f) => (
                          <a
                            key={f.id}
                            className="text-xs text-accent hover:underline inline-flex items-center gap-1 px-2 py-1 bg-accent/10 hover:bg-accent/20 rounded"
                            href={`${API_BASE}/api/questionnaires/${docsInfo?.questionnaire_id}/documents/${String(key)}/view`}
                            target="_blank"
                            rel="noreferrer"
                            title={f.file_name}
                          >
                            <Download size={14} />
                            {f.file_name || 'Открыть файл'}
                            {f.file_size ? ` (${(f.file_size / 1024).toFixed(1)} КБ)` : ''}
                          </a>
                        ))}
                      </div>
                    ) : (
                      <div className="mt-1 text-xs text-slate-500">Файл не приложен</div>
                    )}
                  </div>

                  <span className={`px-2 py-1 rounded text-xs ${value ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
                    {value ? 'Да' : 'Нет'}
                  </span>
                </div>
              ))}
            </div>
            {loadingQuestionnaire && (
              <div className="text-xs text-slate-500 mt-2">Загрузка вложений документов...</div>
            )}
            {docsInfo?.questionnaire_id && Object.keys(docsFilesByNumber).length === 0 && !loadingQuestionnaire && (
              <div className="text-xs text-slate-500 mt-2">Документы не загружены</div>
            )}
          </div>
        )}

        {/* Карта обследования */}
        {data.vesselName && (
          <div>
            <label className="text-xs text-slate-400 mb-2 block">Карта обследования</label>
            <div className="grid grid-cols-2 gap-4 p-4 bg-secondary/50 rounded">
              <div>
                <span className="text-xs text-slate-400">Наименование сосуда</span>
                <p className="text-white font-medium">{data.vesselName}</p>
              </div>
              {data.serialNumber && (
                <div>
                  <span className="text-xs text-slate-400">Заводской номер</span>
                  <p className="text-white font-medium">{data.serialNumber}</p>
                </div>
              )}
              {data.regNumber && (
                <div>
                  <span className="text-xs text-slate-400">Регистрационный номер</span>
                  <p className="text-white font-medium">{data.regNumber}</p>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Приложенные файлы (фото таблички, схема контроля и т.п.) */}
        {docsInfo?.questionnaire_id && attachmentKeys.length > 0 && (
          <div>
            <label className="text-xs text-slate-400 mb-2 block">Приложенные файлы</label>
            <div className="space-y-2">
              {attachmentKeys.map((k) => (
                <div key={k} className="flex items-center justify-between p-2 bg-secondary/50 rounded">
                  <div className="flex-1 pr-3">
                    <div className="text-sm text-slate-300 font-medium">{attachmentLabels[k] || k}</div>
                    <div className="mt-1 flex flex-wrap gap-2">
                      {(docsFilesByNumber[k] || []).map((f) => (
                        <a
                          key={f.id}
                          className="text-xs text-accent hover:underline inline-flex items-center gap-1 px-2 py-1 bg-accent/10 hover:bg-accent/20 rounded"
                          href={`${API_BASE}/api/questionnaires/${docsInfo.questionnaire_id}/documents/${k}/view`}
                          target="_blank"
                          rel="noreferrer"
                          title={f.file_name}
                        >
                          <Download size={14} />
                          {f.file_name || 'Открыть'}
                          {f.file_size ? ` (${(f.file_size / 1024).toFixed(1)} КБ)` : ''}
                        </a>
                      ))}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Прочие вложения */}
        {docsInfo?.questionnaire_id && otherAttachmentKeys.length > 0 && (
          <div>
            <label className="text-xs text-slate-400 mb-2 block">Прочие вложения</label>
            <div className="space-y-2">
              {otherAttachmentKeys.map((k) => (
                <div key={k} className="flex items-center justify-between p-2 bg-secondary/50 rounded">
                  <div className="flex-1 pr-3">
                    <div className="text-sm text-slate-300 font-medium">{k}</div>
                    <div className="mt-1 flex flex-wrap gap-2">
                      {(docsFilesByNumber[k] || []).map((f) => (
                        <a
                          key={f.id}
                          className="text-xs text-accent hover:underline inline-flex items-center gap-1 px-2 py-1 bg-accent/10 hover:bg-accent/20 rounded"
                          href={`${API_BASE}/api/questionnaires/${docsInfo.questionnaire_id}/documents/${k}/view`}
                          target="_blank"
                          rel="noreferrer"
                          title={f.file_name}
                        >
                          <Download size={14} />
                          {f.file_name || 'Открыть'}
                          {f.file_size ? ` (${(f.file_size / 1024).toFixed(1)} КБ)` : ''}
                        </a>
                      ))}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
        
        {/* Информация о документах, если они не загружены */}
        {!docsInfo?.questionnaire_id && (
          <div className="p-3 bg-yellow-500/10 border border-yellow-500/20 rounded">
            <p className="text-xs text-yellow-400">
              Документы привязаны к опросному листу. Для просмотра документов необходимо наличие опросного листа для данного оборудования.
            </p>
          </div>
        )}

        {/* Заключение */}
        {insp.conclusion && (
          <div>
            <label className="text-xs text-slate-400 mb-1 block">Заключение</label>
            <div className="p-4 bg-secondary/50 rounded">
              <p className="text-white whitespace-pre-wrap">{insp.conclusion}</p>
            </div>
          </div>
        )}

        {/* Дополнительные данные */}
        {Object.keys(data).length > 0 && (
          <details className="mt-4">
            <summary className="cursor-pointer text-sm text-slate-400 hover:text-white">
              Показать все данные
            </summary>
            <pre className="mt-2 p-4 bg-secondary/50 rounded text-xs overflow-auto text-slate-300">
              {JSON.stringify(data, null, 2)}
            </pre>
          </details>
        )}
      </div>
    );
  };

  return (
    <div className="space-y-6">
      {/* Заголовок */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <FileText className="text-accent" size={28} />
            Чек-листы диагностики
          </h1>
          <p className="text-slate-400 mt-1">Просмотр всех чек-листов, отправленных из мобильного приложения</p>
        </div>
      </div>

      {/* Фильтры и поиск */}
      <div className="bg-secondary/50 rounded-lg p-4 space-y-4">
        {selectedInspections.size > 0 && (
          <div className="flex items-center justify-between p-3 bg-accent/20 border border-accent/30 rounded-lg">
            <span className="text-white font-semibold">Выбрано: {selectedInspections.size}</span>
            <div className="flex gap-2">
              <button
                onClick={handleBulkArchive}
                disabled={isProcessing}
                className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm font-semibold disabled:opacity-50"
              >
                Отправить в архив
              </button>
              <button
                onClick={handleBulkDelete}
                disabled={isProcessing}
                className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-sm font-semibold disabled:opacity-50"
              >
                Удалить выбранные
              </button>
              <button
                onClick={() => setSelectedInspections(new Set())}
                className="px-4 py-2 bg-slate-600 hover:bg-slate-700 text-white rounded-lg text-sm font-semibold"
              >
                Снять выделение
              </button>
            </div>
          </div>
        )}
        <div className="flex flex-wrap gap-4">
          {/* Поиск */}
          <div className="flex-1 min-w-[200px]">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={18} />
              <input
                type="text"
                placeholder="Поиск по оборудованию, заключению..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full pl-10 pr-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
              />
            </div>
          </div>

          {/* Фильтр по оборудованию */}
          <div className="min-w-[200px]">
            <select
              value={selectedEquipment}
              onChange={(e) => setSelectedEquipment(e.target.value)}
              className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="all">Все оборудование</option>
              {equipment.map((eq) => (
                <option key={eq.id} value={eq.id}>
                  {eq.name}
                </option>
              ))}
            </select>
          </div>

          {/* Фильтр по статусу */}
          <div className="min-w-[150px]">
            <select
              value={selectedStatus}
              onChange={(e) => setSelectedStatus(e.target.value)}
              className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="all">Все статусы</option>
              <option value="DRAFT">Черновик</option>
              <option value="SIGNED">Подписан</option>
              <option value="REJECTED">Отклонен</option>
            </select>
          </div>

          <div className="flex items-center gap-2 sm:ml-auto">
            <select
              value={cleanupInspectionsDays}
              onChange={(e) => setCleanupInspectionsDays(parseInt(e.target.value, 10))}
              className="px-3 py-2 bg-primary border border-slate-600 rounded-lg text-white text-sm focus:outline-none focus:border-accent"
              title="Удалить чек-листы старше N дней"
            >
              <option value={30}>Старше 30 дней</option>
              <option value={90}>Старше 90 дней</option>
              <option value={180}>Старше 180 дней</option>
              <option value={365}>Старше 365 дней</option>
            </select>
            <button
              onClick={cleanupOldInspections}
              className="flex items-center gap-2 px-3 py-2 bg-red-500/10 hover:bg-red-500/20 border border-red-500/20 text-red-300 rounded-lg text-sm font-semibold"
              title="Удалить старые чек-листы"
            >
              <Trash2 size={16} />
              <span className="hidden sm:inline">Удалить старые чек-листы</span>
              <span className="sm:hidden">Очистить</span>
            </button>
          </div>
        </div>
      </div>

      {/* Список чек-листов */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-accent"></div>
          <p className="text-slate-400 mt-4">Загрузка чек-листов...</p>
        </div>
      ) : filteredInspections.length === 0 ? (
        <div className="text-center py-12 bg-secondary/50 rounded-lg">
          <FileText className="mx-auto text-slate-400 mb-4" size={48} />
          <p className="text-slate-400">Чек-листы не найдены</p>
        </div>
      ) : (
        <div className="space-y-3">
          {filteredInspections.map((insp) => (
            <div
              key={insp.id}
              className="bg-secondary/50 rounded-lg p-4 hover:bg-secondary/70 transition-colors border border-slate-700"
            >
              <div className="flex items-start justify-between gap-3">
                <input
                  type="checkbox"
                  checked={selectedInspections.has(insp.id)}
                  onChange={(e) => {
                    e.stopPropagation();
                    setSelectedInspections(prev => {
                      const newSet = new Set(prev);
                      if (newSet.has(insp.id)) {
                        newSet.delete(insp.id);
                      } else {
                        newSet.add(insp.id);
                      }
                      return newSet;
                    });
                  }}
                  onClick={(e) => e.stopPropagation()}
                  className="mt-1 rounded"
                />
                <div
                  className="flex-1 cursor-pointer"
                  onClick={() => {
                    setSelectedInspection(insp);
                    setShowDetails(true);
                    loadInspectionQuestionnaireInfo(insp.id);
                  }}
                >
                  <div className="flex items-center gap-3 mb-2">
                    <Package className="text-accent" size={20} />
                    <h3 className="font-semibold text-white">{insp.equipment_name || 'Неизвестное оборудование'}</h3>
                    <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium border ${getStatusColor(insp.status)}`}>
                      {getStatusLabel(insp.status)}
                    </span>
                  </div>
                  
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                    {insp.equipment_location && (
                      <div className="flex items-center gap-2 text-slate-400">
                        <MapPin size={14} />
                        <span>{insp.equipment_location}</span>
                      </div>
                    )}
                    <div className="flex items-center gap-2 text-slate-400">
                      <Calendar size={14} />
                      <span>{formatDate(insp.date_performed)}</span>
                    </div>
                    <div className="flex items-center gap-2 text-slate-400">
                      <FileText size={14} />
                      <span>ID: {insp.id.substring(0, 8)}...</span>
                    </div>
                    {insp.conclusion && (
                      <div className="text-slate-300 truncate">
                        {insp.conclusion.substring(0, 50)}...
                      </div>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                  {canApprove && String(insp.status || '').toUpperCase() !== 'APPROVED' && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        approveInspection(insp.id);
                      }}
                      className="p-2 rounded-lg text-green-300 hover:bg-green-500/10 border border-green-500/20"
                      title="Утвердить чек-лист"
                    >
                      <CheckCircle2 size={16} />
                    </button>
                  )}
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      deleteInspection(insp.id);
                    }}
                    className="p-2 rounded-lg text-red-300 hover:bg-red-500/10 border border-red-500/20"
                    title="Удалить чек-лист"
                  >
                    <Trash2 size={16} />
                  </button>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setSelectedInspection(insp);
                      setShowDetails(true);
                      loadInspectionQuestionnaireInfo(insp.id);
                    }}
                    className="p-2 text-slate-400 hover:text-accent hover:bg-secondary rounded transition-colors"
                    title="Просмотр деталей"
                  >
                    <Eye size={20} />
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Модальное окно с деталями */}
      {showDetails && selectedInspection && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setShowDetails(false)}>
          <div
            className="bg-secondary rounded-lg max-w-4xl w-full max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-secondary border-b border-slate-700 p-6 flex items-center justify-between">
              <h2 className="text-xl font-bold text-white flex items-center gap-2">
                <FileText className="text-accent" size={24} />
                Детали чек-листа
              </h2>
              <button
                onClick={() => setShowDetails(false)}
                className="text-slate-400 hover:text-white transition-colors"
              >
                ✕
              </button>
            </div>
            <div className="p-6">
              {renderInspectionDetails(selectedInspection)}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default InspectionsList;

