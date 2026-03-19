import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/assignment.dart';

void main() {
  group('Assignment', () {
    final fullJson = {
      'id': 'a-001',
      'equipment_id': 'eq-001',
      'equipment_code': 'EQ-001',
      'equipment_name': 'Сосуд В-101',
      'assignment_type': 'DIAGNOSTICS',
      'assigned_by': 'user-admin',
      'assigned_to': 'user-engineer',
      'assigned_to_name': 'Иванов И.И.',
      'status': 'PENDING',
      'priority': 'HIGH',
      'due_date': '2025-06-15T00:00:00',
      'description': 'Провести диагностику сосуда',
      'created_at': '2025-01-10T12:00:00',
      'updated_at': '2025-01-11T08:30:00',
      'completed_at': null,
      'enterprise_id': 'ent-1',
      'enterprise_name': 'НефтеГаз',
      'branch_id': 'br-1',
      'branch_name': 'Филиал Север',
      'workshop_id': 'ws-1',
      'workshop_name': 'Цех 1',
      'opo_id': 'opo-1',
      'opo_name': 'ОПО №1',
      'opo_code': 'OPO-001',
    };

    group('fromJson', () {
      test('парсинг полного JSON', () {
        final assignment = Assignment.fromJson(fullJson);

        expect(assignment.id, 'a-001');
        expect(assignment.equipmentId, 'eq-001');
        expect(assignment.equipmentCode, 'EQ-001');
        expect(assignment.equipmentName, 'Сосуд В-101');
        expect(assignment.assignmentType, 'DIAGNOSTICS');
        expect(assignment.assignedBy, 'user-admin');
        expect(assignment.assignedTo, 'user-engineer');
        expect(assignment.assignedToName, 'Иванов И.И.');
        expect(assignment.status, 'PENDING');
        expect(assignment.priority, 'HIGH');
        expect(assignment.dueDate, isA<DateTime>());
        expect(assignment.description, 'Провести диагностику сосуда');
        expect(assignment.createdAt, isA<DateTime>());
        expect(assignment.updatedAt, isA<DateTime>());
        expect(assignment.completedAt, isNull);
        expect(assignment.enterpriseName, 'НефтеГаз');
        expect(assignment.opoCode, 'OPO-001');
      });

      test('парсинг с минимальными обязательными полями', () {
        final json = {
          'id': 'a-min',
          'equipment_id': 'eq-min',
          'assignment_type': 'INSPECTION',
          'assigned_to': 'user-1',
          'status': 'IN_PROGRESS',
          'priority': 'NORMAL',
          'created_at': '2025-03-01T00:00:00',
        };

        final assignment = Assignment.fromJson(json);

        expect(assignment.id, 'a-min');
        expect(assignment.equipmentCode, '');
        expect(assignment.equipmentName, '');
        expect(assignment.assignedBy, isNull);
        expect(assignment.description, isNull);
        expect(assignment.dueDate, isNull);
        expect(assignment.enterpriseId, isNull);
      });

      test('парсинг некорректной даты возвращает fallback', () {
        final json = {
          'id': 'a-bad-date',
          'equipment_id': 'eq-1',
          'assignment_type': 'DIAGNOSTICS',
          'assigned_to': 'user-1',
          'status': 'PENDING',
          'priority': 'LOW',
          'created_at': 'not-a-date',
          'due_date': 'invalid',
        };

        final assignment = Assignment.fromJson(json);

        expect(assignment.createdAt, isA<DateTime>());
        expect(assignment.dueDate, isNull);
      });

      test('парсинг null created_at использует DateTime.now()', () {
        final json = {
          'id': 'a-null-date',
          'equipment_id': 'eq-1',
          'assignment_type': 'DIAGNOSTICS',
          'assigned_to': 'user-1',
          'status': 'PENDING',
          'priority': 'NORMAL',
          'created_at': null,
        };

        final now = DateTime.now();
        final assignment = Assignment.fromJson(json);

        expect(assignment.createdAt.year, now.year);
        expect(assignment.createdAt.month, now.month);
        expect(assignment.createdAt.day, now.day);
      });
    });

    group('toJson', () {
      test('сериализация полного объекта', () {
        final assignment = Assignment.fromJson(fullJson);
        final json = assignment.toJson();

        expect(json['id'], 'a-001');
        expect(json['equipment_id'], 'eq-001');
        expect(json['equipment_code'], 'EQ-001');
        expect(json['assignment_type'], 'DIAGNOSTICS');
        expect(json['status'], 'PENDING');
        expect(json['priority'], 'HIGH');
        expect(json['enterprise_name'], 'НефтеГаз');
        expect(json['created_at'], isA<String>());
        expect(json['due_date'], isA<String>());
      });

      test('null даты сериализуются как null', () {
        final assignment = Assignment(
          id: 'a-null',
          equipmentId: 'eq-1',
          equipmentCode: '',
          equipmentName: '',
          assignmentType: 'DIAGNOSTICS',
          assignedTo: 'user-1',
          status: 'PENDING',
          priority: 'NORMAL',
          createdAt: DateTime(2025, 1, 1),
        );

        final json = assignment.toJson();

        expect(json['due_date'], isNull);
        expect(json['completed_at'], isNull);
        expect(json['updated_at'], isNull);
      });
    });

    group('fromJson → toJson roundtrip', () {
      test('roundtrip сохраняет данные', () {
        final assignment = Assignment.fromJson(fullJson);
        final json = assignment.toJson();
        final restored = Assignment.fromJson(json);

        expect(restored.id, assignment.id);
        expect(restored.equipmentId, assignment.equipmentId);
        expect(restored.assignmentType, assignment.assignmentType);
        expect(restored.status, assignment.status);
        expect(restored.priority, assignment.priority);
        expect(restored.enterpriseName, assignment.enterpriseName);
      });
    });

    group('typeLabel', () {
      test('DIAGNOSTICS → Диагностика', () {
        final a = Assignment.fromJson({...fullJson, 'assignment_type': 'DIAGNOSTICS'});
        expect(a.typeLabel, 'Диагностика');
      });

      test('EXPERTISE → Экспертиза ПБ', () {
        final a = Assignment.fromJson({...fullJson, 'assignment_type': 'EXPERTISE'});
        expect(a.typeLabel, 'Экспертиза ПБ');
      });

      test('INSPECTION → Обследование', () {
        final a = Assignment.fromJson({...fullJson, 'assignment_type': 'INSPECTION'});
        expect(a.typeLabel, 'Обследование');
      });

      test('неизвестный тип возвращает код', () {
        final a = Assignment.fromJson({...fullJson, 'assignment_type': 'CUSTOM'});
        expect(a.typeLabel, 'CUSTOM');
      });
    });

    group('statusLabel', () {
      test('PENDING → Ожидает', () {
        final a = Assignment.fromJson({...fullJson, 'status': 'PENDING'});
        expect(a.statusLabel, 'Ожидает');
      });

      test('IN_PROGRESS → В работе', () {
        final a = Assignment.fromJson({...fullJson, 'status': 'IN_PROGRESS'});
        expect(a.statusLabel, 'В работе');
      });

      test('COMPLETED → Завершено', () {
        final a = Assignment.fromJson({...fullJson, 'status': 'COMPLETED'});
        expect(a.statusLabel, 'Завершено');
      });

      test('CANCELLED → Отменено', () {
        final a = Assignment.fromJson({...fullJson, 'status': 'CANCELLED'});
        expect(a.statusLabel, 'Отменено');
      });

      test('неизвестный статус возвращает код', () {
        final a = Assignment.fromJson({...fullJson, 'status': 'UNKNOWN'});
        expect(a.statusLabel, 'UNKNOWN');
      });
    });
  });
}
