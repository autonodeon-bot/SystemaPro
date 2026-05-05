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
  /** «Карточки» (по умолчанию) или компактная таблица */
  layout?: 'cards' | 'table';
  /** Строка таблицы (обычно <ReportTableRow … />) */
  renderTableRow?: (item: UnifiedListItem) => React.ReactNode;
}

const TABLE_HEAD = (
  <thead>
    <tr className="text-left text-xs uppercase tracking-wide text-app-text3 border-b border-app-line">
      <th className="px-2 py-2 w-10" />
      <th className="px-3 py-2">Наименование / объект</th>
      <th className="px-2 py-2">Статус</th>
      <th className="px-2 py-2">Тип</th>
      <th className="px-2 py-2">Создан</th>
      <th className="px-2 py-2 text-right">Действия</th>
    </tr>
  </thead>
);

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
  layout = 'cards',
  renderTableRow,
}) => {
  const isEmpty =
    Object.keys(groupedItems).length === 0 || filteredItems.length === 0;

  if (isEmpty) {
    return (
      <div className="space-y-4">
        <div className="text-center text-app-text3 py-20">
          {searchTerm || filterType !== 'all' || filterStatus !== 'all'
            ? 'Ничего не найдено'
            : 'Отчеты и опросные листы не найдены'}
        </div>
      </div>
    );
  }

  const useTable = layout === 'table' && renderTableRow;

  if (groupBy === 'none') {
    if (useTable) {
      return (
        <div className="overflow-x-auto rounded-lg border border-app-line bg-app-deep/40">
          <table className="w-full text-sm min-w-[720px]">{TABLE_HEAD}<tbody>{filteredItems.map((item) => (
            <Fragment key={item.id}>{renderTableRow(item)}</Fragment>
          ))}</tbody></table>
        </div>
      );
    }
    return (
      <div className="space-y-4">
        {filteredItems.map((item) => (
          <Fragment key={item.id}>{renderItem(item)}</Fragment>
        ))}
      </div>
    );
  }

  if (useTable) {
    return (
      <div className="space-y-6">
        {Object.entries(groupedItems).map(([groupKey, items]) => {
          if (items.length === 0) return null;
          const firstItem = items[0];
          const groupTitle = getGroupName(firstItem, groupBy);
          const isExpanded = expandedGroups.has(groupKey);
          return (
            <div key={groupKey} className="bg-app-panel border border-app-line rounded-lg overflow-hidden">
              <button
                type="button"
                onClick={() => {
                  const next = new Set(expandedGroups);
                  if (isExpanded) next.delete(groupKey);
                  else next.add(groupKey);
                  onExpandedGroupsChange(next);
                }}
                className="w-full flex items-center justify-between p-3 hover:bg-app-soft/50 transition-colors text-left"
              >
                <div className="flex items-center gap-2">
                  <ChevronRight
                    size={18}
                    className={`text-app-text3 transform transition-transform ${isExpanded ? 'rotate-90' : ''}`}
                  />
                  <span className="font-bold text-white">{groupTitle}</span>
                  <span className="text-app-text3 text-sm">({items.length})</span>
                </div>
              </button>
              {isExpanded && (
                <div className="border-t border-app-line overflow-x-auto">
                  <table className="w-full text-sm min-w-[720px]">
                    {TABLE_HEAD}
                    <tbody>
                      {items.map((item) => (
                        <Fragment key={item.id}>{renderTableRow(item)}</Fragment>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          );
        })}
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
          <div key={groupKey} className="bg-app-panel border border-app-line rounded-lg overflow-hidden">
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
              className="w-full flex items-center justify-between p-4 hover:bg-app-soft/50 transition-colors text-left"
            >
              <div className="flex items-center gap-3">
                <ChevronRight
                  size={20}
                  className={`text-app-text3 transform transition-transform ${isExpanded ? 'rotate-90' : ''}`}
                />
                <span className="text-lg font-bold text-app-text">{groupTitle}</span>
                <span className="text-app-text3 text-sm">({items.length})</span>
              </div>
            </button>
            {isExpanded && (
              <div className="border-t border-app-line p-4 space-y-3">
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
