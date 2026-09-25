import type { CreateFormData } from './types';

export function equipmentPayload(data: CreateFormData, isEdit: boolean, workshopId?: string) {
  return {
    name: data.name.trim(),
    type_id: data.type_id || undefined,
    serial_number: data.serial_number || (isEdit ? '' : undefined),
    location: data.location || (isEdit ? '' : undefined),
    commissioning_date: data.commissioning_date || (isEdit ? '' : undefined),
    ...(isEdit ? {} : { attributes: {}, workshop_id: workshopId }),
  };
}
