import { useId, useMemo, useState } from 'react';
import { Check, ChevronDown, Search } from 'lucide-react';
import Modal from './Modal';

export interface SelectOption { value: string; label: string; description?: string }
interface Props { label: string; value: string; options: SelectOption[]; onChange: (value: string) => void; disabled?: boolean; placeholder?: string }

export default function SearchSelect({ label, value, options, onChange, disabled, placeholder = 'Выберите значение' }: Props) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const id = useId();
  const selected = options.find(option => option.value === value);
  const filtered = useMemo(() => options.filter(option =>
    `${option.label} ${option.description ?? ''}`.toLocaleLowerCase('ru').includes(query.trim().toLocaleLowerCase('ru')),
  ), [options, query]);
  return <div className="sp-select">
    <label id={id}>{label}</label>
    <button type="button" className="sp-select__trigger" aria-labelledby={id} aria-haspopup="dialog" aria-expanded={open}
      disabled={disabled} onClick={() => { setQuery(''); setOpen(true); }}>
      <span>{selected?.label ?? (value ? 'Сохранённое значение отсутствует в справочнике' : placeholder)}</span><ChevronDown size={18} />
    </button>
    {open && <Modal title={label} onClose={() => setOpen(false)} description="Найдите нужный вариант по названию или коду">
      <div className="sp-search-field"><Search size={18} /><input autoFocus data-initial-focus type="search" value={query} aria-label="Поиск вариантов"
        placeholder="Начните вводить название…" onChange={event => setQuery(event.target.value)} /></div>
      <div className="sp-select__options" aria-label="Варианты">
        <button type="button" className="sp-select__option" onClick={() => { onChange(''); setOpen(false); }}>Не выбрано</button>
        {filtered.map(option => <button key={option.value} type="button" className="sp-select__option" aria-pressed={value === option.value}
          onClick={() => { onChange(option.value); setOpen(false); }}>
          <span><strong>{option.label}</strong>{option.description && <small>{option.description}</small>}</span>
          {value === option.value && <Check size={18} />}
        </button>)}
        {filtered.length === 0 && <p className="sp-empty">Ничего не найдено. Измените поисковый запрос.</p>}
      </div>
      <p className="sp-hint">Найдено: {filtered.length} из {options.length}</p>
    </Modal>}
  </div>;
}
