import type { UnifiedListItem } from './types';

export function getReportTypeLabel(type: string): string {
  switch (type) {
    case 'TECHNICAL_REPORT':
      return 'Технический отчет';
    case 'EXPERTISE':
      return 'Экспертиза ПБ';
    case 'RESOURCE_EXTENSION':
      return 'Продление ресурса';
    case 'QUESTIONNAIRE':
      return 'Опросный лист';
    default:
      return type;
  }
}

export function getStatusColor(status: string): string {
  switch (status) {
    case 'SIGNED':
    case 'APPROVED':
      return 'bg-green-500/20 text-green-400 border-green-500/30';
    case 'DRAFT':
      return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30';
    case 'SENT':
      return 'bg-blue-500/20 text-blue-400 border-blue-500/30';
    default:
      return 'bg-slate-500/20 text-slate-400 border-slate-500/30';
  }
}

export function getStatusLabel(status: string): string {
  switch (status) {
    case 'DRAFT':
      return 'Черновик';
    case 'SIGNED':
      return 'Подписан';
    case 'APPROVED':
      return 'Утвержден';
    case 'SENT':
      return 'Отправлен клиенту';
    default:
      return status;
  }
}

export function formatDate(dateString?: string): string {
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

export function formatFileSize(bytes: number): string {
  if (!bytes || bytes === 0) return '0 Б';
  if (bytes < 1024) return `${bytes} Б`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} КБ`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} МБ`;
}

export function getDocumentName(number: number): string {
  const names: Record<number, string> = {
    1: 'Лицензия на осуществление деятельности по эксплуатации взрывопожароопасных и химически опасных производственных объектов I, II и III классов опасности',
    2: 'Свидетельство о регистрации в государственном реестре ОПО, включая сведения характеризующие ОПО',
    3: 'Технологический регламент объектов опасных производственных объектов',
    4: 'План мероприятий по локализации и ликвидации последствий аварий на опасном производственном объекте',
    5: 'Положение о производственном контроле за соблюдением требований промышленной безопасности на опасных производственных объектах',
    6: 'Журнал учета аварий и инцидентов на ОПО',
    7: 'Страховой полис страхования гражданской ответственности владельца опасного объекта за причинение вреда в результате аварии на опасном объекте',
    8: 'Приказ о назначении ответственного лица за исправное состояние и безопасную эксплуатацию сосудов',
    9: 'Приказ о назначении ответственного лица за осуществление производственного контроля и соблюдение требований промышленной безопасности на опасном производственном объекте',
    10: 'Паспорт сосуда заводской (удостоверение о качестве монтажа, сертификат соответствия, сборочный чертёж и схема включения сосуда, расчёт на прочность)',
    11: 'Инструкция по монтажу и эксплуатации',
    12: 'Паспорта на предохранительные клапаны',
    13: 'Паспорта на запорную арматуру',
    14: 'Документация на контрольно-измерительные приборы',
    15: 'Ремонтная (исполнительная) документация',
    16: 'Заключение экспертизы промышленной безопасности',
    17: 'Акты проведения УЗТ',
  };
  return names[number] || `Документ ${number}`;
}

export function getGroupKey(item: UnifiedListItem, groupType: string): string | null {
  switch (groupType) {
    case 'enterprise':
      return item.enterprise_id ? `enterprise_${item.enterprise_id}` : 'enterprise_unknown';
    case 'branch':
      return item.branch_id ? `branch_${item.branch_id}` : 'branch_unknown';
    case 'workshop':
      return item.workshop_id ? `workshop_${item.workshop_id}` : 'workshop_unknown';
    case 'opo':
      return item.opo_id ? `opo_${item.opo_id}` : 'opo_unknown';
    default:
      return null;
  }
}

export function getGroupName(item: UnifiedListItem, groupType: string): string {
  switch (groupType) {
    case 'enterprise':
      return item.enterprise_name || 'Предприятие не указано';
    case 'branch':
      return item.branch_name || 'Филиал не указан';
    case 'workshop':
      return item.workshop_name || 'Цех не указан';
    case 'opo':
      return item.opo_name
        ? `${item.opo_name}${item.opo_code ? ` (${item.opo_code})` : ''}`
        : 'ОПО не указано';
    default:
      return '';
  }
}
