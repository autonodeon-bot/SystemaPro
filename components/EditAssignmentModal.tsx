import React, { useState, useEffect, useRef } from 'react';
import { X, Save, Loader2, Upload, FileText, Trash2 } from 'lucide-react';
import { API_BASE } from '../constants';
import { useToast } from '../contexts/ToastContext';
import { useAuth } from '../contexts/AuthContext';
import type { Assignment } from './AssignmentCard';

export interface EditAssignmentModalProps {
  assignment: Assignment;
  isOpen: boolean;
  onClose: () => void;
  onSaved: () => void;
}

const STATUS_OPTIONS = [
  { value: 'PENDING', label: 'Ожидает' },
  { value: 'IN_PROGRESS', label: 'В работе' },
  { value: 'COMPLETED', label: 'Завершено' },
  { value: 'CANCELLED', label: 'Отменено' },
];

const PRIORITY_OPTIONS = [
  { value: 'LOW', label: 'Низкий' },
  { value: 'NORMAL', label: 'Обычный' },
  { value: 'HIGH', label: 'Высокий' },
  { value: 'URGENT', label: 'Срочный' },
];

const EditAssignmentModal: React.FC<EditAssignmentModalProps> = ({ assignment, isOpen, onClose, onSaved }) => {
  const toast = useToast();
  const { hasRole } = useAuth();
  const canEditTemplate =
    hasRole('admin') || hasRole('chief_operator') || hasRole('operator');

  const [status, setStatus] = useState(assignment.status);
  const [priority, setPriority] = useState(assignment.priority);
  const [dueDate, setDueDate] = useState(assignment.due_date ? assignment.due_date.slice(0, 10) : '');
  const [description, setDescription] = useState(assignment.description || '');
  const [protocolTemplateId, setProtocolTemplateId] = useState(assignment.protocol_template_id || '');
  const [protocolTemplates, setProtocolTemplates] = useState<Array<{ id: string; name: string; category?: string }>>([]);
  const [contractNumber, setContractNumber] = useState(assignment.contract_number || '');
  const [contractDate, setContractDate] = useState(assignment.contract_date || '');
  const [workPeriodFrom, setWorkPeriodFrom] = useState(assignment.work_period_from || '');
  const [workPeriodTo, setWorkPeriodTo] = useState(assignment.work_period_to || '');
  const [workBasis, setWorkBasis] = useState(assignment.work_basis || '');
  const [techCardNumber, setTechCardNumber] = useState(assignment.tech_card_number || '');
  const [saving, setSaving] = useState(false);
  const [hasTechCardFile, setHasTechCardFile] = useState(!!assignment.has_tech_card_file);
  const [techCardFileName, setTechCardFileName] = useState(assignment.tech_card_file_name || '');
  const [uploadingFile, setUploadingFile] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!isOpen) return;
    setStatus(assignment.status);
    setPriority(assignment.priority);
    setDueDate(assignment.due_date ? assignment.due_date.slice(0, 10) : '');
    setDescription(assignment.description || '');
    setProtocolTemplateId(assignment.protocol_template_id || '');
    setContractNumber(assignment.contract_number || '');
    setContractDate(assignment.contract_date || '');
    setWorkPeriodFrom(assignment.work_period_from || '');
    setWorkPeriodTo(assignment.work_period_to || '');
    setWorkBasis(assignment.work_basis || '');
    setTechCardNumber(assignment.tech_card_number || '');
    setHasTechCardFile(!!assignment.has_tech_card_file);
    setTechCardFileName(assignment.tech_card_file_name || '');
  }, [isOpen, assignment]);

  const handleUploadTechCardFile = async (file: File) => {
    setUploadingFile(true);
    try {
      const token = localStorage.getItem('token');
      const formData = new FormData();
      formData.append('file', file);
      const res = await fetch(`${API_BASE}/api/assignments/${assignment.id}/tech-card-file`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: formData,
      });
      if (res.ok) {
        const data = await res.json();
        setHasTechCardFile(!!data.has_tech_card_file);
        setTechCardFileName(data.tech_card_file_name || file.name);
        toast.success('Файл схемы/техкарты загружен');
      } else {
        const err = await res.json().catch(() => ({}));
        toast.error(err.detail || 'Ошибка загрузки файла');
      }
    } catch (e) {
      console.error('Ошибка загрузки файла техкарты:', e);
      toast.error('Ошибка сети при загрузке файла');
    } finally {
      setUploadingFile(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const handleDeleteTechCardFile = async () => {
    setUploadingFile(true);
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/assignments/${assignment.id}/tech-card-file`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        setHasTechCardFile(false);
        setTechCardFileName('');
        toast.success('Файл схемы/техкарты удалён');
      } else {
        const err = await res.json().catch(() => ({}));
        toast.error(err.detail || 'Ошибка удаления файла');
      }
    } catch (e) {
      console.error('Ошибка удаления файла техкарты:', e);
      toast.error('Ошибка сети при удалении файла');
    } finally {
      setUploadingFile(false);
    }
  };

  useEffect(() => {
    const loadTemplates = async () => {
      try {
        const token = localStorage.getItem('token');
        const res = await fetch(`${API_BASE}/api/protocol-templates?active_only=true`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) return;
        const data = await res.json();
        if (!Array.isArray(data)) return;
        setProtocolTemplates(
          data
            .map((row: { id?: string; name?: string; category?: string }) => ({
              id: String(row.id ?? ''),
              name: String(row.name ?? row.id ?? ''),
              category: row.category,
            }))
            .filter((t: { id: string }) => t.id.length > 0),
        );
      } catch {
        /* справочник шаблонов опционален */
      }
    };
    loadTemplates();
  }, []);

  if (!isOpen) return null;

  const handleSave = async () => {
    setSaving(true);
    try {
      const token = localStorage.getItem('token');
      const body: Record<string, string | null> = {};

      if (status !== assignment.status) body.status = status;
      if (priority !== assignment.priority) body.priority = priority;
      if (dueDate !== (assignment.due_date ? assignment.due_date.slice(0, 10) : '')) {
        body.due_date = dueDate ? new Date(dueDate).toISOString() : null;
      }
      if (description !== (assignment.description || '')) {
        body.description = description;
      }

      const origTemplate = assignment.protocol_template_id || '';
      if (canEditTemplate && protocolTemplateId.trim() !== origTemplate) {
        body.protocol_template_id = protocolTemplateId.trim() ? protocolTemplateId.trim() : null;
      }

      const setIfChanged = (key: string, next: string, prev?: string | null) => {
        const n = next.trim();
        const p = (prev || '').trim();
        if (n !== p) body[key] = n || null;
      };
      setIfChanged('contract_number', contractNumber, assignment.contract_number);
      setIfChanged('contract_date', contractDate, assignment.contract_date);
      setIfChanged('work_period_from', workPeriodFrom, assignment.work_period_from);
      setIfChanged('work_period_to', workPeriodTo, assignment.work_period_to);
      setIfChanged('work_basis', workBasis, assignment.work_basis);
      setIfChanged('tech_card_number', techCardNumber, assignment.tech_card_number);

      if (Object.keys(body).length === 0) {
        toast.info('Нет изменений для сохранения');
        onClose();
        return;
      }

      const res = await fetch(`${API_BASE}/api/assignments/${assignment.id}`, {
        method: 'PUT',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });

      if (res.ok) {
        toast.success('Задание успешно обновлено');
        onSaved();
        onClose();
      } else {
        const err = await res.json().catch(() => ({}));
        toast.error(err.detail || 'Ошибка при обновлении задания');
      }
    } catch (e) {
      console.error('Ошибка сохранения задания:', e);
      toast.error('Ошибка сети при сохранении');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-app-panel rounded-2xl border border-app-line shadow-2xl w-full max-w-lg"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-5 border-b border-app-line">
          <div>
            <h2 className="text-lg font-bold text-app-text">Редактировать задание</h2>
            <p className="text-sm text-app-text3 mt-0.5">
              {assignment.equipment_code} — {assignment.equipment_name}
            </p>
          </div>
          <button onClick={onClose} className="p-2 hover:bg-app-soft rounded-lg text-app-text3 hover:text-app-text transition">
            <X size={20} />
          </button>
        </div>

        <div className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-medium text-app-text2 mb-1.5">Статус</label>
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value)}
              className="w-full px-3 py-2.5 bg-app-deep border border-app-line rounded-lg text-app-text text-sm focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent"
            >
              {STATUS_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-app-text2 mb-1.5">Приоритет</label>
            <select
              value={priority}
              onChange={(e) => setPriority(e.target.value)}
              className="w-full px-3 py-2.5 bg-app-deep border border-app-line rounded-lg text-app-text text-sm focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent"
            >
              {PRIORITY_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-app-text2 mb-1.5">Срок выполнения</label>
            <input
              type="date"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
              className="w-full px-3 py-2.5 bg-app-deep border border-app-line rounded-lg text-app-text text-sm focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-app-text2 mb-1.5">Описание</label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows={4}
              placeholder="Описание задания..."
              className="w-full px-3 py-2.5 bg-app-deep border border-app-line rounded-lg text-app-text text-sm focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent resize-none placeholder-app-text3"
            />
          </div>

          <div className="rounded-lg border border-app-line bg-app-deep/40 p-3 space-y-3">
            <p className="text-sm font-medium text-app-text">Данные для титула отчёта ТО</p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className="block text-xs text-app-text3 mb-1">№ договора</label>
                <input type="text" value={contractNumber} onChange={(e) => setContractNumber(e.target.value)}
                  className="w-full px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text text-sm" />
              </div>
              <div>
                <label className="block text-xs text-app-text3 mb-1">Дата договора</label>
                <input type="date" value={contractDate} onChange={(e) => setContractDate(e.target.value)}
                  className="w-full px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text text-sm" />
              </div>
              <div>
                <label className="block text-xs text-app-text3 mb-1">Период работ с</label>
                <input type="date" value={workPeriodFrom} onChange={(e) => setWorkPeriodFrom(e.target.value)}
                  className="w-full px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text text-sm" />
              </div>
              <div>
                <label className="block text-xs text-app-text3 mb-1">Период работ по</label>
                <input type="date" value={workPeriodTo} onChange={(e) => setWorkPeriodTo(e.target.value)}
                  className="w-full px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text text-sm" />
              </div>
              <div className="sm:col-span-2">
                <label className="block text-xs text-app-text3 mb-1">Основание</label>
                <input type="text" value={workBasis} onChange={(e) => setWorkBasis(e.target.value)}
                  className="w-full px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text text-sm" />
              </div>
              <div className="sm:col-span-2">
                <label className="block text-xs text-app-text3 mb-1">№ техкарты</label>
                <input type="text" value={techCardNumber} onChange={(e) => setTechCardNumber(e.target.value)}
                  className="w-full px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text text-sm" />
              </div>
              <div className="sm:col-span-2">
                <label className="block text-xs text-app-text3 mb-1">
                  Файл схемы контроля / техкарты
                </label>
                {hasTechCardFile ? (
                  <div className="flex items-center gap-2 px-3 py-2 bg-app-deep border border-app-line rounded-lg text-sm">
                    <FileText size={14} className="text-accent shrink-0" />
                    <a
                      href={`${API_BASE}/api/assignments/${assignment.id}/tech-card-file?inline=true`}
                      target="_blank"
                      rel="noreferrer"
                      className="text-app-text truncate flex-1 hover:underline"
                      title={techCardFileName}
                    >
                      {techCardFileName || 'Файл'}
                    </a>
                    <button
                      type="button"
                      onClick={handleDeleteTechCardFile}
                      disabled={uploadingFile}
                      className="p-1 text-app-text3 hover:text-red-400 transition disabled:opacity-50"
                      title="Удалить файл"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                ) : (
                  <button
                    type="button"
                    onClick={() => fileInputRef.current?.click()}
                    disabled={uploadingFile}
                    className="w-full flex items-center justify-center gap-2 px-3 py-2 bg-app-deep border border-dashed border-app-line rounded-lg text-app-text3 text-sm hover:border-accent hover:text-app-text transition disabled:opacity-50"
                  >
                    {uploadingFile ? <Loader2 size={14} className="animate-spin" /> : <Upload size={14} />}
                    Приложить схему/техкарту (PDF, изображение, DOCX)
                  </button>
                )}
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".pdf,.doc,.docx,.png,.jpg,.jpeg,.webp"
                  className="hidden"
                  onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) handleUploadTechCardFile(f);
                  }}
                />
                <p className="text-xs text-app-text3 mt-1">
                  Готовая схема контроля/техкарта прикладывается к заданию и передаётся инженеру вместе с заданием.
                </p>
              </div>
            </div>
          </div>

          {canEditTemplate ? (
            <div>
              <label className="block text-sm font-medium text-app-text2 mb-1.5">
                Шаблон протокола (мобильное приложение)
              </label>
              <select
                value={protocolTemplateId}
                onChange={(e) => setProtocolTemplateId(e.target.value)}
                className="w-full px-3 py-2.5 bg-app-deep border border-app-line rounded-lg text-app-text text-sm focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent"
              >
                <option value="">Не назначать</option>
                {protocolTemplates.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name}
                    {t.category ? ` — ${t.category}` : ''}
                  </option>
                ))}
              </select>
              <p className="text-xs text-app-text3 mt-1.5">
                Изменение доступно администратору, старшему оператору и оператору.
              </p>
            </div>
          ) : (
            (assignment.protocol_template_id || assignment.protocol_template_name) && (
              <div className="rounded-lg border border-app-line bg-app-deep/50 px-3 py-2.5 text-sm text-app-text2">
                <span className="text-app-text3 block text-xs mb-1">Шаблон протокола</span>
                {assignment.protocol_template_name?.trim()
                  ? assignment.protocol_template_name
                  : assignment.protocol_template_id
                    ? `ID: ${assignment.protocol_template_id}`
                    : '—'}
              </div>
            )
          )}
        </div>

        <div className="flex items-center justify-end gap-3 p-5 border-t border-app-line">
          <button
            onClick={onClose}
            disabled={saving}
            className="px-4 py-2.5 bg-app-soft hover:bg-app-softer text-app-text text-sm font-medium rounded-lg transition disabled:opacity-50"
          >
            Отмена
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className="flex items-center gap-2 px-4 py-2.5 bg-accent hover:bg-blue-600 text-white text-sm font-medium rounded-lg transition disabled:opacity-50"
          >
            {saving ? (
              <>
                <Loader2 size={16} className="animate-spin" />
                Сохранение...
              </>
            ) : (
              <>
                <Save size={16} />
                Сохранить
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};

export default EditAssignmentModal;
