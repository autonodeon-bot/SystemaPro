import 'diagnostic_menu_structure.dart';

/// Коды шаблонов protocol_templates.quick_control_code (сервер).
class QuickControlTemplateCodes {
  QuickControlTemplateCodes._();

  static const emergency = 'qc_emergency';
  static const vik = 'qc_vik';
  static const uzt = 'qc_uzt';
  static const uzk = 'qc_uzk';
  static const pvk = 'qc_pvk';
  static const gi = 'qc_gi';
  static const pi = 'qc_pi';
  static const psGpm = 'qc_ps_gpm';

  static const all = <String>[
    emergency,
    vik,
    uzt,
    uzk,
    pvk,
    gi,
    pi,
    psGpm,
  ];

  static String? forAction(DiagnosticMenuAction action) {
    switch (action) {
      case DiagnosticMenuAction.emergencyInspection:
        return emergency;
      case DiagnosticMenuAction.expressNdtVik:
        return vik;
      case DiagnosticMenuAction.expressNdtUzt:
        return uzt;
      case DiagnosticMenuAction.expressNdtUzk:
        return uzk;
      case DiagnosticMenuAction.expressNdtPvk:
        return pvk;
      case DiagnosticMenuAction.pressureGi:
        return gi;
      case DiagnosticMenuAction.pressurePi:
        return pi;
      case DiagnosticMenuAction.pressurePsGpm:
        return psGpm;
      default:
        return null;
    }
  }
}
