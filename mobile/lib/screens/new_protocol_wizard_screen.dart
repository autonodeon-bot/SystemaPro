import 'package:flutter/material.dart';

import '../models/diagnostic_menu_config.dart';

import '../models/diagnostic_menu_structure.dart';

import '../models/inspection_matrix.dart';

import '../services/diagnostic_menu_service.dart';

import '../theme/app_colors.dart';

import 'select_equipment_for_act_screen.dart';

import 'new_ndk_protocol_screen.dart';

import 'inspection_tests_hub_screen.dart';

import 'protocol_template_selection_screen.dart';

import 'experience_base_catalog_screen.dart';



/// «Новый протокол»: категории объектов и матрица обследований (xlsx).

class NewProtocolWizardScreen extends StatefulWidget {

  const NewProtocolWizardScreen({super.key});



  @override

  State<NewProtocolWizardScreen> createState() => _NewProtocolWizardScreenState();

}



class _NewProtocolWizardScreenState extends State<NewProtocolWizardScreen> {

  late final Future<DiagnosticMenuConfig> _configFuture =

      DiagnosticMenuService.instance.getConfig();



  void _openDirection(

    BuildContext context,

    DiagnosticObjectCategory cat,

    InspectionMatrixDirection dir,

  ) {

    final flow = '${dir.title} · ${cat.title}';



    switch (dir.id) {

      case 'gi_pi_ae':

        Navigator.of(context).push(

          MaterialPageRoute(

            builder: (_) => InspectionTestsHubScreen(

              category: cat,

              flowTitleSuffix: flow,

            ),

          ),

        );

        break;

      case 'valve_tests':

        Navigator.of(context).push(

          MaterialPageRoute(

            builder: (_) => SelectEquipmentForActScreen(

              presetCategory: cat.equipmentPreset,

              flowTitleSuffix: flow,

              categoryCode: cat.id,

              inspectionDirection: 'hydraulic',

              preferredInspectionType: 'VISUAL',

            ),

          ),

        );

        break;

      case 'external':

      case 'internal':

      case 'technical':

      case 'hydraulic':

      case 'pneumatic':

      case 'ae':

        Navigator.of(context).push(

          MaterialPageRoute(

            builder: (_) => SelectEquipmentForActScreen(

              presetCategory: cat.equipmentPreset,

              flowTitleSuffix: flow,

              categoryCode: cat.id,

              inspectionDirection: dir.id,

              preferredInspectionType: inspectionTypeForDirection(dir.id),

            ),

          ),

        );

        break;

      case 'ndk_express':

        Navigator.of(context).push(

          MaterialPageRoute(

            builder: (_) => NewNdkProtocolScreen(wizardSubtitle: flow),

          ),

        );

        break;

      case 'custom_template':

        Navigator.of(context).push(

          MaterialPageRoute(

            builder: (_) => const ProtocolTemplateSelectionScreen(),

          ),

        );

        break;

    }

  }



