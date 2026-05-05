export function getInspectionStatusColorClass(status: string): string {
  switch (status) {
    case 'SIGNED':
      return 'bg-green-500/20 text-green-400 border-green-500/30';
    case 'DRAFT':
      return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30';
    case 'REJECTED':
      return 'bg-red-500/20 text-red-400 border-red-500/30';
    default:
      return 'bg-app-text3/20 text-app-text3 border-app-text3/30';
  }
}

export function getInspectionStatusLabel(status: string): string {
  switch (status) {
    case 'SIGNED':
      return 'Подписан';
    case 'DRAFT':
      return 'Черновик';
    case 'REJECTED':
      return 'Отклонен';
    default:
      return status;
  }
}
