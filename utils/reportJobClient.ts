import { API_BASE } from '../constants';

export async function runReportJob(request: Record<string, unknown>, owner: string, headers: HeadersInit,
  signal: AbortSignal, onStage: (stage: string) => void) {
  const key = `report-job:${owner}:${JSON.stringify(request)}`;
  const jobId = localStorage.getItem(key) || crypto.randomUUID();
  localStorage.setItem(key, jobId);
  const start = await fetch(`${API_BASE}/api/reports/jobs`, {
    method: 'POST', headers, signal, body: JSON.stringify({ job_id: jobId, request }),
  });
  let job = await start.json();
  if (!start.ok) {
    if (start.status === 409 || start.status === 403) localStorage.removeItem(key);
    throw new Error(job.detail || 'Не удалось поставить отчет в очередь');
  }
  for (let attempt = 0; attempt < 300; attempt++) {
    onStage(job.stage || 'Генерация отчета');
    if (job.status === 'completed') { localStorage.removeItem(key); return job.result; }
    if (job.status === 'failed') { localStorage.removeItem(key); throw new Error(job.error || 'Ошибка генерации'); }
    await new Promise<void>((resolve, reject) => {
      if (signal.aborted) { reject(new DOMException('Cancelled', 'AbortError')); return; }
      const abort = () => { clearTimeout(timer); reject(new DOMException('Cancelled', 'AbortError')); };
      const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, 1000);
      signal.addEventListener('abort', abort, { once: true });
    });
    const response = await fetch(`${API_BASE}/api/reports/jobs/${jobId}`, { headers, signal });
    job = await response.json();
    if (!response.ok) throw new Error(job.detail || 'Не удалось получить состояние отчета');
  }
  throw new Error('Генерация еще не завершена. Повторное нажатие проверит это же задание, не создавая новое.');
}
