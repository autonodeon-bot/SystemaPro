import { afterEach, expect, it, vi } from 'vitest';
import { runReportJob } from '../utils/reportJobClient';

afterEach(() => { vi.unstubAllGlobals(); localStorage.clear(); });

it('reuses the submission ID after a network failure', async () => {
  const calls: string[] = [];
  let fail = true;
  vi.stubGlobal('fetch', vi.fn(async (_url, options) => {
    calls.push(JSON.parse(options.body).job_id);
    if (fail) { fail = false; throw new Error('connection lost'); }
    return new Response(JSON.stringify({status: 'completed', stage: 'Готово', result: {id: 'report'}}));
  }));
  const request = {inspection_id: 'inspection', format: 'pdf'};
  const controller = new AbortController();
  await expect(runReportJob(request, 'user', {}, controller.signal, () => {})).rejects.toThrow('connection lost');
  await expect(runReportJob(request, 'user', {}, controller.signal, () => {})).resolves.toEqual({id: 'report'});
  expect(calls[0]).toBe(calls[1]);
});
