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

class EquipmentListScreen extends ConsumerStatefulWidget {
  const EquipmentListScreen({super.key});

  @override
  ConsumerState<EquipmentListScreen> createState() =>
      _EquipmentListScreenState();
}

class _EquipmentListScreenState extends ConsumerState<EquipmentListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all'; // all, vessel, pipeline, etc.

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Equipment> _filterEquipment(List<Equipment> equipment) {
    var filtered = equipment;

    // Фильтр по поисковому запросу
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((eq) {
        final query = _searchQuery.toLowerCase();
        return eq.name.toLowerCase().contains(query) ||
            (eq.serialNumber?.toLowerCase().contains(query) ?? false) ||
            (eq.location?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    // Фильтр по типу (если выбран)
    if (_selectedFilter != 'all') {
      filtered = filtered.where((eq) {
        // Здесь можно добавить фильтрацию по типу оборудования
        return true; // Пока возвращаем все
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
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
      body: Column(
        children: [
          // Поиск
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск оборудования...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1e293b),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFF3b82f6), width: 2),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          // Список оборудования
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(equipmentListProvider);
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: equipmentAsync.when(
                data: (equipmentList) {
                  final filteredList = _filterEquipment(equipmentList);

                  if (filteredList.isEmpty) {
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
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Ничего не найдено по запросу "$_searchQuery"'
                                : 'Оборудование не найдено',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                          if (_searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                              child: const Text('Очистить поиск'),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final equipment = filteredList[index];
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
                                    style:
                                        const TextStyle(color: Colors.white70),
                                  ),
                                ),
                              if (equipment.attributes != null &&
                                  equipment.attributes!['regNumber'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Рег. №: ${equipment.attributes!['regNumber']}',
                                    style:
                                        const TextStyle(color: Colors.white70),
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
                                    builder: (context) =>
                                        VesselInspectionScreen(
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
                                    Icon(Icons.checklist,
                                        color: Color(0xFF3b82f6)),
                                    SizedBox(width: 8),
                                    Text('Диагностика',
                                        style: TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'questionnaire',
                                child: Row(
                                  children: [
                                    Icon(Icons.description,
                                        color: Color(0xFF3b82f6)),
                                    SizedBox(width: 8),
                                    Text('Опросный лист',
                                        style: TextStyle(color: Colors.white)),
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
            ),
          ),
        ],
      ),
    );
  }
}
