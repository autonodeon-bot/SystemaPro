export function getInspectionStatusColorClass(status: string): string {
  switch (status) {
    case 'SIGNED':
      return 'bg-green-500/20 text-green-400 border-green-500/30';
    case 'DRAFT':
      return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30';
    case 'REJECTED':
      return 'bg-red-500/20 text-red-400 border-red-500/30';
    default:
      return 'bg-slate-500/20 text-slate-400 border-slate-500/30';
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
