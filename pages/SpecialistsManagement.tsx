import React, { useState, useEffect } from 'react';
import { 
  Users, Search, Plus, Edit, Trash2, Eye, Download, 
  Mail, Phone, Award, Briefcase, FileText, Filter,
  CheckCircle, XCircle, Calendar, MapPin, Shield
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

interface Specialist {
  id: string;
  full_name: string;
  position?: string;
  email?: string;
  phone?: string;
  qualifications?: Record<string, any>;
  certifications?: any[];
  equipment_types?: string[];
  is_active: number;
  created_at: string;
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
  file_path?: string;
}

const SpecialistsManagement = () => {
  const { user, hasRole } = useAuth();
  const [specialists, setSpecialists] = useState<Specialist[]>([]);
  const [certifications, setCertifications] = useState<Certification[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [showAddForm, setShowAddForm] = useState(false);
  const [showAddCertForm, setShowAddCertForm] = useState(false);
  const [selectedSpecialist, setSelectedSpecialist] = useState<Specialist | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [certFormData, setCertFormData] = useState({
    engineer_id: '',
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
  
  // Проверка доступа: инженеры не могут управлять специалистами
  const canManageSpecialists = hasRole('admin') || hasRole('chief_operator') || hasRole('operator');

  useEffect(() => {
    loadSpecialists();
    loadCertifications();
  }, []);

  const loadSpecialists = async () => {
    try {
      const response = await fetch(`${API_BASE}/api/engineers`);
      const data = await response.json();
      setSpecialists(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки специалистов:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadCertifications = async () => {
    try {
      const response = await fetch(`${API_BASE}/api/certifications`);
      const data = await response.json();
      setCertifications(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки сертификатов:', error);
    }
  };

  const filteredSpecialists = specialists.filter(spec => {
    const matchesSearch = 
      spec.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      spec.position?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      spec.email?.toLowerCase().includes(searchTerm.toLowerCase());
    return matchesSearch;
  });

  const getSpecialistCertifications = (specialistId: string) => {
    return certifications.filter(cert => cert.engineer_id === specialistId);
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

  const isCertificationExpired = (expiryDate?: string) => {
    if (!expiryDate) return false;
    try {
      return new Date(expiryDate) < new Date();
    } catch {
      return false;
    }
  };

  const isCertificationExpiringSoon = (expiryDate?: string, days: number = 90) => {
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

  const getExpiringCertifications = () => {
    const expiring: Array<{ specialist: Specialist; cert: Certification; daysLeft: number }> = [];
    specialists.forEach(spec => {
      const certs = getSpecialistCertifications(spec.id);
      certs.forEach(cert => {
        if (cert.expiry_date && !isCertificationExpired(cert.expiry_date)) {
          const expiry = new Date(cert.expiry_date);
          const now = new Date();
          const diffTime = expiry.getTime() - now.getTime();
          const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
          if (diffDays > 0 && diffDays <= 90) {
            expiring.push({ specialist: spec, cert, daysLeft: diffDays });
          }
        }
      });
    });
    return expiring.sort((a, b) => a.daysLeft - b.daysLeft);
  };

  const handleAddCertification = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const formData = new FormData();
      formData.append('engineer_id', certFormData.engineer_id);
      formData.append('certification_type', certFormData.certification_type);
      formData.append('method', certFormData.method);
      formData.append('level', certFormData.level);
      formData.append('number', certFormData.number);
      formData.append('issued_by', certFormData.issued_by);
      if (certFormData.issue_date) {
        formData.append('issue_date', certFormData.issue_date);
      }
      if (certFormData.expiry_date) {
        formData.append('expiry_date', certFormData.expiry_date);
      }
      if (certFormData.file) {
        formData.append('file', certFormData.file);
      }

      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/certifications`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`
        },
        body: formData
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.detail || 'Ошибка при создании сертификата');
      }

      await loadCertifications();
      setShowAddCertForm(false);
      setCertFormData({
        engineer_id: '',
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

  // Если пользователь - инженер, показываем сообщение о запрете доступа
  if (!canManageSpecialists) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="text-center">
          <Shield className="mx-auto text-red-400 mb-4" size={48} />
          <h2 className="text-2xl font-bold text-white mb-2">Доступ запрещен</h2>
          <p className="text-slate-400">Управление специалистами доступно только администраторам, главным операторам и операторам</p>
          {user && (
            <p className="text-slate-500 mt-2">Ваша роль: {user.role}</p>
          )}
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
            <Users className="text-accent" size={28} />
            Специалисты неразрушающего контроля
          </h1>
          <p className="text-slate-400 mt-1">
            Управление специалистами, их квалификациями и сертификатами
          </p>
        </div>
        <div className="flex gap-2">
          {canManageSpecialists && (
            <>
              <button
                onClick={() => setShowAddCertForm(true)}
                className="px-4 py-2 bg-green-600 hover:bg-green-700 rounded-lg text-white font-medium flex items-center gap-2 transition-colors"
              >
                <Award size={20} />
                Добавить сертификат
              </button>
              <button
                onClick={() => setShowAddForm(true)}
                className="px-4 py-2 bg-accent hover:bg-accent/80 rounded-lg text-white font-medium flex items-center gap-2 transition-colors"
              >
                <Plus size={20} />
                Добавить специалиста
              </button>
            </>
          )}
        </div>
      </div>

      {/* Предупреждение о истекающих аккредитациях */}
      {getExpiringCertifications().length > 0 && (
        <div className="bg-yellow-500/20 border border-yellow-500/50 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Calendar className="text-yellow-400" size={20} />
            <h3 className="text-yellow-400 font-semibold">Истекающие аккредитации</h3>
          </div>
          <div className="space-y-2">
            {getExpiringCertifications().slice(0, 5).map((item, idx) => (
              <div key={idx} className="text-sm text-slate-300">
                <span className="font-medium text-white">{item.specialist.full_name}</span>
                {' - '}
                <span>{item.cert.method || item.cert.certification_type}</span>
                {' '}
                <span className="text-yellow-400">(уровень {item.cert.level || 'не указан'})</span>
                {' - истекает через '}
                <span className="font-semibold text-yellow-400">{item.daysLeft} дн.</span>
                {' '}
                <span className="text-slate-400">
                  ({formatDate(item.cert.expiry_date)})
                </span>
              </div>
            ))}
            {getExpiringCertifications().length > 5 && (
              <p className="text-xs text-slate-400 mt-2">
                И еще {getExpiringCertifications().length - 5} аккредитаций истекают в ближайшее время
              </p>
            )}
          </div>
        </div>
      )}

      {/* Поиск */}
      <div className="bg-secondary/50 rounded-lg p-4">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={18} />
          <input
            type="text"
            placeholder="Поиск по имени, должности, email..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
          />
        </div>
      </div>

      {/* Список специалистов */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-accent"></div>
          <p className="text-slate-400 mt-4">Загрузка специалистов...</p>
        </div>
      ) : filteredSpecialists.length === 0 ? (
        <div className="text-center py-12 bg-secondary/50 rounded-lg">
          <Users className="mx-auto text-slate-400 mb-4" size={48} />
          <p className="text-slate-400">Специалисты не найдены</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredSpecialists.map((specialist) => {
            const specialistCerts = getSpecialistCertifications(specialist.id);
            const expiredCerts = specialistCerts.filter(cert => 
              isCertificationExpired(cert.expiry_date)
            );

            return (
              <div
                key={specialist.id}
                className="bg-secondary/50 rounded-lg p-6 hover:bg-secondary/70 transition-colors border border-slate-700"
              >
                <div className="flex items-start justify-between mb-4">
                  <div className="flex items-center gap-3">
                    <div className="w-12 h-12 rounded-full bg-accent flex items-center justify-center text-white font-bold">
                      {specialist.full_name[0].toUpperCase()}
                    </div>
                    <div>
                      <h3 className="font-semibold text-white">{specialist.full_name}</h3>
                      {specialist.position && (
                        <p className="text-sm text-slate-400">{specialist.position}</p>
                      )}
                    </div>
                  </div>
                  <span className={`px-2 py-1 rounded text-xs font-medium ${
                    specialist.is_active 
                      ? 'bg-green-500/20 text-green-400' 
                      : 'bg-red-500/20 text-red-400'
                  }`}>
                    {specialist.is_active ? 'Активен' : 'Неактивен'}
                  </span>
                </div>

                <div className="space-y-2 mb-4">
                  {specialist.email && (
                    <div className="flex items-center gap-2 text-sm text-slate-400">
                      <Mail size={14} />
                      <span>{specialist.email}</span>
                    </div>
                  )}
                  {specialist.phone && (
                    <div className="flex items-center gap-2 text-sm text-slate-400">
                      <Phone size={14} />
                      <span>{specialist.phone}</span>
                    </div>
                  )}
                </div>

                {specialist.equipment_types && specialist.equipment_types.length > 0 && (
                  <div className="mb-4">
                    <p className="text-xs text-slate-400 mb-2">Специализация:</p>
                    <div className="flex flex-wrap gap-2">
                      {specialist.equipment_types.slice(0, 3).map((type, idx) => (
                        <span
                          key={idx}
                          className="px-2 py-1 bg-slate-700 rounded text-xs text-slate-300"
                        >
                          {type}
                        </span>
                      ))}
                      {specialist.equipment_types.length > 3 && (
                        <span className="px-2 py-1 bg-slate-700 rounded text-xs text-slate-300">
                          +{specialist.equipment_types.length - 3}
                        </span>
                      )}
                    </div>
                  </div>
                )}

                <div className="flex items-center justify-between pt-4 border-t border-slate-700">
                  <div className="flex items-center gap-4 text-sm">
                    <div className="flex items-center gap-1">
                      <Award size={14} className="text-yellow-400" />
                      <span className="text-slate-400">
                        {specialistCerts.length} серт.
                      </span>
                    </div>
                    {expiredCerts.length > 0 && (
                      <div className="flex items-center gap-1 text-red-400">
                        <XCircle size={14} />
                        <span>{expiredCerts.length} просрочено</span>
                      </div>
                    )}
                  </div>
                  <button
                    onClick={() => {
                      setSelectedSpecialist(specialist);
                      setShowDetails(true);
                    }}
                    className="px-3 py-1.5 bg-slate-700 hover:bg-slate-600 rounded text-sm text-white transition-colors"
                  >
                    <Eye size={16} />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Модальное окно с деталями */}
      {showDetails && selectedSpecialist && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setShowDetails(false)}>
          <div
            className="bg-secondary rounded-lg max-w-4xl w-full max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-secondary border-b border-slate-700 p-6 flex items-center justify-between">
              <h2 className="text-xl font-bold text-white flex items-center gap-2">
                <Users className="text-accent" size={24} />
                {selectedSpecialist.full_name}
              </h2>
              <button
                onClick={() => setShowDetails(false)}
                className="text-slate-400 hover:text-white transition-colors"
              >
                ✕
              </button>
            </div>
            <div className="p-6 space-y-6">
              {/* Основная информация */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Должность</label>
                  <p className="text-white">{selectedSpecialist.position || 'Не указана'}</p>
                </div>
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Email</label>
                  <p className="text-white">{selectedSpecialist.email || 'Не указан'}</p>
                </div>
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Телефон</label>
                  <p className="text-white">{selectedSpecialist.phone || 'Не указан'}</p>
                </div>
                <div>
                  <label className="text-xs text-slate-400 mb-1 block">Статус</label>
                  <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium ${
                    selectedSpecialist.is_active 
                      ? 'bg-green-500/20 text-green-400' 
                      : 'bg-red-500/20 text-red-400'
                  }`}>
                    {selectedSpecialist.is_active ? 'Активен' : 'Неактивен'}
                  </span>
                </div>
              </div>

              {/* Специализация */}
              {selectedSpecialist.equipment_types && selectedSpecialist.equipment_types.length > 0 && (
                <div>
                  <label className="text-xs text-slate-400 mb-2 block">Специализация</label>
                  <div className="flex flex-wrap gap-2">
                    {selectedSpecialist.equipment_types.map((type, idx) => (
                      <span
                        key={idx}
                        className="px-3 py-1 bg-slate-700 rounded text-sm text-slate-300"
                      >
                        {type}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {/* Квалификации */}
              {selectedSpecialist.qualifications && Object.keys(selectedSpecialist.qualifications).length > 0 && (
                <div>
                  <label className="text-xs text-slate-400 mb-2 block">Квалификации</label>
                  <div className="space-y-2">
                    {Object.entries(selectedSpecialist.qualifications).map(([key, value]) => (
                      <div key={key} className="flex justify-between p-2 bg-slate-700/50 rounded">
                        <span className="text-sm text-slate-300">{key}</span>
                        <span className="text-sm text-white">{String(value)}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Сертификаты */}
              <div>
                <label className="text-xs text-slate-400 mb-2 block">Сертификаты</label>
                {getSpecialistCertifications(selectedSpecialist.id).length === 0 ? (
                  <p className="text-slate-400 text-sm">Сертификаты не найдены</p>
                ) : (
                  <div className="space-y-2">
                    {getSpecialistCertifications(selectedSpecialist.id).map((cert) => {
                      const isExpired = isCertificationExpired(cert.expiry_date);
                      return (
                        <div
                          key={cert.id}
                          className={`p-4 rounded-lg border ${
                            isExpired
                              ? 'bg-red-500/10 border-red-500/30'
                              : 'bg-slate-700/50 border-slate-600'
                          }`}
                        >
                          <div className="flex items-start justify-between">
                            <div className="flex-1">
                              <div className="flex items-center gap-2 mb-2">
                                <Award className={isExpired ? 'text-red-400' : 'text-yellow-400'} size={18} />
                                <h4 className="font-medium text-white">
                                  {cert.certification_type} №{cert.number}
                                </h4>
                                {isExpired && (
                                  <span className="px-2 py-0.5 bg-red-500/20 text-red-400 rounded text-xs">
                                    Просрочен
                                  </span>
                                )}
                              </div>
                              <div className="space-y-1 text-sm">
                                {cert.method && (
                                  <p className="text-slate-300">
                                    <span className="font-medium">Метод:</span> {cert.method}
                                  </p>
                                )}
                                {cert.level && (
                                  <p className="text-slate-300">
                                    <span className="font-medium">Уровень:</span> {cert.level}
                                  </p>
                                )}
                                <p className="text-slate-400">
                                  Выдан: {cert.issued_by}
                                </p>
                                {cert.issue_date && (
                                  <p className="text-slate-400">
                                    Дата выдачи: {formatDate(cert.issue_date)}
                                  </p>
                                )}
                                {cert.expiry_date && (
                                  <p className={isExpired ? 'text-red-400' : 'text-slate-400'}>
                                    Действителен до: {formatDate(cert.expiry_date)}
                                  </p>
                                )}
                              </div>
                            </div>
                            {cert.file_path && (
                              <a
                                href={`${API_BASE}/api/documents/${cert.id}/download`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="p-2 text-accent hover:bg-slate-700 rounded transition-colors"
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
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Модальное окно добавления сертификата */}
      {showAddCertForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setShowAddCertForm(false)}>
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
                onClick={() => setShowAddCertForm(false)}
                className="text-slate-400 hover:text-white transition-colors"
              >
                ✕
              </button>
            </div>
            <form onSubmit={handleAddCertification} className="p-6 space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  Специалист <span className="text-red-400">*</span>
                </label>
                <select
                  required
                  value={certFormData.engineer_id}
                  onChange={(e) => setCertFormData({ ...certFormData, engineer_id: e.target.value })}
                  className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white focus:outline-none focus:border-accent"
                >
                  <option value="">Выберите специалиста</option>
                  {specialists.map(spec => (
                    <option key={spec.id} value={spec.id}>{spec.full_name}</option>
                  ))}
                </select>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Метод контроля <span className="text-red-400">*</span>
                  </label>
                  <select
                    required
                    value={certFormData.method}
                    onChange={(e) => setCertFormData({ ...certFormData, method: e.target.value })}
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
                    value={certFormData.level}
                    onChange={(e) => setCertFormData({ ...certFormData, level: e.target.value })}
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
                  value={certFormData.certification_type}
                  onChange={(e) => setCertFormData({ ...certFormData, certification_type: e.target.value })}
                  placeholder="Например: Допуск к диагностике сосудов"
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
                    value={certFormData.number}
                    onChange={(e) => setCertFormData({ ...certFormData, number: e.target.value })}
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
                    value={certFormData.issued_by}
                    onChange={(e) => setCertFormData({ ...certFormData, issued_by: e.target.value })}
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
                    value={certFormData.issue_date}
                    onChange={(e) => setCertFormData({ ...certFormData, issue_date: e.target.value })}
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
                    value={certFormData.expiry_date}
                    onChange={(e) => setCertFormData({ ...certFormData, expiry_date: e.target.value })}
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
                  onChange={(e) => setCertFormData({ ...certFormData, file: e.target.files?.[0] || null })}
                  className="w-full px-4 py-2 bg-primary border border-slate-600 rounded-lg text-white file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-semibold file:bg-accent file:text-white hover:file:bg-accent/80"
                />
                {certFormData.file && (
                  <p className="text-xs text-slate-400 mt-1">Выбран файл: {certFormData.file.name}</p>
                )}
              </div>

              <div className="flex gap-3 pt-4">
                <button
                  type="submit"
                  className="flex-1 px-4 py-2 bg-accent hover:bg-accent/80 rounded-lg text-white font-medium transition-colors"
                >
                  Добавить сертификат
                </button>
                <button
                  type="button"
                  onClick={() => setShowAddCertForm(false)}
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

export default SpecialistsManagement;




