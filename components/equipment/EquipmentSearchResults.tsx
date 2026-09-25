import { useEffect, useState } from 'react';
import { Pencil, Trash2, ArrowRight } from 'lucide-react';
import { API_BASE } from '../../constants';
import { useAuth } from '../../contexts/AuthContext';
import type { Equipment } from './types';

interface Props { query: string; onEdit: (item: Equipment, workshopId: string) => void; onDelete: (id: string, workshopId?: string) => void; onOpen: (id: string) => void }
export default function EquipmentSearchResults({ query, onEdit, onDelete, onOpen }: Props) {
  const { getToken } = useAuth();
  const token = getToken();
  const [items, setItems] = useState<Equipment[]>([]);
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    const abort = new AbortController();
    setLoading(true); setError('');
    const timer = window.setTimeout(async () => {
      try {
        const response = await fetch(`${API_BASE}/api/equipment?search=${encodeURIComponent(query)}&limit=50&offset=${page * 50}`, {
          headers: { Authorization: `Bearer ${token}` }, signal: abort.signal,
        });
        if (!response.ok) throw new Error(`Не удалось выполнить поиск (${response.status})`);
        const data = await response.json();
        if (!abort.signal.aborted) setItems(data.items ?? []);
      } catch (err) {
        if (!abort.signal.aborted) setError(err instanceof Error ? err.message : 'Ошибка поиска');
      } finally { if (!abort.signal.aborted) setLoading(false); }
    }, 250);
    return () => { clearTimeout(timer); abort.abort(); };
  }, [query, page, token, retry]);
  return <section className="sp-surface p-4" aria-label="Результаты поиска оборудования" aria-busy={loading}>
    {loading ? <p role="status" className="sp-empty">Поиск оборудования…</p> : error ? <div role="alert">{error} <button className="ind-btn" onClick={() => setRetry(n => n + 1)}>Повторить</button></div> : <>
      <p className="sp-hint mb-3">По названию, заводскому номеру и расположению · страница {page + 1}</p>
      {items.length === 0 && <p className="sp-empty">Оборудование не найдено. Попробуйте другое название или номер.</p>}
      {items.map(item => <div key={item.id} className="flex flex-wrap items-center justify-between gap-3 border-b border-app-line py-3">
        <button type="button" className="text-left min-w-0 flex-1" onClick={() => onOpen(item.id)}>
          <strong className="block break-words">{item.name}</strong>
          <span className="text-sm text-app-text3 break-words">{[item.serial_number && `№ ${item.serial_number}`, item.location].filter(Boolean).join(' · ') || 'Расположение не указано'}</span>
        </button>
        <div className="flex gap-1">
          <button className="sp-icon-button" title="Редактировать" aria-label={`Редактировать ${item.name}`} onClick={() => onEdit(item, item.workshop_id ?? '')}><Pencil size={17} /></button>
          <button className="sp-icon-button" title="Удалить" aria-label={`Удалить ${item.name}`} onClick={() => onDelete(item.id, item.workshop_id)}><Trash2 size={17} /></button>
          <button className="sp-icon-button" title="Открыть карточку" aria-label={`Открыть ${item.name}`} onClick={() => onOpen(item.id)}><ArrowRight size={17} /></button>
        </div>
      </div>)}
      <div className="flex justify-between gap-3 mt-4">
        <button className="ind-btn" disabled={page === 0} onClick={() => setPage(p => p - 1)}>Назад</button>
        <button className="ind-btn" disabled={items.length < 50} onClick={() => setPage(p => p + 1)}>Далее</button>
      </div>
    </>}
  </section>;
}
