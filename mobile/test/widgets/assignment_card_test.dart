import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:es_td_ngo_mobile/models/assignment.dart';
import 'package:es_td_ngo_mobile/services/sync_service.dart';
import 'package:es_td_ngo_mobile/widgets/assignments/assignment_card.dart';

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  final baseJson = {
    'id': 'a-1',
    'equipment_id': 'eq-1',
    'equipment_code': 'EQ-001',
    'equipment_name': 'Сосуд тестовый',
    'assignment_type': 'DIAGNOSTICS',
    'assigned_to': 'user-1',
    'status': 'PENDING',
    'priority': 'HIGH',
    'created_at': '2025-03-01T10:00:00',
    'due_date': '2026-12-31T00:00:00',
  };

  testWidgets('отображает код, название и метку статуса', (tester) async {
    final assignment = Assignment.fromJson(baseJson);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignmentCard(
            assignment: assignment,
            localInspectionState: LocalAssignmentInspectionState.none(),
            opoSurveyFilled: false,
            formatDate: _formatDate,
          ),
        ),
      ),
    );

    expect(find.text('EQ-001'), findsOneWidget);
    expect(find.text('Сосуд тестовый'), findsOneWidget);
    expect(find.text('Ожидает'), findsOneWidget);
    expect(find.text('Диагностика'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
  });

  testWidgets('при hasDraft показывает иконку облака', (tester) async {
    final assignment = Assignment.fromJson(baseJson);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignmentCard(
            assignment: assignment,
            localInspectionState:
                LocalAssignmentInspectionState.none().copyWith(hasDraft: true),
            opoSurveyFilled: false,
            formatDate: _formatDate,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text('Черновик (локально)'), findsOneWidget);
  });

  testWidgets('строка срока при наличии dueDate', (tester) async {
    final assignment = Assignment.fromJson(baseJson);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignmentCard(
            assignment: assignment,
            localInspectionState: LocalAssignmentInspectionState.none(),
            opoSurveyFilled: false,
            formatDate: _formatDate,
          ),
        ),
      ),
    );

    expect(find.textContaining('Срок:'), findsOneWidget);
  });

  testWidgets('onTap вызывается', (tester) async {
    final assignment = Assignment.fromJson(baseJson);
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignmentCard(
            assignment: assignment,
            localInspectionState: LocalAssignmentInspectionState.none(),
            opoSurveyFilled: false,
            formatDate: _formatDate,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    expect(tapped, true);
  });
}
