import React, { useState, useEffect } from 'react';
import { Users, User, Mail, Shield, Search, Edit, Trash2, Plus, X } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

interface UserData {
  id: string;
  username: string;
  email?: string;
  full_name?: string;
  role: string;
  engineer_id?: string;
}

const UsersManagement = () => {
  const { user: currentUser } = useAuth();
  const [users, setUsers] = useState<UserData[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [filterRole, setFilterRole] = useState<string>('all');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [selectedUser, setSelectedUser] = useState<UserData | null>(null);

  const API_BASE = 'http://5.129.203.182:8000';

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
    return colors[role] || 'bg-slate-500/20 text-slate-400 border-slate-500/50';
  };

  const filteredUsers = users.filter(u => {
    const matchesSearch = searchQuery === '' || 
      u.username.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (u.full_name && u.full_name.toLowerCase().includes(searchQuery.toLowerCase())) ||
      (u.email && u.email.toLowerCase().includes(searchQuery.toLowerCase()));
    const matchesRole = filterRole === 'all' || u.role === filterRole;
    return matchesSearch && matchesRole;
  });

  if (currentUser?.role !== 'admin') {
    return (
      <div className="text-center text-slate-400 mt-20">
        <Shield className="mx-auto mb-4" size={48} />
        <p>Доступ запрещен. Только администратор может просматривать список пользователей.</p>
      </div>
    );
  }

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Users className="text-accent" size={32} />
          <h1 className="text-3xl font-bold text-white">Сотрудники</h1>
        </div>
      </div>

      {/* Фильтры */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-4">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
            <input
              type="text"
              placeholder="Поиск по имени, логину, email..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
            />
          </div>
          
          <select
            value={filterRole}
            onChange={(e) => setFilterRole(e.target.value)}
            className="px-4 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-accent"
          >
            <option value="all">Все роли</option>
            <option value="admin">Администратор</option>
            <option value="chief_operator">Шеф-оператор</option>
            <option value="operator">Оператор</option>
            <option value="engineer">Инженер</option>
            <option value="client">Клиент</option>
          </select>
        </div>
      </div>

      {/* Список пользователей */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredUsers.map((user) => (
          <div
            key={user.id}
            className="bg-slate-800 rounded-xl border border-slate-700 p-6 hover:border-accent/50 transition-colors cursor-pointer"
            onClick={() => setSelectedUser(user)}
          >
            <div className="flex items-start justify-between mb-4">
              <div className="flex items-center gap-3">
                <div className="bg-accent/10 p-3 rounded-lg">
                  <User className="text-accent" size={24} />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-white">
                    {user.full_name || user.username}
                  </h3>
                  <p className="text-sm text-slate-400">{user.username}</p>
                </div>
              </div>
            </div>

            <div className="space-y-2">
              {user.email && (
                <div className="flex items-center gap-2 text-sm text-slate-300">
                  <Mail size={14} />
                  <span>{user.email}</span>
                </div>
              )}

              <div className="flex items-center gap-2">
                <Shield size={14} className="text-slate-400" />
                <span className={`px-2 py-1 rounded text-xs font-semibold border ${getRoleColor(user.role)}`}>
                  {getRoleLabel(user.role)}
                </span>
              </div>
            </div>
          </div>
        ))}
      </div>

      {filteredUsers.length === 0 && (
        <div className="text-center text-slate-400 py-20">
          <Users className="mx-auto mb-4 opacity-50" size={48} />
          <p>Пользователи не найдены</p>
        </div>
      )}

      {/* Модальное окно с деталями пользователя */}
      {selectedUser && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setSelectedUser(null)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-md w-full mx-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-start mb-4">
              <div>
                <h2 className="text-xl font-bold text-white">{selectedUser.full_name || selectedUser.username}</h2>
                <p className="text-slate-400">{selectedUser.username}</p>
              </div>
              <button onClick={() => setSelectedUser(null)} className="text-slate-400 hover:text-white">
                <X size={24} />
              </button>
            </div>

            <div className="space-y-4">
              <div>
                <p className="text-sm text-slate-400 mb-1">Email</p>
                <p className="text-white">{selectedUser.email || 'Не указан'}</p>
              </div>

              <div>
                <p className="text-sm text-slate-400 mb-1">Роль</p>
                <span className={`px-3 py-1 rounded text-sm font-semibold border ${getRoleColor(selectedUser.role)}`}>
                  {getRoleLabel(selectedUser.role)}
                </span>
              </div>

              {selectedUser.engineer_id && (
                <div>
                  <p className="text-sm text-slate-400 mb-1">ID инженера</p>
                  <p className="text-white font-mono text-sm">{selectedUser.engineer_id}</p>
                </div>
              )}

              <div>
                <p className="text-sm text-slate-400 mb-1">ID пользователя</p>
                <p className="text-white font-mono text-sm">{selectedUser.id}</p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default UsersManagement;











