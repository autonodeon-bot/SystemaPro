import React from 'react';
import Modal from '../ui/Modal';
import SearchSelect from '../ui/SearchSelect';
import type { CreateFormData, CreateModalState, EquipmentType } from './types';

export interface EquipmentCreateModalProps {
  busy?: boolean;
  error?: string;
  modal: CreateModalState;
  formData: CreateFormData;
  equipmentTypes: EquipmentType[];
  onClose: () => void;
  onSubmit: (e: React.FormEvent) => void;
  onFormDataChange: (data: CreateFormData) => void;
}

const EquipmentCreateModal: React.FC<EquipmentCreateModalProps> = ({
  modal,
  busy = false,
  error,
  formData,
  equipmentTypes,
  onClose,
  onSubmit,
  onFormDataChange,
}) => {
  const isEdit = modal.mode === 'edit';
  const entityLabel =
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
    <Modal title={`${isEdit ? 'Редактировать' : 'Создать'} ${entityLabel}`} onClose={onClose} busy={busy}
      description={modal.parentName ? `Расположение: ${modal.parentName}` : 'Основные сведения. Обязательные поля отмечены звёздочкой.'}
      footer={<>
        <button type="button" disabled={busy} onClick={onClose} className="ind-btn">Отмена</button>
        <button type="submit" form="equipment-entity-form" disabled={busy} className="ind-btn ind-btn--primary">{busy ? 'Сохранение…' : isEdit ? 'Сохранить изменения' : 'Создать'}</button>
      </>}>
        <form id="equipment-entity-form" onSubmit={onSubmit} className="space-y-4">
          {error && <div role="alert" className="sp-notice">{error}</div>}
          <fieldset disabled={busy} className="space-y-4">
          <div>
            <label className="text-sm text-app-text3 block mb-1">Название *</label>
            <input
              type="text"
              aria-label="Название"
              autoFocus data-initial-focus
              required
              value={formData.name}
              onChange={(e) => onFormDataChange({ ...formData, name: e.target.value })}
              className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
              placeholder="Введите название"
            />
          </div>

          {(modal.type === 'enterprise' ||
            modal.type === 'branch' ||
            modal.type === 'workshop' ||
            modal.type === 'equipment_type') && (
            <>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Код</label>
                <input
                  type="text"
                  aria-label="Код"
                  value={formData.code}
                  onChange={(e) => onFormDataChange({ ...formData, code: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                  placeholder="Введите код (необязательно)"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Описание</label>
                <textarea
                  aria-label="Описание"
                  value={formData.description}
                  onChange={(e) =>
                    onFormDataChange({ ...formData, description: e.target.value })
                  }
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                  placeholder="Введите описание (необязательно)"
                  rows={3}
                />
              </div>
            </>
          )}

          {modal.type === 'enterprise' && (
            <>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Руководитель</label>
                <input
                  type="text"
                  aria-label="Руководитель"
                  value={formData.director || ''}
                  onChange={(e) => onFormDataChange({ ...formData, director: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Телефон</label>
                <input
                  type="tel"
                  aria-label="Телефон"
                  value={formData.phone || ''}
                  onChange={(e) => onFormDataChange({ ...formData, phone: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">E-mail</label>
                <input
                  type="email"
                  aria-label="E-mail"
                  value={formData.email || ''}
                  onChange={(e) => onFormDataChange({ ...formData, email: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Юридический адрес</label>
                <input
                  type="text"
                  aria-label="Юридический адрес"
                  value={formData.legal_address || ''}
                  onChange={(e) => onFormDataChange({ ...formData, legal_address: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
            </>
          )}

          {modal.type === 'equipment' && (
            <>
              <SearchSelect label="Тип оборудования" value={formData.type_id}
                options={equipmentTypes.map(t => ({ value: t.id, label: t.name, description: t.code }))}
                onChange={type_id => onFormDataChange({ ...formData, type_id })} />
              <div>
                <label className="text-sm text-app-text3 block mb-1">Заводской номер</label>
                <input
                  type="text"
                  aria-label="Заводской номер"
                  value={formData.serial_number}
                  onChange={(e) =>
                    onFormDataChange({ ...formData, serial_number: e.target.value })
                  }
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                  placeholder="Введите заводской номер"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Место расположения</label>
                <input
                  type="text"
                  aria-label="Место расположения"
                  value={formData.location}
                  onChange={(e) => onFormDataChange({ ...formData, location: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                  placeholder="Введите место расположения"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">
                  Дата ввода в эксплуатацию
                </label>
                <input
                  type="date"
                  aria-label="Дата ввода в эксплуатацию"
                  value={formData.commissioning_date}
                  onChange={(e) =>
                    onFormDataChange({ ...formData, commissioning_date: e.target.value })
                  }
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
            </>
          )}

          </fieldset>
        </form>
    </Modal>
  );
};

export default EquipmentCreateModal;
