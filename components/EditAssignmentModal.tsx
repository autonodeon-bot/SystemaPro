import React, { useState } from 'react';
import { X, Save, Loader2 } from 'lucide-react';
import { API_BASE } from '../constants';
import { useToast } from '../contexts/ToastContext';
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
  const [status, setStatus] = useState(assignment.status);
  const [priority, setPriority] = useState(assignment.priority);
  const [dueDate, setDueDate] = useState(assignment.due_date ? assignment.due_date.slice(0, 10) : '');
  const [description, setDescription] = useState(assignment.description || '');
  const [saving, setSaving] = useState(false);

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
        className="bg-slate-800 rounded-2xl border border-slate-700 shadow-2xl w-full max-w-lg"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-5 border-b border-slate-700">
          <div>
            <h2 className="text-lg font-bold text-white">Редактировать задание</h2>
            <p className="text-sm text-slate-400 mt-0.5">
              {assignment.equipment_code} — {assignment.equipment_name}
            </p>
          </div>
          <button onClick={onClose} className="p-2 hover:bg-slate-700 rounded-lg text-slate-400 hover:text-white transition">
            <X size={20} />
          </button>
        </div>

        <div className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1.5">Статус</label>
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value)}
              className="w-full px-3 py-2.5 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent"
            >
              {STATUS_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1.5">Приоритет</label>
            <select
              value={priority}
              onChange={(e) => setPriority(e.target.value)}
              className="w-full px-3 py-2.5 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent"
            >
              {PRIORITY_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1.5">Срок выполнения</label>
            <input
              type="date"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
              className="w-full px-3 py-2.5 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1.5">Описание</label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows={4}
              placeholder="Описание задания..."
              className="w-full px-3 py-2.5 bg-slate-900 border border-slate-700 rounded-lg text-white text-sm focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent resize-none placeholder-slate-500"
            />
          </div>
        </div>

        <div className="flex items-center justify-end gap-3 p-5 border-t border-slate-700">
          <button
            onClick={onClose}
            disabled={saving}
            className="px-4 py-2.5 bg-slate-700 hover:bg-slate-600 text-white text-sm font-medium rounded-lg transition disabled:opacity-50"
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
