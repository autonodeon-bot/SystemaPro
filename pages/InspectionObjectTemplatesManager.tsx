/**
 * Шаблоны обследования объектов (мобильное приложение + акт ТД).
 */
import React, { useCallback, useEffect, useState } from 'react';
import { Plus, RefreshCw, Save, Trash2, AlertCircle } from 'lucide-react';
import { API_BASE } from '../constants';
import { useAuth } from '../contexts/AuthContext';

interface TemplateRow {
  id: string;
  name: string;
  description?: string;
  category_code: string;
  equipment_preset?: string;
  inspection_direction: string;
  target_flow: string;
  equipment_kind?: string;
  equipment_mark?: string;
  default_data: Record<string, unknown>;
  is_active?: boolean;
}

const DIRECTIONS = [
  { value: 'external', label: 'НиВО / осмотр' },
  { value: 'internal', label: 'ЭПБ / внутренний' },
  { value: 'technical', label: 'ТД' },
  { value: 'hydraulic', label: 'ГИ / опрессовка' },
  { value: 'pneumatic', label: 'ПИ' },
];

const FLOWS = [
  { value: 'vessel_checklist', label: 'Чек-лист сосуда' },
  { value: 'ndk_protocol', label: 'Протокол НК' },
  { value: 'pressure_test', label: 'Опрессовка' },
  { value: 'questionnaire', label: 'Опросный лист' },
];

function toPayload(edit: TemplateRow, defaultData: Record<string, unknown>) {
  return {
    name: edit.name,
    description: edit.description ?? null,
    category_code: edit.category_code,
    equipment_preset: edit.equipment_preset ?? null,
    inspection_direction: edit.inspection_direction,
    target_flow: edit.target_flow,
    equipment_kind: edit.equipment_kind ?? null,
    equipment_mark: edit.equipment_mark ?? null,
    default_data: defaultData,
  };
}

