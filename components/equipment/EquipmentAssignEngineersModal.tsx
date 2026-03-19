import React from 'react';
import { X, UserCheck } from 'lucide-react';
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
}) => (
  <div
    className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
    onClick={onClose}
    role="presentation"
  >
    <div
      className="bg-slate-800 rounded-xl p-6 max-w-md w-full mx-4 max-h-[80vh] overflow-y-auto"
      onClick={(e) => e.stopPropagation()}
      role="dialog"
      aria-modal="true"
    >
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-bold text-white">Назначить инженеров: {modal.name}</h2>
        <button type="button" onClick={onClose} className="text-slate-400 hover:text-white">
          <X size={24} />
        </button>
      </div>

      <form onSubmit={onSubmit} className="space-y-4">
        <div className="max-h-64 overflow-y-auto space-y-2">
          {usersList.map((user) => {
            const isSelected = selectedEngineers.includes(user.id);
            const isAlreadyAssigned = assignedEngineers.some((e) => e.user_id === user.id);
            return (
              <label
                key={user.id}
                className={`flex items-center gap-3 p-3 rounded-lg border cursor-pointer ${
                  isSelected ? 'bg-accent/20 border-accent' : 'bg-slate-900 border-slate-700'
                } ${isAlreadyAssigned ? 'opacity-75' : ''}`}
              >
                <input
                  type="checkbox"
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
                  <div className="text-white font-medium">
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
            disabled={selectedEngineers.length === 0}
          >
            Назначить ({selectedEngineers.length})
          </button>
          <button
            type="button"
            onClick={onClose}
            className="flex-1 bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
          >
            Отмена
          </button>
        </div>
      </form>
    </div>
  </div>
);

export default EquipmentAssignEngineersModal;
