import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/services/vessel_pressure_calculation.dart';

VesselPressureInput input(
        {String element = 'cylinder',
        String group = 'manual',
        String material = '09Г2С',
        double p = 1.6,
        double d = 1000,
        double nominal = 12,
        double temperature = 20,
        double phi = 1,
        double c1 = 1,
        double c2 = 0,
        double c3 = 0,
        double? h,
        double? flange = 0,
        double? yield20,
        String load = 'internal_pressure',
        double sigma = 150}) =>
    VesselPressureInput(
        element: element,
        materialGroup: group,
        material: material,
        stressBasis: 'Проверенные данные при расчётной температуре',
        pressure: p,
        diameter: d,
        nominal: nominal,
        temperature: temperature,
        weldFactor: phi,
        corrosionAllowance: c1,
        toleranceAllowance: c2,
        technologyAllowance: c3,
        headHeight: h,
        flangeLength: flange,
        manualStress: sigma,
        yieldAt20: yield20,
        loadCase: load);

void main() {
  test('cylinder: independent example p=1.6 D=1000 sigma=150 phi=1 c=1', () {
    final r = VesselPressureCalculation.calculate(input());
    expect(r.calculatedThickness, closeTo(5.3619302949, 1e-9));
    expect(r.minimumThickness, 6.37);
    expect(r.nominalSufficient, true);
  });
  test('elliptical 2:1 head uses radius D and the half-pressure denominator',
      () {
    final r = VesselPressureCalculation.calculate(
        input(element: 'elliptical', h: 250));
    expect(r.calculatedThickness, closeTo(5.3475935829, 1e-9));
    expect(r.minimumThickness, 6.35);
  });
  test('hemispherical head uses radius D/2', () {
    final r =
        VesselPressureCalculation.calculate(input(element: 'hemispherical'));
    expect(r.calculatedThickness, closeTo(2.6737967914, 1e-9));
    expect(r.minimumThickness, 3.68);
  });
  test(
      'long head flange cannot be thinner than the corresponding shell (6.3.1.4)',
      () {
    final r = VesselPressureCalculation.calculate(
        input(element: 'hemispherical', flange: 200));
    expect(r.flangeControls, true);
    expect(r.minimumThickness, 6.37);
  });
  test('elliptic minimum stays inside the lower applicability ratio', () {
    final r = VesselPressureCalculation.calculate(
        input(element: 'elliptical', h: 250, p: 0.1));
    expect(r.minimumThickness, 3);
  });
  test(
      'table A.1 uses material group, temperature and conservative interpolation',
      () {
    expect(VesselPressureCalculation.stress(input(group: '09g2s_le32')), 196);
    expect(
        VesselPressureCalculation.stress(
            input(group: '09g2s_le32', temperature: 125)),
        174);
    expect(VesselPressureCalculation.stress(input(group: '09g2s_gt32')), 183);
    expect(VesselPressureCalculation.stress(input(group: '09g2s_forging245')),
        closeTo(164.7, 1e-9));
    expect(
        VesselPressureCalculation.stress(input(
            group: 'steel20', material: '20', yield20: 220, temperature: 175)),
        137.5);
    expect(
        VesselPressureCalculation.stress(
            input(group: 'steel20', material: '20', yield20: 110)),
        73.5);
  });
  test('nominal below the calculated threshold is not presented as sufficient',
      () {
    expect(
        VesselPressureCalculation.calculate(input(nominal: 6))
            .nominalSufficient,
        false);
  });
  test('all three allowances are included without guessing missing values', () {
    final r =
        VesselPressureCalculation.calculate(input(c1: 1, c2: 0.4, c3: 0.2));
    expect(r.allowances, closeTo(1.6, 1e-9));
    expect(r.minimumThickness, 6.97);
  });
  test(
      'unsupported load cases, invalid geometry and mismatched material are rejected',
      () {
    for (final p in [
      input(load: 'external_pressure'),
      input(load: 'combined'),
      input(d: 100),
      input(element: 'flat'),
      input(element: 'elliptical', h: 100),
      input(element: 'elliptical', h: 500),
      input(phi: 1.2),
      input(c2: -1),
      input(p: 300),
      input(group: '09g2s_le32', material: '20'),
      input(group: '09g2s_le32', temperature: 400),
      input(group: 'steel20', material: '20')
    ]) {
      expect(
          () => VesselPressureCalculation.calculate(p), throwsFormatException);
    }
  });
  test('stored inputs can be recalculated exactly after reopening', () {
    final p = input(element: 'elliptical', h: 250, flange: 100);
    final restored = VesselPressureInput.fromJson(p.toJson());
    expect(VesselPressureCalculation.calculate(restored).toJson(),
        VesselPressureCalculation.calculate(p).toJson());
  });
}
