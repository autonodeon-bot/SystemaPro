import React, { useState, useEffect, useMemo } from 'react';
import { Users, User, Mail, Shield, Search, Edit, Trash2, Plus, X, Camera, Phone, Briefcase, Save, ArrowUp, ArrowDown, ArrowUpDown, CheckCircle, XCircle } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { API_BASE } from '../constants';

interface UserData {
  id: string;
  username: string;
  email?: string;
  full_name?: string;
  role: string;
  engineer_id?: string;
  phone?: string;
  position?: string;
  department?: string;
  photo_url?: string;
  is_active?: boolean;
}

const UsersManagement = () => {
  const { user: currentUser } = useAuth();
  const [users, setUsers] = useState<UserData[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [filterRole, setFilterRole] = useState<string>('all');
  const [filterActive, setFilterActive] = useState<string>('all');
  const [sortCol, setSortCol] = useState<string>('full_name');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [selectedUser, setSelectedUser] = useState<UserData | null>(null);
  const [formData, setFormData] = useState({
    username: '',
    password: '',
    email: '',
    full_name: '',
    role: 'engineer',
    phone: '',
    position: '',
    department: '',
    engineer_id: '',
    is_active: true,
  });
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);

  const textClass = 'text-app-text';
  const textSecondaryClass = 'text-app-text3';
  const borderClass = 'border-app-line';
  const inputBgClass = 'bg-app-panel';
  const cardBgClass = 'bg-app-panel';

  useEffect(() => {
    if (currentUser?.role === 'admin') {
      loadUsers();
    }
  }, [currentUser]);

  const loadUsers = async () => {
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/users`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      if (response.ok) {
        const data = await response.json();
        setUsers(data.items || []);
      } else {
        console.error('Ошибка загрузки пользователей:', response.status);
      }
    } catch (error) {
      console.error('Ошибка загрузки пользователей:', error);
    } finally {
      setLoading(false);
    }
  };

  const handlePhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      const file = e.target.files[0];
      setPhotoFile(file);
      const reader = new FileReader();
      reader.onloadend = () => {
        setPhotoPreview(reader.result as string);
      };
      reader.readAsDataURL(file);
    }
  };

  const handleCreateUser = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const token = localStorage.getItem('token');
      const formDataToSend = new FormData();
      
      formDataToSend.append('username', formData.username);
      formDataToSend.append('password', formData.password);
      formDataToSend.append('email', formData.email);
      formDataToSend.append('full_name', formData.full_name);
      formDataToSend.append('role', formData.role);
      formDataToSend.append('phone', formData.phone);
      formDataToSend.append('position', formData.position);
      formDataToSend.append('department', formData.department);
      formDataToSend.append('engineer_id', formData.engineer_id);
      formDataToSend.append('is_active', formData.is_active ? '1' : '0');
      
      if (photoFile) {
        formDataToSend.append('photo', photoFile);
      }

      const response = await fetch(`${API_BASE}/api/users`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`
        },
        body: formDataToSend
      });

      if (response.ok) {
        alert('Сотрудник успешно создан');
        setShowCreateModal(false);
        resetForm();
        loadUsers();
      } else {
        const error = await response.json();
        const detail = error.detail;
        const msg =
          typeof detail === 'string'
            ? detail
            : detail?.message ||
              (Array.isArray(detail?.errors) ? detail.errors.join('; ') : null) ||
              'Не удалось создать сотрудника';
        alert(`Ошибка: ${msg}`);
      }
    } catch (error) {
      console.error('Ошибка создания сотрудника:', error);
      alert('Ошибка создания сотрудника');
    }
  };

  const handleEditUser = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedUser) return;

    try {
      const token = localStorage.getItem('token');
      const formDataToSend = new FormData();
      
      formDataToSend.append('email', formData.email);
      formDataToSend.append('full_name', formData.full_name);
      formDataToSend.append('role', formData.role);
      formDataToSend.append('phone', formData.phone);
      formDataToSend.append('position', formData.position);
      formDataToSend.append('department', formData.department);
      formDataToSend.append('engineer_id', formData.engineer_id);
      formDataToSend.append('is_active', formData.is_active ? '1' : '0');
      
      if (photoFile) {
        formDataToSend.append('photo', photoFile);
      }
      if (formData.password) {
        formDataToSend.append('password', formData.password);
      }

      const response = await fetch(`${API_BASE}/api/users/${selectedUser.id}`, {
        method: 'PUT',
        headers: {
          'Authorization': `Bearer ${token}`
        },
        body: formDataToSend
      });

      if (response.ok) {
        alert('Сотрудник успешно обновлен');
        setShowEditModal(false);
        setSelectedUser(null);
        resetForm();
        loadUsers();
      } else {
        const error = await response.json();
        const detail = error.detail;
        const msg =
          typeof detail === 'string'
            ? detail
            : detail?.message ||
              (Array.isArray(detail?.errors) ? detail.errors.join('; ') : null) ||
              'Не удалось обновить сотрудника';
        alert(`Ошибка: ${msg}`);
      }
    } catch (error) {
      console.error('Ошибка обновления сотрудника:', error);
      alert('Ошибка обновления сотрудника');
    }
  };

  const handleDeleteUser = async (userId: string) => {
    if (!confirm('Вы уверены, что хотите удалить этого сотрудника?')) return;

    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/users/${userId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      if (response.ok) {
        alert('Сотрудник успешно удален');
        loadUsers();
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось удалить сотрудника'}`);
      }
    } catch (error) {
      console.error('Ошибка удаления сотрудника:', error);
      alert('Ошибка удаления сотрудника');
    }
  };

  const openEditModal = (user: UserData) => {
    setSelectedUser(user);
    setFormData({
      username: user.username,
      password: '',
      email: user.email || '',
      full_name: user.full_name || '',
      role: user.role,
      phone: user.phone || '',
      position: user.position || '',
      department: user.department || '',
      engineer_id: user.engineer_id || '',
      is_active: user.is_active !== false,
    });
    setPhotoPreview(user.photo_url || null);
    setPhotoFile(null);
    setShowEditModal(true);
  };

  const resetForm = () => {
    setFormData({
      username: '',
      password: '',
      email: '',
      full_name: '',
      role: 'engineer',
      phone: '',
      position: '',
      department: '',
      engineer_id: '',
      is_active: true,
    });
    setPhotoFile(null);
    setPhotoPreview(null);
  };

  const getRoleLabel = (role: string) => {
    const labels: { [key: string]: string } = {
      'admin': 'Администратор',
      'chief_operator': 'Шеф-оператор',
      'operator': 'Оператор',
      'engineer': 'Инженер',
      'client': 'Клиент'
    };
    return labels[role] || role;
  };

  const getRoleColor = (role: string) => {
    const colors: { [key: string]: string } = {
      'admin': 'bg-red-500/20 text-red-400 border-red-500/50',
      'chief_operator': 'bg-purple-500/20 text-purple-400 border-purple-500/50',
      'operator': 'bg-blue-500/20 text-blue-400 border-blue-500/50',
      'engineer': 'bg-green-500/20 text-green-400 border-green-500/50',
      'client': 'bg-yellow-500/20 text-yellow-400 border-yellow-500/50'
    };
    return colors[role] || 'bg-app-text3/20 text-app-text3 border-app-line/50';
  };

  const filteredUsers = useMemo(() => {
    let list = users.filter(u => {
      const q = searchQuery.toLowerCase();
      const matchesSearch = q === '' ||
        u.username.toLowerCase().includes(q) ||
        (u.full_name?.toLowerCase().includes(q) ?? false) ||
        (u.email?.toLowerCase().includes(q) ?? false) ||
        (u.position?.toLowerCase().includes(q) ?? false) ||
        (u.department?.toLowerCase().includes(q) ?? false);
      const matchesRole = filterRole === 'all' || u.role === filterRole;
      const matchesActive = filterActive === 'all'
        || (filterActive === 'active' && u.is_active !== false)
        || (filterActive === 'inactive' && u.is_active === false);
      return matchesSearch && matchesRole && matchesActive;
    });
    list = [...list].sort((a, b) => {
      let av: string = '';
      let bv: string = '';
      if (sortCol === 'full_name') { av = (a.full_name || a.username).toLowerCase(); bv = (b.full_name || b.username).toLowerCase(); }
      else if (sortCol === 'role') { av = a.role; bv = b.role; }
      else if (sortCol === 'email') { av = a.email?.toLowerCase() ?? ''; bv = b.email?.toLowerCase() ?? ''; }
      else if (sortCol === 'position') { av = a.position?.toLowerCase() ?? ''; bv = b.position?.toLowerCase() ?? ''; }
      const cmp = av < bv ? -1 : av > bv ? 1 : 0;
      return sortDir === 'asc' ? cmp : -cmp;
    });
    return list;
  }, [users, searchQuery, filterRole, filterActive, sortCol, sortDir]);

  const handleSort = (col: string) => {
    if (sortCol === col) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortCol(col); setSortDir('asc'); }
  };

  const SortIcon = ({ col }: { col: string }) => {
    if (sortCol !== col) return <ArrowUpDown size={12} className="ml-1 opacity-30 inline" />;
    return sortDir === 'asc'
      ? <ArrowUp size={12} className="ml-1 inline" style={{ color: 'var(--accent)' }} />
      : <ArrowDown size={12} className="ml-1 inline" style={{ color: 'var(--accent)' }} />;
  };

  if (currentUser?.role !== 'admin') {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="sp-surface text-center" style={{ padding: '40px', maxWidth: '420px' }}>
          <Shield className="mx-auto mb-4" size={40} style={{ color: 'var(--danger)' }} />
          <h2 className="text-xl font-bold mb-2" style={{ color: 'var(--text-primary)', letterSpacing: '-0.02em' }}>Доступ запрещён</h2>
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>Только администратор может просматривать список пользователей.</p>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="sp-surface flex flex-col items-center justify-center py-16">
        <div className="animate-spin rounded-full h-8 w-8 border-2 border-transparent" style={{ borderTopColor: 'var(--accent)', borderRightColor: 'var(--accent)' }}></div>
        <p className="mt-4 text-sm" style={{ color: 'var(--text-muted)' }}>Загрузка...</p>
      </div>
    );
  }

  return (
    <div className="space-y-5 sp-animate-in">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Users size={28} style={{ color: 'var(--accent)' }} />
          <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)', letterSpacing: '-0.02em' }}>Сотрудники</h1>
        </div>
        <button
          onClick={() => { resetForm(); setShowCreateModal(true); }}
          className="ind-btn ind-btn--primary"
        >
          <Plus size={16} />
          Добавить сотрудника
        </button>
      </div>

      {/* Фильтры */}
      <div className="sp-surface" style={{ padding: '12px' }}>
        <div className="flex flex-wrap gap-3 items-center">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2" size={15} style={{ color: 'var(--text-muted)' }} />
            <input
              type="text"
              placeholder="Поиск по имени, логину, email, должности..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="ind-input w-full pl-9"
              style={{ height: '38px' }}
            />
          </div>
          <select
            value={filterRole}
            onChange={(e) => setFilterRole(e.target.value)}
            className="ind-input"
            style={{ height: '38px', minWidth: 140 }}
          >
            <option value="all">Все роли</option>
            <option value="admin">Администратор</option>
            <option value="chief_operator">Шеф-оператор</option>
            <option value="operator">Оператор</option>
            <option value="engineer">Инженер</option>
            <option value="client">Клиент</option>
          </select>
          <select
            value={filterActive}
            onChange={(e) => setFilterActive(e.target.value)}
            className="ind-input"
            style={{ height: '38px', minWidth: 130 }}
          >
            <option value="all">Все</option>
            <option value="active">Активные</option>
            <option value="inactive">Отключённые</option>
          </select>
          <span className="text-sm ml-auto" style={{ color: 'var(--text-muted)' }}>
            {filteredUsers.length} из {users.length}
          </span>
        </div>
      </div>

      {/* Таблица пользователей */}
      <div className="sp-surface overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ borderBottom: '1px solid var(--border-subtle)', background: 'var(--bg-tertiary)' }}>
                <th className="px-4 py-3 text-left font-semibold cursor-pointer select-none" style={{ color: 'var(--text-secondary)' }} onClick={() => handleSort('full_name')}>
                  Сотрудник<SortIcon col="full_name" />
                </th>
                <th className="px-4 py-3 text-left font-semibold cursor-pointer select-none" style={{ color: 'var(--text-secondary)' }} onClick={() => handleSort('role')}>
                  Роль<SortIcon col="role" />
                </th>
                <th className="px-4 py-3 text-left font-semibold cursor-pointer select-none hidden md:table-cell" style={{ color: 'var(--text-secondary)' }} onClick={() => handleSort('email')}>
                  Email<SortIcon col="email" />
                </th>
                <th className="px-4 py-3 text-left font-semibold cursor-pointer select-none hidden lg:table-cell" style={{ color: 'var(--text-secondary)' }} onClick={() => handleSort('position')}>
                  Должность<SortIcon col="position" />
                </th>
                <th className="px-4 py-3 text-left font-semibold" style={{ color: 'var(--text-secondary)' }}>Статус</th>
                <th className="px-4 py-3 text-right font-semibold" style={{ color: 'var(--text-secondary)' }}>Действия</th>
              </tr>
            </thead>
            <tbody>
              {filteredUsers.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-10 text-center" style={{ color: 'var(--text-muted)' }}>
                    Сотрудники не найдены
                  </td>
                </tr>
              ) : filteredUsers.map((user) => (
                <tr key={user.id} style={{ borderBottom: '1px solid var(--border-subtle)' }} className="hover:bg-white/[0.02] transition-colors">
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-3">
                      {user.photo_url ? (
                        <img src={user.photo_url} alt="" className="w-8 h-8 rounded-full object-cover flex-shrink-0" />
                      ) : (
                        <div className="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: 'var(--accent-glow)' }}>
                          <User size={15} style={{ color: 'var(--accent)' }} />
                        </div>
                      )}
                      <div className="min-w-0">
                        <div className="font-semibold truncate" style={{ color: 'var(--text-primary)' }}>{user.full_name || user.username}</div>
                        <div className="text-xs truncate" style={{ color: 'var(--text-muted)' }}>@{user.username}</div>
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-0.5 rounded-full text-xs font-semibold border ${getRoleColor(user.role)}`}>
                      {getRoleLabel(user.role)}
                    </span>
                  </td>
                  <td className="px-4 py-3 hidden md:table-cell">
                    {user.email ? (
                      <div className="flex items-center gap-1.5 text-xs" style={{ color: 'var(--text-muted)' }}>
                        <Mail size={12} />{user.email}
                      </div>
                    ) : <span style={{ color: 'var(--text-muted)' }}>—</span>}
                  </td>
                  <td className="px-4 py-3 hidden lg:table-cell">
                    {user.position ? (
                      <div className="flex items-center gap-1.5 text-xs" style={{ color: 'var(--text-muted)' }}>
                        <Briefcase size={12} />{user.position}
                      </div>
                    ) : <span style={{ color: 'var(--text-muted)' }}>—</span>}
                  </td>
                  <td className="px-4 py-3">
                    {user.is_active !== false
                      ? <span className="flex items-center gap-1 text-xs font-medium" style={{ color: 'var(--success)' }}><CheckCircle size={13} />Активен</span>
                      : <span className="flex items-center gap-1 text-xs font-medium" style={{ color: 'var(--danger)' }}><XCircle size={13} />Отключён</span>}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center justify-end gap-1">
                      <button onClick={() => openEditModal(user)} className="ind-btn" title="Редактировать" style={{ padding: '4px 8px' }}>
                        <Edit size={14} />
                      </button>
                      <button onClick={() => handleDeleteUser(user.id)} className="ind-btn" title="Удалить" style={{ padding: '4px 8px', color: 'var(--danger)' }}>
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {filteredUsers.length === 0 && (
        <div className="sp-surface text-center" style={{ padding: '60px 20px' }}>
          <Users className="mx-auto mb-3 opacity-40" size={40} style={{ color: 'var(--text-muted)' }} />
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>Пользователи не найдены</p>
        </div>
      )}

      {/* Модальное окно создания сотрудника */}
      {showCreateModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className={`${cardBgClass} rounded-xl p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto border ${borderClass}`}>
            <div className="flex justify-between items-center mb-6">
              <h2 className={`text-xl font-bold ${textClass}`}>Добавить сотрудника</h2>
              <button onClick={() => setShowCreateModal(false)} className={textSecondaryClass}>
                <X size={24} />
              </button>
            </div>

            <form onSubmit={handleCreateUser} className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Логин *</label>
                  <input
                    type="text"
                    required
                    value={formData.username}
                    onChange={(e) => setFormData({ ...formData, username: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Пароль *</label>
                  <input
                    type="password"
                    required
                    value={formData.password}
                    onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>ФИО</label>
                  <input
                    type="text"
                    value={formData.full_name}
                    onChange={(e) => setFormData({ ...formData, full_name: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Email</label>
                  <input
                    type="email"
                    value={formData.email}
                    onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Телефон</label>
                  <input
                    type="tel"
                    value={formData.phone}
                    onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Должность</label>
                  <input
                    type="text"
                    value={formData.position}
                    onChange={(e) => setFormData({ ...formData, position: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Отдел</label>
                  <input
                    type="text"
                    value={formData.department}
                    onChange={(e) => setFormData({ ...formData, department: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Роль *</label>
                  <select
                    required
                    value={formData.role}
                    onChange={(e) => setFormData({ ...formData, role: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  >
                    <option value="engineer">Инженер</option>
                    <option value="operator">Оператор</option>
                    <option value="chief_operator">Шеф-оператор</option>
                    <option value="admin">Администратор</option>
                    <option value="client">Клиент</option>
                  </select>
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>ID инженера</label>
                  <input
                    type="text"
                    value={formData.engineer_id}
                    onChange={(e) => setFormData({ ...formData, engineer_id: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                    placeholder="UUID инженера (опционально)"
                  />
                </div>
                <div className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={formData.is_active}
                    onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                    className="w-4 h-4"
                  />
                  <label className={`text-sm ${textSecondaryClass}`}>Активен</label>
                </div>
              </div>

              <div>
                <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Фото</label>
                <div className="flex items-center gap-4">
                  {photoPreview && (
                    <img src={photoPreview} alt="Preview" className="w-20 h-20 rounded-full object-cover" />
                  )}
                  <label className="flex items-center gap-2 px-4 py-2 bg-app-soft hover:bg-app-softer text-app-text rounded-lg cursor-pointer">
                    <Camera size={20} />
                    <span>Выбрать фото</span>
                    <input
                      type="file"
                      accept="image/*"
                      onChange={handlePhotoChange}
                      className="hidden"
                    />
                  </label>
                </div>
              </div>

              <div className="flex gap-2 justify-end">
                <button
                  type="button"
                  onClick={() => setShowCreateModal(false)}
                  className="px-4 py-2 bg-app-soft hover:bg-app-softer text-app-text rounded-lg"
                >
                  Отмена
                </button>
                <button
                  type="submit"
                  className="flex items-center gap-2 px-4 py-2 bg-accent hover:bg-blue-600 text-white rounded-lg"
                >
                  <Save size={20} />
                  Создать
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Модальное окно редактирования сотрудника */}
      {showEditModal && selectedUser && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className={`${cardBgClass} rounded-xl p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto border ${borderClass}`}>
            <div className="flex justify-between items-center mb-6">
              <h2 className={`text-xl font-bold ${textClass}`}>Редактировать сотрудника</h2>
              <button onClick={() => setShowEditModal(false)} className={textSecondaryClass}>
                <X size={24} />
              </button>
            </div>

            <form onSubmit={handleEditUser} className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Логин</label>
                  <input
                    type="text"
                    value={selectedUser.username}
                    disabled
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textSecondaryClass} opacity-50`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Новый пароль</label>
                  <input
                    type="password"
                    value={formData.password}
                    onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                    placeholder="Оставьте пустым, чтобы не менять"
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>ФИО</label>
                  <input
                    type="text"
                    value={formData.full_name}
                    onChange={(e) => setFormData({ ...formData, full_name: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Email</label>
                  <input
                    type="email"
                    value={formData.email}
                    onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Телефон</label>
                  <input
                    type="tel"
                    value={formData.phone}
                    onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Должность</label>
                  <input
                    type="text"
                    value={formData.position}
                    onChange={(e) => setFormData({ ...formData, position: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Отдел</label>
                  <input
                    type="text"
                    value={formData.department}
                    onChange={(e) => setFormData({ ...formData, department: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Роль</label>
                  <select
                    value={formData.role}
                    onChange={(e) => setFormData({ ...formData, role: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                  >
                    <option value="engineer">Инженер</option>
                    <option value="operator">Оператор</option>
                    <option value="chief_operator">Шеф-оператор</option>
                    <option value="admin">Администратор</option>
                    <option value="client">Клиент</option>
                  </select>
                </div>
                <div>
                  <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>ID инженера</label>
                  <input
                    type="text"
                    value={formData.engineer_id}
                    onChange={(e) => setFormData({ ...formData, engineer_id: e.target.value })}
                    className={`w-full px-3 py-2 ${inputBgClass} border ${borderClass} rounded-lg ${textClass} focus:outline-none focus:border-accent`}
                    placeholder="UUID инженера (опционально)"
                  />
                </div>
                <div className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={formData.is_active}
                    onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                    className="w-4 h-4"
                  />
                  <label className={`text-sm ${textSecondaryClass}`}>Активен</label>
                </div>
              </div>

              <div>
                <label className={`block text-sm font-medium ${textSecondaryClass} mb-1`}>Фото</label>
                <div className="flex items-center gap-4">
                  {photoPreview && (
                    <img src={photoPreview} alt="Preview" className="w-20 h-20 rounded-full object-cover" />
                  )}
                  <label className="flex items-center gap-2 px-4 py-2 bg-app-soft hover:bg-app-softer text-app-text rounded-lg cursor-pointer">
                    <Camera size={20} />
                    <span>Изменить фото</span>
                    <input
                      type="file"
                      accept="image/*"
                      onChange={handlePhotoChange}
                      className="hidden"
                    />
                  </label>
                </div>
              </div>

              <div className="flex gap-2 justify-end">
                <button
                  type="button"
                  onClick={() => setShowEditModal(false)}
                  className="px-4 py-2 bg-app-soft hover:bg-app-softer text-app-text rounded-lg"
                >
                  Отмена
                </button>
                <button
                  type="submit"
                  className="flex items-center gap-2 px-4 py-2 bg-accent hover:bg-blue-600 text-white rounded-lg"
                >
                  <Save size={20} />
                  Сохранить
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

export default UsersManagement;
