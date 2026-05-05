import React from 'react';
import { Search, Trash2, LayoutGrid, List } from 'lucide-react';
import type { Branch, Enterprise, Workshop } from './types';

export interface ReportFiltersProps {
  selectedReports: Set<string>;
  filteredItemsCount: number;
  onToggleSelectAll: () => void;
  onClearSelection: () => void;
  onBulkArchive: () => void;
  onBulkDelete: () => void;
  isProcessing: boolean;
  searchTerm: string;
  onSearchTermChange: (v: string) => void;
  filterType: string;
  onFilterTypeChange: (v: string) => void;
  filterStatus: string;
  onFilterStatusChange: (v: string) => void;
  showMineOnly: boolean;
  onShowMineOnlyChange: (v: boolean) => void;
  showMineOnlyVisible: boolean;
  enterprises: Enterprise[];
  branches: Branch[];
  workshops: Workshop[];
  selectedEnterpriseId: string;
  selectedBranchId: string;
  selectedWorkshopId: string;
  onEnterpriseChange: (enterpriseId: string) => void;
  onBranchChange: (branchId: string) => void;
  onWorkshopChange: (workshopId: string) => void;
  groupBy: string;
  onGroupByChange: (v: string) => void;
  listLayout: 'cards' | 'table';
  onListLayoutChange: (v: 'cards' | 'table') => void;
  cleanupReportsDays: number;
  onCleanupReportsDaysChange: (days: number) => void;
  onCleanupOldReports: () => void;
}

