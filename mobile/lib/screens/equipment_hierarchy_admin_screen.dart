import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Управление иерархией: предприятие → филиал → цех (редактирование и удаление).
class EquipmentHierarchyAdminScreen extends StatefulWidget {
  const EquipmentHierarchyAdminScreen({super.key});

  @override
  State<EquipmentHierarchyAdminScreen> createState() =>
      _EquipmentHierarchyAdminScreenState();
}

class _EquipmentHierarchyAdminScreenState
    extends State<EquipmentHierarchyAdminScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _enterprises = [];
  final Map<String, List<Map<String, dynamic>>> _branches = {};
  final Map<String, List<Map<String, dynamic>>> _workshops = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final enterprises = await _api.getHierarchyEnterprises();
      _enterprises = enterprises;
      _branches.clear();
      _workshops.clear();
      for (final ent in enterprises) {
        final entId = ent['id']?.toString() ?? '';
        if (entId.isEmpty) continue;
        final branches = await _api.getHierarchyBranches(entId);
        _branches[entId] = branches;
        for (final br in branches) {
          final brId = br['id']?.toString() ?? '';
          if (brId.isEmpty) continue;
          _workshops[brId] = await _api.getHierarchyWorkshops(brId);
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _editEntity({
    required String title,
    required String initialName,
    String? initialCode,
    required Future<void> Function(String name, String code) onSave,
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final codeCtrl = TextEditingController(text: initialCode ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Название *'),
            ),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Код'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await onSave(name, codeCtrl.text.trim());
    await _load();
  }

  Future<void> _confirmDelete(String label, Future<void> Function() onDelete) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удаление'),
        content: Text('Удалить «$label»?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await onDelete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Удалено'), backgroundColor: Colors.green),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Иерархия оборудования'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: _enterprises.map((ent) {
                    final entId = ent['id']?.toString() ?? '';
                    final entName = ent['name']?.toString() ?? '';
                    return ExpansionTile(
                      title: Text(entName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: ent['code'] != null ? Text(ent['code'].toString()) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _editEntity(
                              title: 'Редактировать предприятие',
                              initialName: entName,
                              initialCode: ent['code']?.toString(),
                              onSave: (name, code) => _api.updateHierarchyEntity(
                                '/api/hierarchy/enterprises/$entId',
                                {
                                  'name': name,
                                  if (code.isNotEmpty) 'code': code,
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            onPressed: () => _confirmDelete(
                              entName,
                              () => _api.deleteHierarchyEntity(
                                '/api/hierarchy/enterprises/$entId',
                              ),
                            ),
                          ),
                        ],
                      ),
                      children: (_branches[entId] ?? []).map((br) {
                        final brId = br['id']?.toString() ?? '';
                        final brName = br['name']?.toString() ?? '';
                        return ExpansionTile(
                          title: Text('  $brName'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _editEntity(
                                  title: 'Редактировать филиал',
                                  initialName: brName,
                                  initialCode: br['code']?.toString(),
                                  onSave: (name, code) => _api.updateHierarchyEntity(
                                    '/api/hierarchy/branches/$brId',
                                    {
                                      'name': name,
                                      if (code.isNotEmpty) 'code': code,
                                    },
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                onPressed: () => _confirmDelete(
                                  brName,
                                  () => _api.deleteHierarchyEntity(
                                    '/api/hierarchy/branches/$brId',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          children: (_workshops[brId] ?? []).map((ws) {
                            final wsId = ws['id']?.toString() ?? '';
                            final wsName = ws['name']?.toString() ?? '';
                            return ListTile(
                              dense: true,
                              title: Text('    $wsName'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 16),
                                    onPressed: () => _editEntity(
                                      title: 'Редактировать цех',
                                      initialName: wsName,
                                      initialCode: ws['code']?.toString(),
                                      onSave: (name, code) => _api.updateHierarchyEntity(
                                        '/api/hierarchy/workshops/$wsId',
                                        {
                                          'name': name,
                                          if (code.isNotEmpty) 'code': code,
                                        },
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                    onPressed: () => _confirmDelete(
                                      wsName,
                                      () => _api.deleteHierarchyEntity(
                                        '/api/hierarchy/workshops/$wsId',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
    );
  }
}
