import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/services/inspection_resume.dart';

void main() {
  test('GPS and page navigation do not change the saved document content', () {
    final first = {
      'vessel_name': 'Сосуд',
      'additional_data': {
        'profile_values': {'shell_material': '09Г2С'},
        'current_page': 1
      }
    };
    final second = {
      'vessel_name': 'Сосуд',
      'gps_coordinates': {'latitude': 57.1},
      'additional_data': {
        'current_page': 5,
        'gps_coordinates': {'latitude': 57.1},
        '_client_document_id': 'local',
        'profile_values': {'shell_material': '09Г2С'}
      }
    };
    expect(inspectionContentSnapshot(first), inspectionContentSnapshot(second));
    expect(
        inspectionContentSnapshot({...second, 'vessel_name': 'Другой сосуд'}),
        isNot(inspectionContentSnapshot(first)));
  });
  final complete = <String, dynamic>{
    'id': 'complete',
    'assignment_id': 'task',
    'status': 'SIGNED',
    'created_at': '2026-11-18T09:49:00Z',
    'data': {'report_form_id': 'to-1', 'manufacturer': 'Сохранено'}
  };
  test(
      'reopens the completed assignment using its top-level ID, ignoring sparse autosave copies',
      () {
    final result = inspectionToResume([
      {...complete, 'id': 'another-task', 'assignment_id': 'different'},
      {...complete, 'id': 'archived', 'is_archived': true},
      {
        ...complete,
        'id': 'blank',
        'status': 'DRAFT',
        'created_at': '2026-11-18T10:05:00Z'
      },
      complete,
    ], assignmentId: 'task', reportFormId: 'to-1');
    expect(result?['id'], 'complete');
    expect(result?['data']['manufacturer'], 'Сохранено');
  });
  test(
      'does not open a different report form or a different vessel inspection ID',
      () {
    expect(
        inspectionToResume([complete],
            assignmentId: 'task', reportFormId: 'to-3'),
        isNull);
    expect(inspectionToResume([complete], inspectionId: 'missing'), isNull);
  });
  test(
      'explicit edit opens the requested record and does not silently substitute another',
      () {
    expect(
        inspectionToResume([
          complete,
          {...complete, 'id': 'draft', 'status': 'DRAFT'}
        ], inspectionId: 'draft')?['id'],
        'draft');
  });
}
