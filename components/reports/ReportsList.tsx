import React, { Fragment } from 'react';
import { ChevronRight } from 'lucide-react';
import type { UnifiedListItem } from './types';
import { getGroupName } from './reportUtils';

export interface ReportsListProps {
  groupedItems: Record<string, UnifiedListItem[]>;
  filteredItems: UnifiedListItem[];
  groupBy: string;
  expandedGroups: Set<string>;
  onExpandedGroupsChange: (next: Set<string>) => void;
  searchTerm: string;
  filterType: string;
  filterStatus: string;
  renderItem: (item: UnifiedListItem) => React.ReactNode;
}

const ReportsList: React.FC<ReportsListProps> = ({
  groupedItems,
  filteredItems,
  groupBy,
  expandedGroups,
  onExpandedGroupsChange,
  searchTerm,
  filterType,
  filterStatus,
  renderItem,
}) => {
  const isEmpty =
    Object.keys(groupedItems).length === 0 || filteredItems.length === 0;

  if (isEmpty) {
    return (
      <div className="space-y-4">
        <div className="text-center text-slate-400 py-20">
          {searchTerm || filterType !== 'all' || filterStatus !== 'all'
            ? 'Ничего не найдено'
            : 'Отчеты и опросные листы не найдены'}
        </div>
      </div>
    );
  }

  if (groupBy === 'none') {
    return (
      <div className="space-y-4">
        {filteredItems.map((item) => (
          <Fragment key={item.id}>{renderItem(item)}</Fragment>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {Object.entries(groupedItems).map(([groupKey, items]) => {
        if (items.length === 0) return null;
        const firstItem = items[0];
        const groupTitle = getGroupName(firstItem, groupBy);
        const isExpanded = expandedGroups.has(groupKey);

        return (
          <div key={groupKey} className="bg-slate-800 border border-slate-700 rounded-lg overflow-hidden">
            <button
              type="button"
              onClick={() => {
                const next = new Set(expandedGroups);
                if (isExpanded) {
                  next.delete(groupKey);
                } else {
                  next.add(groupKey);
                }
                onExpandedGroupsChange(next);
              }}
              className="w-full flex items-center justify-between p-4 hover:bg-slate-700/50 transition-colors"
            >
              <div className="flex items-center gap-3">
                <ChevronRight
                  size={20}
                  className={`text-slate-400 transform transition-transform ${isExpanded ? 'rotate-90' : ''}`}
                />
                <span className="text-lg font-bold text-white">{groupTitle}</span>
                <span className="text-slate-400 text-sm">({items.length})</span>
              </div>
            </button>
            {isExpanded && (
              <div className="border-t border-slate-700 p-4 space-y-3">
                {items.map((item) => (
                  <Fragment key={item.id}>{renderItem(item)}</Fragment>
                ))}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

export default ReportsList;
