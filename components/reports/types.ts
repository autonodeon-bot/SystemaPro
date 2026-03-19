export interface Report {
  id: string;
  inspection_id?: string;
  equipment_id: string;
  equipment_name?: string;
  equipment_location?: string;
  project_id?: string;
  enterprise_id?: string;
  enterprise_name?: string;
  branch_id?: string;
  branch_name?: string;
  workshop_id?: string;
  workshop_name?: string;
  opo_id?: string;
  opo_name?: string;
  opo_code?: string;
  report_type: string;
  title: string;
  file_path?: string;
  file_size?: number;
  status: string;
  created_at?: string;
  created_by?: string;
  inspector_name?: string;
  inspector_position?: string;
}

export interface NDTMethod {
  id: string;
  method_code: string;
  method_name: string;
  is_performed: boolean;
  standard?: string;
  equipment?: string;
  inspector_name?: string;
  inspector_level?: string;
  results?: string;
  defects?: string;
  conclusion?: string;
}

export interface DocumentFile {
  id: string;
  document_number: string;
  file_name: string;
  file_size: number;
  file_type?: string;
  mime_type?: string;
  created_at?: string;
}

export interface Questionnaire {
  id: string;
  equipment_id: string;
  equipment_name?: string;
  equipment_location?: string;
  equipment_inventory_number?: string;
  inspection_date?: string;
  inspector_name?: string;
  inspector_position?: string;
  file_path?: string;
  file_size?: number;
  word_file_path?: string;
  word_file_size?: number;
  enterprise_id?: string;
  enterprise_name?: string;
  branch_id?: string;
  branch_name?: string;
  workshop_id?: string;
  workshop_name?: string;
  opo_id?: string;
  opo_name?: string;
  opo_code?: string;
  ndt_methods?: NDTMethod[];
  document_files?: DocumentFile[];
  created_by?: string;
  created_at?: string;
}

export interface Enterprise {
  id: string;
  name: string;
  code?: string;
}

export interface Branch {
  id: string;
  enterprise_id: string;
  name: string;
  code?: string;
}

export interface Workshop {
  id: string;
  branch_id: string;
  name: string;
  code?: string;
}

export type UnifiedListItem =
  | (Report & { itemType: 'report' })
  | (Questionnaire & {
      itemType: 'questionnaire';
      report_type: string;
      title: string;
      status: string;
      equipment_location?: string;
    });
