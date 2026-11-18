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
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';

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

class _SavedSync extends _LocalSync {
  final Map<String, dynamic>? cached;
  Map<String, dynamic>? written;
  _SavedSync(this.cached);
  @override
  Future<Map<String, dynamic>?> getCachedInspection(
          {required String equipmentId,
          String? assignmentId,
          String? reportFormId,
          String? inspectionId}) async =>
      cached;
  @override
  Future<Map<String, dynamic>?> getCachedDocument(String documentId) async =>
      null;
  @override
  Future<void> cacheInspection(Map<String, dynamic> item) async {}
  @override
  Future<void> saveInspectionOffline(
      {required String equipmentId,
      required VesselChecklist checklist,
      String? conclusion,
      required String inspectionDate,
      Map<String, String>? documentFiles,
      String? assignmentId,
      String? inspectionId,
      String? sourceRevision,
      List<String>? verificationEquipmentIds,
      String status = 'DRAFT'}) async {
    written = {
      'inspection_id': inspectionId,
      'source_revision': sourceRevision,
      'data': checklist.toJson()
    };
  }
}

class _NoDraft extends AutoSaveService {
  @override
  Future<Map<String, dynamic>?> getDraftForEquipment(String equipmentId,
          {String? assignmentId,
          String? inspectionId,
          String? reportFormId}) async =>
      null;
  @override
  Future<void> saveDraft(
      {required String equipmentId,
      required Map<String, dynamic> checklistData,
      String? assignmentId,
      String? inspectionId,
      String? sourceRevision}) async {}
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

  for (final offline in [false, true]) {
    testWidgets(
        'assignment reopens full ${offline ? 'offline' : 'server'} data and autosaves the same ID',
        (tester) async {
      final server = <String, dynamic>{
        'id': 'server-complete',
        'inspection_id': 'server-complete',
        'assignment_id': 'task',
        'status': 'SIGNED',
        'revision': '2026-11-18T10:00:00Z',
        'source_revision': '2026-11-18T10:00:00Z',
        'data': {
          'report_form_id': 'to-1',
          'vessel_name': 'Сохранённый сепаратор',
          'manufacturer': 'Завод инженера',
          'inspection_engineers': [
            {
              'method': 'UZT',
              'engineer_id': 'saved-engineer',
              'full_name': 'Сохранённый инженер',
              'certificate_number': 'УЗТ-123',
              'valid_until': '2027-11-18'
            }
          ],
          'ndt_methods': ['UZT'],
          'thickness_measurements': [
            {'point_number': '1', 'thickness': 9.3, 'nominal_thickness': 10.0}
          ],
          'additional_data': {
            'profile_values': {'shell_material': '09Г2С'}
          }
        }
      };
      final sync = _SavedSync(offline ? server : null);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
            home: VesselInspectionScreen(
                equipment:
                    Equipment(id: 'vessel', name: 'Сосуд', typeCode: 'VESSEL'),
                assignmentId: 'task',
                reportFormId: 'to-1',
                syncService: sync,
                autoSaveService: _NoDraft())));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final form = tester.state<FormBuilderState>(find.byType(FormBuilder));
        expect(form.widget.initialValue['manufacturer'], 'Завод инженера');
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(sync.written, isNull,
            reason: 'Просмотр завершённого обследования не создаёт черновик');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        form.fields['contract_number']!.didChange('Договор после корректировки');
        await tester.pump();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(sync.written?['inspection_id'], 'server-complete');
        expect(sync.written?['source_revision'], '2026-11-18T10:00:00Z');
        expect(sync.written?['data']['manufacturer'], 'Завод инженера');
        expect(sync.written?['data']['contract_number'],'Договор после корректировки');
        expect(sync.written?['data']['inspection_engineers'][0]['full_name'],
            'Сохранённый инженер');
        expect(
            sync.written?['data']['inspection_engineers'][0]
                ['certificate_number'],
            'УЗТ-123');
        expect(sync.written?['data']['thickness_measurements'][0]['thickness'],
            9.3);
        expect(
            sync.written?['data']['additional_data']['profile_values']
                ['shell_material'],
            '09Г2С');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      },
          () => MockClient((request) async {
                if (request.url.path == '/api/inspections' && offline)
                  throw Exception('offline');
                return http.Response(
                    jsonEncode({
                      'items': request.url.path == '/api/inspections'
                          ? [server]
                          : [],
                      'organizations': [],
                      'engineers': [],
                      'opos': []
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
    });
  }
}
