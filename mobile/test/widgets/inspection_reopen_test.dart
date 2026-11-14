import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:es_td_ngo_mobile/models/equipment.dart';
import 'package:es_td_ngo_mobile/screens/vessel_inspection_screen.dart';
import 'package:es_td_ngo_mobile/services/auto_save_service.dart';
import 'package:es_td_ngo_mobile/services/sync_service.dart';

class _LocalSync extends SyncService {
  @override
  Future<Map<String, dynamic>?> getLatestPendingInspection(
          {required String equipmentId,
          String? assignmentId,
          String? reportFormId,
          String? inspectionId}) async =>
      null;
}

class _Drafts extends AutoSaveService {
  final Map<String, dynamic> data;
  _Drafts(this.data);
  @override
  Future<Map<String, dynamic>?> getDraftForEquipment(String equipmentId,
          {String? assignmentId,
          String? inspectionId,
          String? reportFormId}) async =>
      data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets(
      'reopening a server inspection loads the locally edited full checklist',
      (tester) async {
    final data = <String, dynamic>{
      'report_form_id': 'to-1',
      'vessel_name': 'Введено инженером',
      'manufacturer': 'Завод инженера',
      'wall_thickness': '12,5',
      'additional_data': {
        'profile_values': {'material': '09Г2С'},
        'object_photos': ['/app/uploads/photo.jpg']
      }
    };
    final draft = {
      'id': 'server-a',
      'inspection_id': 'server-a',
      'equipment_id': 'vessel',
      'saved_at': DateTime.now().toIso8601String(),
      'checklist_data': data
    };
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          home: VesselInspectionScreen(
        equipment: Equipment(id: 'vessel', name: 'Сосуд', typeCode: 'VESSEL'),
        existingInspectionId: 'server-a',
        initialChecklistJson: {
          'report_form_id': 'to-1',
          'vessel_name': 'Старая серверная копия'
        },
        syncService: _LocalSync(),
        autoSaveService: _Drafts(draft),
      )));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final form = tester.state<FormBuilderState>(find.byType(FormBuilder));
      expect(form.widget.initialValue['vessel_name'], 'Введено инженером');
      expect(form.widget.initialValue['manufacturer'], 'Завод инженера');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
        () => MockClient((request) async => http.Response(
            jsonEncode({
              'items': [],
              'organizations': [],
              'engineers': [],
              'opos': []
            }),
            200)));
  });
}
