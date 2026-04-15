# Skill: Создание новой страницы (Frontend)

## Описание
Создание новой страницы React для web-интерфейса «Монитор» (SystemaPro).

## Когда использовать
- Пользователь просит добавить новый раздел/страницу
- Нужна новая функциональность в web-интерфейсе

## Шаги выполнения

### 1. Создать файл страницы `pages/NewPage.tsx`

```typescript
import { useState, useEffect } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { useToast } from '../contexts/ToastContext';
import { API_BASE } from '../constants';
import { Skeleton, SkeletonTable } from '../components/Skeleton';
import { ConfirmModal } from '../components/ConfirmModal';
import { Plus, Edit, Trash2, Search, Download } from 'lucide-react';

// --- Типы ---
interface EntityItem {
  id: string;
  name: string;
  // ... поля
}

export default function NewPage() {
  const { token, user, hasRole } = useAuth();
  const { showToast } = useToast();
  
  const [items, setItems] = useState<EntityItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [showModal, setShowModal] = useState(false);
  const [editItem, setEditItem] = useState<EntityItem | null>(null);

  useEffect(() => {
    fetchItems();
  }, []);

  const fetchItems = async () => {
    try {
      setLoading(true);
      const res = await fetch(`${API_BASE}/api/entities`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (!res.ok) throw new Error('Ошибка загрузки');
      setItems(await res.json());
    } catch (e: any) {
      showToast(e.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  const filtered = items.filter(item =>
    item.name.toLowerCase().includes(search.toLowerCase())
  );

  if (loading) return <SkeletonTable />;

  return (
    <div className="space-y-6">
      {/* Заголовок */}
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-[var(--text-primary)]">
          Название раздела
        </h1>
        {hasRole('admin') && (
          <button
            onClick={() => { setEditItem(null); setShowModal(true); }}
            className="flex items-center gap-2 px-4 py-2 bg-accent text-white rounded-lg hover:bg-blue-600 transition-colors"
          >
            <Plus size={18} />
            Добавить
          </button>
        )}
      </div>

      {/* Поиск */}
      <div className="relative">
        <Search size={18} className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-secondary)]" />
        <input
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Поиск..."
          className="w-full pl-10 pr-4 py-2 rounded-lg border border-[var(--border-primary)] bg-[var(--bg-secondary)] text-[var(--text-primary)]"
        />
      </div>

      {/* Таблица */}
      <div className="sp-card overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="border-b border-[var(--border-primary)]">
              <th className="text-left p-3 text-[var(--text-secondary)]">Название</th>
              <th className="text-right p-3 text-[var(--text-secondary)]">Действия</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map(item => (
              <tr key={item.id} className="border-b border-[var(--border-primary)] hover:bg-[var(--bg-tertiary)]">
                <td className="p-3 text-[var(--text-primary)]">{item.name}</td>
                <td className="p-3 text-right">
                  <button onClick={() => { setEditItem(item); setShowModal(true); }} className="p-1 hover:text-accent">
                    <Edit size={16} />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
```

### 2. Добавить маршрут в `App.tsx`

Найти блок `<Routes>` и добавить:
```tsx
import NewPage from './pages/NewPage';

// Внутри <Routes>:
<Route path="/new-page" element={<ProtectedRoute><NewPage /></ProtectedRoute>} />
```

### 3. Добавить ссылку в навигацию сайдбара (App.tsx)

В массив навигации сайдбара добавить:
```tsx
{ path: '/new-page', label: 'Название', icon: <IconName size={20} /> }
```

### 4. Стилизация
- Использовать CSS переменные: `var(--text-primary)`, `var(--bg-secondary)`, и т.д.
- Использовать классы: `.sp-card`, `.sp-card-soft`
- Все элементы должны поддерживать тёмную тему
- Адаптивность для мобильных

### 5. Типы (если нужны)
Добавить новые типы в `types.ts`.
