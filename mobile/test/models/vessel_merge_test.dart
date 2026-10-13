import 'package:flutter_test/flutter_test.dart';
import '../../lib/models/vessel_geometry.dart';
import '../../lib/models/vessel_merge.dart';

void main() {
  test('independent edits merge; same entity requires explicit choice', () {
    final base = VesselGeometry.create().data;
    final local = VesselGeometry.copy(base), remote = VesselGeometry.copy(base);
    local['parts'][0]['designation'] = 'Моя A';
    remote['parts'][1]['designation'] = 'Новая B';
    final merged = VesselMerge(base, local, remote);
    expect(merged.conflicts, isEmpty);
    expect(merged.merged['parts'][0]['designation'], 'Моя A');
    remote['parts'][0]['designation'] = 'Новая A';
    final conflict = VesselMerge(base, local, remote);
    expect(conflict.conflicts.length, 1);
    conflict.choose(conflict.conflicts.first, true);
    expect(conflict.conflicts, isEmpty);
    expect((conflict.merged['parts'] as List).where((p) => p['designation']=='Моя A').length, 1);
  });
}
