export interface Enterprise {
  id: string;
  name: string;
  code?: string;
  description?: string;
  director?: string;
  phone?: string;
  email?: string;
  legal_address?: string;
}

export interface Branch {
  id: string;
  enterprise_id: string;
  name: string;
  code?: string;
  description?: string;
}

export interface Workshop {
  id: string;
  branch_id: string;
  name: string;
  code?: string;
  description?: string;
}

export interface EquipmentType {
  id: string;
  name: string;
  code?: string;
}

export interface Equipment {
  id: string;
  name: string;
  type_id?: string;
  serial_number?: string;
  location?: string;
  workshop_id?: string;
  attributes?: Record<string, unknown>;
  commissioning_date?: string;
}

export type CreateEntityType =
  | 'enterprise'
  | 'branch'
  | 'workshop'
  | 'equipment_type'
  | 'equipment';

export type HierarchyInfoType = 'enterprise' | 'branch' | 'workshop' | 'equipment';

export type ModalMode = 'create' | 'edit';

export interface CreateModalState {
  type: CreateEntityType;
  mode?: ModalMode;
  entityId?: string;
  parentId?: string;
  parentName?: string;
}

export interface AssignModalState {
  type: CreateEntityType;
  id: string;
  name: string;
}

export interface InfoModalState {
  type: HierarchyInfoType;
  id: string;
  name: string;
}

export interface CreateFormData {
  name: string;
  code: string;
  description: string;
  director: string;
  phone: string;
  email: string;
  legal_address: string;
  enterprise_id: string;
  branch_id: string;
  workshop_id: string;
  type_id: string;
  serial_number: string;
  location: string;
  commissioning_date: string;
}

export interface EngineerUserListItem {
  id: string;
  full_name?: string;
  username?: string;
}

export interface AssignedEngineerRecord {
  user_id: string;
  full_name?: string;
  username?: string;
  email?: string;
  granted_at?: string;
}
