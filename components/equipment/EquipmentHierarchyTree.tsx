import React from 'react';
import { NavigateFunction } from 'react-router-dom';
import {
  Plus,
  ChevronRight,
  ChevronDown,
  Building2,
  Network,
  Factory,
  Box,
  Trash2,
  MapPin,
  Users,
  Info,
} from 'lucide-react';
import type {
  Branch,
  CreateEntityType,
  Enterprise,
  Equipment,
  EquipmentType,
  HierarchyInfoType,
  Workshop,
} from './types';

export interface EquipmentHierarchyTreeProps {
  enterprises: Enterprise[];
  branches: Record<string, Branch[]>;
  workshops: Record<string, Workshop[]>;
  equipment: Record<string, Equipment[]>;
  equipmentTypes: EquipmentType[];
  expanded: Record<string, boolean>;
  navigate: NavigateFunction;
  onToggleExpand: (key: string) => void;
  onCreateEnterprise: () => void;
  onCreateClick: (
    type: CreateEntityType,
    parentId?: string,
    parentName?: string
  ) => void;
  onPrepareEquipmentCreateFromType: (
    workshopId: string,
    workshopName: string,
    typeId: string
  ) => void;
  onShowInfo: (type: HierarchyInfoType, id: string, name: string) => void;
  onAssignEngineers: (
    type: CreateEntityType,
    id: string,
    name: string
  ) => void;
  onDeleteEquipment: (id: string) => void;
}

