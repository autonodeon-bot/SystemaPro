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
    <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
    <input
      type="text"
      placeholder="Поиск по названию..."
      value={searchTerm}
      onChange={(e) => onSearchTermChange(e.target.value)}
      className="w-full bg-slate-800 border border-slate-700 rounded-lg pl-10 pr-4 py-2 text-white placeholder-slate-500"
    />
  </div>
);

export default EquipmentHierarchySearch;
