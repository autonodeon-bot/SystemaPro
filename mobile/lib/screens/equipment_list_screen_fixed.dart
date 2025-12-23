import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'vessel_inspection_screen.dart';

final equipmentListProvider = FutureProvider<List<Equipment>>((ref) async {
  final apiService = ApiService();
  final syncService = SyncService();
  
  try {
    // Пытаемся загрузить с сервера
    final equipmentList = await apiService.getEquipmentList();
    // Сохраняем локально для офлайн-режима
    await syncService.saveEquipmentOffline(equipmentList);
    return equipmentList;
  } catch (e) {
    // Если не удалось загрузить с сервера, используем локальное хранилище
    final offlineEquipment = await syncService.getOfflineEquipment();
    if (offlineEquipment.isNotEmpty) {
      return offlineEquipment;
    }
    // Если локального хранилища нет, пробрасываем ошибку
    rethrow;
  }
});

class EquipmentListScreen extends ConsumerStatefulWidget {
  const EquipmentListScreen({super.key});

  @override
  ConsumerState<EquipmentListScreen> createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends ConsumerState<EquipmentListScreen> {
  String? _selectedEnterprise;
  String? _selectedBranch;
  String? _selectedWorkshop;
  String? _selectedType;
  
  Map<String, List<String>> _enterprisesMap = {}; // enterprise_id -> [branch_ids]
  Map<String, List<String>> _branchesMap = {}; // branch_id -> [workshop_ids]
  Map<String, String> _enterpriseNames = {}; // enterprise_id -> name
  Map<String, String> _branchNames = {}; // branch_id -> name
  Map<String, String> _workshopNames = {}; // workshop_id -> name
  Map<String, String> _typeNames = {}; // type_id -> name
  
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expandedGroups = {}; // Для раскрывающихся списков
  int _lastEquipmentHash = 0;

  @override
  void initState() {
    super.initState();
    // Инициализация фильтров после загрузки данных, чтобы не было setState в build
    ref.listen<AsyncValue<List<Equipment>>>(equipmentListProvider, (_, next) {
      next.whenData((equipmentList) {
        final h = Object.hashAll(equipmentList.map((e) => e.id));
        if (h == _lastEquipmentHash) return;
        _lastEquipmentHash = h;
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _loadFilters(equipmentList);
        });
      });
    });
  }

  void _loadFilters(List<Equipment> equipmentList) {
      final enterprisesMap = <String, Set<String>>{}; // enterprise_id -> {branch_ids}
      final branchesMap = <String, Set<String>>{}; // branch_id -> {workshop_ids}
      final enterpriseNames = <String, String>{};
      final branchNames = <String, String>{};
      final workshopNames = <String, String>{};
      final typeNames = <String, String>{};

      for (var equipment in equipmentList) {
        // Группируем по иерархии
        if (equipment.enterpriseId != null && equipment.enterpriseName != null) {
          enterprisesMap.putIfAbsent(equipment.enterpriseId!, () => <String>{});
          enterpriseNames[equipment.enterpriseId!] = equipment.enterpriseName!;
          
          if (equipment.branchId != null && equipment.branchName != null) {
            enterprisesMap[equipment.enterpriseId!]!.add(equipment.branchId!);
            branchesMap.putIfAbsent(equipment.branchId!, () => <String>{});
            branchNames[equipment.branchId!] = equipment.branchName!;
            
            if (equipment.workshopId != null && equipment.workshopName != null) {
              branchesMap[equipment.branchId!]!.add(equipment.workshopId!);
              workshopNames[equipment.workshopId!] = equipment.workshopName!;
            }
          }
        }
        
        // Группируем по типу оборудования
        if (equipment.typeId != null && equipment.typeName != null) {
          typeNames[equipment.typeId!] = equipment.typeName!;
        }
      }

      setState(() {
        _enterprisesMap = enterprisesMap.map((k, v) => MapEntry(k, v.toList()..sort()));
        _branchesMap = branchesMap.map((k, v) => MapEntry(k, v.toList()..sort()));
        _enterpriseNames = enterpriseNames;
        _branchNames = branchNames;
        _workshopNames = workshopNames;
        _typeNames = typeNames;
      });
  }

  List<Equipment> _filterEquipment(List<Equipment> equipmentList) {
    var filtered = equipmentList;

    // Фильтр по поисковому запросу
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((eq) {
        return eq.name.toLowerCase().contains(query) ||
            (eq.serialNumber?.toLowerCase().contains(query) ?? false) ||
            (eq.location?.toLowerCase().contains(query) ?? false) ||
            (eq.enterpriseName?.toLowerCase().contains(query) ?? false) ||
            (eq.branchName?.toLowerCase().contains(query) ?? false) ||
            (eq.workshopName?.toLowerCase().contains(query) ?? false) ||
            (eq.typeName?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    // Фильтр по предприятию
    if (_selectedEnterprise != null) {
      filtered = filtered.where((eq) {
        return eq.enterpriseId == _selectedEnterprise;
      }).toList();
    }

    // Фильтр по филиалу
    if (_selectedBranch != null) {
      filtered = filtered.where((eq) {
        return eq.branchId == _selectedBranch;
      }).toList();
    }

    // Фильтр по цеху
    if (_selectedWorkshop != null) {
      filtered = filtered.where((eq) {
        return eq.workshopId == _selectedWorkshop;
      }).toList();
    }

    // Фильтр по типу оборудования
    if (_selectedType != null) {
      filtered = filtered.where((eq) {
        return eq.typeId == _selectedType;
      }).toList();
    }

    return filtered;
  }

  List<Map<String, dynamic>> _groupEquipmentByHierarchy(List<Equipment> equipmentList) {
    final groups = <Map<String, dynamic>>[];
    
    // Группируем по предприятию -> филиал -> цех -> тип
    final enterpriseGroups = <String, Map<String, Map<String, Map<String, List<Equipment>>>>>{};
    
    for (var equipment in equipmentList) {
      final enterpriseId = equipment.enterpriseId ?? 'unknown';
      final branchId = equipment.branchId ?? 'unknown';
      final workshopId = equipment.workshopId ?? 'unknown';
      final typeId = equipment.typeId ?? 'unknown';
      
      enterpriseGroups.putIfAbsent(enterpriseId, () => {});
      enterpriseGroups[enterpriseId]!.putIfAbsent(branchId, () => {});
      enterpriseGroups[enterpriseId]![branchId]!.putIfAbsent(workshopId, () => {});
      enterpriseGroups[enterpriseId]![branchId]![workshopId]!.putIfAbsent(typeId, () => []);
      enterpriseGroups[enterpriseId]![branchId]![workshopId]![typeId]!.add(equipment);
    }
    
    // Формируем список групп для отображения
    for (var enterpriseEntry in enterpriseGroups.entries) {
      final enterpriseId = enterpriseEntry.key;
      final enterpriseName = _enterpriseNames[enterpriseId] ?? 'Неизвестное предприятие';
      
      for (var branchEntry in enterpriseEntry.value.entries) {
        final branchId = branchEntry.key;
        final branchName = _branchNames[branchId] ?? 'Неизвестный филиал';
        
        for (var workshopEntry in branchEntry.value.entries) {
          final workshopId = workshopEntry.key;
          final workshopName = _workshopNames[workshopId] ?? 'Неизвестный цех';
          
          for (var typeEntry in workshopEntry.value.entries) {
            final typeId = typeEntry.key;
            final typeName = _typeNames[typeId] ?? 'Неизвестный тип';
            final equipmentList = typeEntry.value;
            
            if (equipmentList.isNotEmpty) {
              groups.add({
                'key': '$enterpriseId-$branchId-$workshopId-$typeId',
                'title': typeName,
                'subtitle': '$enterpriseName → $branchName → $workshopName',
                'icon': Icons.category,
                'items': equipmentList,
              });
            }
          }
        }
      }
    }
    
    // Если нет иерархии, группируем просто по типу
    if (groups.isEmpty) {
      final typeGroups = <String, List<Equipment>>{};
      for (var equipment in equipmentList) {
        final typeId = equipment.typeId ?? 'unknown';
        typeGroups.putIfAbsent(typeId, () => []);
        typeGroups[typeId]!.add(equipment);
      }
      
      for (var typeEntry in typeGroups.entries) {
        final typeName = _typeNames[typeEntry.key] ?? 'Неизвестный тип';
        groups.add({
          'key': 'type-${typeEntry.key}',
          'title': typeName,
          'subtitle': null,
          'icon': Icons.category,
          'items': typeEntry.value,
        });
      }
    }
    
    return groups;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final equipmentAsync = ref.watch(equipmentListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбор оборудования'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: Column(
        children: [
          // Фильтры
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1e293b),
            child: Column(
              children: [
                // Поиск
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск по названию, номеру, местоположению...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF0f172a),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                // Фильтры по иерархии
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Фильтр по предприятию
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedEnterprise,
                        decoration: InputDecoration(
                          labelText: 'Предприятие',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: const Color(0xFF0f172a),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                          ),
                        ),
                        dropdownColor: const Color(0xFF1e293b),
                        style: const TextStyle(color: Colors.white),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Все предприятия'),
                          ),
                          ..._enterpriseNames.entries.map((entry) => DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value),
                              )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedEnterprise = value;
                            _selectedBranch = null; // Сбрасываем филиал при смене предприятия
                            _selectedWorkshop = null; // Сбрасываем цех
                          });
                        },
                      ),
                    ),
                    // Фильтр по филиалу
                    if (_selectedEnterprise != null)
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedBranch,
                          decoration: InputDecoration(
                            labelText: 'Филиал',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: const Color(0xFF0f172a),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white24),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                            ),
                          ),
                          dropdownColor: const Color(0xFF1e293b),
                          style: const TextStyle(color: Colors.white),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Все филиалы'),
                            ),
                            ...(_enterprisesMap[_selectedEnterprise] ?? []).map((branchId) {
                              return DropdownMenuItem<String>(
                                value: branchId,
                                child: Text(_branchNames[branchId] ?? branchId),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedBranch = value;
                              _selectedWorkshop = null; // Сбрасываем цех при смене филиала
                            });
                          },
                        ),
                      ),
                    // Фильтр по цеху
                    if (_selectedBranch != null)
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedWorkshop,
                          decoration: InputDecoration(
                            labelText: 'Цех',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: const Color(0xFF0f172a),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white24),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                            ),
                          ),
                          dropdownColor: const Color(0xFF1e293b),
                          style: const TextStyle(color: Colors.white),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Все цеха'),
                            ),
                            ...(_branchesMap[_selectedBranch] ?? []).map((workshopId) {
                              return DropdownMenuItem<String>(
                                value: workshopId,
                                child: Text(_workshopNames[workshopId] ?? workshopId),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedWorkshop = value;
                            });
                          },
                        ),
                      ),
                    // Фильтр по типу оборудования
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedType,
                        decoration: InputDecoration(
                          labelText: 'Тип оборудования',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: const Color(0xFF0f172a),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                          ),
                        ),
                        dropdownColor: const Color(0xFF1e293b),
                        style: const TextStyle(color: Colors.white),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Все типы'),
                          ),
                          ..._typeNames.entries.map((entry) => DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value),
                              )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedType = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                // Кнопка сброса фильтров
                if (_selectedEnterprise != null || _selectedBranch != null || 
                    _selectedWorkshop != null || _selectedType != null || 
                    _searchController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedEnterprise = null;
                          _selectedBranch = null;
                          _selectedWorkshop = null;
                          _selectedType = null;
                          _searchController.clear();
                        });
                      },
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Сбросить фильтры'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF3b82f6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Список оборудования
          Expanded(
            child: equipmentAsync.when(
              data: (equipmentList) {
                final filtered = _filterEquipment(equipmentList);
                
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.white38,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Оборудование не найдено',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        if (_selectedEnterprise != null || _selectedBranch != null || 
                            _selectedWorkshop != null || _selectedType != null || 
                            _searchController.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedEnterprise = null;
                                  _selectedBranch = null;
                                  _selectedWorkshop = null;
                                  _selectedType = null;
                                  _searchController.clear();
                                });
                              },
                              child: const Text('Сбросить фильтры'),
                            ),
                          ),
                      ],
                    ),
                  );
                }

                // Группируем оборудование по иерархии
                final groupedEquipment = _groupEquipmentByHierarchy(filtered);
                
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groupedEquipment.length,
                  itemBuilder: (context, index) {
                    final group = groupedEquipment[index];
                    final isExpanded = _expandedGroups[group['key']] ?? true;
                    
                    return Card(
                      color: const Color(0xFF1e293b),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          // Заголовок группы
                          InkWell(
                            onTap: () {
                              setState(() {
                                _expandedGroups[group['key']] = !isExpanded;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    group['icon'] as IconData,
                                    color: const Color(0xFF3b82f6),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          group['title'] as String,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (group['subtitle'] != null)
                                          Text(
                                            group['subtitle'] as String,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${(group['items'] as List).length}',
                                    style: const TextStyle(
                                      color: Color(0xFF3b82f6),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isExpanded ? Icons.expand_less : Icons.expand_more,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Список оборудования в группе
                          if (isExpanded)
                            ...(group['items'] as List<Equipment>).map((equipment) {
                              return InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VesselInspectionScreen(
                                        equipment: equipment,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.white.withOpacity(0.1),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 32), // Отступ для иконки группы
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              equipment.name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (equipment.typeName != null)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Text(
                                                  'Тип: ${equipment.typeName}',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            if (equipment.serialNumber != null)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(
                                                  'Заводской №: ${equipment.serialNumber}',
                                                  style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_forward_ios,
                                        color: Color(0xFF3b82f6),
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                        ],
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
        ],
      ),
    );
  }
}