const ReportFilters: React.FC<ReportFiltersProps> = ({
  selectedReports,
  filteredItemsCount,
  onToggleSelectAll,
  onClearSelection,
  onBulkArchive,
  onBulkDelete,
  isProcessing,
  searchTerm,
  onSearchTermChange,
  filterType,
  onFilterTypeChange,
  filterStatus,
  onFilterStatusChange,
  showMineOnly,
  onShowMineOnlyChange,
  showMineOnlyVisible,
  enterprises,
  branches,
  workshops,
  selectedEnterpriseId,
  selectedBranchId,
  selectedWorkshopId,
  onEnterpriseChange,
  onBranchChange,
  onWorkshopChange,
  groupBy,
  onGroupByChange,
  listLayout,
  onListLayoutChange,
  cleanupReportsDays,
  onCleanupReportsDaysChange,
  onCleanupOldReports,
}) => {
  const allSelected =
    filteredItemsCount > 0 && selectedReports.size === filteredItemsCount;

  return (
    <div className="mb-6 space-y-4">
      <div className="flex items-center justify-between p-3 bg-app-panel/50 border border-app-line rounded-lg">
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={onToggleSelectAll}
            className="px-3 py-1.5 bg-app-soft hover:bg-app-softer text-app-text rounded-lg text-sm font-semibold"
          >
            {allSelected ? 'Снять все' : 'Выделить все'}
          </button>
          {selectedReports.size > 0 && (
            <span className="text-white font-semibold">Выбрано: {selectedReports.size}</span>
          )}
        </div>
        {selectedReports.size > 0 && (
          <div className="flex gap-2">
            <button
              type="button"
              onClick={onBulkArchive}
              disabled={isProcessing}
              className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm font-semibold disabled:opacity-50"
            >
              Отправить в архив
            </button>
            <button
              type="button"
              onClick={onBulkDelete}
              disabled={isProcessing}
              className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-sm font-semibold disabled:opacity-50"
            >
              Удалить выбранные
            </button>
            <button
              type="button"
              onClick={onClearSelection}
              className="px-4 py-2 bg-app-softer hover:bg-app-soft text-app-text rounded-lg text-sm font-semibold"
            >
              Снять выделение
            </button>
          </div>
        )}
      </div>
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="flex-1 relative">
          <Search
            className="absolute left-3 top-1/2 transform -translate-y-1/2 text-app-text3"
            size={20}
          />
          <input
            type="text"
            placeholder="Поиск по названию, оборудованию, локации..."
            value={searchTerm}
            onChange={(e) => onSearchTermChange(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-app-deep border border-app-line rounded-lg text-app-text placeholder-app-text3"
          />
        </div>
      </div>

      <div className="flex flex-wrap gap-3 items-center">
        <select
          value={filterType}
          onChange={(e) => onFilterTypeChange(e.target.value)}
          className="px-4 py-2 bg-app-deep border border-app-line rounded-lg text-app-text"
        >
          <option value="all">Все типы</option>
          <option value="TECHNICAL_REPORT">Технические отчеты</option>
          <option value="EXPERTISE">Экспертизы</option>
          <option value="RESOURCE_EXTENSION">Продление ресурса</option>
          <option value="questionnaire">Опросные листы</option>
        </select>

        <select
          value={filterStatus}
          onChange={(e) => onFilterStatusChange(e.target.value)}
          className="px-4 py-2 bg-app-deep border border-app-line rounded-lg text-app-text"
        >
          <option value="all">Все статусы</option>
          <option value="DRAFT">Черновик</option>
          <option value="SIGNED">Подписан</option>
          <option value="APPROVED">Утвержден</option>
          <option value="SENT">Отправлен</option>
        </select>

        {showMineOnlyVisible && (
          <label className="flex items-center gap-2 text-app-text text-sm bg-app-deep border border-app-line rounded-lg px-3 py-2">
            <input
              type="checkbox"
              checked={showMineOnly}
              onChange={(e) => onShowMineOnlyChange(e.target.checked)}
              className="accent-blue-500"
            />
            Мои чек-листы и отчеты
          </label>
        )}

        <div className="w-full flex flex-wrap gap-3 items-end pt-2 border-t border-app-line/50 mt-2">
          <div className="min-w-[160px]">
            <label className="block text-xs text-app-text3 mb-1">Предприятие</label>
            <select
              value={selectedEnterpriseId}
              onChange={(e) => onEnterpriseChange(e.target.value)}
              className="w-full px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text focus:outline-none focus:border-accent"
            >
              <option value="">Все предприятия</option>
              {enterprises.map((ent) => (
                <option key={ent.id} value={ent.id}>
                  {ent.name}
                </option>
              ))}
            </select>
          </div>
          <div className="min-w-[160px]">
            <label className="block text-xs text-app-text3 mb-1">Филиал</label>
            <select
              value={selectedBranchId}
              onChange={(e) => onBranchChange(e.target.value)}
              disabled={!selectedEnterpriseId}
              className="w-full px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text focus:outline-none focus:border-accent disabled:opacity-50"
            >
              <option value="">Все филиалы</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </div>
          <div className="min-w-[160px]">
            <label className="block text-xs text-app-text3 mb-1">Цех</label>
            <select
              value={selectedWorkshopId}
              onChange={(e) => onWorkshopChange(e.target.value)}
              disabled={!selectedBranchId}
              className="w-full px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text focus:outline-none focus:border-accent disabled:opacity-50"
            >
              <option value="">Все цеха</option>
              {workshops.map((w) => (
                <option key={w.id} value={w.id}>
                  {w.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        <select
          value={groupBy}
          onChange={(e) => onGroupByChange(e.target.value)}
          className="px-4 py-2 bg-app-deep border border-app-line rounded-lg text-app-text"
          title="Группировка отчетов"
        >
          <option value="none">Без группировки</option>
          <option value="enterprise">По предприятию</option>
          <option value="branch">По филиалу</option>
          <option value="workshop">По цеху</option>
          <option value="opo">По ОПО</option>
        </select>

        <div
          className="inline-flex rounded-lg border border-app-line overflow-hidden"
          title="Вид списка"
        >
          <button
            type="button"
            onClick={() => onListLayoutChange('cards')}
            className={`px-3 py-2 flex items-center gap-1.5 text-sm font-medium ${
              listLayout === 'cards' ? 'bg-accent text-white' : 'bg-app-deep text-app-text3 hover:text-app-text'
            }`}
          >
            <LayoutGrid size={16} /> Карточки
          </button>
          <button
            type="button"
            onClick={() => onListLayoutChange('table')}
            className={`px-3 py-2 flex items-center gap-1.5 text-sm font-medium border-l border-app-line ${
              listLayout === 'table' ? 'bg-accent text-white' : 'bg-app-deep text-app-text3 hover:text-app-text'
            }`}
          >
            <List size={16} /> Таблица
          </button>
        </div>

        <div className="flex items-center gap-2 sm:ml-auto">
          <span className="text-app-text3 text-sm hidden sm:inline">Очистка:</span>
          <select
            value={cleanupReportsDays}
            onChange={(e) => onCleanupReportsDaysChange(parseInt(e.target.value, 10))}
            className="px-3 py-2 bg-app-deep border border-app-line rounded-lg text-app-text text-sm"
            title="Удалить отчеты старше N дней"
          >
            <option value={30}>Старше 30 дней</option>
            <option value={90}>Старше 90 дней</option>
            <option value={180}>Старше 180 дней</option>
            <option value={365}>Старше 365 дней</option>
          </select>
          <button
            type="button"
            onClick={onCleanupOldReports}
            className="flex items-center gap-2 px-3 py-2 bg-red-500/10 hover:bg-red-500/20 border border-red-500/20 text-red-300 rounded-lg text-sm font-semibold"
            title="Удалить старые отчеты"
          >
            <Trash2 size={16} />
            <span className="hidden sm:inline">Удалить старые отчеты</span>
            <span className="sm:hidden">Очистить</span>
          </button>
        </div>
      </div>
    </div>
  );
};

export default ReportFilters;
