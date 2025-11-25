import React, { useState, useEffect } from 'react';
import { Plus, Calendar, User, DollarSign, Filter, CheckCircle, Clock, XCircle, AlertCircle } from 'lucide-react';

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

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      const [projectsRes, clientsRes] = await Promise.all([
        fetch(`${API_BASE}/api/projects`),
        fetch(`${API_BASE}/api/clients`)
      ]);
      
      const projectsData = await projectsRes.json();
      const clientsData = await clientsRes.json();
      
      setProjects(projectsData.items || []);
      setClients(clientsData.items || []);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
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
                <label className="text-sm text-slate-400 block mb-1">Клиент *</label>
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
            onClick={() => setSelectedProject(project)}
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

      {/* Модальное окно с деталями проекта */}
      {selectedProject && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setSelectedProject(null)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-2xl w-full mx-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">{selectedProject.name}</h2>
              <button onClick={() => setSelectedProject(null)} className="text-slate-400 hover:text-white">✕</button>
            </div>
            
            <div className="space-y-4">
              <div>
                <p className="text-sm text-slate-400 mb-1">Клиент</p>
                <p className="text-white">{getClientName(selectedProject.client_id)}</p>
              </div>
              
              {selectedProject.description && (
                <div>
                  <p className="text-sm text-slate-400 mb-1">Описание</p>
                  <p className="text-white">{selectedProject.description}</p>
                </div>
              )}
              
              <div className="grid grid-cols-2 gap-4">
                {selectedProject.start_date && (
                  <div>
                    <p className="text-sm text-slate-400 mb-1">Дата начала</p>
                    <p className="text-white">{new Date(selectedProject.start_date).toLocaleDateString('ru-RU')}</p>
                  </div>
                )}
                {selectedProject.deadline && (
                  <div>
                    <p className="text-sm text-slate-400 mb-1">Дедлайн</p>
                    <p className="text-white">{new Date(selectedProject.deadline).toLocaleDateString('ru-RU')}</p>
                  </div>
                )}
                {selectedProject.budget && (
                  <div>
                    <p className="text-sm text-slate-400 mb-1">Бюджет</p>
                    <p className="text-white">{selectedProject.budget.toLocaleString('ru-RU')} ₽</p>
                  </div>
                )}
                <div>
                  <p className="text-sm text-slate-400 mb-1">Статус</p>
                  <span className={`px-2 py-1 rounded text-xs border inline-block ${getStatusColor(selectedProject.status)}`}>
                    {getStatusText(selectedProject.status)}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ProjectsManagement;



