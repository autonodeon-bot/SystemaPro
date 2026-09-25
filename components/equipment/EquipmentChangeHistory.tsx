import { useEffect, useState } from 'react';
import { API_BASE } from '../../constants';

interface Entry { id: string; actor: string; created_at: string; details: {
  source?: string; before?: Record<string, unknown>; after?: Record<string, unknown>; conflicts?: string[];
} }

export default function EquipmentChangeHistory({ equipmentId }: {equipmentId: string}) {
  const [items, setItems] = useState<Entry[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true); setError('');
    fetch(`${API_BASE}/api/equipment/${equipmentId}/change-history`, { signal: controller.signal,
      headers: { Authorization: `Bearer ${localStorage.getItem('token') ?? ''}` },
    }).then(async response => {
      if (!response.ok) throw new Error(response.status === 403 ? 'История доступна сотрудникам с правом редактирования.' : 'Не удалось загрузить историю.');
      setItems((await response.json()).items ?? []);
    }).catch(reason => { if (!controller.signal.aborted) setError(reason.message); })
      .finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [equipmentId, revision]);
  const show = (value: unknown) => value === null || value === undefined || value === '' ? 'Не заполнено'
    : typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value);
  return <section className="bg-app-deep rounded-lg p-4 border border-app-line">
    <h3 className="text-lg font-semibold mb-3">История изменений</h3>
    {loading ? <p role="status">Загрузка…</p> : error ? <p role="alert">{error} <button type="button" className="ind-btn" onClick={() => setRevision(value => value + 1)}>Повторить</button></p>
      : !items.length ? <p className="text-app-text3">Изменений пока нет. Журнал ведется с момента обновления системы.</p> : items.map(item => {
        const before = item.details.before ?? {}; const after = item.details.after ?? {};
        return <details key={item.id} className="border-t border-app-line py-3">
          <summary className="cursor-pointer break-words">{new Date(item.created_at).toLocaleString('ru-RU')} · {item.actor} · {item.details.source === 'mobile_inspection' ? 'Мобильное обследование' : 'Карточка оборудования'}</summary>
          {Object.keys({...before, ...after}).filter(key => JSON.stringify(before[key]) !== JSON.stringify(after[key])).map(key =>
            <div key={key} className="mt-3"><strong>{({name: 'Название', attributes: 'Характеристики', serial_number: 'Заводской номер', location: 'Расположение', commissioning_date: 'Дата ввода'} as Record<string, string>)[key] ?? key}</strong>
              <div className="grid sm:grid-cols-2 gap-2 mt-1"><pre className="whitespace-pre-wrap break-words text-xs">Было: {show(before[key])}</pre><pre className="whitespace-pre-wrap break-words text-xs">Стало: {show(after[key])}</pre></div>
            </div>)}
          {!!item.details.conflicts?.length && <p className="mt-2">Сохранены значения оператора: {item.details.conflicts.join(', ')}</p>}
        </details>;
      })}
  </section>;
}
