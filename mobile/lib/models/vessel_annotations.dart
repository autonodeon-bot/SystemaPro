import 'vessel_geometry.dart';

const vesselLegendKinds = {'nozzle':'⊕ Штуцер','manway':'◎ Люк','support':'Опора','pad':'Накладка',
  'instrument':'Бобышка КИП','lug':'Проушина','drain':'Дренаж','vent':'Воздушник','cover':'Крышка — отдельный вид'};

List<String> coordinateCallout(VesselGeometry model, Map e, Map owner, {String? detail}) {
  if (model.data['print_settings']?['show_dimensions'] == false) return [];
  final point=e.containsKey('owner_id');
  if(detail==null)return [];
  final p=e['placement'] as Map? ?? {};
  if(p['mode']!='physical')return point?[]:['Положение условное'];
  String fmt(num n) => n.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'),'').replaceAll('.',',');
  final shell=owner['kind']=='shell';
  dynamic value=p[shell?'z_local_mm':'radius_projection_mm'];final angle=p['theta_deg'];
  if(value is! num || angle is! num || !value.isFinite || !angle.isFinite)return ['Координаты не заданы'];
  String linear;
  if(shell) {
    final refs=model.welds.where((w)=>w['id']==p['reference_weld_id'] && w['kind']=='circumferential' && (w['connected_part_ids'] as List).contains(owner['id']));
    var origin='от начала детали';
    if(refs.isNotEmpty) {
      final ref=refs.first;
      if((ref['connected_part_ids'] as List).first==owner['id']) {
        final length=owner['dimensions']?['length_mm'];
        if(length is! num || !length.isFinite)return ['Размер от шва не задан'];
        value=length-value;
      }
      origin='от ${ref['designation']}';
    }
    linear='${fmt(value)} мм $origin';
  } else {linear='Rпр=${fmt(value)} мм от центра';}
  return [linear,'θ=${fmt(angle%360)}°${p['angle_convention']=='visio-head-2026'?' · Visio':''}'];
}

List<String> vesselLegend(VesselGeometry model, Set<String> visible, {String layer='Все',String? detail}) {
  final labels=<String>{};
  for(final e in model.elements) {
    if(visible.contains(e['id']) && e['archived']!=true)labels.add(vesselLegendKinds[e['kind']]??'${e['kind']}');
  }
  if(model.parts.any((p)=>p['kind']=='cover'&&visible.contains(p['id'])))labels.add(vesselLegendKinds['cover']!);
  if((layer=='Все'||layer=='УЗТ') && model.points.any((p)=>visible.contains(p['id'])&&p['archived']!=true))labels.add('× Точка УЗТ');
  for(final w in model.welds) {
    final zones=model.zones.where((z)=>z['weld_id']==w['id']&&(layer=='Все'||(z['planned_methods'] as List).contains(layer))).toList();
    final shown=w['kind']=='attachment'?visible.contains(w['geometry']['element_id'])&&zones.isNotEmpty:
      model.parts.any((p)=>visible.contains(p['id'])&&(w['connected_part_ids'] as List).contains(p['id'])&&(w['kind']=='head_joint'||p['kind']=='shell'));
    if(!shown)continue;
    labels.add({'circumferential':'К — кольцевой шов','longitudinal':'П — продольный шов','head_joint':'Шов днища','attachment':'Шов приварки'}[w['kind']]!);
    for(final z in (w['kind']=='head_joint'?<VesselEntity>[]:zones)) {
      if(z['weld_id']==w['id'] && (layer=='Все'||(z['planned_methods'] as List).contains(layer))) {
        for(final method in z['planned_methods']) {labels.add('${method=='УЗК'?'/ ':'× '}$method');}
      }
    }
  }
  for(final s in model.data['sections'] as List? ?? []) {
    if(s['kind']=='ovality'&&visible.contains(s['owner_id']))labels.add('I–III овальность');
    if(s['kind']=='weld_profile'&&detail==null)labels.add('А–А твердометрия');
  }
  return labels.toList()..sort();
}

List<String> vesselLegendLines(List<String> entries,double width) {
  final lines=<String>[];var line='Обозначения: ';
  final limit=((width-40)/6.5).floor().clamp(40,10000);
  for(final entry in entries) {
    if(line.length+entry.length+3>limit) {lines.add(line);line='';}
    line+='${line.isNotEmpty&&line!='Обозначения: '?' · ':''}$entry';
  }
  if(entries.isNotEmpty)lines.add(line);
  return lines;
}
