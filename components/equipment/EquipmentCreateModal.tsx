import React from 'react';
import { X } from 'lucide-react';
import type { CreateFormData, CreateModalState, EquipmentType } from './types';

export interface EquipmentCreateModalProps {
  modal: CreateModalState;
  formData: CreateFormData;
  equipmentTypes: EquipmentType[];
  onClose: () => void;
  onSubmit: (e: React.FormEvent) => void;
  onFormDataChange: (data: CreateFormData) => void;
}

const EquipmentCreateModal: React.FC<EquipmentCreateModalProps> = ({
  modal,
  formData,
  equipmentTypes,
  onClose,
  onSubmit,
  onFormDataChange,
}) => {
  const title =
    modal.type === 'enterprise'
      ? 'предприятие'
      : modal.type === 'branch'
        ? 'филиал'
        : modal.type === 'workshop'
          ? 'цех'
          : modal.type === 'equipment_type'
            ? 'тип оборудования'
            : 'оборудование';

  return (
    <div
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      onClick={onClose}
      role="presentation"
    >
      <div
        className="bg-slate-800 rounded-xl p-6 max-w-md w-full mx-4"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
      >
        <div className="flex justify-between items-center mb-4">
          <h2 className="text-xl font-bold text-white">Создать {title}</h2>
          <button type="button" onClick={onClose} className="text-slate-400 hover:text-white">
            <X size={24} />
          </button>
        </div>

        {modal.parentName && (
          <p className="text-slate-400 text-sm mb-4">Родитель: {modal.parentName}</p>
        )}

        <form onSubmit={onSubmit} className="space-y-4">
          <div>
            <label className="text-sm text-slate-400 block mb-1">Название *</label>
            <input
              type="text"
              required
              value={formData.name}
              onChange={(e) => onFormDataChange({ ...formData, name: e.target.value })}
              className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
              placeholder="Введите название"
            />
          </div>

          {(modal.type === 'enterprise' ||
            modal.type === 'branch' ||
            modal.type === 'workshop' ||
            modal.type === 'equipment_type') && (
            <>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Код</label>
                <input
                  type="text"
                  value={formData.code}
                  onChange={(e) => onFormDataChange({ ...formData, code: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Введите код (необязательно)"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Описание</label>
                <textarea
                  value={formData.description}
                  onChange={(e) =>
                    onFormDataChange({ ...formData, description: e.target.value })
                  }
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Введите описание (необязательно)"
                  rows={3}
                />
              </div>
            </>
          )}

          {modal.type === 'equipment' && (
            <>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Тип оборудования</label>
                <select
                  value={formData.type_id}
                  onChange={(e) => onFormDataChange({ ...formData, type_id: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                >
                  <option value="">Выберите тип</option>
                  {equipmentTypes.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.name}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Заводской номер</label>
                <input
                  type="text"
                  value={formData.serial_number}
                  onChange={(e) =>
                    onFormDataChange({ ...formData, serial_number: e.target.value })
                  }
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Введите заводской номер"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Место расположения</label>
                <input
                  type="text"
                  value={formData.location}
                  onChange={(e) => onFormDataChange({ ...formData, location: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Введите место расположения"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">
                  Дата ввода в эксплуатацию
                </label>
                <input
                  type="date"
                  value={formData.commissioning_date}
                  onChange={(e) =>
                    onFormDataChange({ ...formData, commissioning_date: e.target.value })
                  }
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
            </>
          )}

          <div className="flex gap-2">
            <button
              type="submit"
              className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600"
            >
              Создать
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
};

export default EquipmentCreateModal;
