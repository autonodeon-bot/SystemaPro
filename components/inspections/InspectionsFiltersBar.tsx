import React from 'react';
import { Search, Download, Trash2 } from 'lucide-react';
import type { Equipment, Enterprise, Branch, Workshop } from './types';

export type InspectionsGroupBy = 'none' | 'enterprise' | 'branch' | 'workshop' | 'inspection_type';

interface InspectionsFiltersBarProps {
  selectedCount: number;
  isProcessing: boolean;
  onBulkArchive: () => void;
  onBulkDelete: () => void;
  onClearSelection: () => void;
  searchTerm: string;
  onSearchTermChange: (value: string) => void;
  equipment: Equipment[];
  selectedEquipment: string;
  onSelectedEquipmentChange: (value: string) => void;
  selectedStatus: string;
  onSelectedStatusChange: (value: string) => void;
  selectedInspectionType: string;
  onSelectedInspectionTypeChange: (value: string) => void;
  enterprises: Enterprise[];
  branches: Branch[];
  workshops: Workshop[];
  selectedEnterpriseId: string;
  selectedBranchId: string;
  selectedWorkshopId: string;
  onEnterpriseChange: (enterpriseId: string) => void;
  onBranchChange: (branchId: string) => void;
  onWorkshopChange: (workshopId: string) => void;
  groupBy: InspectionsGroupBy;
  onGroupByChange: (value: InspectionsGroupBy) => void;
  onExportCsv: () => void;
  cleanupInspectionsDays: number;
  onCleanupDaysChange: (days: number) => void;
  onCleanupOldInspections: () => void;
}

const InspectionsFiltersBar: React.FC<InspectionsFiltersBarProps> = ({
  selectedCount,
  isProcessing,
  onBulkArchive,
  onBulkDelete,
  onClearSelection,
  searchTerm,
  onSearchTermChange,
  equipment,
  selectedEquipment,
  onSelectedEquipmentChange,
  selectedStatus,
  onSelectedStatusChange,
  selectedInspectionType,
  onSelectedInspectionTypeChange,
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
  onExportCsv,
  cleanupInspectionsDays,
  onCleanupDaysChange,
  onCleanupOldInspections,
}) => (
  <div className="bg-secondary/50 rounded-lg p-4 space-y-4">
    {selectedCount > 0 && (
      <div className="flex items-center justify-between p-3 bg-accent/20 border border-accent/30 rounded-lg">
        <span className="text-white font-semibold">Выбрано: {selectedCount}</span>
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
            className="px-4 py-2 bg-slate-600 hover:bg-slate-700 text-white rounded-lg text-sm font-semibold"
          >
            Снять выделение
          </button>
        </div>
      </div>
    )}
    <div className="flex flex-wrap gap-4">
      <div className="flex-1 min-w-[200px]">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={18} />
          <input
            type="text"
            placeholder="Поиск по оборудованию, заключению..."
            value={searchTerm}
            onChange={(e) => onSearchTermChange(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
          />
        </div>
      </div>

      <div className="min-w-[200px]">
        <select
          value={selectedEquipment}
          onChange={(e) => onSelectedEquipmentChange(e.target.value)}
          className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
        >
          <option value="all">Все оборудование</option>
          {equipment.map((eq) => (
            <option key={eq.id} value={eq.id}>
              {eq.name}
            </option>
          ))}
        </select>
      </div>

      <div className="min-w-[150px]">
        <select
          value={selectedStatus}
          onChange={(e) => onSelectedStatusChange(e.target.value)}
          className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
        >
          <option value="all">Все статусы</option>
          <option value="DRAFT">Черновик</option>
          <option value="SIGNED">Подписан</option>
          <option value="REJECTED">Отклонен</option>
        </select>
      </div>

      <div className="min-w-[180px]">
        <select
          value={selectedInspectionType}
          onChange={(e) => onSelectedInspectionTypeChange(e.target.value)}
          className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
        >
          <option value="all">Все типы обследования</option>
          <option value="VISUAL">VISUAL</option>
          <option value="NDT">NDT</option>
          <option value="QUESTIONNAIRE">QUESTIONNAIRE</option>
          <option value="EXPERTISE">EXPERTISE</option>
        </select>
      </div>

      <div className="w-full flex flex-wrap gap-4 pt-2 border-t border-slate-600/50 mt-2">
        <div className="min-w-[180px]">
          <label className="block text-xs text-slate-400 mb-1">Предприятие</label>
          <select
            value={selectedEnterpriseId}
            onChange={(e) => onEnterpriseChange(e.target.value)}
            className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
          >
            <option value="">Все предприятия</option>
            {enterprises.map((ent) => (
              <option key={ent.id} value={ent.id}>
                {ent.name}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-[180px]">
          <label className="block text-xs text-slate-400 mb-1">Филиал</label>
          <select
            value={selectedBranchId}
            onChange={(e) => onBranchChange(e.target.value)}
            disabled={!selectedEnterpriseId}
            className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent disabled:opacity-50"
          >
            <option value="">Все филиалы</option>
            {branches.map((b) => (
              <option key={b.id} value={b.id}>
                {b.name}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-[180px]">
          <label className="block text-xs text-slate-400 mb-1">Цех</label>
          <select
            value={selectedWorkshopId}
            onChange={(e) => onWorkshopChange(e.target.value)}
            disabled={!selectedBranchId}
            className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent disabled:opacity-50"
          >
            <option value="">Все цеха</option>
            {workshops.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-[160px]">
          <label className="block text-xs text-slate-400 mb-1">Группировка</label>
          <select
            value={groupBy}
            onChange={(e) => onGroupByChange(e.target.value as InspectionsGroupBy)}
            className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
          >
            <option value="none">Без группировки</option>
            <option value="enterprise">По предприятию</option>
            <option value="branch">По филиалу</option>
            <option value="workshop">По цеху</option>
            <option value="inspection_type">По типу обследования</option>
          </select>
        </div>
      </div>

      <div className="flex items-center gap-2 sm:ml-auto">
        <button
          type="button"
          onClick={onExportCsv}
          className="flex items-center gap-2 px-3 py-2 bg-accent/10 hover:bg-accent/20 border border-accent/20 text-accent rounded-lg text-sm font-semibold"
          title="Экспорт текущей выборки в CSV"
        >
          <Download size={16} />
          <span className="hidden sm:inline">Экспорт CSV</span>
        </button>
        <select
          value={cleanupInspectionsDays}
          onChange={(e) => onCleanupDaysChange(parseInt(e.target.value, 10))}
          className="px-3 py-2 bg-primary border border-slate-600 rounded-lg text-white text-sm focus:outline-none focus:border-accent"
          title="Удалить чек-листы старше N дней"
        >
          <option value={30}>Старше 30 дней</option>
          <option value={90}>Старше 90 дней</option>
          <option value={180}>Старше 180 дней</option>
          <option value={365}>Старше 365 дней</option>
        </select>
        <button
          type="button"
          onClick={onCleanupOldInspections}
          className="flex items-center gap-2 px-3 py-2 bg-red-500/10 hover:bg-red-500/20 border border-red-500/20 text-red-300 rounded-lg text-sm font-semibold"
          title="Удалить старые чек-листы"
        >
          <Trash2 size={16} />
          <span className="hidden sm:inline">Удалить старые чек-листы</span>
          <span className="sm:hidden">Очистить</span>
        </button>
      </div>
    </div>
  </div>
);

export default InspectionsFiltersBar;
