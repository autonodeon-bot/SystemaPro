import React from 'react';
import { FileText, Building2, ChevronDown, ChevronRight } from 'lucide-react';
import type { Inspection } from './types';
import InspectionCard from './InspectionCard';

interface InspectionsListViewProps {
  loading: boolean;
  filteredInspections: Inspection[];
  groupBy: 'none' | 'enterprise' | 'branch' | 'workshop' | 'inspection_type';
  groupedInspections: [string, Inspection[]][] | null;
  expandedGroups: Set<string>;
  onToggleGroup: (key: string) => void;
  selectedInspectionIds: Set<string>;
  onToggleSelect: (id: string) => void;
  onOpenDetails: (inspection: Inspection) => void;
  canApprove: boolean;
  onApprove: (id: string) => void;
  onDelete: (id: string) => void;
}

const InspectionsListView: React.FC<InspectionsListViewProps> = ({
  loading,
  filteredInspections,
  groupBy,
  groupedInspections,
  expandedGroups,
  onToggleGroup,
  selectedInspectionIds,
  onToggleSelect,
  onOpenDetails,
  canApprove,
  onApprove,
  onDelete,
}) => {
  if (loading) {
    return (
      <div className="text-center py-12">
        <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-accent" />
        <p className="text-slate-400 mt-4">Загрузка чек-листов...</p>
      </div>
    );
  }

  if (filteredInspections.length === 0) {
    return (
      <div className="text-center py-12 bg-secondary/50 rounded-lg">
        <FileText className="mx-auto text-slate-400 mb-4" size={48} />
        <p className="text-slate-400">Чек-листы не найдены</p>
      </div>
    );
  }

  if (groupBy !== 'none' && groupedInspections && groupedInspections.length > 0) {
    return (
      <div className="space-y-4">
        {groupedInspections.map(([groupKey, items]) => {
          const isCollapsed = expandedGroups.has(groupKey);
          const isExpanded = expandedGroups.size === 0 || !isCollapsed;
          return (
            <div key={groupKey} className="rounded-lg border border-slate-700 overflow-hidden">
              <button
                type="button"
                onClick={() => onToggleGroup(groupKey)}
                className="w-full flex items-center gap-2 px-4 py-3 bg-secondary/70 hover:bg-secondary text-left text-white font-medium"
              >
                {isExpanded ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
                <Building2 size={18} className="text-accent" />
                <span>{groupKey}</span>
                <span className="text-slate-400 text-sm font-normal">({items.length})</span>
              </button>
              {isExpanded && (
                <div className="p-2 space-y-2 bg-secondary/30">
                  {items.map((insp) => (
                    <InspectionCard
                      key={insp.id}
                      inspection={insp}
                      selected={selectedInspectionIds.has(insp.id)}
                      canApprove={canApprove}
                      onToggleSelect={onToggleSelect}
                      onOpenDetails={onOpenDetails}
                      onApprove={onApprove}
                      onDelete={onDelete}
                    />
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {filteredInspections.map((insp) => (
        <InspectionCard
          key={insp.id}
          inspection={insp}
          selected={selectedInspectionIds.has(insp.id)}
          canApprove={canApprove}
          onToggleSelect={onToggleSelect}
          onOpenDetails={onOpenDetails}
          onApprove={onApprove}
          onDelete={onDelete}
        />
      ))}
    </div>
  );
};

export default InspectionsListView;
