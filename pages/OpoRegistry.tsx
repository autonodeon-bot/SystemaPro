import React, { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, Edit2, RefreshCw, Save, X } from 'lucide-react';
import { API_BASE } from '../constants';

interface OpoItem {
  id: string;
  name: string;
  code?: string | null;
  description?: string | null;
  hazard_class?: string | null;
  registration_number?: string | null;
  workshop_id?: string | null;
}

/**
 * Реестр ОПО: класс опасности и регистрационный № —
 * нужны для титула отчёта ТО (замечания PDF).
 */
const OpoRegistry: React.FC = () => {
  const [items, setItems] = useState<OpoItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<OpoItem | null>(null);
  const [saving, setSaving] = useState(false);

  const token = () => localStorage.getItem('token') || '';

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/api/opos`, {
        headers: { Authorization: `Bearer ${token()}` },
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setItems(Array.isArray(data?.items) ? data.items : []);
    } catch (e: any) {
      setError(e?.message || 'Ошибка загрузки');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const save = async () => {
    if (!editing) return;
    setSaving(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/api/opos/${editing.id}`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token()}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: editing.name,
          code: editing.code,
          description: editing.description,
          hazard_class: editing.hazard_class || null,
          registration_number: editing.registration_number || null,
        }),
      });
      if (!res.ok) {
        const t = await res.text();
        throw new Error(t || `HTTP ${res.status}`);
      }
      setEditing(null);
      await load();
    } catch (e: any) {
      setError(e?.message || 'Ошибка сохранения');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="p-6 max-w-5xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-semibold text-app-text">Реестр ОПО</h1>
          <p className="text-sm text-app-text3 mt-1">
            Класс опасности и регистрационный номер подставляются в титул отчёта ТО
          </p>
        </div>
        <button
          type="button"
          onClick={load}
          className="inline-flex items-center gap-2 px-3 py-2 rounded-lg border border-app-border text-app-text2 hover:bg-app-surface2"
        >
          <RefreshCw className="w-4 h-4" />
          Обновить
        </button>
      </div>

      {error && (
        <div className="mb-4 flex items-start gap-2 p-3 rounded-lg bg-red-500/10 text-red-300 text-sm">
          <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {loading ? (
        <p className="text-app-text3">Загрузка…</p>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-app-border">
          <table className="w-full text-sm">
            <thead className="bg-app-surface2 text-app-text2 text-left">
              <tr>
                <th className="px-3 py-2 font-medium">Наименование</th>
                <th className="px-3 py-2 font-medium">Код</th>
                <th className="px-3 py-2 font-medium">Класс опасности</th>
                <th className="px-3 py-2 font-medium">Рег. № ОПО</th>
                <th className="px-3 py-2 w-16" />
              </tr>
            </thead>
            <tbody>
              {items.map((o) => (
                <tr key={o.id} className="border-t border-app-border text-app-text">
                  <td className="px-3 py-2">{o.name}</td>
                  <td className="px-3 py-2 text-app-text3">{o.code || '—'}</td>
                  <td className="px-3 py-2">{o.hazard_class || '—'}</td>
                  <td className="px-3 py-2">{o.registration_number || '—'}</td>
                  <td className="px-3 py-2">
                    <button
                      type="button"
                      className="p-1.5 rounded hover:bg-app-surface2 text-app-text2"
                      title="Редактировать"
                      onClick={() => setEditing({ ...o })}
                    >
                      <Edit2 className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-3 py-8 text-center text-app-text3">
                    ОПО не найдены
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {editing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
          <div className="w-full max-w-lg rounded-xl bg-app-surface border border-app-border p-5 shadow-xl">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-medium text-app-text">Редактирование ОПО</h2>
              <button type="button" onClick={() => setEditing(null)} className="text-app-text3">
                <X className="w-5 h-5" />
              </button>
            </div>
            <div className="space-y-3">
              <label className="block text-sm text-app-text2">
                Наименование
                <input
                  className="mt-1 w-full rounded-lg border border-app-border bg-app-surface2 px-3 py-2 text-app-text"
                  value={editing.name || ''}
                  onChange={(e) => setEditing({ ...editing, name: e.target.value })}
                />
              </label>
              <label className="block text-sm text-app-text2">
                Код (внутренний)
                <input
                  className="mt-1 w-full rounded-lg border border-app-border bg-app-surface2 px-3 py-2 text-app-text"
                  value={editing.code || ''}
                  onChange={(e) => setEditing({ ...editing, code: e.target.value })}
                />
              </label>
              <label className="block text-sm text-app-text2">
                Класс опасности ОПО
                <input
                  className="mt-1 w-full rounded-lg border border-app-border bg-app-surface2 px-3 py-2 text-app-text"
                  placeholder="например: III"
                  value={editing.hazard_class || ''}
                  onChange={(e) => setEditing({ ...editing, hazard_class: e.target.value })}
                />
              </label>
              <label className="block text-sm text-app-text2">
                Регистрационный № ОПО (Ростехнадзор)
                <input
                  className="mt-1 w-full rounded-lg border border-app-border bg-app-surface2 px-3 py-2 text-app-text"
                  placeholder="АXX-XXXXX"
                  value={editing.registration_number || ''}
                  onChange={(e) =>
                    setEditing({ ...editing, registration_number: e.target.value })
                  }
                />
              </label>
              <label className="block text-sm text-app-text2">
                Описание
                <textarea
                  className="mt-1 w-full rounded-lg border border-app-border bg-app-surface2 px-3 py-2 text-app-text"
                  rows={2}
                  value={editing.description || ''}
                  onChange={(e) => setEditing({ ...editing, description: e.target.value })}
                />
              </label>
            </div>
            <div className="mt-5 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setEditing(null)}
                className="px-3 py-2 rounded-lg border border-app-border text-app-text2"
              >
                Отмена
              </button>
              <button
                type="button"
                disabled={saving}
                onClick={save}
                className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-blue-600 text-white disabled:opacity-50"
              >
                <Save className="w-4 h-4" />
                {saving ? 'Сохранение…' : 'Сохранить'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default OpoRegistry;
