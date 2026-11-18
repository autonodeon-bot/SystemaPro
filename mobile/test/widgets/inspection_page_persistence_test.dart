import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:es_td_ngo_mobile/models/assignment.dart';
import 'package:es_td_ngo_mobile/models/equipment.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/screens/vessel_inspection_screen.dart';
import 'package:es_td_ngo_mobile/services/auto_save_service.dart';
import 'package:es_td_ngo_mobile/services/sync_service.dart';
import 'package:es_td_ngo_mobile/widgets/inspection/inspection_passport_section.dart';

Map<String, dynamic> _copy(Map<String, dynamic> data) =>
    jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

class _PageDrafts extends AutoSaveService {
  Map<String, dynamic>? saved;
  Completer<void>? firstWrite;
  int writes = 0;
  bool failFirstWrite = false;
  @override
  Future<void> saveDraft(
      {required String equipmentId,
      required Map<String, dynamic> checklistData,
      String? assignmentId,
      String? inspectionId,
      String? sourceRevision}) async {
    final value = _copy({
      'equipment_id': equipmentId,
      'assignment_id': assignmentId,
      'inspection_id': inspectionId,
      'source_revision': sourceRevision,
      'checklist_data': checklistData,
      'saved_at': DateTime.now().toIso8601String()
    });
    writes++;
    if (writes == 1 && failFirstWrite) throw StateError('Test storage failure');
    if (writes == 1 && firstWrite != null) await firstWrite!.future;
    saved = value;
  }

  @override
  Future<Map<String, dynamic>?> getDraftForEquipment(String equipmentId,
          {String? assignmentId,
          String? inspectionId,
          String? reportFormId}) async =>
      saved == null ? null : _copy(saved!);
}

