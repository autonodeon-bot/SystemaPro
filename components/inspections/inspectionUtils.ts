import type { Inspection } from './types';

export function inspectionTypeLabel(type?: string): string {
  return ({VISUAL:'Визуальный контроль',NDT:'Неразрушающий контроль',QUESTIONNAIRE:'Опросный лист',EXPERTISE:'Экспертиза',UNSPECIFIED:'Тип не указан'} as Record<string,string>)[type || 'UNSPECIFIED'] || type || 'Тип не указан';
}

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
