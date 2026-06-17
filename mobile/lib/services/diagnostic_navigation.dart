import 'package:flutter/material.dart';

import '../models/diagnostic_menu_structure.dart';

import '../models/quick_control_template_codes.dart';

import '../screens/quick_control_protocol_loader_screen.dart';

import '../screens/new_protocol_wizard_screen.dart';

import '../screens/protocol_template_selection_screen.dart';

import '../screens/experience_base_catalog_screen.dart';



/// Переходы по пунктам меню диагностики (структура xlsx).

class DiagnosticNavigation {

  DiagnosticNavigation._();



  static void openAction(BuildContext context, DiagnosticMenuAction action) {

    final qcCode = QuickControlTemplateCodes.forAction(action);

    if (qcCode != null) {

      _openQuickControlByCode(context, code: qcCode, title: _titleForAction(action));

      return;

    }



    switch (action) {

      case DiagnosticMenuAction.newProtocolWizard:

        Navigator.of(context).push(

          MaterialPageRoute(builder: (_) => const NewProtocolWizardScreen()),

        );

        break;

      case DiagnosticMenuAction.experienceBase:

        Navigator.of(context).push(

          MaterialPageRoute(builder: (_) => const ExperienceBaseCatalogScreen()),

        );

        break;

      case DiagnosticMenuAction.customTemplate:

        Navigator.of(context).push(

          MaterialPageRoute(

            builder: (_) => const ProtocolTemplateSelectionScreen(),

          ),

        );

        break;

      default:

        break;

    }

  }



  static String _titleForAction(DiagnosticMenuAction action) {

    switch (action) {

      case DiagnosticMenuAction.emergencyInspection:

        return 'Аварийный осмотр';

      case DiagnosticMenuAction.expressNdtVik:

        return 'Экспресс-диагностика · ВИК';

      case DiagnosticMenuAction.expressNdtUzt:

        return 'Экспресс-диагностика · УЗТ';

      case DiagnosticMenuAction.expressNdtUzk:

        return 'Экспресс-диагностика · УЗК';

      case DiagnosticMenuAction.expressNdtPvk:

        return 'Экспресс-диагностика · ПВК';

      case DiagnosticMenuAction.pressureGi:

        return 'Гидравлические испытания (ГИ)';

      case DiagnosticMenuAction.pressurePi:

        return 'Пневматические испытания (ПИ)';

      case DiagnosticMenuAction.pressurePsGpm:

        return 'Испытание ПС и ГПМ';

      default:

        return 'Быстрый контроль';

    }

  }



  static void _openQuickControlByCode(

    BuildContext context, {

    required String code,

    required String title,

  }) {

    Navigator.of(context).push(

      MaterialPageRoute(

        builder: (_) => QuickControlProtocolLoaderScreen(

          quickControlCode: code,

          screenTitle: title,

        ),

      ),

    );

  }



  static void openQuickControlNode(

    BuildContext context,

    DiagnosticQuickControlNode node,

  ) {

    if (node.action != null) {

      openAction(context, node.action!);

      return;

    }

    Navigator.of(context).push(

      MaterialPageRoute(

        builder: (_) => _QuickControlBranchScreen(root: node),

      ),

    );

  }

}



/// Вложенный уровень «Быстрый контроль» (методы НК / виды опрессовки).

class _QuickControlBranchScreen extends StatelessWidget {

  final DiagnosticQuickControlNode root;



  const _QuickControlBranchScreen({required this.root});



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF0f172a),

      appBar: AppBar(

        title: Text(root.title),

        backgroundColor: const Color(0xFF1e293b),

        foregroundColor: Colors.white,

      ),

      body: ListView(

        padding: const EdgeInsets.all(16),

        children: [

          if (root.protocolHint != null)

            Padding(

              padding: const EdgeInsets.only(bottom: 12),

              child: Text(

                root.protocolHint!,

                style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13),

              ),

            ),

          ...root.children.map(

            (child) => Padding(

              padding: const EdgeInsets.only(bottom: 10),

              child: _MenuTile(

                title: child.title,

                subtitle: child.subtitle,

                icon: child.icon,

                onTap: () => DiagnosticNavigation.openQuickControlNode(context, child),

              ),

            ),

          ),

        ],

      ),

    );

  }

}



class _MenuTile extends StatelessWidget {

  final String title;

  final String? subtitle;

  final IconData icon;

  final VoidCallback onTap;



  const _MenuTile({

    required this.title,

    this.subtitle,

    required this.icon,

    required this.onTap,

  });



  @override

  Widget build(BuildContext context) {

    return Material(

      color: const Color(0xFF1e293b),

      borderRadius: BorderRadius.circular(12),

      child: InkWell(

        onTap: onTap,

        borderRadius: BorderRadius.circular(12),

        child: Padding(

          padding: const EdgeInsets.all(14),

          child: Row(

            children: [

              Icon(icon, color: Colors.white70, size: 26),

              const SizedBox(width: 12),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Text(

                      title,

                      style: const TextStyle(

                        color: Colors.white,

                        fontWeight: FontWeight.w600,

                        fontSize: 15,

                      ),

                    ),

                    if (subtitle != null) ...[

                      const SizedBox(height: 4),

                      Text(

                        subtitle!,

                        style: TextStyle(

                          color: Colors.white.withOpacity(0.6),

                          fontSize: 12,

                        ),

                      ),

                    ],

                  ],

                ),

              ),

              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.35)),

            ],

          ),

        ),

      ),

    );

  }

}


