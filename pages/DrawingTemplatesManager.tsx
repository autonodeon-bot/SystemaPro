/**
 * Менеджер шаблонов чертежей оборудования (П.2 ТЗ 2026-04).
 *
 * Возможности:
 *  - Список шаблонов (плотная industrial-таблица)
 *  - Загрузка нового шаблона (multipart PNG/JPG) с привязкой к типу/экземпляру
 *  - Редактор точек замера: клик по чертежу = добавить, drag = перенести,
 *    правая панель — редактирование label/type/expected value
 *  - Координаты точек — в процентах (0-100) от размеров оригинального изображения
 *  - Зум/пан через wheel и middle-drag
 */
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Upload, Trash2, Edit3, Save, Plus, X, ArrowLeft, Image as ImageIcon,
  Target, Search, Filter, ZoomIn, ZoomOut, RotateCcw,
} from 'lucide-react';
import { API_BASE } from '../constants';

// ─── Типы ──────────────────────────────────────────────────────────────────

type PointType = 'thickness' | 'ndt' | 'reference' | 'custom';

interface DrawingPoint {
  id?: string;
  label: string;
  point_type: PointType;
  x_percent: number;
  y_percent: number;
  expected_value?: number | null;
  notes?: string | null;
  sort_order?: number;
}

interface DrawingTemplateSummary {
  id: string;
  name: string;
  description?: string | null;
  category?: string | null;
  equipment_type_id?: string | null;
  equipment_id?: string | null;
  equipment_type_name?: string | null;
  equipment_name?: string | null;
  image_width?: number | null;
  image_height?: number | null;
  mime_type?: string | null;
  file_size?: number | null;
  version: number;
  is_active: boolean;
  points_count?: number;
  created_at?: string;
  updated_at?: string;
}

interface DrawingTemplateDetail extends DrawingTemplateSummary {
  points: DrawingPoint[];
}

interface EquipmentType {
  id: string;
  name: string;
  code?: string;
}

const CATEGORIES = ['vessel', 'pipeline', 'ndt_scheme', 'thickness_scheme', 'other'];
const CATEGORY_LABELS: Record<string, string> = {
  vessel: 'Сосуды',
  pipeline: 'Трубопроводы',
  ndt_scheme: 'Схема НК',
  thickness_scheme: 'Схема УЗТ',
  other: 'Прочее',
};

const POINT_TYPES: { value: PointType; label: string; color: string }[] = [
  { value: 'thickness', label: 'УЗТ / толщинометрия', color: 'var(--accent)' },
  { value: 'ndt', label: 'НК (ВИК, УЗК, ПВК)', color: 'var(--warning)' },
  { value: 'reference', label: 'Опорная', color: 'var(--text-muted)' },
  { value: 'custom', label: 'Произвольная', color: 'var(--success)' },
];

// ─── API helpers ──────────────────────────────────────────────────────────

/** Тот же ключ токена, что в AuthContext (`token`), плюс совместимость со старым `auth_token`. */
const authHeaders = (): Record<string, string> => {
  const token =
    localStorage.getItem('token') ||
    localStorage.getItem('auth_token') ||
    sessionStorage.getItem('auth_token');
  return token ? { Authorization: `Bearer ${token}` } : {};
};

async function apiJson<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: { ...(init?.headers || {}), ...authHeaders() },
  });
  if (!res.ok) {
    const txt = await res.text().catch(() => '');
    throw new Error(`${res.status}: ${txt || res.statusText}`);
  }
  if (res.status === 204) return undefined as unknown as T;
  return res.json();
}

// ─── Модалка загрузки ────────────────────────────────────────────────────

interface UploadModalProps {
  onClose: () => void;
  onCreated: (t: DrawingTemplateDetail) => void;
  equipmentTypes: EquipmentType[];
}

