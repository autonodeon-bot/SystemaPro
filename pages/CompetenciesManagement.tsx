import React, { useState, useEffect } from 'react';
import { User, Award, Calendar, Plus, AlertTriangle, CheckCircle } from 'lucide-react';

interface Engineer {
  id: string;
  full_name: string;
  position?: string;
  email?: string;
  phone?: string;
  qualifications?: string[];
  certifications?: any[];
  equipment_types?: string[];
}

interface Certification {
  id: string;
  engineer_id: string;
  certification_type: string;
  number: string;
  issued_by: string;
  issue_date?: string;
  expiry_date?: string;
}

const CompetenciesManagement = () => {
  const [engineers, setEngineers] = useState<Engineer[]>([]);
  const [certifications, setCertifications] = useState<Certification[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedEngineer, setSelectedEngineer] = useState<Engineer | null>(null);
  const [showAddForm, setShowAddForm] = useState(false);

  const [formData, setFormData] = useState({
    full_name: '',
    position: '',
    email: '',
    phone: '',
    qualifications: [] as string[],
    equipment_types: [] as string[],
  });

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      const [engRes, certRes] = await Promise.all([
        fetch(`${API_BASE}/api/engineers`),
        fetch(`${API_BASE}/api/certifications`)
      ]);
      
      const engData = await engRes.json();
      const certData = await certRes.json();
      
      setEngineers(engData.items || []);
      setCertifications(certData.items || []);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const response = await fetch(`${API_BASE}/api/engineers`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });

      if (response.ok) {
        setShowAddForm(false);
        setFormData({
          full_name: '',
          position: '',
          email: '',
          phone: '',
          qualifications: [],
          equipment_types: [],
        });
        loadData();
        alert('Инженер успешно добавлен');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось добавить инженера'}`);
      }
    } catch (error) {
      console.error('Ошибка создания инженера:', error);
      alert('Ошибка создания инженера');
    }
  };

  const getEngineerCertifications = (engineerId: string) => {
    return certifications.filter(c => c.engineer_id === engineerId);
  };

  const isCertificationExpiring = (expiryDate?: string) => {
    if (!expiryDate) return false;
    const expiry = new Date(expiryDate);
    const now = new Date();
    const daysUntilExpiry = Math.ceil((expiry.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
    return daysUntilExpiry > 0 && daysUntilExpiry <= 90;
  };

  const isCertificationExpired = (expiryDate?: string) => {
    if (!expiryDate) return false;
    return new Date(expiryDate) < new Date();
  };

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">Управление компетенциями</h1>
        <button
          onClick={() => setShowAddForm(true)}
          className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20"
        >
          <Plus size={16} /> Добавить инженера
        </button>
      </div>

      {/* Форма добавления */}
      {showAddForm && (
        <div className="bg-slate-800 p-6 rounded-xl border border-slate-600">
          <h2 className="text-xl font-bold text-white mb-4">Добавить инженера</h2>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm text-slate-400 block mb-1">ФИО *</label>
                <input
                  type="text"
                  required
                  value={formData.full_name}
                  onChange={(e) => setFormData({ ...formData, full_name: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Должность</label>
                <input
                  type="text"
                  value={formData.position}
                  onChange={(e) => setFormData({ ...formData, position: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Email</label>
                <input
                  type="email"
                  value={formData.email}
                  onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
              <div>
                <label className="text-sm text-slate-400 block mb-1">Телефон</label>
                <input
                  type="tel"
                  value={formData.phone}
                  onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                  className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                />
              </div>
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80"
              >
                Сохранить
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

      {/* Список инженеров */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {engineers.map((engineer) => {
          const engCerts = getEngineerCertifications(engineer.id);
          const hasExpiringCerts = engCerts.some(c => isCertificationExpiring(c.expiry_date));
          const hasExpiredCerts = engCerts.some(c => isCertificationExpired(c.expiry_date));
          
          return (
            <div
              key={engineer.id}
              className={`bg-slate-800 p-4 rounded-xl border transition-colors cursor-pointer ${
                hasExpiredCerts ? 'border-red-500/50' : hasExpiringCerts ? 'border-yellow-500/50' : 'border-slate-700 hover:border-accent/50'
              }`}
              onClick={() => setSelectedEngineer(engineer)}
            >
              <div className="flex items-start gap-3 mb-3">
                <div className="bg-accent/10 p-2 rounded-lg">
                  <User className="text-accent" size={20} />
                </div>
                <div className="flex-1">
                  <h3 className="text-lg font-bold text-white">{engineer.full_name}</h3>
                  {engineer.position && (
                    <p className="text-sm text-slate-400">{engineer.position}</p>
                  )}
                </div>
                {hasExpiredCerts && <AlertTriangle className="text-red-400" size={20} />}
                {hasExpiringCerts && !hasExpiredCerts && <AlertTriangle className="text-yellow-400" size={20} />}
              </div>

              {engineer.qualifications && engineer.qualifications.length > 0 && (
                <div className="mb-2">
                  <p className="text-xs text-slate-400 mb-1">Квалификации:</p>
                  <div className="flex flex-wrap gap-1">
                    {engineer.qualifications.slice(0, 3).map((qual, idx) => (
                      <span key={idx} className="text-xs bg-slate-700 text-slate-300 px-2 py-1 rounded">
                        {qual}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              <div className="flex items-center gap-2 text-sm text-slate-400">
                <Award size={14} />
                <span>Сертификатов: {engCerts.length}</span>
              </div>

              {engineer.equipment_types && engineer.equipment_types.length > 0 && (
                <div className="mt-2">
                  <p className="text-xs text-slate-400 mb-1">Типы оборудования:</p>
                  <div className="flex flex-wrap gap-1">
                    {engineer.equipment_types.slice(0, 2).map((type, idx) => (
                      <span key={idx} className="text-xs bg-accent/10 text-accent px-2 py-1 rounded">
                        {type}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {engineers.length === 0 && (
        <div className="text-center text-slate-400 py-20">
          Инженеры не найдены
        </div>
      )}

      {/* Модальное окно с деталями */}
      {selectedEngineer && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setSelectedEngineer(null)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-3xl w-full mx-4 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-start mb-4">
              <div>
                <h2 className="text-xl font-bold text-white">{selectedEngineer.full_name}</h2>
                {selectedEngineer.position && (
                  <p className="text-slate-400">{selectedEngineer.position}</p>
                )}
              </div>
              <button onClick={() => setSelectedEngineer(null)} className="text-slate-400 hover:text-white">✕</button>
            </div>

            <div className="space-y-4">
              {selectedEngineer.email && (
                <div>
                  <p className="text-sm text-slate-400 mb-1">Email</p>
                  <p className="text-white">{selectedEngineer.email}</p>
                </div>
              )}
              {selectedEngineer.phone && (
                <div>
                  <p className="text-sm text-slate-400 mb-1">Телефон</p>
                  <p className="text-white">{selectedEngineer.phone}</p>
                </div>
              )}

              {selectedEngineer.qualifications && selectedEngineer.qualifications.length > 0 && (
                <div>
                  <p className="text-sm text-slate-400 mb-2">Квалификации</p>
                  <div className="flex flex-wrap gap-2">
                    {selectedEngineer.qualifications.map((qual, idx) => (
                      <span key={idx} className="bg-slate-700 text-slate-300 px-3 py-1 rounded text-sm">
                        {qual}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              <div>
                <p className="text-sm text-slate-400 mb-2">Сертификаты и допуски</p>
                {getEngineerCertifications(selectedEngineer.id).length === 0 ? (
                  <p className="text-slate-400">Сертификаты не найдены</p>
                ) : (
                  <div className="space-y-2">
                    {getEngineerCertifications(selectedEngineer.id).map((cert) => {
                      const isExpired = isCertificationExpired(cert.expiry_date);
                      const isExpiring = isCertificationExpiring(cert.expiry_date);
                      
                      return (
                        <div
                          key={cert.id}
                          className={`bg-slate-900 p-3 rounded-lg border ${
                            isExpired ? 'border-red-500/50' : isExpiring ? 'border-yellow-500/50' : 'border-slate-700'
                          }`}
                        >
                          <div className="flex justify-between items-start">
                            <div>
                              <p className="text-white font-bold">{cert.certification_type}</p>
                              <p className="text-sm text-slate-400">№ {cert.number}</p>
                              <p className="text-sm text-slate-400">Выдан: {cert.issued_by}</p>
                            </div>
                            {isExpired ? (
                              <AlertTriangle className="text-red-400" size={20} />
                            ) : isExpiring ? (
                              <AlertTriangle className="text-yellow-400" size={20} />
                            ) : (
                              <CheckCircle className="text-green-400" size={20} />
                            )}
                          </div>
                          {cert.issue_date && (
                            <p className="text-xs text-slate-500 mt-2">
                              Выдан: {new Date(cert.issue_date).toLocaleDateString('ru-RU')}
                            </p>
                          )}
                          {cert.expiry_date && (
                            <p className={`text-xs mt-1 ${
                              isExpired ? 'text-red-400' : isExpiring ? 'text-yellow-400' : 'text-slate-400'
                            }`}>
                              Действует до: {new Date(cert.expiry_date).toLocaleDateString('ru-RU')}
                              {isExpired && ' (Истек)'}
                              {isExpiring && !isExpired && ' (Истекает скоро)'}
                            </p>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>

              {selectedEngineer.equipment_types && selectedEngineer.equipment_types.length > 0 && (
                <div>
                  <p className="text-sm text-slate-400 mb-2">Типы оборудования</p>
                  <div className="flex flex-wrap gap-2">
                    {selectedEngineer.equipment_types.map((type, idx) => (
                      <span key={idx} className="bg-accent/10 text-accent px-3 py-1 rounded text-sm">
                        {type}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default CompetenciesManagement;



