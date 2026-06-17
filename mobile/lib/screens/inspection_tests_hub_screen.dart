import 'package:flutter/material.dart';
import '../models/diagnostic_menu_structure.dart';
import '../theme/app_colors.dart';
import 'select_equipment_for_act_screen.dart';

/// Хаб «ГИ (ПИ + АЭ)» — выбор подвида испытаний по xlsx.
class InspectionTestsHubScreen extends StatelessWidget {
  final DiagnosticObjectCategory category;
  final String flowTitleSuffix;

  const InspectionTestsHubScreen({
    super.key,
    required this.category,
    required this.flowTitleSuffix,
  });

  void _openGi(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectEquipmentForActScreen(
          presetCategory: category.equipmentPreset,
          flowTitleSuffix: '$flowTitleSuffix · ГИ',
          categoryCode: category.id,
          inspectionDirection: 'hydraulic',
          preferredInspectionType: 'VISUAL',
        ),
      ),
    );
  }

  void _openPi(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectEquipmentForActScreen(
          presetCategory: category.equipmentPreset,
          flowTitleSuffix: '$flowTitleSuffix · ПИ',
          categoryCode: category.id,
          inspectionDirection: 'pneumatic',
          preferredInspectionType: 'VISUAL',
        ),
      ),
    );
  }

  void _openAe(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectEquipmentForActScreen(
          presetCategory: category.equipmentPreset,
          flowTitleSuffix: '$flowTitleSuffix · АЭ',
          categoryCode: category.id,
          inspectionDirection: 'ae',
          preferredInspectionType: 'NDT',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Испытания'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            flowTitleSuffix,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            'Гидравлические, пневматические испытания и акустико-эмиссионный контроль',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
          ),
          const SizedBox(height: 20),
          _HubTile(
            icon: Icons.water_drop_outlined,
            title: 'Гидравлические испытания (ГИ)',
            subtitle: 'Выбор объекта → опрессовка / шаблон',
            onTap: () => _openGi(context),
          ),
          _HubTile(
            icon: Icons.compress_outlined,
            title: 'Пневматические испытания (ПИ)',
            subtitle: 'Выбор объекта → опрессовка / шаблон',
            onTap: () => _openPi(context),
          ),
          _HubTile(
            icon: Icons.graphic_eq,
            title: 'Акустико-эмиссионный контроль (АЭ)',
            subtitle: 'Выбор объекта → протокол АЭ',
            onTap: () => _openAe(context),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1e293b),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppColors.darkPrimary),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
        onTap: onTap,
      ),
    );
  }
}