const UploadModal: React.FC<UploadModalProps> = ({ onClose, onCreated, equipmentTypes }) => {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState<string>('vessel');
  const [equipmentTypeId, setEquipmentTypeId] = useState<string>('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const dragOver = useRef(false);
  const [_dragState, setDragState] = useState(0);

  useEffect(() => {
    if (!file) { setPreview(null); return; }
    const url = URL.createObjectURL(file);
    setPreview(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  const pickFile = (f: File | null) => {
    if (!f) return;
    if (!['image/png', 'image/jpeg', 'image/jpg'].includes(f.type)) {
      setError('Поддерживаются только PNG и JPEG');
      return;
    }
    if (f.size > 10 * 1024 * 1024) {
      setError('Файл больше 10 МБ');
      return;
    }
    setError(null);
    setFile(f);
    if (!name) setName(f.name.replace(/\.[^.]+$/, ''));
  };

  const submit = async () => {
    if (!file || !name.trim()) {
      setError('Укажите имя и выберите файл');
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const fd = new FormData();
      fd.append('file', file);
      fd.append('name', name.trim());
      if (description.trim()) fd.append('description', description.trim());
      if (category) fd.append('category', category);
      if (equipmentTypeId) fd.append('equipment_type_id', equipmentTypeId);

      const res = await fetch(`${API_BASE}/api/drawing-templates`, {
        method: 'POST',
        headers: authHeaders(),
        body: fd,
      });
      if (!res.ok) {
        const txt = await res.text().catch(() => '');
        throw new Error(`${res.status}: ${txt || res.statusText}`);
      }
      const data: DrawingTemplateDetail = await res.json();
      onCreated(data);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 sp-fade-in">
      <div className="ind-panel w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        <div className="ind-panel-header">
          <span className="ind-panel-title">Загрузка шаблона чертежа</span>
          <button onClick={onClose} className="ind-btn ind-btn--sm" aria-label="Закрыть">
            <X size={14} />
          </button>
        </div>
        <div className="ind-panel-body space-y-4">
          {error && (
            <div className="ind-chip ind-chip--danger w-full" style={{ justifyContent: 'flex-start' }}>
              {error}
            </div>
          )}

          <div
            onDragOver={(e) => { e.preventDefault(); dragOver.current = true; setDragState((x) => x + 1); }}
            onDragLeave={() => { dragOver.current = false; setDragState((x) => x + 1); }}
            onDrop={(e) => {
              e.preventDefault();
              dragOver.current = false;
              setDragState((x) => x + 1);
              const f = e.dataTransfer.files?.[0];
              if (f) pickFile(f);
            }}
            className="relative rounded border border-dashed cursor-pointer transition-colors"
            style={{
              borderColor: dragOver.current ? 'var(--accent)' : 'var(--border-primary)',
              background: dragOver.current ? 'var(--accent-glow)' : 'var(--bg-tertiary)',
              minHeight: 180,
            }}
          >
            <input
              type="file"
              accept="image/png,image/jpeg"
              className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
              onChange={(e) => pickFile(e.target.files?.[0] || null)}
            />
            {preview ? (
              <img src={preview} alt="" className="w-full h-64 object-contain bg-black/30 rounded" />
            ) : (
              <div className="flex flex-col items-center justify-center h-[180px] gap-2 text-[var(--text-muted)]">
                <Upload size={32} />
                <span className="text-sm">Перетащите PNG / JPG сюда или нажмите для выбора</span>
                <span className="text-xs">Оптимально: 1500–2500 px по большей стороне, ≤ 10 МБ</span>
              </div>
            )}
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="ind-label">Название</label>
              <input
                className="ind-input"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Например: ГПА-25, схема УЗТ днища"
              />
            </div>
            <div>
              <label className="ind-label">Категория чертежа</label>
              <select
                className="ind-input"
                value={category}
                onChange={(e) => setCategory(e.target.value)}
              >
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>{CATEGORY_LABELS[c]}</option>
                ))}
              </select>
              <p className="text-xs text-[var(--text-muted)] mt-1">
                Для группировки и фильтра в списке (сосуд / трубопровод / схема НК и т.д.).
              </p>
            </div>
            <div className="md:col-span-2">
              <label className="ind-label">Тип оборудования из справочника (опционально)</label>
              <select
                className="ind-input"
                value={equipmentTypeId}
                onChange={(e) => setEquipmentTypeId(e.target.value)}
              >
                <option value="">— Универсальный шаблон —</option>
                {equipmentTypes.map((t) => (
                  <option key={t.id} value={t.id}>{t.name}</option>
                ))}
              </select>
              <p className="text-xs text-[var(--text-muted)] mt-1">
                Если выбран тип, шаблон удобнее подбирать к конкретным единицам этого типа; пусто — для любого оборудования.
              </p>
            </div>
            <div className="md:col-span-2">
              <label className="ind-label">Описание</label>
              <textarea
                className="ind-input ind-input--textarea"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Назначение, особенности"
              />
            </div>
          </div>

          <div className="flex items-center justify-end gap-2 pt-2">
            <button onClick={onClose} className="ind-btn">Отмена</button>
            <button
              onClick={submit}
              disabled={submitting || !file || !name.trim()}
              className="ind-btn ind-btn--primary"
            >
              <Save size={14} /> {submitting ? 'Загрузка...' : 'Создать шаблон'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

// ─── Редактор точек замера ────────────────────────────────────────────────

interface EditorProps {
  templateId: string;
  onBack: () => void;
  onSaved: (t: DrawingTemplateDetail) => void;
}

const DrawingEditor: React.FC<EditorProps> = ({ templateId, onBack, onSaved }) => {
  const [template, setTemplate] = useState<DrawingTemplateDetail | null>(null);
  const [points, setPoints] = useState<DrawingPoint[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [imgLoaded, setImgLoaded] = useState(false);
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [draggingPanStart, setDraggingPanStart] = useState<{ mx: number; my: number; px: number; py: number } | null>(null);
  const [draggingPointId, setDraggingPointId] = useState<string | null>(null);

  const canvasRef = useRef<HTMLDivElement | null>(null);
  const imgRef = useRef<HTMLImageElement | null>(null);

  const [blobImageUrl, setBlobImageUrl] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      setLoading(true);
      try {
        const data = await apiJson<DrawingTemplateDetail>(`/api/drawing-templates/${templateId}`);
        if (!active) return;
        setTemplate(data);
        setPoints(data.points || []);
      } catch (e) {
        console.error(e);
      } finally {
        if (active) setLoading(false);
      }
    })();
    return () => { active = false; };
  }, [templateId]);

  // Скачиваем изображение с Authorization, превращаем в blob URL
  useEffect(() => {
    if (!template) return;
    let active = true;
    let currentUrl: string | null = null;
    (async () => {
      try {
        const res = await fetch(
          `${API_BASE}/api/drawing-templates/${templateId}/image?v=${template.version}`,
          { headers: authHeaders() },
        );
        if (!res.ok) throw new Error(String(res.status));
        const blob = await res.blob();
        if (!active) return;
        currentUrl = URL.createObjectURL(blob);
        setBlobImageUrl(currentUrl);
      } catch (e) {
        console.error('Load image error', e);
      }
    })();
    return () => {
      active = false;
      if (currentUrl) URL.revokeObjectURL(currentUrl);
    };
  }, [template?.version, templateId]);

  const addPoint = (xp: number, yp: number) => {
    const existing = points.filter((p) => p.point_type === 'thickness').length;
    const label = `Т${existing + 1}`;
    const p: DrawingPoint = {
      id: (crypto as any).randomUUID?.() ?? `new-${Date.now()}-${Math.random()}`,
      label,
      point_type: 'thickness',
      x_percent: xp,
      y_percent: yp,
      sort_order: points.length,
    };
    setPoints((prev) => [...prev, p]);
    setSelectedId(p.id!);
  };

  const deletePoint = (id: string) => {
    setPoints((prev) => prev.filter((p) => p.id !== id));
    if (selectedId === id) setSelectedId(null);
  };

  const updatePoint = (id: string, patch: Partial<DrawingPoint>) => {
    setPoints((prev) => prev.map((p) => (p.id === id ? { ...p, ...patch } : p)));
  };

  // ── Вычисление % координат тапа по фактическому изображению ────────────
  const getPercentAt = (ev: React.MouseEvent): { xp: number; yp: number } | null => {
    const img = imgRef.current;
    if (!img) return null;
    const rect = img.getBoundingClientRect();
    const x = ev.clientX - rect.left;
    const y = ev.clientY - rect.top;
    if (x < 0 || y < 0 || x > rect.width || y > rect.height) return null;
    return { xp: (x / rect.width) * 100, yp: (y / rect.height) * 100 };
  };

  const onCanvasClick = (ev: React.MouseEvent) => {
    if (draggingPointId) return;
    const p = getPercentAt(ev);
    if (p) addPoint(p.xp, p.yp);
  };

  const onPointMouseDown = (ev: React.MouseEvent, id: string) => {
    ev.stopPropagation();
    setSelectedId(id);
    setDraggingPointId(id);
  };

  useEffect(() => {
    if (!draggingPointId) return;
    const onMove = (e: MouseEvent) => {
      const img = imgRef.current;
      if (!img) return;
      const rect = img.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const xp = Math.max(0, Math.min(100, (x / rect.width) * 100));
      const yp = Math.max(0, Math.min(100, (y / rect.height) * 100));
      setPoints((prev) => prev.map((p) => (p.id === draggingPointId ? { ...p, x_percent: xp, y_percent: yp } : p)));
    };
    const onUp = () => setDraggingPointId(null);
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    return () => {
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    };
  }, [draggingPointId]);

  // ── Zoom & Pan (wheel + middle-button drag) ────────────────────────────
  const onWheel = (ev: React.WheelEvent) => {
    ev.preventDefault();
    const delta = -ev.deltaY * 0.0015;
    setZoom((z) => Math.max(0.3, Math.min(5, z + delta)));
  };
  const resetView = () => { setZoom(1); setPan({ x: 0, y: 0 }); };

  const onPanMouseDown = (ev: React.MouseEvent) => {
    if (ev.button !== 1) return; // middle button
    ev.preventDefault();
    setDraggingPanStart({ mx: ev.clientX, my: ev.clientY, px: pan.x, py: pan.y });
  };
  useEffect(() => {
    if (!draggingPanStart) return;
    const onMove = (e: MouseEvent) => {
      setPan({
        x: draggingPanStart.px + (e.clientX - draggingPanStart.mx),
        y: draggingPanStart.py + (e.clientY - draggingPanStart.my),
      });
    };
    const onUp = () => setDraggingPanStart(null);
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    return () => {
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    };
  }, [draggingPanStart]);

  const save = async () => {
    setSaving(true);
    try {
      const body = {
        points: points.map((p, idx) => ({
          label: p.label,
          point_type: p.point_type,
          x_percent: Number(p.x_percent.toFixed(3)),
          y_percent: Number(p.y_percent.toFixed(3)),
          expected_value: p.expected_value ?? null,
          notes: p.notes ?? null,
          sort_order: idx,
        })),
      };
      const updated = await apiJson<DrawingTemplateDetail>(
        `/api/drawing-templates/${templateId}/points`,
        {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        },
      );
      setTemplate(updated);
      setPoints(updated.points || []);
      onSaved(updated);
    } catch (e) {
      alert(`Ошибка сохранения: ${(e as Error).message}`);
    } finally {
      setSaving(false);
    }
  };

  if (loading || !template) {
    return (
      <div className="ind-panel">
        <div className="ind-panel-body text-center text-[var(--text-muted)]">Загрузка...</div>
      </div>
    );
  }

  const selected = points.find((p) => p.id === selectedId) || null;

  return (
    <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-4">
      {/* ── Левая часть: чертёж ── */}
      <div className="ind-panel">
        <div className="ind-panel-header">
          <div className="flex items-center gap-2">
            <button onClick={onBack} className="ind-btn ind-btn--sm">
              <ArrowLeft size={14} /> Назад
            </button>
            <span className="ind-panel-title">{template.name}</span>
            <span className="ind-chip ind-mono">v{template.version}</span>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={() => setZoom((z) => Math.max(0.3, z - 0.2))} className="ind-btn ind-btn--sm">
              <ZoomOut size={14} />
            </button>
            <span className="text-xs ind-mono text-[var(--text-muted)] w-12 text-center">
              {Math.round(zoom * 100)}%
            </span>
            <button onClick={() => setZoom((z) => Math.min(5, z + 0.2))} className="ind-btn ind-btn--sm">
              <ZoomIn size={14} />
            </button>
            <button onClick={resetView} className="ind-btn ind-btn--sm" title="Сброс">
              <RotateCcw size={14} />
            </button>
            <button onClick={save} disabled={saving} className="ind-btn ind-btn--primary ind-btn--sm">
              <Save size={14} /> {saving ? '...' : 'Сохранить'}
            </button>
          </div>
        </div>
        <div
          className="ind-drawing-canvas"
          ref={canvasRef}
          onWheel={onWheel}
          onMouseDown={onPanMouseDown}
          style={{ height: 'calc(100vh - 220px)', cursor: draggingPanStart ? 'grabbing' : 'crosshair' }}
        >
          <div
            className="absolute inset-0 flex items-center justify-center"
            style={{
              transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
              transformOrigin: 'center center',
              transition: draggingPanStart ? 'none' : 'transform 0.1s ease-out',
            }}
          >
            <div className="relative" onClick={onCanvasClick}>
              {blobImageUrl ? (
                <img
                  ref={imgRef}
                  src={blobImageUrl}
                  alt={template.name}
                  onLoad={() => setImgLoaded(true)}
                  className="max-w-full max-h-[calc(100vh-260px)] block pointer-events-auto"
                  draggable={false}
                />
              ) : (
                <div className="text-[var(--text-muted)] text-sm">Загрузка изображения...</div>
              )}
              {imgLoaded && points.map((p) => {
                const typeClass = `ind-drawing-point--${p.point_type}`;
                const sel = p.id === selectedId ? ' ind-drawing-point--selected' : '';
                return (
                  <div
                    key={p.id}
                    className={`ind-drawing-point ${typeClass}${sel}`}
                    style={{ left: `${p.x_percent}%`, top: `${p.y_percent}%` }}
                    onMouseDown={(e) => onPointMouseDown(e, p.id!)}
                    onClick={(e) => e.stopPropagation()}
                    title={`${p.label}${p.expected_value ? ` (${p.expected_value})` : ''}`}
                  >
                    {p.label.length > 3 ? p.label.slice(0, 3) : p.label}
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </div>

      {/* ── Правая панель: список точек ── */}
      <div className="ind-panel flex flex-col" style={{ maxHeight: 'calc(100vh - 140px)' }}>
        <div className="ind-panel-header">
          <span className="ind-panel-title">
            <Target size={12} className="inline mr-1" />
            Точки замера ({points.length})
          </span>
          <button
            onClick={() => setPoints([])}
            disabled={points.length === 0}
            className="ind-btn ind-btn--sm ind-btn--danger"
          >
            <Trash2 size={12} /> Очистить
          </button>
        </div>

        <div className="flex-1 overflow-y-auto">
          {points.length === 0 ? (
            <div className="p-6 text-center text-[var(--text-muted)] text-sm">
              Кликните по чертежу, чтобы добавить точку замера.
              <br />
              <span className="text-xs">Средняя кнопка мыши — панорамирование, колесо — зум.</span>
            </div>
          ) : (
            <table className="ind-table">
              <thead>
                <tr>
                  <th>Метка</th>
                  <th>Тип</th>
                  <th>X%</th>
                  <th>Y%</th>
                  <th style={{ width: 32 }}></th>
                </tr>
              </thead>
              <tbody>
                {points.map((p) => (
                  <tr
                    key={p.id}
                    onClick={() => setSelectedId(p.id!)}
                    className={p.id === selectedId ? 'bg-[var(--bg-tertiary)]' : ''}
                    style={{ cursor: 'pointer' }}
                  >
                    <td className="ind-mono font-semibold">{p.label}</td>
                    <td className="text-xs text-[var(--text-secondary)]">
                      {POINT_TYPES.find((t) => t.value === p.point_type)?.label.split(' ')[0]}
                    </td>
                    <td className="ind-mono text-xs">{p.x_percent.toFixed(1)}</td>
                    <td className="ind-mono text-xs">{p.y_percent.toFixed(1)}</td>
                    <td>
                      <button
                        className="ind-btn ind-btn--sm ind-btn--danger"
                        onClick={(e) => { e.stopPropagation(); deletePoint(p.id!); }}
                        title="Удалить"
                      >
                        <Trash2 size={11} />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* Редактор выбранной точки */}
        {selected && (
          <div className="border-t border-[var(--border-subtle)] p-3 space-y-3">
            <div className="ind-panel-title">Параметры точки</div>
            <div>
              <label className="ind-label">Метка</label>
              <input
                className="ind-input"
                value={selected.label}
                onChange={(e) => updatePoint(selected.id!, { label: e.target.value })}
              />
            </div>
            <div>
              <label className="ind-label">Тип</label>
              <select
                className="ind-input"
                value={selected.point_type}
                onChange={(e) => updatePoint(selected.id!, { point_type: e.target.value as PointType })}
              >
                {POINT_TYPES.map((t) => (
                  <option key={t.value} value={t.value}>{t.label}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="ind-label">Проектное значение (мм)</label>
              <input
                type="number"
                step="0.1"
                className="ind-input ind-mono"
                value={selected.expected_value ?? ''}
                onChange={(e) => updatePoint(selected.id!, { expected_value: e.target.value === '' ? null : Number(e.target.value) })}
                placeholder="—"
              />
            </div>
            <div>
              <label className="ind-label">Примечание</label>
              <textarea
                className="ind-input ind-input--textarea"
                value={selected.notes ?? ''}
                onChange={(e) => updatePoint(selected.id!, { notes: e.target.value || null })}
              />
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

// ─── Главная страница ────────────────────────────────────────────────────

const DrawingTemplatesManager: React.FC = () => {
  const [items, setItems] = useState<DrawingTemplateSummary[]>([]);
  const [equipmentTypes, setEquipmentTypes] = useState<EquipmentType[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [editorId, setEditorId] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string>('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [list, types] = await Promise.all([
        apiJson<{ items: DrawingTemplateSummary[] }>('/api/drawing-templates?active_only=true'),
        apiJson<EquipmentType[] | { items: EquipmentType[] }>('/api/equipment-types').catch(() => ({ items: [] })),
      ]);
      setItems(list.items || []);
      const rawTypes: any = types;
      setEquipmentTypes(Array.isArray(rawTypes) ? rawTypes : (rawTypes?.items || []));
    } catch (e) {
      console.error(e);
      setItems([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const filtered = useMemo(() => {
    return items.filter((t) => {
      if (categoryFilter && t.category !== categoryFilter) return false;
      if (search) {
        const s = search.toLowerCase();
        return (
          t.name.toLowerCase().includes(s) ||
          (t.equipment_type_name || '').toLowerCase().includes(s) ||
          (t.equipment_name || '').toLowerCase().includes(s)
        );
      }
      return true;
    });
  }, [items, search, categoryFilter]);

  const removeTemplate = async (id: string) => {
    if (!confirm('Удалить шаблон? (soft-delete, можно восстановить)')) return;
    try {
      await apiJson(`/api/drawing-templates/${id}`, { method: 'DELETE' });
      setItems((prev) => prev.filter((t) => t.id !== id));
    } catch (e) {
      alert(`Ошибка: ${(e as Error).message}`);
    }
  };

  if (editorId) {
    return (
      <div className="p-4 sp-fade-in-up">
        <DrawingEditor
          templateId={editorId}
          onBack={() => setEditorId(null)}
          onSaved={() => load()}
        />
      </div>
    );
  }

  return (
    <div className="p-4 sp-fade-in-up space-y-4">
      {/* Header */}
      <div className="ind-panel">
        <div className="ind-panel-header">
          <span className="ind-panel-title">
            <ImageIcon size={12} className="inline mr-1" />
            Шаблоны чертежей оборудования
          </span>
          <button onClick={() => setUploadOpen(true)} className="ind-btn ind-btn--primary ind-btn--sm">
            <Plus size={14} /> Загрузить шаблон
          </button>
        </div>
        <div className="ind-panel-body flex flex-wrap items-center gap-3">
          <div className="relative flex-1 min-w-[220px]">
            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
            <input
              className="ind-input pl-9"
              placeholder="Поиск по названию, типу оборудования..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <div className="flex items-center gap-2">
            <Filter size={14} className="text-[var(--text-muted)]" />
            <select
              className="ind-input"
              style={{ width: 180 }}
              value={categoryFilter}
              onChange={(e) => setCategoryFilter(e.target.value)}
            >
              <option value="">Все категории</option>
              {CATEGORIES.map((c) => (
                <option key={c} value={c}>{CATEGORY_LABELS[c]}</option>
              ))}
            </select>
          </div>
          <div className="ind-chip ind-mono">
            {filtered.length} / {items.length}
          </div>
        </div>
      </div>

      <div className="ind-panel">
        <div className="ind-panel-body text-sm text-[var(--text-secondary)] space-y-2 leading-relaxed">
          <p className="font-semibold text-[var(--text-primary)]">Как загрузить чертёж и задать категорию</p>
          <ol className="list-decimal list-inside space-y-1 text-[var(--text-muted)]">
            <li>Нажмите «Загрузить шаблон».</li>
            <li>Выберите PNG или JPEG (до 10 МБ) или перетащите файл в область загрузки.</li>
            <li>Укажите название, при необходимости описание.</li>
            <li>В поле «Категория чертежа» выберите вид схемы (сосуды, трубопроводы, схема НК и т.д.).</li>
            <li>При необходимости укажите тип оборудования из справочника или оставьте универсальный шаблон.</li>
            <li>После создания откройте редактор точек и расставьте точки замера на изображении.</li>
          </ol>
        </div>
      </div>

      {/* Table */}
      <div className="ind-panel">
        {loading ? (
          <div className="ind-panel-body text-center text-[var(--text-muted)]">Загрузка...</div>
        ) : filtered.length === 0 ? (
          <div className="ind-panel-body text-center text-[var(--text-muted)] py-12">
            <ImageIcon size={40} className="mx-auto mb-3 opacity-50" />
            <div className="text-sm">Шаблонов пока нет</div>
            <div className="text-xs mt-1">Загрузите первый чертёж, чтобы начать работу</div>
          </div>
        ) : (
          <table className="ind-table">
            <thead>
              <tr>
                <th style={{ width: 56 }}></th>
                <th>Название</th>
                <th>Категория</th>
                <th>Привязка</th>
                <th>Размер</th>
                <th>Точек</th>
                <th>Версия</th>
                <th>Обновлено</th>
                <th style={{ width: 120 }}></th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((t) => (
                <tr key={t.id}>
                  <td>
                    <div
                      className="w-10 h-10 rounded border border-[var(--border-primary)] bg-[var(--bg-tertiary)] flex items-center justify-center"
                    >
                      <ImageIcon size={18} className="text-[var(--text-muted)]" />
                    </div>
                  </td>
                  <td>
                    <div className="font-semibold text-[var(--text-primary)]">{t.name}</div>
                    {t.description && (
                      <div className="text-xs text-[var(--text-muted)] mt-0.5">{t.description}</div>
                    )}
                  </td>
                  <td>
                    <span className="ind-chip">{CATEGORY_LABELS[t.category || ''] || t.category || '—'}</span>
                  </td>
                  <td className="text-xs">
                    {t.equipment_name ? (
                      <span className="ind-chip ind-chip--info">{t.equipment_name}</span>
                    ) : t.equipment_type_name ? (
                      <span>{t.equipment_type_name}</span>
                    ) : (
                      <span className="text-[var(--text-muted)]">универсальный</span>
                    )}
                  </td>
                  <td className="ind-mono text-xs">
                    {t.image_width && t.image_height
                      ? `${t.image_width}×${t.image_height}`
                      : '—'}
                    {t.file_size ? (
                      <span className="text-[var(--text-muted)] ml-1">
                        ({Math.round(t.file_size / 1024)} KB)
                      </span>
                    ) : null}
                  </td>
                  <td className="ind-mono">{t.points_count ?? 0}</td>
                  <td>
                    <span className="ind-chip ind-mono">v{t.version}</span>
                  </td>
                  <td className="text-xs text-[var(--text-muted)]">
                    {t.updated_at ? new Date(t.updated_at).toLocaleDateString('ru-RU') : '—'}
                  </td>
                  <td>
                    <div className="flex items-center justify-end gap-1">
                      <button
                        className="ind-btn ind-btn--sm"
                        onClick={() => setEditorId(t.id)}
                        title="Редактор точек"
                      >
                        <Edit3 size={12} />
                      </button>
                      <button
                        className="ind-btn ind-btn--sm ind-btn--danger"
                        onClick={() => removeTemplate(t.id)}
                        title="Удалить"
                      >
                        <Trash2 size={12} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {uploadOpen && (
        <UploadModal
          onClose={() => setUploadOpen(false)}
          onCreated={(t) => {
            setUploadOpen(false);
            setItems((prev) => [
              { ...t, points_count: t.points?.length ?? 0 },
              ...prev,
            ]);
            setEditorId(t.id);
          }}
          equipmentTypes={equipmentTypes}
        />
      )}
    </div>
  );
};

export default DrawingTemplatesManager;
