import React, { useState, useEffect } from 'react';
import { Plus, Edit, Trash2, MapPin, Search } from 'lucide-react';

interface Equipment {
  id: string;
  name: string;
  type_id?: string;
  serial_number?: string;
  location?: string;
  attributes?: any;
  commissioning_date?: string;
}

interface EquipmentType {
  id: string;
  name: string;
  code?: string;
}

const EquipmentManagement = () => {
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [equipmentTypes, setEquipmentTypes] = useState<EquipmentType[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddForm, setShowAddForm] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedEquipment, setSelectedEquipment] = useState<Equipment | null>(null);
  const [showInspections, setShowInspections] = useState(false);
  const [inspections, setInspections] = useState<any[]>([]);
  const [equipmentInspectionsCount, setEquipmentInspectionsCount] = useState<Record<string, number>>({});

  const [formData, setFormData] = useState({
    name: '',
    type_id: '',
    serial_number: '',
    location: '',
    commissioning_date: '',
    attributes: {}
  });

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadEquipment();
    loadEquipmentTypes();
  }, []);

  useEffect(() => {
    // Загружаем количество диагностик для каждого оборудования
    equipment.forEach(eq => {
      fetch(`${API_BASE}/api/inspections?equipment_id=${eq.id}`)
        .then(res => res.json())
        .then(data => {
          setEquipmentInspectionsCount(prev => ({
            ...prev,
            [eq.id]: data.items?.length || 0
          }));
        })
        .catch(() => {});
    });
  }, [equipment]);

  const loadEquipment = async () => {
    try {
      const response = await fetch(`${API_BASE}/api/equipment`);
      const data = await response.json();
      setEquipment(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки оборудования:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadEquipmentTypes = async () => {
    try {
      const response = await fetch(`${API_BASE}/api/equipment-types`);
      const data = await response.json();
      setEquipmentTypes(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки типов оборудования:', error);
    }
  };

  const loadInspections = async (equipmentId: string) => {
    try {
      const response = await fetch(`${API_BASE}/api/inspections?equipment_id=${equipmentId}`);
      const data = await response.json();
      setInspections(data.items || []);
      setShowInspections(true);
    } catch (error) {
      console.error('Ошибка загрузки диагностик:', error);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const response = await fetch(`${API_BASE}/api/equipment`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });

      if (response.ok) {
        setShowAddForm(false);
        setFormData({
          name: '',
          type_id: '',
          serial_number: '',
          location: '',
          commissioning_date: '',
          attributes: {}
        });
        loadEquipment();
        alert('Оборудование успешно добавлено');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось добавить оборудование'}`);
      }
    } catch (error) {
      console.error('Ошибка создания оборудования:', error);
      alert('Ошибка создания оборудования');
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Вы уверены, что хотите удалить это оборудование?')) return;

    try {
      const response = await fetch(`${API_BASE}/api/equipment/${id}`, {
        method: 'DELETE'
      });

      if (response.ok) {
        loadEquipment();
        alert('Оборудование удалено');
      } else {
        alert('Ошибка удаления оборудования');
      }
    } catch (error) {
      console.error('Ошибка удаления:', error);
      alert('Ошибка удаления оборудования');
    }
  };

  const filteredEquipment = equipment.filter(eq =>
    eq.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    (eq.location && eq.location.toLowerCase().includes(searchTerm.toLowerCase())) ||
    (eq.serial_number && eq.serial_number.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">Управление оборудованием</h1>
        <button
          onClick={() => setShowAddForm(true)}
          className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20"
        >
          <Plus size={16} /> Добавить оборудование
        </button>
      </div>

      {/* Форма добавления */}
      {showAddForm && (
        <div className="bg-slate-800 p-6 rounded-xl border border-slate-600">
          <h2 className="text-xl font-bold text-white mb-4">Добавить оборудование</h2>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm text-slate-400 block mb-1">Название *</label>
                <input
                  type="text"
                  required
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Например: Сосуд В-101"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Тип оборудования</label>
                <select
                  value={formData.type_id}
                  onChange={(e) => setFormData({ ...formData, type_id: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                >
                  <option value="">Выберите тип</option>
                  {equipmentTypes.map(type => (
                    <option key={type.id} value={type.id}>{type.name}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Заводской номер</label>
                <input
                  type="text"
                  value={formData.serial_number}
                  onChange={(e) => setFormData({ ...formData, serial_number: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Место расположения *</label>
                <input
                  type="text"
                  required
                  value={formData.location}
                  onChange={(e) => setFormData({ ...formData, location: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="НГДУ, цех, месторождение"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Дата ввода в эксплуатацию</label>
                <input
                  type="date"
                  value={formData.commissioning_date}
                  onChange={(e) => setFormData({ ...formData, commissioning_date: e.target.value })}
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

      {/* Поиск */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
        <input
          type="text"
          placeholder="Поиск по названию, местоположению, номеру..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full bg-slate-800 border border-slate-700 rounded-lg pl-10 pr-4 py-2 text-white placeholder-slate-500"
        />
      </div>

      {/* Список оборудования */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredEquipment.map((eq) => (
          <div
            key={eq.id}
            className="bg-slate-800 p-4 rounded-xl border border-slate-700 hover:border-accent/50 transition-colors cursor-pointer"
            onClick={() => {
              setSelectedEquipment(eq);
              loadInspections(eq.id);
            }}
          >
            <div className="flex justify-between items-start mb-2">
              <h3 className="text-lg font-bold text-white">{eq.name}</h3>
              <div className="flex gap-2">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleDelete(eq.id);
                  }}
                  className="text-red-400 hover:text-red-300"
                >
                  <Trash2 size={16} />
                </button>
              </div>
            </div>
            {eq.location && (
              <div className="flex items-center gap-2 text-accent mb-2">
                <MapPin size={14} />
                <span className="text-sm">{eq.location}</span>
              </div>
            )}
            {eq.serial_number && (
              <p className="text-sm text-slate-400 mb-1">№ {eq.serial_number}</p>
            )}
            <button
              onClick={(e) => {
                e.stopPropagation();
                setSelectedEquipment(eq);
                loadInspections(eq.id);
              }}
              className="text-sm text-accent hover:underline mt-2"
            >
              Просмотр диагностик ({equipmentInspectionsCount[eq.id] || 0})
            </button>
          </div>
        ))}
      </div>

      {filteredEquipment.length === 0 && (
        <div className="text-center text-slate-400 py-20">
          {searchTerm ? 'Оборудование не найдено' : 'Оборудование не добавлено'}
        </div>
      )}

      {/* Модальное окно с диагностиками */}
      {showInspections && selectedEquipment && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowInspections(false)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-4xl w-full mx-4 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">Диагностики: {selectedEquipment.name}</h2>
              <button onClick={() => setShowInspections(false)} className="text-slate-400 hover:text-white">✕</button>
            </div>
            {inspections.length === 0 ? (
              <p className="text-slate-400">Диагностики не найдены</p>
            ) : (
              <div className="space-y-4">
                {inspections.map((insp) => (
                  <div key={insp.id} className="bg-slate-900 p-4 rounded-lg border border-slate-700">
                    <div className="flex justify-between items-start mb-2">
                      <div>
                        <p className="text-white font-bold">{insp.date_performed ? new Date(insp.date_performed).toLocaleDateString('ru-RU') : 'Дата не указана'}</p>
                        <p className="text-sm text-slate-400">Статус: {insp.status}</p>
                      </div>
                    </div>
                    {insp.conclusion && (
                      <p className="text-slate-300 mt-2">{insp.conclusion}</p>
                    )}
                    {insp.data && (
                      <details className="mt-2">
                        <summary className="text-sm text-accent cursor-pointer">Детали диагностики</summary>
                        <pre className="mt-2 text-xs text-slate-400 overflow-auto bg-slate-950 p-2 rounded">
                          {JSON.stringify(insp.data, null, 2)}
                        </pre>
                      </details>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default EquipmentManagement;

