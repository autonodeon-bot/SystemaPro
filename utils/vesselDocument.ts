export type Entity = Record<string, any>;
export type VesselDocument = Entity & { schema_version: 2; model_id: string; revision: number; parts: Entity[]; elements: Entity[]; welds: Entity[]; control_points: Entity[]; control_zones: Entity[]; views: Entity[] };
export const newId = () => crypto.randomUUID();
export function exampleVessel(raw: VesselDocument): VesselDocument {
  const ids = new Map<string,string>();
  const collect = (v: any) => { if (v && typeof v === 'object') { if (typeof v.id === 'string') ids.set(v.id,newId()); Object.values(v).forEach(collect); } };
  collect(raw);
  const remap = (v: any): any => Array.isArray(v) ? v.map(remap) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k,x]) => [ids.get(k) || k,remap(x)])) : typeof v === 'string' ? ids.get(v) || v : v;
  return {...remap(raw),model_id:newId(),revision:0};
}
export const clone = <T,>(v: T): T => v === undefined ? v : JSON.parse(JSON.stringify(v));
const same = (a: any, b: any) => JSON.stringify(a) === JSON.stringify(b);
export function rebuildRings(g: VesselDocument) {
  const chain = [g.parts.find(p => p.side === 'A')!, ...g.parts.filter(p => p.kind === 'shell'), g.parts.find(p => p.side === 'B')!];
  const rings = chain.slice(1).map((part, i) => {
    const ids = [chain[i].id, part.id];
    const old = g.welds.find(w => w.kind === 'circumferential' && same(w.connected_part_ids, ids));
    return { ...old, id: old?.id || newId(), kind: 'circumferential', designation: `К${i + 1}`, connected_part_ids: ids, geometry: { boundary_index: i } };
  });
  g.welds = [...rings, ...g.welds.filter(w => w.kind !== 'circumferential')];
}
export function newVessel(): VesselDocument {
  const g = { schema_version: 2, model_id: newId(), revision: 0, units: 'mm', equipment_kind: 'vessel', orientation: 'vertical',
    coordinate_frame: { axis: 'A_to_B', view_from: 'A', clockwise: true, zero_description: '', confirmed: false },
    parts: ['A', 'B'].map(side => ({ id: newId(), kind: 'head', side, designation: `Днище ${side}`, head_type: 'elliptical', dimensions: {} })),
    elements: [], welds: [], control_points: [], control_zones: [], control_templates: [], source_documents: [],
    views: [{ id: newId(), kind: 'development', cut_angle_deg: 0, label_overrides: {} }], sections: [] } as VesselDocument;
  g.parts.push({ id: newId(), kind: 'shell', designation: 'Обечайка 1', dimensions: {} }); rebuildRings(g); return g;
}
export function pointTemplate(g: VesselDocument, owner: Entity, count: number) {
  const existing = g.control_points.filter(p => p.owner_id === owner.id);
  existing.forEach((p, i) => { p.archived = i >= count; });
  for (let i = existing.length; i < count; i++) {
    const shell = owner.kind === 'shell';
    const u = shell ? (Math.floor(i / 4) + 1) / (Math.ceil(count / 4) + 1) : .5 + .32 * Math.sin(i * 2 * Math.PI / count);
    const v = shell ? (i % 4) / 4 : .5 - .32 * Math.cos(i * 2 * Math.PI / count);
    const cardinal=[[.18,.5],[.82,.5],[.5,.18],[.5,.82]];
    const pair=['nozzle','manway'].includes(owner.kind)&&count<=4?cardinal[i]:[u,v];
    g.control_points.push({ id: newId(), kind: 'point', owner_id: owner.id, local_number: i + 1, planned_methods: ['УЗТ'], status: 'planned', placement: { mode: 'schematic', u:pair[0], v:pair[1] } });
  }
  let n = 1;
  g.parts.filter(p => p.kind === 'shell').forEach(p => g.control_points.filter(x => x.owner_id === p.id && !x.archived).forEach(x => { x.body_number = n++; }));
}
export type Conflict = { key: string; id?: string; local: any; remote: any };
/** Three-way comparison by stable entity ID; unresolved conflicts require a human choice. */
export function mergeVessel(base: VesselDocument, local: VesselDocument, remote: VesselDocument) {
  if (local.model_id !== remote.model_id) throw new Error('Другой сосуд: нельзя объединить разные модели');
  const merged = clone(remote), conflicts: Conflict[] = [];
  for (const key of new Set([...Object.keys(base), ...Object.keys(local), ...Object.keys(remote)])) {
    if (['revision','base_revision','operation_id','diagnostics'].includes(key)) continue;
    const b = base[key], l = local[key], r = remote[key];
    if (same(l, b)) continue;
    if (same(r, b) || same(l, r)) { merged[key] = clone(l); continue; }
    if (Array.isArray(l) && Array.isArray(r) && [...l, ...r].every(e => e?.id)) {
      const result: Entity[] = [];
      for (const id of new Set([...r.map(e => e.id), ...l.map(e => e.id), ...(b || []).map((e: Entity) => e.id)])) {
        const be = b?.find((e: Entity) => e.id === id), le = l.find(e => e.id === id), re = r.find(e => e.id === id);
        let chosen = re;
        if (same(le, be)) chosen = re;
        else if (same(re, be) || same(le, re)) chosen = le;
        else conflicts.push({ key, id, local: le, remote: re });
        if (chosen) result.push(clone(chosen));
      }
      merged[key] = result;
    } else conflicts.push({ key, local: l, remote: r });
  }
  merged.base_revision = remote.revision;
  merged.revision = Math.max(local.revision, remote.revision) + 1;
  merged.operation_id = newId();
  return { merged, conflicts };
}
export function chooseConflict(g: VesselDocument, c: Conflict, value: any) {
  if (c.id) { const index = g[c.key].findIndex((e: Entity) => e.id === c.id); if (index >= 0) { if (value) g[c.key][index] = clone(value); else g[c.key].splice(index, 1); } else if (value) g[c.key].push(clone(value)); }
  else if (value === undefined) delete g[c.key]; else g[c.key] = clone(value);
}

