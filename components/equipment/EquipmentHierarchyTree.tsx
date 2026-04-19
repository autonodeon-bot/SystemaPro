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

const rowBase: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  padding: '8px 10px',
  borderRadius: 'var(--radius-xs, 6px)',
  transition: 'background 0.12s ease, border-color 0.12s ease',
  border: '1px solid transparent',
};

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
  <div className="sp-surface" style={{ padding: '16px' }}>
    <div className="mb-3">
      <button
        type="button"
        onClick={onCreateEnterprise}
        className="ind-btn ind-btn--primary"
      >
        <Plus size={14} /> Создать предприятие
      </button>
    </div>

    {enterprises.map((enterprise) => (
      <div key={enterprise.id} className="mb-3">
        <div
          style={{
            ...rowBase,
            background: 'var(--bg-tertiary)',
            borderColor: 'var(--border-subtle, var(--border))',
          }}
        >
          <div className="flex items-center gap-2 flex-1 min-w-0">
            <button
              type="button"
              onClick={() => onToggleExpand(`enterprise_${enterprise.id}`)}
              className="ind-btn"
              style={{ height: 24, width: 24, padding: 0, color: 'var(--text-muted)' }}
              aria-label={expanded[`enterprise_${enterprise.id}`] ? 'Свернуть' : 'Развернуть'}
            >
              {expanded[`enterprise_${enterprise.id}`] ? (
                <ChevronDown size={16} />
              ) : (
                <ChevronRight size={16} />
              )}
            </button>
            <Building2 size={16} style={{ color: 'var(--accent)' }} />
            <span className="font-semibold text-sm truncate" style={{ color: 'var(--text-primary)', letterSpacing: '-0.01em' }}>
              {enterprise.name}
            </span>
            {enterprise.code && (
              <span className="text-xs tabular-nums" style={{ color: 'var(--text-muted)' }}>
                ({enterprise.code})
              </span>
            )}
          </div>
          <div className="flex items-center gap-1 flex-shrink-0">
            <button
              type="button"
              onClick={() => onShowInfo('enterprise', enterprise.id, enterprise.name)}
              className="ind-btn"
              style={{ padding: '0 6px', color: 'var(--accent)' }}
              title="Информация"
            >
              <Info size={14} />
            </button>
            <button
              type="button"
              onClick={() => onAssignEngineers('enterprise', enterprise.id, enterprise.name)}
              className="ind-btn"
              style={{ padding: '0 6px', color: 'var(--success)' }}
              title="Назначить инженеров"
            >
              <Users size={14} />
            </button>
            <button
              type="button"
              onClick={() => onCreateClick('branch', enterprise.id, enterprise.name)}
              className="ind-btn"
              style={{ padding: '0 6px', color: 'var(--accent)' }}
              title="Создать филиал"
            >
              <Plus size={14} />
            </button>
          </div>
        </div>

        {expanded[`enterprise_${enterprise.id}`] && (
          <div className="ml-6 mt-1.5 space-y-1.5" style={{ borderLeft: '1px dashed var(--border)', paddingLeft: '10px' }}>
            {(branches[enterprise.id] || []).map((branch) => (
              <div key={branch.id}>
                <div
                  style={{
                    ...rowBase,
                    background: 'color-mix(in srgb, var(--bg-tertiary) 60%, transparent)',
                  }}
                >
                  <div className="flex items-center gap-2 flex-1 min-w-0">
                    <button
                      type="button"
                      onClick={() => onToggleExpand(`branch_${branch.id}`)}
                      className="ind-btn"
                      style={{ height: 22, width: 22, padding: 0, color: 'var(--text-muted)' }}
                    >
                      {expanded[`branch_${branch.id}`] ? (
                        <ChevronDown size={14} />
                      ) : (
                        <ChevronRight size={14} />
                      )}
                    </button>
                    <Network size={14} style={{ color: 'var(--accent)' }} />
                    <span className="text-sm truncate" style={{ color: 'var(--text-primary)' }}>
                      {branch.name}
                    </span>
                    {branch.code && (
                      <span className="text-xs tabular-nums" style={{ color: 'var(--text-muted)' }}>
                        ({branch.code})
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-1 flex-shrink-0">
                    <button
                      type="button"
                      onClick={() => onShowInfo('branch', branch.id, branch.name)}
                      className="ind-btn"
                      style={{ padding: '0 6px', color: 'var(--accent)' }}
                      title="Информация"
                    >
                      <Info size={13} />
                    </button>
                    <button
                      type="button"
                      onClick={() => onAssignEngineers('branch', branch.id, branch.name)}
                      className="ind-btn"
                      style={{ padding: '0 6px', color: 'var(--success)' }}
                      title="Назначить инженеров"
                    >
                      <Users size={13} />
                    </button>
                    <button
                      type="button"
                      onClick={() => onCreateClick('workshop', branch.id, branch.name)}
                      className="ind-btn"
                      style={{ padding: '0 6px', color: 'var(--accent)' }}
                      title="Создать цех"
                    >
                      <Plus size={13} />
                    </button>
                  </div>
                </div>

                {expanded[`branch_${branch.id}`] && (
                  <div className="ml-5 mt-1.5 space-y-1.5" style={{ borderLeft: '1px dashed var(--border)', paddingLeft: '10px' }}>
                    {(workshops[branch.id] || []).map((workshop) => (
                      <div key={workshop.id}>
                        <div
                          style={{
                            ...rowBase,
                            background: 'color-mix(in srgb, var(--bg-tertiary) 40%, transparent)',
                          }}
                        >
                          <div className="flex items-center gap-2 flex-1 min-w-0">
                            <button
                              type="button"
                              onClick={() => onToggleExpand(`workshop_${workshop.id}`)}
                              className="ind-btn"
                              style={{ height: 20, width: 20, padding: 0, color: 'var(--text-muted)' }}
                            >
                              {expanded[`workshop_${workshop.id}`] ? (
                                <ChevronDown size={13} />
                              ) : (
                                <ChevronRight size={13} />
                              )}
                            </button>
                            <Factory size={13} style={{ color: 'var(--success)' }} />
                            <span className="text-xs truncate" style={{ color: 'var(--text-primary)' }}>
                              {workshop.name}
                            </span>
                            {workshop.code && (
                              <span className="text-xs tabular-nums" style={{ color: 'var(--text-muted)' }}>
                                ({workshop.code})
                              </span>
                            )}
                          </div>
                          <div className="flex items-center gap-1 flex-shrink-0">
                            <button
                              type="button"
                              onClick={() => onShowInfo('workshop', workshop.id, workshop.name)}
                              className="ind-btn"
                              style={{ padding: '0 5px', color: 'var(--accent)' }}
                              title="Информация"
                            >
                              <Info size={12} />
                            </button>
                            <button
                              type="button"
                              onClick={() => onAssignEngineers('workshop', workshop.id, workshop.name)}
                              className="ind-btn"
                              style={{ padding: '0 5px', color: 'var(--success)' }}
                              title="Назначить инженеров"
                            >
                              <Users size={12} />
                            </button>
                            <button
                              type="button"
                              onClick={() => onCreateClick('equipment', workshop.id, workshop.name)}
                              className="ind-btn"
                              style={{ padding: '0 5px', color: 'var(--accent)' }}
                              title="Создать оборудование"
                            >
                              <Plus size={12} />
                            </button>
                          </div>
                        </div>

                        {expanded[`workshop_${workshop.id}`] && (
                          <div className="ml-5 mt-1.5 space-y-1.5" style={{ borderLeft: '1px dashed var(--border)', paddingLeft: '10px' }}>
                            {equipmentTypes.map((type) => (
                              <div key={type.id}>
                                <div
                                  style={{
                                    ...rowBase,
                                    padding: '6px 10px',
                                    background: 'transparent',
                                  }}
                                >
                                  <div className="flex items-center gap-2 flex-1 min-w-0">
                                    <button
                                      type="button"
                                      onClick={() =>
                                        onToggleExpand(`type_${workshop.id}_${type.id}`)
                                      }
                                      className="ind-btn"
                                      style={{ height: 20, width: 20, padding: 0, color: 'var(--text-muted)' }}
                                    >
                                      {expanded[`type_${workshop.id}_${type.id}`] ? (
                                        <ChevronDown size={12} />
                                      ) : (
                                        <ChevronRight size={12} />
                                      )}
                                    </button>
                                    <Box size={12} style={{ color: 'var(--warning)' }} />
                                    <span className="text-xs truncate" style={{ color: 'var(--text-secondary)' }}>
                                      {type.name}
                                    </span>
                                  </div>
                                  <button
                                    type="button"
                                    onClick={() =>
                                      onPrepareEquipmentCreateFromType(
                                        workshop.id,
                                        workshop.name,
                                        type.id
                                      )
                                    }
                                    className="ind-btn"
                                    style={{ padding: '0 5px', color: 'var(--accent)' }}
                                    title="Создать оборудование в этом типе"
                                  >
                                    <Plus size={12} />
                                  </button>
                                </div>

                                {expanded[`type_${workshop.id}_${type.id}`] && (
                                  <div className="ml-5 mt-1 space-y-1">
                                    {(equipment[workshop.id] || [])
                                      .filter((eq) => eq.type_id === type.id)
                                      .map((eq) => (
                                        <div
                                          key={eq.id}
                                          style={{
                                            ...rowBase,
                                            padding: '6px 10px',
                                            background: 'var(--bg-tertiary)',
                                            fontSize: '12px',
                                          }}
                                        >
                                          <div className="flex items-center gap-2 flex-1 min-w-0">
                                            <MapPin size={11} style={{ color: 'var(--text-muted)' }} />
                                            <button
                                              type="button"
                                              onClick={() => navigate(`/equipment/${eq.id}`)}
                                              className="text-xs text-left truncate hover:underline underline-offset-2"
                                              style={{ color: 'var(--text-primary)', background: 'transparent', border: 'none', padding: 0 }}
                                              title="Открыть карточку оборудования"
                                            >
                                              {eq.name}
                                            </button>
                                            {eq.serial_number && (
                                              <span className="text-xs tabular-nums" style={{ color: 'var(--text-muted)' }}>
                                                №{eq.serial_number}
                                              </span>
                                            )}
                                          </div>
                                          <div className="flex items-center gap-0.5 flex-shrink-0">
                                            <button
                                              type="button"
                                              onClick={() =>
                                                onShowInfo('equipment', eq.id, eq.name)
                                              }
                                              className="ind-btn"
                                              style={{ padding: '0 4px', color: 'var(--accent)' }}
                                              title="Информация"
                                            >
                                              <Info size={11} />
                                            </button>
                                            <button
                                              type="button"
                                              onClick={() =>
                                                onAssignEngineers('equipment', eq.id, eq.name)
                                              }
                                              className="ind-btn"
                                              style={{ padding: '0 4px', color: 'var(--success)' }}
                                              title="Назначить инженеров"
                                            >
                                              <Users size={11} />
                                            </button>
                                            <button
                                              type="button"
                                              onClick={() => onDeleteEquipment(eq.id)}
                                              className="ind-btn"
                                              style={{ padding: '0 4px', color: 'var(--danger)' }}
                                              title="Удалить"
                                            >
                                              <Trash2 size={11} />
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
      <div className="text-center py-10" style={{ color: 'var(--text-muted)' }}>
        <Building2 className="mx-auto mb-3 opacity-40" size={36} />
        <p className="text-sm">Предприятия не добавлены.</p>
        <p className="text-xs mt-1">Нажмите «Создать предприятие» для начала.</p>
      </div>
    )}
  </div>
);

export default EquipmentHierarchyTree;
