import React, { useState, useEffect, useMemo } from 'react';
import {
  Wrench, Plus, Search, Filter, RefreshCw, Edit2, Trash2,
  CheckCircle, AlertTriangle, XCircle, Link2, User,
  ChevronDown, ChevronUp, X,
} from 'lucide-react';
import { API_BASE } from '../constants';
import { useAuth } from '../contexts/AuthContext';

// ─── Справочник типов приборов ────────────────────────────────────────────────
// Подсказки для поля «Тип» — включая категории, ранее отсутствовавшие в реестре
const INSTRUMENT_TYPE_OPTIONS = [
  'ВИК', 'УЗК', 'УЗТ', 'МПК', 'ПВК (капиллярный)',
  'Образец шероховатости', 'Люксметр',
  'Комплект капиллярного контроля (с реагентами)',
  'Твердомер',
];

// ─── Типы ────────────────────────────────────────────────────────────────────

interface Instrument {
  id: string;
  /** Строка только из журнала поверок (ещё не в реестре) */
  is_shadow_row?: boolean;
  name: string;
  type: string;
  serial_number: string;
  verification_until: string;
  verification_status: 'ok' | 'warning' | 'expiring_soon' | 'expired' | 'unknown';
  condition: 'ok' | 'damaged' | 'broken';
  condition_notes: string;
  reagents?: string;
  specialist_id: string | null;
  specialist_name: string;
  verification_equipment_id: string | null;
  ve_name: string | null;
  ve_manufacturer: string | null;
  ve_model: string | null;
  ve_certificate: string | null;
  ve_organization: string | null;
  ve_next_verification_date: string | null;
  created_at: string | null;
}

interface VEOption {
  id: string;
  name: string;
  equipment_type: string;
  serial_number: string;
  next_verification_date: string | null;
  manufacturer: string;
  model: string;
}

interface User {
  id: string;
  full_name: string;
  username: string;
  role: string;
}

// ─── Хелперы ─────────────────────────────────────────────────────────────────

const CONDITION_CONFIG = {
  ok: { label: 'Исправен', color: 'text-green-400', bg: 'bg-green-400/10 border-green-400/20', icon: CheckCircle },
  damaged: { label: 'Повреждён', color: 'text-yellow-400', bg: 'bg-yellow-400/10 border-yellow-400/20', icon: AlertTriangle },
  broken: { label: 'Неисправен', color: 'text-red-400', bg: 'bg-red-400/10 border-red-400/20', icon: XCircle },
} as const;

const VER_STATUS_CONFIG = {
  ok: { label: '', color: 'text-green-400', bg: 'bg-green-400/10' },
  warning: { label: '', color: 'text-yellow-400', bg: 'bg-yellow-400/10' },
  expiring_soon: { label: ' (!)', color: 'text-orange-400', bg: 'bg-orange-400/10' },
  expired: { label: ' ✕', color: 'text-red-400', bg: 'bg-red-400/10' },
  unknown: { label: '', color: 'text-gray-400', bg: 'bg-gray-400/10' },
} as const;

function formatVerDate(dateStr: string): string {
  if (!dateStr) return '—';
  // YYYY-MM формат
  if (/^\d{4}-\d{2}$/.test(dateStr)) {
    const [y, m] = dateStr.split('-');
    return `${m}.${y}`;
  }
  // YYYY-MM-DD формат
  if (/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
    const [y, m] = dateStr.split('-');
    return `${m}.${y}`;
  }
  return dateStr;
}