const EquipmentHierarchyTree: React.FC<EquipmentHierarchyTreeProps> = ({
  enterprises,
  branches,
  workshops,
  equipment,
  equipmentTypes,
  expanded,
  navigate,
  onToggleExpand,
  onCreateEnterprise,
  onCreateClick,
  onPrepareEquipmentCreateFromType,
  onShowInfo,
  onAssignEngineers,
  onDeleteEquipment,
}) => (
  <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
    <div className="mb-4">
      <button
        type="button"
        onClick={onCreateEnterprise}
        className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20"
      >
        <Plus size={16} /> Создать предприятие
      </button>
    </div>

    {enterprises.map((enterprise) => (
      <div key={enterprise.id} className="mb-4">
        <div className="flex items-center justify-between p-3 bg-slate-900 rounded-lg hover:bg-slate-800 transition-colors">
          <div className="flex items-center gap-3 flex-1">
            <button
              type="button"
              onClick={() => onToggleExpand(`enterprise_${enterprise.id}`)}
              className="text-slate-400 hover:text-white"
            >
              {expanded[`enterprise_${enterprise.id}`] ? (
                <ChevronDown size={20} />
              ) : (
                <ChevronRight size={20} />
              )}
            </button>
            <Building2 className="text-accent" size={20} />
            <span className="text-white font-bold">{enterprise.name}</span>
            {enterprise.code && (
              <span className="text-slate-400 text-sm">({enterprise.code})</span>
            )}
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => onShowInfo('enterprise', enterprise.id, enterprise.name)}
              className="text-blue-400 hover:text-blue-300 p-2 rounded hover:bg-slate-700"
              title="Информация"
            >
              <Info size={18} />
            </button>
            <button
              type="button"
              onClick={() => onAssignEngineers('enterprise', enterprise.id, enterprise.name)}
              className="text-green-400 hover:text-green-300 p-2 rounded hover:bg-slate-700"
              title="Назначить инженеров"
            >
              <Users size={18} />
            </button>
            <button
              type="button"
              onClick={() => onCreateClick('branch', enterprise.id, enterprise.name)}
              className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
              title="Создать филиал"
            >
              <Plus size={18} />
            </button>
          </div>
        </div>

        {expanded[`enterprise_${enterprise.id}`] && (
          <div className="ml-8 mt-2 space-y-2">
            {(branches[enterprise.id] || []).map((branch) => (
              <div key={branch.id} className="mb-2">
                <div className="flex items-center justify-between p-2 bg-slate-900/50 rounded-lg hover:bg-slate-800 transition-colors">
                  <div className="flex items-center gap-3 flex-1">
                    <button
                      type="button"
                      onClick={() => onToggleExpand(`branch_${branch.id}`)}
                      className="text-slate-400 hover:text-white"
                    >
                      {expanded[`branch_${branch.id}`] ? (
                        <ChevronDown size={18} />
                      ) : (
                        <ChevronRight size={18} />
                      )}
                    </button>
                    <Network className="text-blue-400" size={18} />
                    <span className="text-slate-200">{branch.name}</span>
                    {branch.code && (
                      <span className="text-slate-500 text-sm">({branch.code})</span>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => onShowInfo('branch', branch.id, branch.name)}
                      className="text-blue-400 hover:text-blue-300 p-2 rounded hover:bg-slate-700"
                      title="Информация"
                    >
                      <Info size={16} />
                    </button>
                    <button
                      type="button"
                      onClick={() => onAssignEngineers('branch', branch.id, branch.name)}
                      className="text-green-400 hover:text-green-300 p-2 rounded hover:bg-slate-700"
                      title="Назначить инженеров"
                    >
                      <Users size={16} />
                    </button>
                    <button
                      type="button"
                      onClick={() => onCreateClick('workshop', branch.id, branch.name)}
                      className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                      title="Создать цех"
                    >
                      <Plus size={16} />
                    </button>
                  </div>
                </div>

                {expanded[`branch_${branch.id}`] && (
                  <div className="ml-6 mt-2 space-y-2">
                    {(workshops[branch.id] || []).map((workshop) => (
                      <div key={workshop.id} className="mb-2">
                        <div className="flex items-center justify-between p-2 bg-slate-900/30 rounded-lg hover:bg-slate-800 transition-colors">
                          <div className="flex items-center gap-3 flex-1">
                            <button
                              type="button"
                              onClick={() => onToggleExpand(`workshop_${workshop.id}`)}
                              className="text-slate-400 hover:text-white"
                            >
                              {expanded[`workshop_${workshop.id}`] ? (
                                <ChevronDown size={16} />
                              ) : (
                                <ChevronRight size={16} />
                              )}
                            </button>
                            <Factory className="text-green-400" size={16} />
                            <span className="text-slate-300 text-sm">{workshop.name}</span>
                            {workshop.code && (
                              <span className="text-slate-500 text-xs">({workshop.code})</span>
                            )}
                          </div>
                          <div className="flex items-center gap-2">
                            <button
                              type="button"
                              onClick={() => onShowInfo('workshop', workshop.id, workshop.name)}
                              className="text-blue-400 hover:text-blue-300 p-2 rounded hover:bg-slate-700"
                              title="Информация"
                            >
                              <Info size={14} />
                            </button>
                            <button
                              type="button"
                              onClick={() => onAssignEngineers('workshop', workshop.id, workshop.name)}
                              className="text-green-400 hover:text-green-300 p-2 rounded hover:bg-slate-700"
                              title="Назначить инженеров"
                            >
                              <Users size={14} />
                            </button>
                            <button
                              type="button"
                              onClick={() => onCreateClick('equipment', workshop.id, workshop.name)}
                              className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                              title="Создать оборудование"
                            >
                              <Plus size={14} />
                            </button>
                          </div>
                        </div>

                        {expanded[`workshop_${workshop.id}`] && (
                          <div className="ml-6 mt-2 space-y-2">
                            {equipmentTypes.map((type) => (
                              <div key={type.id} className="mb-2">
                                <div className="flex items-center justify-between p-2 bg-slate-900/20 rounded-lg hover:bg-slate-800 transition-colors">
                                  <div className="flex items-center gap-3 flex-1">
                                    <button
                                      type="button"
                                      onClick={() =>
                                        onToggleExpand(`type_${workshop.id}_${type.id}`)
                                      }
                                      className="text-slate-400 hover:text-white"
                                    >
                                      {expanded[`type_${workshop.id}_${type.id}`] ? (
                                        <ChevronDown size={14} />
                                      ) : (
                                        <ChevronRight size={14} />
                                      )}
                                    </button>
                                    <Box className="text-yellow-400" size={14} />
                                    <span className="text-slate-300 text-sm">{type.name}</span>
                                  </div>
                                  <div className="flex items-center gap-2">
                                    <button
                                      type="button"
                                      onClick={() =>
                                        onPrepareEquipmentCreateFromType(
                                          workshop.id,
                                          workshop.name,
                                          type.id
                                        )
                                      }
                                      className="text-accent hover:text-blue-400 p-2 rounded hover:bg-slate-700"
                                      title="Создать оборудование в этом типе"
                                    >
                                      <Plus size={14} />
                                    </button>
                                  </div>
                                </div>

                                {expanded[`type_${workshop.id}_${type.id}`] && (
                                  <div className="ml-6 mt-2 space-y-1">
                                    {(equipment[workshop.id] || [])
                                      .filter((eq) => eq.type_id === type.id)
                                      .map((eq) => (
                                        <div
                                          key={eq.id}
                                          className="flex items-center justify-between p-2 bg-slate-950 rounded hover:bg-slate-900 transition-colors"
                                        >
                                          <div className="flex items-center gap-2 flex-1">
                                            <MapPin className="text-slate-500" size={12} />
                                            <button
                                              type="button"
                                              onClick={() => navigate(`/equipment/${eq.id}`)}
                                              className="text-slate-200 hover:text-white text-xs underline-offset-2 hover:underline text-left"
                                              title="Открыть карточку оборудования"
                                            >
                                              {eq.name}
                                            </button>
                                            {eq.serial_number && (
                                              <span className="text-slate-500 text-xs">
                                                №{eq.serial_number}
                                              </span>
                                            )}
                                          </div>
                                          <div className="flex items-center gap-1">
                                            <button
                                              type="button"
                                              onClick={() =>
                                                onShowInfo('equipment', eq.id, eq.name)
                                              }
                                              className="text-blue-400 hover:text-blue-300 p-1"
                                              title="Информация"
                                            >
                                              <Info size={12} />
                                            </button>
                                            <button
                                              type="button"
                                              onClick={() =>
                                                onAssignEngineers('equipment', eq.id, eq.name)
                                              }
                                              className="text-green-400 hover:text-green-300 p-1"
                                              title="Назначить инженеров"
                                            >
                                              <Users size={12} />
                                            </button>
                                            <button
                                              type="button"
                                              onClick={() => onDeleteEquipment(eq.id)}
                                              className="text-red-400 hover:text-red-300 p-1"
                                              title="Удалить"
                                            >
                                              <Trash2 size={12} />
                                            </button>
                                          </div>
                                        </div>
                                      ))}
                                  </div>
                                )}
                              </div>
                            ))}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    ))}

    {enterprises.length === 0 && (
      <div className="text-center text-slate-400 py-10">
        Предприятия не добавлены. Нажмите &quot;Создать предприятие&quot; для начала.
      </div>
    )}
  </div>
);

export default EquipmentHierarchyTree;
