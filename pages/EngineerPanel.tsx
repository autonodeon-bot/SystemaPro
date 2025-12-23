import React, { useState, useEffect } from 'react';
import { 
  Award, Edit, Plus, Trash2, Download, Calendar, 
  CheckCircle, XCircle, AlertTriangle, FileText, Save, Upload
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

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
  file_path?: string;
}

const EngineerPanel = () => {
  const { user } = useAuth();
  const [certifications, setCertifications] = useState<Certification[]>([]);
  const [loading, setLoading] = useState(true);
  const [editingCert, setEditingCert] = useState<Certification | null>(null);
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

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    if (user?.engineer_id) {
      loadCertifications();
    }
  }, [user]);

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

  return (
    <div className="space-y-6">
      {/* Заголовок */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Award className="text-accent" size={28} />
            Мои сертификаты НК
          </h1>
          <p className="text-slate-400 mt-1">
            Управление вашими сертификатами и допусками
          </p>
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
                    <span>{cert.method || 'Не указан'}</span>
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
                  {cert.file_path && (
                    <a
                      href={`${API_BASE}/api/documents/${cert.id}/download`}
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
    </div>
  );
};

export default EngineerPanel;





















