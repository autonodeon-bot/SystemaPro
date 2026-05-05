import React, { useState, useEffect, useRef } from 'react';
import { FileText, Plus, Trash2, Printer, Download, Edit3, Save, ChevronDown, ChevronUp, AlertTriangle, CheckCircle, Info } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

const API_BASE = import.meta.env.VITE_API_URL || '';

// ─── Типы ─────────────────────────────────────────────────────────────────────

type Severity = 'critical' | 'significant' | 'minor';

interface DefectRow {
  id: string;
  number: number;
  name: string;        // Наименование / тип дефекта
  location: string;    // Место расположения
  size: string;        // Размер
  severity: Severity;
  recommendation: string;
  notes: string;
}

interface StatementHeader {
  statementNumber: string;
  date: string;
  objectName: string;
  customer: string;
  executor: string;
  devices: string;
  normDoc: string;
  organization: string;
  controlType: string;
}

interface InspectionOption {
  id: string;
  label: string;
  objectName: string;
  date: string;
  defects?: Array<Record<string, unknown>>;
}

// ─── Хелперы ──────────────────────────────────────────────────────────────────

const SEVERITY_CONFIG: Record<Severity, { label: string; color: string; bg: string; icon: React.ReactNode }> = {
  critical:    { label: 'Критический',   color: 'text-red-600',    bg: 'bg-red-50',    icon: <AlertTriangle size={14} className="text-red-500" /> },
  significant: { label: 'Значительный',  color: 'text-orange-600', bg: 'bg-orange-50', icon: <AlertTriangle size={14} className="text-orange-400" /> },
  minor:       { label: 'Малозначимый',  color: 'text-green-700',  bg: 'bg-green-50',  icon: <CheckCircle   size={14} className="text-green-500" /> },
};

function newRow(number: number): DefectRow {
  return { id: crypto.randomUUID(), number, name: '', location: '', size: '', severity: 'minor', recommendation: '', notes: '' };
}

// ─── Компонент ────────────────────────────────────────────────────────────────

