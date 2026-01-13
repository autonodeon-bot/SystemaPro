import React, { useEffect, useMemo, useState } from 'react';
import { Plus, Trash2, Save, RefreshCw, Edit3, Upload, X } from 'lucide-react';

interface EquipmentType {
  id: string;
  name: string;
  code?: string;
}

interface ReportTemplate {
  id: string;
  name: string;
  report_type: string;
  format: string;
  equipment_type_id?: string | null;
  is_active: boolean;
  definition?: any;
  created_at?: string;
  updated_at?: string;
}

const API_BASE = 'http://5.129.203.182:8000';

const ReportTemplates = () => {
  const [templates, setTemplates] = useState<ReportTemplate[]>([]);
  const [equipmentTypes, setEquipmentTypes] = useState<EquipmentType[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<ReportTemplate | null>(null);
  const [editTab, setEditTab] = useState<'visual' | 'json'>('visual');
  const [definitionDraft, setDefinitionDraft] = useState<any>(null);
  const [definitionJson, setDefinitionJson] = useState<string>('');
  const [uploadingLogo, setUploadingLogo] = useState(false);

  const token = useMemo(() => localStorage.getItem('token'), []);

  const headers: HeadersInit = useMemo(
    () => ({
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    }),
    [token]
  );

  const loadAll = async () => {
    setLoading(true);
    try {
      const [tplRes, typesRes] = await Promise.all([
        fetch(`${API_BASE}/api/report-templates`, { headers }),
        fetch(`${API_BASE}/api/equipment-types`),
      ]);
      const tpl = tplRes.ok ? await tplRes.json() : [];
      const types = typesRes.ok ? await typesRes.json() : { items: [] };
      setTemplates(Array.isArray(tpl) ? tpl : []);
      setEquipmentTypes(types.items || []);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const createTemplate = async () => {
    setCreating(true);
    try {
      const res = await fetch(`${API_BASE}/api/report-templates`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          name: 'Новый шаблон',
          report_type: 'DIAGNOSTICS',
          format: 'docx',
          equipment_type_id: null,
          is_active: true,
        }),
      });
      if (res.ok) {
        const item = await res.json();
        setTemplates((prev) => [item, ...prev]);
      }
    } finally {
      setCreating(false);
    }
  };

  const updateTemplate = async (id: string, patch: Partial<ReportTemplate>) => {
    setSaving(id);
    try {
      const res = await fetch(`${API_BASE}/api/report-templates/${id}`, {
        method: 'PUT',
        headers,
        body: JSON.stringify(patch),
      });
      if (res.ok) {
        const item = await res.json();
        setTemplates((prev) => prev.map((t) => (t.id === id ? item : t)));
        // если сейчас редактируем — обновим объект
        if (editing?.id === id) {
          setEditing(item);
        }
      }
    } finally {
      setSaving(null);
    }
  };

  const openEditor = (t: ReportTemplate) => {
    const def = t.definition || {
      logo_path: '/app/reports/assets/yutar_logo.png',
      fields: {
        contractor_name: 'ООО «ЮТАР»',
        director_title: 'Генеральный директор',
        director_name: '__________________',
        report_city: 'г. Урай',
      },
      sections: [
        { key: 'title', enabled: true },
        { key: 'toc', enabled: true },
        { key: 'sections_1_15', enabled: true },
        { key: 'appendices', enabled: true },
      ],
    };
    setEditing(t);
    setEditTab('visual');
    setDefinitionDraft(def);
    setDefinitionJson(JSON.stringify(def, null, 2));
  };

  const saveDefinition = async () => {
    if (!editing) return;
    if (editTab === 'json') {
      try {
        const parsed = JSON.parse(definitionJson);
        await updateTemplate(editing.id, { definition: parsed } as any);
        setDefinitionDraft(parsed);
      } catch (e: any) {
        alert(`JSON ошибка: ${e?.message || e}`);
        return;
      }
    } else {
      await updateTemplate(editing.id, { definition: definitionDraft } as any);
    }
  };

  const uploadLogo = async (file: File) => {
    if (!editing) return;
    setUploadingLogo(true);
    try {
      const form = new FormData();
      form.append('file', file);
      const res = await fetch(`${API_BASE}/api/report-templates/assets/logo`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
        body: form,
      });
      if (!res.ok) {
        const t = await res.text();
        throw new Error(t || String(res.status));
      }
      const data = await res.json();
      const path = data.path as string;
      const next = { ...(definitionDraft || {}), logo_path: path };
      setDefinitionDraft(next);
      setDefinitionJson(JSON.stringify(next, null, 2));
    } catch (e: any) {
      alert(`Ошибка загрузки логотипа: ${e?.message || e}`);
    } finally {
      setUploadingLogo(false);
    }
  };

  const deleteTemplate = async (id: string) => {
    if (!confirm('Удалить шаблон?')) return;
    const res = await fetch(`${API_BASE}/api/report-templates/${id}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${token}` },
    });
    if (res.ok) {
      setTemplates((prev) => prev.filter((t) => t.id !== id));
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Шаблоны отчетов (MVP)</h1>
          <p className="text-slate-400 text-sm mt-1">
            Настройка, какой тип отчета и формат использовать для разных типов оборудования.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={loadAll}
            className="px-3 py-2 rounded bg-slate-700 hover:bg-slate-600 text-white inline-flex items-center gap-2"
            title="Обновить"
          >
            <RefreshCw size={16} /> Обновить
          </button>
          <button
            onClick={createTemplate}
            disabled={creating}
            className="px-3 py-2 rounded bg-accent hover:bg-blue-600 disabled:opacity-50 text-white inline-flex items-center gap-2"
          >
            <Plus size={16} /> Добавить
          </button>
        </div>
      </div>

      {loading ? (
        <div className="text-slate-400">Загрузка...</div>
      ) : (
        <div className="space-y-3">
          {templates.length === 0 ? (
            <div className="text-slate-400">Шаблонов нет</div>
          ) : (
            templates.map((t) => (
              <div key={t.id} className="bg-slate-800 border border-slate-700 rounded-xl p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1 grid grid-cols-1 md:grid-cols-4 gap-3">
                    <div>
                      <label className="text-xs text-slate-400">Название</label>
                      <input
                        className="mt-1 w-full bg-slate-900 border border-slate-700 rounded px-3 py-2 text-white"
                        value={t.name}
                        onChange={(e) =>
                          setTemplates((prev) =>
                            prev.map((x) => (x.id === t.id ? { ...x, name: e.target.value } : x))
                          )
                        }
                      />
                    </div>
                    <div>
                      <label className="text-xs text-slate-400">Тип отчета</label>
                      <select
                        className="mt-1 w-full bg-slate-900 border border-slate-700 rounded px-3 py-2 text-white"
                        value={t.report_type}
                        onChange={(e) => updateTemplate(t.id, { report_type: e.target.value })}
                      >
                        <option value="DIAGNOSTICS">DIAGNOSTICS</option>
                        <option value="TECHNICAL">TECHNICAL</option>
                        <option value="EXPERTISE">EXPERTISE</option>
                      </select>
                    </div>
                    <div>
                      <label className="text-xs text-slate-400">Формат</label>
                      <select
                        className="mt-1 w-full bg-slate-900 border border-slate-700 rounded px-3 py-2 text-white"
                        value={t.format}
                        onChange={(e) => updateTemplate(t.id, { format: e.target.value })}
                      >
                        <option value="docx">DOCX</option>
                        <option value="pdf">PDF</option>
                      </select>
                    </div>
                    <div>
                      <label className="text-xs text-slate-400">Тип оборудования</label>
                      <select
                        className="mt-1 w-full bg-slate-900 border border-slate-700 rounded px-3 py-2 text-white"
                        value={t.equipment_type_id || ''}
                        onChange={(e) =>
                          updateTemplate(t.id, { equipment_type_id: e.target.value || null })
                        }
                      >
                        <option value="">(По умолчанию)</option>
                        {equipmentTypes.map((et) => (
                          <option key={et.id} value={et.id}>
                            {et.name}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div className="md:col-span-4 flex items-center gap-3">
                      <label className="flex items-center gap-2 text-slate-300 text-sm">
                        <input
                          type="checkbox"
                          checked={t.is_active}
                          onChange={(e) => updateTemplate(t.id, { is_active: e.target.checked })}
                        />
                        Активен
                      </label>
                      {saving === t.id && (
                        <span className="text-xs text-slate-400 inline-flex items-center gap-2">
                          <Save size={14} /> Сохранение...
                        </span>
                      )}
                    </div>
                  </div>
                  <button
                    onClick={() => openEditor(t)}
                    className="px-3 py-2 rounded bg-slate-700 hover:bg-slate-600 text-white inline-flex items-center gap-2"
                    title="Редактор макета"
                  >
                    <Edit3 size={16} />
                  </button>
                  <button
                    onClick={() => updateTemplate(t.id, { name: t.name })}
                    className="px-3 py-2 rounded bg-slate-700 hover:bg-slate-600 text-white inline-flex items-center gap-2"
                    title="Сохранить имя"
                  >
                    <Save size={16} />
                  </button>
                  <button
                    onClick={() => deleteTemplate(t.id)}
                    className="px-3 py-2 rounded bg-red-600 hover:bg-red-700 text-white inline-flex items-center gap-2"
                    title="Удалить"
                  >
                    <Trash2 size={16} />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Модалка редактора макета */}
      {editing && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50" onClick={() => setEditing(null)}>
          <div className="bg-slate-800 border border-slate-700 rounded-xl w-full max-w-3xl mx-4" onClick={(e) => e.stopPropagation()}>
            <div className="p-4 border-b border-slate-700 flex items-center justify-between">
              <div>
                <div className="text-white font-bold">Редактор макета: {editing.name}</div>
                <div className="text-slate-400 text-xs">{editing.report_type} • {String(editing.format).toUpperCase()}</div>
              </div>
              <button className="text-slate-400 hover:text-white" onClick={() => setEditing(null)}>
                <X size={20} />
              </button>
            </div>

            <div className="p-4 space-y-4">
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setEditTab('visual')}
                  className={`px-3 py-2 rounded ${editTab === 'visual' ? 'bg-accent text-white' : 'bg-slate-700 text-slate-200'}`}
                >
                  Визуально
                </button>
                <button
                  onClick={() => setEditTab('json')}
                  className={`px-3 py-2 rounded ${editTab === 'json' ? 'bg-accent text-white' : 'bg-slate-700 text-slate-200'}`}
                >
                  JSON
                </button>
              </div>

              {editTab === 'visual' ? (
                <div className="space-y-4">
                  <div className="bg-slate-900 border border-slate-700 rounded-lg p-4">
                    <div className="text-white font-semibold mb-3">Логотип титульного листа</div>
                    <div className="flex items-center gap-3">
                      <div className="text-slate-300 text-sm flex-1 break-all">
                        Путь: <span className="text-slate-100">{String(definitionDraft?.logo_path || '')}</span>
                      </div>
                      <label className="px-3 py-2 rounded bg-slate-700 hover:bg-slate-600 text-white inline-flex items-center gap-2 cursor-pointer">
                        <Upload size={16} />
                        {uploadingLogo ? 'Загрузка...' : 'Загрузить'}
                        <input
                          type="file"
                          accept="image/*"
                          className="hidden"
                          onChange={(e) => {
                            const f = e.target.files?.[0];
                            if (f) uploadLogo(f);
                          }}
                        />
                      </label>
                    </div>
                    <div className="text-slate-500 text-xs mt-2">Файл сохраняется на сервер: `/app/reports/assets/yutar_logo.png`</div>
                  </div>

                  <div className="bg-slate-900 border border-slate-700 rounded-lg p-4">
                    <div className="text-white font-semibold mb-3">Поля титульного листа</div>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                      {[
                        ['contractor_name', 'Организация'],
                        ['director_title', 'Должность'],
                        ['director_name', 'ФИО директора'],
                        ['report_city', 'Город'],
                      ].map(([key, label]) => (
                        <div key={key}>
                          <label className="text-xs text-slate-400">{label}</label>
                          <input
                            className="mt-1 w-full bg-slate-800 border border-slate-700 rounded px-3 py-2 text-white"
                            value={String(definitionDraft?.fields?.[key] || '')}
                            onChange={(e) => {
                              const next = {
                                ...(definitionDraft || {}),
                                fields: { ...(definitionDraft?.fields || {}), [key]: e.target.value },
                              };
                              setDefinitionDraft(next);
                              setDefinitionJson(JSON.stringify(next, null, 2));
                            }}
                          />
                        </div>
                      ))}
                    </div>
                  </div>

                  <div className="bg-slate-900 border border-slate-700 rounded-lg p-4">
                    <div className="text-white font-semibold mb-3">Разделы</div>
                    <div className="space-y-2">
                      {(definitionDraft?.sections || []).map((s: any, idx: number) => (
                        <label key={String(s.key) + idx} className="flex items-center gap-2 text-slate-200 text-sm">
                          <input
                            type="checkbox"
                            checked={!!s.enabled}
                            onChange={(e) => {
                              const arr = [...(definitionDraft?.sections || [])];
                              arr[idx] = { ...arr[idx], enabled: e.target.checked };
                              const next = { ...(definitionDraft || {}), sections: arr };
                              setDefinitionDraft(next);
                              setDefinitionJson(JSON.stringify(next, null, 2));
                            }}
                          />
                          {String(s.key)}
                        </label>
                      ))}
                    </div>
                  </div>
                </div>
              ) : (
                <div className="space-y-2">
                  <textarea
                    className="w-full h-80 bg-slate-900 border border-slate-700 rounded p-3 text-slate-100 font-mono text-xs"
                    value={definitionJson}
                    onChange={(e) => setDefinitionJson(e.target.value)}
                  />
                  <div className="text-slate-500 text-xs">Можно редактировать весь JSON целиком. Сохранение валидирует JSON.</div>
                </div>
              )}
            </div>

            <div className="p-4 border-t border-slate-700 flex items-center justify-end gap-2">
              <button
                onClick={() => setEditing(null)}
                className="px-4 py-2 rounded bg-slate-700 hover:bg-slate-600 text-white"
              >
                Закрыть
              </button>
              <button
                onClick={saveDefinition}
                className="px-4 py-2 rounded bg-accent hover:bg-blue-600 text-white inline-flex items-center gap-2"
              >
                <Save size={16} />
                Сохранить макет
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ReportTemplates;

