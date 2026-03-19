import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { 
  Award, Plus, Download,
  AlertTriangle, FileText, Save,
  ClipboardList, Package, Gauge, Wrench
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { API_BASE } from '../constants';

interface Certification {
  id: string;
  engineer_id: string;
  certification_type: string;
  method?: string;
  method_code?: string;
  level?: string;
  number: string;
  issued_by: string;
  issue_date?: string;
  expiry_date?: string;
  file_path?: string;
  scan_file_name?: string;
}

interface Assignment {
  id: string;
  equipment_id: string;
  equipment_name?: string;
  status: string;
  due_date: string | null;
  priority: string;
  created_at: string;
}

interface Report {
  id: string;
  inspection_id: string;
  equipment_name?: string;
  title: string;
  created_at: string;
  file_path?: string;
}

interface VerificationItem {
  id: string;
  equipment_type: string;
  serial_number: string;
  manufacturer?: string;
  model?: string;
  expiry_date?: string;
}

type EngineerTab = 'certifications' | 'assignments' | 'reports' | 'equipment' | 'instruments';

const EngineerPanel = () => {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<EngineerTab>('certifications');
  const [certifications, setCertifications] = useState<Certification[]>([]);
  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [verificationEquipment, setVerificationEquipment] = useState<VerificationItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [_editingCert, _setEditingCert] = useState<Certification | null>(null);
  const [showAddForm, setShowAddForm] = useState(false);
  const [formData, setFormData] = useState({
    certification_type: '',
    method: '',
    level: '',
    number: '',
    issued_by: '',
    issue_date: '',
    expiry_date: '',
    file: null as File | null
  });

  useEffect(() => {
    if (user?.engineer_id) {
      loadCertifications();
    }
  }, [user]);

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (!token || !user?.id) return;
    if (activeTab === 'assignments' || activeTab === 'equipment') loadAssignments();
    if (activeTab === 'reports') loadMyReports();
    if (activeTab === 'instruments') loadVerificationEquipment();
  }, [user?.id, activeTab]);

  const loadAssignments = async () => {
    setLoading(true);
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/assignments`, {
        headers: { 'Authorization': `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setAssignments(data.items || data || []);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  const loadMyReports = async () => {
    setLoading(true);
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/reports?limit=200`, {
        headers: { 'Authorization': `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setReports(data.items || data || []);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  const loadVerificationEquipment = async () => {
    setLoading(true);
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/verification-equipment?is_active=true`, {
        headers: { 'Authorization': `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setVerificationEquipment(data.items || data || []);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  const loadCertifications = async () => {
    if (!user?.engineer_id) return;
    
    setLoading(true);
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(
        `${API_BASE}/api/certifications?engineer_id=${user.engineer_id}`,
        {
          headers: {
            'Content-Type': 'application/json',
            ...(token && { 'Authorization': `Bearer ${token}` }),
          },
        }
      );

      if (response.ok) {
        const data = await response.json();
        setCertifications(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки сертификатов:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleAddCertification = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user?.engineer_id) return;

    try {
      const token = localStorage.getItem('token');
      const formDataToSend = new FormData();
      formDataToSend.append('engineer_id', user.engineer_id);
      formDataToSend.append('certification_type', formData.certification_type);
      formDataToSend.append('method', formData.method);
      formDataToSend.append('level', formData.level);
      formDataToSend.append('number', formData.number);
      formDataToSend.append('issued_by', formData.issued_by);
      if (formData.issue_date) {
        formDataToSend.append('issue_date', formData.issue_date);
      }
      if (formData.expiry_date) {
        formDataToSend.append('expiry_date', formData.expiry_date);
      }
      if (formData.file) {
        formDataToSend.append('file', formData.file);
      }

      const response = await fetch(`${API_BASE}/api/certifications`, {
        method: 'POST',
        headers: {
          ...(token && { 'Authorization': `Bearer ${token}` }),
        },
        body: formDataToSend,
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.detail || 'Ошибка при создании сертификата');
      }

      await loadCertifications();
      setShowAddForm(false);
      setFormData({
        certification_type: '',
        method: '',
        level: '',
        number: '',
        issued_by: '',
        issue_date: '',
        expiry_date: '',
        file: null
      });
      alert('Сертификат успешно добавлен!');
    } catch (error: any) {
      console.error('Ошибка при добавлении сертификата:', error);
      alert(`Ошибка: ${error.message}`);
    }
  };

  const formatDate = (dateString?: string) => {
    if (!dateString) return 'Не указана';
    try {
      const date = new Date(dateString);
      return date.toLocaleDateString('ru-RU');
    } catch {
      return dateString;
    }
  };

  const isExpired = (expiryDate?: string) => {
    if (!expiryDate) return false;
    try {
      return new Date(expiryDate) < new Date();
    } catch {
      return false;
    }
  };

  const isExpiringSoon = (expiryDate?: string, days: number = 90) => {
    if (!expiryDate) return false;
    try {
      const expiry = new Date(expiryDate);
      const now = new Date();
      const diffTime = expiry.getTime() - now.getTime();
      const diffDays = diffTime / (1000 * 60 * 60 * 24);
      return diffDays > 0 && diffDays <= days;
    } catch {
      return false;
    }
  };

  const daysUntilExpiry = (expiryDate?: string) => {
    if (!expiryDate) return 0;
    try {
      const expiry = new Date(expiryDate);
      const now = new Date();
      return Math.ceil((expiry.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
    } catch {
      return 0;
    }
  };

  if (!user) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <p className="text-slate-400">Загрузка данных пользователя...</p>
      </div>
    );
  }

  if (!user.engineer_id) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="text-center">
          <AlertTriangle className="mx-auto text-yellow-400 mb-4" size={48} />
          <h2 className="text-2xl font-bold text-white mb-2">Профиль инженера не найден</h2>
          <p className="text-slate-400">Обратитесь к администратору для привязки профиля инженера</p>
        </div>
      </div>
    );
  }

  const tabs: { id: EngineerTab; label: string; icon: React.ReactNode }[] = [
    { id: 'certifications', label: 'Сертификаты НК', icon: <Award size={18} /> },
    { id: 'assignments', label: 'Мои задания', icon: <ClipboardList size={18} /> },
    { id: 'reports', label: 'Мои отчёты', icon: <FileText size={18} /> },
    { id: 'equipment', label: 'Моё оборудование', icon: <Package size={18} /> },
    { id: 'instruments', label: 'Приборы поверки', icon: <Gauge size={18} /> },
  ];

  const uniqueEquipmentFromAssignments = Array.from(
    new Map(assignments.map(a => [a.equipment_id, { id: a.equipment_id, name: a.equipment_name || a.equipment_id }])).values()
  );

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white flex items-center gap-2">
          <Wrench className="text-accent" size={28} />
          Моя панель
        </h1>
        <p className="text-slate-400 mt-1">
          Сертификаты, задания, отчёты и доступное оборудование
        </p>
      </div>

      {/* Табы */}
      <div className="flex flex-wrap gap-2 border-b border-slate-700 pb-2">
        {tabs.map(({ id, label, icon }) => (
          <button
            key={id}
            onClick={() => setActiveTab(id)}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg font-medium transition-colors ${
              activeTab === id
                ? 'bg-accent text-white'
                : 'bg-secondary/50 text-slate-400 hover:text-white hover:bg-secondary'
            }`}
          >
            {icon}
            {label}
          </button>
        ))}
      </div>

      {/* Контент: Сертификаты */}
      {activeTab === 'certifications' && (
        <>
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-white flex items-center gap-2">
            <Award className="text-accent" size={22} />
            Мои сертификаты НК
          </h2>
        </div>
        <button
          onClick={() => setShowAddForm(true)}
          className="px-4 py-2 bg-accent hover:bg-accent/80 rounded-lg text-white font-medium flex items-center gap-2 transition-colors"
        >
          <Plus size={20} />
          Добавить сертификат
        </button>
      </div>

      {/* Предупреждения о истекающих сертификатах */}
      {certifications.filter(c => isExpiringSoon(c.expiry_date)).length > 0 && (
        <div className="bg-yellow-500/20 border border-yellow-500/50 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <AlertTriangle className="text-yellow-400" size={20} />
            <h3 className="text-yellow-400 font-semibold">Истекающие сертификаты</h3>
          </div>
          <div className="space-y-2">
            {certifications
              .filter(c => isExpiringSoon(c.expiry_date))
              .map((cert) => {
                const days = daysUntilExpiry(cert.expiry_date);
                return (
                  <div key={cert.id} className="text-sm text-slate-300">
                    <span className="font-medium text-white">{cert.certification_type}</span>
                    {' - '}
                    <span>{cert.method_code || cert.method || 'Не указан'}</span>
                    {' '}
                    <span className="text-yellow-400">(уровень {cert.level || 'не указан'})</span>
                    {' - истекает через '}
                    <span className="font-semibold text-yellow-400">{days} дн.</span>
                  </div>
                );
              })}
          </div>
        </div>
      )}

      {/* Список сертификатов */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-accent"></div>
          <p className="text-slate-400 mt-4">Загрузка сертификатов...</p>
        </div>
      ) : certifications.length === 0 ? (
        <div className="text-center py-12 bg-secondary/50 rounded-lg">
          <Award className="mx-auto text-slate-400 mb-4" size={48} />
          <p className="text-slate-400">Сертификаты не найдены</p>
          <p className="text-slate-500 text-sm mt-2">Добавьте свой первый сертификат</p>
        </div>
      ) : (
        <div className="space-y-3">
          {certifications.map((cert) => {
            const expired = isExpired(cert.expiry_date);
            const expiringSoon = isExpiringSoon(cert.expiry_date);
            const days = daysUntilExpiry(cert.expiry_date);

            return (
              <div
                key={cert.id}
                className={`bg-secondary/50 rounded-lg p-4 border ${
                  expired
                    ? 'border-red-500/50 bg-red-500/10'
                    : expiringSoon
                    ? 'border-yellow-500/50'
                    : 'border-slate-700'
                }`}
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-2">
                      <Award
                        className={expired ? 'text-red-400' : expiringSoon ? 'text-yellow-400' : 'text-green-400'}
                        size={20}
                      />
                      <h3 className="font-semibold text-white">{cert.certification_type}</h3>
                      {expired && (
                        <span className="px-2 py-1 bg-red-500/20 text-red-400 rounded text-xs">
                          Просрочен
                        </span>
                      )}
                      {expiringSoon && !expired && (
                        <span className="px-2 py-1 bg-yellow-500/20 text-yellow-400 rounded text-xs">
                          Истекает через {days} дн.
                        </span>
                      )}
                    </div>
                    <div className="grid grid-cols-2 gap-2 text-sm">
                      {cert.method && (
                        <div>
                          <span className="text-slate-400">Метод:</span>
                          <span className="text-white ml-2">{cert.method}</span>
                        </div>
                      )}
                      {cert.level && (
                        <div>
                          <span className="text-slate-400">Уровень:</span>
                          <span className="text-white ml-2">{cert.level}</span>
                        </div>
                      )}
                      <div>
                        <span className="text-slate-400">Номер:</span>
                        <span className="text-white ml-2">{cert.number}</span>
                      </div>
                      <div>
                        <span className="text-slate-400">Выдан:</span>
                        <span className="text-white ml-2">{cert.issued_by}</span>
                      </div>
                      {cert.expiry_date && (
                        <div>
                          <span className="text-slate-400">Действителен до:</span>
                          <span
                            className={`ml-2 ${
                              expired ? 'text-red-400' : expiringSoon ? 'text-yellow-400' : 'text-green-400'
                            }`}
                          >
                            {formatDate(cert.expiry_date)}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                  {(cert.file_path || cert.scan_file_name) && (
                    <a
                      href={`${API_BASE}/api/certifications/${cert.id}/scan`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="p-2 text-accent hover:bg-slate-700 rounded transition-colors"
                      title="Скачать документ"
                    >
                      <Download size={20} />
                    </a>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Модальное окно добавления сертификата */}
      {showAddForm && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={() => setShowAddForm(false)}
        >
          <div
            className="bg-secondary rounded-lg max-w-2xl w-full max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-secondary border-b border-slate-700 p-6 flex items-center justify-between">
              <h2 className="text-xl font-bold text-white flex items-center gap-2">
                <Award className="text-accent" size={24} />
                Добавить сертификат
              </h2>
              <button
                onClick={() => setShowAddForm(false)}
                className="text-slate-400 hover:text-white transition-colors"
              >
                ✕
              </button>
            </div>
            <form onSubmit={handleAddCertification} className="p-6 space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Метод контроля <span className="text-red-400">*</span>
                  </label>
                  <select
                    required
                    value={formData.method}
                    onChange={(e) => setFormData({ ...formData, method: e.target.value })}
                    className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
                  >
                    <option value="">Выберите метод</option>
                    <option value="УЗК">УЗК (Ультразвуковой контроль)</option>
                    <option value="РК">РК (Радиографический контроль)</option>
                    <option value="ВИК">ВИК (Визуальный и измерительный контроль)</option>
                    <option value="ПВК">ПВК (Пневматический контроль)</option>
                    <option value="МК">МК (Магнитный контроль)</option>
                    <option value="ПК">ПК (Пенетрантный контроль)</option>
                    <option value="ТК">ТК (Тепловой контроль)</option>
                    <option value="АК">АК (Акустико-эмиссионный контроль)</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Уровень <span className="text-red-400">*</span>
                  </label>
                  <select
                    required
                    value={formData.level}
                    onChange={(e) => setFormData({ ...formData, level: e.target.value })}
                    className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
                  >
                    <option value="">Выберите уровень</option>
                    <option value="I">I уровень</option>
                    <option value="II">II уровень</option>
                    <option value="III">III уровень</option>
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  Тип сертификата <span className="text-red-400">*</span>
                </label>
                <input
                  type="text"
                  required
                  value={formData.certification_type}
                  onChange={(e) => setFormData({ ...formData, certification_type: e.target.value })}
                  placeholder="Например: Допуск к ультразвуковому контролю"
                  className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Номер сертификата <span className="text-red-400">*</span>
                  </label>
                  <input
                    type="text"
                    required
                    value={formData.number}
                    onChange={(e) => setFormData({ ...formData, number: e.target.value })}
                    placeholder="CERT-2024-001"
                    className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Выдан организацией <span className="text-red-400">*</span>
                  </label>
                  <input
                    type="text"
                    required
                    value={formData.issued_by}
                    onChange={(e) => setFormData({ ...formData, issued_by: e.target.value })}
                    placeholder="Ростехнадзор"
                    className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Дата выдачи
                  </label>
                  <input
                    type="date"
                    value={formData.issue_date}
                    onChange={(e) => setFormData({ ...formData, issue_date: e.target.value })}
                    className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Дата окончания <span className="text-red-400">*</span>
                  </label>
                  <input
                    type="date"
                    required
                    value={formData.expiry_date}
                    onChange={(e) => setFormData({ ...formData, expiry_date: e.target.value })}
                    className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  Фото документа
                </label>
                <input
                  type="file"
                  accept="image/*,.pdf"
                  onChange={(e) => setFormData({ ...formData, file: e.target.files?.[0] || null })}
                  className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-semibold file:bg-accent file:text-white hover:file:bg-accent/80"
                />
                {formData.file && (
                  <p className="text-xs text-slate-400 mt-1">Выбран файл: {formData.file.name}</p>
                )}
              </div>

              <div className="flex gap-3 pt-4">
                <button
                  type="submit"
                  className="flex-1 px-4 py-2 bg-accent hover:bg-accent/80 rounded-lg text-white font-medium transition-colors flex items-center justify-center gap-2"
                >
                  <Save size={20} />
                  Сохранить
                </button>
                <button
                  type="button"
                  onClick={() => setShowAddForm(false)}
                  className="px-4 py-2 bg-slate-700 hover:bg-slate-600 rounded-lg text-white font-medium transition-colors"
                >
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
        </>
      )}

      {/* Мои задания */}
      {activeTab === 'assignments' && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-white flex items-center gap-2">
            <ClipboardList className="text-accent" size={22} />
            Мои задания
          </h2>
          {loading ? (
            <div className="text-center py-8 text-slate-400">Загрузка...</div>
          ) : assignments.length === 0 ? (
            <div className="bg-secondary/50 rounded-lg p-8 text-center text-slate-400">
              Нет назначенных заданий
            </div>
          ) : (
            <div className="space-y-2">
              {assignments.map((a) => (
                <div
                  key={a.id}
                  className="bg-secondary/50 rounded-lg p-4 border border-slate-700 flex items-center justify-between flex-wrap gap-2"
                >
                  <div>
                    <p className="font-medium text-white">{a.equipment_name || a.equipment_id}</p>
                    <p className="text-sm text-slate-400">
                      Срок: {a.due_date ? formatDate(a.due_date) : '—'} · Приоритет: {a.priority} · {a.status}
                    </p>
                  </div>
                  <button
                    onClick={() => navigate(`/equipment/${a.equipment_id}`)}
                    className="px-3 py-2 bg-accent/20 text-accent rounded-lg text-sm font-medium hover:bg-accent/30"
                  >
                    К оборудованию
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Мои отчёты */}
      {activeTab === 'reports' && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-white flex items-center gap-2">
            <FileText className="text-accent" size={22} />
            Мои отчёты
          </h2>
          {loading ? (
            <div className="text-center py-8 text-slate-400">Загрузка...</div>
          ) : reports.length === 0 ? (
            <div className="bg-secondary/50 rounded-lg p-8 text-center text-slate-400">
              Нет отчётов
            </div>
          ) : (
            <div className="space-y-2">
              {reports.slice(0, 100).map((r) => (
                <div
                  key={r.id}
                  className="bg-secondary/50 rounded-lg p-4 border border-slate-700 flex items-center justify-between flex-wrap gap-2"
                >
                  <div>
                    <p className="font-medium text-white">{r.title || r.equipment_name || r.id}</p>
                    <p className="text-sm text-slate-400">{r.created_at ? formatDate(r.created_at) : ''}</p>
                  </div>
                  <a
                    href={`${API_BASE}/api/reports/${r.id}/download`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="px-3 py-2 bg-accent/20 text-accent rounded-lg text-sm font-medium hover:bg-accent/30 flex items-center gap-1"
                  >
                    <Download size={16} />
                    Скачать
                  </a>
                </div>
              ))}
              {reports.length > 100 && (
                <p className="text-slate-400 text-sm">Показаны первые 100 из {reports.length}</p>
              )}
            </div>
          )}
        </div>
      )}

      {/* Моё оборудование (из заданий) */}
      {activeTab === 'equipment' && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-white flex items-center gap-2">
            <Package className="text-accent" size={22} />
            Оборудование по моим заданиям
          </h2>
          {uniqueEquipmentFromAssignments.length === 0 ? (
            <div className="bg-secondary/50 rounded-lg p-8 text-center text-slate-400">
              Загрузите задания во вкладке «Мои задания»
            </div>
          ) : (
            <div className="space-y-2">
              {uniqueEquipmentFromAssignments.map((eq) => (
                <div
                  key={eq.id}
                  className="bg-secondary/50 rounded-lg p-4 border border-slate-700 flex items-center justify-between"
                >
                  <p className="font-medium text-white">{eq.name || eq.id}</p>
                  <button
                    onClick={() => navigate(`/equipment/${eq.id}`)}
                    className="px-3 py-2 bg-accent/20 text-accent rounded-lg text-sm font-medium hover:bg-accent/30"
                  >
                    Открыть
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Приборы поверки */}
      {activeTab === 'instruments' && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-white flex items-center gap-2">
            <Gauge className="text-accent" size={22} />
            Приборы поверки (справочник)
          </h2>
          {loading ? (
            <div className="text-center py-8 text-slate-400">Загрузка...</div>
          ) : verificationEquipment.length === 0 ? (
            <div className="bg-secondary/50 rounded-lg p-8 text-center text-slate-400">
              Нет данных
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left">
                <thead>
                  <tr className="text-slate-400 border-b border-slate-700">
                    <th className="py-2 pr-4">Тип</th>
                    <th className="py-2 pr-4">Серийный номер</th>
                    <th className="py-2 pr-4">Производитель</th>
                    <th className="py-2 pr-4">Поверка до</th>
                  </tr>
                </thead>
                <tbody>
                  {verificationEquipment.map((v) => (
                    <tr key={v.id} className="border-b border-slate-700/50">
                      <td className="py-2 pr-4 text-white">{v.equipment_type}</td>
                      <td className="py-2 pr-4 text-white">{v.serial_number}</td>
                      <td className="py-2 pr-4 text-slate-300">{v.manufacturer || '—'}</td>
                      <td className="py-2 pr-4 text-slate-300">{v.expiry_date ? formatDate(v.expiry_date) : '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default EngineerPanel;























