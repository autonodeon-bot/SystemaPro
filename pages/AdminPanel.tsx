import React, { useState, useEffect } from 'react';
import { 
  Users, Shield, FileText, BarChart3, Search, 
  Plus, Edit, Trash2, Download, Eye, 
  UserPlus, Award, Mail, Phone,
  CheckCircle, XCircle, AlertTriangle
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { API_BASE } from '../constants';

interface User {
  id: string;
  username: string;
  email: string;
  full_name: string;
  role: string;
  is_active: boolean;
  engineer_id?: string;
  created_at: string;
  last_login?: string;
}

interface Engineer {
  id: string;
  full_name: string;
  position?: string;
  email?: string;
  phone?: string;
  is_active: number;
}

interface Certification {
  id: string;
  engineer_id: string;
  certification_type: string;
  method?: string;
  level?: string;
  number: string;
  issued_by: string;
  issue_date?: string;
  expiry_date?: string;
}

interface Report {
  id: string;
  title: string;
  report_type: string;
  status: string;
  created_at: string;
  file_path?: string;
}

const AdminPanel = () => {
  const [activeTab, setActiveTab] = useState<'users' | 'engineers' | 'certifications' | 'reports' | 'stats'>('users');
  const [users, setUsers] = useState<User[]>([]);
  const [engineers, setEngineers] = useState<Engineer[]>([]);
  const [certifications, setCertifications] = useState<Certification[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [_showAddUser, setShowAddUser] = useState(false);
  const [showAddEngineer, setShowAddEngineer] = useState(false);
  const [_selectedUser, _setSelectedUser] = useState<User | null>(null);
  const [stats, setStats] = useState({
    totalUsers: 0,
    totalEngineers: 0,
    activeCertifications: 0,
    expiredCertifications: 0,
    totalReports: 0,
    pendingReports: 0,
  });

  const { user, hasRole } = useAuth();

  useEffect(() => {
    loadData();
  }, [activeTab]);

  // Проверка доступа только для администраторов
  if (!hasRole('admin')) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="sp-surface text-center" style={{ padding: '40px', maxWidth: '420px' }}>
          <Shield className="mx-auto mb-4" size={40} style={{ color: 'var(--danger)' }} />
          <h2 className="text-xl font-bold mb-2" style={{ color: 'var(--text-primary)', letterSpacing: '-0.02em' }}>Доступ запрещён</h2>
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>Эта страница доступна только администраторам</p>
          {user && (
            <p className="text-xs mt-2" style={{ color: 'var(--text-muted)' }}>Ваша роль: {user.role}</p>
          )}
        </div>
      </div>
    );
  }

  const loadData = async () => {
    setLoading(true);
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = {
        'Content-Type': 'application/json',
      };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      switch (activeTab) {
        case 'users':
          const usersRes = await fetch(`${API_BASE}/api/users`, { headers });
          if (usersRes.ok) {
            const usersData = await usersRes.json();
            setUsers(usersData.items || []);
          }
          break;
        case 'engineers':
          const engRes = await fetch(`${API_BASE}/api/engineers`, { headers });
          if (engRes.ok) {
            const engData = await engRes.json();
            setEngineers(engData.items || []);
          }
          break;
        case 'certifications':
          const certRes = await fetch(`${API_BASE}/api/certifications`, { headers });
          if (certRes.ok) {
            const certData = await certRes.json();
            setCertifications(certData.items || []);
          }
          break;
        case 'reports':
          const repRes = await fetch(`${API_BASE}/api/reports`, { headers });
          if (repRes.ok) {
            const repData = await repRes.json();
            setReports(repData.items || []);
          }
          break;
        case 'stats':
          await loadStats();
          break;
      }
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadStats = async () => {
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = {
        'Content-Type': 'application/json',
      };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const [usersRes, engRes, certRes, repRes] = await Promise.all([
        fetch(`${API_BASE}/api/users`, { headers }),
        fetch(`${API_BASE}/api/engineers`, { headers }),
        fetch(`${API_BASE}/api/certifications`, { headers }),
        fetch(`${API_BASE}/api/reports`, { headers }),
      ]);

      const usersData = usersRes.ok ? await usersRes.json() : { items: [] };
      const engData = engRes.ok ? await engRes.json() : { items: [] };
      const certData = certRes.ok ? await certRes.json() : { items: [] };
      const repData = repRes.ok ? await repRes.json() : { items: [] };

      const now = new Date();
      const expiredCerts = certData.items.filter((c: Certification) => {
        if (!c.expiry_date) return false;
        return new Date(c.expiry_date) < now;
      });

      const pendingReps = repData.items.filter((r: Report) => r.status === 'DRAFT');

      setStats({
        totalUsers: usersData.items?.length || 0,
        totalEngineers: engData.items?.length || 0,
        activeCertifications: certData.items?.length - expiredCerts.length,
        expiredCertifications: expiredCerts.length,
        totalReports: repData.items?.length || 0,
        pendingReports: pendingReps.length,
      });
    } catch (error) {
      console.error('Ошибка загрузки статистики:', error);
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

  const filteredUsers = users.filter(u =>
    u.username.toLowerCase().includes(searchTerm.toLowerCase()) ||
    u.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    u.full_name?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const filteredEngineers = engineers.filter(e =>
    e.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    e.email?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const filteredCertifications = certifications.filter(c =>
    c.certification_type.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.number.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.method?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="space-y-5 sp-animate-in">
      {/* Заголовок */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2" style={{ color: 'var(--text-primary)', letterSpacing: '-0.02em' }}>
            <Shield size={28} style={{ color: 'var(--accent)' }} />
            Админ панель
          </h1>
          <p className="mt-1 text-sm" style={{ color: 'var(--text-muted)' }}>
            Управление системой, пользователями, документами и отчётами
          </p>
        </div>
      </div>

      {/* Вкладки */}
      <div className="sp-pill-nav overflow-x-auto">
        {[
          { id: 'users', label: 'Пользователи', icon: Users },
          { id: 'engineers', label: 'Сотрудники', icon: UserPlus },
          { id: 'certifications', label: 'Сертификаты', icon: Award },
          { id: 'reports', label: 'Отчеты', icon: FileText },
          { id: 'stats', label: 'Статистика', icon: BarChart3 },
        ].map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id as any)}
            className={`sp-pill-nav__item ${activeTab === tab.id ? 'is-active' : ''}`}
          >
            <tab.icon size={16} />
            <span>{tab.label}</span>
          </button>
        ))}
      </div>

      {/* Поиск */}
      {(activeTab === 'users' || activeTab === 'engineers' || activeTab === 'certifications') && (
        <div className="sp-surface" style={{ padding: '12px' }}>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2" size={16} style={{ color: 'var(--text-muted)' }} />
            <input
              type="text"
              placeholder="Поиск..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="ind-input w-full pl-9"
              style={{ height: '40px' }}
            />
          </div>
        </div>
      )}

      {/* Контент вкладок */}
      {loading ? (
        <div className="sp-surface flex flex-col items-center justify-center py-16">
          <div className="animate-spin rounded-full h-8 w-8 border-2 border-transparent" style={{ borderTopColor: 'var(--accent)', borderRightColor: 'var(--accent)' }}></div>
          <p className="mt-4 text-sm" style={{ color: 'var(--text-muted)' }}>Загрузка данных...</p>
        </div>
      ) : (
        <>
          {activeTab === 'users' && (
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <h2 className="sp-section-title">Пользователи системы</h2>
                <button
                  onClick={() => setShowAddUser(true)}
                  className="ind-btn ind-btn--primary"
                >
                  <Plus size={16} />
                  Добавить пользователя
                </button>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                {filteredUsers.map(user => (
                  <div key={user.id} className="sp-surface" style={{ padding: '16px' }}>
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full flex items-center justify-center font-bold text-white" style={{ background: 'var(--accent)', fontSize: '14px' }}>
                          {user.full_name?.[0]?.toUpperCase() || user.username[0].toUpperCase()}
                        </div>
                        <div>
                          <h3 className="font-semibold text-sm" style={{ color: 'var(--text-primary)', letterSpacing: '-0.01em' }}>{user.full_name || user.username}</h3>
                          <p className="text-xs" style={{ color: 'var(--text-muted)' }}>{user.email}</p>
                        </div>
                      </div>
                      <span className={`ind-chip ${user.is_active ? 'ind-chip--success' : 'ind-chip--danger'}`}>
                        {user.is_active ? 'Активен' : 'Неактивен'}
                      </span>
                    </div>
                    <div className="space-y-1.5 text-xs">
                      <div className="flex items-center justify-between">
                        <span style={{ color: 'var(--text-muted)' }}>Роль</span>
                        <span className="font-medium" style={{ color: 'var(--text-primary)' }}>{user.role}</span>
                      </div>
                      <div className="flex items-center justify-between">
                        <span style={{ color: 'var(--text-muted)' }}>Логин</span>
                        <span style={{ color: 'var(--text-primary)' }}>{user.username}</span>
                      </div>
                      {user.last_login && (
                        <div className="flex items-center justify-between">
                          <span style={{ color: 'var(--text-muted)' }}>Последний вход</span>
                          <span className="tabular-nums" style={{ color: 'var(--text-primary)' }}>{formatDate(user.last_login)}</span>
                        </div>
                      )}
                    </div>
                    <div className="flex gap-2 mt-3 pt-3" style={{ borderTop: '1px solid var(--border)' }}>
                      <button className="ind-btn flex-1">
                        <Edit size={14} />
                        Редактировать
                      </button>
                      <button className="ind-btn" style={{ color: 'var(--danger)' }}>
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {activeTab === 'engineers' && (
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <h2 className="sp-section-title">Сотрудники</h2>
                <button
                  onClick={() => setShowAddEngineer(true)}
                  className="ind-btn ind-btn--primary"
                >
                  <Plus size={16} />
                  Добавить сотрудника
                </button>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                {filteredEngineers.map(engineer => (
                  <div key={engineer.id} className="sp-surface" style={{ padding: '16px' }}>
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full flex items-center justify-center font-bold text-white" style={{ background: 'var(--accent)', fontSize: '14px' }}>
                          {engineer.full_name[0].toUpperCase()}
                        </div>
                        <div>
                          <h3 className="font-semibold text-sm" style={{ color: 'var(--text-primary)', letterSpacing: '-0.01em' }}>{engineer.full_name}</h3>
                          {engineer.position && (
                            <p className="text-xs" style={{ color: 'var(--text-muted)' }}>{engineer.position}</p>
                          )}
                        </div>
                      </div>
                      <span className={`ind-chip ${engineer.is_active ? 'ind-chip--success' : 'ind-chip--danger'}`}>
                        {engineer.is_active ? 'Активен' : 'Неактивен'}
                      </span>
                    </div>
                    <div className="space-y-1.5 text-xs">
                      {engineer.email && (
                        <div className="flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
                          <Mail size={13} />
                          <span className="truncate">{engineer.email}</span>
                        </div>
                      )}
                      {engineer.phone && (
                        <div className="flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
                          <Phone size={13} />
                          <span>{engineer.phone}</span>
                        </div>
                      )}
                    </div>
                    <div className="flex gap-2 mt-3 pt-3" style={{ borderTop: '1px solid var(--border)' }}>
                      <button className="ind-btn flex-1">
                        <Edit size={14} />
                        Редактировать
                      </button>
                      <button className="ind-btn">
                        <Eye size={14} />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {activeTab === 'certifications' && (
            <div className="space-y-4">
              <h2 className="sp-section-title">Сертификаты сотрудников</h2>
              <div className="space-y-2">
                {filteredCertifications.map(cert => {
                  const isExpired = cert.expiry_date && new Date(cert.expiry_date) < new Date();
                  return (
                    <div
                      key={cert.id}
                      className="sp-surface"
                      style={{ padding: '14px', borderColor: isExpired ? 'var(--danger-soft-border, color-mix(in srgb, var(--danger) 35%, transparent))' : undefined }}
                    >
                      <div className="flex items-start justify-between gap-4">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-2 flex-wrap">
                            <Award size={16} style={{ color: isExpired ? 'var(--danger)' : 'var(--warning)' }} />
                            <h3 className="font-semibold text-sm" style={{ color: 'var(--text-primary)', letterSpacing: '-0.01em' }}>{cert.certification_type}</h3>
                            {isExpired && (
                              <span className="ind-chip ind-chip--danger">Просрочен</span>
                            )}
                          </div>
                          <div className="grid grid-cols-2 lg:grid-cols-3 gap-x-4 gap-y-1 text-xs">
                            {cert.method && (
                              <div className="flex gap-1">
                                <span style={{ color: 'var(--text-muted)' }}>Метод:</span>
                                <span style={{ color: 'var(--text-primary)' }}>{cert.method}</span>
                              </div>
                            )}
                            {cert.level && (
                              <div className="flex gap-1">
                                <span style={{ color: 'var(--text-muted)' }}>Уровень:</span>
                                <span style={{ color: 'var(--text-primary)' }}>{cert.level}</span>
                              </div>
                            )}
                            <div className="flex gap-1">
                              <span style={{ color: 'var(--text-muted)' }}>№</span>
                              <span className="tabular-nums" style={{ color: 'var(--text-primary)' }}>{cert.number}</span>
                            </div>
                            <div className="flex gap-1">
                              <span style={{ color: 'var(--text-muted)' }}>Выдан:</span>
                              <span style={{ color: 'var(--text-primary)' }}>{cert.issued_by}</span>
                            </div>
                            {cert.expiry_date && (
                              <div className="flex gap-1">
                                <span style={{ color: 'var(--text-muted)' }}>До:</span>
                                <span className="tabular-nums" style={{ color: isExpired ? 'var(--danger)' : 'var(--text-primary)' }}>
                                  {formatDate(cert.expiry_date)}
                                </span>
                              </div>
                            )}
                          </div>
                        </div>
                        <button className="ind-btn">
                          <Eye size={14} />
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {activeTab === 'reports' && (
            <div className="space-y-4">
              <h2 className="sp-section-title">Отчёты и экспертизы</h2>
              <div className="space-y-2">
                {reports.map(report => (
                  <div key={report.id} className="sp-surface" style={{ padding: '14px' }}>
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex-1 min-w-0">
                        <h3 className="font-semibold text-sm mb-2" style={{ color: 'var(--text-primary)', letterSpacing: '-0.01em' }}>{report.title}</h3>
                        <div className="flex items-center gap-x-3 gap-y-1 text-xs flex-wrap">
                          <span style={{ color: 'var(--text-muted)' }}>Тип:</span>
                          <span style={{ color: 'var(--text-primary)' }}>{report.report_type}</span>
                          <span className={`ind-chip ${
                            report.status === 'APPROVED' ? 'ind-chip--success' :
                            report.status === 'DRAFT' ? 'ind-chip--warning' :
                            ''
                          }`}>
                            {report.status}
                          </span>
                          <span style={{ color: 'var(--text-muted)' }}>Создан:</span>
                          <span className="tabular-nums" style={{ color: 'var(--text-primary)' }}>{formatDate(report.created_at)}</span>
                        </div>
                      </div>
                      <div className="flex gap-2">
                        {report.file_path && (
                          <button className="ind-btn ind-btn--primary">
                            <Download size={14} />
                            Скачать
                          </button>
                        )}
                        <button className="ind-btn">
                          <Eye size={14} />
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {activeTab === 'stats' && (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              <div className="sp-stat">
                <div className="sp-stat__head">
                  <span className="sp-stat__label">Всего пользователей</span>
                  <Users size={16} style={{ color: 'var(--accent)' }} />
                </div>
                <div className="sp-stat__value tabular-nums">{stats.totalUsers}</div>
              </div>
              <div className="sp-stat">
                <div className="sp-stat__head">
                  <span className="sp-stat__label">Сотрудников</span>
                  <UserPlus size={16} style={{ color: 'var(--accent)' }} />
                </div>
                <div className="sp-stat__value tabular-nums">{stats.totalEngineers}</div>
              </div>
              <div className="sp-stat">
                <div className="sp-stat__head">
                  <span className="sp-stat__label">Активных сертификатов</span>
                  <CheckCircle size={16} style={{ color: 'var(--success)' }} />
                </div>
                <div className="sp-stat__value tabular-nums" style={{ color: 'var(--success)' }}>{stats.activeCertifications}</div>
              </div>
              <div className="sp-stat">
                <div className="sp-stat__head">
                  <span className="sp-stat__label">Просроченных сертификатов</span>
                  <XCircle size={16} style={{ color: 'var(--danger)' }} />
                </div>
                <div className="sp-stat__value tabular-nums" style={{ color: 'var(--danger)' }}>{stats.expiredCertifications}</div>
              </div>
              <div className="sp-stat">
                <div className="sp-stat__head">
                  <span className="sp-stat__label">Всего отчётов</span>
                  <FileText size={16} style={{ color: 'var(--accent)' }} />
                </div>
                <div className="sp-stat__value tabular-nums">{stats.totalReports}</div>
              </div>
              <div className="sp-stat">
                <div className="sp-stat__head">
                  <span className="sp-stat__label">Отчётов в работе</span>
                  <AlertTriangle size={16} style={{ color: 'var(--warning)' }} />
                </div>
                <div className="sp-stat__value tabular-nums" style={{ color: 'var(--warning)' }}>{stats.pendingReports}</div>
              </div>
            </div>
          )}
        </>
      )}

      {/* Модальное окно добавления инженера */}
      {showAddEngineer && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowAddEngineer(false)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-2xl w-full mx-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">Добавить инженера</h2>
              <button onClick={() => setShowAddEngineer(false)} className="text-slate-400 hover:text-white">✕</button>
            </div>
            <AddEngineerForm onClose={() => setShowAddEngineer(false)} onSuccess={() => {
              setShowAddEngineer(false);
              loadData();
            }} />
          </div>
        </div>
      )}
    </div>
  );
};

// Компонент формы добавления инженера
const AddEngineerForm: React.FC<{ onClose: () => void; onSuccess: () => void }> = ({ onClose, onSuccess }) => {
  const [formData, setFormData] = useState({
    full_name: '',
    position: '',
    email: '',
    phone: '',
    qualifications: [] as string[],
    equipment_types: [] as string[],
  });
  const [qualificationInput, setQualificationInput] = useState('');
  const [equipmentTypes, setEquipmentTypes] = useState<any[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadEquipmentTypes();
  }, []);

  const loadEquipmentTypes = async () => {
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/equipment-types`, { headers });
      if (response.ok) {
        const data = await response.json();
        setEquipmentTypes(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки типов оборудования:', error);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      const response = await fetch(`${API_BASE}/api/engineers`, {
        method: 'POST',
        headers,
        body: JSON.stringify(formData)
      });

      if (response.ok) {
        setFormData({
          full_name: '',
          position: '',
          email: '',
          phone: '',
          qualifications: [],
          equipment_types: [],
        });
        setQualificationInput('');
        onSuccess();
        alert('Инженер успешно создан');
      } else {
        const errorData = await response.json();
        setError(errorData.detail || 'Ошибка при создании инженера');
      }
    } catch (error: any) {
      setError(error.message || 'Ошибка при создании инженера');
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {error && (
        <div className="bg-red-500/20 border border-red-500 rounded-lg p-3 text-red-400 text-sm">
          {error}
        </div>
      )}

      <div>
        <label className="text-sm text-slate-400 block mb-1">ФИО *</label>
        <input
          type="text"
          required
          value={formData.full_name}
          onChange={(e) => setFormData({ ...formData, full_name: e.target.value })}
          className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
          placeholder="Иванов Иван Иванович"
        />
      </div>

      <div>
        <label className="text-sm text-slate-400 block mb-1">Должность</label>
        <input
          type="text"
          value={formData.position}
          onChange={(e) => setFormData({ ...formData, position: e.target.value })}
          className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
          placeholder="Инженер-диагност"
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="text-sm text-slate-400 block mb-1">Email</label>
          <input
            type="email"
            value={formData.email}
            onChange={(e) => setFormData({ ...formData, email: e.target.value })}
            className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
            placeholder="ivanov@example.com"
          />
        </div>
        <div>
          <label className="text-sm text-slate-400 block mb-1">Телефон</label>
          <input
            type="tel"
            value={formData.phone}
            onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
            className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
            placeholder="+7 (XXX) XXX-XX-XX"
          />
        </div>
      </div>

      <div>
        <label className="text-sm text-slate-400 block mb-2">Квалификации</label>
        <div className="flex gap-2 mb-2">
          <input
            type="text"
            value={qualificationInput}
            onChange={(e) => setQualificationInput(e.target.value)}
            onKeyPress={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                if (qualificationInput.trim() && !formData.qualifications.includes(qualificationInput.trim())) {
                  setFormData({ ...formData, qualifications: [...formData.qualifications, qualificationInput.trim()] });
                  setQualificationInput('');
                }
              }
            }}
            className="flex-1 bg-slate-900 border border-slate-700 rounded p-2 text-white"
            placeholder="Введите квалификацию и нажмите Enter"
          />
          <button
            type="button"
            onClick={() => {
              if (qualificationInput.trim() && !formData.qualifications.includes(qualificationInput.trim())) {
                setFormData({ ...formData, qualifications: [...formData.qualifications, qualificationInput.trim()] });
                setQualificationInput('');
              }
            }}
            className="bg-accent/20 text-accent px-4 py-2 rounded hover:bg-accent/30"
          >
            Добавить
          </button>
        </div>
        {formData.qualifications.length > 0 && (
          <div className="flex flex-wrap gap-2 mb-2">
            {formData.qualifications.map((qual, idx) => (
              <span key={idx} className="bg-slate-700 text-slate-300 px-3 py-1 rounded text-sm flex items-center gap-2">
                {qual}
                <button
                  type="button"
                  onClick={() => {
                    setFormData({ ...formData, qualifications: formData.qualifications.filter((_, i) => i !== idx) });
                  }}
                  className="text-red-400 hover:text-red-300"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        )}
      </div>

      <div>
        <label className="text-sm text-slate-400 block mb-2">Типы оборудования, с которыми работает</label>
        <div className="grid grid-cols-2 gap-2 max-h-48 overflow-y-auto bg-slate-900 border border-slate-700 rounded p-3">
          {equipmentTypes.map((type) => (
            <label key={type.id} className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={formData.equipment_types.includes(type.id)}
                onChange={(e) => {
                  if (e.target.checked) {
                    setFormData({ ...formData, equipment_types: [...formData.equipment_types, type.id] });
                  } else {
                    setFormData({ ...formData, equipment_types: formData.equipment_types.filter(id => id !== type.id) });
                  }
                }}
                className="accent-blue-500"
              />
              <span className="text-white text-sm">{type.name}</span>
            </label>
          ))}
        </div>
        {equipmentTypes.length === 0 && (
          <p className="text-xs text-yellow-400 mt-1">Типы оборудования не загружены</p>
        )}
      </div>

      <div className="flex gap-2">
        <button
          type="submit"
          disabled={saving}
          className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80 disabled:opacity-50"
        >
          {saving ? 'Создание...' : 'Создать'}
        </button>
        <button
          type="button"
          onClick={onClose}
          className="bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
        >
          Отмена
        </button>
      </div>
    </form>
  );
};

export default AdminPanel;

