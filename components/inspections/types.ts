export interface Inspection {
  id: string;
  equipment_id: string;
  equipment_name?: string;
  equipment_location?: string;
  enterprise_id?: string;
  enterprise_name?: string;
  branch_id?: string;
  branch_name?: string;
  workshop_id?: string;
  workshop_name?: string;
  data: unknown;
  conclusion?: string;
  status: string;
  date_performed?: string;
  created_at: string;
  inspector_id?: string;
  inspector_name?: string;
  inspection_type?: string;
  inspection_method?: string;
  inspection_category?: string;
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

export interface InspectionQuestionnaireInfo {
  questionnaire_id: string | null;
  document_files: DocumentFile[];
}

export interface Equipment {
  id: string;
  name: string;
  location?: string;
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
