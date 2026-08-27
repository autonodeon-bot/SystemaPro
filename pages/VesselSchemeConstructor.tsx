/**
 * Конструктор карт контроля: выбор из 44 форм ТО → параметры → PNG / DrawingTemplate.
 */
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Download, Save, RefreshCw, Plus, Trash2, ArrowLeft } from 'lucide-react';
import { API_BASE } from '../constants';

type Orientation = 'horizontal' | 'vertical';
type WeldPreset = 'ring_only' | 'long_plus_rings' | 'multi_shell' | 'custom';
type HeadType = 'elliptical' | 'flat' | 'hemispherical';

interface Nozzle {
  id: string;
  dn: number | string;
  position: number;
  circ?: number;
  side: string;
  place?: string;
  label: string;
  purpose?: string;
}

interface Weld {
  id: string;
  kind: 'circumferential' | 'longitudinal';
  position: number;
  label: string;
}

interface KindMeta {
  code: string;
  form_id: string;
  title: string;
  category: string;
  group: string;
  family: string;
  family_title?: string;
  defaults?: Record<string, unknown>;
}

const authHeaders = (): Record<string, string> => {
  const token =
    localStorage.getItem('token') ||
    localStorage.getItem('auth_token') ||
    sessionStorage.getItem('auth_token');
  return token ? { Authorization: `Bearer ${token}` } : {};
};

const PRESET_LABELS: Record<WeldPreset, string> = {
  ring_only: 'Только кольцевые (К)',
  long_plus_rings: 'Продольные вразбежку (~½) + кольцевые',
  multi_shell: 'Несколько обечаек, часть с двумя продольными',
  custom: 'Свой список швов',
};

const GROUP_LABELS: Record<string, string> = {
  емкостное: 'Ёмкостное',
  трубопроводы: 'Трубопроводы',
  грузоподъёмное: 'Грузоподъёмное',
  машины: 'Машины / агрегаты',
  котлы: 'Котлы',
  арматура: 'Арматура',
  электрооборудование: 'Электрооборудование',
  станции: 'Станции / узлы',
  башни: 'Башни / трубы / факел',
  прочее: 'Прочее',
};

const VESSEL_FAMILIES = new Set(['vessel_development']);
const PIPE_FAMILIES = new Set(['pipeline']);
const COUNT_FAMILIES = new Set([
  'vessel_development',
  'pipeline',
  'tank',
  'tower',
  'boiler',
  'crane',
  'station',
  'electrical',
  'machinery',
  'valve',
  'generic',
]);

const COUNT_LABELS: Record<string, string> = {
  vessel_development: 'Обечаек корпуса',
  pipeline: 'Секций / стыков',
  tank: 'Поясов стенки',
  tower: 'Поясов ствола',
  boiler: 'Зон / секций котла',
  crane: 'Пролётов / зон контроля',
  station: 'Узлов на схеме',
  electrical: 'Ячеек / зон',
  machinery: 'Узлов агрегата',
  valve: 'Узлов арматуры',
  generic: 'Зон контроля',
};

const FAMILY_HINTS: Record<string, string> = {
  vessel_development: 'Развёртка корпуса: днища — круги, продольные швы вразбежку.',
  pipeline: 'Линейная схема трубопровода / коллектора со стыками К1…Kn.',
  tank: 'План резервуара + развёртка стенки с поясами.',
  tower: 'Ствол трубы / факела с поясами и продольными швами.',
  boiler: 'Схема котла / котельного оборудования по зонам контроля.',
  crane: 'Схема ГПМ / подкрановых путей по пролётам.',
  station: 'План станции / узла с обозначением блоков.',
  electrical: 'Схема электрооборудования / щитов / кабельных линий.',
  machinery: 'Схема агрегата (ГПА, нагнетатель, двигатель) по узлам.',
  valve: 'Схема арматуры / фонтанной ёлки / обвязки.',
  generic: 'Общая карта контроля объекта по зонам.',
};

let _uid = 0;
const uid = (p: string) => `${p}${++_uid}`;

