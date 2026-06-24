import { API_BASE } from '../constants';
import {
  isGasSeparatorType,
  isOilSettlerType,
  isUndergroundTankType,
} from '../constants';

export interface EquipmentProfileResponse {
  profile: {
    code: string;
    preset: string;
    display_name: string;
    pressure_regime?: string;
    default_purpose?: string;
  };
  default_data: Record<string, unknown>;
}

/** type_code / preset → код для API профилей */
export function resolveEquipmentTypeCode(
  typeCode?: string | null,
  typeName?: string | null,
  equipmentName?: string | null,
): string {
  const code = (typeCode || '').toUpperCase();
  const name = `${typeName || ''} ${equipmentName || ''}`;
  if (code.includes('OIL_SETTLER') || isOilSettlerType(code, name)) return 'OIL_SETTLER';
  if (code.includes('GAS_SEP') || isGasSeparatorType(code, name)) return 'GAS_SEPARATOR';
  if (code.includes('UNDERGROUND') || isUndergroundTankType(code, name)) return 'UNDERGROUND_TANK';
  if (code.includes('VESSEL')) return 'VESSEL';
  return code || 'VESSEL';
}

export async function fetchEquipmentProfileResolve(
  token: string,
  params: {
    typeCode?: string;
    preset?: string;
    inspectionDirection?: string;
    includeUztTemplate?: boolean;
  },
): Promise<EquipmentProfileResponse> {
  const q = new URLSearchParams();
  if (params.typeCode) q.set('type_code', params.typeCode);
  if (params.preset) q.set('preset', params.preset);
  q.set('inspection_direction', params.inspectionDirection || 'technical');
  q.set('include_uzt_template', String(params.includeUztTemplate !== false));

  const res = await fetch(`${API_BASE}/api/equipment-profiles/resolve?${q}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error((err as { detail?: string }).detail || `Профиль: HTTP ${res.status}`);
  }
  return res.json();
}

/** Значения полей схемы из default_data профиля */
export function profileFieldDefaults(
  defaultData: Record<string, unknown> | undefined,
): Record<string, string> {
  if (!defaultData) return {};
  const d = defaultData;
  const str = (k: string) => {
    const v = d[k];
    if (v === null || v === undefined) return '';
    return String(v);
  };
  return {
    purpose: str('purpose'),
    construction_type: str('construction_type'),
    pressure_current: str('working_pressure'),
    volume: str('volume'),
    scheme_index: str('scheme_index'),
    working_medium: str('working_medium'),
    temp_wall: str('working_temperature'),
    wall_thickness: str('wall_thickness'),
    diameter: str('diameter'),
  };
}
