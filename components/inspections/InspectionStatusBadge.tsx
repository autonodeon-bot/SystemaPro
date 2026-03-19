import React from 'react';
import { getInspectionStatusColorClass, getInspectionStatusLabel } from './inspectionStatus';

interface InspectionStatusBadgeProps {
  status: string;
  className?: string;
}

const InspectionStatusBadge: React.FC<InspectionStatusBadgeProps> = ({ status, className = '' }) => (
  <span
    className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium border ${getInspectionStatusColorClass(status)} ${className}`.trim()}
  >
    {getInspectionStatusLabel(status)}
  </span>
);

export default InspectionStatusBadge;
