import {vesselLibrary} from '../utils/vesselLibrary';
import React, { useEffect, useRef, useState } from 'react';
import { API_BASE } from '../constants';
import { applyLibrary, recommendedNozzlePoints, exampleVessel, chooseConflict, clone, Conflict, Entity, mergeVessel, newId, newVessel, pointTemplate, rebuildRings, VesselDocument } from '../utils/vesselDocument';
import './vessel-constructor.css';

const types: Record<string, string> = { nozzle: 'Штуцер', manway: 'Люк', support: 'Опора', instrument: 'Бобышка КИП', pad: 'Усиление', drain: 'Дренаж', vent: 'Воздушник', lug: 'Строповая проушина' };
const steps = ['Основа', 'Детали и швы', 'Элементы', 'Контроль', 'Проверка'];
const headers = () => ({ 'Content-Type': 'application/json', Authorization: `Bearer ${localStorage.getItem('token') || localStorage.getItem('auth_token') || sessionStorage.getItem('auth_token') || ''}` });
async function api(path: string, body?: any, method = 'POST') {
  const r = await fetch(`${API_BASE}/api/vessel-scheme/${path}`, { method, headers: headers(), ...(body ? { body: JSON.stringify(body) } : {}) });
  if (!r.ok) { const e = await r.json(); throw Object.assign(new Error(typeof e.detail === 'string' ? e.detail : e.detail?.message || 'Ошибка сервера'), { status: r.status, detail: e.detail }); }
  return r;
}

