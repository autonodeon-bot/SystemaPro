import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/auth_provider.dart';
import 'vessel_inspection_screen.dart';
import 'questionnaire_screen.dart';
import 'add_equipment_screen.dart';

final equipmentListProvider = FutureProvider<List<Equipment>>((ref) async {
  final apiService = ApiService();
  return await apiService.getEquipmentList();
});

class EquipmentListScreen extends ConsumerWidget {
  const EquipmentListScreen({super.key});

  Future<String> _getUserRole() async {
    final authService = AuthService();
    final user = await authService.getCurrentUser();
    return user?.role ?? 'engineer';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipmentAsync = ref.watch(equipmentListProvider);
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбор оборудования'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          // Кнопка добавления только для операторов и выше
          userAsync.when(
            data: (user) {
              if (user != null && AuthHelper.canManageEquipment(user)) {
                return IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AddEquipmentScreen(),
                      ),
                    );
                    if (result != null) {
                      // Обновляем список оборудования
                      ref.invalidate(equipmentListProvider);
                      // Переходим к диагностике нового оборудования
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VesselInspectionScreen(
                            equipment: result as Equipment,
                          ),
                        ),
                      );
                    }
                  },
                  tooltip: 'Добавить оборудование',
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: equipmentAsync.when(
        data: (equipmentList) {
          if (equipmentList.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.white38,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Оборудование не найдено',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder(
                    future: _getUserRole(),
                    builder: (context, snapshot) {
                      final role = snapshot.data ?? 'engineer';
                      if (role == 'engineer') {
                        return const Text(
                          'Вам не назначен доступ к оборудованию.\nОбратитесь к администратору для получения доступа.',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        );
                      } else {
                        return Column(
                          children: [
                            const Text(
                              'Нажмите + чтобы добавить новое оборудование',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AddEquipmentScreen(),
                                  ),
                                );
                                if (result != null) {
                                  ref.invalidate(equipmentListProvider);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VesselInspectionScreen(
                                        equipment: result as Equipment,
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить оборудование'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3b82f6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: equipmentList.length,
            itemBuilder: (context, index) {
              final equipment = equipmentList[index];
              return Card(
                color: const Color(0xFF1e293b),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  title: Text(
                    equipment.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (equipment.location != null &&
                          equipment.location!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 16,
                                color: Color(0xFF3b82f6),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  equipment.location!,
                                  style: const TextStyle(
                                    color: Color(0xFF3b82f6),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (equipment.serialNumber != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Заводской №: ${equipment.serialNumber}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      if (equipment.attributes != null &&
                          equipment.attributes!['regNumber'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Рег. №: ${equipment.attributes!['regNumber']}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert,
                      color: Color(0xFF3b82f6),
                    ),
                    color: const Color(0xFF1e293b),
                    onSelected: (value) {
                      if (value == 'inspection') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VesselInspectionScreen(
                              equipment: equipment,
                            ),
                          ),
                        );
                      } else if (value == 'questionnaire') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => QuestionnaireScreen(
                              equipment: equipment,
                            ),
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'inspection',
                        child: Row(
                          children: [
                            Icon(Icons.checklist, color: Color(0xFF3b82f6)),
                            SizedBox(width: 8),
                            Text('Диагностика', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'questionnaire',
                        child: Row(
                          children: [
                            Icon(Icons.description, color: Color(0xFF3b82f6)),
                            SizedBox(width: 8),
                            Text('Опросный лист', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    // По умолчанию открываем диагностику
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VesselInspectionScreen(
                          equipment: equipment,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF3b82f6),
          ),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'Ошибка загрузки оборудования',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(equipmentListProvider),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
