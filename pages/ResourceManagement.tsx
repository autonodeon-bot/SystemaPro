import React, { useState, useEffect } from 'react';
import { Calculator, Calendar, FileText, TrendingUp, AlertTriangle } from 'lucide-react';

interface Equipment {
  id: string;
  name: string;
  serial_number?: string;
  location?: string;
}

interface Resource {
  id: string;
  equipment_id: string;
  remaining_resource_years?: number;
  resource_end_date?: string;
  extension_years?: number;
  extension_date?: string;
  status: string;
  document_number?: string;
}

const ResourceManagement = () => {
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [resources, setResources] = useState<Resource[]>([]);
  const [selectedEquipment, setSelectedEquipment] = useState<Equipment | null>(null);
  const [showAddForm, setShowAddForm] = useState(false);
  const [loading, setLoading] = useState(true);

  const [formData, setFormData] = useState({
    equipment_id: '',
    remaining_resource_years: '',
    resource_end_date: '',
    extension_years: '',
    extension_date: '',
    calculation_method: '',
    document_number: '',
    status: 'ACTIVE',
  });

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      const [eqRes, resRes] = await Promise.all([
        fetch(`${API_BASE}/api/equipment`),
        fetch(`${API_BASE}/api/equipment-resources`)
      ]);
      
      const eqData = await eqRes.json();
      const resData = await resRes.json();
      
      setEquipment(eqData.items || []);
      setResources(resData.items || []);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const response = await fetch(`${API_BASE}/api/equipment-resources`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });

      if (response.ok) {
        setShowAddForm(false);
        setFormData({
          equipment_id: '',
          remaining_resource_years: '',
          resource_end_date: '',
          extension_years: '',
          extension_date: '',
          calculation_method: '',
          document_number: '',
          status: 'ACTIVE',
        });
        loadData();
        alert('Ресурс успешно добавлен');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось добавить ресурс'}`);
      }
    } catch (error) {
      console.error('Ошибка создания ресурса:', error);
      alert('Ошибка создания ресурса');
    }
  };

  const getEquipmentResource = (equipmentId: string) => {
    return resources.find(r => r.equipment_id === equipmentId && r.status === 'ACTIVE');
  };

  const calculateDaysUntilExpiry = (endDate?: string) => {
    if (!endDate) return null;
    const end = new Date(endDate);
    const now = new Date();
    const diff = end.getTime() - now.getTime();
    return Math.ceil(diff / (1000 * 60 * 60 * 24));
  };

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">Управление ресурсом оборудования</h1>
        <button
          onClick={() => setShowAddForm(true)}
          className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20"
        >
          <Calculator size={16} /> Добавить ресурс
        </button>
      </div>

      {/* Форма добавления */}
      {showAddForm && (
        <div className="bg-slate-800 p-6 rounded-xl border border-slate-600">
          <h2 className="text-xl font-bold text-white mb-4">Добавить ресурс оборудования</h2>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm text-slate-400 block mb-1">Оборудование *</label>
                <select
                  required
                  value={formData.equipment_id}
                  onChange={(e) => setFormData({ ...formData, equipment_id: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                >
                  <option value="">Выберите оборудование</option>
                  {equipment.map(eq => (
                    <option key={eq.id} value={eq.id}>{eq.name}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Остаточный ресурс (лет)</label>
                <input
                  type="number"
                  step="0.1"
                  value={formData.remaining_resource_years}
                  onChange={(e) => setFormData({ ...formData, remaining_resource_years: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Дата окончания ресурса</label>
                <input
                  type="date"
                  value={formData.resource_end_date}
                  onChange={(e) => setFormData({ ...formData, resource_end_date: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Продление (лет)</label>
                <input
                  type="number"
                  step="0.1"
                  value={formData.extension_years}
                  onChange={(e) => setFormData({ ...formData, extension_years: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Дата продления</label>
                <input
                  type="date"
                  value={formData.extension_date}
                  onChange={(e) => setFormData({ ...formData, extension_date: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Методика расчета</label>
                <input
                  type="text"
                  value={formData.calculation_method}
                  onChange={(e) => setFormData({ ...formData, calculation_method: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Например: РД 03-421-01"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Номер документа</label>
                <input
                  type="text"
                  value={formData.document_number}
                  onChange={(e) => setFormData({ ...formData, document_number: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80"
              >
                Сохранить
              </button>
              <button
                type="button"
                onClick={() => setShowAddForm(false)}
                className="bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
              >
                Отмена
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Список оборудования с ресурсом */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {equipment.map((eq) => {
          const resource = getEquipmentResource(eq.id);
          const daysUntilExpiry = resource ? calculateDaysUntilExpiry(resource.resource_end_date) : null;
          const isExpiringSoon = daysUntilExpiry !== null && daysUntilExpiry < 365 && daysUntilExpiry > 0;
          const isExpired = daysUntilExpiry !== null && daysUntilExpiry <= 0;
          
          return (
            <div
              key={eq.id}
              className={`bg-slate-800 p-4 rounded-xl border transition-colors cursor-pointer ${
                isExpired ? 'border-red-500/50' : isExpiringSoon ? 'border-yellow-500/50' : 'border-slate-700 hover:border-accent/50'
              }`}
              onClick={() => setSelectedEquipment(eq)}
            >
              <div className="flex justify-between items-start mb-2">
                <h3 className="text-lg font-bold text-white">{eq.name}</h3>
                {isExpired && <AlertTriangle className="text-red-400" size={20} />}
                {isExpiringSoon && <AlertTriangle className="text-yellow-400" size={20} />}
              </div>
              
              {eq.location && (
                <p className="text-sm text-slate-400 mb-3">{eq.location}</p>
              )}

              {resource ? (
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-slate-400">Остаточный ресурс:</span>
                    <span className="text-sm font-bold text-white">
                      {resource.remaining_resource_years?.toFixed(1)} лет
                    </span>
                  </div>
                  {resource.resource_end_date && (
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-slate-400">Окончание ресурса:</span>
                      <span className={`text-sm font-bold ${
                        isExpired ? 'text-red-400' : isExpiringSoon ? 'text-yellow-400' : 'text-white'
                      }`}>
                        {new Date(resource.resource_end_date).toLocaleDateString('ru-RU')}
                      </span>
                    </div>
                  )}
                  {daysUntilExpiry !== null && (
                    <div className="text-xs text-slate-500 mt-2">
                      {isExpired 
                        ? 'Ресурс истек' 
                        : isExpiringSoon 
                        ? `Осталось ${daysUntilExpiry} дней` 
                        : `Осталось ${daysUntilExpiry} дней`}
                    </div>
                  )}
                  {resource.extension_years && (
                    <div className="flex items-center gap-2 text-accent mt-2">
                      <TrendingUp size={14} />
                      <span className="text-sm">Продлен на {resource.extension_years} лет</span>
                    </div>
                  )}
                </div>
              ) : (
                <p className="text-sm text-slate-500">Ресурс не указан</p>
              )}
            </div>
          );
        })}
      </div>

      {/* Модальное окно с деталями */}
      {selectedEquipment && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setSelectedEquipment(null)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-2xl w-full mx-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">{selectedEquipment.name}</h2>
              <button onClick={() => setSelectedEquipment(null)} className="text-slate-400 hover:text-white">✕</button>
            </div>
            
            {getEquipmentResource(selectedEquipment.id) ? (
              <div className="space-y-4">
                {Object.entries(getEquipmentResource(selectedEquipment.id)!).map(([key, value]) => {
                  if (key === 'id' || !value) return null;
                  return (
                    <div key={key}>
                      <p className="text-sm text-slate-400 mb-1">{key.replace(/_/g, ' ')}</p>
                      <p className="text-white">{String(value)}</p>
                    </div>
                  );
                })}
              </div>
            ) : (
              <p className="text-slate-400">Ресурс не указан</p>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default ResourceManagement;



