import 'package:flutter/material.dart';
import '../models/diagnostic_menu_config.dart';
import '../models/diagnostic_menu_structure.dart';
import '../services/diagnostic_menu_service.dart';
import '../services/diagnostic_navigation.dart';
import '../services/quick_control_template_service.dart';
import '../theme/app_colors.dart';

/// Вход в «Быстрый контроль» — дерево по структуре xlsx.
class QuickControlHubScreen extends StatefulWidget {
  const QuickControlHubScreen({super.key});

  @override
  State<QuickControlHubScreen> createState() => _QuickControlHubScreenState();
}

class _QuickControlHubScreenState extends State<QuickControlHubScreen> {
  late Future<DiagnosticMenuConfig> _configFuture =
      DiagnosticMenuService.instance.getConfig();

  @override
  void initState() {
    super.initState();
    QuickControlTemplateService().prefetchAll();
    DiagnosticMenuService.instance.prefetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Быстрый контроль'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<DiagnosticMenuConfig>(
        future: _configFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final tree = snap.data?.quickControlTree ??
              DiagnosticMenuConfig.builtin().quickControlTree;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Выберите режим',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ...tree.map(
                (node) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ModeCard(
                    node: node,
                    onTap: () =>
                        DiagnosticNavigation.openQuickControlNode(context, node),
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

class _ModeCard extends StatelessWidget {
  final DiagnosticQuickControlNode node;
  final VoidCallback onTap;

  const _ModeCard({required this.node, required this.onTap});

  Color get _color {
    switch (node.id) {
      case 'emergency':
        return AppColors.danger;
      case 'express_ndt':
        return AppColors.darkPrimary;
      case 'pressure':
        return AppColors.accent;
      default:
        return AppColors.darkPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1e293b),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(node.icon, color: _color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (node.subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        node.subtitle!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (node.children.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: node.children
                            .map(
                              (c) => Chip(
                                label: Text(c.title, style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: _color.withOpacity(0.12),
                                labelStyle: TextStyle(color: _color.withOpacity(0.9)),
                                side: BorderSide.none,
                              ),
                            )
                            .toList(),
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