function getAuthHeaders() {
  const token = localStorage.getItem('token');
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

// ─── Модалка создания/редактирования ─────────────────────────────────────────

interface FormModalProps {
  instrument: Instrument | null;
  /** При создании из «тени» поверки — сразу выбрать поверочный прибор */
  prefillVerificationEquipmentId?: string | null;
  veOptions: VEOption[];
  engineers: User[];
  onClose: () => void;
  onSave: () => void;
}

const FormModal: React.FC<FormModalProps> = ({
  instrument,
  prefillVerificationEquipmentId,
  veOptions,
  engineers,
  onClose,
  onSave,
}) => {
  const { user } = useAuth();
  const isOperatorOrAdmin = ['admin', 'chief_operator', 'operator'].includes(user?.role ?? '');

  const [form, setForm] = useState({
    name: instrument?.name ?? '',
    type: instrument?.type ?? '',
    serial_number: instrument?.serial_number ?? '',
    verification_until: instrument?.verification_until ?? '',
    condition: instrument?.condition ?? 'ok',
    condition_notes: instrument?.condition_notes ?? '',
    specialist_id: instrument?.specialist_id ?? '',
    verification_equipment_id: instrument?.verification_equipment_id ?? '',
    reagents: instrument?.reagents ?? '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  React.useEffect(() => {
    if (!instrument && prefillVerificationEquipmentId) {
      const ve = veOptions.find(v => v.id === prefillVerificationEquipmentId);
      if (ve) {
        setForm(f => ({
          ...f,
          verification_equipment_id: prefillVerificationEquipmentId,
          name: f.name || ve.name,
          type: f.type || ve.equipment_type,
          serial_number: f.serial_number || ve.serial_number,
        }));
      }
    }
  }, [instrument, prefillVerificationEquipmentId, veOptions]);

  const linkedVE = veOptions.find(v => v.id === form.verification_equipment_id);

  const handleVESelect = (veId: string) => {
    const ve = veOptions.find(v => v.id === veId);
    if (ve) {
      setForm(f => ({
        ...f,
        verification_equipment_id: veId,
        name: f.name || ve.name,
        type: f.type || ve.equipment_type,
        serial_number: f.serial_number || ve.serial_number,
      }));
    } else {
      setForm(f => ({ ...f, verification_equipment_id: '' }));
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) { setError('Укажите наименование прибора'); return; }
    setSaving(true);
    setError('');
    try {
      const url = instrument
        ? `${API_BASE}/api/instruments/${instrument.id}`
        : `${API_BASE}/api/instruments`;
      const method = instrument ? 'PUT' : 'POST';
      const payload = { ...form, specialist_id: form.specialist_id || null, verification_equipment_id: form.verification_equipment_id || null };
      const res = await fetch(url, { method, headers: getAuthHeaders(), body: JSON.stringify(payload) });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.detail || 'Ошибка сохранения');
      }
      onSave();
    } catch (err: any) {
      setError(err.message ?? 'Ошибка');
    } finally {
      setSaving(false);
    }
  };

  const inp = 'w-full px-3 py-2 rounded-lg text-sm border focus:outline-none focus:ring-2 focus:ring-blue-500/40';
  const inpStyle = { background: 'var(--bg-tertiary)', borderColor: 'var(--border-subtle)', color: 'var(--text-primary)' };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.7)', backdropFilter: 'blur(4px)' }}>
      <div className="w-full max-w-lg mx-4 rounded-2xl shadow-2xl" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border-subtle)' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b" style={{ borderColor: 'var(--border-subtle)' }}>
          <h2 className="font-semibold text-base" style={{ color: 'var(--text-primary)' }}>
            {instrument ? 'Редактировать прибор' : 'Добавить прибор'}
          </h2>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-white/10 transition-colors" style={{ color: 'var(--text-muted)' }}>
            <X size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="px-6 py-4 space-y-3 max-h-[70vh] overflow-y-auto">

          {/* Привязка к поверке (только для операторов/admin) */}
          {isOperatorOrAdmin && (
            <div>
              <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)' }}>
                Привязать к поверочному прибору
              </label>
              <select
                className={inp}
                style={inpStyle}
                value={form.verification_equipment_id}
                onChange={e => handleVESelect(e.target.value)}
              >
                <option value="">— Без привязки (ввести вручную) —</option>
                {veOptions.map(ve => (
                  <option key={ve.id} value={ve.id}>
                    {ve.name}{ve.serial_number ? ` / ${ve.serial_number}` : ''}
                    {ve.next_verification_date ? ` (поверка до ${formatVerDate(ve.next_verification_date)})` : ''}
                  </option>
                ))}
              </select>
              {linkedVE && (
                <p className="text-xs mt-1 text-blue-400 flex items-center gap-1">
                  <Link2 size={11} />
                  Данные поверки синхронизируются автоматически
                </p>
              )}
            </div>
          )}

          <div>
            <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)' }}>Наименование *</label>
            <input className={inp} style={inpStyle} value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="Например: Булат-1М" required />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)' }}>Тип (УЗТ, УЗК, ВИК...)</label>
              <input
                list="instrument-type-options"
                className={inp}
                style={inpStyle}
                value={form.type}
                onChange={e => setForm(f => ({ ...f, type: e.target.value }))}
                placeholder="УЗТ"
              />
              <datalist id="instrument-type-options">
                {INSTRUMENT_TYPE_OPTIONS.map(opt => <option key={opt} value={opt} />)}
              </datalist>
            </div>
            <div>
              <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)' }}>Заводской номер</label>
              <input className={inp} style={inpStyle} value={form.serial_number} onChange={e => setForm(f => ({ ...f, serial_number: e.target.value }))} placeholder="A-12345" />
            </div>
          </div>

          {/(капилляр|пвк)/i.test(form.type) && (
            <div>
              <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)' }}>Реагенты (очиститель, индикаторный пенетрант, проявитель — партии/сроки годности)</label>
              <textarea
                className={inp}
                style={inpStyle}
                rows={2}
                value={form.reagents}
                onChange={e => setForm(f => ({ ...f, reagents: e.target.value }))}
                placeholder="Очиститель СО-50 парт. 12, годен до 2027-01; Пенетрант К, проявитель П..."
              />
            </div>
          )}

          {!form.verification_equipment_id && (
            <div>
              <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)' }}>Поверка до (ГОД-МЕСЯЦ)</label>
              <input className={inp} style={inpStyle} value={form.verification_until} onChange={e => setForm(f => ({ ...f, verification_until: e.target.value }))} placeholder="2026-08" />
            </div>
          )}

          {isOperatorOrAdmin && (
            <div>
              <label className="block text-xs font-medium mb-1.5 flex items-center gap-1" style={{ color: 'var(--text-muted)' }}>
                <User size={12} /> Закреплён за специалистом
              </label>
              <select className={inp} style={inpStyle} value={form.specialist_id} onChange={e => setForm(f => ({ ...f, specialist_id: e.target.value }))}>
                <option value="">— Не закреплён —</option>
                {engineers.map(eng => (
                  <option key={eng.id} value={eng.id}>{eng.full_name || eng.username}</option>
                ))}
              </select>
            </div>
          )}

          <div>
            <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)' }}>Состояние прибора</label>
            <div className="flex gap-2">
              {(Object.keys(CONDITION_CONFIG) as Array<keyof typeof CONDITION_CONFIG>).map(key => {
                const cfg = CONDITION_CONFIG[key];
                const Icon = cfg.icon;
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setForm(f => ({ ...f, condition: key }))}
                    className={`flex-1 flex items-center justify-center gap-1.5 py-2 rounded-lg text-xs font-medium border transition-all ${
                      form.condition === key ? cfg.bg + ' ' + cfg.color : 'border-transparent'
                    }`}
                    style={form.condition !== key ? { background: 'var(--bg-tertiary)', color: 'var(--text-muted)' } : undefined}
                  >
                    <Icon size={13} />
                    {cfg.label}
                  </button>
                );
              })}
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)' }}>Примечание к состоянию</label>
            <input className={inp} style={inpStyle} value={form.condition_notes} onChange={e => setForm(f => ({ ...f, condition_notes: e.target.value }))} placeholder="Необязательно" />
          </div>

          {error && (
            <p className="text-xs text-red-400 flex items-center gap-1"><XCircle size={13} />{error}</p>
          )}
        </form>

        <div className="flex items-center justify-end gap-2 px-6 py-4 border-t" style={{ borderColor: 'var(--border-subtle)' }}>
          <button onClick={onClose} className="px-4 py-2 rounded-lg text-sm font-medium transition-colors hover:bg-white/5" style={{ color: 'var(--text-muted)' }}>
            Отмена
          </button>
          <button
            onClick={handleSubmit as any}
            disabled={saving}
            className="px-4 py-2 rounded-lg text-sm font-semibold text-white transition-colors disabled:opacity-50"
            style={{ background: 'var(--accent)' }}
          >
            {saving ? 'Сохранение...' : instrument ? 'Сохранить' : 'Добавить'}
          </button>
        </div>
      </div>
    </div>
  );
};

