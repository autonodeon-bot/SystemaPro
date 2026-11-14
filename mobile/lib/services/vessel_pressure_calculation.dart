import 'dart:math' as math;

/// Internal pressure only. Source: GOST 34233.2-2017 5.2.1, 5.3.1, 6.2.1,
/// 6.3.1.1-6.3.1.5. Other load cases and opening reinforcement are separate checks.
class VesselPressureInput {
  final String element, materialGroup, material, stressBasis, loadCase;
  final double pressure, diameter, nominal, temperature, weldFactor;
  final double corrosionAllowance, toleranceAllowance, technologyAllowance;
  final double? headHeight, flangeLength, manualStress, yieldAt20;
  const VesselPressureInput(
      {required this.element,
      required this.materialGroup,
      required this.material,
      required this.stressBasis,
      required this.pressure,
      required this.diameter,
      required this.nominal,
      required this.temperature,
      required this.weldFactor,
      required this.corrosionAllowance,
      required this.toleranceAllowance,
      required this.technologyAllowance,
      this.headHeight,
      this.flangeLength,
      this.manualStress,
      this.yieldAt20,
      this.loadCase = 'internal_pressure'});
  factory VesselPressureInput.fromJson(Map<String, dynamic> j) {
    double n(String key) => (j[key] as num).toDouble();
    double? optional(String key) => (j[key] as num?)?.toDouble();
    return VesselPressureInput(
        element: j['element'],
        materialGroup: j['material_group'],
        material: j['material'],
        stressBasis: j['stress_basis'] ?? '',
        loadCase: j['load_case'] ?? 'internal_pressure',
        pressure: n('pressure_mpa'),
        diameter: n('diameter_mm'),
        nominal: n('nominal_mm'),
        temperature: n('temperature_c'),
        weldFactor: n('weld_factor'),
        corrosionAllowance: n('c1_mm'),
        toleranceAllowance: n('c2_mm'),
        technologyAllowance: n('c3_mm'),
        headHeight: optional('head_height_mm'),
        flangeLength: optional('flange_length_mm'),
        manualStress: optional('manual_stress_mpa'),
        yieldAt20: optional('yield_at_20_mpa'));
  }
  Map<String, dynamic> toJson() => {
        'element': element,
        'material_group': materialGroup,
        'material': material,
        'stress_basis': stressBasis,
        'load_case': loadCase,
        'pressure_mpa': pressure,
        'diameter_mm': diameter,
        'nominal_mm': nominal,
        'temperature_c': temperature,
        'weld_factor': weldFactor,
        'c1_mm': corrosionAllowance,
        'c2_mm': toleranceAllowance,
        'c3_mm': technologyAllowance,
        'head_height_mm': headHeight,
        'flange_length_mm': flangeLength,
        'manual_stress_mpa': manualStress,
        'yield_at_20_mpa': yieldAt20
      };
}

class VesselPressureResult {
  final double allowableStress,
      calculatedThickness,
      minimumThickness,
      allowances;
  final bool flangeControls, nominalSufficient;
  final String clause, formula;
  const VesselPressureResult(
      {required this.allowableStress,
      required this.calculatedThickness,
      required this.minimumThickness,
      required this.allowances,
      required this.flangeControls,
      required this.nominalSufficient,
      required this.clause,
      required this.formula});
  Map<String, dynamic> toJson() => {
        'standard': 'ГОСТ 34233.2-2017',
        'clause': clause,
        'formula': formula,
        'allowable_stress_mpa': allowableStress,
        'calculated_thickness_mm': calculatedThickness,
        'minimum_thickness_mm': minimumThickness,
        'allowances_mm': allowances,
        'flange_controls': flangeControls,
        'nominal_sufficient': nominalSufficient,
        'scope': 'internal_pressure_only'
      };
}

