import React from 'react';
import { Package, Calendar, FileText, MapPin, Eye, Trash2, CheckCircle2, Building2 } from 'lucide-react';
import type { Inspection } from './types';
import InspectionStatusBadge from './InspectionStatusBadge';
import { formatInspectionDate, inspectionHierarchySubtitle } from './inspectionUtils';

interface InspectionCardProps {
  inspection: Inspection;
  selected: boolean;
  canApprove: boolean;
  onToggleSelect: (id: string) => void;
  onOpenDetails: (inspection: Inspection) => void;
  onApprove: (id: string) => void;
  onDelete: (id: string) => void;
}

const InspectionCard: React.FC<InspectionCardProps> = ({
  inspection: insp,
  selected,
  canApprove,
  onToggleSelect,
  onOpenDetails,
  onApprove,
  onDelete,
}) => {
  const hierarchy = inspectionHierarchySubtitle(insp);

  return (
    <div className="bg-app-panel rounded-lg p-4 hover:bg-app-soft transition-colors border border-app-line">
      <div className="flex items-start justify-between gap-3">
        <input
          type="checkbox"
          checked={selected}
          onChange={(e) => {
            e.stopPropagation();
            onToggleSelect(insp.id);
          }}
          onClick={(e) => e.stopPropagation()}
          className="mt-1 rounded"
        />
        <div
          className="flex-1 cursor-pointer"
          onClick={() => onOpenDetails(insp)}
        >
          <div className="flex items-center gap-3 mb-2">
            <Package className="text-accent" size={20} />
            <h3 className="font-semibold text-app-text">{insp.equipment_name || 'Неизвестное оборудование'}</h3>
            <InspectionStatusBadge status={insp.status} />
            <span className="inline-flex items-center px-2 py-1 rounded text-xs font-medium border border-accent/30 text-accent bg-accent/10">
              {insp.inspection_type || 'UNSPECIFIED'}
            </span>
          </div>
          {hierarchy && (
            <p className="text-xs text-app-text3 mb-2 flex items-center gap-1">
              <Building2 size={12} />
              {hierarchy}
            </p>
          )}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            {insp.equipment_location && (
              <div className="flex items-center gap-2 text-app-text3">
                <MapPin size={14} />
                <span>{insp.equipment_location}</span>
              </div>
            )}
            <div className="flex items-center gap-2 text-app-text3">
              <Calendar size={14} />
              <span>{formatInspectionDate(insp.date_performed)}</span>
            </div>
            <div className="flex items-center gap-2 text-app-text3">
              <FileText size={14} />
              <span>ID: {insp.id.substring(0, 8)}...</span>
            </div>
            {insp.conclusion && (
              <div className="text-app-text2 truncate">
                {insp.conclusion.substring(0, 50)}...
              </div>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2 flex-shrink-0">
          {canApprove && String(insp.status || '').toUpperCase() !== 'APPROVED' && (
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                onApprove(insp.id);
              }}
              className="p-2 rounded-lg text-green-300 hover:bg-green-500/10 border border-green-500/20"
              title="Утвердить чек-лист"
            >
              <CheckCircle2 size={16} />
            </button>
          )}
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              onDelete(insp.id);
            }}
            className="p-2 rounded-lg text-red-300 hover:bg-red-500/10 border border-red-500/20"
            title="Удалить чек-лист"
          >
            <Trash2 size={16} />
          </button>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              onOpenDetails(insp);
            }}
            className="p-2 text-app-text3 hover:text-accent hover:bg-app-soft rounded transition-colors"
            title="Просмотр деталей"
          >
            <Eye size={20} />
          </button>
        </div>
      </div>
    </div>
  );
};

export default InspectionCard;
