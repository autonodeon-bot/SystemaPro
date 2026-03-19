import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/equipment.dart';

void main() {
  group('Equipment', () {
    group('fromJson', () {
      test('парсинг полного JSON', () {
        final json = {
          'id': '550e8400-e29b-41d4-a716-446655440000',
          'name': 'Сосуд В-101',
          'type_id': 'type-uuid-123',
          'type_name': 'Сосуд',
          'type_code': 'VESSEL',
          'serial_number': 'SN-001',
          'location': 'Цех №1',
          'attributes': {'pressure': 10.5, 'volume': 100},
          'commissioning_date': '2020-01-15',
          'workshop_id': 'ws-uuid',
          'workshop_name': 'Цех переработки',
          'workshop_code': 'WS-01',
          'branch_id': 'br-uuid',
          'branch_name': 'Филиал Север',
          'branch_code': 'BR-N',
          'enterprise_id': 'ent-uuid',
          'enterprise_name': 'НефтеГаз',
          'enterprise_code': 'NG-01',
          'opo_id': 'opo-uuid',
          'opo_name': 'ОПО №1',
          'opo_code': 'OPO-001',
        };

        final equipment = Equipment.fromJson(json);

        expect(equipment.id, '550e8400-e29b-41d4-a716-446655440000');
        expect(equipment.name, 'Сосуд В-101');
        expect(equipment.typeId, 'type-uuid-123');
        expect(equipment.typeName, 'Сосуд');
        expect(equipment.typeCode, 'VESSEL');
        expect(equipment.serialNumber, 'SN-001');
        expect(equipment.location, 'Цех №1');
        expect(equipment.attributes, isA<Map<String, dynamic>>());
        expect(equipment.attributes!['pressure'], 10.5);
        expect(equipment.commissioningDate, '2020-01-15');
        expect(equipment.workshopName, 'Цех переработки');
        expect(equipment.branchName, 'Филиал Север');
        expect(equipment.enterpriseName, 'НефтеГаз');
        expect(equipment.opoName, 'ОПО №1');
      });

      test('парсинг минимального JSON', () {
        final json = {'id': 'abc-123', 'name': 'Труба'};
        final equipment = Equipment.fromJson(json);

        expect(equipment.id, 'abc-123');
        expect(equipment.name, 'Труба');
        expect(equipment.typeId, isNull);
        expect(equipment.serialNumber, isNull);
        expect(equipment.attributes, isNull);
        expect(equipment.workshopId, isNull);
      });

      test('парсинг с null полями', () {
        final json = {
          'id': '1',
          'name': 'Test',
          'type_id': null,
          'serial_number': null,
          'attributes': null,
        };
        final equipment = Equipment.fromJson(json);
        expect(equipment.typeId, isNull);
        expect(equipment.serialNumber, isNull);
        expect(equipment.attributes, isNull);
      });

      test('парсинг type_id как int', () {
        final json = {'id': '1', 'name': 'Test', 'type_id': 42};
        final equipment = Equipment.fromJson(json);
        expect(equipment.typeId, '42');
      });

      test('парсинг type_id как String', () {
        final json = {'id': '1', 'name': 'Test', 'type_id': 'uuid-str'};
        final equipment = Equipment.fromJson(json);
        expect(equipment.typeId, 'uuid-str');
      });

      test('парсинг с пустым id возвращает пустую строку', () {
        final json = {'name': 'NoId'};
        final equipment = Equipment.fromJson(json);
        expect(equipment.id, '');
      });

      test('парсинг с пустым name возвращает пустую строку', () {
        final json = {'id': '1'};
        final equipment = Equipment.fromJson(json);
        expect(equipment.name, '');
      });
    });

    group('toJson', () {
      test('сериализация полного объекта', () {
        final equipment = Equipment(
          id: 'eq-1',
          name: 'Ресивер Р-1',
          typeId: 'type-1',
          typeName: 'Ресивер',
          typeCode: 'RECEIVER',
          serialNumber: 'SN-100',
          location: 'Площадка А',
          attributes: {'material': 'Сталь 09Г2С'},
          commissioningDate: '2019-06-01',
          workshopId: 'ws-1',
          workshopName: 'Цех 1',
          workshopCode: 'C1',
          branchId: 'br-1',
          branchName: 'Филиал 1',
          branchCode: 'F1',
          enterpriseId: 'ent-1',
          enterpriseName: 'Предприятие',
          enterpriseCode: 'P1',
          opoId: 'opo-1',
          opoName: 'ОПО',
          opoCode: 'O1',
        );

        final json = equipment.toJson();

        expect(json['id'], 'eq-1');
        expect(json['name'], 'Ресивер Р-1');
        expect(json['type_id'], 'type-1');
        expect(json['type_name'], 'Ресивер');
        expect(json['serial_number'], 'SN-100');
        expect(json['location'], 'Площадка А');
        expect(json['attributes'], isA<Map>());
        expect(json['workshop_id'], 'ws-1');
        expect(json['enterprise_id'], 'ent-1');
        expect(json['opo_id'], 'opo-1');
      });

      test('null-поля сериализуются как null', () {
        final equipment = Equipment(id: 'eq-2', name: 'Минимальный');
        final json = equipment.toJson();

        expect(json['type_id'], isNull);
        expect(json['serial_number'], isNull);
        expect(json['attributes'], isNull);
        expect(json['workshop_id'], isNull);
      });
    });

    group('fromJson → toJson roundtrip', () {
      test('roundtrip сохраняет данные', () {
        final original = {
          'id': 'rt-1',
          'name': 'Roundtrip Test',
          'type_id': 'type-rt',
          'type_name': 'Тип',
          'type_code': 'TYPE',
          'serial_number': 'SN-RT',
          'location': 'Loc',
          'attributes': {'key': 'value'},
          'commissioning_date': '2023-01-01',
          'workshop_id': 'ws-rt',
          'workshop_name': 'WS',
          'workshop_code': 'WC',
          'branch_id': 'br-rt',
          'branch_name': 'BR',
          'branch_code': 'BC',
          'enterprise_id': 'ent-rt',
          'enterprise_name': 'ENT',
          'enterprise_code': 'EC',
          'opo_id': 'opo-rt',
          'opo_name': 'OPO',
          'opo_code': 'OC',
        };

        final equipment = Equipment.fromJson(original);
        final json = equipment.toJson();

        expect(json['id'], original['id']);
        expect(json['name'], original['name']);
        expect(json['type_id'], original['type_id']);
        expect(json['serial_number'], original['serial_number']);
        expect(json['enterprise_id'], original['enterprise_id']);
        expect(json['opo_code'], original['opo_code']);
      });
    });
  });
}