// ─── Основная страница ────────────────────────────────────────────────────────

const InstrumentRegistry: React.FC = () => {
  const { user } = useAuth();
  const isOperatorOrAdmin = ['admin', 'chief_operator', 'operator'].includes(user?.role ?? '');
  const isEngineer = user?.role === 'engineer';

  const [instruments, setInstruments] = useState<Instrument[]>([]);
  const [veOptions, setVeOptions] = useState<VEOption[]>([]);
  const [engineers, setEngineers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filterType, setFilterType] = useState('');
  const [filterSpecialist, setFilterSpecialist] = useState('');
  const [filterCondition, setFilterCondition] = useState('');
  const [filterExpiring, setFilterExpiring] = useState(false);
  const [showFilters, setShowFilters] = useState(true);
  const [modalInstrument, setModalInstrument] = useState<Instrument | null | 'new'>('new' as any);
  const [prefillVeId, setPrefillVeId] = useState<string | null>(null);
  const [showModal, setShowModal] = useState(false);
  const [sortField, setSortField] = useState<string>('name');
  const [sortAsc, setSortAsc] = useState(true);
  const [deleteConfirm, setDeleteConfirm] = useState<Instrument | null>(null);

  useEffect(() => {
    loadAll();
  }, []);

  const loadAll = async () => {
    setLoading(true);
    try {
      const headers = getAuthHeaders();
      const [instrRes, veRes, engRes] = await Promise.all([
        fetch(`${API_BASE}/api/instruments`, { headers }),
        fetch(`${API_BASE}/api/instruments/ve-options`, { headers }),
        fetch(`${API_BASE}/api/instruments/specialists`, { headers }),
      ]);
      if (instrRes.ok) setInstruments(await instrRes.json());
      if (veRes.ok) setVeOptions(await veRes.json());
      if (engRes.ok) {
        const data = await engRes.json();
        setEngineers(Array.isArray(data) ? data : []);
      }
    } catch (err) {
      console.error('Ошибка загрузки реестра приборов:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (inst: Instrument) => {
    try {
      const res = await fetch(`${API_BASE}/api/instruments/${inst.id}`, {
        method: 'DELETE',
        headers: getAuthHeaders(),
      });
      if (res.ok || res.status === 204) {
        setDeleteConfirm(null);
        loadAll();
      }
    } catch (err) {
      console.error('Ошибка удаления:', err);
    }
  };

  // Уникальные значения для фильтров
  const uniqueTypes = useMemo(() => [...new Set(instruments.map(i => i.type).filter(Boolean))].sort(), [instruments]);
  const uniqueSpecialists = useMemo(() => [...new Set(instruments.map(i => i.specialist_name).filter(Boolean))].sort(), [instruments]);

  // Фильтрация + поиск
  const filtered = useMemo(() => {
    let list = instruments;
    if (search) {
      const q = search.toLowerCase();
      list = list.filter(i =>
        i.name.toLowerCase().includes(q) ||
        i.type.toLowerCase().includes(q) ||
        i.serial_number.toLowerCase().includes(q) ||
        i.specialist_name.toLowerCase().includes(q)
      );
    }
    if (filterType) list = list.filter(i => i.type === filterType);
    if (filterSpecialist) list = list.filter(i => i.specialist_name === filterSpecialist);
    if (filterCondition) list = list.filter(i => i.condition === filterCondition);
    if (filterExpiring) list = list.filter(i => i.verification_status === 'expired' || i.verification_status === 'expiring_soon' || i.verification_status === 'warning');

    // Сортировка
    list = [...list].sort((a, b) => {
      let va: any = (a as any)[sortField] ?? '';
      let vb: any = (b as any)[sortField] ?? '';
      if (typeof va === 'string') va = va.toLowerCase();
      if (typeof vb === 'string') vb = vb.toLowerCase();
      if (va < vb) return sortAsc ? -1 : 1;
      if (va > vb) return sortAsc ? 1 : -1;
      return 0;
    });
    return list;
  }, [instruments, search, filterType, filterSpecialist, filterCondition, filterExpiring, sortField, sortAsc]);

  // Статистика
  const stats = useMemo(() => ({
    total: instruments.length,
    expired: instruments.filter(i => i.verification_status === 'expired').length,
    expiring: instruments.filter(i => i.verification_status === 'expiring_soon').length,
    broken: instruments.filter(i => i.condition === 'damaged' || i.condition === 'broken').length,
    linked: instruments.filter(i => i.verification_equipment_id).length,
    inRegistry: instruments.filter(i => !i.is_shadow_row).length,
  }), [instruments]);

  const toggleSort = (field: string) => {
    if (sortField === field) setSortAsc(a => !a);
    else { setSortField(field); setSortAsc(true); }
  };

  const SortIcon = ({ field }: { field: string }) => {
    if (sortField !== field) return null;
    return sortAsc ? <ChevronUp size={12} className="inline ml-0.5" /> : <ChevronDown size={12} className="inline ml-0.5" />;
  };

  const activeFiltersCount = [filterType, filterSpecialist, filterCondition, filterExpiring].filter(Boolean).length;

  return (
    <div className="space-y-4">

      {/* Заголовок */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-bold flex items-center gap-2" style={{ color: 'var(--text-primary)' }}>
            <Wrench size={22} style={{ color: 'var(--accent)' }} />
            Реестр приборов
          </h1>
          <p className="text-xs mt-0.5" style={{ color: 'var(--text-muted)' }}>
            Приборный парк — учёт, состояние, закрепление за специалистами
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={loadAll} className="p-2 rounded-lg transition-colors hover:bg-white/5" style={{ color: 'var(--text-muted)' }} title="Обновить">
            <RefreshCw size={16} />
          </button>
          {isOperatorOrAdmin && (
            <button
              onClick={() => { setModalInstrument(null); setPrefillVeId(null); setShowModal(true); }}
              className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold text-white transition-all hover:opacity-90"
              style={{ background: 'var(--accent)' }}
            >
              <Plus size={16} /> Добавить прибор
            </button>
          )}
        </div>
      </div>

      {/* Статистика */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        {[
          { label: 'Всего в списке', value: stats.total, color: 'text-blue-400' },
          { label: 'В реестре', value: stats.inRegistry, color: 'text-app-text2' },
          { label: 'Привязано к поверкам', value: stats.linked, color: 'text-cyan-400' },
          { label: 'Просрочена поверка', value: stats.expired, color: stats.expired > 0 ? 'text-red-400' : 'text-gray-400' },
          { label: 'Поверка скоро', value: stats.expiring, color: stats.expiring > 0 ? 'text-orange-400' : 'text-gray-400' },
          { label: 'Неисправны', value: stats.broken, color: stats.broken > 0 ? 'text-yellow-400' : 'text-gray-400' },
        ].map(({ label, value, color }) => (
          <div key={label} className="rounded-xl p-3 text-center" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border-subtle)' }}>
            <div className={`text-2xl font-bold ${color}`}>{value}</div>
            <div className="text-xs mt-0.5" style={{ color: 'var(--text-muted)' }}>{label}</div>
          </div>
        ))}
      </div>

      {/* Поиск и фильтры */}
      <div className="rounded-xl p-3 flex flex-wrap gap-2 items-center" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border-subtle)' }}>
        <div className="relative flex-1 min-w-[200px]">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2" style={{ color: 'var(--text-muted)' }} />
          <input
            className="w-full pl-9 pr-3 py-2 rounded-lg text-sm border focus:outline-none focus:ring-2 focus:ring-blue-500/30"
            style={{ background: 'var(--bg-tertiary)', borderColor: 'var(--border-subtle)', color: 'var(--text-primary)' }}
            placeholder="Поиск по названию, типу, номеру, специалисту..."
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>
        <button
          onClick={() => setShowFilters(f => !f)}
          className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-medium transition-colors border ${showFilters ? 'border-blue-500/40 text-blue-400' : ''}`}
          style={showFilters ? { background: 'rgba(59,130,246,0.08)' } : { background: 'var(--bg-tertiary)', borderColor: 'var(--border-subtle)', color: 'var(--text-muted)' }}
        >
          <Filter size={14} />
          Фильтры
          {activeFiltersCount > 0 && (
            <span className="ml-0.5 px-1.5 py-0.5 rounded-full text-xs font-bold text-white" style={{ background: 'var(--accent)' }}>
              {activeFiltersCount}
            </span>
          )}
        </button>

        {showFilters && (
          <div className="w-full flex flex-wrap gap-2 pt-2 border-t" style={{ borderColor: 'var(--border-subtle)' }}>
            <select
              className="px-3 py-1.5 rounded-lg text-sm border focus:outline-none"
              style={{ background: 'var(--bg-tertiary)', borderColor: 'var(--border-subtle)', color: 'var(--text-primary)' }}
              value={filterType}
              onChange={e => setFilterType(e.target.value)}
            >
              <option value="">Все типы</option>
              {uniqueTypes.map(t => <option key={t} value={t}>{t}</option>)}
            </select>

            <select
              className="px-3 py-1.5 rounded-lg text-sm border focus:outline-none"
              style={{ background: 'var(--bg-tertiary)', borderColor: 'var(--border-subtle)', color: 'var(--text-primary)' }}
              value={filterSpecialist}
              onChange={e => setFilterSpecialist(e.target.value)}
            >
              <option value="">Все специалисты</option>
              {uniqueSpecialists.map(s => <option key={s} value={s}>{s}</option>)}
            </select>

            <select
              className="px-3 py-1.5 rounded-lg text-sm border focus:outline-none"
              style={{ background: 'var(--bg-tertiary)', borderColor: 'var(--border-subtle)', color: 'var(--text-primary)' }}
              value={filterCondition}
              onChange={e => setFilterCondition(e.target.value)}
            >
              <option value="">Все состояния</option>
              <option value="ok">Исправен</option>
              <option value="damaged">Повреждён</option>
              <option value="broken">Неисправен</option>
            </select>

            <label className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm cursor-pointer select-none border" style={{ background: 'var(--bg-tertiary)', borderColor: 'var(--border-subtle)', color: 'var(--text-muted)' }}>
              <input type="checkbox" checked={filterExpiring} onChange={e => setFilterExpiring(e.target.checked)} className="rounded" />
              Поверка истекает / просрочена
            </label>

            {activeFiltersCount > 0 && (
              <button
                onClick={() => { setFilterType(''); setFilterSpecialist(''); setFilterCondition(''); setFilterExpiring(false); }}
                className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs text-red-400 hover:bg-red-400/10 transition-colors"
              >
                <X size={12} /> Сбросить
              </button>
            )}
          </div>
        )}
      </div>

      {/* Таблица */}
      <div className="rounded-xl overflow-hidden" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border-subtle)' }}>
        {loading ? (
          <div className="flex items-center justify-center py-16">
            <div className="w-8 h-8 rounded-full border-2 border-transparent border-t-blue-500 border-r-blue-500 animate-spin" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <Wrench size={40} style={{ color: 'var(--text-muted)' }} />
            <p className="text-sm font-medium" style={{ color: 'var(--text-muted)' }}>
              {instruments.length === 0 ? 'Реестр приборов пуст' : 'Нет приборов по выбранным фильтрам'}
            </p>
            {isOperatorOrAdmin && instruments.length === 0 && (
              <button
                onClick={() => { setModalInstrument(null); setPrefillVeId(null); setShowModal(true); }}
                className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium text-white"
                style={{ background: 'var(--accent)' }}
              >
                <Plus size={15} /> Добавить первый прибор
              </button>
            )}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b" style={{ borderColor: 'var(--border-subtle)' }}>
                  {[
                    { label: '№', field: null, w: '3%' },
                    { label: 'Наименование', field: 'name', w: '22%' },
                    { label: 'Тип', field: 'type', w: '8%' },
                    { label: 'Зав. №', field: 'serial_number', w: '10%' },
                    { label: 'Поверка до', field: 'verification_until', w: '10%' },
                    { label: 'Состояние', field: 'condition', w: '12%' },
                    { label: 'Специалист', field: 'specialist_name', w: '15%' },
                    { label: 'Связь', field: null, w: '5%' },
                    ...(isOperatorOrAdmin || isEngineer ? [{ label: '', field: null, w: '8%' }] : []),
                  ].map(({ label, field, w }) => (
                    <th
                      key={label || w}
                      style={{ width: w, color: 'var(--text-muted)', textAlign: 'left' }}
                      className={`px-4 py-3 text-xs font-semibold uppercase tracking-wider ${field ? 'cursor-pointer hover:text-blue-400 select-none' : ''}`}
                      onClick={() => field && toggleSort(field)}
                    >
                      {label}{field && <SortIcon field={field} />}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {filtered.map((inst, idx) => {
                  const condCfg = CONDITION_CONFIG[inst.condition] ?? CONDITION_CONFIG.ok;
                  const CondIcon = condCfg.icon;
                  const verCfg = VER_STATUS_CONFIG[inst.verification_status] ?? VER_STATUS_CONFIG.unknown;
                  const condLabel = inst.condition_notes || condCfg.label;
                  const isLinked = !!inst.verification_equipment_id;

                  return (
                    <tr
                      key={inst.id}
                      className="border-b transition-colors hover:bg-white/[0.02]"
                      style={{ borderColor: 'var(--border-subtle)' }}
                    >
                      <td className="px-4 py-3" style={{ color: 'var(--text-muted)' }}>{idx + 1}</td>

                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2 flex-wrap">
                          <div className="font-medium" style={{ color: 'var(--text-primary)' }}>{inst.name}</div>
                          {(inst.is_shadow_row || inst.id.startsWith('ve-shadow:')) && (
                            <span className="text-[10px] px-1.5 py-0.5 rounded font-medium bg-amber-500/15 text-amber-300 border border-amber-500/25">
                              только поверка
                            </span>
                          )}
                        </div>
                        {isLinked && inst.ve_manufacturer && (
                          <div className="text-xs mt-0.5" style={{ color: 'var(--text-muted)' }}>
                            {inst.ve_manufacturer}{inst.ve_model ? ` ${inst.ve_model}` : ''}
                          </div>
                        )}
                      </td>

                      <td className="px-4 py-3">
                        {inst.type ? (
                          <span className="px-2 py-0.5 rounded text-xs font-medium" style={{ background: 'rgba(59,130,246,0.12)', color: 'var(--accent)' }}>
                            {inst.type}
                          </span>
                        ) : <span style={{ color: 'var(--text-muted)' }}>—</span>}
                      </td>

                      <td className="px-4 py-3 text-xs font-mono" style={{ color: 'var(--text-secondary)' }}>
                        {inst.serial_number || '—'}
                      </td>

                      <td className="px-4 py-3">
                        {inst.verification_until ? (
                          <span className={`font-semibold text-sm ${verCfg.color}`}>
                            {formatVerDate(inst.verification_until)}{verCfg.label}
                          </span>
                        ) : (
                          <span style={{ color: 'var(--text-muted)' }}>—</span>
                        )}
                      </td>

                      <td className="px-4 py-3">
                        <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-medium border ${condCfg.bg} ${condCfg.color}`}>
                          <CondIcon size={11} />
                          {condLabel}
                        </span>
                      </td>

                      <td className="px-4 py-3">
                        {inst.specialist_name ? (
                          <span className="flex items-center gap-1.5 text-sm" style={{ color: 'var(--text-secondary)' }}>
                            <User size={13} style={{ color: 'var(--text-muted)' }} />
                            {inst.specialist_name}
                          </span>
                        ) : (
                          <span className="text-xs" style={{ color: 'var(--text-muted)' }}>Не закреплён</span>
                        )}
                      </td>

                      <td className="px-4 py-3 text-center">
                        {isLinked ? (
                          <span title="Привязан к журналу поверок" className="text-cyan-400">
                            <Link2 size={14} />
                          </span>
                        ) : (
                          <span title="Ввод вручную" style={{ color: 'var(--text-muted)', opacity: 0.4 }}>
                            <Link2 size={14} />
                          </span>
                        )}
                      </td>

                      {(isOperatorOrAdmin || isEngineer) && (
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-1">
                            {isOperatorOrAdmin && (inst.is_shadow_row || inst.id.startsWith('ve-shadow:')) && (
                              <button
                                type="button"
                                onClick={() => {
                                  setModalInstrument(null);
                                  setPrefillVeId(inst.verification_equipment_id || '');
                                  setShowModal(true);
                                }}
                                className="px-2 py-1 rounded-lg text-xs font-semibold bg-amber-500/20 text-amber-200 border border-amber-500/30 hover:bg-amber-500/30"
                                title="Создать запись реестра с привязкой к этой поверке"
                              >
                                В реестр
                              </button>
                            )}
                            {(isOperatorOrAdmin || (isEngineer && inst.specialist_id === user?.id)) &&
                              !inst.is_shadow_row &&
                              !inst.id.startsWith('ve-shadow:') && (
                              <button
                                onClick={() => { setPrefillVeId(null); setModalInstrument(inst); setShowModal(true); }}
                                className="p-1.5 rounded-lg hover:bg-white/10 transition-colors"
                                style={{ color: 'var(--text-muted)' }}
                                title="Редактировать"
                              >
                                <Edit2 size={14} />
                              </button>
                            )}
                            {isOperatorOrAdmin && !inst.is_shadow_row && !inst.id.startsWith('ve-shadow:') && (
                              <button
                                onClick={() => setDeleteConfirm(inst)}
                                className="p-1.5 rounded-lg hover:bg-red-400/10 transition-colors text-red-400/60 hover:text-red-400"
                                title="Удалить"
                              >
                                <Trash2 size={14} />
                              </button>
                            )}
                          </div>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
            <div className="px-4 py-2 text-xs" style={{ color: 'var(--text-muted)', borderTop: '1px solid var(--border-subtle)' }}>
              Показано: {filtered.length} из {instruments.length}
              {stats.linked > 0 && (
                <span className="ml-3 text-cyan-400 flex items-center gap-1 inline-flex">
                  <Link2 size={10} /> {stats.linked} привязано к журналу поверок
                </span>
              )}
            </div>
          </div>
        )}
      </div>

      {/* Модалка создания/редактирования */}
      {showModal && (
        <FormModal
          instrument={modalInstrument as Instrument | null}
          prefillVerificationEquipmentId={prefillVeId}
          veOptions={veOptions}
          engineers={engineers}
          onClose={() => { setShowModal(false); setPrefillVeId(null); }}
          onSave={() => { setShowModal(false); setPrefillVeId(null); loadAll(); }}
        />
      )}

      {/* Подтверждение удаления */}
      {deleteConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.7)', backdropFilter: 'blur(4px)' }}>
          <div className="w-full max-w-sm mx-4 rounded-2xl p-6 shadow-2xl" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border-subtle)' }}>
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-red-400/10 flex items-center justify-center">
                <Trash2 size={18} className="text-red-400" />
              </div>
              <div>
                <h3 className="font-semibold text-sm" style={{ color: 'var(--text-primary)' }}>Удалить прибор?</h3>
                <p className="text-xs mt-0.5" style={{ color: 'var(--text-muted)' }}>{deleteConfirm.name}</p>
              </div>
            </div>
            <div className="flex gap-2 justify-end">
              <button onClick={() => setDeleteConfirm(null)} className="px-4 py-2 rounded-lg text-sm font-medium hover:bg-white/5 transition-colors" style={{ color: 'var(--text-muted)' }}>
                Отмена
              </button>
              <button onClick={() => handleDelete(deleteConfirm)} className="px-4 py-2 rounded-lg text-sm font-semibold text-white bg-red-500 hover:bg-red-600 transition-colors">
                Удалить
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default InstrumentRegistry;