const DefectStatement: React.FC = () => {
  const { token } = useAuth();

  // Источник данных
  const [inspections, setInspections] = useState<InspectionOption[]>([]);
  const [selectedId, setSelectedId] = useState<string>('');
  const [loadingInsp, setLoadingInsp] = useState(false);

  // Шапка документа
  const [header, setHeader] = useState<StatementHeader>({
    statementNumber: '',
    date: new Date().toLocaleDateString('ru-RU'),
    objectName: '',
    customer: '',
    executor: '',
    devices: '',
    normDoc: 'ГОСТ Р 55614-2013, РД 03-606-03',
    organization: '',
    controlType: '',
  });

  // Таблица дефектов
  const [defects, setDefects] = useState<DefectRow[]>([newRow(1)]);
  const [editingRowId, setEditingRowId] = useState<string | null>(null);

  // Заключение
  const [conclusion, setConclusion] = useState('');

  // Подписи
  const [sigExecutor, setSigExecutor] = useState('');
  const [sigDate, setSigDate] = useState(new Date().toLocaleDateString('ru-RU'));

  // UI
  const [editHeader, setEditHeader] = useState(true);
  const [filterSeverity, setFilterSeverity] = useState<Severity | 'all'>('all');
  const printRef = useRef<HTMLDivElement>(null);

  // ─── Загрузка обследований ────────────────────────────────────────────────

  useEffect(() => {
    loadInspections();
  }, []);

  async function loadInspections() {
    setLoadingInsp(true);
    try {
      const res = await fetch(`${API_BASE}/api/inspections?limit=200`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) throw new Error();
      const data = await res.json();
      const rawList: unknown[] = Array.isArray(data)
        ? data
        : (data.items as unknown[]) || (data.inspections as unknown[]) || [];
      const opts: InspectionOption[] = rawList.map((raw) => {
        const ins = raw as Record<string, unknown>;
        const checklist = (ins.checklist_data as Record<string, unknown>) || {};
        const payload = (ins.data as Record<string, unknown>) || {};
        const cl = { ...payload, ...checklist };
        const vessel =
          (cl.vessel_name as string) ||
          (cl.object_name as string) ||
          (ins.equipment_name as string) ||
          (ins.equipment_id as string) ||
          '—';
        const dateRaw =
          (ins.date_performed as string) ||
          (ins.inspection_date as string) ||
          (cl.inspection_date as string) ||
          (ins.created_at as string) ||
          '';
        let dateFmt = dateRaw;
        try { dateFmt = new Date(dateRaw).toLocaleDateString('ru-RU'); } catch (_) {}
        const fromMain = (cl.defects as Array<Record<string, unknown>>) || [];
        const visual = (cl.visual_defects as Array<Record<string, unknown>>) || [];
        const fromVisual = visual.map(v => ({
          type: (v.defect_type as string) || 'Визуальный',
          name: (v.description as string) || (v.defect_type as string) || '',
          location: (v.location as string) || '',
          size: (v.size as string) || '',
          severity: 'minor',
          recommendation: '',
          notes: '',
        }));
        return {
          id: (ins.id as string) || '',
          label: `${dateFmt} — ${vessel}`,
          objectName: vessel,
          date: dateFmt,
          defects: [...fromMain, ...fromVisual],
        };
      });
      setInspections(opts);
    } catch {
      /* Обследования недоступны — работаем в ручном режиме */
    }
    setLoadingInsp(false);
  }

  // ─── Импорт из обследования ───────────────────────────────────────────────

  function importFromInspection(id: string) {
    setSelectedId(id);
    const insp = inspections.find(i => i.id === id);
    if (!insp) return;

    setHeader(h => ({ ...h, objectName: insp.objectName, date: insp.date }));

    if (insp.defects && insp.defects.length > 0) {
      const rows: DefectRow[] = insp.defects.map((d, idx) => ({
        id: crypto.randomUUID(),
        number: idx + 1,
        name: (d.type as string) || (d.name as string) || '',
        location: (d.location as string) || '',
        size: (d.size as string) || '',
        severity: (() => {
          const sev = ((d.severity as string) || '').toLowerCase();
          if (sev === 'critical') return 'critical';
          if (sev === 'significant') return 'significant';
          return 'minor';
        })(),
        recommendation: (d.recommendation as string) || '',
        notes: (d.notes as string) || '',
      }));
      setDefects(rows);
      updateConclusion(rows);
    }
  }

  // ─── Таблица дефектов ─────────────────────────────────────────────────────

  function addRow() {
    setDefects(prev => {
      const next = [...prev, newRow(prev.length + 1)];
      return next;
    });
  }

  function updateRow(id: string, field: keyof DefectRow, value: string) {
    setDefects(prev => prev.map(r => r.id === id ? { ...r, [field]: value } : r));
  }

  function deleteRow(id: string) {
    if (!window.confirm('Удалить дефект? Это действие нельзя отменить.')) return;
    setDefects(prev => {
      const next = prev.filter(r => r.id !== id).map((r, i) => ({ ...r, number: i + 1 }));
      updateConclusion(next);
      return next;
    });
  }

  function updateConclusion(rows: DefectRow[]) {
    const critical = rows.filter(r => r.severity === 'critical').length;
    const significant = rows.filter(r => r.severity === 'significant').length;
    const minor = rows.filter(r => r.severity === 'minor').length;
    const total = rows.length;
    if (total === 0) { setConclusion(''); return; }
    const parts: string[] = [];
    if (critical > 0) parts.push(`критических — ${critical}`);
    if (significant > 0) parts.push(`значительных — ${significant}`);
    if (minor > 0) parts.push(`малозначимых — ${minor}`);
    const verdict = critical > 0
      ? 'Эксплуатация объекта до устранения критических дефектов не допускается.'
      : significant > 0
      ? 'Требуется проведение ремонтных работ по устранению значительных дефектов.'
      : 'Объект может быть допущен к дальнейшей эксплуатации с устранением выявленных дефектов в плановом порядке.';
    setConclusion(
      `В ходе контроля выявлено дефектов: всего — ${total}, из них ${parts.join(', ')}. ${verdict}`
    );
  }

  // ─── Печать ───────────────────────────────────────────────────────────────

  function handlePrint() {
    const content = printRef.current;
    if (!content) return;
    const win = window.open('', '_blank');
    if (!win) return;
    win.document.write(`
      <html><head>
        <title>Ведомость дефектов — ${header.objectName}</title>
        <style>
          body { font-family: Arial, sans-serif; font-size: 11pt; margin: 20mm; color: #000; }
          h1 { font-size: 14pt; text-align: center; margin-bottom: 4px; }
          h2 { font-size: 11pt; text-align: center; color: #555; margin-top: 0; }
          table { width: 100%; border-collapse: collapse; margin-top: 12px; font-size: 9pt; }
          th, td { border: 1px solid #333; padding: 4px 6px; }
          th { background: #e8e8e8; font-weight: bold; text-align: center; }
          .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 16px; margin: 8px 0; font-size: 10pt; }
          .info-grid span { font-weight: bold; }
          .conclusion { margin-top: 12px; font-size: 10pt; line-height: 1.5; border: 1px solid #ccc; padding: 8px; }
          .sig { margin-top: 20px; display: flex; justify-content: space-between; font-size: 10pt; }
          .critical td { background: #ffe0e0; }
          .significant td { background: #fff3e0; }
        </style>
      </head><body>${content.innerHTML}</body></html>
    `);
    win.document.close();
    win.print();
  }

  // ─── Статистика ───────────────────────────────────────────────────────────

  const stats = {
    total: defects.length,
    critical: defects.filter(d => d.severity === 'critical').length,
    significant: defects.filter(d => d.severity === 'significant').length,
    minor: defects.filter(d => d.severity === 'minor').length,
  };

  const visibleDefects = filterSeverity === 'all'
    ? defects
    : defects.filter(d => d.severity === filterSeverity);

  // ─── Рендер ───────────────────────────────────────────────────────────────

  return (
    <div className="space-y-6 max-w-6xl mx-auto">
      {/* ── Заголовок страницы ── */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <FileText size={26} className="text-accent" />
            Ведомость дефектов
          </h1>
          <p className="text-app-text3 text-sm mt-1">Официальный бланк результатов НК (П.6)</p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <button
            onClick={handlePrint}
            className="flex items-center gap-2 px-4 py-2 bg-app-softer hover:bg-app-soft text-app-text rounded-lg text-sm transition"
          >
            <Printer size={16} /> Печать / PDF
          </button>
        </div>
      </div>

      {/* ── Импорт из обследования ── */}
      <div className="bg-secondary rounded-xl p-4 border border-app-line">
        <h3 className="text-white font-semibold mb-3 flex items-center gap-2">
          <Download size={16} className="text-accent" />
          Импортировать дефекты из обследования
        </h3>
        <div className="flex gap-3 items-end">
          <div className="flex-1">
            <label className="block text-xs text-app-text3 mb-1">Выбрать обследование</label>
            <select
              value={selectedId}
              onChange={e => importFromInspection(e.target.value)}
              className="w-full bg-primary border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
            >
              <option value="">— выбрать или заполнить вручную —</option>
              {loadingInsp && <option disabled>Загрузка...</option>}
              {inspections.map(i => (
                <option key={i.id} value={i.id}>{i.label}</option>
              ))}
            </select>
          </div>
          <button
            onClick={loadInspections}
            className="px-3 py-2 bg-app-softer hover:bg-app-soft text-app-text rounded-lg text-sm"
            title="Обновить список"
          >↻</button>
        </div>
        <p className="text-xs text-app-text3 mt-2">
          <Info size={12} className="inline mr-1" />
          Дефекты будут импортированы автоматически. При необходимости их можно отредактировать.
        </p>
      </div>

      {/* ── Шапка документа (редактируемая) ── */}
      <div className="bg-secondary rounded-xl border border-app-line overflow-hidden">
        <button
          onClick={() => setEditHeader(!editHeader)}
          className="w-full flex items-center justify-between px-4 py-3 text-white hover:bg-white/5 transition"
        >
          <span className="font-semibold flex items-center gap-2">
            <Edit3 size={16} className="text-accent" /> Реквизиты документа
          </span>
          {editHeader ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
        </button>
        {editHeader && (
          <div className="p-4 border-t border-app-line grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {([
              ['statementNumber', '№ ведомости'],
              ['date', 'Дата контроля'],
              ['objectName', 'Объект контроля'],
              ['customer', 'Заказчик'],
              ['executor', 'Исполнитель (ФИО)'],
              ['devices', 'Приборы'],
              ['controlType', 'Метод контроля'],
              ['normDoc', 'Нормативный документ'],
              ['organization', 'Организация'],
            ] as [keyof StatementHeader, string][]).map(([field, label]) => (
              <div key={field}>
                <label className="block text-xs text-app-text3 mb-1">{label}</label>
                <input
                  type="text"
                  value={header[field]}
                  onChange={e => setHeader(h => ({ ...h, [field]: e.target.value }))}
                  className="w-full bg-primary border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
                />
              </div>
            ))}
          </div>
        )}
      </div>

      {/* ── Статистика ── */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {[
          { label: 'Всего дефектов', value: stats.total, color: 'text-app-text', bg: 'bg-app-soft' },
          { label: 'Критических', value: stats.critical, color: 'text-red-400', bg: 'bg-red-900/30' },
          { label: 'Значительных', value: stats.significant, color: 'text-orange-400', bg: 'bg-orange-900/30' },
          { label: 'Малозначимых', value: stats.minor, color: 'text-green-400', bg: 'bg-green-900/30' },
        ].map(s => (
          <div key={s.label} className={`${s.bg} rounded-xl p-3 text-center`}>
            <p className={`text-2xl font-bold ${s.color}`}>{s.value}</p>
            <p className="text-xs text-app-text3 mt-1">{s.label}</p>
          </div>
        ))}
      </div>

      {/* ── Фильтр по степени ── */}
      <div className="flex gap-2 flex-wrap">
        <span className="text-xs text-app-text3 self-center">Фильтр:</span>
        {(['all', 'critical', 'significant', 'minor'] as const).map(sev => (
          <button
            key={sev}
            onClick={() => setFilterSeverity(sev)}
            className={`px-3 py-1 rounded-full text-xs font-medium transition ${
              filterSeverity === sev
                ? 'bg-accent text-white'
                : 'bg-app-soft text-app-text2 hover:bg-app-softer'
            }`}
          >
            {sev === 'all' ? 'Все' : SEVERITY_CONFIG[sev].label}
            {sev !== 'all' && stats[sev] > 0 && (
              <span className="ml-1 bg-black/20 rounded-full px-1.5">{stats[sev]}</span>
            )}
          </button>
        ))}
      </div>

      {/* ── Таблица дефектов ── */}
      <div className="bg-secondary rounded-xl border border-app-line overflow-hidden">
        <div className="flex items-center justify-between px-4 py-3 border-b border-app-line">
          <h3 className="text-white font-semibold">Таблица дефектов</h3>
          <button
            onClick={addRow}
            className="flex items-center gap-1 px-3 py-1.5 bg-accent hover:bg-accent/80 text-white rounded-lg text-sm"
          >
            <Plus size={14} /> Добавить дефект
          </button>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-app-soft/50 text-app-text2 text-xs">
                <th className="px-3 py-2 text-left w-8">№</th>
                <th className="px-3 py-2 text-left min-w-[160px]">Наименование / тип дефекта</th>
                <th className="px-3 py-2 text-left min-w-[120px]">Место расположения</th>
                <th className="px-3 py-2 text-left w-24">Размер</th>
                <th className="px-3 py-2 text-left w-32">Степень</th>
                <th className="px-3 py-2 text-left min-w-[160px]">Рекомендации</th>
                <th className="px-3 py-2 text-left min-w-[100px]">Примечания</th>
                <th className="px-3 py-2 w-16"></th>
              </tr>
            </thead>
            <tbody>
              {visibleDefects.length === 0 && (
                <tr>
                  <td colSpan={8} className="text-center text-app-text3 py-8">
                    Нет дефектов для отображения
                  </td>
                </tr>
              )}
              {visibleDefects.map((row) => {
                const cfg = SEVERITY_CONFIG[row.severity];
                const isEditing = editingRowId === row.id;
                return (
                  <tr
                    key={row.id}
                    className={`border-t border-app-line hover:bg-white/5 transition ${
                      row.severity === 'critical' ? 'bg-red-900/10' :
                      row.severity === 'significant' ? 'bg-orange-900/10' : ''
                    }`}
                  >
                    <td className="px-3 py-2 text-app-text3 font-mono text-xs">{row.number}</td>
                    <td className="px-3 py-2">
                      {isEditing ? (
                        <input
                          autoFocus
                          value={row.name}
                          onChange={e => updateRow(row.id, 'name', e.target.value)}
                          className="w-full bg-primary border border-app-line rounded px-2 py-1 text-white text-xs"
                        />
                      ) : (
                        <span className="text-white">{row.name || <span className="text-app-text3 italic">—</span>}</span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      {isEditing ? (
                        <input
                          value={row.location}
                          onChange={e => updateRow(row.id, 'location', e.target.value)}
                          className="w-full bg-primary border border-app-line rounded px-2 py-1 text-white text-xs"
                        />
                      ) : (
                        <span className="text-app-text2">{row.location || '—'}</span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      {isEditing ? (
                        <input
                          value={row.size}
                          onChange={e => updateRow(row.id, 'size', e.target.value)}
                          className="w-full bg-primary border border-app-line rounded px-2 py-1 text-white text-xs"
                        />
                      ) : (
                        <span className="text-app-text2 font-mono text-xs">{row.size || '—'}</span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      {isEditing ? (
                        <select
                          value={row.severity}
                          onChange={e => updateRow(row.id, 'severity', e.target.value)}
                          className="w-full bg-primary border border-app-line rounded px-2 py-1 text-white text-xs"
                        >
                          <option value="critical">Критический</option>
                          <option value="significant">Значительный</option>
                          <option value="minor">Малозначимый</option>
                        </select>
                      ) : (
                        <span className={`inline-flex items-center gap-1 text-xs font-medium ${cfg.color}`}>
                          {cfg.icon} {cfg.label}
                        </span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      {isEditing ? (
                        <input
                          value={row.recommendation}
                          onChange={e => updateRow(row.id, 'recommendation', e.target.value)}
                          className="w-full bg-primary border border-app-line rounded px-2 py-1 text-white text-xs"
                        />
                      ) : (
                        <span className="text-app-text2 text-xs">{row.recommendation || '—'}</span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      {isEditing ? (
                        <input
                          value={row.notes}
                          onChange={e => updateRow(row.id, 'notes', e.target.value)}
                          className="w-full bg-primary border border-app-line rounded px-2 py-1 text-white text-xs"
                        />
                      ) : (
                        <span className="text-app-text3 text-xs">{row.notes || ''}</span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      <div className="flex items-center gap-1">
                        <button
                          onClick={() => setEditingRowId(isEditing ? null : row.id)}
                          className="p-1 text-app-text3 hover:text-accent rounded"
                          title={isEditing ? 'Сохранить' : 'Редактировать'}
                        >
                          {isEditing ? <Save size={13} /> : <Edit3 size={13} />}
                        </button>
                        <button
                          onClick={() => deleteRow(row.id)}
                          className="p-1 text-app-text3 hover:text-red-400 rounded"
                          title="Удалить дефект"
                        >
                          <Trash2 size={13} />
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── Заключение ── */}
      <div className="bg-secondary rounded-xl border border-app-line p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-white font-semibold">Заключение</h3>
          <button
            onClick={() => updateConclusion(defects)}
            className="text-xs text-accent hover:underline"
          >
            Сгенерировать автоматически
          </button>
        </div>
        <textarea
          value={conclusion}
          onChange={e => setConclusion(e.target.value)}
          rows={4}
          className="w-full bg-primary border border-app-line rounded-lg px-3 py-2 text-app-text text-sm resize-none"
          placeholder="Заключение по результатам контроля..."
        />
      </div>

      {/* ── Подписи ── */}
      <div className="bg-secondary rounded-xl border border-app-line p-4">
        <h3 className="text-white font-semibold mb-3">Подписи</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="text-xs text-app-text3 block mb-1">ФИО и должность исполнителя</label>
            <input
              type="text"
              value={sigExecutor || header.executor}
              onChange={e => setSigExecutor(e.target.value)}
              className="w-full bg-primary border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
              placeholder="Иванов И.И., инженер-дефектоскопист"
            />
          </div>
          <div>
            <label className="text-xs text-app-text3 block mb-1">Дата подписания</label>
            <input
              type="text"
              value={sigDate}
              onChange={e => setSigDate(e.target.value)}
              className="w-full bg-primary border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
            />
          </div>
        </div>
      </div>

      {/* ── Скрытая область печати ── */}
      <div ref={printRef} style={{ display: 'none' }}>
        <h1>ВЕДОМОСТЬ ДЕФЕКТОВ</h1>
        <h2>{header.objectName && `Объект: ${header.objectName}`}</h2>
        <div className="info-grid">
          {header.statementNumber && <><span>№ ведомости:</span><span>{header.statementNumber}</span></>}
          <span>Дата:</span><span>{header.date}</span>
          <span>Объект:</span><span>{header.objectName}</span>
          <span>Заказчик:</span><span>{header.customer}</span>
          <span>Исполнитель:</span><span>{header.executor}</span>
          <span>Метод контроля:</span><span>{header.controlType}</span>
          <span>Приборы:</span><span>{header.devices}</span>
          <span>Норм. документ:</span><span>{header.normDoc}</span>
        </div>
        <table>
          <thead>
            <tr>
              <th>№</th>
              <th>Наименование / тип дефекта</th>
              <th>Место расположения</th>
              <th>Размер</th>
              <th>Степень</th>
              <th>Рекомендации</th>
              <th>Примечания</th>
            </tr>
          </thead>
          <tbody>
            {defects.map(d => (
              <tr key={d.id} className={d.severity === 'critical' ? 'critical' : d.severity === 'significant' ? 'significant' : ''}>
                <td>{d.number}</td>
                <td>{d.name}</td>
                <td>{d.location}</td>
                <td>{d.size}</td>
                <td>{SEVERITY_CONFIG[d.severity].label}</td>
                <td>{d.recommendation}</td>
                <td>{d.notes}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {conclusion && (
          <div className="conclusion"><strong>Заключение:</strong> {conclusion}</div>
        )}
        <div className="sig">
          <span>Исполнитель: {sigExecutor || header.executor}</span>
          <span>Подпись: _______________</span>
          <span>Дата: {sigDate}</span>
        </div>
      </div>
    </div>
  );
};

export default DefectStatement;
