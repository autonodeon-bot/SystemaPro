import { useEffect, useRef, useState } from 'react';
import { API_BASE } from '../../constants';

interface Analysis {
  source_fingerprint: string;
  draft_text: string;
  scope: string;
  findings: { code: string; message: string; source: string; severity: string }[];
  facts: { label: string; value: string; unit: string; source: string }[];
  measurements: { measured: number; pending: number; invalid: number; duplicate_rows?: number; archived?: number; minimum_mm: string | null; maximum_mm: string | null };
}

export default function VesselReportAssistant({ inspectionId }: { inspectionId: string }) {
  const [result, setResult] = useState<Analysis | null>(null);
  const [text, setText] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [format, setFormat] = useState<'txt' | 'docx'>('txt');
  const controller = useRef<AbortController | null>(null);
  useEffect(() => {
    setResult(null); setText(''); setConfirmed(false); setError(''); setBusy(false);
    return () => controller.current?.abort();
  }, [inspectionId]);
  const headers = () => ({ Authorization: `Bearer ${localStorage.getItem('token') || ''}`, 'Content-Type': 'application/json' });

  async function analyze() {
    controller.current?.abort();
    const current = new AbortController(); controller.current = current;
    setBusy(true); setError(''); setConfirmed(false); setResult(null);
    try {
      const response = await fetch(`${API_BASE}/api/report-assistant/inspections/${inspectionId}`, { headers: headers(), signal: current.signal });
      const data = await response.json();
      if (!response.ok) throw new Error(typeof data.detail === 'string' ? data.detail : 'Не удалось проверить данные');
      if (current.signal.aborted) return;
      setResult(data); setText(data.draft_text);
    } catch (e) {
      if (!current.signal.aborted) setError(e instanceof Error ? e.message : 'Ошибка проверки');
    } finally { if (!current.signal.aborted) setBusy(false); }
  }

  async function download() {
    if (!result || !confirmed) return;
    const current = new AbortController(); controller.current = current;
    setBusy(true); setError('');
    try {
      const response = await fetch(`${API_BASE}/api/report-assistant/inspections/${inspectionId}/export`, {
        method: 'POST', headers: headers(), signal: current.signal,
        body: JSON.stringify({ text, source_fingerprint: result.source_fingerprint, confirmed, format }),
      });
      if (!response.ok) {
        const data = await response.json();
        if (response.status === 409) setConfirmed(false);
        throw new Error(typeof data.detail === 'string' ? data.detail : 'Не удалось выгрузить черновик');
      }
      const blob = await response.blob();
      if (current.signal.aborted) return;
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a'); link.href = url; link.download = `vessel-draft-${inspectionId}.${format}`;
      document.body.appendChild(link); link.click(); link.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (e) {
      if (!current.signal.aborted) setError(e instanceof Error ? e.message : 'Ошибка выгрузки');
    } finally { if (!current.signal.aborted) setBusy(false); }
  }

  return <section className="sp-card space-y-3" aria-label="Помощник подготовки отчёта по сосуду">
    <h3 className="sp-section-title text-lg">Помощник подготовки отчёта по сосуду</h3>
    <p className="text-sm text-app-text3">Автопроверка данных и черновик по фактам. Генеративный ИИ пока не подключён; данные обрабатываются внутри системы.</p>
    <button type="button" className="ind-btn ind-btn--primary" onClick={analyze} disabled={busy}>
      {busy ? 'Обработка…' : result ? 'Обновить проверку и черновик' : 'Проверить данные сосуда'}
    </button>
    {error && <p role="alert" className="text-red-400">{error}</p>}
    {result && <>
      <p className="text-sm text-app-text3">{result.scope}</p>
      <p className="text-sm">УЗТ: результатов — {result.measurements.measured}; незаполненных строк — {result.measurements.pending}; некорректных — {result.measurements.invalid}.
        {` Исключено повторных строк — ${result.measurements.duplicate_rows ?? 0}; архивных — ${result.measurements.archived ?? 0}.`}
        {result.measurements.minimum_mm !== null && ` Диапазон: ${result.measurements.minimum_mm}–${result.measurements.maximum_mm} мм.`}</p>
      <ul className="space-y-2 text-sm">
        {result.findings.map((item, index) => <li key={`${item.code}-${index}`} className={item.severity === 'error' ? 'text-red-400' : 'text-app-text'}>
          {item.severity === 'error' ? 'Проверьте противоречие: ' : ''}{item.message}
          <div className="text-xs text-app-text3 break-all">Источник: {item.source}</div>
        </li>)}
      </ul>
      <details><summary className="cursor-pointer text-sm">Исходные факты и источники ({result.facts.length})</summary>
        <ul className="text-sm space-y-2 mt-2">{result.facts.map(fact => <li key={fact.source}>
          {fact.label}: {fact.value} {fact.unit}<div className="text-xs text-app-text3 break-all">{fact.source}</div>
        </li>)}</ul>
      </details>
      <label className="block text-sm">Черновик описательной части
        <textarea className="w-full mt-2 p-3 rounded bg-app-deep text-app-text border border-app-line" rows={12} maxLength={16000}
          value={text} onChange={e => { setText(e.target.value); setConfirmed(false); }} />
      </label>
      <p className="text-sm text-app-text3">Проверьте текст и замечания. Выгрузка создаёт отдельный черновик, без подписи и заключения о пригодности сосуда.</p>
      <label className="block text-sm">Формат черновика
        <select className="ml-2 p-2 bg-app-deep border border-app-line rounded" value={format} disabled={busy}
          onChange={e => setFormat(e.target.value as 'txt' | 'docx')}>
          <option value="txt">Текст (TXT)</option><option value="docx">Word (DOCX)</option>
        </select>
      </label>
      <label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={confirmed} onChange={e => setConfirmed(e.target.checked)} />
        Я проверил текст и ознакомился с замечаниями</label>
      <button type="button" className="ind-btn ind-btn--primary" onClick={download} disabled={busy || !confirmed || !text.trim()}>Скачать проверенный черновик</button>
    </>}
  </section>;
}
