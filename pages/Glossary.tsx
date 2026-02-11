import React, { useState } from 'react';
import { BookOpen, Search } from 'lucide-react';

const TERMS: { term: string; full: string; desc: string }[] = [
  { term: 'ВИК', full: 'Визуальный и измерительный контроль', desc: 'Метод неразрушающего контроля, включающий осмотр поверхности и измерение размеров.' },
  { term: 'УЗТ', full: 'Ультразвуковая толщинометрия', desc: 'Измерение толщины стенок элементов оборудования ультразвуковым толщиномером.' },
  { term: 'УЗК', full: 'Ультразвуковой контроль', desc: 'Контроль качества сварных соединений и основного металла ультразвуковым методом.' },
  { term: 'ОПО', full: 'Опасный производственный объект', desc: 'Предприятие или его участок, где используется оборудование, работающее под давлением.' },
  { term: 'ПВК', full: 'Просвечивание или магнитопорошковый контроль', desc: 'Методы выявления поверхностных и подповерхностных дефектов.' },
  { term: 'МК', full: 'Магнитопорошковый контроль', desc: 'Выявление дефектов на поверхности ферромагнитных материалов.' },
  { term: 'РК', full: 'Радиационный контроль', desc: 'Контроль с использованием рентгеновского или гамма-излучения.' },
  { term: 'НК', full: 'Неразрушающий контроль', desc: 'Контроль свойств материалов без нарушения их целостности.' },
  { term: 'ЛНМК', full: 'Лаборатория неразрушающего контроля', desc: 'Подразделение, выполняющее работы по НК.' },
  { term: 'Ростехнадзор', full: 'Федеральная служба по экологическому, технологическому и атомному надзору', desc: 'Орган надзора за промышленной безопасностью.' },
];

const Glossary = () => {
  const [search, setSearch] = useState('');

  const filtered = TERMS.filter(
    (t) =>
      !search.trim() ||
      t.term.toLowerCase().includes(search.toLowerCase()) ||
      t.full.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="p-4 sm:p-6">
      <h1 className="text-2xl font-bold text-white flex items-center gap-2 mb-6">
        <BookOpen className="text-accent" size={28} />
        Глоссарий терминов
      </h1>
      <div className="relative max-w-md mb-6">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={20} />
        <input
          type="text"
          placeholder="Поиск термина..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full pl-10 pr-4 py-2 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent"
        />
      </div>
      <div className="space-y-4">
        {filtered.map((t) => (
          <div
            key={t.term}
            className="bg-secondary/50 rounded-lg p-4 border border-slate-700 hover:border-slate-600 transition-colors"
          >
            <div className="font-bold text-accent text-lg">{t.term}</div>
            <div className="text-slate-300 mt-1">{t.full}</div>
            <div className="text-slate-400 text-sm mt-2">{t.desc}</div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default Glossary;
