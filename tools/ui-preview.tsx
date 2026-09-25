/** Local-only component review page. No API calls or production authentication bypass. */
import { useState } from 'react';
import { createRoot } from 'react-dom/client';
import EquipmentCreateModal from '../components/equipment/EquipmentCreateModal';
import type { CreateEntityType, CreateFormData } from '../components/equipment/types';
import '../index.css';
import '../styles/workspace-ui.css';

function Preview() {
  const [type, setType] = useState<CreateEntityType | null>(null);
  const [data, setData] = useState<CreateFormData>({ name: '', director: '', phone: '', email: '', legal_address: '', code: '', description: '', enterprise_id: '', branch_id: '', workshop_id: '', type_id: '', serial_number: '', location: '', commissioning_date: '' });
  const [saved, setSaved] = useState(false);
  return <main style={{ maxWidth: 1000, margin: '0 auto', padding: '32px 20px' }}>
    <p className="sp-hint">SystemaPro · локальная проверка компонентов</p>
    <div className="sp-workspace-heading my-6"><div><h1 className="text-2xl font-semibold">Оборудование и структура</h1><p>Предприятия, филиалы, цеха и оборудование.</p></div>
      <button className="ind-btn" onClick={() => document.documentElement.classList.toggle('light')}>Сменить тему</button></div>
    <section className="sp-surface p-6"><h2 className="font-semibold mb-4">Добавить в структуру</h2><div className="flex flex-wrap gap-3">
      {([['enterprise', 'Предприятие'], ['branch', 'Филиал'], ['workshop', 'Цех'], ['equipment_type', 'Тип оборудования'], ['equipment', 'Оборудование']] as const).map(([key, label]) => <button key={key} className="ind-btn ind-btn--primary" onClick={() => setType(key)}>{label}</button>)}
    </div>{saved && <p role="status" className="mt-4">Проверка формы выполнена. Данные не отправлялись на сервер.</p>}</section>
    {type && <EquipmentCreateModal modal={{ mode: 'create', type, parentName: 'Промышленная площадка · Цех № 4' }} formData={data} onFormDataChange={setData}
      equipmentTypes={[{ id: '1', name: 'Сосуд под давлением', code: 'VESSEL' }, { id: '2', name: 'Подземный трубопровод', code: 'UNDERGROUND_PIPELINE' }, { id: '3', name: 'Электродвигатель', code: 'ELECTRIC_MOTOR' }, { id: '4', name: 'Резервуар для хранения технологической воды', code: 'WATER_TANK' }]}
      onClose={() => setType(null)} onSubmit={event => { event.preventDefault(); setSaved(true); setType(null); }} />}
  </main>;
}
createRoot(document.getElementById('root')!).render(<Preview />);
