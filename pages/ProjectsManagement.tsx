import React, { useState, useEffect } from 'react';
import { Plus, Calendar, User, DollarSign, Filter, CheckCircle, Clock, XCircle, AlertCircle, BarChart3, TrendingUp, Users, Package, FileText, Activity } from 'lucide-react';
import { API_BASE } from '../constants';

interface Client {
  id: string;
  name: string;
}

interface Project {
  id: string;
  client_id: string;
  name: string;
  description?: string;
  status: string;
  start_date?: string;
  end_date?: string;
  deadline?: string;
  budget?: number;
}

const ProjectsManagement = () => {
  const [projects, setProjects] = useState<Project[]>([]);
  const [clients, setClients] = useState<Client[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddForm, setShowAddForm] = useState(false);
  const [statusFilter, setStatusFilter] = useState<string>('ALL');
  const [selectedProject, setSelectedProject] = useState<Project | null>(null);
  const [projectStatistics, setProjectStatistics] = useState<any>(null);
  const [loadingStats, setLoadingStats] = useState(false);

  const [formData, setFormData] = useState({
    client_id: '',
    name: '',
    description: '',
    status: 'PLANNED',
    start_date: '',
    end_date: '',
    deadline: '',
    budget: '',
  });
  const [showAddClientForm, setShowAddClientForm] = useState(false);
  const [newClientData, setNewClientData] = useState({
    name: '',
    inn: '',
    address: '',
    contact_person: '',
    contact_phone: '',
    contact_email: '',
  });

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const [projectsRes, clientsRes] = await Promise.all([
        fetch(`${API_BASE}/api/projects`, { headers }),
        fetch(`${API_BASE}/api/clients`, { headers })
      ]);
      
      if (!projectsRes.ok || !clientsRes.ok) {
        throw new Error('Ошибка загрузки данных');
      }
      
      const projectsData = await projectsRes.json();
      const clientsData = await clientsRes.json();
      
      setProjects(projectsData.items || []);
      setClients(clientsData.items || []);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
      alert('Ошибка загрузки данных. Проверьте подключение к серверу.');
    } finally {
      setLoading(false);
    }
  };

  const loadProjectStatistics = async (projectId: string) => {
    setLoadingStats(true);
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const response = await fetch(`${API_BASE}/api/projects/${projectId}/statistics`, { headers });
      if (response.ok) {
        const stats = await response.json();
        setProjectStatistics(stats);
      }
    } catch (error) {
      console.error('Ошибка загрузки статистики:', error);
    } finally {
      setLoadingStats(false);
    }
  };

  const handleAddClient = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const token = localStorage.getItem('token');
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      const response = await fetch(`${API_BASE}/api/clients`, {
        method: 'POST',
        headers,
        body: JSON.stringify(newClientData)
      });

      if (response.ok) {
        const result = await response.json();
        setShowAddClientForm(false);
        setNewClientData({
          name: '',
          inn: '',
          address: '',
          contact_person: '',
          contact_phone: '',
          contact_email: '',
        });
        await loadData();
        setFormData({ ...formData, client_id: result.id });
        alert('Клиент успешно создан');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось создать клиента'}`);
      }
    } catch (error) {
      console.error('Ошибка создания клиента:', error);
      alert('Ошибка создания клиента');
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const response = await fetch(`${API_BASE}/api/projects`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });

      if (response.ok) {
        setShowAddForm(false);
        setFormData({
          client_id: '',
          name: '',
          description: '',
          status: 'PLANNED',
          start_date: '',
          end_date: '',
          deadline: '',
          budget: '',
        });
        loadData();
        alert('Проект успешно создан');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось создать проект'}`);
      }
    } catch (error) {
      console.error('Ошибка создания проекта:', error);
      alert('Ошибка создания проекта');
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'COMPLETED':
        return <CheckCircle className="text-green-400" size={20} />;
      case 'IN_PROGRESS':
        return <Clock className="text-blue-400" size={20} />;
      case 'CANCELLED':
        return <XCircle className="text-red-400" size={20} />;
      default:
        return <AlertCircle className="text-yellow-400" size={20} />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'COMPLETED':
        return 'bg-green-500/10 text-green-400 border-green-500/20';
      case 'IN_PROGRESS':
        return 'bg-blue-500/10 text-blue-400 border-blue-500/20';
      case 'CANCELLED':
        return 'bg-red-500/10 text-red-400 border-red-500/20';
      default:
        return 'bg-yellow-500/10 text-yellow-400 border-yellow-500/20';
    }
  };

  const getStatusText = (status: string) => {
    const statusMap: Record<string, string> = {
      'PLANNED': 'Запланирован',
      'IN_PROGRESS': 'В работе',
      'COMPLETED': 'Завершен',
      'CANCELLED': 'Отменен'
    };
    return statusMap[status] || status;
  };

  const getClientName = (clientId: string) => {
    const client = clients.find(c => c.id === clientId);
    return client?.name || 'Неизвестный клиент';
  };

  const filteredProjects = projects.filter(p => 
    statusFilter === 'ALL' || p.status === statusFilter
  );

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">Управление проектами</h1>
        <button
          onClick={() => setShowAddForm(true)}
          className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20"
        >
          <Plus size={16} /> Создать проект
        </button>
      </div>

      {/* Фильтры */}
      <div className="flex gap-2">
        <button
          onClick={() => setStatusFilter('ALL')}
          className={`px-4 py-2 rounded-lg text-sm font-bold ${
            statusFilter === 'ALL' 
              ? 'bg-accent text-white' 
              : 'bg-slate-800 text-slate-400 border border-slate-700'
          }`}
        >
          Все
        </button>
        {['PLANNED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'].map(status => (
          <button
            key={status}
            onClick={() => setStatusFilter(status)}
            className={`px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 ${
              statusFilter === status 
                ? 'bg-accent text-white' 
                : 'bg-slate-800 text-slate-400 border border-slate-700'
            }`}
          >
            {getStatusIcon(status)}
            {getStatusText(status)}
          </button>
        ))}
      </div>

      {/* Форма добавления */}
      {showAddForm && (
        <div className="bg-slate-800 p-6 rounded-xl border border-slate-600">
          <h2 className="text-xl font-bold text-white mb-4">Создать проект</h2>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <div className="flex items-center justify-between mb-1">
                  <label className="text-sm text-slate-400">Клиент *</label>
                  <button
                    type="button"
                    onClick={() => setShowAddClientForm(true)}
                    className="text-xs text-accent hover:underline"
                  >
                    + Добавить клиента
                  </button>
                </div>
                <select
                  required
                  value={formData.client_id}
                  onChange={(e) => setFormData({ ...formData, client_id: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                >
                  <option value="">Выберите клиента</option>
                  {clients.map(client => (
                    <option key={client.id} value={client.id}>{client.name}</option>
                  ))}
                </select>
                {clients.length === 0 && (
                  <p className="text-xs text-yellow-400 mt-1">Клиенты не найдены. Добавьте нового клиента.</p>
                )}
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Название проекта *</label>
                <input
                  type="text"
                  required
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="Например: Диагностика оборудования НГДУ-1"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Статус</label>
                <select
                  value={formData.status}
                  onChange={(e) => setFormData({ ...formData, status: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                >
                  <option value="PLANNED">Запланирован</option>
                  <option value="IN_PROGRESS">В работе</option>
                  <option value="COMPLETED">Завершен</option>
                  <option value="CANCELLED">Отменен</option>
                </select>
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Бюджет</label>
                <input
                  type="number"
                  value={formData.budget}
                  onChange={(e) => setFormData({ ...formData, budget: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  placeholder="0.00"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Дата начала</label>
                <input
                  type="date"
                  value={formData.start_date}
                  onChange={(e) => setFormData({ ...formData, start_date: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Дедлайн</label>
                <input
                  type="date"
                  value={formData.deadline}
                  onChange={(e) => setFormData({ ...formData, deadline: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div className="col-span-2">
                <label className="text-sm text-slate-400 block mb-1">Описание</label>
                <textarea
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  rows={3}
                />
              </div>
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80"
              >
                Создать
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

      {/* Список проектов */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredProjects.map((project) => (
          <div
            key={project.id}
            className="bg-slate-800 p-4 rounded-xl border border-slate-700 hover:border-accent/50 transition-colors cursor-pointer"
            onClick={async () => {
              setSelectedProject(project);
              await loadProjectStatistics(project.id);
            }}
          >
            <div className="flex justify-between items-start mb-2">
              <h3 className="text-lg font-bold text-white">{project.name}</h3>
              <span className={`px-2 py-1 rounded text-xs border ${getStatusColor(project.status)}`}>
                {getStatusText(project.status)}
              </span>
            </div>
            
            <p className="text-sm text-slate-400 mb-3">{getClientName(project.client_id)}</p>
            
            {project.description && (
              <p className="text-sm text-slate-300 mb-3 line-clamp-2">{project.description}</p>
            )}

            <div className="space-y-2 text-sm">
              {project.deadline && (
                <div className="flex items-center gap-2 text-slate-400">
                  <Calendar size={14} />
                  <span>Дедлайн: {new Date(project.deadline).toLocaleDateString('ru-RU')}</span>
                </div>
              )}
              {project.budget && (
                <div className="flex items-center gap-2 text-slate-400">
                  <DollarSign size={14} />
                  <span>Бюджет: {project.budget.toLocaleString('ru-RU')} ₽</span>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      {filteredProjects.length === 0 && (
        <div className="text-center text-slate-400 py-20">
          Проекты не найдены
        </div>
      )}

      {/* Модальное окно добавления клиента */}
      {showAddClientForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowAddClientForm(false)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-2xl w-full mx-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">Добавить клиента</h2>
              <button onClick={() => setShowAddClientForm(false)} className="text-slate-400 hover:text-white">✕</button>
            </div>
            <form onSubmit={handleAddClient} className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="col-span-2">
                  <label className="text-sm text-slate-400 block mb-1">Название *</label>
                  <input
                    type="text"
                    required
                    value={newClientData.name}
                    onChange={(e) => setNewClientData({ ...newClientData, name: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    placeholder="Название организации"
                  />
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">ИНН</label>
                  <input
                    type="text"
                    value={newClientData.inn}
                    onChange={(e) => setNewClientData({ ...newClientData, inn: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    placeholder="ИНН"
                  />
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Контактное лицо</label>
                  <input
                    type="text"
                    value={newClientData.contact_person}
                    onChange={(e) => setNewClientData({ ...newClientData, contact_person: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    placeholder="ФИО"
                  />
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Телефон</label>
                  <input
                    type="text"
                    value={newClientData.contact_phone}
                    onChange={(e) => setNewClientData({ ...newClientData, contact_phone: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    placeholder="+7 (XXX) XXX-XX-XX"
                  />
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Email</label>
                  <input
                    type="email"
                    value={newClientData.contact_email}
                    onChange={(e) => setNewClientData({ ...newClientData, contact_email: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    placeholder="email@example.com"
                  />
                </div>
                <div className="col-span-2">
                  <label className="text-sm text-slate-400 block mb-1">Адрес</label>
                  <textarea
                    value={newClientData.address}
                    onChange={(e) => setNewClientData({ ...newClientData, address: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    rows={2}
                    placeholder="Адрес организации"
                  />
                </div>
              </div>
              <div className="flex gap-2">
                <button
                  type="submit"
                  className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80"
                >
                  Создать
                </button>
                <button
                  type="button"
                  onClick={() => setShowAddClientForm(false)}
                  className="bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
                >
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Модальное окно просмотра проекта */}
      {selectedProject && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-slate-800 rounded-xl p-6 max-w-6xl w-full max-h-[90vh] overflow-y-auto border border-slate-700">
            <div className="flex justify-between items-center mb-6">
              <h2 className="text-2xl font-bold text-white">{selectedProject.name}</h2>
              <button 
                onClick={() => {
                  setSelectedProject(null);
                  setProjectStatistics(null);
                }} 
                className="text-slate-400 hover:text-white text-2xl"
              >
                ✕
              </button>
            </div>
            
            {/* Основная информация */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
              <div>
                <p className="text-sm text-slate-400 mb-1">Клиент</p>
                <p className="text-white font-semibold">{getClientName(selectedProject.client_id)}</p>
              </div>
              
              <div>
                <p className="text-sm text-slate-400 mb-1">Статус</p>
                <span className={`px-3 py-1 rounded text-sm border inline-block ${getStatusColor(selectedProject.status)}`}>
                  {getStatusText(selectedProject.status)}
                </span>
              </div>
              
              {selectedProject.start_date && (
                <div>
                  <p className="text-sm text-slate-400 mb-1">Дата начала</p>
                  <p className="text-white">{new Date(selectedProject.start_date).toLocaleDateString('ru-RU')}</p>
                </div>
              )}
              
              {selectedProject.deadline && (
                <div>
                  <p className="text-sm text-slate-400 mb-1">Дедлайн</p>
                  <p className="text-white font-semibold">{new Date(selectedProject.deadline).toLocaleDateString('ru-RU')}</p>
                </div>
              )}
              
              {selectedProject.budget && (
                <div>
                  <p className="text-sm text-slate-400 mb-1">Бюджет</p>
                  <p className="text-white font-semibold text-lg">{selectedProject.budget.toLocaleString('ru-RU')} ₽</p>
                </div>
              )}
              
              {selectedProject.description && (
                <div className="md:col-span-2">
                  <p className="text-sm text-slate-400 mb-1">Описание</p>
                  <p className="text-white">{selectedProject.description}</p>
                </div>
              )}
            </div>

            {/* Статистика проекта */}
            {loadingStats ? (
              <div className="text-center py-8 text-slate-400">Загрузка статистики...</div>
            ) : projectStatistics ? (
              <div className="space-y-6">
                {/* Прогресс выполнения */}
                <div className="bg-slate-900 rounded-lg p-6 border border-slate-700">
                  <h3 className="text-lg font-bold text-white mb-4 flex items-center gap-2">
                    <BarChart3 size={20} />
                    Прогресс выполнения
                  </h3>
                  
                  <div className="mb-4">
                    <div className="flex justify-between items-center mb-2">
                      <span className="text-sm text-slate-400">Выполнено</span>
                      <span className="text-lg font-bold text-white">{projectStatistics.progress_percent.toFixed(1)}%</span>
                    </div>
                    <div className="w-full bg-slate-700 rounded-full h-4 overflow-hidden">
                      <div 
                        className="bg-gradient-to-r from-blue-500 to-green-500 h-full transition-all duration-500"
                        style={{ width: `${projectStatistics.progress_percent}%` }}
                      />
                    </div>
                  </div>
                  
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-4">
                    <div className="bg-slate-800 rounded-lg p-4 border border-slate-700">
                      <div className="flex items-center gap-2 mb-2">
                        <Package size={18} className="text-blue-400" />
                        <span className="text-sm text-slate-400">Всего оборудования</span>
                      </div>
                      <p className="text-2xl font-bold text-white">{projectStatistics.total_equipment}</p>
                    </div>
                    
                    <div className="bg-slate-800 rounded-lg p-4 border border-green-500/30">
                      <div className="flex items-center gap-2 mb-2">
                        <CheckCircle size={18} className="text-green-400" />
                        <span className="text-sm text-slate-400">Выполнено</span>
                      </div>
                      <p className="text-2xl font-bold text-green-400">{projectStatistics.completed_equipment}</p>
                    </div>
                    
                    <div className="bg-slate-800 rounded-lg p-4 border border-yellow-500/30">
                      <div className="flex items-center gap-2 mb-2">
                        <Clock size={18} className="text-yellow-400" />
                        <span className="text-sm text-slate-400">В работе</span>
                      </div>
                      <p className="text-2xl font-bold text-yellow-400">{projectStatistics.in_progress_equipment}</p>
                    </div>
                    
                    <div className="bg-slate-800 rounded-lg p-4 border border-slate-700">
                      <div className="flex items-center gap-2 mb-2">
                        <AlertCircle size={18} className="text-slate-400" />
                        <span className="text-sm text-slate-400">Ожидает</span>
                      </div>
                      <p className="text-2xl font-bold text-white">{projectStatistics.pending_equipment}</p>
                    </div>
                  </div>
                </div>

                {/* Скорость работы и прогноз */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="bg-slate-900 rounded-lg p-6 border border-slate-700">
                    <h3 className="text-lg font-bold text-white mb-4 flex items-center gap-2">
                      <TrendingUp size={20} />
                      Скорость работы
                    </h3>
                    <div className="space-y-3">
                      <div>
                        <p className="text-sm text-slate-400 mb-1">Оборудования в день</p>
                        <p className="text-3xl font-bold text-blue-400">{projectStatistics.speed_per_day.toFixed(2)}</p>
                      </div>
                      {projectStatistics.estimated_completion_date && (
                        <div>
                          <p className="text-sm text-slate-400 mb-1">Прогноз завершения</p>
                          <p className="text-xl font-semibold text-white">
                            {new Date(projectStatistics.estimated_completion_date).toLocaleDateString('ru-RU')}
                          </p>
                        </div>
                      )}
                    </div>
                  </div>
                  
                  <div className="bg-slate-900 rounded-lg p-6 border border-slate-700">
                    <h3 className="text-lg font-bold text-white mb-4 flex items-center gap-2">
                      <FileText size={20} />
                      Отчеты и обследования
                    </h3>
                    <div className="space-y-3">
                      <div>
                        <p className="text-sm text-slate-400 mb-1">Всего обследований</p>
                        <p className="text-3xl font-bold text-purple-400">{projectStatistics.inspections_count}</p>
                      </div>
                      <div>
                        <p className="text-sm text-slate-400 mb-1">Сгенерировано отчетов</p>
                        <p className="text-3xl font-bold text-green-400">{projectStatistics.reports_count}</p>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Статистика по инженерам */}
                {projectStatistics.engineers && projectStatistics.engineers.length > 0 && (
                  <div className="bg-slate-900 rounded-lg p-6 border border-slate-700">
                    <h3 className="text-lg font-bold text-white mb-4 flex items-center gap-2">
                      <Users size={20} />
                      Работа инженеров
                    </h3>
                    <div className="space-y-3">
                      {projectStatistics.engineers.map((eng: any) => {
                        const engProgress = eng.total > 0 ? (eng.completed / eng.total * 100) : 0;
                        return (
                          <div key={eng.engineer_id} className="bg-slate-800 rounded-lg p-4 border border-slate-700">
                            <div className="flex justify-between items-center mb-2">
                              <span className="font-semibold text-white">{eng.engineer_name}</span>
                              <span className="text-sm text-slate-400">
                                {eng.completed} / {eng.total}
                              </span>
                            </div>
                            <div className="w-full bg-slate-700 rounded-full h-2 overflow-hidden">
                              <div 
                                className="bg-gradient-to-r from-blue-500 to-green-500 h-full transition-all duration-500"
                                style={{ width: `${engProgress}%` }}
                              />
                            </div>
                            <div className="flex gap-4 mt-2 text-xs text-slate-400">
                              <span>Выполнено: {eng.completed}</span>
                              <span>В работе: {eng.in_progress}</span>
                              <span>Ожидает: {eng.total - eng.completed - eng.in_progress}</span>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}

                {/* Временная шкала (Gantt-like) */}
                {selectedProject.start_date && selectedProject.deadline && (
                  <div className="bg-slate-900 rounded-lg p-6 border border-slate-700">
                    <h3 className="text-lg font-bold text-white mb-4 flex items-center gap-2">
                      <Calendar size={20} />
                      Временная шкала проекта
                    </h3>
                    <div className="relative">
                      <div className="flex items-center gap-4 mb-4">
                        <div className="flex-1">
                          <div className="text-sm text-slate-400 mb-1">Начало</div>
                          <div className="text-white font-semibold">
                            {new Date(selectedProject.start_date).toLocaleDateString('ru-RU')}
                          </div>
                        </div>
                        <div className="flex-1">
                          <div className="text-sm text-slate-400 mb-1">Дедлайн</div>
                          <div className="text-white font-semibold">
                            {new Date(selectedProject.deadline).toLocaleDateString('ru-RU')}
                          </div>
                        </div>
                        <div className="flex-1">
                          <div className="text-sm text-slate-400 mb-1">Текущая дата</div>
                          <div className="text-white font-semibold">
                            {new Date().toLocaleDateString('ru-RU')}
                          </div>
                        </div>
                      </div>
                      
                      {/* Упрощенная временная шкала */}
                      <div className="relative h-8 bg-slate-700 rounded-full overflow-hidden">
                        <div 
                          className="absolute left-0 top-0 h-full bg-gradient-to-r from-blue-500 to-green-500 transition-all duration-500"
                          style={{ 
                            width: `${projectStatistics.progress_percent}%` 
                          }}
                        />
                        <div 
                          className="absolute top-0 h-full w-1 bg-red-500"
                          style={{ 
                            left: `${((new Date().getTime() - new Date(selectedProject.start_date).getTime()) / 
                                    (new Date(selectedProject.deadline).getTime() - new Date(selectedProject.start_date).getTime())) * 100}%` 
                          }}
                        />
                      </div>
                    </div>
                  </div>
                )}
              </div>
            ) : (
              <div className="text-center py-8 text-slate-400">Статистика недоступна</div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default ProjectsManagement;