  void _openArchetype(

    BuildContext context,

    DiagnosticObjectCategory cat,

    DiagnosticEquipmentArchetype archetype,

  ) {

    Navigator.of(context).push(

      MaterialPageRoute(

        builder: (_) => SelectEquipmentForActScreen(

          presetCategory: cat.equipmentPreset,

          flowTitleSuffix: archetype.displayLabel.replaceAll('\n', ' · '),

          categoryCode: cat.id,

          archetypeKind: archetype.kind,

          archetypeMark: archetype.exampleMark,

          inspectionDirection: 'external',

          preferredInspectionType: 'VISUAL',

        ),

      ),

    );

  }



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF0f172a),

      appBar: AppBar(

        title: const Text('Новый протокол'),

        backgroundColor: const Color(0xFF1e293b),

        foregroundColor: Colors.white,

        actions: [

          IconButton(

            icon: const Icon(Icons.menu_book_outlined),

            tooltip: 'Опытная база',

            onPressed: () => Navigator.of(context).push(

              MaterialPageRoute(

                builder: (_) => const ExperienceBaseCatalogScreen(),

              ),

            ),

          ),

        ],

      ),

      body: FutureBuilder<DiagnosticMenuConfig>(

        future: _configFuture,

        builder: (context, snap) {

          if (snap.connectionState == ConnectionState.waiting) {

            return const Center(

              child: CircularProgressIndicator(color: AppColors.accent),

            );

          }

          final config = snap.data ?? DiagnosticMenuConfig.builtin();

          return ListView(

            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),

            children: [

              Text(

                config.newProtocolDescription,

                style: TextStyle(

                  color: Colors.white.withValues(alpha: 0.7),

                  fontSize: 13,

                  height: 1.35,

                ),

              ),

              const SizedBox(height: 12),

              ...config.objectCategories.map(

                (cat) => Theme(

                  data: Theme.of(context).copyWith(

                    dividerColor: Colors.white12,

                    splashColor: AppColors.darkPrimary.withValues(alpha: 0.2),

                  ),

                  child: ExpansionTile(

                    key: PageStorageKey('npw_${cat.id}'),

                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),

                    collapsedIconColor: Colors.white54,

                    iconColor: AppColors.darkPrimary,

                    title: Row(

                      children: [

                        Icon(cat.icon, color: AppColors.darkPrimary, size: 22),

                        const SizedBox(width: 10),

                        Expanded(

                          child: Text(

                            cat.title,

                            style: const TextStyle(

                              color: Colors.white,

                              fontWeight: FontWeight.w600,

                              fontSize: 15,

                            ),

                          ),

                        ),

                      ],

                    ),

                    subtitle: cat.inspectionTypeLabels.isEmpty

                        ? null

                        : Padding(

                            padding: const EdgeInsets.only(left: 32, top: 4),

                            child: Text(

                              cat.inspectionTypeLabels.join(' · '),

                              style: TextStyle(

                                color: Colors.white.withValues(alpha: 0.5),

                                fontSize: 11,

                              ),

                            ),

                          ),

                    children: [

                      if (cat.archetypes.isNotEmpty)

                        Padding(

                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),

                          child: Align(

                            alignment: Alignment.centerLeft,

                            child: Text(

                              'Опытная база (примеры марок)',

                              style: TextStyle(

                                color: Colors.white.withValues(alpha: 0.45),

                                fontSize: 11,

                              ),

                            ),

                          ),

                        ),

                      ...cat.archetypes.map(

                        (a) => ListTile(

                          dense: true,

                          contentPadding: const EdgeInsets.only(left: 44, right: 8),

                          title: Text(

                            a.kind,

                            style: const TextStyle(color: Colors.white70, fontSize: 13),

                          ),

                          subtitle: a.exampleMark.isEmpty

                              ? null

                              : Text(

                                  a.exampleMark,

                                  style: const TextStyle(

                                    color: Colors.white38,

                                    fontSize: 12,

                                  ),

                                ),

                          trailing: const Icon(Icons.link, color: Colors.white24, size: 18),

                          onTap: () => _openArchetype(context, cat, a),

                        ),

                      ),

                      const Divider(height: 1, color: Colors.white12),

                      ...directionsFromLabels(cat.inspectionTypeLabels).map(

                        (d) => ListTile(

                          contentPadding: const EdgeInsets.only(left: 44, right: 8),

                          leading: Icon(d.icon, color: Colors.white54, size: 20),

                          title: Text(

                            d.title,

                            style: const TextStyle(color: Colors.white, fontSize: 14),

                          ),

                          trailing: const Icon(

                            Icons.chevron_right,

                            color: Colors.white24,

                            size: 20,

                          ),

                          onTap: () => _openDirection(context, cat, d),

                        ),

                      ),

                      ListTile(

                        contentPadding: const EdgeInsets.only(left: 44, right: 8),

                        leading: const Icon(Icons.speed_outlined, color: Colors.white54, size: 20),

                        title: const Text(

                          'Протокол НК (без акта)',

                          style: TextStyle(color: Colors.white70, fontSize: 13),

                        ),

                        trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 20),

                        onTap: () => _openDirection(

                          context,

                          cat,

                          const InspectionMatrixDirection(

                            id: 'ndk_express',

                            title: 'Протокол НК',

                            icon: Icons.speed_outlined,

                          ),

                        ),

                      ),

                    ],

                  ),

                ),

              ),

            ],

          );

        },

      ),

    );

  }

}


