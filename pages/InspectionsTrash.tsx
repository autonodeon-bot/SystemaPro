import React, { useState, useEffect } from 'react';
import { Trash2, RotateCcw, AlertTriangle, RefreshCw, Shield, Clock } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

const API_BASE = import.meta.env.VITE_API_URL || '';

interface DeletedInspection {
  id: string;
  equipment_id: string | null;
  status: string;
  inspection_type: string | null;
  deleted_at: string | null;
  days_left_to_restore: number | null;
}

const InspectionsTrash: React.FC = () => {
  const { token, user } = useAuth();

  const [items, setItems] = useState<DeletedInspection[]>([]);
  const [loading, setLoading] = useState(true);
  const [purging, setPurging] = useState(false);
  const [restoringId, setRestoringId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { load(); }, []);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/api/inspections-trash`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) throw new Error(`Ошибка ${res.status}`);
      const data = await res.json();
      setItems(data.items || []);
    } catch (e: unknown) {
      setError((e as Error).message || 'Ошибка загрузки');
    }
    setLoading(false);
  }

  async function restore(id: string) {
    if (!window.confirm('Восстановить обследование?')) return;
    setRestoringId(id);
    try {
      const res = await fetch(`${API_BASE}/api/inspections/${id}/restore`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) throw new Error(`Ошибка ${res.status}`);
      await load();
    } catch (e: unknown) {
      alert((e as Error).message || 'Ошибка восстановления');
    }
    setRestoringId(null);
  }

  async function purge(days: number) {
    if (!window.confirm(
      `Физически удалить все записи в корзине старше ${days} дней?\n\nЭто действие нельзя отменить!`
    )) return;
    setPurging(true);
    try {
      const res = await fetch(
        `${API_BASE}/api/inspections-trash/purge?older_than_days=${days}`,
        { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } }
      );
      if (!res.ok) throw new Error(`Ошибка ${res.status}`);
      const data = await res.json();
      alert(`Удалено: ${data.deleted_count} записей`);
      await load();
    } catch (e: unknown) {
      alert((e as Error).message || 'Ошибка очистки');
    }
    setPurging(false);
  }

  function formatDate(iso: string | null) {
    if (!iso) return '—';
    try { return new Date(iso).toLocaleString('ru-RU'); } catch { return iso; }
  }

  function daysColor(days: number | null) {
    if (days === null) return 'text-app-text3';
    if (days <= 7) return 'text-red-400 font-bold';
    if (days <= 20) return 'text-orange-400';
    return 'text-green-400';
  }

  const isAdmin = user?.role === 'admin';

  return (
    <div className="space-y-6 max-w-5xl mx-auto">
      {/* Заголовок */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Trash2 size={26} className="text-red-400" />
            Корзина обследований
          </h1>
          <p className="text-app-text3 text-sm mt-1">
            Мягко удалённые обследования хранятся 60 дней, после чего удаляются автоматически
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <button
            onClick={load}
            disabled={loading}
            className="flex items-center gap-2 px-3 py-2 bg-app-soft hover:bg-app-softer text-app-text rounded-lg text-sm transition"
          >
            <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
            Обновить
          </button>
          {isAdmin && (
            <>
              <button
                onClick={() => purge(60)}
                disabled={purging}
                className="flex items-center gap-2 px-3 py-2 bg-orange-700 hover:bg-orange-600 text-white rounded-lg text-sm transition"
              >
                <Shield size={14} /> Очистить (60+ дней)
              </button>
              <button
                onClick={() => purge(0)}
                disabled={purging}
                className="flex items-center gap-2 px-3 py-2 bg-red-700 hover:bg-red-600 text-white rounded-lg text-sm transition"
              >
                <Trash2 size={14} /> Очистить всё
              </button>
            </>
          )}
        </div>
      </div>

      {/* Предупреждение */}
      <div className="bg-yellow-900/20 border border-yellow-700/50 rounded-xl p-4 flex gap-3">
        <AlertTriangle size={20} className="text-yellow-400 shrink-0 mt-0.5" />
        <div className="text-sm text-yellow-200">
          <strong>П.5.1 — Защита от случайного удаления.</strong> Удалённые обследования хранятся здесь 60 дней.
          Восстановить может автор записи, старший оператор или администратор.
          По истечении срока запись удаляется физически вместе с файлами отчётов.
        </div>
      </div>

      {/* Контент */}
      {loading ? (
        <div className="flex justify-center py-16">
          <div className="w-8 h-8 border-4 border-accent border-t-transparent rounded-full animate-spin" />
        </div>
      ) : error ? (
        <div className="text-center text-red-400 py-12">
          <AlertTriangle size={40} className="mx-auto mb-3 opacity-60" />
          <p>{error}</p>
        </div>
      ) : items.length === 0 ? (
        <div className="text-center text-app-text3 py-16">
          <Trash2 size={48} className="mx-auto mb-4 opacity-30" />
          <p className="text-lg">Корзина пуста</p>
          <p className="text-sm mt-1">Удалённые обследования будут отображаться здесь</p>
        </div>
      ) : (
        <div className="bg-secondary rounded-xl border border-app-line overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-app-soft/50 text-app-text2 text-xs">
                  <th className="px-4 py-3 text-left">ID обследования</th>
                  <th className="px-4 py-3 text-left">Тип</th>
                  <th className="px-4 py-3 text-left">Статус</th>
                  <th className="px-4 py-3 text-left">Дата удаления</th>
                  <th className="px-4 py-3 text-left">
                    <span className="flex items-center gap-1">
                      <Clock size={12} /> Осталось дней
                    </span>
                  </th>
                  <th className="px-4 py-3 text-center">Восстановить</th>
                </tr>
              </thead>
              <tbody>
                {items.map((item, idx) => (
                  <tr
                    key={item.id}
                    className={`border-t border-app-line hover:bg-white/5 transition ${
                      idx % 2 === 1 ? 'bg-white/[0.02]' : ''
                    }`}
                  >
                    <td className="px-4 py-3">
                      <span className="font-mono text-xs text-app-text3">{item.id.slice(0, 8)}…</span>
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-white text-xs">{item.inspection_type || '—'}</span>
                    </td>
                    <td className="px-4 py-3">
                      <span className="inline-block px-2 py-0.5 bg-app-softer rounded text-xs text-app-text2">
                        {item.status || '—'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-app-text3 text-xs">
                      {formatDate(item.deleted_at)}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`text-sm ${daysColor(item.days_left_to_restore)}`}>
                        {item.days_left_to_restore !== null
                          ? `${item.days_left_to_restore} дн.`
                          : '—'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-center">
                      {(item.days_left_to_restore === null || item.days_left_to_restore > 0) ? (
                        <button
                          onClick={() => restore(item.id)}
                          disabled={restoringId === item.id}
                          className="inline-flex items-center gap-1 px-3 py-1.5 bg-green-700 hover:bg-green-600 text-white rounded-lg text-xs transition disabled:opacity-50"
                        >
                          <RotateCcw size={12} className={restoringId === item.id ? 'animate-spin' : ''} />
                          Восстановить
                        </button>
                      ) : (
                        <span className="text-xs text-red-400">Срок истёк</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="px-4 py-3 border-t border-app-line text-xs text-app-text3">
            Всего в корзине: {items.length} записей
          </div>
        </div>
      )}
    </div>
  );
};

export default InspectionsTrash;
