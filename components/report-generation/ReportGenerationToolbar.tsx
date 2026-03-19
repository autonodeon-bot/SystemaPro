import { Search } from 'lucide-react';
import type { NavigateFunction } from 'react-router-dom';

interface ReportGenerationToolbarProps {
  navigate: NavigateFunction;
  showArchived: boolean;
  onShowArchivedChange: (value: boolean) => void;
  filterReportType: string;
  onFilterReportTypeChange: (value: string) => void;
  filterStatus: string;
  onFilterStatusChange: (value: string) => void;
  filterDateFrom: string;
  onFilterDateFromChange: (value: string) => void;
  filterDateTo: string;
  onFilterDateToChange: (value: string) => void;
  searchTerm: string;
  onSearchTermChange: (value: string) => void;
  onResetFilters: () => void;
}

const ReportGenerationToolbar = ({
  navigate,
  showArchived,
  onShowArchivedChange,
  filterReportType,
  onFilterReportTypeChange,
  filterStatus,
  onFilterStatusChange,
  filterDateFrom,
  onFilterDateFromChange,
  filterDateTo,
  onFilterDateToChange,
  searchTerm,
  onSearchTermChange,
  onResetFilters,
}: ReportGenerationToolbarProps) => (
  <div className="flex flex-col md:flex-row md:justify-between md:items-center gap-4">
    <div className="flex items-center gap-3">
      <h1 className="text-xl md:text-2xl font-bold text-white">Генерация отчетов и экспертиз</h1>
      <button
        type="button"
        onClick={() => navigate('/report-templates')}
        className="px-3 py-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-white text-xs md:text-sm font-bold"
        title="Перейти в редактор макетов отчетов"
      >
        Редактор отчетов
      </button>
    </div>
    <div className="flex flex-col md:flex-row items-start md:items-center gap-4">
      <label className="flex items-center gap-2 text-sm text-slate-300 cursor-pointer">
        <input
          type="checkbox"
          checked={showArchived}
          onChange={(e) => onShowArchivedChange(e.target.checked)}
          className="w-4 h-4 rounded border-slate-600 bg-slate-700 text-accent focus:ring-accent"
        />
        <span>Показать архивные</span>
      </label>

      <div className="flex flex-wrap gap-2">
        <select
          value={filterReportType}
          onChange={(e) => onFilterReportTypeChange(e.target.value)}
          className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white text-sm"
        >
          <option value="all">Все типы отчетов</option>
          <option value="DIAGNOSTICS">Диагностические</option>
          <option value="TECHNICAL_REPORT">Технические</option>
          <option value="EXPERTISE">Экспертиза ПБ</option>
        </select>

        <select
          value={filterStatus}
          onChange={(e) => onFilterStatusChange(e.target.value)}
          className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white text-sm"
        >
          <option value="all">Все статусы</option>
          <option value="DRAFT">Черновик</option>
          <option value="SIGNED">Подписан</option>
          <option value="APPROVED">Утверждён</option>
          <option value="SUBMITTED">Отправлен</option>
          <option value="COMPLETED">Завершен</option>
        </select>

        <input
          type="date"
          value={filterDateFrom}
          onChange={(e) => onFilterDateFromChange(e.target.value)}
          placeholder="Дата от"
          className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white text-sm"
        />

        <input
          type="date"
          value={filterDateTo}
          onChange={(e) => onFilterDateToChange(e.target.value)}
          placeholder="Дата до"
          className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white text-sm"
        />
        <button
          type="button"
          onClick={onResetFilters}
          className="px-3 py-2 bg-slate-700 hover:bg-slate-600 border border-slate-600 rounded-lg text-white text-sm"
        >
          Сбросить фильтры
        </button>
      </div>

      <div className="relative w-full md:w-64">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
        <input
          type="text"
          placeholder="Поиск по оборудованию..."
          value={searchTerm}
          onChange={(e) => onSearchTermChange(e.target.value)}
          className="w-full bg-slate-800 border border-slate-700 rounded-lg pl-10 pr-4 py-2 text-white placeholder-slate-500 text-sm md:text-base"
        />
      </div>
    </div>
  </div>
);

export default ReportGenerationToolbar;
