import { describe, expect, it } from 'vitest';
import { chooseConflict, clone, mergeVessel, newVessel, pointTemplate } from './vesselDocument';
describe('vessel shared contract', () => {
  it('merges independent entities and asks for overlapping edits', () => {
    const base = newVessel(), a = clone(base), b = clone(base);
    a.parts[0].designation = 'Local A'; b.parts[1].designation = 'Server B';
    const first = mergeVessel(base, a, b);
    expect(first.conflicts).toHaveLength(0); expect(first.merged.parts.map(p => p.designation)).toContain('Local A');
    b.parts[0].designation = 'Server A';
    const next = mergeVessel(base, a, b); expect(next.conflicts).toHaveLength(1);
    chooseConflict(next.merged, next.conflicts[0], next.conflicts[0].local);
    expect(next.merged.parts.find(p => p.id === a.parts[0].id)?.designation).toBe('Local A');
  });
  it('archives template points and restores stable IDs', () => {
    const g = newVessel(), shell = g.parts.find(p => p.kind === 'shell')!;
    pointTemplate(g, shell, 12); const ids = g.control_points.map(p => p.id);
    pointTemplate(g, shell, 4); expect(g.control_points.filter(p => !p.archived)).toHaveLength(4);
    pointTemplate(g, shell, 12); expect(g.control_points.map(p => p.id)).toEqual(ids);
    expect(g.control_points.filter(p => !p.archived)).toHaveLength(12);
  });
});
