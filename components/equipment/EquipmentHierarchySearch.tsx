import React from 'react';
import { Search } from 'lucide-react';

export interface EquipmentHierarchySearchProps {
  searchTerm: string;
  onSearchTermChange: (value: string) => void;
}

const EquipmentHierarchySearch: React.FC<EquipmentHierarchySearchProps> = ({
  searchTerm,
  onSearchTermChange,
}) => (
  <div className="relative">
    <Search
      className="absolute left-3 top-1/2 transform -translate-y-1/2"
      size={18}
      style={{ color: 'var(--text-muted)' }}
    />
    <input
      type="text"
      placeholder="Поиск по названию..."
      value={searchTerm}
      onChange={(e) => onSearchTermChange(e.target.value)}
      className="ind-input"
      style={{ paddingLeft: '36px', height: '40px' }}
    />
  </div>
);

export default EquipmentHierarchySearch;
