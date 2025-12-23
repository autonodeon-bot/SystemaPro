import React, { useState, useEffect } from 'react';
import { AlertTriangle, Plus, Search, Filter, Download, Calendar, FileText, Eye, Edit, Trash2, Upload, CheckCircle, XCircle, Clock, FileDown, History, BarChart3 } from 'lucide-react';
import { API_BASE } from '../constants';

interface VerificationEquipment {
  id: string;
  name: string;
  equipment_type: string;
  category?: string;
  serial_number: string;
  manufacturer?: string;
  model?: string;
  inventory_number?: string;
  verification_date: string;
  next_verification_date: string;
  verification_certificate_number?: string;
  verification_organization?: string;
  scan_file_path?: string;
  scan_file_name?: string;
  is_active: boolean;
  notes?: string;
  days_until_expiry?: number;
  is_expired: boolean;
}

const VerificationsManagement: React.FC = () => {
  const [equipment, setEquipment] = useState<VerificationEquipment[]>([]);
  const [filteredEquipment, setFilteredEquipment] = useState<VerificationEquipment[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterType, setFilterType] = useState<string>('all');
  const [filterExpiry, setFilterExpiry] = useState<string>('all');
  const [showModal, setShowModal] = useState(false);
  const [editingItem, setEditingItem] = useState<VerificationEquipment | null>(null);
  const [showScanModal, setShowScanModal] = useState<string | null>(null);
  const [showHistoryModal, setShowHistoryModal] = useState<string | null>(null);
  const [historyData, setHistoryData] = useState<any[]>([]);
  const [showStatistics, setShowStatistics] = useState(false);
  const [usageStatistics, setUsageStatistics] = useState<any>(null);

  useEffect(() => {
    loadEquipment();
  }, []);

  useEffect(() => {
    filterEquipment();
  }, [equipment, searchTerm, filterType, filterExpiry]);

  const loadEquipment = async () => {
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/verification-equipment?is_active=true`, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
      if (response.ok) {
        const data = await response.json();
        setEquipment(data);
      }
    } catch (error) {
      console.error('Ошибка загрузки оборудования:', error);
    } finally {
      setLoading(false);
    }
  };

  const filterEquipment = () => {
    let filtered = [...equipment];

    // Поиск
    if (searchTerm) {
      const term = searchTerm.toLowerCase();
      filtered = filtered.filter(item =>
        item.name.toLowerCase().includes(term) ||
        item.serial_number.toLowerCase().includes(term) ||
        item.equipment_type.toLowerCase().includes(term) ||
        (item.manufacturer && item.manufacturer.toLowerCase().includes(term)) ||
        (item.model && item.model.toLowerCase().includes(term))
      );
    }

    // Фильтр по типу
    if (filterType !== 'all') {
      filtered = filtered.filter(item => item.equipment_type === filterType);
    }

    // Фильтр по сроку поверки
    if (filterExpiry === 'expired') {
      filtered = filtered.filter(item => item.is_expired);
    } else if (filterExpiry === 'warning-30') {
      filtered = filtered.filter(item => item.days_until_expiry !== null && item.days_until_expiry <= 30 && item.days_until_expiry > 0);
    } else if (filterExpiry === 'warning-14') {
      filtered = filtered.filter(item => item.days_until_expiry !== null && item.days_until_expiry <= 14 && item.days_until_expiry > 0);
    } else if (filterExpiry === 'warning-7') {
      filtered = filtered.filter(item => item.days_until_expiry !== null && item.days_until_expiry <= 7 && item.days_until_expiry > 0);
    }

    setFilteredEquipment(filtered);
  };

  const getStatusBadge = (item: VerificationEquipment) => {
    if (item.is_expired) {
      return <span className="px-2 py-1 bg-red-500/20 text-red-400 rounded text-xs flex items-center gap-1"><XCircle size={12} />Просрочено</span>;
    }
    if (item.days_until_expiry !== null && item.days_until_expiry <= 7) {
      return <span className="px-2 py-1 bg-red-500/20 text-red-400 rounded text-xs flex items-center gap-1"><AlertTriangle size={12} />Скоро истекает</span>;
    }
    if (item.days_until_expiry !== null && item.days_until_expiry <= 30) {
      return <span className="px-2 py-1 bg-yellow-500/20 text-yellow-400 rounded text-xs flex items-center gap-1"><Clock size={12} />Предупреждение</span>;
    }
    return <span className="px-2 py-1 bg-green-500/20 text-green-400 rounded text-xs flex items-center gap-1"><CheckCircle size={12} />Активно</span>;
  };

  const getEquipmentTypes = () => {
    const types = new Set(equipment.map(item => item.equipment_type));
    return Array.from(types).sort();
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Вы уверены, что хотите удалить это оборудование?')) return;
    
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/verification-equipment/${id}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
      if (response.ok) {
        await loadEquipment();
      } else {
        alert('Ошибка удаления');
      }
    } catch (error) {
      console.error('Ошибка удаления:', error);
      alert('Ошибка удаления');
    }
  };

  const handleViewScan = (id: string) => {
    setShowScanModal(id);
  };

  const loadUsageStatistics = async () => {
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/verification-equipment/statistics/usage?days=90`, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
      if (response.ok) {
        const data = await response.json();
        setUsageStatistics(data);
      }
    } catch (error) {
      console.error('Ошибка загрузки статистики:', error);
    }
  };

  const handleExportExcel = async () => {
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/verification-equipment/export/csv`, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
      if (response.ok) {
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `verification-equipment-${new Date().toISOString().split('T')[0]}.csv`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
      } else {
        // Если endpoint не существует, создаем CSV вручную
        const csvContent = [
          ['Название', 'Тип', 'Серийный номер', 'Дата поверки', 'Следующая поверка', 'Статус'].join(','),
          ...filteredEquipment.map(item => [
            `"${item.name}"`,
            `"${item.equipment_type}"`,
            `"${item.serial_number}"`,
            item.verification_date ? new Date(item.verification_date).toLocaleDateString('ru-RU') : '',
            item.next_verification_date ? new Date(item.next_verification_date).toLocaleDateString('ru-RU') : '',
            item.is_expired ? 'Просрочено' : (item.days_until_expiry !== null && item.days_until_expiry <= 30 ? 'Предупреждение' : 'Активно')
          ].join(','))
        ].join('\n');
        
        const blob = new Blob(['\ufeff' + csvContent], { type: 'text/csv;charset=utf-8;' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `verification-equipment-${new Date().toISOString().split('T')[0]}.csv`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
      }
    } catch (error) {
      console.error('Ошибка экспорта:', error);
      alert('Ошибка экспорта данных');
    }
  };

  const handleViewHistory = async (id: string) => {
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/verification-equipment/${id}/history`, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
      if (response.ok) {
        const data = await response.json();
        setHistoryData(data);
        setShowHistoryModal(id);
      } else {
        setHistoryData([]);
        setShowHistoryModal(id);
      }
    } catch (error) {
      console.error('Ошибка загрузки истории:', error);
      setHistoryData([]);
      setShowHistoryModal(id);
    }
  };

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  const expiredCount = equipment.filter(item => item.is_expired).length;
  const warning30Count = equipment.filter(item => item.days_until_expiry !== null && item.days_until_expiry <= 30 && item.days_until_expiry > 0 && !item.is_expired).length;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <div>
            <h1 className="text-2xl font-bold text-white">Поверки оборудования</h1>
            <p className="text-slate-400 mt-1">Управление оборудованием для поверок и контроль сроков</p>
          </div>
          <div className="flex items-center gap-2">
            <a
              href="#/verifications-calendar"
              className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
            >
              <Calendar size={20} />
              Календарь
            </a>
          </div>
        </div>
        <div className="flex items-center justify-between">
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              setShowStatistics(!showStatistics);
              if (!showStatistics && !usageStatistics) {
                loadUsageStatistics();
              }
            }}
            className="flex items-center gap-2 px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition"
            title="Статистика использования"
          >
            <BarChart3 size={20} />
            Статистика
          </button>
          <button
            onClick={handleExportExcel}
            className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition"
            title="Экспорт в CSV"
          >
            <FileDown size={20} />
            Экспорт
          </button>
          <button
            onClick={() => {
              setEditingItem(null);
              setShowModal(true);
            }}
            className="flex items-center gap-2 px-4 py-2 bg-accent text-white rounded-lg hover:bg-accent/90 transition"
          >
            <Plus size={20} />
            Добавить оборудование
          </button>
        </div>
      </div>

      {/* Статистика */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="bg-secondary/50 rounded-lg p-4 border border-slate-700">
          <div className="text-slate-400 text-sm">Всего оборудования</div>
          <div className="text-2xl font-bold text-white mt-1">{equipment.length}</div>
        </div>
        <div className="bg-red-500/10 rounded-lg p-4 border border-red-500/20">
          <div className="text-red-400 text-sm flex items-center gap-1">
            <AlertTriangle size={16} />
            Просрочено
          </div>
          <div className="text-2xl font-bold text-red-400 mt-1">{expiredCount}</div>
        </div>
        <div className="bg-yellow-500/10 rounded-lg p-4 border border-yellow-500/20">
          <div className="text-yellow-400 text-sm flex items-center gap-1">
            <Clock size={16} />
            Предупреждение (≤30 дней)
          </div>
          <div className="text-2xl font-bold text-yellow-400 mt-1">{warning30Count}</div>
        </div>
      </div>

      {/* Фильтры */}
      <div className="bg-secondary/50 rounded-lg p-4 border border-slate-700">
        <div className="flex flex-col md:flex-row gap-4">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
            <input
              type="text"
              placeholder="Поиск по названию, серийному номеру, типу..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-primary border border-slate-700 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:border-accent"
            />
          </div>
          <select
            value={filterType}
            onChange={(e) => setFilterType(e.target.value)}
            className="px-4 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
          >
            <option value="all">Все типы</option>
            {getEquipmentTypes().map(type => (
              <option key={type} value={type}>{type}</option>
            ))}
          </select>
          <select
            value={filterExpiry}
            onChange={(e) => setFilterExpiry(e.target.value)}
            className="px-4 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
          >
            <option value="all">Все сроки</option>
            <option value="expired">Просрочено</option>
            <option value="warning-30">Предупреждение (≤30 дней)</option>
            <option value="warning-14">Предупреждение (≤14 дней)</option>
            <option value="warning-7">Предупреждение (≤7 дней)</option>
          </select>
        </div>
      </div>

      {/* Статистика использования */}
      {showStatistics && usageStatistics && (
        <div className="bg-secondary/50 rounded-lg p-4 border border-slate-700">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-white">Статистика использования оборудования</h3>
            <button
              onClick={() => setShowStatistics(false)}
              className="text-slate-400 hover:text-white"
            >
              <XCircle size={20} />
            </button>
          </div>
          <div className="mb-4">
            <div className="text-slate-400 text-sm">
              За последние {usageStatistics.period_days} дней: {usageStatistics.total_uses} использований, {usageStatistics.equipment_count} единиц оборудования
            </div>
          </div>
          <div className="space-y-2 max-h-64 overflow-y-auto">
            {usageStatistics.equipment.slice(0, 10).map((eq: any, idx: number) => (
              <div key={eq.id} className="bg-slate-800 rounded-lg p-3 border border-slate-700">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="font-semibold text-white">{eq.name}</div>
                    <div className="text-sm text-slate-400">
                      {eq.equipment_type} • {eq.serial_number}
                    </div>
                  </div>
                  <div className="text-lg font-bold text-blue-400">
                    {eq.usage_count} раз
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Таблица */}
      <div className="bg-secondary/50 rounded-lg border border-slate-700 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-slate-800/50">
              <tr>
                <th className="px-4 py-3 text-left text-sm font-semibold text-slate-300">Название</th>
                <th className="px-4 py-3 text-left text-sm font-semibold text-slate-300">Тип</th>
                <th className="px-4 py-3 text-left text-sm font-semibold text-slate-300">Серийный номер</th>
                <th className="px-4 py-3 text-left text-sm font-semibold text-slate-300">Следующая поверка</th>
                <th className="px-4 py-3 text-left text-sm font-semibold text-slate-300">Статус</th>
                <th className="px-4 py-3 text-left text-sm font-semibold text-slate-300">Скан</th>
                <th className="px-4 py-3 text-left text-sm font-semibold text-slate-300">Действия</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-700">
              {filteredEquipment.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-8 text-center text-slate-400">
                    Оборудование не найдено
                  </td>
                </tr>
              ) : (
                filteredEquipment.map((item) => (
                  <tr key={item.id} className="hover:bg-slate-800/30 transition">
                    <td className="px-4 py-3 text-white">{item.name}</td>
                    <td className="px-4 py-3 text-slate-300">{item.equipment_type}</td>
                    <td className="px-4 py-3 text-slate-300">{item.serial_number}</td>
                    <td className="px-4 py-3 text-slate-300">
                      {item.next_verification_date ? new Date(item.next_verification_date).toLocaleDateString('ru-RU') : '-'}
                      {item.days_until_expiry !== null && (
                        <div className="text-xs text-slate-500 mt-1">
                          {item.days_until_expiry > 0 ? `через ${item.days_until_expiry} дн.` : 'просрочено'}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3">{getStatusBadge(item)}</td>
                    <td className="px-4 py-3">
                      {item.scan_file_path ? (
                        <button
                          onClick={() => handleViewScan(item.id)}
                          className="text-accent hover:text-accent/80 flex items-center gap-1"
                        >
                          <Eye size={16} />
                          Просмотр
                        </button>
                      ) : (
                        <span className="text-slate-500 text-sm">Нет скана</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => handleViewHistory(item.id)}
                          className="p-1 text-slate-400 hover:text-blue-400 transition"
                          title="История поверок"
                        >
                          <History size={16} />
                        </button>
                        <button
                          onClick={() => {
                            setEditingItem(item);
                            setShowModal(true);
                          }}
                          className="p-1 text-slate-400 hover:text-accent transition"
                          title="Редактировать"
                        >
                          <Edit size={16} />
                        </button>
                        <button
                          onClick={() => handleDelete(item.id)}
                          className="p-1 text-slate-400 hover:text-red-400 transition"
                          title="Удалить"
                        >
                          <Trash2 size={16} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Модальное окно для просмотра скана */}
      {showScanModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-secondary rounded-lg max-w-4xl w-full max-h-[90vh] overflow-auto">
            <div className="p-4 border-b border-slate-700 flex items-center justify-between">
              <h3 className="text-lg font-semibold text-white">Скан свидетельства о поверке</h3>
              <button
                onClick={() => setShowScanModal(null)}
                className="text-slate-400 hover:text-white"
              >
                <XCircle size={24} />
              </button>
            </div>
            <div className="p-4">
              <iframe
                src={`${API_BASE}/api/verification-equipment/${showScanModal}/scan?inline=true`}
                className="w-full h-[70vh] border border-slate-700 rounded"
                title="Скан поверки"
              />
            </div>
          </div>
        </div>
      )}

      {/* Модальное окно для истории поверок */}
      {showHistoryModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-secondary rounded-lg max-w-4xl w-full max-h-[90vh] overflow-auto">
            <div className="p-4 border-b border-slate-700 flex items-center justify-between">
              <h3 className="text-lg font-semibold text-white">История поверок</h3>
              <button
                onClick={() => {
                  setShowHistoryModal(null);
                  setHistoryData([]);
                }}
                className="text-slate-400 hover:text-white"
              >
                <XCircle size={24} />
              </button>
            </div>
            <div className="p-4">
              {historyData.length === 0 ? (
                <p className="text-slate-400 text-center py-8">История поверок отсутствует</p>
              ) : (
                <div className="space-y-4">
                  {historyData.map((history: any, idx: number) => (
                    <div key={idx} className="bg-slate-800 rounded-lg p-4 border border-slate-700">
                      <div className="grid grid-cols-2 gap-4 text-sm">
                        <div>
                          <span className="text-slate-400">Предыдущая поверка:</span>
                          <p className="text-white">{new Date(history.previous_verification_date).toLocaleDateString('ru-RU')}</p>
                        </div>
                        <div>
                          <span className="text-slate-400">Новая поверка:</span>
                          <p className="text-white">{new Date(history.new_verification_date).toLocaleDateString('ru-RU')}</p>
                        </div>
                        <div>
                          <span className="text-slate-400">Следующая поверка:</span>
                          <p className="text-white">{new Date(history.new_next_verification_date).toLocaleDateString('ru-RU')}</p>
                        </div>
                        {history.certificate_number && (
                          <div>
                            <span className="text-slate-400">Номер свидетельства:</span>
                            <p className="text-white">{history.certificate_number}</p>
                          </div>
                        )}
                        {history.organization && (
                          <div>
                            <span className="text-slate-400">Организация:</span>
                            <p className="text-white">{history.organization}</p>
                          </div>
                        )}
                        {history.recorded_at && (
                          <div>
                            <span className="text-slate-400">Записано:</span>
                            <p className="text-white">{new Date(history.recorded_at).toLocaleDateString('ru-RU')}</p>
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Модальное окно для добавления/редактирования */}
      {showModal && (
        <VerificationEquipmentModal
          item={editingItem}
          onClose={() => {
            setShowModal(false);
            setEditingItem(null);
          }}
          onSave={loadEquipment}
        />
      )}
    </div>
  );
};

// Компонент модального окна для добавления/редактирования
const VerificationEquipmentModal: React.FC<{
  item: VerificationEquipment | null;
  onClose: () => void;
  onSave: () => void;
}> = ({ item, onClose, onSave }) => {
  const [formData, setFormData] = useState({
    name: item?.name || '',
    equipment_type: item?.equipment_type || '',
    category: item?.category || '',
    serial_number: item?.serial_number || '',
    manufacturer: item?.manufacturer || '',
    model: item?.model || '',
    inventory_number: item?.inventory_number || '',
    verification_date: item?.verification_date ? item.verification_date.split('T')[0] : '',
    next_verification_date: item?.next_verification_date ? item.next_verification_date.split('T')[0] : '',
    verification_certificate_number: item?.verification_certificate_number || '',
    verification_organization: item?.verification_organization || '',
    notes: item?.notes || '',
  });
  const [scanFile, setScanFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);

    try {
      const token = localStorage.getItem('token');
      const formDataToSend = new FormData();
      
      Object.entries(formData).forEach(([key, value]) => {
        if (value) formDataToSend.append(key, value);
      });
      
      if (scanFile) {
        formDataToSend.append('scan_file', scanFile);
      }

      const url = item
        ? `${API_BASE}/api/verification-equipment/${item.id}`
        : `${API_BASE}/api/verification-equipment`;
      
      const method = item ? 'PUT' : 'POST';

      const response = await fetch(url, {
        method,
        headers: {
          'Authorization': `Bearer ${token}`,
        },
        body: formDataToSend,
      });

      if (response.ok) {
        onSave();
        onClose();
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось сохранить'}`);
      }
    } catch (error) {
      console.error('Ошибка сохранения:', error);
      alert('Ошибка сохранения');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-secondary rounded-lg max-w-2xl w-full max-h-[90vh] overflow-auto">
        <div className="p-6 border-b border-slate-700">
          <h2 className="text-xl font-semibold text-white">
            {item ? 'Редактировать оборудование' : 'Добавить оборудование'}
          </h2>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Название *</label>
              <input
                type="text"
                required
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Тип оборудования *</label>
              <select
                required
                value={formData.equipment_type}
                onChange={(e) => setFormData({ ...formData, equipment_type: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              >
                <option value="">Выберите тип</option>
                <option value="ВИК">ВИК (Визуальный и измерительный контроль)</option>
                <option value="УЗК">УЗК (Ультразвуковой контроль)</option>
                <option value="ПВК">ПВК (Пневматический контроль)</option>
                <option value="РК">РК (Радиографический контроль)</option>
                <option value="МК">МК (Магнитный контроль)</option>
                <option value="ВК">ВК (Вихретоковый контроль)</option>
                <option value="ТК">ТК (Тепловой контроль)</option>
                <option value="Другое">Другое</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Серийный номер *</label>
              <input
                type="text"
                required
                value={formData.serial_number}
                onChange={(e) => setFormData({ ...formData, serial_number: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Производитель</label>
              <input
                type="text"
                value={formData.manufacturer}
                onChange={(e) => setFormData({ ...formData, manufacturer: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Модель</label>
              <input
                type="text"
                value={formData.model}
                onChange={(e) => setFormData({ ...formData, model: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Инвентарный номер</label>
              <input
                type="text"
                value={formData.inventory_number}
                onChange={(e) => setFormData({ ...formData, inventory_number: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Дата поверки *</label>
              <input
                type="date"
                required
                value={formData.verification_date}
                onChange={(e) => setFormData({ ...formData, verification_date: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Следующая поверка *</label>
              <input
                type="date"
                required
                value={formData.next_verification_date}
                onChange={(e) => setFormData({ ...formData, next_verification_date: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Номер свидетельства</label>
              <input
                type="text"
                value={formData.verification_certificate_number}
                onChange={(e) => setFormData({ ...formData, verification_certificate_number: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Организация поверки</label>
              <input
                type="text"
                value={formData.verification_organization}
                onChange={(e) => setFormData({ ...formData, verification_organization: e.target.value })}
                className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
              />
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Скан свидетельства о поверке</label>
            <input
              type="file"
              accept=".pdf,.jpg,.jpeg,.png"
              onChange={(e) => setScanFile(e.target.files?.[0] || null)}
              className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            />
            {item?.scan_file_name && (
              <p className="text-xs text-slate-400 mt-1">Текущий файл: {item.scan_file_name}</p>
            )}
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Примечания</label>
            <textarea
              value={formData.notes}
              onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
              rows={3}
              className="w-full px-3 py-2 bg-primary border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
            />
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-slate-700">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-slate-400 hover:text-white transition"
            >
              Отмена
            </button>
            <button
              type="submit"
              disabled={saving}
              className="px-4 py-2 bg-accent text-white rounded-lg hover:bg-accent/90 transition disabled:opacity-50"
            >
              {saving ? 'Сохранение...' : item ? 'Сохранить' : 'Добавить'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default VerificationsManagement;

