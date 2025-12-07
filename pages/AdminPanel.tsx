import React, { useState, useEffect } from 'react';
import { 
  Users, Shield, FileText, BarChart3, Settings, Search, 
  Plus, Edit, Trash2, Download, Eye, Filter, 
  UserPlus, FileCheck, Award, Calendar, Mail, Phone,
  CheckCircle, XCircle, AlertTriangle, TrendingUp
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

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
  const [showAddUser, setShowAddUser] = useState(false);
  const [showAddEngineer, setShowAddEngineer] = useState(false);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
  const [stats, setStats] = useState({
    totalUsers: 0,
    totalEngineers: 0,
    activeCertifications: 0,
    expiredCertifications: 0,
    totalReports: 0,
    pendingReports: 0,
  });

  const API_BASE = 'http://5.129.203.182:8000';
  const { user, hasRole } = useAuth();

  useEffect(() => {
    loadData();
  }, [activeTab]);

  // Проверка доступа только для администраторов
  if (!hasRole('admin')) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="text-center">
          <Shield className="mx-auto text-red-400 mb-4" size={48} />
          <h2 className="text-2xl font-bold text-white mb-2">Доступ запрещен</h2>
          <p className="text-slate-400">Эта страница доступна только администраторам</p>
          {user && (
            <p className="text-slate-500 mt-2">Ваша роль: {user.role}</p>
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
    <div className="space-y-6">
      {/* Заголовок */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Shield className="text-accent" size={28} />
            Админ панель
          </h1>
          <p className="text-slate-400 mt-1">
            Управление системой, пользователями, документами и отчетами
          </p>
        </div>
      </div>

      {/* Вкладки */}
      <div className="flex gap-2 border-b border-slate-700 overflow-x-auto">
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
            className={`flex items-center gap-2 px-4 py-3 border-b-2 transition-colors whitespace-nowrap ${
              activeTab === tab.id
                ? 'border-accent text-accent'
                : 'border-transparent text-slate-400 hover:text-white'
            }`}
          >
            <tab.icon size={18} />
            <span className="font-medium">{tab.label}</span>
          </button>
        ))}
      </div>

      {/* Поиск */}
      {(activeTab === 'users' || activeTab === 'engineers' || activeTab === 'certifications') && (
        <div className="bg-secondary/50 rounded-lg p-4">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={18} />
            <input
              type="text"
              placeholder="Поиск..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
            />
          </div>
        </div>
      )}

      {/* Контент вкладок */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-accent"></div>
          <p className="text-slate-400 mt-4">Загрузка данных...</p>
        </div>
      ) : (
        <>
          {activeTab === 'users' && (
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <h2 className="text-xl font-bold text-white">Пользователи системы</h2>
                <button
                  onClick={() => setShowAddUser(true)}
                  className="px-4 py-2 bg-accent hover:bg-accent/80 rounded-lg text-white font-medium flex items-center gap-2"
                >
                  <Plus size={20} />
                  Добавить пользователя
                </button>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {filteredUsers.map(user => (
                  <div
                    key={user.id}
                    className="bg-secondary/50 rounded-lg p-6 border border-slate-700 hover:border-accent/50 transition-colors"
                  >
                    <div className="flex items-start justify-between mb-4">
                      <div className="flex items-center gap-3">
                        <div className="w-12 h-12 rounded-full bg-accent flex items-center justify-center text-white font-bold">
                          {user.full_name?.[0]?.toUpperCase() || user.username[0].toUpperCase()}
                        </div>
                        <div>
                          <h3 className="font-semibold text-white">{user.full_name || user.username}</h3>
                          <p className="text-sm text-slate-400">{user.email}</p>
                        </div>
                      </div>
                      <span className={`px-2 py-1 rounded text-xs font-medium ${
                        user.is_active
                          ? 'bg-green-500/20 text-green-400'
                          : 'bg-red-500/20 text-red-400'
                      }`}>
                        {user.is_active ? 'Активен' : 'Неактивен'}
                      </span>
                    </div>
                    <div className="space-y-2">
                      <div className="flex items-center gap-2 text-sm">
                        <span className="text-slate-400">Роль:</span>
                        <span className="text-white font-medium">{user.role}</span>
                      </div>
                      <div className="flex items-center gap-2 text-sm">
                        <span className="text-slate-400">Логин:</span>
                        <span className="text-white">{user.username}</span>
                      </div>
                      {user.last_login && (
                        <div className="flex items-center gap-2 text-sm">
                          <span className="text-slate-400">Последний вход:</span>
                          <span className="text-white">{formatDate(user.last_login)}</span>
                        </div>
                      )}
                    </div>
                    <div className="flex gap-2 mt-4 pt-4 border-t border-slate-700">
                      <button className="flex-1 px-3 py-2 bg-slate-700 hover:bg-slate-600 rounded text-sm text-white">
                        <Edit size={16} className="inline mr-1" />
                        Редактировать
                      </button>
                      <button className="px-3 py-2 bg-red-500/20 hover:bg-red-500/30 rounded text-sm text-red-400">
                        <Trash2 size={16} />
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
                <h2 className="text-xl font-bold text-white">Сотрудники</h2>
                <button
                  onClick={() => setShowAddEngineer(true)}
                  className="px-4 py-2 bg-accent hover:bg-accent/80 rounded-lg text-white font-medium flex items-center gap-2"
                >
                  <Plus size={20} />
                  Добавить сотрудника
                </button>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {filteredEngineers.map(engineer => (
                  <div
                    key={engineer.id}
                    className="bg-secondary/50 rounded-lg p-6 border border-slate-700"
                  >
                    <div className="flex items-start justify-between mb-4">
                      <div className="flex items-center gap-3">
                        <div className="w-12 h-12 rounded-full bg-accent flex items-center justify-center text-white font-bold">
                          {engineer.full_name[0].toUpperCase()}
                        </div>
                        <div>
                          <h3 className="font-semibold text-white">{engineer.full_name}</h3>
                          {engineer.position && (
                            <p className="text-sm text-slate-400">{engineer.position}</p>
                          )}
                        </div>
                      </div>
                      <span className={`px-2 py-1 rounded text-xs font-medium ${
                        engineer.is_active
                          ? 'bg-green-500/20 text-green-400'
                          : 'bg-red-500/20 text-red-400'
                      }`}>
                        {engineer.is_active ? 'Активен' : 'Неактивен'}
                      </span>
                    </div>
                    <div className="space-y-2 text-sm">
                      {engineer.email && (
                        <div className="flex items-center gap-2 text-slate-400">
                          <Mail size={14} />
                          <span>{engineer.email}</span>
                        </div>
                      )}
                      {engineer.phone && (
                        <div className="flex items-center gap-2 text-slate-400">
                          <Phone size={14} />
                          <span>{engineer.phone}</span>
                        </div>
                      )}
                    </div>
                    <div className="flex gap-2 mt-4 pt-4 border-t border-slate-700">
                      <button className="flex-1 px-3 py-2 bg-slate-700 hover:bg-slate-600 rounded text-sm text-white">
                        <Edit size={16} className="inline mr-1" />
                        Редактировать
                      </button>
                      <button className="px-3 py-2 bg-slate-700 hover:bg-slate-600 rounded text-sm text-white">
                        <Eye size={16} />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {activeTab === 'certifications' && (
            <div className="space-y-4">
              <h2 className="text-xl font-bold text-white">Сертификаты сотрудников</h2>
              <div className="space-y-3">
                {filteredCertifications.map(cert => {
                  const isExpired = cert.expiry_date && new Date(cert.expiry_date) < new Date();
                  return (
                    <div
                      key={cert.id}
                      className={`bg-secondary/50 rounded-lg p-4 border ${
                        isExpired ? 'border-red-500/50' : 'border-slate-700'
                      }`}
                    >
                      <div className="flex items-start justify-between">
                        <div className="flex-1">
                          <div className="flex items-center gap-2 mb-2">
                            <Award className={isExpired ? 'text-red-400' : 'text-yellow-400'} size={20} />
                            <h3 className="font-semibold text-white">{cert.certification_type}</h3>
                            {isExpired && (
                              <span className="px-2 py-1 bg-red-500/20 text-red-400 rounded text-xs">
                                Просрочен
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
                                <span className={isExpired ? 'text-red-400 ml-2' : 'text-white ml-2'}>
                                  {formatDate(cert.expiry_date)}
                                </span>
                              </div>
                            )}
                          </div>
                        </div>
                        <button className="px-3 py-2 bg-slate-700 hover:bg-slate-600 rounded text-sm text-white">
                          <Eye size={16} />
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
              <h2 className="text-xl font-bold text-white">Отчеты и экспертизы</h2>
              <div className="space-y-3">
                {reports.map(report => (
                  <div
                    key={report.id}
                    className="bg-secondary/50 rounded-lg p-4 border border-slate-700"
                  >
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <h3 className="font-semibold text-white mb-2">{report.title}</h3>
                        <div className="flex items-center gap-4 text-sm">
                          <span className="text-slate-400">Тип:</span>
                          <span className="text-white">{report.report_type}</span>
                          <span className="text-slate-400">Статус:</span>
                          <span className={`px-2 py-1 rounded text-xs ${
                            report.status === 'APPROVED' ? 'bg-green-500/20 text-green-400' :
                            report.status === 'DRAFT' ? 'bg-yellow-500/20 text-yellow-400' :
                            'bg-slate-700 text-slate-300'
                          }`}>
                            {report.status}
                          </span>
                          <span className="text-slate-400">Создан:</span>
                          <span className="text-white">{formatDate(report.created_at)}</span>
                        </div>
                      </div>
                      <div className="flex gap-2">
                        {report.file_path && (
                          <button className="px-3 py-2 bg-accent hover:bg-accent/80 rounded text-sm text-white">
                            <Download size={16} className="inline mr-1" />
                            Скачать
                          </button>
                        )}
                        <button className="px-3 py-2 bg-slate-700 hover:bg-slate-600 rounded text-sm text-white">
                          <Eye size={16} />
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {activeTab === 'stats' && (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-slate-400 font-medium">Всего пользователей</h3>
                  <Users className="text-accent" size={24} />
                </div>
                <p className="text-3xl font-bold text-white">{stats.totalUsers}</p>
              </div>
              <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-slate-400 font-medium">Сотрудников</h3>
                  <UserPlus className="text-accent" size={24} />
                </div>
                <p className="text-3xl font-bold text-white">{stats.totalEngineers}</p>
              </div>
              <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-slate-400 font-medium">Активных сертификатов</h3>
                  <CheckCircle className="text-green-400" size={24} />
                </div>
                <p className="text-3xl font-bold text-white">{stats.activeCertifications}</p>
              </div>
              <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-slate-400 font-medium">Просроченных сертификатов</h3>
                  <XCircle className="text-red-400" size={24} />
                </div>
                <p className="text-3xl font-bold text-red-400">{stats.expiredCertifications}</p>
              </div>
              <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-slate-400 font-medium">Всего отчетов</h3>
                  <FileText className="text-accent" size={24} />
                </div>
                <p className="text-3xl font-bold text-white">{stats.totalReports}</p>
              </div>
              <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-slate-400 font-medium">Отчетов в работе</h3>
                  <AlertTriangle className="text-yellow-400" size={24} />
                </div>
                <p className="text-3xl font-bold text-yellow-400">{stats.pendingReports}</p>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
};

export default AdminPanel;

