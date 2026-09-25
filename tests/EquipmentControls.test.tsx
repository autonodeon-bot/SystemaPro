import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import SearchSelect from '../components/ui/SearchSelect';
import { equipmentPayload } from '../components/equipment/equipmentPayload';
import type { CreateFormData } from '../components/equipment/types';

beforeAll(() => {
  Object.defineProperty(HTMLDialogElement.prototype, 'showModal', { configurable: true, value: function (this: HTMLDialogElement) { this.setAttribute('open', ''); } });
  Object.defineProperty(HTMLDialogElement.prototype, 'close', { configurable: true, value: function (this: HTMLDialogElement) { this.removeAttribute('open'); } });
});
afterAll(() => vi.restoreAllMocks());

describe('equipment controls', () => {
  it('searches by code and selects an option without submitting its parent form', async () => {
    const onChange = vi.fn();
    const submit = vi.fn();
    const user = userEvent.setup();
    render(<form onSubmit={submit}><SearchSelect label="Тип оборудования" value="" onChange={onChange}
      options={[{ value: 'a', label: 'Сосуд', description: 'VESSEL' }, { value: 'b', label: 'Электродвигатель', description: 'MOTOR' }]} /></form>);
    await user.click(screen.getByRole('button', { name: 'Тип оборудования' }));
    const dialog = screen.getByRole('dialog', { name: 'Тип оборудования' });
    await user.type(within(dialog).getByRole('searchbox'), 'motor');
    expect(within(dialog).queryByText('Сосуд')).not.toBeInTheDocument();
    await user.click(within(dialog).getByRole('button', { name: /Электродвигатель/ }));
    expect(onChange).toHaveBeenCalledWith('b');
    expect(submit).not.toHaveBeenCalled();
  });

  it('preserves equipment attributes and allows clearing text when editing', () => {
    const fields = { name: '  Насос  ', serial_number: '', location: '', type_id: 'type', commissioning_date: '' } as CreateFormData;
    const payload = equipmentPayload(fields, true);
    expect(payload).not.toHaveProperty('attributes');
    expect(payload).not.toHaveProperty('workshop_id');
    expect(payload.name).toBe('Насос');
    expect(payload.serial_number).toBe('');
  });
});