const VesselSchemeConstructor: React.FC = () => {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const equipmentId = params.get('equipment_id') || '';
  const presetKind = params.get('kind') || params.get('form_id') || '';

  const [step, setStep] = useState<'kind' | 'params'>(presetKind ? 'params' : 'kind');
  const [kinds, setKinds] = useState<KindMeta[]>([]);
  const [groupOrder, setGroupOrder] = useState<string[]>(Object.keys(GROUP_LABELS));
  const [equipmentKind, setEquipmentKind] = useState(presetKind || 'vessel');
  const [kindMeta, setKindMeta] = useState<KindMeta | null>(null);

  const [orientation, setOrientation] = useState<Orientation>('vertical');
  const [shellLength, setShellLength] = useState(1);
  const [shellDiameter, setShellDiameter] = useState(0.5);
  const [shellCount, setShellCount] = useState(3);
  const [headType, setHeadType] = useState<HeadType>('elliptical');
  const [weldPreset, setWeldPreset] = useState<WeldPreset>('multi_shell');
  const [title, setTitle] = useState('Карта контроля');
  const [nozzles, setNozzles] = useState<Nozzle[]>([
    { id: 'N1', dn: 50, position: 0.35, side: 'body', label: 'Пт1', purpose: 'вход нефти' },
  ]);
  const [welds, setWelds] = useState<Weld[]>([]);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saveName, setSaveName] = useState('Карта контроля (конструктор)');
  const [savedId, setSavedId] = useState<string | null>(null);
  const [filter, setFilter] = useState('');

  const family = kindMeta?.family || 'generic';
  const showVesselParams = VESSEL_FAMILIES.has(family);
  const showPipelineParams = PIPE_FAMILIES.has(family);
  const showCount = COUNT_FAMILIES.has(family);
  const showWelds =
    showVesselParams || showPipelineParams || family === 'tank' || family === 'tower' || family === 'boiler';
  const showNozzles = showVesselParams || showPipelineParams || family === 'tank' || family === 'valve';
  const countLabel = COUNT_LABELS[family] || 'Зон контроля';
  const familyHint = FAMILY_HINTS[family] || FAMILY_HINTS.generic;

  const applyKindMeta = useCallback((meta: KindMeta) => {
    setEquipmentKind(meta.code);
    setKindMeta(meta);
    const d = meta.defaults || {};
    const t = `Карта контроля: ${meta.title}`;
    setTitle(t);
    setSaveName(`${meta.title} (конструктор)`);
    if (typeof d.orientation === 'string') {
      setOrientation(d.orientation === 'horizontal' ? 'horizontal' : 'vertical');
    } else if (meta.family === 'pipeline' || meta.family === 'crane') {
      setOrientation('horizontal');
    } else {
      setOrientation('vertical');
    }
    if (typeof d.shell_count === 'number') setShellCount(d.shell_count);
    else if (meta.family === 'pipeline') setShellCount(4);
    else if (meta.family === 'vessel_development') setShellCount(3);
    if (typeof d.weld_preset === 'string') setWeldPreset(d.weld_preset as WeldPreset);
    else if (meta.family === 'pipeline') setWeldPreset('ring_only');
    else setWeldPreset('multi_shell');
    setStep('params');
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`${API_BASE}/api/vessel-scheme/kinds`, { headers: authHeaders() });
        if (!res.ok) return;
        const data = await res.json();
        const items = (data.items || []) as KindMeta[];
        if (cancelled || !items.length) return;
        setKinds(items);
        if (Array.isArray(data.groups) && data.groups.length) setGroupOrder(data.groups);
        const found =
          items.find((k) => k.code === presetKind) ||
          items.find((k) => k.form_id === presetKind) ||
          items.find((k) => k.form_id === `to-${presetKind}`);
        if (found) applyKindMeta(found);
      } catch {
        /* ignore */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [presetKind, applyKindMeta]);

  useEffect(() => {
    if (!equipmentId || presetKind || !kinds.length) return;
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`${API_BASE}/api/equipment/${equipmentId}`, { headers: authHeaders() });
        if (!res.ok) return;
        const eq = await res.json();
        const code = String(eq.type_code || eq.equipment_type_code || '')
          .toLowerCase()
          .replace(/-/g, '_');
        const found = kinds.find((k) => k.code === code);
        if (found && !cancelled) applyKindMeta(found);
      } catch {
        /* ignore */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [equipmentId, presetKind, kinds, applyKindMeta]);

  const body = useMemo(
    () => ({
      equipment_kind: equipmentKind,
      form_id: kindMeta?.form_id,
      orientation,
      shell_length: shellLength,
      shell_diameter: shellDiameter,
      shell_count: shellCount,
      segment_count: shellCount,
      head_type: headType,
      weld_preset: weldPreset,
      title,
      nozzles: showNozzles ? nozzles : [],
      welds: weldPreset === 'custom' ? welds : [],
      width: 1200,
      height: 1100,
    }),
    [
      equipmentKind,
      kindMeta,
      orientation,
      shellLength,
      shellDiameter,
      shellCount,
      headType,
      weldPreset,
      title,
      nozzles,
      welds,
      showNozzles,
    ],
  );

  const refreshPreview = useCallback(async () => {
    if (step !== 'params') return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/api/vessel-scheme/render`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...authHeaders() },
        body: JSON.stringify(body),
      });
      if (!res.ok) throw new Error((await res.text()) || res.statusText);
      const blob = await res.blob();
      setPreviewUrl((prev) => {
        if (prev) URL.revokeObjectURL(prev);
        return URL.createObjectURL(blob);
      });
    } catch (e: any) {
      setError(e?.message || String(e));
    } finally {
      setBusy(false);
    }
  }, [body, step]);

  useEffect(() => {
    if (step !== 'params') return;
    const t = setTimeout(() => void refreshPreview(), 350);
    return () => clearTimeout(t);
  }, [refreshPreview, step]);

  useEffect(() => {
    return () => {
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [previewUrl]);

  const downloadPng = () => {
    if (!previewUrl) return;
    const a = document.createElement('a');
    a.href = previewUrl;
    a.download = `${saveName || 'scheme'}.png`;
    a.click();
  };

  const saveTemplate = async () => {
    setBusy(true);
    setError(null);
    setSavedId(null);
    try {
      const res = await fetch(`${API_BASE}/api/vessel-scheme/save-template`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...authHeaders() },
        body: JSON.stringify({
          ...body,
          name: saveName || title,
          equipment_id: equipmentId || null,
          create_points: true,
        }),
      });
      if (!res.ok) throw new Error((await res.text()) || res.statusText);
      const data = await res.json();
      setSavedId(data.id);
    } catch (e: any) {
      setError(e?.message || String(e));
    } finally {
      setBusy(false);
    }
  };

  const filteredKinds = useMemo(() => {
    const q = filter.trim().toLowerCase();
    if (!q) return kinds;
    return kinds.filter(
      (k) =>
        k.title.toLowerCase().includes(q) ||
        k.code.includes(q) ||
        (k.form_id || '').includes(q) ||
        String(k.form_id || '').replace('to-', '') === q,
    );
  }, [kinds, filter]);

  if (step === 'kind') {
    return (
      <div className="p-4 md:p-6 max-w-5xl mx-auto">
        <div className="flex flex-wrap items-center gap-3 mb-4">
          <button type="button" className="ind-btn ind-btn--ghost" onClick={() => navigate('/drawing-templates')}>
            <ArrowLeft size={16} /> Шаблоны чертежей
          </button>
          <h1 className="text-xl font-semibold text-app-text">Конструктор карт контроля</h1>
          <span className="text-xs text-app-text3">{kinds.length ? `${kinds.length} видов · 44 формы ТО` : '…'}</span>
        </div>
        <p className="text-sm text-app-text2 mb-3">
          Выберите тип оборудования по форме технического отчёта (Приложение ТО). Дальше задаются параметры
          схемы.
        </p>
        <input
          className="ind-input w-full mb-4"
          placeholder="Поиск: название, код или to-12…"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
        <div className="space-y-6">
          {groupOrder.map((g) => {
            const items = filteredKinds.filter((k) => k.group === g);
            if (!items.length) return null;
            return (
              <div key={g}>
                <h2 className="text-sm font-semibold text-app-text2 mb-2 uppercase tracking-wide">
                  {GROUP_LABELS[g] || g}
                </h2>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {items.map((k) => (
                    <button
                      key={k.code}
                      type="button"
                      className="ind-card p-3 text-left hover:border-accent border border-app-border transition-colors"
                      onClick={() => applyKindMeta(k)}
                    >
                      <div className="font-semibold text-app-text text-sm">{k.title}</div>
                      <div className="text-xs text-app-text3 mt-1 flex gap-2 flex-wrap">
                        <span className="font-mono">{k.form_id}</span>
                        <span>·</span>
                        <span>{k.family_title || k.family}</span>
                      </div>
                    </button>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    );
  }

  return (
    <div className="p-4 md:p-6 max-w-7xl mx-auto">
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <button type="button" className="ind-btn ind-btn--ghost" onClick={() => setStep('kind')}>
          <ArrowLeft size={16} /> Тип оборудования
        </button>
        <h1 className="text-xl font-semibold text-app-text">{kindMeta?.title || 'Конструктор'}</h1>
        {kindMeta?.form_id && (
          <span className="text-xs px-2 py-1 rounded bg-app-soft text-app-text2 font-mono">{kindMeta.form_id}</span>
        )}
        <span className="text-xs px-2 py-1 rounded bg-app-soft text-app-text3">{family}</span>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="ind-card p-4 space-y-3">
          <label className="block text-sm text-app-text2">
            Название схемы
            <input className="ind-input mt-1 w-full" value={title} onChange={(e) => setTitle(e.target.value)} />
          </label>

          {showVesselParams && (
            <>
              <div className="grid grid-cols-2 gap-3">
                <label className="block text-sm text-app-text2">
                  Ориентация
                  <select
                    className="ind-input mt-1 w-full"
                    value={orientation}
                    onChange={(e) => setOrientation(e.target.value as Orientation)}
                  >
                    <option value="vertical">Вертикальный</option>
                    <option value="horizontal">Горизонтальный</option>
                  </select>
                </label>
                <label className="block text-sm text-app-text2">
                  Тип днищ
                  <select
                    className="ind-input mt-1 w-full"
                    value={headType}
                    onChange={(e) => setHeadType(e.target.value as HeadType)}
                  >
                    <option value="elliptical">Эллиптические</option>
                    <option value="hemispherical">Полусферические</option>
                    <option value="flat">Плоские</option>
                  </select>
                </label>
              </div>
              <div className="grid grid-cols-3 gap-3">
                <label className="block text-sm text-app-text2">
                  Длина (отн.)
                  <input
                    type="number"
                    step="0.1"
                    min="0.2"
                    className="ind-input mt-1 w-full"
                    value={shellLength}
                    onChange={(e) => setShellLength(Number(e.target.value) || 1)}
                  />
                </label>
                <label className="block text-sm text-app-text2">
                  Диаметр (отн.)
                  <input
                    type="number"
                    step="0.05"
                    min="0.15"
                    className="ind-input mt-1 w-full"
                    value={shellDiameter}
                    onChange={(e) => setShellDiameter(Number(e.target.value) || 0.5)}
                  />
                </label>
                <label className="block text-sm text-app-text2">
                  Обечаек
                  <input
                    type="number"
                    min="1"
                    max="12"
                    className="ind-input mt-1 w-full"
                    value={shellCount}
                    onChange={(e) => setShellCount(Math.max(1, Number(e.target.value) || 1))}
                  />
                </label>
              </div>
              <p className="text-xs text-app-text3">
                Развёртка: днища — полные круги; продольные швы смещены ~на половину соседней обечайки.
              </p>
            </>
          )}

          {showPipelineParams && (
            <div className="grid grid-cols-2 gap-3">
              <label className="block text-sm text-app-text2">
                Диаметр (отн.)
                <input
                  type="number"
                  step="0.05"
                  min="0.15"
                  className="ind-input mt-1 w-full"
                  value={shellDiameter}
                  onChange={(e) => setShellDiameter(Number(e.target.value) || 0.5)}
                />
              </label>
              <label className="block text-sm text-app-text2">
                Секций
                <input
                  type="number"
                  min="1"
                  max="20"
                  className="ind-input mt-1 w-full"
                  value={shellCount}
                  onChange={(e) => setShellCount(Math.max(1, Number(e.target.value) || 1))}
                />
              </label>
            </div>
          )}

          {showCount && !showVesselParams && !showPipelineParams && (
            <label className="block text-sm text-app-text2">
              {countLabel}
              <input
                type="number"
                min="1"
                max="20"
                className="ind-input mt-1 w-full"
                value={shellCount}
                onChange={(e) => setShellCount(Math.max(1, Number(e.target.value) || 1))}
              />
            </label>
          )}

          {!showVesselParams && !showPipelineParams && (
            <p className="text-sm text-app-text2">{familyHint}</p>
          )}

          {showWelds && (
            <label className="block text-sm text-app-text2">
              Схема сварки / стыков
              <select
                className="ind-input mt-1 w-full"
                value={weldPreset}
                onChange={(e) => setWeldPreset(e.target.value as WeldPreset)}
              >
                {(Object.keys(PRESET_LABELS) as WeldPreset[])
                  .filter((k) => (showPipelineParams ? k === 'ring_only' || k === 'custom' : true))
                  .map((k) => (
                    <option key={k} value={k}>
                      {PRESET_LABELS[k]}
                    </option>
                  ))}
              </select>
            </label>
          )}

          {weldPreset === 'custom' && showWelds && (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm text-app-text2">Швы</span>
                <button
                  type="button"
                  className="ind-btn ind-btn--ghost text-sm"
                  onClick={() =>
                    setWelds((w) => [
                      ...w,
                      { id: uid('C'), kind: 'circumferential', position: 0.5, label: `К${w.length + 1}` },
                    ])
                  }
                >
                  <Plus size={14} /> Шов
                </button>
              </div>
              {welds.map((w, idx) => (
                <div key={w.id} className="flex flex-wrap gap-2 items-center">
                  <input
                    className="ind-input w-20"
                    value={w.label}
                    onChange={(e) => {
                      const v = e.target.value;
                      setWelds((arr) => arr.map((x, i) => (i === idx ? { ...x, label: v } : x)));
                    }}
                  />
                  <select
                    className="ind-input"
                    value={w.kind}
                    onChange={(e) => {
                      const v = e.target.value as Weld['kind'];
                      setWelds((arr) => arr.map((x, i) => (i === idx ? { ...x, kind: v } : x)));
                    }}
                  >
                    <option value="circumferential">Кольцевой</option>
                    <option value="longitudinal">Продольный</option>
                  </select>
                  <input
                    type="number"
                    step="0.05"
                    min="0"
                    max="1"
                    className="ind-input w-24"
                    value={w.position}
                    onChange={(e) => {
                      const v = Number(e.target.value);
                      setWelds((arr) => arr.map((x, i) => (i === idx ? { ...x, position: v } : x)));
                    }}
                  />
                  <button
                    type="button"
                    className="ind-btn ind-btn--ghost"
                    onClick={() => setWelds((arr) => arr.filter((_, i) => i !== idx))}
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              ))}
            </div>
          )}

          {showNozzles && (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm text-app-text2">Патрубки</span>
                <button
                  type="button"
                  className="ind-btn ind-btn--ghost text-sm"
                  onClick={() =>
                    setNozzles((n) => [
                      ...n,
                      {
                        id: uid('N'),
                        dn: 50,
                        position: Math.min(0.92, 0.15 + n.length * 0.14),
                        circ: 0.2 + (n.length % 4) * 0.2,
                        side: 'body',
                        place: 'body',
                        label: `Пт${n.length + 1}`,
                        purpose: 'вход нефти',
                      },
                    ])
                  }
                >
                  <Plus size={14} /> Патрубок
                </button>
              </div>
              {nozzles.map((n, idx) => (
                <div key={n.id} className="flex flex-wrap gap-2 items-center">
                  <input
                    className="ind-input w-28"
                    value={n.label}
                    onChange={(e) => {
                      const v = e.target.value;
                      setNozzles((arr) => arr.map((x, i) => (i === idx ? { ...x, label: v } : x)));
                    }}
                  />
                  <select
                    className="ind-input w-40"
                    value={n.purpose || ''}
                    onChange={(e) => {
                      const v = e.target.value;
                      setNozzles((arr) => arr.map((x, i) => (i === idx ? { ...x, purpose: v } : x)));
                    }}
                  >
                    <option value="">Назначение</option>
                    <option value="вход нефти">вход нефти</option>
                    <option value="вход газа">вход газа</option>
                    <option value="вход ДЭГа">вход ДЭГа</option>
                    <option value="выход нефти">выход нефти</option>
                    <option value="выход газа">выход газа</option>
                    <option value="выход ДЭГа">выход ДЭГа</option>
                    <option value="дренаж">дренаж</option>
                    <option value="люк-лаз">люк-лаз</option>
                    <option value="предохранительный клапан">предохранительный клапан</option>
                    <option value="КИП">КИП</option>
                  </select>
                  <input
                    className="ind-input w-20"
                    placeholder="DN"
                    value={n.dn}
                    onChange={(e) => {
                      const v = e.target.value;
                      setNozzles((arr) => arr.map((x, i) => (i === idx ? { ...x, dn: v } : x)));
                    }}
                  />
                  <input
                    type="number"
                    step="0.05"
                    min="0.05"
                    max="0.95"
                    className="ind-input w-24"
                    title="Положение вдоль оси 0–1"
                    value={n.position}
                    onChange={(e) => {
                      const v = Number(e.target.value);
                      setNozzles((arr) => arr.map((x, i) => (i === idx ? { ...x, position: v } : x)));
                    }}
                  />
                  <input
                    type="number"
                    step="0.05"
                    min="0.05"
                    max="0.95"
                    className="ind-input w-24"
                    title="Положение по окружности 0–1"
                    value={n.circ ?? 0.55}
                    onChange={(e) => {
                      const v = Number(e.target.value);
                      setNozzles((arr) => arr.map((x, i) => (i === idx ? { ...x, circ: v } : x)));
                    }}
                  />
                  <select
                    className="ind-input w-36"
                    value={n.place || 'body'}
                    onChange={(e) => {
                      const v = e.target.value;
                      setNozzles((arr) =>
                        arr.map((x, i) =>
                          i === idx
                            ? {
                                ...x,
                                place: v,
                                side: v === 'head_top' ? 'top' : v === 'head_bottom' ? 'bottom' : 'body',
                              }
                            : x
                        )
                      );
                    }}
                  >
                    <option value="body">Корпус</option>
                    <option value="head_top">Верх/лево днище</option>
                    <option value="head_bottom">Низ/право днище</option>
                  </select>
                  <button
                    type="button"
                    className="ind-btn ind-btn--ghost"
                    onClick={() => setNozzles((arr) => arr.filter((_, i) => i !== idx))}
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              ))}
            </div>
          )}

          <div className="flex flex-wrap gap-2 pt-2 border-t border-app-border">
            <button type="button" className="ind-btn" onClick={() => void refreshPreview()} disabled={busy}>
              <RefreshCw size={16} /> Обновить
            </button>
            <button type="button" className="ind-btn ind-btn--ghost" onClick={downloadPng} disabled={!previewUrl}>
              <Download size={16} /> Скачать PNG
            </button>
          </div>

          <div className="space-y-2 pt-2">
            <label className="block text-sm text-app-text2">
              Имя в библиотеке шаблонов
              <input className="ind-input mt-1 w-full" value={saveName} onChange={(e) => setSaveName(e.target.value)} />
            </label>
            <button
              type="button"
              className="ind-btn ind-btn--primary"
              onClick={() => void saveTemplate()}
              disabled={busy}
            >
              <Save size={16} /> Сохранить в шаблоны чертежей
            </button>
            {savedId && (
              <p className="text-sm text-green-400">
                Сохранено — подставится в отчёт по оборудованию, если в обследовании нет своей схемы.{' '}
                <button type="button" className="underline" onClick={() => navigate('/drawing-templates')}>
                  Библиотека
                </button>
              </p>
            )}
          </div>

          {error && <p className="text-sm text-red-400 whitespace-pre-wrap">{error}</p>}
        </div>

        <div className="ind-card p-4">
          <div className="text-sm text-app-text2 mb-2">Предпросмотр</div>
          <div className="bg-white rounded border border-app-border min-h-[320px] flex items-center justify-center overflow-auto">
            {previewUrl ? (
              <img src={previewUrl} alt="Схема" className="max-w-full h-auto" />
            ) : (
              <span className="text-app-text3 text-sm">{busy ? 'Рендер…' : 'Нет превью'}</span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default VesselSchemeConstructor;
