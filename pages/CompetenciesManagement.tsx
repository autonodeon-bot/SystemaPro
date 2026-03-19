import React, { useState, useEffect, useMemo } from 'react';
import { User, Award, Calendar, Plus, AlertTriangle, CheckCircle, Edit, Trash2, X, FileText, Clock } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { API_BASE } from '../constants';

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
  certificate_number?: string;
  number?: string;
  method_code?: string;
  certification_area?: string | null;
  certification_areas?: string[] | null;
  equipment_type_id?: string;
  issued_by?: string;
  issuing_organization?: string;
  issue_date?: string;
  expiry_date?: string;
  document_number?: string;
  document_date?: string;
  scan_file_name?: string | null;
  scan_file_size?: number | null;
  scan_mime_type?: string | null;
}

const CompetenciesManagement = () => {
  const { user: currentUser, getToken } = useAuth();
  const [engineers, setEngineers] = useState<Engineer[]>([]);
  const [certifications, setCertifications] = useState<Certification[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedEngineer, setSelectedEngineer] = useState<Engineer | null>(null);
  const [showAddForm, setShowAddForm] = useState(false);
  const [showCertForm, setShowCertForm] = useState(false);
  const [editingCert, setEditingCert] = useState<Certification | null>(null);
  const [certScanFile, setCertScanFile] = useState<File | null>(null);
  const [certFormData, setCertFormData] = useState({
    engineer_id: '',
    certification_type: '',
    certificate_number: '',
    method_code: '',
    certification_areas: [] as string[],
    equipment_type_id: '',
    issue_date: '',
    expiry_date: '',
    issuing_organization: '',
    document_number: '',
    document_date: '',
  });
  
  const [ndtMethods, setNdtMethods] = useState<Array<{code: string, name: string}>>([]);
  const [equipmentTypes, setEquipmentTypes] = useState<Array<{id: string, name: string}>>([]);

  const [formData, setFormData] = useState({
    full_name: '',
    position: '',
    email: '',
    phone: '',
    qualifications: [] as string[],
    equipment_types: [] as string[],
  });

  const downloadCertScan = async (cert: Certification) => {
    try {
      const token = getToken();
      if (!token) {
        alert('Сессия истекла. Необходимо войти снова.');
        window.location.href = '/#/login';
        return;
      }
      const res = await fetch(`${API_BASE}/api/certifications/${cert.id}/scan`, {
        headers: { 'Authorization': `Bearer ${token}` },
      });
      if (!res.ok) {
        const t = await res.text();
        alert(`Не удалось скачать скан: ${t}`);
        return;
      }
      const blob = await res.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = (cert.scan_file_name || 'certificate-scan');
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
    } catch (e) {
      alert(`Ошибка скачивания: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  useEffect(() => {
    loadData();
    loadNdtMethods();
    loadEquipmentTypes();
  }, []);
  
  const loadNdtMethods = async () => {
    const methods = [
      { code: 'ВИК', name: 'Визуальный и измерительный контроль' },
      { code: 'УЗК', name: 'Ультразвуковой контроль' },
      { code: 'РК', name: 'Радиографический контроль' },
      { code: 'МПД', name: 'Магнитопорошковая дефектоскопия' },
      { code: 'КПД', name: 'Капиллярная дефектоскопия' },
      { code: 'ПВК', name: 'Пневматический контроль' },
      { code: 'АК', name: 'Акустико-эмиссионный контроль' },
      { code: 'ТК', name: 'Тепловой контроль' },
      { code: 'УЗТ', name: 'Ультразвуковая толщинометрия' },
      { code: 'ВТК', name: 'Вихретоковый контроль' },
      { code: 'ТВИ', name: 'Тепловизионный контроль' },
      { code: 'ОЭ', name: 'Оптико-эмиссионная спектрометрия' },
      { code: 'МК', name: 'Магнитный контроль' },
    ];
    setNdtMethods(methods);
  };
  
  const loadEquipmentTypes = async () => {
    try {
      const token = getToken();
      if (!token) return;
      
      const headers: HeadersInit = {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      };
      
      const response = await fetch(`${API_BASE}/api/equipment-types`, { headers });
      if (response.ok) {
        const data = await response.json();
        setEquipmentTypes(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки типов оборудования:', error);
    }
  };

  const loadData = async () => {
    setLoading(true);
    try {
      const token = getToken();
      if (!token) {
        console.error('Токен авторизации не найден');
        alert('Необходимо авторизоваться. Перенаправление на страницу входа...');
        window.location.href = '/#/login';
        return;
      }
      
      const headers: HeadersInit = {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      };
      
      console.log('Загрузка компетенций...', { API_BASE });
      
      const [engRes, certRes] = await Promise.all([
        fetch(`${API_BASE}/api/engineers`, { headers }),
        fetch(`${API_BASE}/api/certifications`, { headers })
      ]);
      
      console.log('Ответы сервера:', {
        engineers: { status: engRes.status, ok: engRes.ok },
        certifications: { status: certRes.status, ok: certRes.ok }
      });
      
      if (!engRes.ok) {
        const errorText = await engRes.text();
        console.error('Ошибка загрузки инженеров:', engRes.status, engRes.statusText, errorText);
        if (engRes.status === 401) {
          localStorage.removeItem('token');
          alert('Сессия истекла. Необходимо войти снова.');
          window.location.href = '/#/login';
          return;
        }
        throw new Error(`Failed to load engineers: ${engRes.status} ${engRes.statusText} - ${errorText}`);
      }
      
      if (!certRes.ok) {
        const errorText = await certRes.text();
        console.error('Ошибка загрузки сертификатов:', certRes.status, certRes.statusText, errorText);
        if (certRes.status === 401) {
          localStorage.removeItem('token');
          alert('Сессия истекла. Необходимо войти снова.');
          window.location.href = '/#/login';
          return;
        }
        throw new Error(`Failed to load certifications: ${certRes.status} ${certRes.statusText} - ${errorText}`);
      }
      
      const engData = await engRes.json();
      const certData = await certRes.json();
      
      console.log('Загружены данные (raw):', { engineers: engData, certifications: certData });
      
      // Валидация и очистка данных
      const engineersList = Array.isArray(engData?.items) ? engData.items : [];
      const certificationsList = Array.isArray(certData?.items) ? certData.items : [];
      
      // Фильтруем некорректные записи
      const validEngineers = engineersList.filter(e => e && e.id);
      const validCertifications = certificationsList.filter(c => c && c.id && c.engineer_id);
      
      console.log('Валидированные данные:', {
        engineers: validEngineers.length,
        certifications: validCertifications.length
      });
      
      setEngineers(validEngineers);
      setCertifications(validCertifications);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
      setEngineers([]);
      setCertifications([]);
      alert(`Ошибка загрузки данных: ${error instanceof Error ? error.message : String(error)}`);
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
    if (!engineerId || !certifications || !Array.isArray(certifications)) return [];
    return certifications.filter(c => c && c.engineer_id === engineerId);
  };

  const handleAddCertification = (engineerId: string) => {
    setCertFormData({
      engineer_id: engineerId,
      certification_type: '',
      certificate_number: '',
      method_code: '',
      certification_areas: [],
      equipment_type_id: '',
      issue_date: '',
      expiry_date: '',
      issuing_organization: '',
      document_number: '',
      document_date: '',
    });
    setEditingCert(null);
    setCertScanFile(null);
    setShowCertForm(true);
  };

  const handleEditCertification = (cert: Certification) => {
    const areasRaw = cert.certification_areas?.length
      ? cert.certification_areas
      : (cert.certification_area ? [cert.certification_area] : []);
    const areas = areasRaw.map((a) => (typeof a === 'string' ? a : toDisplayStr(a))).filter(Boolean);
    setCertFormData({
      engineer_id: cert.engineer_id,
      certification_type: cert.certification_type || '',
      certificate_number: cert.certificate_number || cert.number || '',
      method_code: (cert as any).method_code || '',
      certification_areas: areas,
      equipment_type_id: (cert as any).equipment_type_id || '',
      issue_date: cert.issue_date ? cert.issue_date.split('T')[0] : '',
      expiry_date: cert.expiry_date ? cert.expiry_date.split('T')[0] : '',
      issuing_organization: cert.issuing_organization || cert.issued_by || '',
      document_number: cert.document_number || '',
      document_date: cert.document_date ? cert.document_date.split('T')[0] : '',
    });
    setEditingCert(cert);
    setCertScanFile(null);
    setShowCertForm(true);
  };

  const handleDeleteCertification = async (certId: string) => {
    if (!confirm('Вы уверены, что хотите удалить этот сертификат?')) return;
    
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/certifications/${certId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      if (response.ok) {
        loadData();
        alert('Сертификат успешно удален');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось удалить сертификат'}`);
      }
    } catch (error) {
      console.error('Ошибка удаления сертификата:', error);
      alert('Ошибка удаления сертификата');
    }
  };

  const handleCertSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const token = getToken();
      if (!token) {
        alert('Сессия истекла. Необходимо войти снова.');
        window.location.href = '/#/login';
        return;
      }
      const url = editingCert 
        ? `${API_BASE}/api/certifications/${editingCert.id}`
        : `${API_BASE}/api/certifications`;
      
      const method = editingCert ? 'PUT' : 'POST';
      
      const response = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify(certFormData)
      });

      if (response.ok) {
        const saved = await response.json().catch(() => null);
        const certId = (editingCert?.id || saved?.id) as string | undefined;

        // Если выбран файл скана — загружаем после сохранения сертификата
        if (certId && certScanFile) {
          const fd = new FormData();
          fd.append('file', certScanFile);
          const upRes = await fetch(`${API_BASE}/api/certifications/${certId}/scan`, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${token}`,
            },
            body: fd,
          });
          if (!upRes.ok) {
            const errTxt = await upRes.text();
            alert(`Сертификат сохранен, но скан не загружен: ${errTxt}`);
          }
        }

        setShowCertForm(false);
        setEditingCert(null);
        setCertScanFile(null);
        loadData();
        alert(editingCert ? 'Сертификат успешно обновлен' : 'Сертификат успешно создан');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось сохранить сертификат'}`);
      }
    } catch (error) {
      console.error('Ошибка сохранения сертификата:', error);
      alert('Ошибка сохранения сертификата');
    }
  };

  // Вспомогательные функции для проверки статуса сертификатов
  const checkIsExpired = (expiryDate?: string | null): boolean => {
    if (!expiryDate) return false;
    try {
      const expiry = new Date(expiryDate);
      if (isNaN(expiry.getTime())) return false;
      return expiry < new Date();
    } catch (e) {
      return false;
    }
  };

  const checkIsExpiring = (expiryDate?: string | null): boolean => {
    if (!expiryDate) return false;
    try {
      const expiry = new Date(expiryDate);
      const now = new Date();
      if (isNaN(expiry.getTime())) return false;
      const daysUntilExpiry = Math.ceil((expiry.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
      return daysUntilExpiry > 0 && daysUntilExpiry <= 90;
    } catch (e) {
      return false;
    }
  };

  const isCertificationExpiring = (expiryDate?: string | null) => checkIsExpiring(expiryDate);
  const isCertificationExpired = (expiryDate?: string | null) => checkIsExpired(expiryDate);

  const getDaysUntilExpiry = (expiryDate?: string | null) => {
    if (!expiryDate) return null;
    try {
      const expiry = new Date(expiryDate);
      const now = new Date();
      const daysUntilExpiry = Math.ceil((expiry.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
      return daysUntilExpiry;
    } catch (e) {
      return null;
    }
  };

  const formatDateRu = (dateStr?: string | null): string => {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleDateString('ru-RU');
  };

  /** Безопасное преобразование в строку для рендера (API может вернуть объект в qualifications) */
  const toDisplayStr = (v: unknown): string => {
    if (v == null) return '';
    if (typeof v === 'string') return v;
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (Array.isArray(v)) return v.map(toDisplayStr).filter(Boolean).join('; ');
    if (typeof v === 'object') {
      const o = v as Record<string, unknown>;
      return (o.certification_type as string) || (o.method_code as string) || (o.method as string) || (o.name as string) || '';
    }
    return String(v);
  };

  // Вычисляем статистику сертификатов с помощью useMemo для гарантии определения переменных
  // Важно: вычисляем ДО проверки loading, чтобы переменные всегда были определены
  const statistics = useMemo(() => {
    if (!certifications || !Array.isArray(certifications) || certifications.length === 0) {
      return { validCount: 0, expiringSoonCount: 0, expiredCount: 0 };
    }

    let valid = 0;
    let expiring = 0;
    let expired = 0;

    for (const c of certifications) {
      if (!c) continue;
      
      try {
        if (c.expiry_date) {
          const isExpired = checkIsExpired(c.expiry_date);
          const isExpiring = checkIsExpiring(c.expiry_date);
          
          if (isExpired) {
            expired++;
          } else if (isExpiring) {
            expiring++;
          } else {
            valid++;
          }
        }
      } catch (e) {
        // Игнорируем ошибки при обработке отдельных сертификатов
        continue;
      }
    }

    return { validCount: valid, expiringSoonCount: expiring, expiredCount: expired };
  }, [certifications]);

  // Деструктурируем после useMemo с дефолтными значениями
  const { validCount = 0, expiringSoonCount = 0, expiredCount = 0 } = statistics;

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  const CERTIFICATION_TYPES = [
    "Ультразвуковая дефектоскопия (УЗК)",
    "Радиографический контроль (РК)",
    "Магнитопорошковая дефектоскопия (МПД)",
    "Капиллярная дефектоскопия (ПВК)",
    "Визуальный и измерительный контроль (ВИК)",
    "Вихретоковый контроль (ВТК)",
    "Толщинометрия",
    "Акустико-эмиссионный контроль (АЭК)",
    "Тепловой контроль (ТК)",
    "Ультразвуковая толщинометрия (УЗТ)"
  ];

  // Области аттестации специалистов НК (по приказам Ростехнадзора и ГОСТ Р ИСО 9712)
  const CERTIFICATION_AREAS = [
    "А.1 — Основные требования промышленной безопасности",
    "Б.3.1 — Оборудование металлургической промышленности (доменное)",
    "Б.3.2 — Оборудование металлургической промышленности (сталеплавильное)",
    "Б.3.3 — Оборудование металлургической промышленности (прокатное)",
    "Б.3.4 — Оборудование металлургической промышленности (трубное производство)",
    "Б.3.5 — Оборудование металлургической промышленности (коксохимическое)",
    "Б.3.6 — Оборудование металлургической промышленности (агломерационное)",
    "Б.3.7 — Оборудование металлургической промышленности (литейное)",
    "Б.3.8 — Оборудование металлургической промышленности (вспомогательное)",
    "Б.3.9 — Оборудование металлургической промышленности (прочее)",
    "Б.3.10 — Требования к порядку работы на объектах металлургической промышленности",
    "Б.4.1 — Сосуды, работающие под давлением",
    "Б.4.2 — Трубопроводы пара и горячей воды",
    "Б.4.3 — Котлы (паровые и водогрейные)",
    "Б.4.4 — Оборудование, работающее под избыточным давлением",
    "Б.7.1 — Гидротехнические сооружения (общие требования)",
    "Б.7.2 — Гидротехнические сооружения водохранилищ",
    "Б.7.3 — Гидротехнические сооружения намывных площадок",
    "Б.7.4 — Гидротехнические сооружения водоподпорные",
    "Б.7.5 — Гидротехнические сооружения каналов",
    "Б.7.6 — Гидротехнические сооружения (прочие)",
    "Сварные соединения (ГОСТ Р ИСО 9712)",
    "Литые изделия (ГОСТ Р ИСО 9712)",
    "Кованые изделия и штамповки (ГОСТ Р ИСО 9712)",
    "Трубопроводы (ГОСТ Р ИСО 9712)",
    "Металлические конструкции (ГОСТ Р ИСО 9712)",
    "Строительные конструкции (ГОСТ Р ИСО 9712)",
    "Оборудование нефтегазовой отрасли",
  ];

  // Группы областей для быстрого выбора «вся область»
  const AREA_GROUPS: { label: string; areas: string[] }[] = [
    { label: "А.1 — Основы промышленной безопасности", areas: [CERTIFICATION_AREAS[0]] },
    { label: "Вся область Б.3 (металлургия)", areas: CERTIFICATION_AREAS.slice(1, 11) },
    { label: "Вся область Б.4 (сосуды, котлы)", areas: CERTIFICATION_AREAS.slice(11, 15) },
    { label: "Вся область Б.7 (гидротехнические сооружения)", areas: CERTIFICATION_AREAS.slice(15, 21) },
    { label: "ГОСТ Р ИСО 9712 (объекты контроля)", areas: CERTIFICATION_AREAS.slice(21, 28) },
  ];

  const toggleCertificationArea = (area: string) => {
    const cur = certFormData.certification_areas;
    if (cur.includes(area)) {
      setCertFormData({ ...certFormData, certification_areas: cur.filter((a) => a !== area) });
    } else {
      setCertFormData({ ...certFormData, certification_areas: [...cur, area] });
    }
  };

  const addAreaGroup = (areas: string[]) => {
    const cur = certFormData.certification_areas;
    const next = [...new Set([...cur, ...areas])];
    setCertFormData({ ...certFormData, certification_areas: next });
  };

  const removeAreaGroup = (areas: string[]) => {
    const setB = new Set(areas);
    setCertFormData({
      ...certFormData,
      certification_areas: certFormData.certification_areas.filter((a) => !setB.has(a)),
    });
  };

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

      {/* Статистика по сертификатам */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="bg-slate-800 rounded-xl border border-slate-700 p-4">
          <div className="flex items-center gap-3">
            <FileText className="text-blue-400" size={24} />
            <div>
              <p className="text-slate-400 text-sm">Всего сертификатов</p>
              <p className="text-white text-2xl font-bold">{certifications.length}</p>
            </div>
          </div>
        </div>
        <div className="bg-slate-800 rounded-xl border border-green-500/50 p-4">
          <div className="flex items-center gap-3">
            <CheckCircle className="text-green-400" size={24} />
            <div>
              <p className="text-slate-400 text-sm">Действительных</p>
              <p className="text-white text-2xl font-bold">{validCount}</p>
            </div>
          </div>
        </div>
        <div className="bg-slate-800 rounded-xl border border-yellow-500/50 p-4">
          <div className="flex items-center gap-3">
            <Clock className="text-yellow-400" size={24} />
            <div>
              <p className="text-slate-400 text-sm">Истекающих скоро</p>
              <p className="text-white text-2xl font-bold">{expiringSoonCount}</p>
            </div>
          </div>
        </div>
        <div className="bg-slate-800 rounded-xl border border-red-500/50 p-4">
          <div className="flex items-center gap-3">
            <AlertTriangle className="text-red-400" size={24} />
            <div>
              <p className="text-slate-400 text-sm">Истекших</p>
              <p className="text-white text-2xl font-bold">{expiredCount}</p>
            </div>
          </div>
        </div>
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
                        {toDisplayStr(qual)}
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
                        {toDisplayStr(type)}
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
                        {toDisplayStr(qual)}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              <div>
                <div className="flex justify-between items-center mb-2">
                  <p className="text-sm text-slate-400">Сертификаты и допуски</p>
                  {(currentUser?.role === 'admin' || currentUser?.role === 'chief_operator') && (
                    <button
                      onClick={() => handleAddCertification(selectedEngineer.id)}
                      className="text-accent hover:text-blue-400 text-sm flex items-center gap-1"
                    >
                      <Plus size={14} /> Добавить сертификат
                    </button>
                  )}
                </div>
                {getEngineerCertifications(selectedEngineer.id).length === 0 ? (
                  <p className="text-slate-400">Сертификаты не найдены</p>
                ) : (
                  <div className="space-y-2">
                    {getEngineerCertifications(selectedEngineer.id).map((cert) => {
                      const isExpired = isCertificationExpired(cert.expiry_date);
                      const isExpiring = isCertificationExpiring(cert.expiry_date);
                      const daysLeft = getDaysUntilExpiry(cert.expiry_date);
                      
                      return (
                        <div
                          key={cert.id}
                          className={`bg-slate-900 p-3 rounded-lg border ${
                            isExpired ? 'border-red-500/50' : isExpiring ? 'border-yellow-500/50' : 'border-slate-700'
                          }`}
                        >
                          <div className="flex justify-between items-start">
                            <div className="flex-1">
                              <p className="text-white font-bold">{cert.certification_type}</p>
                              <p className="text-sm text-slate-400">№ {cert.certificate_number || cert.number}</p>
                              {(cert.certification_areas?.length || (cert.certification_area ? 1 : 0)) > 0 && (
                                <p className="text-sm text-accent/90">
                                  Области аттестации: {(cert.certification_areas?.length ? cert.certification_areas : [cert.certification_area]).map(toDisplayStr).filter(Boolean).join('; ')}
                                </p>
                              )}
                              <p className="text-sm text-slate-400">
                                Выдан: {cert.issuing_organization || cert.issued_by}
                              </p>
                              {cert.scan_file_name && (
                                <button
                                  type="button"
                                  onClick={() => downloadCertScan(cert)}
                                  className="mt-2 inline-flex items-center gap-2 text-xs bg-slate-800 hover:bg-slate-700 border border-slate-700 px-2 py-1 rounded text-slate-200"
                                  title="Скачать скан (фото/PDF)"
                                >
                                  <FileText size={14} className="text-accent" />
                                  <span>Скан: {cert.scan_file_name}</span>
                                </button>
                              )}
                              {cert.document_number && (
                                <p className="text-xs text-slate-500 mt-1">
                                  Документ: {cert.document_number}
                                  {formatDateRu(cert.document_date) && ` от ${formatDateRu(cert.document_date)}`}
                                </p>
                              )}
                            </div>
                            <div className="flex items-center gap-2">
                              {isExpired ? (
                                <AlertTriangle className="text-red-400" size={20} />
                              ) : isExpiring ? (
                                <AlertTriangle className="text-yellow-400" size={20} />
                              ) : (
                                <CheckCircle className="text-green-400" size={20} />
                              )}
                              {(currentUser?.role === 'admin' || currentUser?.role === 'chief_operator') && (
                                <div className="flex gap-1">
                                  <button
                                    onClick={() => handleEditCertification(cert)}
                                    className="text-blue-400 hover:text-blue-300 p-1"
                                    title="Редактировать"
                                  >
                                    <Edit size={16} />
                                  </button>
                                  <button
                                    onClick={() => handleDeleteCertification(cert.id)}
                                    className="text-red-400 hover:text-red-300 p-1"
                                    title="Удалить"
                                  >
                                    <Trash2 size={16} />
                                  </button>
                                </div>
                              )}
                            </div>
                          </div>
                          {cert.issue_date && (
                            <p className="text-xs text-slate-500 mt-2">
                              Выдан: {formatDateRu(cert.issue_date) || '—'}
                            </p>
                          )}
                          {cert.expiry_date && (
                            <p className={`text-xs mt-1 ${
                              isExpired ? 'text-red-400' : isExpiring ? 'text-yellow-400' : 'text-slate-400'
                            }`}>
                              Действует до: {formatDateRu(cert.expiry_date) || '—'}
                              {isExpired && ' (Истек)'}
                              {isExpiring && !isExpired && ` (Истекает через ${daysLeft} дн.)`}
                              {!isExpired && !isExpiring && daysLeft && daysLeft > 90 && ` (Осталось ${daysLeft} дн.)`}
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
                        {toDisplayStr(type)}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Модальное окно создания/редактирования сертификата */}
      {showCertForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowCertForm(false)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-white">
                {editingCert ? 'Редактировать сертификат' : 'Добавить сертификат'}
              </h2>
              <button onClick={() => setShowCertForm(false)} className="text-slate-400 hover:text-white">
                <X size={24} />
              </button>
            </div>

            <form onSubmit={handleCertSubmit} className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Тип сертификата *</label>
                  <select
                    required
                    value={certFormData.certification_type}
                    onChange={(e) => setCertFormData({ ...certFormData, certification_type: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  >
                    <option value="">Выберите тип</option>
                    {CERTIFICATION_TYPES.map(type => (
                      <option key={type} value={type}>{type}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Номер сертификата *</label>
                  <input
                    type="text"
                    required
                    value={certFormData.certificate_number}
                    onChange={(e) => setCertFormData({ ...certFormData, certificate_number: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    placeholder="СЕРТ-2024-123456"
                  />
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Метод НК</label>
                  <select
                    value={certFormData.method_code}
                    onChange={(e) => setCertFormData({ ...certFormData, method_code: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  >
                    <option value="">Выберите метод</option>
                    {ndtMethods.map(method => (
                      <option key={method.code} value={method.code}>
                        {method.code} - {method.name}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="col-span-2">
                  <label className="text-sm text-slate-400 block mb-1">Области аттестации (можно несколько, до 10 и более)</label>
                  <div className="flex flex-wrap gap-2 mb-2">
                    {AREA_GROUPS.map((gr) => {
                      const allIn = gr.areas.every((a) => certFormData.certification_areas.includes(a));
                      return (
                        <span key={gr.label} className="flex gap-1 items-center flex-wrap">
                          <button
                            type="button"
                            onClick={() => (allIn ? removeAreaGroup(gr.areas) : addAreaGroup(gr.areas))}
                            className={`px-3 py-1.5 rounded text-sm font-medium border ${
                              allIn ? 'bg-accent/20 text-accent border-accent/50' : 'bg-slate-800 text-slate-300 border-slate-600 hover:border-accent/50'
                            }`}
                          >
                            {allIn ? '− ' : '+ '}{gr.label}
                          </button>
                        </span>
                      );
                    })}
                  </div>
                  <div className="max-h-48 overflow-y-auto border border-slate-700 rounded-lg p-3 bg-slate-900 space-y-1.5">
                    {CERTIFICATION_AREAS.map((area) => (
                      <label key={area} className="flex items-start gap-2 cursor-pointer text-sm text-slate-200 hover:text-white">
                        <input
                          type="checkbox"
                          checked={certFormData.certification_areas.includes(area)}
                          onChange={() => toggleCertificationArea(area)}
                          className="mt-1 rounded border-slate-600 text-accent bg-slate-800"
                        />
                        <span className="flex-1">{area}</span>
                      </label>
                    ))}
                  </div>
                  {certFormData.certification_areas.length > 0 && (
                    <p className="text-xs text-slate-500 mt-1">Выбрано: {certFormData.certification_areas.length}</p>
                  )}
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Тип оборудования</label>
                  <select
                    value={certFormData.equipment_type_id}
                    onChange={(e) => setCertFormData({ ...certFormData, equipment_type_id: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  >
                    <option value="">Выберите тип оборудования</option>
                    {equipmentTypes.map(type => (
                      <option key={type.id} value={type.id}>
                        {type.name}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Организация, выдавшая сертификат *</label>
                  <input
                    type="text"
                    required
                    value={certFormData.issuing_organization}
                    onChange={(e) => setCertFormData({ ...certFormData, issuing_organization: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    placeholder="Ростехнадзор"
                  />
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Номер документа о продлении</label>
                  <input
                    type="text"
                    value={certFormData.document_number}
                    onChange={(e) => setCertFormData({ ...certFormData, document_number: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                    placeholder="ДОК-2024-1234"
                  />
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Дата выдачи *</label>
                  <input
                    type="date"
                    required
                    value={certFormData.issue_date}
                    onChange={(e) => setCertFormData({ ...certFormData, issue_date: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  />
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Дата окончания действия *</label>
                  <input
                    type="date"
                    required
                    value={certFormData.expiry_date}
                    onChange={(e) => setCertFormData({ ...certFormData, expiry_date: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  />
                </div>
                <div>
                  <label className="text-sm text-slate-400 block mb-1">Дата документа о продлении</label>
                  <input
                    type="date"
                    value={certFormData.document_date}
                    onChange={(e) => setCertFormData({ ...certFormData, document_date: e.target.value })}
                    className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                  />
                </div>
              </div>

              <div className="bg-slate-900/50 border border-slate-700 rounded-lg p-4">
                <label className="text-sm text-slate-300 block mb-2">Скан сертификата (фото/PDF)</label>
                <input
                  type="file"
                  accept="application/pdf,image/*"
                  onChange={(e) => setCertScanFile(e.target.files?.[0] || null)}
                  className="block w-full text-sm text-slate-300 file:mr-4 file:py-2 file:px-4 file:rounded file:border-0 file:text-sm file:font-semibold file:bg-accent/20 file:text-accent hover:file:bg-accent/30"
                />
                <p className="text-xs text-slate-500 mt-2">
                  Файл будет загружен после сохранения сертификата.
                </p>
              </div>

              <div className="flex gap-2">
                <button
                  type="submit"
                  className="flex-1 bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-blue-600"
                >
                  {editingCert ? 'Сохранить изменения' : 'Создать сертификат'}
                </button>
                <button
                  type="button"
                  onClick={() => setShowCertForm(false)}
                  className="flex-1 bg-slate-700 px-4 py-2 rounded-lg text-white font-bold hover:bg-slate-600"
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

export default CompetenciesManagement;