export const recommendedNozzlePoints=(dn:number|null|undefined)=>dn && dn>0?(dn<150?2:4):null;
export function applyLibrary(g:VesselDocument, preset:string, owner:Entity):string {
 const add=(kind:string,parent=owner.id)=>{const e={id:newId(),kind,parent_id:parent,designation:`${kind==='manway'?'Л':'Э'}${g.elements.length+1}`,placement:{mode:'schematic',u:.5,v:.5},library_preset:preset} as Entity;g.elements.push(e);return e;};
 if(preset.startsWith('nozzle_')||preset==='support') {
  const e=add(preset==='support'?'support':'nozzle');
  if(preset!=='support'&&preset!=='nozzle_none') {
   e.nominal_dn_mm=preset.includes('small')?100:150;pointTemplate(g,e,recommendedNozzlePoints(e.nominal_dn_mm)!);
   const w={id:newId(),kind:'attachment',designation:`Шов ${e.designation}`,connected_part_ids:[owner.id],geometry:{element_id:e.id}};g.welds.push(w);
   g.control_zones.push({id:newId(),kind:'weld_zone',designation:`${g.control_zones.length+1} уч.`,weld_id:w.id,planned_methods:[...(preset.endsWith('combined')?['УЗК']:[]),'ПВК'],coverage:{kind:'whole'}});
  } return e.id;
 }
 if(preset==='cover') {const man=owner.kind==='manway'?owner:add('manway');let cover=g.parts.find(p=>p.parent_id===man.id);if(!cover){cover={id:newId(),kind:'cover',parent_id:man.id,designation:`Крышка ${man.designation}`,dimensions:{}};g.parts.push(cover);}pointTemplate(g,cover,6);if(!g.elements.some(e=>e.parent_id===cover!.id)){for(let i=0;i<2;i++){const id=applyLibrary(g,i===0?'nozzle_large':'nozzle_large_combined',cover);g.elements.find(e=>e.id===id)!.placement={mode:'schematic',u:.5,v:i===0?.3:.7};}}return cover.id;}
 if(preset==='point'){const p={id:newId(),kind:'point',owner_id:owner.id,local_number:g.control_points.filter(p=>p.owner_id===owner.id).length+1,planned_methods:['УЗТ'],placement:{mode:'schematic',u:.5,v:.5}};g.control_points.push(p);return p.id;}
 if(preset==='longitudinal') {const shell=owner.kind==='shell';const w={id:newId(),kind:shell?'longitudinal':'head_joint',designation:`П${g.welds.filter(w=>w.kind!=='circumferential').length+1}`,connected_part_ids:[owner.id],geometry:shell?{theta_deg:0}:{offset_mm:0}};g.welds.push(w);return w.id;}
 const w=g.welds.includes(owner)?owner:g.welds.find(w=>w.connected_part_ids.includes(owner.id)&&(preset.includes('ring')?w.kind==='circumferential':w.kind!=='circumferential'));
 if(!w)throw Error('Сначала выберите соответствующий шов');
 if(preset==='ring')return w.id;
 if(preset==='profile'){(g.sections||=[]).push({id:newId(),kind:'weld_profile',owner_id:w.id,designation:'А–А',method:'ТВ',positions:['Основной металл','ЗТВ','Шов','ЗТВ','Основной металл']});return w.id;}
 const z={id:newId(),kind:'weld_zone',designation:`${g.control_zones.length+1} уч.`,weld_id:w.id,planned_methods:['УЗК','ПВК'],coverage:{kind:'whole'}};g.control_zones.push(z);return z.id;
}
