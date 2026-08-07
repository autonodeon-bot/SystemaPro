/**
 * Конструктор актов/протоколов (П.2)
 * Позволяет создавать произвольные шаблоны документов с блоками:
 * заголовками, полями, таблицами, фото-секциями, подписями.
 * Работает на ПК; готовые шаблоны используются в мобильном приложении.
 */
import React, { useState, useEffect, useCallback } from 'react';
import {
  Plus, Trash2, ChevronUp, ChevronDown, Edit3, Save,
  FileText, Table, Image, AlignLeft, Type, Hash, Calendar,
  CheckSquare, Pen, Wrench, Eye, EyeOff, Copy, AlertCircle,
  LayoutList, X, GripVertical,
} from 'lucide-react';
import { API_BASE } from '../constants';
import { useAuth } from '../contexts/AuthContext';

// ─── Типы ──────────────────────────────────────────────────────────────────

type BlockType =
  | 'section_header'
  | 'text_field'
  | 'date_field'
  | 'number_field'
  | 'textarea'
  | 'table'
  | 'photo_section'
  | 'instruments_field'
  | 'signature'
  | 'checkbox_list';

type TemplateStatus = 'draft' | 'published' | 'archived';

interface TableColumn {
  key: string;
  label: string;
  col_type: 'text' | 'number' | 'date';
  width?: number;
  required?: boolean;
}

interface TemplateBlock {
  id: string;
  block_type: BlockType;
  label: string;
  field_key?: string;
  required?: boolean;
  placeholder?: string;
  columns?: TableColumn[];
  items?: string[];
}

interface ProtocolTemplate {
  id: string;
  name: string;
  description?: string;
  category?: string;
  structure: TemplateBlock[];
  created_by?: string;
  created_at?: string;
  updated_at?: string;
  is_active?: boolean;
  status?: TemplateStatus;
  version?: number;
}

interface TemplateVersionInfo {
  version: number;
  created_by?: string;
  created_at?: string;
}

const CATEGORIES = ['ВИК', 'УЗТ', 'УЗК', 'ПВК(МПД)', 'ТД(ЭПБ)', 'Другое'];

const BLOCK_DEFS: { type: BlockType; label: string; icon: React.ComponentType<any>; hint: string }[] = [
  { type: 'section_header',   label: 'Заголовок раздела',   icon: LayoutList,   hint: 'Разделитель с заголовком' },
  { type: 'text_field',       label: 'Текстовое поле',       icon: Type,         hint: 'Однострочный ввод' },
  { type: 'date_field',       label: 'Поле даты',            icon: Calendar,     hint: 'Выбор даты' },
  { type: 'number_field',     label: 'Числовое поле',        icon: Hash,         hint: 'Ввод числа' },
  { type: 'textarea',         label: 'Многострочный текст',  icon: AlignLeft,    hint: 'Большое поле ввода' },
  { type: 'table',            label: 'Таблица',              icon: Table,        hint: 'Таблица с настраиваемыми колонками' },
  { type: 'photo_section',    label: 'Фото / схема',         icon: Image,        hint: 'Секция для фотографий' },
  { type: 'instruments_field',label: 'Приборы',              icon: Wrench,       hint: 'Список приборов из реестра' },
  { type: 'checkbox_list',    label: 'Список с флажками',    icon: CheckSquare,  hint: 'Чек-лист элементов' },
  { type: 'signature',        label: 'Подпись',              icon: Pen,          hint: 'Блок подписи' },
];

// ─── Утилиты ──────────────────────────────────────────────────────────────

const newBlock = (type: BlockType): TemplateBlock => ({
  id: crypto.randomUUID(),
  block_type: type,
  label: BLOCK_DEFS.find(d => d.type === type)?.label ?? type,
  field_key: type !== 'section_header' ? type + '_' + Date.now() : undefined,
  required: false,
  columns: type === 'table' ? [
    { key: 'col1', label: 'Колонка 1', col_type: 'text' },
  ] : undefined,
  items: type === 'checkbox_list' ? ['Пункт 1'] : undefined,
});

const emptyTemplate = (): Omit<ProtocolTemplate, 'id' | 'created_at' | 'updated_at' | 'created_by'> => ({
  name: '',
  description: '',
  category: 'Другое',
  structure: [],
  is_active: true,
  status: 'draft',
});

// ─── Иконка типа блока ─────────────────────────────────────────────────────

const BlockIcon: React.FC<{ type: BlockType }> = ({ type }) => {
  const def = BLOCK_DEFS.find(d => d.type === type);
  if (!def) return <FileText size={16} />;
  const Icon = def.icon;
  return <Icon size={16} />;
};

// ─── Превью блока ──────────────────────────────────────────────────────────

