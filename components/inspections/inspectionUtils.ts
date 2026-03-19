import type { Inspection } from './types';

export function formatInspectionDate(dateString?: string): string {
  if (!dateString) return 'Не указана';
  try {
    const date = new Date(dateString);
    return date.toLocaleDateString('ru-RU', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return dateString;
  }
}

export function inspectionHierarchySubtitle(insp: Inspection): string | null {
  const parts = [insp.enterprise_name, insp.branch_name, insp.workshop_name].filter(Boolean);
  return parts.length ? parts.join(' / ') : null;
}
