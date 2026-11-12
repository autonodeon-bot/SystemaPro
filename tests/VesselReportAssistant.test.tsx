import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import VesselReportAssistant from '../components/report-generation/VesselReportAssistant';

const analysis = { source_fingerprint: 'a'.repeat(64), draft_text: 'Черновик по измерениям', scope: 'Только чек-лист',
  facts: [], findings: [{ code: 'missing', message: 'Проверьте паспорт', source: 'inspection.data.documents', severity: 'warning' }],
  measurements: { measured: 2, pending: 1, invalid: 0, minimum_mm: '7.8', maximum_mm: '7.9' } };
afterEach(() => vi.unstubAllGlobals());

describe('Vessel report assistant', () => {
  it('requires review and resets confirmation after an edit', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => analysis }));
    render(<VesselReportAssistant inspectionId="one" />);
    expect(screen.getByText(/Генеративный ИИ пока не подключён/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Проверить данные сосуда' }));
    const download = await screen.findByRole('button', { name: 'Скачать проверенный черновик' });
    expect(download).toBeDisabled();
    expect(screen.getByText('Проверьте паспорт')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('checkbox'));
    expect(download).toBeEnabled();
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'Исправленный текст' } });
    expect(download).toBeDisabled();
  });
  it('displays stale source error and requires another review', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValueOnce({ ok: true, json: async () => analysis })
      .mockResolvedValueOnce({ ok: false, status: 409, json: async () => ({ detail: 'Исходные данные изменились' }) }));
    render(<VesselReportAssistant inspectionId="two" />);
    fireEvent.click(screen.getByRole('button', { name: 'Проверить данные сосуда' }));
    const download = await screen.findByRole('button', { name: 'Скачать проверенный черновик' });
    fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(download);
    expect(await screen.findByRole('alert')).toHaveTextContent('Исходные данные изменились');
    expect(download).toBeDisabled();
  });
  it('sends the selected Word format and the reviewed source fingerprint', async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce({ ok: true, json: async () => analysis })
      .mockResolvedValueOnce({ ok: false, status: 503, json: async () => ({ detail: 'Временно недоступно' }) });
    vi.stubGlobal('fetch', fetchMock);
    render(<VesselReportAssistant inspectionId="word" />);
    fireEvent.click(screen.getByRole('button', { name: 'Проверить данные сосуда' }));
    await screen.findByRole('textbox');
    fireEvent.change(screen.getByLabelText('Формат черновика'), { target: { value: 'docx' } });
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByRole('button', { name: 'Скачать проверенный черновик' }));
    await screen.findByRole('alert');
    const payload = JSON.parse(fetchMock.mock.calls[1][1].body);
    expect(payload.format).toBe('docx');
    expect(payload.source_fingerprint).toBe(analysis.source_fingerprint);
    expect(payload.confirmed).toBe(true);
  });
  it('clears source and draft on switching inspections', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => analysis }));
    const view = render(<VesselReportAssistant inspectionId="one" />);
    fireEvent.click(screen.getByRole('button', { name: 'Проверить данные сосуда' }));
    await screen.findByRole('textbox');
    view.rerender(<VesselReportAssistant inspectionId="two" />);
    await waitFor(() => expect(screen.queryByRole('textbox')).not.toBeInTheDocument());
  });
});
