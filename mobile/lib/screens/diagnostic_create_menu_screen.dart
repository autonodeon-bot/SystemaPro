import 'package:flutter/material.dart';
import '../models/diagnostic_menu_config.dart';
import '../models/diagnostic_menu_structure.dart';
import '../services/diagnostic_menu_service.dart';
import '../services/diagnostic_navigation.dart';
import '../theme/app_colors.dart';
import 'new_protocol_wizard_screen.dart';
import 'experience_base_catalog_screen.dart';
import 'protocol_template_selection_screen.dart';

/// Меню «Протокол → создать» (структура с сервера или встроенная).
class DiagnosticCreateMenuScreen extends StatefulWidget {
  const DiagnosticCreateMenuScreen({super.key});

  @override
  State<DiagnosticCreateMenuScreen> createState() =>
      _DiagnosticCreateMenuScreenState();
}

class _DiagnosticCreateMenuScreenState extends State<DiagnosticCreateMenuScreen> {
  Future<DiagnosticMenuConfig> _configFuture =
      DiagnosticMenuService.instance.getConfig();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Создать протокол / акт'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить меню с сервера',
            onPressed: () {
              setState(() {
                _configFuture = DiagnosticMenuService.instance.getConfig(
                  forceRefresh: true,
                );
              });
            },
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _sectionTitle('Быстрый контроль'),
              const SizedBox(height: 8),
              ...config.quickControlTree.map(
                (node) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _QuickCard(
                    node: node,
                    onTap: () =>
                        DiagnosticNavigation.openQuickControlNode(context, node),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Новый протокол'),
              const SizedBox(height: 6),
              Text(
                config.newProtocolDescription,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              ...config.createMenuActions.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ActionCard(
                    icon: a.icon,
                    color: a.color,
                    title: a.title,
                    subtitle: a.subtitle,
                    onTap: () => _openCreateAction(context, a),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Свой шаблон'),
              const SizedBox(height: 8),
              _ActionCard(
                icon: Icons.layers_outlined,
                color: Colors.tealAccent,
                title: 'Конструктор протокола',
                subtitle: 'Протокол из пользовательского шаблона',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProtocolTemplateSelectionScreen(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openCreateAction(BuildContext context, DiagnosticCreateMenuAction a) {
    switch (a.action) {
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
        DiagnosticNavigation.openAction(context, a.action);
    }
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final DiagnosticQuickControlNode node;
  final VoidCallback onTap;

  const _QuickCard({required this.node, required this.onTap});

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(node.icon, color: AppColors.darkPrimary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (node.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        node.subtitle!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (node.protocolHint != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        node.protocolHint!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
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
                                label: Text(
                                  c.title,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    AppColors.darkPrimary.withOpacity(0.15),
                                labelStyle:
                                    const TextStyle(color: Colors.white70),
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

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 26),
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
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white30, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