export default function InspectionObjectTemplatesManager() {
  const { token, user } = useAuth();
  const canEdit =
    user?.role === 'admin' ||
    user?.role === 'chief_operator' ||
    user?.role === 'operator';

  const [items, setItems] = useState<TemplateRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [edit, setEdit] = useState<TemplateRow | null>(null);
  const [jsonData, setJsonData] = useState('{}');

  const headers = useCallback(
    () => ({
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    }),
    [token],
  );

  const load = useCallback(async () => {
    if (!token) return;
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(
        `${API_BASE}/api/inspection-object-templates?active_only=false`,
        { headers: headers() },
      );
      if (!res.ok) throw new Error(await res.text());
      setItems(await res.json());
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [token, headers]);

  useEffect(() => {
    load();
  }, [load]);

  const openEdit = (row: TemplateRow) => {
    setEdit({ ...row });
    setJsonData(JSON.stringify(row.default_data ?? {}, null, 2));
  };

  const openNew = () => {
    setEdit({
      id: '',
      name: '',
      category_code: 'srpd',
      inspection_direction: 'external',
      target_flow: 'vessel_checklist',
      default_data: { inspection_type: 'VISUAL' },
    });
    setJsonData(JSON.stringify({ inspection_type: 'VISUAL' }, null, 2));
  };

  const save = async () => {
    if (!edit || !token) return;
    setError(null);
    try {
      const defaultData = JSON.parse(jsonData) as Record<string, unknown>;
      const payload = toPayload(edit, defaultData);
      const isNew = !edit.id;
      const url = isNew
        ? `${API_BASE}/api/inspection-object-templates`
        : `${API_BASE}/api/inspection-object-templates/${edit.id}`;
      const res = await fetch(url, {
        method: isNew ? 'POST' : 'PATCH',
        headers: headers(),
        body: JSON.stringify(payload),
      });
      if (!res.ok) throw new Error(await res.text());
      setEdit(null);
      await load();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const remove = async (id: string) => {
    if (!confirm('Деактивировать шаблон?')) return;
    await fetch(`${API_BASE}/api/inspection-object-templates/${id}`, {
      method: 'DELETE',
      headers: headers(),
    });
    await load();
  };

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <div className="flex flex-wrap items-center gap-3 mb-6">
        <h1 className="text-xl font-semibold text-app-text flex-1">
          Шаблоны обследования объектов
        </h1>
        <button type="button" onClick={load} className="btn-secondary flex items-center gap-2 text-sm">
          <RefreshCw size={16} />
          Обновить
        </button>
        {canEdit && (
          <button type="button" onClick={openNew} className="btn-primary flex items-center gap-2 text-sm">
            <Plus size={16} />
            Добавить
          </button>
        )}
      </div>

      <p className="text-sm text-app-text3 mb-4">
        Предзаполнение акта/чек-листа при выборе оборудования в мобильном приложении (категория + направление обследования).
      </p>

      {error && (
        <div className="mb-4 p-3 rounded-lg bg-red-500/10 border border-red-500/30 flex gap-2 text-red-400 text-sm">
          <AlertCircle size={18} />
          {error}
        </div>
      )}

      {loading ? (
        <p className="text-app-text3">Загрузка…</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-app-border">
          <table className="w-full text-sm text-left">
            <thead className="bg-app-surface2 text-app-text3">
              <tr>
                <th className="p-3">Название</th>
                <th className="p-3">Категория</th>
                <th className="p-3">Направление</th>
                <th className="p-3">Поток</th>
                <th className="p-3"></th>
              </tr>
            </thead>
            <tbody>
              {items.map((row) => (
                <tr key={row.id} className="border-t border-app-border hover:bg-app-surface2/50">
                  <td className="p-3 text-app-text">
                    {row.name}
                    {!row.is_active && (
                      <span className="ml-2 text-xs text-app-text3">(выкл.)</span>
                    )}
                  </td>
                  <td className="p-3">{row.category_code}</td>
                  <td className="p-3">{row.inspection_direction}</td>
                  <td className="p-3">{row.target_flow}</td>
                  <td className="p-3 text-right whitespace-nowrap">
                    <button
                      type="button"
                      className="text-[var(--accent)] mr-3"
                      onClick={() => openEdit(row)}
                    >
                      Изменить
                    </button>
                    {canEdit && (
                      <button
                        type="button"
                        className="text-red-400"
                        onClick={() => remove(row.id)}
                      >
                        <Trash2 size={14} className="inline" />
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {edit && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="bg-app-surface rounded-xl border border-app-border w-full max-w-lg max-h-[90vh] overflow-y-auto p-6">
            <h2 className="text-lg font-semibold text-app-text mb-4">
              {edit.id ? 'Редактировать шаблон' : 'Новый шаблон'}
            </h2>
            <div className="space-y-3">
              <input
                className="w-full p-2 rounded border border-app-border bg-app-surface2 text-app-text"
                placeholder="Название"
                value={edit.name}
                onChange={(e) => setEdit({ ...edit, name: e.target.value })}
              />
              <input
                className="w-full p-2 rounded border border-app-border bg-app-surface2 text-app-text"
                placeholder="category_code (srpd, bu, …)"
                value={edit.category_code}
                onChange={(e) => setEdit({ ...edit, category_code: e.target.value })}
              />
              <select
                className="w-full p-2 rounded border border-app-border bg-app-surface2 text-app-text"
                value={edit.inspection_direction}
                onChange={(e) =>
                  setEdit({ ...edit, inspection_direction: e.target.value })
                }
              >
                {DIRECTIONS.map((d) => (
                  <option key={d.value} value={d.value}>
                    {d.label}
                  </option>
                ))}
              </select>
              <select
                className="w-full p-2 rounded border border-app-border bg-app-surface2 text-app-text"
                value={edit.target_flow}
                onChange={(e) => setEdit({ ...edit, target_flow: e.target.value })}
              >
                {FLOWS.map((f) => (
                  <option key={f.value} value={f.value}>
                    {f.label}
                  </option>
                ))}
              </select>
              <textarea
                className="w-full min-h-[160px] font-mono text-xs p-2 rounded border border-app-border bg-app-surface2 text-app-text"
                value={jsonData}
                onChange={(e) => setJsonData(e.target.value)}
              />
            </div>
            <div className="flex justify-end gap-2 mt-6">
              <button type="button" className="btn-secondary" onClick={() => setEdit(null)}>
                Отмена
              </button>
              {canEdit && (
                <button type="button" className="btn-primary flex items-center gap-2" onClick={save}>
                  <Save size={16} />
                  Сохранить
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