// Only the renderer's passive SVG vocabulary may enter the document.
function safeSvg(source: string) {
  const doc = new DOMParser().parseFromString(source, 'image/svg+xml');
  const allowed = new Set(['svg','g','rect','ellipse','line','polyline','text']);
  const attrs = new Set(['xmlns','viewBox','width','height','x','y','x1','y1','x2','y2','cx','cy','rx','ry','points','fill','stroke','stroke-width','font-family','font-size','data-entity-id']);
  for (const element of Array.from(doc.querySelectorAll('*'))) {
    if (!allowed.has(element.localName)) { element.remove(); continue; }
    for (const attr of Array.from(element.attributes)) {
      if (!attrs.has(attr.name) || /url\s*\(|javascript:/i.test(attr.value)) element.removeAttribute(attr.name);
    }
  }
  return doc.documentElement.localName === 'svg' ? new XMLSerializer().serializeToString(doc.documentElement) : '';
}

export default function VesselConstructorV2({ equipmentId, inspectionId, onBack }: { equipmentId: string; inspectionId: string; onBack: () => void }) {
  const key = `vessel-v2:${inspectionId || equipmentId || 'new'}`;
  const [g, setG] = useState<VesselDocument>(() => { try { return JSON.parse(localStorage.getItem(key) || '').geometry || newVessel(); } catch { return newVessel(); } });
  const [base, setBase] = useState<VesselDocument>(() => { try { return JSON.parse(localStorage.getItem(key) || '').base || clone(g); } catch { return clone(g); } });
  const [selected, select] = useState(g.parts[0].id), [step, setStep] = useState(0), [detail, setDetail] = useState(''), [layer, setLayer] = useState('');
  const [message, setMessage] = useState('Черновик на этом устройстве'), [busy, setBusy] = useState(false), [svg, setSvg] = useState('');
  const [diagnostics, setDiagnostics] = useState<Entity[]>([]), [merge, setMerge] = useState<{ merged: VesselDocument; conflicts: Conflict[] } | null>(null);
  const [results, setResults] = useState<Entity[]>([]), [zoom, setZoom] = useState(1), [exteriorB, setExteriorB] = useState(false);
  const undo = useRef<VesselDocument[]>([]), redo = useRef<VesselDocument[]>([]);
  const entities = [...g.parts, ...g.elements, ...g.welds, ...g.control_points, ...g.control_zones, ...(g.sections || [])];
  const e = entities.find(x => x.id === selected) || g.parts[0];
  const owner = entities.find(x => x.id === (e.parent_id || e.owner_id));
  function edit(change: (next: VesselDocument) => void) {
    try { const next = clone(g); change(next); next.revision = g.revision + 1; delete next.operation_id; undo.current = [...undo.current.slice(-49), clone(g)]; redo.current = []; setG(next); setMessage('Черновик на этом устройстве'); } catch (error: any) { setMessage(error.message); }
  }
  const patch = (change: Entity) => edit(next => Object.assign([...next.parts, ...next.elements, ...next.welds, ...next.control_points, ...next.control_zones, ...(next.sections || [])].find(x => x.id === e.id)!, change));
  useEffect(() => { try { localStorage.setItem(key, JSON.stringify({ geometry: g, base, step, selected })); } catch { setMessage('Не удалось сохранить черновик: память устройства заполнена. Экспортируйте JSON.'); } }, [g, base, key, step, selected]);
  useEffect(() => {
    if (!inspectionId) return;
    let alive = true;
    api(`inspections/${inspectionId}`, undefined, 'GET').then(r => r.json()).then(r => {
      if (!alive) return; setResults(r.data?.thickness_measurements || []);
      const remote = r.data?.base_vessel_scheme?.geometry;
      if (!remote) { setMessage('У обследования ещё нет схемы. Создайте и сохраните её.'); return; }
      if (remote.schema_version !== 2) { setMessage('Схема v1: выполните миграцию в мобильном конструкторе с сохранением исходника.'); return; }
      const draft = JSON.parse(localStorage.getItem(key) || '{}');
      if (draft.geometry?.model_id === remote.model_id && draft.geometry.revision > draft.base?.revision) { setMessage('Восстановлен локальный черновик. При сохранении проверим ревизию сервера.'); }
      else { setG(remote); setBase(clone(remote)); select(remote.parts[0].id); setMessage('Загружено с сервера'); }
    }).catch(error => alive && setMessage(error.message));
    return () => { alive = false; };
  }, [inspectionId]);
  useEffect(() => {
    const controller = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const r = await fetch(`${API_BASE}/api/vessel-scheme/export?format=svg`, { method: 'POST', headers: headers(), body: JSON.stringify({ geometry: g, detail_id: detail || null, scheme_layer: layer || null, exterior_b: exteriorB }), signal: controller.signal });
        if (!r.ok) { const err = await r.json(); setMessage(typeof err.detail === 'string' ? err.detail : 'Проверьте параметры схемы'); return; }
        const source = await r.text(); if (!controller.signal.aborted) setSvg(safeSvg(source));
      } catch { /* Offline draft remains editable. */ }
    }, 350);
    return () => { clearTimeout(timer); controller.abort(); };
  }, [g, detail, layer, exteriorB]);
  function number(label: string, value: any, set: (n: number | null) => void) {
    return <label>{label}<input key={`${e.id}:${label}:${value}`} type="text" inputMode="decimal" defaultValue={value ?? ''} onBlur={event => { const raw = event.target.value.trim(); const n = raw ? Number(raw.replace(',', '.')) : null; if (n !== null && !Number.isFinite(n)) { setMessage('Введите число, например 350 или 12,5'); return; } if (n !== value) set(n); }} /></label>;
  }
  function placement(next: Entity) {
    const measured = results.some(r => r.scheme_point_id === e.id && r.thickness != null);
    const reason = measured ? window.prompt('У точки есть результат. Укажите причину перемещения:') : null;
    if (measured && !reason?.trim()) return;
    edit(doc => { const target = [...doc.elements, ...doc.control_points].find(x => x.id === e.id)!; target.placement = next;
      if (reason) (doc.revision_history ||= []).push({ entity_id: e.id, reason, revision: doc.revision, old_placement: e.placement }); });
  }
  async function loadExample() {
    if (results.some(r => r.thickness != null)) { setMessage('Откройте пример в новом обследовании: здесь уже есть замеры.'); return; }
    if (!window.confirm('Заменить схему примером Visio: 6 обечаек, 25 элементов, 138 точек? Размеры учебные. Действие можно отменить.')) return;
    try {
      const response = await fetch('/examples/visio-vessel.json');
      if (!response.ok) throw Error('Пример не загружен');
      const example = exampleVessel(await response.json());
      edit(d => { Object.keys(d).forEach(k => delete d[k]); Object.assign(d,example); });
      select(example.parts.find(p => p.kind === 'shell')!.id);setDetail('');setZoom(1);
    } catch (error: any) { setMessage(error.message); }
  }
  async function validate() {
    const response = await (await api('normalize', { geometry: g })).json(); setDiagnostics(response.diagnostics); return response.geometry;
  }
  async function save() {
    setBusy(true);
    try {
      const geometry = await validate(); geometry.base_revision = base.revision; geometry.revision = Math.max(g.revision, base.revision + 1); geometry.operation_id = newId();
      if (!inspectionId) {
        await api('save-template', { geometry, name: `Сосуд · ревизия ${geometry.revision}`, equipment_id: equipmentId || null }); setMessage('Шаблон сохранён. Для записи в обследование откройте конструктор из обследования.');
      } else {
        const result = await (await api(`inspections/${inspectionId}`, { geometry }, 'PUT')).json(); setG(result.geometry); setBase(clone(result.geometry)); setMessage('Сохранено на сервере: схема, детали и привязки точек');
      }
    } catch (error: any) {
      if (error.status === 409 && error.detail?.current_geometry) { const remote = error.detail.current_geometry; setMerge(mergeVessel(base, g, remote)); setBase(remote); setMessage('Есть изменения другого пользователя. Сравните конфликтующие элементы.'); }
      else setMessage(error.message);
    } finally { setBusy(false); }
  }
  async function download(format: string) {
    try { const blob = format === 'json' ? new Blob([JSON.stringify(g, null, 2)], { type: 'application/json' }) : await (await api(`export?format=${format}`, { geometry: g })).blob();
      const url = URL.createObjectURL(blob), a = document.createElement('a'); a.href = url; a.download = `vessel-r${g.revision}.${format}`; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (error: any) { setMessage(error.message); }
  }
  function addShell() { edit(doc => { if (doc.parts.filter(p => p.kind === 'shell').length >= 20) throw Error('Максимум 20 обечаек'); if (doc.control_zones.length) throw Error('Сначала согласуйте изменение швов: к ним привязаны зоны контроля'); const id = newId(); doc.parts.push({ id, kind: 'shell', designation: `Обечайка ${doc.parts.filter(p => p.kind === 'shell').length + 1}`, dimensions: {} }); rebuildRings(doc); select(id); }); }
  function addElement(kind: string) { const parent = g.parts.find(p => p.id === selected) || owner || g.parts[0]; edit(doc => { const id = newId(); doc.elements.push({ id, kind, parent_id: parent.id, designation: `${types[kind]} ${doc.elements.filter(x => x.kind === kind).length + 1}`, placement: { mode: 'schematic', u: .5, v: .5 }, dimensions: {} }); select(id); }); }
  const part = g.parts.find(p => p.id === selected);
  return <main className="vessel-editor">
    <header><button onClick={onBack}>← Формы</button><div><h1>Конструктор сосуда</h1><small>Ревизия {g.revision} · мм · градусы</small></div><button disabled={!undo.current.length} onClick={() => { redo.current.push(g); const prev = undo.current.pop()!; prev.revision = g.revision + 1; setG(prev); }}>Отменить</button><button disabled={!redo.current.length} onClick={() => { undo.current.push(g); const next = redo.current.pop()!; next.revision = g.revision + 1; setG(next); }}>Повторить</button><button className="primary" disabled={busy || !!merge} onClick={save}>Сохранить</button></header>
    <nav>{steps.map((title, i) => <button key={title} className={step === i ? 'active' : ''} onClick={() => setStep(i)}>{i + 1}. {title}</button>)}</nav>
    <p role="status" className="vessel-status">{message}</p>
    {merge && <section className="vessel-conflicts"><h2>Сравнение версий</h2><p>Независимые изменения объединены. Для каждой строки выберите нужный вариант.</p>{merge.conflicts.map((c, i) => <article key={`${c.key}:${c.id}`}><strong>{c.local?.designation || c.remote?.designation || c.key}</strong><div className="vessel-compare">{['local', 'remote'].map(side => <div key={side}><pre>{JSON.stringify(c[side as 'local' | 'remote'], null, 2) || 'Удалено'}</pre><button onClick={() => { const next = clone(merge.merged); chooseConflict(next, c, c[side as 'local' | 'remote']); setMerge({ merged: next, conflicts: merge.conflicts.filter((_, j) => j !== i) }); }}>{side === 'local' ? 'Моя версия' : 'Серверная версия'}</button></div>)}</div></article>)}<button disabled={merge.conflicts.length > 0} onClick={() => { setG(merge.merged); setMerge(null); setMessage('Сравнение завершено. Проверьте схему и сохраните.'); }}>Применить объединение</button></section>}
    <div className="vessel-workspace"><aside className="vessel-tree"><h2>Состав сосуда</h2>{g.parts.map(p => <section key={p.id}><button className={selected === p.id ? 'active' : ''} onClick={() => select(p.id)}>{p.designation}</button>{g.elements.filter(x => x.parent_id === p.id).map(x => <button className={selected === x.id ? 'active child' : 'child'} key={x.id} onClick={() => select(x.id)}>{types[x.kind]} · {x.designation}</button>)}</section>)}<button onClick={addShell}>＋ Обечайка</button><h3>Швы и зоны</h3>{g.welds.map(w => <section key={w.id}><button onClick={() => select(w.id)}>{w.designation}</button>{g.control_zones.filter(z => z.weld_id === w.id).map(z => <button className="child" key={z.id} onClick={() => select(z.id)}>{z.designation} · {z.planned_methods.join(', ')}</button>)}</section>)}{(g.sections || []).map((s: Entity) => <button key={s.id} onClick={() => select(s.id)}>{s.designation}</button>)}</aside>
      <section className="vessel-canvas"><div className="vessel-toolbar"><select aria-label="Вид" value={detail} onChange={ev => setDetail(ev.target.value)}><option value="">Общий вид</option>{g.parts.map(p => <option key={p.id} value={p.id}>{p.designation}</option>)}</select><select aria-label="Метод" value={layer} onChange={ev => setLayer(ev.target.value)}>{["", "УЗТ", "УЗК", "МК", "ПВК", "ВИК"].map(m => <option key={m} value={m}>{m || "Все методы"}</option>)}</select><label>Масштаб<input type="range" min="0.5" max="3" step="0.1" value={zoom} onChange={ev => setZoom(Number(ev.target.value))} /></label><button onClick={() => setZoom(1)}>Вписать</button><label><input type="checkbox" checked={exteriorB} onChange={ev => setExteriorB(ev.target.checked)} /> B снаружи</label><span>{g.control_points.filter(p => !p.archived).length} точек</span></div><div className="vessel-scroll">{svg ? <div className="vessel-vector" role="img" aria-label="Развёртка сосуда: нажмите на обозначение элемента или точки" style={{ width: `${zoom * 100}%` }} onClick={event => { const node = (event.target as Element).closest('[data-entity-id]'); if (node) select(node.getAttribute('data-entity-id')!); }} dangerouslySetInnerHTML={{__html: svg}} /> : <p>Предпросмотр появится после подключения к серверу. Изменения сохраняются на устройстве.</p>}</div></section>
      <aside className="vessel-properties"><h2>{e.designation || `Точка ${e.body_number || e.local_number || ''}`}</h2>
        {step === 0 && <><button onClick={loadExample}>Пример Visio · 6 обечаек</button><label>Ориентация<select value={g.orientation} onChange={ev => edit(d => { d.orientation = ev.target.value; })}><option value="vertical">Вертикальный</option><option value="horizontal">Горизонтальный</option></select></label><label>Описание нулевой образующей<input value={g.coordinate_frame.zero_description} onChange={ev => edit(d => { d.coordinate_frame.zero_description = ev.target.value; })} /></label><label><input type="checkbox" checked={g.coordinate_frame.confirmed} onChange={ev => edit(d => { d.coordinate_frame.confirmed = ev.target.checked; })} /> Ноль проверен по источнику</label>{number('Разрез развёртки, °', g.views[0].cut_angle_deg, n => edit(d => { d.views[0].cut_angle_deg = n || 0; }))}<p>Угол задаётся по часовой стрелке со стороны A. Размеры вводятся в миллиметрах.</p></>}
        <label>Обозначение<input value={e.designation || ''} onChange={ev => patch({ designation: ev.target.value })} /></label>
        {(part || g.elements.some(x => x.id === e.id)) && <><h3>Размеры</h3>{['length_mm','diameter_mm','thickness_mm'].map((field, i) => <React.Fragment key={field}>{number(['Длина, мм','Диаметр, мм','Толщина, мм'][i], e.dimensions?.[field], n => patch({ dimensions: { ...e.dimensions, [field]: n } }))}</React.Fragment>)}<label>Источник размеров<input value={e.dimension_source || ''} onChange={ev => patch({ dimension_source: ev.target.value })} /></label></>}
        {part?.kind === 'head' && <label>Форма днища<select value={part.head_type} onChange={ev => patch({ head_type: ev.target.value })}><option value="elliptical">Эллиптическое</option><option value="hemispherical">Полусферическое</option><option value="flat">Плоское</option><option value="conical">Коническое</option></select></label>}
        {step === 1 && part?.kind === 'shell' && <button onClick={() => edit(d => { const id = newId(); d.welds.push({ id, kind: 'longitudinal', designation: `П${d.welds.filter(w => w.kind === 'longitudinal').length + 1}`, connected_part_ids: [part.id], geometry: { theta_deg: 0 } }); select(id); })}>＋ Фактический продольный шов</button>}
        {e.kind === 'longitudinal' && number('Угол шва, °', e.geometry.theta_deg, n => patch({ geometry: { theta_deg: n || 0 } }))}
        {step === 2 && part && <><h3>Готовые элементы</h3><div className="vessel-palette">{Object.entries(vesselLibrary).map(([kind,title])=><button key={kind} onClick={()=>edit(d=>select(applyLibrary(d,kind,d.parts.find(p=>p.id===part.id)!)))}><svg width="32" height="32" viewBox="0 0 32 32" aria-hidden="true">{kind.startsWith('nozzle')||kind==='cover'?<><circle cx="16" cy="16" r="11" fill="none" stroke="currentColor"/><path d="M2 16h28 M16 2v28" stroke="currentColor"/>{kind!=='nozzle_none'&&<circle cx="16" cy="16" r="14" fill="none" stroke="currentColor"/>}</>:<path d={kind==='support'?'M12 2h8v28h-8z':kind==='profile'?'M3 13h26v6H3z M16 2v28':'M3 16h26'} fill="none" stroke="currentColor"/>}</svg>{title}</button>)}{Object.entries(types).map(([kind, title]) => <button key={kind} onClick={() => addElement(kind)}><span aria-hidden="true">{kind === 'nozzle' ? '⊕' : kind === 'manway' ? '◎' : kind === 'support' ? '△' : '◇'}</span>{title}</button>)}</div></>}
        {types[e.kind] && <>{number('ДУ (номинальный), мм',e.nominal_dn_mm,n=>patch({nominal_dn_mm:n}))}{number('Диаметр отверстия, мм',e.opening_diameter_mm,n=>patch({opening_diameter_mm:n}))}{e.kind==='nozzle'&&<button onClick={()=>{const n=recommendedNozzlePoints(e.nominal_dn_mm);if(!n){setMessage('Сначала задайте ДУ');return;}if(!window.confirm(`Применить ${n} точки по ДУ? Лишние точки будут архивированы с сохранением результатов.`))return;edit(d=>pointTemplate(d,e,n));}}>По ДУ: {recommendedNozzlePoints(e.nominal_dn_mm)||'?'} точки</button>}<label>Присоединение к сосуду<select value={e.attachment_to_vessel || 'unknown'} onChange={ev => patch({attachment_to_vessel: ev.target.value})}><option value="unknown">Не задано</option><option value="welded">Сварное</option><option value="flanged">Фланцевое</option></select></label><label>Концевое соединение<select value={e.end_connection || 'unknown'} onChange={ev => patch({end_connection: ev.target.value})}><option value="unknown">Не задано</option><option value="flanged">Фланец</option><option value="threaded">Резьба</option><option value="welded">Под сварку</option></select></label></>}
        {e.placement && <><h3>Подпись отдельно от точки</h3>{number('Сдвиг подписи X',g.views[0].label_overrides?.[e.id]?.dx,n => edit(d => { (d.views[0].label_overrides ||= {})[e.id] = {...d.views[0].label_overrides[e.id],dx:n || 0}; }))}{number('Сдвиг подписи Y',g.views[0].label_overrides?.[e.id]?.dy,n => edit(d => { (d.views[0].label_overrides ||= {})[e.id] = {...d.views[0].label_overrides[e.id],dy:n || 0}; }))}</>}
        {step === 3 && part?.kind === 'shell' && <button onClick={() => edit(d => { if (!part.dimensions?.length_mm) throw Error('Сначала задайте длину обечайки'); const id=newId(); (d.sections ||= []).push({id,kind:'ovality',owner_id:part.id,designation:'I–I',z_local_mm:part.dimensions.length_mm/2});select(id); })}>＋ Сечение овальности</button>}
        {e.kind === 'ovality' && <>{number('От начала обечайки, мм',e.z_local_mm,n => patch({z_local_mm:n || 0}))}<p>Оценка годности автоматически не назначается.</p></>}
        {['head','cover'].includes(e.kind) && <button onClick={() => {
          const raw=window.prompt('Шов детали: смещение от центра, мм (минус — выше центра)','0');
          if (raw===null) return;
          const offset=Number(raw.replace(',','.'));
          if (!Number.isFinite(offset) || !e.dimensions?.diameter_mm || Math.abs(offset)>=e.dimensions.diameter_mm/2) { setMessage('Задайте диаметр и смещение внутри детали');return; }
          edit(d => { const id=newId();d.welds.push({id,kind:'head_joint',designation:`П${d.welds.filter(w=>w.kind!=='circumferential').length+1}`,connected_part_ids:[e.id],geometry:{offset_mm:offset}});select(id); });
        }}>Добавить шов днища / крышки</button>}
        {['nozzle','manway'].includes(e.kind) && <button onClick={() => edit(d => {
          let weld=d.welds.find(w=>w.kind==='attachment' && w.geometry.element_id===e.id);
          if (!weld) { weld={id:newId(),kind:'attachment',designation:`Шов ${e.designation}`,connected_part_ids:[e.parent_id],geometry:{element_id:e.id}};d.welds.push(weld); }
          select(weld.id);setStep(3);
        })}>Контроль шва приварки</button>}
        {e.kind === 'manway' && <button onClick={() => edit(d => { const found = d.parts.find(p => p.parent_id === e.id); if (found) { select(found.id); return; } const id = newId(); d.parts.push({ id, kind: 'cover', parent_id: e.id, designation: `Крышка ${e.designation}`, dimensions: {} }); select(id); })}>Открыть / создать крышку</button>}
        {e.placement && <><h3>Положение на {owner?.designation}</h3>{owner?.kind==='shell'&&<label>Базовый шов<select value={e.placement.reference_weld_id||g.welds.find(w=>w.kind==='circumferential'&&w.connected_part_ids.at(-1)===owner.id)?.id||''} onChange={ev=>placement({...e.placement,reference_weld_id:ev.target.value})}>{g.welds.filter(w=>w.kind==='circumferential'&&w.connected_part_ids.includes(owner.id)).map(w=><option key={w.id} value={w.id}>{w.designation}</option>)}</select></label>}{['head','cover'].includes(owner?.kind)&&<label>Отсчёт на днище<select value={e.placement.angle_convention||'legacy'} onChange={ev=>placement({...e.placement,angle_convention:ev.target.value})}><option value="legacy">Прежний: 0° сверху</option><option value="visio-head-2026">Visio: A 0° слева, B 0° справа; 90° сверху</option></select></label>}<label>Координаты<select value={e.placement.mode} onChange={ev => placement(ev.target.value === 'physical' ? { mode: 'physical', theta_deg: 0, [owner?.kind === 'shell' ? 'z_local_mm' : 'radius_projection_mm']: 0 } : { mode: 'schematic', u: .5, v: .5 })}><option value="schematic">Условное положение</option><option value="physical">Точные мм и градусы</option></select></label>{e.placement.mode === 'physical' ? <>{number(owner?.kind === 'shell' ? 'До центра от базового шва, мм' : 'Радиус проекции, мм', owner?.kind==='shell' && g.welds.find(w=>w.id===e.placement.reference_weld_id)?.connected_part_ids[0]===owner.id ? owner.dimensions.length_mm-e.placement.z_local_mm : e.placement[owner?.kind === 'shell' ? 'z_local_mm' : 'radius_projection_mm'], n => placement({ ...e.placement, [owner?.kind === 'shell' ? 'z_local_mm' : 'radius_projection_mm']: owner?.kind==='shell' && g.welds.find(w=>w.id===e.placement.reference_weld_id)?.connected_part_ids[0]===owner.id ? owner.dimensions.length_mm-(n||0) : n || 0 }))}{number('Угол, °', e.placement.theta_deg, n => placement({ ...e.placement, theta_deg: n || 0 }))}</> : <>{number('Доля по X (0–1)', e.placement.u, n => placement({ ...e.placement, u: n ?? .5 }))}{number('Доля по Y (0–1)', e.placement.v, n => placement({ ...e.placement, v: n ?? .5 }))}</>}</>}
        {step === 3 && (part || types[e.kind]) && <><h3>Точки УЗТ</h3>{[2,4,6,12].map(count => <button key={count} onClick={() => edit(d => pointTemplate(d, e, count))}>{count} точек</button>)}<p>Шаблон задаёт план. Уменьшение числа архивирует лишние точки и сохраняет результаты.</p>{g.control_points.filter(p => p.owner_id === e.id).map(p => <button key={p.id} onClick={() => select(p.id)}>Точка {p.body_number || p.local_number}{p.archived ? ' · архив' : ''}</button>)}</>}
        {step === 3 && g.welds.some(w => w.id === e.id) && <><h3>Независимые зоны контроля</h3>{['УЗК','МК','ПВК','ВИК'].map(method => <button key={method} onClick={() => edit(d => { const id = newId(); d.control_zones.push({ id, kind: 'weld_zone', designation: `${method} ${e.designation}`, weld_id: e.id, planned_methods: [method], coverage: { kind: 'whole' } }); select(id); })}>＋ {method}</button>)}<button onClick={() => edit(d => { const id = newId(); (d.sections ||= []).push({ id, kind: 'weld_profile', owner_id: e.id, designation: 'А–А', method:'ТВ', positions: ['Основной металл','ЗТВ','Шов','ЗТВ','Основной металл'] }); select(id); })}>＋ Профиль пяти позиций</button></>}
        {e.coverage && <><label>Объём<select value={e.coverage.kind} onChange={ev => patch({ coverage: ev.target.value === 'whole' ? { kind: 'whole' } : { kind: ev.target.value, start: 0, end: ev.target.value === 'sector' ? 90 : 1 } })}><option value="whole">Весь шов</option><option value="sector">Сектор, градусы</option><option value="interval">Интервал 0–1</option></select></label>{e.coverage.kind !== 'whole' && <>{number('Начало', e.coverage.start, n => patch({ coverage: { ...e.coverage, start: n || 0 } }))}{number('Конец', e.coverage.end, n => patch({ coverage: { ...e.coverage, end: n || 0 } }))}<p>Сектор 350° → 10° проходит через ноль.</p></>}</>}
        {e.kind === 'weld_profile' && <label>Метод<select value={e.method || ''} onChange={ev => patch({ method: ev.target.value || null })}><option value="">Не задан</option><option value="ТВ">Твердометрия</option></select></label>}
        {step === 4 && <><button onClick={() => validate().catch(error => setMessage(error.message))}>Проверить модель</button>{diagnostics.map((d, i) => <button key={i} onClick={() => select(d.entity_id)}>{d.message}</button>)}<label>Лист общей схемы<select value={g.print_settings?.paper||'auto'} onChange={ev=>edit(d=>{d.print_settings={...d.print_settings,paper:ev.target.value};})}><option value="auto">Автоматически А4 / А3</option><option value="A4">А4</option><option value="A3">А3</option></select></label><p>Горизонтальный — альбомный; вертикальный — книжный. В PDF одна общая схема с легендой.</p><button onClick={() => download('pdf')}>PDF · отдельный лист</button><button onClick={() => download('svg')}>SVG</button><button onClick={() => download('json')}>Резервная копия JSON</button><p>Предупреждения о неподтверждённых размерах нужно сверить с исходным чертежом.</p></>}
      </aside></div>
  </main>;
}