class VesselPressureCalculation {
  static const materialGroups = <String, String>{
    '09g2s_le32': '09Г2С / 16ГС: лист до 32 мм, обычный класс',
    '09g2s_gt32': '09Г2С / 16ГС: св. 32 мм; трубы; классы 265/295',
    '09g2s_forging245': '09Г2С: поковка категории 245',
    'steel20': '20 / 20К: лист до 160 мм',
    'st3_le20': 'Ст3: лист до 20 мм',
    'st3_gt20': 'Ст3: лист св. 20 мм',
    'manual': 'Другой материал: [σ] из нормативного расчёта',
  };
  // GOST 34233.1-2017, table A.1 (official edition 2019, p.13).
  // Restricted to 20..350 C: no creep-resource column selection or extrapolation.
  static const _temperatures = [20.0, 100.0, 150.0, 200.0, 250.0, 300.0, 350.0];
  static const _stress = <String, List<double>>{
    '09g2s_le32': [196, 177, 171, 165, 162, 151, 140],
    '09g2s_gt32': [183, 160, 154, 148, 145, 134, 123],
    '09g2s_forging245': [183, 160, 154, 148, 145, 134, 123],
    'steel20': [147, 142, 139, 136, 132, 119, 106],
    'st3_le20': [154, 149, 145, 142, 131, 115, 105],
    'st3_gt20': [140, 134, 131, 126, 120, 108, 98],
  };
  static double stress(VesselPressureInput p) {
    if (p.material.trim().isEmpty)
      throw const FormatException('Укажите марку материала по паспорту');
    if (!p.temperature.isFinite)
      throw const FormatException('Укажите расчётную температуру');
    if (p.materialGroup == 'manual') {
      if (p.manualStress == null ||
          !p.manualStress!.isFinite ||
          p.manualStress! <= 0 ||
          p.stressBasis.trim().isEmpty) {
        throw const FormatException(
            'Укажите допускаемое [σ] при расчётной температуре и источник значения');
      }
      return p.manualStress!;
    }
    final values = _stress[p.materialGroup];
    if (values == null)
      throw const FormatException('Выберите табличную группу материала');
    final grade = p.material
        .toUpperCase()
        .replaceAll('СТАЛЬ', '')
        .trim()
        .replaceAll('G', 'Г')
        .replaceAll('S', 'С')
        .replaceAll('T', 'Т')
        .replaceAll('K', 'К');
    final matches = p.materialGroup.startsWith('09g2s')
        ? (grade.startsWith('09Г2С') ||
            (p.materialGroup != '09g2s_forging245' && grade.startsWith('16ГС')))
        : (p.materialGroup == 'steel20'
            ? (grade == '20' || grade == '20К')
            : grade.startsWith('СТ3'));
    if (!matches)
      throw const FormatException(
          'Марка материала не соответствует выбранной табличной группе');
    if (p.temperature < 20 || p.temperature > 350)
      throw const FormatException(
          'Автоматическая таблица доступна для 20–350 °C. Для другой температуры укажите нормативное [σ] вручную');
    if ((p.materialGroup == '09g2s_le32' && p.nominal > 32) ||
        (p.materialGroup == 'steel20' && p.nominal > 160) ||
        (p.materialGroup == 'st3_le20' && p.nominal > 20) ||
        (p.materialGroup == 'st3_gt20' && p.nominal <= 20)) {
      throw const FormatException(
          'Табличная группа не соответствует номинальной толщине элемента');
    }
    var result = values.last;
    for (var i = 1; i < _temperatures.length; i++) {
      if (p.temperature <= _temperatures[i]) {
        final k = (p.temperature - _temperatures[i - 1]) /
            (_temperatures[i] - _temperatures[i - 1]);
        result = values[i - 1] + (values[i] - values[i - 1]) * k;
        break;
      }
    }
    result = (result * 2 + 1e-10).floor() / 2; // A.1 note 2.
    if (p.materialGroup == '09g2s_forging245') result *= 0.9; // A.1 note 6.
    if (p.materialGroup == 'steel20') {
      if (p.yieldAt20 == null || !p.yieldAt20!.isFinite || p.yieldAt20! <= 0)
        throw const FormatException(
            'Для стали 20/20К укажите паспортный предел текучести при 20 °C');
      result *= math.min(
          1.0, p.yieldAt20! / 220); // A.1 note 3, conservative for 20K.
    }
    return result;
  }

