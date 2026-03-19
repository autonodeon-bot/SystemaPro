import React, { useState, useEffect } from 'react';
import { API_BASE } from '../constants';

interface CreateAssignmentModalProps {
  onClose: () => void;
  onSuccess: () => void;
  equipmentList: any[];
  engineersList: any[];
}

const CreateAssignmentModal: React.FC<CreateAssignmentModalProps> = ({ onClose, onSuccess, equipmentList: _equipmentList, engineersList }) => {
  const [formData, setFormData] = useState({
    selectedEquipmentIds: [] as string[],
    assignment_type: 'DIAGNOSTICS',
    assigned_to: '',
    priority: 'NORMAL',
    due_date: '',
    description: ''
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [enterprises, setEnterprises] = useState<any[]>([]);
  const [branches, setBranches] = useState<Record<string, any[]>>({});
  const [workshops, setWorkshops] = useState<Record<string, any[]>>({});
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [equipmentByWorkshop, setEquipmentByWorkshop] = useState<Record<string, any[]>>({});
  const [loadingHierarchy, setLoadingHierarchy] = useState(true);

  useEffect(() => {
    loadHierarchy();
  }, []);

  const loadHierarchy = async () => {
    try {
      const token = localStorage.getItem('token');
      const [enterprisesRes, equipmentRes] = await Promise.all([
        fetch(`${API_BASE}/api/hierarchy/enterprises`, {
          headers: { 'Authorization': `Bearer ${token}` }
        }),
        fetch(`${API_BASE}/api/equipment?limit=10000`, {
          headers: { 'Authorization': `Bearer ${token}` }
        })
      ]);

      if (enterprisesRes.ok) {
        const entData = await enterprisesRes.json();
        setEnterprises(entData.items || []);
      }

      if (equipmentRes.ok) {
        const eqData = await equipmentRes.json();
        const equipmentByWorkshopMap: Record<string, any[]> = {};
        (eqData.items || []).forEach((eq: any) => {
          if (eq.workshop_id) {
            if (!equipmentByWorkshopMap[eq.workshop_id]) {
              equipmentByWorkshopMap[eq.workshop_id] = [];
            }
            equipmentByWorkshopMap[eq.workshop_id].push(eq);
          }
        });
        setEquipmentByWorkshop(equipmentByWorkshopMap);
      }
    } catch (err) {
      console.error('Ошибка загрузки иерархии:', err);
    } finally {
      setLoadingHierarchy(false);
    }
  };

  const loadBranches = async (enterpriseId: string) => {
    if (branches[enterpriseId]) return;
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/hierarchy/branches?enterprise_id=${enterpriseId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (response.ok) {
        const data = await response.json();
        setBranches(prev => ({ ...prev, [enterpriseId]: data.items || [] }));
      }
    } catch (err) {
      console.error('Ошибка загрузки филиалов:', err);
    }
  };

  const loadWorkshops = async (branchId: string) => {
    if (workshops[branchId]) return;
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/hierarchy/workshops?branch_id=${branchId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (response.ok) {
        const data = await response.json();
        setWorkshops(prev => ({ ...prev, [branchId]: data.items || [] }));
      }
    } catch (err) {
      console.error('Ошибка загрузки цехов:', err);
    }
  };

  const getEquipmentForWorkshop = (workshopId: string) => {
    return equipmentByWorkshop[workshopId] || [];
  };

  const toggleExpand = (key: string) => {
    setExpanded(prev => ({ ...prev, [key]: !prev[key] }));
    if (key.startsWith('enterprise-')) {
      const enterpriseId = key.replace('enterprise-', '');
      loadBranches(enterpriseId);
    } else if (key.startsWith('branch-')) {
      const branchId = key.replace('branch-', '');
      loadWorkshops(branchId);
    }
  };

  const toggleEquipment = (equipmentId: string) => {
    setFormData(prev => ({
      ...prev,
      selectedEquipmentIds: prev.selectedEquipmentIds.includes(equipmentId)
        ? prev.selectedEquipmentIds.filter(id => id !== equipmentId)
        : [...prev.selectedEquipmentIds, equipmentId]
    }));
  };

  const isEnterpriseSelected = (enterpriseId: string): boolean => {
    const entBranches = branches[enterpriseId];
    if (!entBranches || entBranches.length === 0) return false;
    
    const allEquipmentIds: string[] = [];
    
    entBranches.forEach((branch: any) => {
      const branchWorkshops = workshops[branch.id];
      if (!branchWorkshops || branchWorkshops.length === 0) return;
      
      branchWorkshops.forEach((workshop: any) => {
        const workshopEquipment = getEquipmentForWorkshop(workshop.id);
        workshopEquipment.forEach((eq: any) => {
          allEquipmentIds.push(eq.id);
        });
      });
    });

    if (allEquipmentIds.length === 0) return false;
    return allEquipmentIds.every(id => formData.selectedEquipmentIds.includes(id));
  };

  const isBranchSelected = (branchId: string): boolean => {
    if (!workshops[branchId] || workshops[branchId].length === 0) return false;
    
    const branchWorkshops = workshops[branchId];
    const allEquipmentIds: string[] = [];
    
    branchWorkshops.forEach((workshop: any) => {
      const workshopEquipment = getEquipmentForWorkshop(workshop.id);
      workshopEquipment.forEach((eq: any) => {
        allEquipmentIds.push(eq.id);
      });
    });

    if (allEquipmentIds.length === 0) return false;
    return allEquipmentIds.every(id => formData.selectedEquipmentIds.includes(id));
  };

  const isWorkshopSelected = (workshopId: string): boolean => {
    const workshopEquipment = getEquipmentForWorkshop(workshopId);
    const allEquipmentIds = workshopEquipment.map((eq: any) => eq.id);

    if (allEquipmentIds.length === 0) return false;
    return allEquipmentIds.every(id => formData.selectedEquipmentIds.includes(id));
  };

  const selectAllInEnterprise = async (enterpriseId: string, isChecked: boolean) => {
    const enterprise = enterprises.find(e => e.id === enterpriseId);
    if (!enterprise) return;

    if (!branches[enterpriseId]) {
      await loadBranches(enterpriseId);
    }

    const allEquipmentIds: string[] = [];
    const entBranches = branches[enterpriseId] || [];
    
    const loadPromises = entBranches.map(async (branch: any) => {
      if (!workshops[branch.id]) {
        await loadWorkshops(branch.id);
      }
    });
    await Promise.all(loadPromises);

    entBranches.forEach((branch: any) => {
      const branchWorkshops = workshops[branch.id] || [];
      branchWorkshops.forEach((workshop: any) => {
        const workshopEquipment = getEquipmentForWorkshop(workshop.id);
        workshopEquipment.forEach((eq: any) => {
          allEquipmentIds.push(eq.id);
        });
      });
    });

    setFormData(prev => {
      if (isChecked) {
        const newIds = [...new Set([...prev.selectedEquipmentIds, ...allEquipmentIds])];
        return { ...prev, selectedEquipmentIds: newIds };
      } else {
        const newIds = prev.selectedEquipmentIds.filter(id => !allEquipmentIds.includes(id));
        return { ...prev, selectedEquipmentIds: newIds };
      }
    });
  };

  const selectAllInBranch = async (branchId: string, isChecked: boolean) => {
    if (!workshops[branchId]) {
      await loadWorkshops(branchId);
    }

    const branchWorkshops = workshops[branchId] || [];
    const allEquipmentIds: string[] = [];
    
    branchWorkshops.forEach((workshop: any) => {
      const workshopEquipment = getEquipmentForWorkshop(workshop.id);
      workshopEquipment.forEach((eq: any) => {
        allEquipmentIds.push(eq.id);
      });
    });

    setFormData(prev => {
      if (isChecked) {
        const newIds = [...new Set([...prev.selectedEquipmentIds, ...allEquipmentIds])];
        return { ...prev, selectedEquipmentIds: newIds };
      } else {
        const newIds = prev.selectedEquipmentIds.filter(id => !allEquipmentIds.includes(id));
        return { ...prev, selectedEquipmentIds: newIds };
      }
    });
  };

  const selectAllInWorkshop = (workshopId: string, isChecked: boolean) => {
    const workshopEquipment = getEquipmentForWorkshop(workshopId);
    const allEquipmentIds = workshopEquipment.map((eq: any) => eq.id);

    setFormData(prev => {
      if (isChecked) {
        return {
          ...prev,
          selectedEquipmentIds: [...new Set([...prev.selectedEquipmentIds, ...allEquipmentIds])]
        };
      } else {
        return {
          ...prev,
          selectedEquipmentIds: prev.selectedEquipmentIds.filter(id => !allEquipmentIds.includes(id))
        };
      }
    });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (formData.selectedEquipmentIds.length === 0) {
      setError('Необходимо выбрать хотя бы одно оборудование');
      return;
    }

    setSaving(true);
    setError(null);

    try {
      const token = localStorage.getItem('token');
      
      const promises = formData.selectedEquipmentIds.map(equipmentId => {
        const payload = {
          equipment_id: equipmentId,
          assignment_type: formData.assignment_type,
          assigned_to: formData.assigned_to,
          priority: formData.priority,
          due_date: formData.due_date ? `${formData.due_date}T23:59:59` : null,
          description: formData.description || null
        };

        return fetch(`${API_BASE}/api/assignments`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify(payload)
        });
      });

      const results = await Promise.all(promises);
      const failed = results.filter(r => !r.ok);
      
      if (failed.length > 0) {
        const errorData = await failed[0].json();
        setError(`Ошибка при создании заданий: ${errorData.detail || 'Неизвестная ошибка'}`);
      } else {
        onSuccess();
      }
    } catch (err) {
      setError('Ошибка при создании заданий');
      console.error('Ошибка:', err);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-slate-800 rounded-lg max-w-2xl w-full max-h-[90vh] overflow-auto">
        <div className="p-6 border-b border-slate-700">
          <h2 className="text-xl font-semibold text-white">Создать задание</h2>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {error && (
            <div className="bg-red-500/20 border border-red-500 rounded-lg p-3 text-red-400 text-sm">
              {error}
            </div>
          )}

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">
              Оборудование * ({formData.selectedEquipmentIds.length} выбрано)
            </label>
            {loadingHierarchy ? (
              <div className="text-slate-400 text-sm">Загрузка иерархии...</div>
            ) : (
              <div className="bg-slate-900 border border-slate-700 rounded-lg p-4 max-h-96 overflow-y-auto">
                {enterprises.length === 0 ? (
                  <div className="text-slate-400 text-sm">Нет доступных предприятий</div>
                ) : (
                  enterprises.map((enterprise) => (
                    <div key={enterprise.id} className="mb-2">
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => toggleExpand(`enterprise-${enterprise.id}`)}
                          className="text-slate-400 hover:text-white"
                        >
                          {expanded[`enterprise-${enterprise.id}`] ? '▼' : '▶'}
                        </button>
                        <input
                          type="checkbox"
                          checked={isEnterpriseSelected(enterprise.id)}
                          onChange={async (e) => {
                            e.stopPropagation();
                            const newChecked = e.target.checked;
                            await selectAllInEnterprise(enterprise.id, newChecked);
                          }}
                          onClick={(e) => e.stopPropagation()}
                          className="rounded cursor-pointer"
                        />
                        <span className="text-white font-semibold">{enterprise.name}</span>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            selectAllInEnterprise(enterprise.id, !isEnterpriseSelected(enterprise.id));
                          }}
                          className="ml-auto text-xs text-accent hover:underline"
                        >
                          {isEnterpriseSelected(enterprise.id) ? 'Снять все' : 'Выбрать все'}
                        </button>
                      </div>
                      {expanded[`enterprise-${enterprise.id}`] && (branches[enterprise.id] || []).map((branch: any) => (
                        <div key={branch.id} className="ml-6 mt-2">
                          <div className="flex items-center gap-2">
                            <button
                              type="button"
                              onClick={() => toggleExpand(`branch-${branch.id}`)}
                              className="text-slate-400 hover:text-white"
                            >
                              {expanded[`branch-${branch.id}`] ? '▼' : '▶'}
                            </button>
                            <input
                              type="checkbox"
                              checked={isBranchSelected(branch.id)}
                              onChange={(e) => {
                                e.stopPropagation();
                                selectAllInBranch(branch.id, e.target.checked);
                              }}
                              onClick={(e) => e.stopPropagation()}
                              className="rounded"
                            />
                            <span className="text-slate-300">{branch.name}</span>
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                selectAllInBranch(branch.id, !isBranchSelected(branch.id));
                              }}
                              className="ml-auto text-xs text-accent hover:underline"
                            >
                              {isBranchSelected(branch.id) ? 'Снять все' : 'Выбрать все'}
                            </button>
                          </div>
                          {expanded[`branch-${branch.id}`] && (workshops[branch.id] || []).map((workshop: any) => (
                            <div key={workshop.id} className="ml-6 mt-2">
                              <div className="flex items-center gap-2">
                                <button
                                  type="button"
                                  onClick={() => toggleExpand(`workshop-${workshop.id}`)}
                                  className="text-slate-400 hover:text-white"
                                >
                                  {expanded[`workshop-${workshop.id}`] ? '▼' : '▶'}
                                </button>
                                <input
                                  type="checkbox"
                                  checked={isWorkshopSelected(workshop.id)}
                                  onChange={(e) => {
                                    e.stopPropagation();
                                    selectAllInWorkshop(workshop.id, e.target.checked);
                                  }}
                                  onClick={(e) => e.stopPropagation()}
                                  className="rounded"
                                />
                                <span className="text-slate-400">{workshop.name}</span>
                                <button
                                  type="button"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    selectAllInWorkshop(workshop.id, !isWorkshopSelected(workshop.id));
                                  }}
                                  className="ml-auto text-xs text-accent hover:underline"
                                >
                                  {isWorkshopSelected(workshop.id) ? 'Снять все' : 'Выбрать все'}
                                </button>
                              </div>
                              {expanded[`workshop-${workshop.id}`] && getEquipmentForWorkshop(workshop.id).map((eq: any) => (
                                <div key={eq.id} className="ml-6 mt-1">
                                  <label className="flex items-center gap-2 cursor-pointer">
                                    <input
                                      type="checkbox"
                                      checked={formData.selectedEquipmentIds.includes(eq.id)}
                                      onChange={() => toggleEquipment(eq.id)}
                                      className="rounded"
                                    />
                                    <span className="text-slate-400 text-sm">
                                      {eq.equipment_code} - {eq.name}
                                    </span>
                                  </label>
                                </div>
                              ))}
                            </div>
                          ))}
                        </div>
                      ))}
                    </div>
                  ))
                )}
              </div>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Тип задания *
            </label>
            <select
              required
              value={formData.assignment_type}
              onChange={(e) => setFormData({ ...formData, assignment_type: e.target.value })}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="DIAGNOSTICS">Диагностика</option>
              <option value="EXPERTISE">Экспертиза ПБ</option>
              <option value="INSPECTION">Обследование</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Назначить инженеру *
            </label>
            <select
              required
              value={formData.assigned_to}
              onChange={(e) => setFormData({ ...formData, assigned_to: e.target.value })}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="">Выберите инженера</option>
              {engineersList.map((eng) => (
                <option key={eng.id} value={eng.id}>
                  {eng.full_name || eng.username}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Приоритет *
            </label>
            <select
              required
              value={formData.priority}
              onChange={(e) => setFormData({ ...formData, priority: e.target.value })}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            >
              <option value="LOW">Низкий</option>
              <option value="NORMAL">Обычный</option>
              <option value="HIGH">Высокий</option>
              <option value="URGENT">Срочный</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Срок выполнения
            </label>
            <input
              type="date"
              value={formData.due_date}
              onChange={(e) => setFormData({ ...formData, due_date: e.target.value })}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Описание
            </label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              rows={4}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              placeholder="Дополнительная информация о задании..."
            />
          </div>

          <div className="flex justify-end gap-3 pt-4 border-t border-slate-700">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-slate-400 hover:text-white transition"
              disabled={saving}
            >
              Отмена
            </button>
            <button
              type="submit"
              disabled={saving}
              className="px-4 py-2 bg-accent text-white rounded-lg hover:bg-accent/90 transition disabled:opacity-50"
            >
              {saving ? `Создание ${formData.selectedEquipmentIds.length} заданий...` : `Создать ${formData.selectedEquipmentIds.length} заданий`}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default CreateAssignmentModal;
