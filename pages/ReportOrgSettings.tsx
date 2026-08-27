import { useEffect, useState } from 'react';
import { Save, RotateCcw } from 'lucide-react';
import { API_BASE } from '../constants';

type Customer = {
  legal_name?: string;
  legal_form?: string;
  address?: string;
  phone?: string;
  email?: string;
  director?: string;
  department?: string;
  department_address?: string;
  department_phone?: string;
  department_head?: string;
  inn?: string;
};

type Contractor = {
  name?: string;
  short_name?: string;
  legal_form?: string;
  address?: string;
  license?: string;
  certificate?: string;
  director_title?: string;
  director_name?: string;
  phone?: string;
  email?: string;
};

type Settings = {
  work_basis?: string;
  normative_documents?: string[];
  report_city?: string;
  epb_registry_date?: string;
  customer?: Customer;
  contractor?: Contractor;
};

const emptySettings: Settings = {
  work_basis: '',
  normative_documents: [],
  report_city: '',
  epb_registry_date: '',
  customer: {},
  contractor: {},
};

const ReportOrgSettings = () => {
  const [settings, setSettings] = useState<Settings>(emptySettings);
  const [normativeText, setNormativeText] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');

  const authHeaders = (): HeadersInit => {
    const headers: HeadersInit = { 'Content-Type': 'application/json' };
    const token = localStorage.getItem('token');
    if (token) headers['Authorization'] = `Bearer ${token}`;
    return headers;
  };

  const load = async () => {
    setLoading(true);
    try {
      const response = await fetch(`${API_BASE}/api/report-org-settings`, { headers: authHeaders() });
      if (!response.ok) throw new Error('Не удалось загрузить настройки');
      const data = await response.json();
      setSettings(data);
      setNormativeText((data.normative_documents || []).join('\n'));
    } catch (e) {
      console.error(e);
      setMessage('Ошибка загрузки настроек');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  const updateCustomer = (key: keyof Customer, value: string) => {
    setSettings((prev) => ({
      ...prev,
      customer: { ...(prev.customer || {}), [key]: value },
    }));
  };

  const updateContractor = (key: keyof Contractor, value: string) => {
    setSettings((prev) => ({
      ...prev,
      contractor: { ...(prev.contractor || {}), [key]: value },
    }));
  };

  const handleSave = async () => {
    setSaving(true);
    setMessage('');
    try {
      const payload = {
        ...settings,
        normative_documents: normativeText
          .split('\n')
          .map((line) => line.trim())
          .filter(Boolean),
      };
      const response = await fetch(`${API_BASE}/api/report-org-settings`, {
        method: 'PUT',
        headers: authHeaders(),
        body: JSON.stringify(payload),
      });
      if (!response.ok) throw new Error('Ошибка сохранения');
      const data = await response.json();
      setSettings(data);
      setNormativeText((data.normative_documents || []).join('\n'));
      setMessage('Настройки сохранены');
    } catch (e) {
      console.error(e);
      setMessage('Не удалось сохранить настройки');
    } finally {
      setSaving(false);
    }
  };

  const handleReset = async () => {
    if (!confirm('Сбросить настройки отчёта к значениям по умолчанию?')) return;
    setSaving(true);
    try {
      const response = await fetch(`${API_BASE}/api/report-org-settings/reset`, {
        method: 'POST',
        headers: authHeaders(),
      });
      if (!response.ok) throw new Error('Ошибка сброса');
      await load();
      setMessage('Настройки сброшены');
    } catch (e) {
      console.error(e);
      setMessage('Не удалось сбросить настройки');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <div className="p-6 text-[var(--text-secondary)]">Загрузка...</div>;
  }

  const customer = settings.customer || {};
  const contractor = settings.contractor || {};

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[var(--text-primary)]">Справочник данных отчёта</h1>
          <p className="text-sm text-[var(--text-secondary)] mt-1">
            Основания работ, сведения о заказчике, организации ТД, перечень НД и шапки приложений
          </p>
        </div>
        <div className="flex gap-2">
          <button onClick={handleReset} className="sp-btn-subtle flex items-center gap-2" disabled={saving}>
            <RotateCcw size={16} /> Сбросить
          </button>
          <button onClick={handleSave} className="sp-btn-primary flex items-center gap-2" disabled={saving}>
            <Save size={16} /> {saving ? 'Сохранение...' : 'Сохранить'}
          </button>
        </div>
      </div>

      {message && <div className="sp-card-soft p-3 text-sm">{message}</div>}

      <section className="sp-card p-4 space-y-3">
        <h2 className="font-semibold">1. Основания для проведения работ</h2>
        <textarea
          className="w-full min-h-[100px] rounded border p-3 bg-[var(--bg-secondary)]"
          value={settings.work_basis || ''}
          onChange={(e) => setSettings((prev) => ({ ...prev, work_basis: e.target.value }))}
        />
      </section>

      <section className="sp-card p-4 space-y-3">
        <h2 className="font-semibold">Таблица №1 — Сведения о заказчике</h2>
        <div className="grid md:grid-cols-2 gap-3">
          {[
            ['legal_name', 'Наименование организации'],
            ['legal_form', 'Организационно-правовая форма'],
            ['address', 'Место нахождения'],
            ['phone', 'Телефон / факс'],
            ['email', 'E-mail'],
            ['director', 'Руководитель'],
            ['department', 'Структурное подразделение'],
            ['department_address', 'Место нахождения подразделения'],
            ['department_phone', 'Телефон / факс подразделения'],
            ['department_head', 'Руководитель подразделения'],
            ['inn', 'ИНН'],
          ].map(([key, label]) => (
            <label key={key} className="text-sm space-y-1 block">
              <span className="text-[var(--text-secondary)]">{label}</span>
              <input
                className="w-full rounded border p-2 bg-[var(--bg-secondary)]"
                value={(customer as Record<string, string>)[key] || ''}
                onChange={(e) => updateCustomer(key as keyof Customer, e.target.value)}
              />
            </label>
          ))}
        </div>
      </section>

      <section className="sp-card p-4 space-y-3">
        <h2 className="font-semibold">Таблица №2 — Организация, проводившая ТД</h2>
        <div className="grid md:grid-cols-2 gap-3">
          {[
            ['short_name', 'Краткое наименование'],
            ['name', 'Полное наименование'],
            ['legal_form', 'Организационно-правовая форма'],
            ['address', 'Юридический адрес'],
            ['license', 'Лицензия'],
            ['certificate', 'Свидетельство об аттестации'],
            ['director_title', 'Должность руководителя'],
            ['director_name', 'ФИО руководителя'],
            ['phone', 'Телефон'],
            ['email', 'E-mail'],
          ].map(([key, label]) => (
            <label key={key} className="text-sm space-y-1 block">
              <span className="text-[var(--text-secondary)]">{label}</span>
              <input
                className="w-full rounded border p-2 bg-[var(--bg-secondary)]"
                value={(contractor as Record<string, string>)[key] || ''}
                onChange={(e) => updateContractor(key as keyof Contractor, e.target.value)}
              />
            </label>
          ))}
        </div>
      </section>

      <section className="sp-card p-4 space-y-3">
        <h2 className="font-semibold">Перечень нормативной документации</h2>
        <p className="text-xs text-[var(--text-secondary)]">Каждый документ — с новой строки</p>
        <textarea
          className="w-full min-h-[180px] rounded border p-3 bg-[var(--bg-secondary)] font-mono text-sm"
          value={normativeText}
          onChange={(e) => setNormativeText(e.target.value)}
        />
      </section>

      <section className="sp-card p-4 grid md:grid-cols-2 gap-3">
        <label className="text-sm space-y-1 block">
          <span className="text-[var(--text-secondary)]">Город на титульном листе</span>
          <input
            className="w-full rounded border p-2 bg-[var(--bg-secondary)]"
            value={settings.report_city || ''}
            onChange={(e) => setSettings((prev) => ({ ...prev, report_city: e.target.value }))}
          />
        </label>
        <label className="text-sm space-y-1 block">
          <span className="text-[var(--text-secondary)]">Дата внесения в реестр ЭПБ</span>
          <input
            className="w-full rounded border p-2 bg-[var(--bg-secondary)]"
            value={settings.epb_registry_date || ''}
            onChange={(e) => setSettings((prev) => ({ ...prev, epb_registry_date: e.target.value }))}
          />
        </label>
      </section>
    </div>
  );
};

export default ReportOrgSettings;
