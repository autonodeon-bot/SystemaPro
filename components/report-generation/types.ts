export interface Inspection {
  id: string;
  equipment_id: string;
  date_performed?: string;
  status: string;
  conclusion?: string;
  enterprise_id?: string;
  enterprise_name?: string;
  branch_id?: string;
  branch_name?: string;
  workshop_id?: string;
  workshop_name?: string;
  is_archived?: boolean;
}

export interface Equipment {
  id: string;
  name: string;
  serial_number?: string;
  location?: string;
}

export interface Report {
  id: string;
  inspection_id: string;
  equipment_id: string;
  equipment_name?: string;
  report_type: string;
  title: string;
  file_path: string;
  word_file_path?: string | null;
  status: string;
  created_at: string;
  enterprise_id?: string;
  enterprise_name?: string;
  branch_id?: string;
  branch_name?: string;
  workshop_id?: string;
  workshop_name?: string;
  is_archived?: boolean;
}

export interface PreviewData {
  inspection: {
    id: string;
    date_performed?: string;
    status: string;
    conclusion?: string;
    data?: Record<string, unknown>;
  };
  equipment: {
    id: string;
    name: string;
    serial_number?: string;
    location?: string;
    commissioning_date?: string;
    attributes?: Record<string, unknown>;
  };
  questionnaire?: {
    id?: string | null;
  };
  document_files?: Array<{
    document_number: string;
    file_name?: string;
    file_size?: number;
    file_type?: string;
    mime_type?: string;
  }>;
  opo?: {
    id?: string;
    name?: string;
    code?: string;
    description?: string;
    enterprise_name?: string;
    branch_name?: string;
    workshop_name?: string;
    survey_data?: {
      organization?: string;
      executors?: string;
    };
  };
  ndt_methods: Array<{
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
  }>;
  resource?: {
    remaining_resource_years?: number;
    resource_end_date?: string;
    extension_years?: number;
    extension_date?: string;
  };
}

export interface GroupedItem {
  key: string;
  enterprise_name?: string;
  branch_name?: string;
  workshop_name?: string;
  inspections: Inspection[];
  reports: Report[];
}

export interface ReportValidationResult {
  is_complete: boolean;
  missing_fields: string[];
  warnings: string[];
  can_generate?: boolean;
}