  static VesselPressureResult calculate(VesselPressureInput p) {
    if (p.loadCase != 'internal_pressure')
      throw const FormatException(
          'Этот модуль считает только внутреннее избыточное давление. Для вакуума и совместных нагрузок нужен другой расчёт');
    for (final value in [p.pressure, p.diameter, p.nominal, p.weldFactor]) {
      if (!value.isFinite || value <= 0)
        throw const FormatException(
            'Давление, диаметр, номинальная толщина и φ должны быть положительными');
    }
    if (p.weldFactor > 1)
      throw const FormatException(
          'Коэффициент прочности шва φ не может превышать 1');
    for (final c in [
      p.corrosionAllowance,
      p.toleranceAllowance,
      p.technologyAllowance
    ]) {
      if (!c.isFinite || c < 0)
        throw const FormatException(
            'Прибавки c1, c2, c3 должны быть заданы и неотрицательны');
    }
    final c =
        p.corrosionAllowance + p.toleranceAllowance + p.technologyAllowance;
    if (c >= p.nominal)
      throw const FormatException(
          'Сумма прибавок должна быть меньше номинальной толщины');
    final sigma = stress(p), ratio = (p.nominal - c) / p.diameter;
    double sp, needed;
    var flangeControls = false;
    String clause, formula;
    if (p.element == 'cylinder') {
      if (p.diameter < 200 || ratio > 0.1 + 1e-12)
        throw const FormatException(
            'Область п.5.2.1: обечайка D ≥ 200 мм и (s−c)/D ≤ 0,1');
      final denominator = 2 * sigma * p.weldFactor - p.pressure;
      if (denominator <= 0)
        throw const FormatException('Некорректное сочетание давления, [σ] и φ');
      sp = p.pressure * p.diameter / denominator;
      needed = sp + c;
      clause = '5.3.1.1, формулы (1), (2)';
      formula = 'sp = pD / (2[σ]φ − p); smin = sp + c1 + c2 + c3';
    } else if (p.element == 'elliptical' || p.element == 'hemispherical') {
      final h = p.element == 'hemispherical' ? p.diameter / 2 : p.headHeight;
      if (h == null ||
          !h.isFinite ||
          h <= 0 ||
          p.flangeLength == null ||
          !p.flangeLength!.isFinite ||
          p.flangeLength! < 0)
        throw const FormatException(
            'Укажите высоту выпуклой части H и длину цилиндрической отбортовки h1 (0 при отсутствии)');
      if (p.element == 'elliptical' &&
          (h / p.diameter < 0.2 ||
              h / p.diameter >= 0.5 ||
              ratio < 0.002 - 1e-12 ||
              ratio > 0.1 + 1e-12)) {
        throw const FormatException(
            'Область п.6.2.1: 0,2 ≤ H/D < 0,5 и 0,002 ≤ (s−c)/D ≤ 0,1');
      }
      if (ratio > 0.1 + 1e-12)
        throw const FormatException(
            'Расчёт ограничен тонкостенными днищами (s−c)/D ≤ 0,1');
      final denominator = 2 * sigma * p.weldFactor - 0.5 * p.pressure;
      if (denominator <= 0)
        throw const FormatException('Некорректное сочетание давления, [σ] и φ');
      final r = p.diameter * p.diameter / (4 * h);
      sp = p.pressure * r / denominator;
      // Keep the selected minimum within the elliptic-head applicability domain.
      needed =
          math.max(sp, p.element == 'elliptical' ? 0.002 * p.diameter : 0.0) +
              c;
      final flangeLimit = (p.element == 'elliptical' ? 0.8 : 0.3) *
          math.sqrt(p.diameter * (needed - c));
      if (p.flangeLength! > flangeLimit) {
        final shellDenominator = 2 * sigma - p.pressure;
        if (shellDenominator <= 0)
          throw const FormatException(
              'Расчёт отбортовки неприменим при заданном давлении');
        final shell = p.pressure * p.diameter / shellDenominator + c;
        flangeControls = shell > needed;
        needed = math.max(needed, shell);
      }
      clause = '6.3.1.1–6.3.1.4, формулы (42), (43), (45)';
      formula =
          'R = D²/(4H); sp = pR/(2[σ]φ − 0,5p); smin = sp + c; проверка отбортовки';
    } else {
      throw const FormatException(
          'Плоские, конические, торосферические днища и штуцеры требуют отдельного расчёта');
    }
    if (!needed.isFinite || !sp.isFinite)
      throw const FormatException('Не удалось вычислить конечный результат');
    if ((needed - c) / p.diameter > 0.1 + 1e-12)
      throw const FormatException(
          'Требуемая толщина вне области тонкостенного расчёта; нужен другой расчётный метод');
    final rounded = (needed * 100 - 1e-10).ceil() / 100;
    return VesselPressureResult(
        allowableStress: sigma,
        calculatedThickness: sp,
        minimumThickness: rounded,
        allowances: c,
        flangeControls: flangeControls,
        nominalSufficient: p.nominal >= rounded,
        clause: clause,
        formula: formula);
  }
}