const BlockPreview: React.FC<{ block: TemplateBlock }> = ({ block }) => {
  switch (block.block_type) {
    case 'section_header':
      return (
        <div className="bg-app-soft/60 rounded px-3 py-2 text-app-text font-semibold border-l-2 border-accent">
          {block.label || 'Заголовок раздела'}
        </div>
      );
    case 'table':
      return (
        <div className="overflow-x-auto">
          <table className="w-full text-xs border border-app-line">
            <thead>
              <tr className="bg-app-soft">
                {(block.columns ?? []).map(col => (
                  <th key={col.key} className="border border-app-line px-2 py-1 text-left text-app-text2">
                    {col.label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              <tr>
                {(block.columns ?? []).map(col => (
                  <td key={col.key} className="border border-app-line px-2 py-1 text-app-text3 italic">
                    ...
                  </td>
                ))}
              </tr>
            </tbody>
          </table>
        </div>
      );
    case 'photo_section':
      return (
        <div className="border-2 border-dashed border-app-line rounded p-4 text-center text-app-text3 text-sm">
          <Image size={20} className="mx-auto mb-1" /> Фото/схема объекта
        </div>
      );
    case 'signature':
      return (
        <div className="flex items-end gap-4">
          <div className="flex-1">
            <div className="text-xs text-app-text3 mb-1">{block.label}</div>
            <div className="border-b border-app-line h-8 w-full" />
            <div className="text-xs text-app-text3 mt-1">Подпись / дата</div>
          </div>
        </div>
      );
    case 'checkbox_list':
      return (
        <div className="space-y-1">
          {(block.items ?? []).map((item, i) => (
            <label key={i} className="flex items-center gap-2 text-sm text-app-text2">
              <input type="checkbox" disabled className="rounded" /> {item}
            </label>
          ))}
        </div>
      );
    case 'textarea':
      return <textarea disabled className="w-full bg-app-panel border border-app-line rounded p-2 text-sm text-app-text3 resize-none h-16" placeholder={block.placeholder ?? block.label} />;
    case 'instruments_field':
      return (
        <div className="flex items-center gap-2 bg-app-panel border border-app-line rounded p-2">
          <Wrench size={14} className="text-app-text3" />
          <span className="text-sm text-app-text3">{block.placeholder ?? 'Приборы из реестра...'}</span>
        </div>
      );
    default:
      return (
        <input
          disabled
          type={block.block_type === 'date_field' ? 'date' : block.block_type === 'number_field' ? 'number' : 'text'}
          className="w-full bg-app-panel border border-app-line rounded p-2 text-sm text-app-text3"
          placeholder={block.placeholder ?? block.label}
        />
      );
  }
};

// ─── Редактор блока ────────────────────────────────────────────────────────

const BlockEditor: React.FC<{
  block: TemplateBlock;
  onChange: (b: TemplateBlock) => void;
  onClose: () => void;
}> = ({ block, onChange, onClose }) => {
  const [local, setLocal] = useState<TemplateBlock>({ ...block, columns: block.columns ? [...block.columns] : undefined, items: block.items ? [...block.items] : undefined });

  const save = () => { onChange(local); onClose(); };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70">
      <div className="bg-app-panel border border-app-line rounded-2xl w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-app-text font-bold flex items-center gap-2">
            <BlockIcon type={block.block_type} /> Редактировать блок
          </h3>
          <button onClick={onClose} className="text-app-text3 hover:text-app-text"><X size={18} /></button>
        </div>

        <div className="space-y-4">
          <div>
            <label className="text-xs text-app-text3 mb-1 block">Заголовок / подпись</label>
            <input
              className="w-full bg-app-soft border border-app-line rounded p-2 text-app-text text-sm"
              value={local.label}
              onChange={e => setLocal({ ...local, label: e.target.value })}
            />
          </div>

          {block.block_type !== 'section_header' && block.block_type !== 'signature' && block.block_type !== 'photo_section' && (
            <div>
              <label className="text-xs text-app-text3 mb-1 block">Ключ поля (латиница, уникальный)</label>
              <input
                className="w-full bg-app-soft border border-app-line rounded p-2 text-app-text text-sm font-mono"
                value={local.field_key ?? ''}
                onChange={e => setLocal({ ...local, field_key: e.target.value })}
                placeholder="object_name"
              />
            </div>
          )}

          {(block.block_type === 'text_field' || block.block_type === 'textarea' || block.block_type === 'number_field') && (
            <div>
              <label className="text-xs text-app-text3 mb-1 block">Подсказка (placeholder)</label>
              <input
                className="w-full bg-app-soft border border-app-line rounded p-2 text-app-text text-sm"
                value={local.placeholder ?? ''}
                onChange={e => setLocal({ ...local, placeholder: e.target.value })}
              />
            </div>
          )}

          {block.block_type !== 'section_header' && (
            <label className="flex items-center gap-2 text-sm text-app-text2 cursor-pointer">
              <input
                type="checkbox"
                checked={local.required ?? false}
                onChange={e => setLocal({ ...local, required: e.target.checked })}
                className="rounded"
              />
              Обязательное поле
            </label>
          )}

          {/* Настройка таблицы */}
          {block.block_type === 'table' && (
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-xs text-app-text3">Колонки таблицы</label>
                <button
                  onClick={() => setLocal({ ...local, columns: [...(local.columns ?? []), { key: 'col' + Date.now(), label: 'Новая колонка', col_type: 'text' }] })}
                  className="text-accent text-xs flex items-center gap-1 hover:underline"
                >
                  <Plus size={12} /> Добавить
                </button>
              </div>
              <div className="space-y-2">
                {(local.columns ?? []).map((col, ci) => (
                  <div key={ci} className="flex items-center gap-2 bg-app-soft/50 rounded p-2">
                    <input
                      className="flex-1 bg-app-soft border border-app-line rounded p-1 text-app-text text-xs"
                      value={col.label}
                      placeholder="Заголовок"
                      onChange={e => {
                        const cols = [...(local.columns ?? [])];
                        cols[ci] = { ...cols[ci], label: e.target.value };
                        setLocal({ ...local, columns: cols });
                      }}
                    />
                    <select
                      className="bg-app-soft border border-app-line rounded p-1 text-xs text-app-text"
                      value={col.col_type}
                      onChange={e => {
                        const cols = [...(local.columns ?? [])];
                        cols[ci] = { ...cols[ci], col_type: e.target.value as 'text' | 'number' | 'date' };
                        setLocal({ ...local, columns: cols });
                      }}
                    >
                      <option value="text">Текст</option>
                      <option value="number">Число</option>
                      <option value="date">Дата</option>
                    </select>
                    <button
                      onClick={() => {
                        const cols = (local.columns ?? []).filter((_, i) => i !== ci);
                        setLocal({ ...local, columns: cols });
                      }}
                      className="text-red-400 hover:text-red-300"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Настройка чек-листа */}
          {block.block_type === 'checkbox_list' && (
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-xs text-app-text3">Пункты списка</label>
                <button
                  onClick={() => setLocal({ ...local, items: [...(local.items ?? []), 'Новый пункт'] })}
                  className="text-accent text-xs flex items-center gap-1 hover:underline"
                >
                  <Plus size={12} /> Добавить
                </button>
              </div>
              <div className="space-y-1">
                {(local.items ?? []).map((item, ii) => (
                  <div key={ii} className="flex items-center gap-2">
                    <input
                      className="flex-1 bg-app-soft border border-app-line rounded p-1 text-app-text text-sm"
                      value={item}
                      onChange={e => {
                        const items = [...(local.items ?? [])];
                        items[ii] = e.target.value;
                        setLocal({ ...local, items });
                      }}
                    />
                    <button
                      onClick={() => setLocal({ ...local, items: (local.items ?? []).filter((_, i) => i !== ii) })}
                      className="text-red-400 hover:text-red-300"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="flex gap-2 mt-6">
          <button onClick={onClose} className="flex-1 px-4 py-2 border border-app-line rounded-lg text-app-text2 hover:bg-app-soft text-sm">
            Отмена
          </button>
          <button onClick={save} className="flex-1 px-4 py-2 bg-accent hover:bg-accent/80 text-white rounded-lg text-sm flex items-center justify-center gap-2">
            <Save size={14} /> Применить
          </button>
        </div>
      </div>
    </div>
  );
};

// ─── Карточка блока в списке конструктора ──────────────────────────────────

const BlockCard: React.FC<{
  block: TemplateBlock;
  index: number;
  total: number;
  onMoveUp: () => void;
  onMoveDown: () => void;
  onEdit: () => void;
  onDelete: () => void;
  onDuplicate: () => void;
}> = ({ block, index, total, onMoveUp, onMoveDown, onEdit, onDelete, onDuplicate }) => {
  const def = BLOCK_DEFS.find(d => d.type === block.block_type);
  return (
    <div className="bg-app-panel border border-app-line rounded-xl p-4 group hover:border-accent/50 transition-colors">
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2">
          <span className="text-app-text3 text-xs font-mono w-5 text-right">{index + 1}.</span>
          <span className="flex items-center gap-1.5 text-xs font-medium px-2 py-0.5 rounded-full bg-accent/10 text-accent border border-accent/20">
            <BlockIcon type={block.block_type} />
            {def?.label ?? block.block_type}
          </span>
          {block.required && (
            <span className="text-xs text-red-400">*обяз.</span>
          )}
        </div>
        <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
          <button onClick={onMoveUp} disabled={index === 0} className="p-1 text-app-text3 hover:text-app-text disabled:opacity-30">
            <ChevronUp size={14} />
          </button>
          <button onClick={onMoveDown} disabled={index === total - 1} className="p-1 text-app-text3 hover:text-app-text disabled:opacity-30">
            <ChevronDown size={14} />
          </button>
          <button onClick={onDuplicate} className="p-1 text-app-text3 hover:text-blue-400" title="Дублировать">
            <Copy size={14} />
          </button>
          <button onClick={onEdit} className="p-1 text-app-text3 hover:text-accent" title="Редактировать">
            <Edit3 size={14} />
          </button>
          <button onClick={onDelete} className="p-1 text-app-text3 hover:text-red-400" title="Удалить">
            <Trash2 size={14} />
          </button>
        </div>
      </div>
      <div className="text-app-text font-medium text-sm mb-2">{block.label}</div>
      <div className="opacity-60 pointer-events-none">
        <BlockPreview block={block} />
      </div>
    </div>
  );
};

// ─── Главный компонент ─────────────────────────────────────────────────────

const ProtocolConstructor: React.FC = () => {
  const { user } = useAuth();
  const token = localStorage.getItem('token');
  const headers = { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' };

  const canEdit = user?.role === 'admin' || user?.role === 'chief_operator' || user?.role === 'operator';

  const [templates, setTemplates] = useState<ProtocolTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Режим просмотра или редактирования
  const [mode, setMode] = useState<'list' | 'edit' | 'create'>('list');
  const [editingTemplate, setEditingTemplate] = useState<Partial<ProtocolTemplate> | null>(null);
  const [templateVersions, setTemplateVersions] = useState<TemplateVersionInfo[]>([]);
  const [restoreVersion, setRestoreVersion] = useState<number | ''>('');
  const [diffFromVersion, setDiffFromVersion] = useState<number | ''>('');
  const [diffToVersion, setDiffToVersion] = useState<number | ''>('');
  const [diffResult, setDiffResult] = useState<{ added: string[]; removed: string[]; unchanged_count: number } | null>(null);

  // Редактирование конкретного блока
  const [editingBlock, setEditingBlock] = useState<TemplateBlock | null>(null);

  // Превью
  const [previewMode, setPreviewMode] = useState(false);
  const [dragIndex, setDragIndex] = useState<number | null>(null);

  // ── Загрузка шаблонов ──
  const loadTemplates = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/api/protocol-templates?active_only=false`, { headers });
      if (!res.ok) throw new Error(await res.text());
      const data = await res.json();
      setTemplates(data);
    } catch (e: any) {
      setError(String(e?.message ?? e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadTemplates(); }, [loadTemplates]);

  const loadTemplateVersions = useCallback(async (templateId: string) => {
    try {
      const res = await fetch(`${API_BASE}/api/protocol-templates/${templateId}/versions`, { headers });
      if (!res.ok) throw new Error(await res.text());
      const data = await res.json();
      setTemplateVersions(Array.isArray(data) ? data : []);
    } catch (e: any) {
      setError(String(e?.message ?? e));
      setTemplateVersions([]);
    }
  }, []);

  const startEditTemplate = useCallback((tmpl: ProtocolTemplate) => {
    setEditingTemplate(tmpl);
    setMode('edit');
    setDiffResult(null);
    setRestoreVersion('');
    setDiffFromVersion('');
    setDiffToVersion('');
    void loadTemplateVersions(tmpl.id);
  }, [loadTemplateVersions]);

  // ── Сохранение шаблона ──
  const saveTemplate = async () => {
    if (!editingTemplate) return;
    setSaving(true);
    try {
      const isNew = !editingTemplate.id;
      const url = isNew
        ? `${API_BASE}/api/protocol-templates`
        : `${API_BASE}/api/protocol-templates/${editingTemplate.id}`;
      const method = isNew ? 'POST' : 'PUT';
      const res = await fetch(url, { method, headers, body: JSON.stringify(editingTemplate) });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail ?? 'Ошибка сохранения');
      }
      await loadTemplates();
      if (editingTemplate.id) {
        await loadTemplateVersions(editingTemplate.id);
      }
      setMode('list');
      setEditingTemplate(null);
    } catch (e: any) {
      setError(String(e?.message ?? e));
    } finally {
      setSaving(false);
    }
  };

  const publishTemplate = async () => {
    if (!editingTemplate?.id) return;
    try {
      setSaving(true);
      const res = await fetch(`${API_BASE}/api/protocol-templates/${editingTemplate.id}/publish`, {
        method: 'POST',
        headers,
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail ?? 'Ошибка публикации');
      }
      await loadTemplates();
      await loadTemplateVersions(editingTemplate.id);
      setEditingTemplate(prev => prev ? { ...prev, status: 'published' } : prev);
    } catch (e: any) {
      setError(String(e?.message ?? e));
    } finally {
      setSaving(false);
    }
  };

  const restoreTemplateVersion = async () => {
    if (!editingTemplate?.id || restoreVersion === '') return;
    try {
      setSaving(true);
      const res = await fetch(`${API_BASE}/api/protocol-templates/${editingTemplate.id}/restore/${restoreVersion}`, {
        method: 'POST',
        headers,
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail ?? 'Ошибка отката версии');
      }
      const fresh = await fetch(`${API_BASE}/api/protocol-templates/${editingTemplate.id}?active_only=false`, { headers });
      if (fresh.ok) {
        setEditingTemplate(await fresh.json());
      }
      await loadTemplates();
      await loadTemplateVersions(editingTemplate.id);
      setRestoreVersion('');
    } catch (e: any) {
      setError(String(e?.message ?? e));
    } finally {
      setSaving(false);
    }
  };

  const compareTemplateVersions = async () => {
    if (!editingTemplate?.id || diffFromVersion === '' || diffToVersion === '') return;
    try {
      const params = new URLSearchParams({
        from_version: String(diffFromVersion),
        to_version: String(diffToVersion),
      });
      const res = await fetch(`${API_BASE}/api/protocol-templates/${editingTemplate.id}/diff?${params.toString()}`, { headers });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail ?? 'Ошибка сравнения версий');
      }
      const data = await res.json();
      setDiffResult(data);
    } catch (e: any) {
      setError(String(e?.message ?? e));
    }
  };

  // ── Удаление шаблона ──
  const deleteTemplate = async (id: string) => {
    if (!window.confirm('Удалить шаблон?')) return;
    try {
      await fetch(`${API_BASE}/api/protocol-templates/${id}`, { method: 'DELETE', headers });
      setTemplates(prev => prev.filter(t => t.id !== id));
    } catch (e: any) {
      setError(String(e?.message ?? e));
    }
  };

  // ── Работа с блоками ──
  const addBlock = (type: BlockType) => {
    if (!editingTemplate) return;
    const block = newBlock(type);
    setEditingTemplate(prev => ({
      ...prev,
      structure: [...(prev?.structure ?? []), block],
    }));
  };

  const updateBlock = (block: TemplateBlock) => {
    setEditingTemplate(prev => ({
      ...prev,
      structure: (prev?.structure ?? []).map(b => b.id === block.id ? block : b),
    }));
    setEditingBlock(null);
  };

  const deleteBlock = (id: string) => {
    setEditingTemplate(prev => ({
      ...prev,
      structure: (prev?.structure ?? []).filter(b => b.id !== id),
    }));
  };

  const moveBlock = (idx: number, dir: -1 | 1) => {
    if (!editingTemplate?.structure) return;
    const arr = [...editingTemplate.structure];
    const newIdx = idx + dir;
    if (newIdx < 0 || newIdx >= arr.length) return;
    [arr[idx], arr[newIdx]] = [arr[newIdx], arr[idx]];
    setEditingTemplate(prev => ({ ...prev, structure: arr }));
  };

  const duplicateBlock = (block: TemplateBlock) => {
    const copy: TemplateBlock = {
      ...block,
      id: crypto.randomUUID(),
      label: block.label + ' (копия)',
      field_key: block.field_key ? block.field_key + '_copy' : undefined,
    };
    setEditingTemplate(prev => ({
      ...prev,
      structure: [...(prev?.structure ?? []), copy],
    }));
  };

  const handleDragStart = (index: number) => {
    setDragIndex(index);
  };

  const handleDrop = (targetIndex: number) => {
    if (dragIndex === null || !editingTemplate?.structure || dragIndex === targetIndex) {
      setDragIndex(null);
      return;
    }
    const arr = [...editingTemplate.structure];
    const [moved] = arr.splice(dragIndex, 1);
    arr.splice(targetIndex, 0, moved);
    setEditingTemplate(prev => ({ ...prev, structure: arr }));
    setDragIndex(null);
  };

  // ── Рендер списка шаблонов ──
  if (mode === 'list') {
    return (
      <div className="max-w-5xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold text-app-text">Конструктор актов / протоколов</h1>
            <p className="text-app-text3 mt-1">
              Создавайте шаблоны протоколов на ПК — они автоматически становятся доступны в мобильном приложении.
            </p>
          </div>
          {canEdit && (
            <button
              onClick={() => {
                setEditingTemplate(emptyTemplate());
                setTemplateVersions([]);
                setDiffResult(null);
                setMode('create');
              }}
              className="flex items-center gap-2 px-4 py-2 bg-accent hover:bg-accent/80 text-white rounded-xl font-medium transition-colors"
            >
              <Plus size={18} /> Новый шаблон
            </button>
          )}
        </div>

        {error && (
          <div className="bg-red-500/10 border border-red-500/40 rounded-xl p-4 flex items-center gap-3 text-red-400">
            <AlertCircle size={18} />{error}
          </div>
        )}

        {loading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {[...Array(6)].map((_, i) => (
              <div key={i} className="bg-app-panel rounded-xl h-40 animate-pulse border border-app-line" />
            ))}
          </div>
        ) : templates.length === 0 ? (
          <div className="text-center py-20 text-app-text3">
            <FileText size={48} className="mx-auto mb-4 opacity-40" />
            <p className="text-lg">Шаблонов пока нет</p>
            {canEdit && (
              <p className="text-sm mt-2">Нажмите «Новый шаблон», чтобы создать первый</p>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {templates.map(tmpl => (
              <div key={tmpl.id} className={`bg-app-panel border rounded-xl p-5 hover:border-accent/50 transition-colors group ${tmpl.is_active ? 'border-app-line' : 'border-app-line/30 opacity-60'}`}>
                <div className="flex items-start justify-between mb-2">
                  <div>
                    {tmpl.category && (
                      <span className="text-xs px-2 py-0.5 bg-accent/10 text-accent border border-accent/20 rounded-full mr-2">
                        {tmpl.category}
                      </span>
                    )}
                    {!tmpl.is_active && (
                      <span className="text-xs px-2 py-0.5 bg-app-soft text-app-text3 rounded-full">
                        Архив
                      </span>
                    )}
                    {tmpl.status && (
                      <span className="text-xs px-2 py-0.5 bg-app-soft text-app-text2 rounded-full ml-1">
                        {tmpl.status === 'published' ? 'Опубликован' : tmpl.status === 'archived' ? 'Архив' : 'Черновик'}
                      </span>
                    )}
                  </div>
                  <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    {canEdit && (
                      <>
                        <button
                          onClick={() => startEditTemplate(tmpl)}
                          className="p-1.5 text-app-text3 hover:text-accent rounded hover:bg-app-soft"
                          title="Редактировать"
                        >
                          <Edit3 size={14} />
                        </button>
                        <button
                          onClick={() => deleteTemplate(tmpl.id)}
                          className="p-1.5 text-app-text3 hover:text-red-400 rounded hover:bg-app-soft"
                          title="Удалить"
                        >
                          <Trash2 size={14} />
                        </button>
                      </>
                    )}
                  </div>
                </div>
                <h3 className="text-app-text font-semibold mt-2 mb-1">{tmpl.name}</h3>
                {tmpl.description && (
                  <p className="text-app-text3 text-sm line-clamp-2">{tmpl.description}</p>
                )}
                <div className="flex items-center gap-3 mt-3 text-xs text-app-text3">
                  <span>{tmpl.structure.length} блоков</span>
                  <span>v{tmpl.version ?? 1}</span>
                  {tmpl.created_at && (
                    <span>{new Date(tmpl.created_at).toLocaleDateString('ru')}</span>
                  )}
                  {tmpl.created_by && <span>от {tmpl.created_by}</span>}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  }

  // ── Редактор ──
  const isCreating = mode === 'create';
  const blocks = editingTemplate?.structure ?? [];

  return (
    <div className="max-w-6xl mx-auto">
      {editingBlock && (
        <BlockEditor
          block={editingBlock}
          onChange={updateBlock}
          onClose={() => setEditingBlock(null)}
        />
      )}

      {/* Шапка */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <button
            onClick={() => {
              setMode('list');
              setEditingTemplate(null);
              setTemplateVersions([]);
              setDiffResult(null);
            }}
            className="text-app-text3 hover:text-app-text text-sm flex items-center gap-1"
          >
            ← Назад к списку
          </button>
          <span className="text-app-text3">|</span>
          <h1 className="text-xl font-bold text-app-text">
            {isCreating ? 'Новый шаблон' : `Редактировать: ${editingTemplate?.name}`}
          </h1>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setPreviewMode(p => !p)}
            className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm transition-colors ${previewMode ? 'bg-accent/20 text-accent' : 'text-app-text3 hover:bg-app-soft'}`}
          >
            {previewMode ? <EyeOff size={16} /> : <Eye size={16} />}
            {previewMode ? 'Скрыть превью' : 'Превью'}
          </button>
          <button
            onClick={saveTemplate}
            disabled={saving || !editingTemplate?.name?.trim()}
            className="flex items-center gap-2 px-4 py-2 bg-accent hover:bg-accent/80 disabled:opacity-50 text-white rounded-lg text-sm font-medium transition-colors"
          >
            <Save size={16} /> {saving ? 'Сохранение...' : 'Сохранить шаблон'}
          </button>
        </div>
      </div>

      {error && (
        <div className="bg-red-500/10 border border-red-500/40 rounded-xl p-3 flex items-center gap-2 text-red-400 text-sm mb-4">
          <AlertCircle size={16} />{error}
          <button onClick={() => setError(null)} className="ml-auto"><X size={14} /></button>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Левая панель — настройки + типы блоков */}
        <div className="space-y-4">
          {/* Мета шаблона */}
          <div className="bg-app-panel border border-app-line rounded-xl p-4 space-y-3">
            <h2 className="text-app-text font-semibold text-sm">Настройки шаблона</h2>
            <div>
              <label className="text-xs text-app-text3 block mb-1">Название шаблона *</label>
              <input
                className="w-full bg-app-soft border border-app-line rounded-lg p-2 text-app-text text-sm focus:border-accent focus:outline-none"
                placeholder="Протокол ВИК трубопровода"
                value={editingTemplate?.name ?? ''}
                onChange={e => setEditingTemplate(prev => ({ ...prev, name: e.target.value }))}
              />
            </div>
            <div>
              <label className="text-xs text-app-text3 block mb-1">Описание</label>
              <textarea
                className="w-full bg-app-soft border border-app-line rounded-lg p-2 text-app-text text-sm resize-none h-16 focus:border-accent focus:outline-none"
                placeholder="Для чего используется этот шаблон..."
                value={editingTemplate?.description ?? ''}
                onChange={e => setEditingTemplate(prev => ({ ...prev, description: e.target.value }))}
              />
            </div>
            <div>
              <label className="text-xs text-app-text3 block mb-1">Категория</label>
              <select
                className="w-full bg-app-soft border border-app-line rounded-lg p-2 text-app-text text-sm focus:border-accent focus:outline-none"
                value={editingTemplate?.category ?? 'Другое'}
                onChange={e => setEditingTemplate(prev => ({ ...prev, category: e.target.value }))}
              >
                {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>
            {!isCreating && (
              <label className="flex items-center gap-2 text-sm text-app-text2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={editingTemplate?.is_active ?? true}
                  onChange={e => setEditingTemplate(prev => ({ ...prev, is_active: e.target.checked }))}
                  className="rounded"
                />
                Активный (доступен в приложении)
              </label>
            )}
            <div>
              <label className="text-xs text-app-text3 block mb-1">Статус шаблона</label>
              <select
                className="w-full bg-app-soft border border-app-line rounded-lg p-2 text-app-text text-sm focus:border-accent focus:outline-none"
                value={editingTemplate?.status ?? 'draft'}
                onChange={e => setEditingTemplate(prev => ({ ...prev, status: e.target.value as TemplateStatus }))}
              >
                <option value="draft">Черновик</option>
                <option value="published">Опубликован</option>
                <option value="archived">Архив</option>
              </select>
            </div>
            {!isCreating && canEdit && (
              <button
                onClick={publishTemplate}
                disabled={saving}
                className="w-full px-3 py-2 bg-emerald-600/90 hover:bg-emerald-600 disabled:opacity-50 text-white rounded-lg text-sm"
              >
                Опубликовать текущую версию
              </button>
            )}
          </div>

          {!isCreating && (
            <div className="bg-app-panel border border-app-line rounded-xl p-4 space-y-3">
              <h2 className="text-app-text font-semibold text-sm">Версии шаблона</h2>
              <div className="max-h-40 overflow-auto space-y-1">
                {templateVersions.length === 0 ? (
                  <p className="text-xs text-app-text3">История версий пока пуста</p>
                ) : (
                  templateVersions.map(v => (
                    <div key={v.version} className="text-xs text-app-text2 flex items-center justify-between bg-app-soft/40 rounded px-2 py-1">
                      <span>v{v.version}</span>
                      <span className="text-app-text3">{v.created_at ? new Date(v.created_at).toLocaleString('ru-RU') : ''}</span>
                    </div>
                  ))
                )}
              </div>

              <div className="grid grid-cols-2 gap-2">
                <select
                  className="bg-app-soft border border-app-line rounded p-2 text-xs text-app-text"
                  value={restoreVersion}
                  onChange={e => setRestoreVersion(e.target.value ? Number(e.target.value) : '')}
                >
                  <option value="">Версия для отката</option>
                  {templateVersions.map(v => <option key={`restore-${v.version}`} value={v.version}>v{v.version}</option>)}
                </select>
                <button
                  onClick={restoreTemplateVersion}
                  disabled={restoreVersion === '' || saving}
                  className="bg-amber-600/90 hover:bg-amber-600 disabled:opacity-50 text-white text-xs rounded p-2"
                >
                  Откатить
                </button>
              </div>

              <div className="grid grid-cols-2 gap-2">
                <select
                  className="bg-app-soft border border-app-line rounded p-2 text-xs text-app-text"
                  value={diffFromVersion}
                  onChange={e => setDiffFromVersion(e.target.value ? Number(e.target.value) : '')}
                >
                  <option value="">С версии</option>
                  {templateVersions.map(v => <option key={`from-${v.version}`} value={v.version}>v{v.version}</option>)}
                </select>
                <select
                  className="bg-app-soft border border-app-line rounded p-2 text-xs text-app-text"
                  value={diffToVersion}
                  onChange={e => setDiffToVersion(e.target.value ? Number(e.target.value) : '')}
                >
                  <option value="">До версии</option>
                  {templateVersions.map(v => <option key={`to-${v.version}`} value={v.version}>v{v.version}</option>)}
                </select>
              </div>
              <button
                onClick={compareTemplateVersions}
                disabled={diffFromVersion === '' || diffToVersion === ''}
                className="w-full bg-app-soft hover:bg-app-softer disabled:opacity-50 text-app-text text-xs rounded p-2"
              >
                Сравнить версии
              </button>
              {diffResult && (
                <div className="text-xs text-app-text2 bg-app-soft/30 border border-app-line rounded p-2 space-y-1">
                  <div>Добавлено полей: {diffResult.added.length}</div>
                  <div>Удалено полей: {diffResult.removed.length}</div>
                  <div>Без изменений: {diffResult.unchanged_count}</div>
                </div>
              )}
            </div>
          )}

          {/* Типы блоков для добавления */}
          <div className="bg-app-panel border border-app-line rounded-xl p-4">
            <h2 className="text-app-text font-semibold text-sm mb-3">Добавить блок</h2>
            <div className="space-y-1.5">
              {BLOCK_DEFS.map(def => {
                const Icon = def.icon;
                return (
                  <button
                    key={def.type}
                    onClick={() => addBlock(def.type)}
                    className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-left text-sm text-app-text2 hover:bg-app-soft hover:text-app-text transition-colors group"
                    title={def.hint}
                  >
                    <Icon size={15} className="text-accent flex-shrink-0" />
                    <span className="flex-1">{def.label}</span>
                    <Plus size={13} className="opacity-0 group-hover:opacity-100 text-accent" />
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        {/* Центральная/правая панель — список блоков или превью */}
        <div className="lg:col-span-2">
          {previewMode ? (
            /* Превью финального документа */
            <div className="bg-white rounded-xl p-8 space-y-5 min-h-96">
              <div className="text-center border-b pb-4 mb-4">
                <h2 className="text-app-text text-xl font-bold">{editingTemplate?.name || 'Название протокола'}</h2>
                {editingTemplate?.description && (
                  <p className="text-app-text3 text-sm mt-1">{editingTemplate.description}</p>
                )}
              </div>
              {blocks.length === 0 ? (
                <p className="text-center text-app-text3">Блоков пока нет. Добавьте блоки из левой панели.</p>
              ) : (
                blocks.map(block => (
                  <div key={block.id} className="space-y-1">
                    {block.block_type !== 'section_header' && (
                      <label className="text-xs font-medium text-app-text3">
                        {block.label}{block.required ? ' *' : ''}
                      </label>
                    )}
                    <BlockPreview block={block} />
                  </div>
                ))
              )}
            </div>
          ) : (
            /* Конструктор — список блоков */
            <div>
              {blocks.length === 0 ? (
                <div className="bg-app-panel/50 border-2 border-dashed border-app-line rounded-xl p-12 text-center">
                  <GripVertical size={32} className="mx-auto mb-3 text-app-text3" />
                  <p className="text-app-text3">Добавьте блоки из панели слева</p>
                  <p className="text-app-text3 text-sm mt-1">Блоки будут отображаться в протоколе в том же порядке</p>
                </div>
              ) : (
                <div className="space-y-3">
                  {blocks.map((block, idx) => (
                    <div
                      key={block.id}
                      draggable
                      onDragStart={() => handleDragStart(idx)}
                      onDragOver={(e) => e.preventDefault()}
                      onDrop={() => handleDrop(idx)}
                      className={dragIndex === idx ? 'opacity-50' : ''}
                    >
                      <BlockCard
                        block={block}
                        index={idx}
                        total={blocks.length}
                        onMoveUp={() => moveBlock(idx, -1)}
                        onMoveDown={() => moveBlock(idx, 1)}
                        onEdit={() => setEditingBlock(block)}
                        onDelete={() => deleteBlock(block.id)}
                        onDuplicate={() => duplicateBlock(block)}
                      />
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default ProtocolConstructor;
