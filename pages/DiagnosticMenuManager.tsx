/**
 * Редактор структуры меню «Протокол → создать» для мобильного приложения.
 */
import React, { useCallback, useEffect, useState } from 'react';
import { Save, Upload, RotateCcw, RefreshCw, AlertCircle } from 'lucide-react';
import { API_BASE } from '../constants';
import { useAuth } from '../contexts/AuthContext';

function PageWrap({
  children,
  className = '',
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return <div className={`p-6 max-w-6xl mx-auto ${className}`}>{children}</div>;
}

export default function DiagnosticMenuManager() {
  const { token, user } = useAuth();
  const canEdit = user?.role === 'admin' || user?.role === 'chief_operator';

  const [jsonText, setJsonText] = useState('');
  const [version, setVersion] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const headers = useCallback(
    () => ({
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    }),
    [token],
  );

  const loadMenu = useCallback(
    async (draft: boolean) => {
      if (!token) return;
      setLoading(true);
      setError(null);
      try {
        const res = await fetch(
          `${API_BASE}/api/diagnostic-menu?draft=${draft ? 'true' : 'false'}`,
          { headers: headers() },
        );
        if (!res.ok) throw new Error(await res.text());
        const data = await res.json();
        setVersion(data.version ?? null);
        setJsonText(JSON.stringify(data.payload ?? {}, null, 2));
      } catch (e: unknown) {
        setError(e instanceof Error ? e.message : String(e));
      } finally {
        setLoading(false);
      }
    },
    [token, headers],
  );

  useEffect(() => {
    loadMenu(canEdit);
  }, [canEdit, loadMenu]);

  const saveDraft = async () => {
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const payload = JSON.parse(jsonText);
      const res = await fetch(`${API_BASE}/api/diagnostic-menu/draft`, {
        method: 'PUT',
        headers: headers(),
        body: JSON.stringify(payload),
      });
      if (!res.ok) throw new Error(await res.text());
      setMessage('Черновик сохранён');
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const publish = async () => {
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const payload = JSON.parse(jsonText);
      const saveRes = await fetch(`${API_BASE}/api/diagnostic-menu/draft`, {
        method: 'PUT',
        headers: headers(),
        body: JSON.stringify(payload),
      });
      if (!saveRes.ok) throw new Error(await saveRes.text());
      const res = await fetch(`${API_BASE}/api/diagnostic-menu/publish`, {
        method: 'POST',
        headers: headers(),
      });
      if (!res.ok) throw new Error(await res.text());
      const data = await res.json();
      setMessage(`Опубликовано (версия ${data.version})`);
      await loadMenu(true);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const resetDraft = async () => {
    setSaving(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/api/diagnostic-menu/reset-draft`, {
        method: 'POST',
        headers: headers(),
      });
      if (!res.ok) throw new Error(await res.text());
      const data = await res.json();
      setJsonText(JSON.stringify(data.payload ?? {}, null, 2));
      setMessage('Черновик сброшен к опубликованной версии');
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  if (!canEdit) {
    return (
      <PageWrap>
        <p className="text-app-text2 text-sm">
          Просмотр опубликованной структуры. Редактирование — для admin и chief_operator.
        </p>
        {loading ? (
          <p className="text-app-text3 mt-4">Загрузка…</p>
        ) : (
          <pre className="mt-4 p-4 rounded-lg bg-app-panel border border-app-line text-xs overflow-auto max-h-[70vh] text-app-text2">
            {jsonText}
          </pre>
        )}
      </PageWrap>
    );
  }

  return (
    <PageWrap>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <h1 className="text-xl font-semibold text-app-text flex-1 min-w-[200px]">
          Меню диагностики (мобильное)
        </h1>
        {version != null && (
          <span className="text-xs text-app-text3">Опубликовано: v{version}</span>
        )}
        <button type="button" onClick={() => loadMenu(true)} className="btn-secondary flex items-center gap-2 text-sm" disabled={loading}>
          <RefreshCw size={16} />
          Обновить
        </button>
        <button type="button" onClick={resetDraft} className="btn-secondary flex items-center gap-2 text-sm" disabled={saving}>
          <RotateCcw size={16} />
          Сбросить
        </button>
        <button type="button" onClick={saveDraft} className="btn-primary flex items-center gap-2 text-sm" disabled={saving}>
          <Save size={16} />
          Черновик
        </button>
        <button
          type="button"
          onClick={publish}
          className="btn-primary flex items-center gap-2 text-sm"
          style={{ background: 'var(--success, #059669)' }}
          disabled={saving}
        >
          <Upload size={16} />
          Опубликовать
        </button>
      </div>

      <p className="text-sm text-app-text3 mb-3">
        Быстрый контроль, категории нового протокола и пункты меню. После публикации мобильное приложение обновит меню при следующей загрузке.
      </p>

      {error && (
        <div className="mb-3 p-3 rounded-lg bg-red-500/10 border border-red-500/30 flex gap-2 text-red-400 text-sm">
          <AlertCircle size={18} className="shrink-0" />
          {error}
        </div>
      )}
      {message && <p className="mb-3 text-sm text-emerald-400">{message}</p>}

      {loading ? (
        <p className="text-app-text3">Загрузка…</p>
      ) : (
        <textarea
          className="w-full min-h-[480px] font-mono text-xs p-4 rounded-lg border border-app-line bg-app-panel text-app-text caret-app-text placeholder:text-app-text3 focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
          value={jsonText}
          onChange={(e) => setJsonText(e.target.value)}
          spellCheck={false}
        />
      )}
    </PageWrap>
  );
}
