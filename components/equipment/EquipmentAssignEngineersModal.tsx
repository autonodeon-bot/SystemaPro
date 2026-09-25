import React, { useState, useRef } from 'react';
import Modal from '../ui/Modal';
import { UserCheck } from 'lucide-react';
import type { AssignedEngineerRecord, AssignModalState, EngineerUserListItem } from './types';

export interface EquipmentAssignEngineersModalProps {
  modal: AssignModalState;
  usersList: EngineerUserListItem[];
  selectedEngineers: string[];
  assignedEngineers: AssignedEngineerRecord[];
  onClose: () => void;
  onSubmit: (e: React.FormEvent) => void;
  onSelectedEngineersChange: (ids: string[]) => void;
}

const EquipmentAssignEngineersModal: React.FC<EquipmentAssignEngineersModalProps> = ({
  modal,
  usersList,
  selectedEngineers,
  assignedEngineers,
  onClose,
  onSubmit,
  onSelectedEngineersChange,
}) => {
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const pending = useRef(false);
  const filtered = usersList.filter(user => `${user.full_name ?? ''} ${user.username ?? ''}`.toLocaleLowerCase('ru').includes(query.trim().toLocaleLowerCase('ru')));
  return <Modal title={`Назначить инженеров: ${modal.name}`} onClose={onClose} busy={busy} description="Найдите специалистов и отметьте нужных. Выбор сохраняется при поиске.">
      <input data-initial-focus type="search" aria-label="Поиск инженеров" placeholder="ФИО или логин…" className="w-full mb-4 p-3 bg-app-deep border border-app-line" value={query} onChange={e => setQuery(e.target.value)} />
      <p className="sp-hint mb-3">Выбрано: {selectedEngineers.length} · Найдено: {filtered.length}</p>
      <form onSubmit={async e => { e.preventDefault(); if (pending.current) return; pending.current = true; setBusy(true); try { await onSubmit(e); } finally { pending.current = false; setBusy(false); } }} className="space-y-4">
        <div className="max-h-64 overflow-y-auto space-y-2">
          {filtered.length === 0 && <p className="sp-empty">Специалисты не найдены</p>}
          {filtered.map((user) => {
            const isSelected = selectedEngineers.includes(user.id);
            const isAlreadyAssigned = assignedEngineers.some((e) => e.user_id === user.id);
            return (
              <label
                key={user.id}
                className={`flex items-center gap-3 p-3 rounded-lg border cursor-pointer ${
                  isSelected ? 'bg-accent/20 border-accent' : 'bg-app-deep border-app-line'
                } ${isAlreadyAssigned ? 'opacity-75' : ''}`}
              >
                <input
                  type="checkbox"
                  disabled={busy}
                  checked={isSelected}
                  onChange={(e) => {
                    if (e.target.checked) {
                      onSelectedEngineersChange([...selectedEngineers, user.id]);
                    } else {
                      onSelectedEngineersChange(
                        selectedEngineers.filter((id) => id !== user.id)
                      );
                    }
                  }}
                  className="w-4 h-4 text-accent rounded"
                />
                <div className="flex-1">
                  <div className="text-app-text font-medium">
                    {user.full_name || user.username}
                  </div>
                  {isAlreadyAssigned && (
                    <div className="text-xs text-green-400 flex items-center gap-1">
                      <UserCheck size={12} />
                      Уже назначен
                    </div>
                  )}
                </div>
              </label>
            );
          })}
        </div>

        <div className="flex gap-2">
          <button
            type="submit"
            className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600"
            disabled={busy || selectedEngineers.length === 0}
          >
            Назначить ({selectedEngineers.length})
          </button>
          <button
            type="button"
            disabled={busy} onClick={onClose}
            className="flex-1 bg-app-soft px-4 py-2 rounded-lg text-app-text font-bold hover:bg-app-softer"
          >
            Отмена
          </button>
        </div>
      </form>
  </Modal>;
};

export default EquipmentAssignEngineersModal;
