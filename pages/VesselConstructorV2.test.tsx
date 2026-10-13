import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import VesselConstructorV2 from './VesselConstructorV2';
import { newVessel } from '../utils/vesselDocument';
beforeEach(() => {
  localStorage.clear();
  vi.stubGlobal('fetch', vi.fn(async (_url, options) => {
    const geometry = options?.body ? JSON.parse(options.body).geometry : newVessel();
    return { ok: true, json: async () => ({ geometry, diagnostics: [], data: { base_vessel_scheme: { geometry } } }), blob: async () => new Blob(['<svg/>']), text: async () => '<svg/>' };
  }));
  URL.createObjectURL = vi.fn(() => 'blob:test'); URL.revokeObjectURL = vi.fn();
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
it('places an individual nozzle on the selected head with decimal-comma coordinates', async () => {
  render(<VesselConstructorV2 equipmentId="test" inspectionId="" onBack={() => {}} />);
  fireEvent.click(screen.getByRole('button', { name: '3. Элементы' }));
  fireEvent.click(screen.getByRole('button', { name: 'Штуцер' }));
  fireEvent.change(screen.getByLabelText('Координаты'), { target: { value: 'physical' } });
  const radius = screen.getByLabelText('Радиус проекции, мм'); fireEvent.change(radius, { target: { value: '350,5' } }); fireEvent.blur(radius);
  await waitFor(() => { const g = JSON.parse(localStorage.getItem('vessel-v2:test')!).geometry; expect(g.elements[0].placement.radius_projection_mm).toBe(350.5); expect(g.elements[0].parent_id).toBe(g.parts[0].id); });
});
it('undo restores element ownership without modifying the original server snapshot', () => {
  render(<VesselConstructorV2 equipmentId="test" inspectionId="" onBack={() => {}} />);
  fireEvent.click(screen.getByRole('button', { name: '3. Элементы' }));
  fireEvent.click(screen.getByRole('button', { name: 'Штуцер' }));
  fireEvent.click(screen.getByRole('button', { name: 'Отменить' }));
  const draft = JSON.parse(localStorage.getItem('vessel-v2:test')!); expect(draft.geometry.elements).toHaveLength(0); expect(draft.base.elements).toHaveLength(0);
});