class _PageSync extends SyncService {
  Map<String, dynamic>? saved;
  Completer<void>? firstWrite;
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> getCachedDocument(String documentId) async =>
      null;
  @override
  Future<Map<String, dynamic>?> getCachedInspection(
          {required String equipmentId,
          String? assignmentId,
          String? reportFormId,
          String? inspectionId}) async =>
      null;
  @override
  Future<List<Assignment>> getOfflineAssignments() async => [];
  @override
  Future<Map<String, dynamic>?> getLatestPendingInspection(
          {required String equipmentId,
          String? assignmentId,
          String? reportFormId,
          String? inspectionId}) async =>
      saved == null ? null : _copy(saved!);
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
    final value = _copy({
      'equipment_id': equipmentId,
      'assignment_id': assignmentId,
      'inspection_id': inspectionId,
      'source_revision': sourceRevision,
      'data': checklist.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
      'status': status
    });
    writes++;
    if (writes == 1 && firstWrite != null) await firstWrite!.future;
    saved = value;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _showForm(
    WidgetTester tester, _PageDrafts drafts, _PageSync sync) async {
  await tester.pumpWidget(MaterialApp(
      home: VesselInspectionScreen(
          equipment: Equipment(
              id: 'nav-vessel',
              name: 'Проверка сохранения',
              typeCode: 'VESSEL'),
          reportFormId: 'to-1',
          syncService: sync,
          autoSaveService: drafts)));
  await _settle(tester);
}

Future<void> _goPage(WidgetTester tester, int page) async {
  tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(page);
  await _settle(tester);
  expect(tester.widget<PageView>(find.byType(PageView)).controller!.page,
      page.toDouble());
}

Future<void> _typeField(WidgetTester tester, String name, String value) async {
  final page =
      tester.widget<PageView>(find.byType(PageView)).controller!.page!.round();
  final pageWidget = find.byKey(PageStorageKey('insp_p$page'));
  final matching = find.descendant(
      of: pageWidget,
      matching: find.byWidgetPredicate(
          (widget) => widget is FormBuilderTextField && widget.name == name));
  await tester.scrollUntilVisible(matching, 250,
      scrollable: find
          .descendant(of: pageWidget, matching: find.byType(Scrollable))
          .first,
      maxScrolls: 80);
  final field = matching.last;
  expect(field, findsOneWidget,
      reason: 'Поле $name должно быть доступно на странице');
  await tester.ensureVisible(field);
  await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextField)), value);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  Future<T> offline<T>(Future<T> Function() body) => http.runWithClient(
      body,
      () => MockClient((request) async => http.Response(
          jsonEncode(
              {'items': [], 'organizations': [], 'engineers': [], 'opos': []}),
          200)));

  testWidgets(
      'entered text survives all section changes and reopening without pressing Save',
      (tester) async {
    final drafts = _PageDrafts();
    final sync = _PageSync();
    await offline(() async {
      await _showForm(tester, drafts, sync);
      await _typeField(tester, 'contract_number', 'ДГ-123/2026');
      await _typeField(tester, 'contract_date', '18.11.2026');
      await _goPage(tester, 1);
      expect(drafts.saved?['checklist_data']['contract_number'], 'ДГ-123/2026');
      final document = find.byWidgetPredicate((w) =>
          w is CheckboxListTile &&
          w.title is Text &&
          ((w.title as Text).data ?? '').startsWith('10.'));
      await tester.ensureVisible(document);
      await tester.pumpAndSettle();
      await tester.tap(document);
      await tester.pump();
      await _typeField(tester, 'doc_number_10', 'Паспорт № 934');
      await _goPage(tester, 2);
      final orientation = find
          .descendant(
              of: find.byType(InspectionPassportSection),
              matching: find.byWidgetPredicate(
                  (w) => w is DropdownButtonFormField<String>))
          .first;
      await tester.ensureVisible(orientation);
      await tester.pumpAndSettle();
      await tester.tap(orientation);
      await _settle(tester);
      await tester.tap(find.text('Вертикальный').last);
      await _settle(tester);
      await _goPage(tester, 3);
      await _typeField(
          tester, 'manufacturer', 'Завод с первой страницы паспорта');
      await _goPage(tester, 4);
      expect(drafts.saved?['checklist_data']['manufacturer'],
          'Завод с первой страницы паспорта');
      final radio = find.byWidgetPredicate(
          (w) => w is FormBuilderRadioGroup && w.name == 'matches_drawing');
      await tester.ensureVisible(radio);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: radio, matching: find.text('Да')));
      await tester.pump();
      await _goPage(tester, 5);
      await tester.ensureVisible(find.text('Добавить ЗРА'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить ЗРА'));
      await _settle(tester);
      var dialogFields = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(dialogFields.at(0), '2');
      await tester.enterText(dialogFields.at(1), 'DN50');
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Добавить')));
      await _settle(tester);
      await _goPage(tester, 6);
      await tester.ensureVisible(find.text('Добавить измерение овальности'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить измерение овальности'));
      await _settle(tester);
      dialogFields = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(dialogFields.at(0), '1');
      await tester.enterText(dialogFields.at(1), '2400,2');
      await tester.enterText(dialogFields.at(2), '2399,8');
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Добавить')));
      await _settle(tester);
      await _goPage(tester, 7);
      await _typeField(
          tester, 'conclusion', 'Заключение, введённое на последней странице');
      for (final page in [0, 3]) {
        await _goPage(tester, page);
      }
      expect(
          tester
              .state<FormBuilderState>(find.byType(FormBuilder))
              .fields['manufacturer']!
              .value,
          'Завод с первой страницы паспорта');
      final restored = sync.saved!['data'] as Map;
      expect(restored['documents']['10'], true);
      expect(restored['documents_info']['10']['number'], 'Паспорт № 934');
      expect(restored['orientation'], 'vertical');
      expect(restored['matches_drawing'], true);
      expect(restored['zra_items'][0]['type_size'], 'DN50');
      expect(restored['ovality_measurements'][0]['max_diameter'], 2400.2);
      expect(restored['conclusion'],
          'Заключение, введённое на последней странице');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await _settle(tester);
      await _showForm(tester, drafts, sync);
      await _goPage(tester, 0);
      expect(
          tester
              .state<FormBuilderState>(find.byType(FormBuilder))
              .fields['contract_number']!
              .value,
          'ДГ-123/2026');
      expect(
          tester
              .widget<FormBuilder>(find.byType(FormBuilder))
              .initialValue['manufacturer'],
          'Завод с первой страницы паспорта');
      await _goPage(tester, 2);
      final reopened = tester
          .widget<InspectionPassportSection>(
              find.byType(InspectionPassportSection))
          .checklist
          .toJson();
      expect(reopened['documents_info']['10']['number'], 'Паспорт № 934');
      expect(reopened['orientation'], 'vertical');
      expect(reopened['matches_drawing'], true);
      expect(reopened['zra_items'][0]['type_size'], 'DN50');
      expect(reopened['ovality_measurements'][0]['max_diameter'], 2400.2);
      expect(reopened['conclusion'],
          'Заключение, введённое на последней странице');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await _settle(tester);
    });
  });

  for (final storage in ['draft', 'queue']) {
    testWidgets(
        'rapid page changes preserve newer data while $storage storage is slow',
        (tester) async {
      final drafts = _PageDrafts();
      final sync = _PageSync();
      final gate = Completer<void>();
      if (storage == 'draft') {
        drafts.firstWrite = gate;
      } else {
        sync.firstWrite = gate;
      }
      await offline(() async {
        await _showForm(tester, drafts, sync);
        await _typeField(tester, 'contract_number', 'Первая страница');
        await _goPage(tester, 3);
        expect(drafts.writes, 1);
        await _typeField(
            tester, 'manufacturer', 'Ввод во время предыдущего сохранения');
        await _goPage(tester, 4);
        gate.complete();
        await _settle(tester);
        expect(drafts.saved?['checklist_data']['manufacturer'],
            'Ввод во время предыдущего сохранения');
        expect(sync.saved?['data']['manufacturer'],
            'Ввод во время предыдущего сохранения');
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await _settle(tester);
      });
    });
  }

  testWidgets(
      'a storage failure stops retries and the next page saves the retained values',
      (tester) async {
    final drafts = _PageDrafts()..failFirstWrite = true;
    final sync = _PageSync();
    await offline(() async {
      await _showForm(tester, drafts, sync);
      await _typeField(tester, 'contract_number', 'Не потерять после ошибки');
      await _goPage(tester, 3);
      expect(drafts.writes, 1);
      expect(drafts.saved, isNull);
      await _typeField(tester, 'manufacturer', 'Следующая страница');
      await _goPage(tester, 4);
      expect(drafts.saved?['checklist_data']['contract_number'],
          'Не потерять после ошибки');
      expect(drafts.saved?['checklist_data']['manufacturer'],
          'Следующая страница');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await _settle(tester);
    });
  });
}
