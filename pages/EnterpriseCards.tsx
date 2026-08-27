import { useEffect, useState } from 'react';
import { Building2, Save } from 'lucide-react';
import { API_BASE } from '../constants';

interface EnterpriseCard {
  id: string;
  name: string;
  code?: string;
  description?: string;
  director?: string;
  phone?: string;
  email?: string;
  legal_address?: string;
}

const emptyCard = (): Omit<EnterpriseCard, 'id'> => ({
  name: '',
  code: '',
  description: '',
  director: '',
  phone: '',
  email: '',
  legal_address: '',
});

const EnterpriseCards = () => {
  const [items, setItems] = useState<EnterpriseCard[]>([]);
  const [selectedId, setSelectedId] = useState<string>('');
  const [form, setForm] = useState(emptyCard());
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');

  const authHeaders = (): HeadersInit => {
    const headers: HeadersInit = { 'Content-Type': 'application/json' };
    const token = localStorage.getItem('token');
    if (token) headers.Authorization = `Bearer ${token}`;
    return headers;
  };

  const load = async () => {
    setLoading(true);
    try {
      const response = await fetch(`${API_BASE}/api/hierarchy/enterprises`, { headers: authHeaders() });
      if (!response.ok) throw new Error('Не удалось загрузить предприятия');
      const data = await response.json();
      const list: EnterpriseCard[] = Array.isArray(data.items) ? data.items : Array.isArray(data) ? data : [];
      setItems(list);
      if (list.length && !selectedId) {
        setSelectedId(list[0].id);
        setForm({
          name: list[0].name || '',
          code: list[0].code || '',
          description: list[0].description || '',
          director: list[0].director || '',
          phone: list[0].phone || '',
          email: list[0].email || '',
          legal_address: list[0].legal_address || '',
        });
      }
    } catch (e) {
      console.error(e);
      setMessage('Ошибка загрузки карточек предприятий');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const selectItem = (item: EnterpriseCard) => {
    setSelectedId(item.id);
    setForm({
      name: item.name || '',
      code: item.code || '',
      description: item.description || '',
      director: item.director || '',
      phone: item.phone || '',
      email: item.email || '',
      legal_address: item.legal_address || '',
    });
    setMessage('');
  };

  const handleSave = async () => {
    if (!selectedId) return;
    setSaving(true);
    setMessage('');
    try {
      const response = await fetch(`${API_BASE}/api/hierarchy/enterprises/${selectedId}`, {
        method: 'PUT',
        headers: authHeaders(),
        body: JSON.stringify(form),
      });
      if (!response.ok) throw new Error('Ошибка сохранения');
      const updated = await response.json();
      setItems((prev) => prev.map((it) => (it.id === selectedId ? { ...it, ...updated } : it)));
      setMessage('Карточка сохранена — данные подставятся в таблицы заказчика отчёта ТО');
    } catch (e) {
      console.error(e);
      setMessage('Не удалось сохранить карточку');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <div className="p-6 text-[var(--text-secondary)]">Загрузка карточек предприятий...</div>;
  }

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[var(--text-primary)] flex items-center gap-2">
          <Building2 size={22} /> Карточки предприятий
        </h1>
        <p className="text-sm text-[var(--text-secondary)] mt-1">
          Руководитель, телефон, e-mail и юридический адрес контрагента. Эти поля автоматически
          заполняют таблицы «Сведения о заказчике» в техническом отчёте.
        </p>
      </div>

      {message && <div className="sp-card-soft p-3 text-sm">{message}</div>}

      <div className="grid md:grid-cols-[280px_1fr] gap-4">
        <aside className="sp-card p-3 space-y-1 max-h-[70vh] overflow-auto">
          {items.length === 0 && (
            <p className="text-sm text-[var(--text-secondary)]">Предприятия не найдены</p>
          )}
          {items.map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={() => selectItem(item)}
              className={`w-full text-left rounded px-3 py-2 text-sm ${
                selectedId === item.id ? 'bg-[var(--bg-secondary)] font-semibold' : 'hover:bg-[var(--bg-secondary)]'
              }`}
            >
              <div>{item.name}</div>
              {item.code && <div className="text-xs text-[var(--text-secondary)]">{item.code}</div>}
            </button>
          ))}
        </aside>

        <section className="sp-card p-4 space-y-3">
          <div className="flex justify-between items-center">
            <h2 className="font-semibold">Карточка контрагента</h2>
            <button
              type="button"
              onClick={() => void handleSave()}
              className="sp-btn-primary flex items-center gap-2"
              disabled={saving || !selectedId}
            >
              <Save size={16} /> {saving ? 'Сохранение...' : 'Сохранить'}
            </button>
          </div>
          <div className="grid md:grid-cols-2 gap-3">
            {[
              ['name', 'Наименование'],
              ['code', 'Код'],
              ['director', 'Руководитель'],
              ['phone', 'Телефон'],
              ['email', 'E-mail'],
              ['legal_address', 'Юридический адрес'],
            ].map(([key, label]) => (
              <label key={key} className="text-sm space-y-1 block">
                <span className="text-[var(--text-secondary)]">{label}</span>
                <input
                  className="w-full rounded border p-2 bg-[var(--bg-secondary)]"
                  value={(form as Record<string, string>)[key] || ''}
                  onChange={(e) => setForm((prev) => ({ ...prev, [key]: e.target.value }))}
                />
              </label>
            ))}
            <label className="text-sm space-y-1 block md:col-span-2">
              <span className="text-[var(--text-secondary)]">Примечание</span>
              <textarea
                className="w-full rounded border p-2 bg-[var(--bg-secondary)] min-h-[80px]"
                value={form.description || ''}
                onChange={(e) => setForm((prev) => ({ ...prev, description: e.target.value }))}
              />
            </label>
          </div>
        </section>
      </div>
    </div>
  );
};

export default EnterpriseCards;
