import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'vessel_inspection_screen.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

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
    final msg = e.toString();
    // Если сессия недействительна — не подменяем офлайн-данными, а просим перелогиниться
    if (msg.contains('AUTH_INVALID') ||
        msg.contains('Invalid authentication credentials') ||
        msg.contains('401')) {
      rethrow;
    }
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
  final _authService = AuthService();
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
    // Инициализируем фильтры при первом получении списка оборудования.
    // ВАЖНО: не делать setState() напрямую внутри build().
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
    final workshopsMap = <String, Set<String>>{}; // workshop_id -> {equipment_ids}
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
            workshopsMap.putIfAbsent(equipment.workshopId!, () => <String>{});
            workshopNames[equipment.workshopId!] = equipment.workshopName!;
            workshopsMap[equipment.workshopId!]!.add(equipment.id);
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
    
    // Группируем по предприятию -> филиал -> цех -> тип (многоуровневая структура)
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
    
    // Формируем многоуровневую структуру для отображения
    for (var enterpriseEntry in enterpriseGroups.entries) {
      final enterpriseId = enterpriseEntry.key;
      final enterpriseName = _enterpriseNames[enterpriseId] ?? 'Неизвестное предприятие';
      
      // Группа предприятия
      final enterpriseItems = <Map<String, dynamic>>[];
      
      for (var branchEntry in enterpriseEntry.value.entries) {
        final branchId = branchEntry.key;
        final branchName = _branchNames[branchId] ?? 'Неизвестный филиал';
        
        // Группа филиала
        final branchItems = <Map<String, dynamic>>[];
        
        for (var workshopEntry in branchEntry.value.entries) {
          final workshopId = workshopEntry.key;
          final workshopName = _workshopNames[workshopId] ?? 'Неизвестный цех';
          
          // Группа цеха
          final workshopItems = <Map<String, dynamic>>[];
          
          for (var typeEntry in workshopEntry.value.entries) {
            final typeId = typeEntry.key;
            final typeName = _typeNames[typeId] ?? 'Неизвестный тип';
            final equipmentList = typeEntry.value;
            
            if (equipmentList.isNotEmpty) {
              workshopItems.add({
                'key': '$enterpriseId-$branchId-$workshopId-$typeId',
                'title': typeName,
                'subtitle': null,
                'icon': Icons.category,
                'items': equipmentList,
                'level': 3, // Уровень типа
              });
            }
          }
          
          if (workshopItems.isNotEmpty) {
            branchItems.add({
              'key': '$enterpriseId-$branchId-$workshopId',
              'title': workshopName,
              'subtitle': 'Цех',
              'icon': Icons.factory,
              'items': workshopItems,
              'level': 2, // Уровень цеха
            });
          }
        }
        
        if (branchItems.isNotEmpty) {
          enterpriseItems.add({
            'key': '$enterpriseId-$branchId',
            'title': branchName,
            'subtitle': 'Филиал',
            'icon': Icons.business,
            'items': branchItems,
            'level': 1, // Уровень филиала
          });
        }
      }
      
      if (enterpriseItems.isNotEmpty) {
        groups.add({
          'key': enterpriseId,
          'title': enterpriseName,
          'subtitle': 'Предприятие',
          'icon': Icons.domain,
          'items': enterpriseItems,
          'level': 0, // Уровень предприятия
        });
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
          'level': 0,
        });
      }
    }
    
    return groups;
  }
  
  Widget _buildGroupItem(Map<String, dynamic> group, int level) {
    final groupKey = group['key'] as String;
    final isExpanded = _expandedGroups[groupKey] ?? (level == 0); // По умолчанию раскрыты только верхние уровни
    final items = group['items'] as List;
    final isEquipmentList = items.isNotEmpty && items.first is Equipment;
    
    return Card(
      color: Color(0xFF1e293b + (level * 0x00101010).clamp(0, 0x00202020)),
      margin: EdgeInsets.only(bottom: 8, left: (level * 16).toDouble()),
      child: Column(
        children: [
          // Заголовок группы
          InkWell(
            onTap: () {
              setState(() {
                _expandedGroups[groupKey] = !isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    group['icon'] as IconData,
                    color: const Color(0xFF3b82f6),
                    size: (20 - (level * 2)).clamp(14, 20).toDouble(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group['title'] as String,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: (16 - (level * 1)).clamp(12, 16).toDouble(),
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
                  if (!isEquipmentList)
                    Text(
                      '${items.length}',
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
          // Содержимое группы
          if (isExpanded)
            ...isEquipmentList
                ? (items as List<Equipment>).map((equipment) => _buildEquipmentItem(equipment, level + 1))
                : (items as List<Map<String, dynamic>>).map((item) => _buildGroupItem(item, level + 1)),
        ],
      ),
    );
  }
  
  Widget _buildEquipmentItem(Equipment equipment, int level) {
    String? attr(String key) {
      final a = equipment.attributes;
      if (a == null) return null;
      final v = a[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final inventoryNumber =
        attr('equipment_inventory_number') ?? attr('inventory_number') ?? attr('inv_number');
    final manufacturer = attr('manufacturer');
    final manufactureYear = attr('manufacture_year') ?? attr('year');

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VesselInspectionScreen(equipment: equipment),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: (16 + (level * 8)).toDouble(),
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
            const SizedBox(width: 32),
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
                  if (inventoryNumber != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Инв. №: $inventoryNumber',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (manufacturer != null || manufactureYear != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if (manufacturer != null) 'Изготовитель: $manufacturer',
                          if (manufactureYear != null) 'Год: $manufactureYear',
                        ].join(' • '),
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
                Column(
                  children: [
                    // Предприятие
                    DropdownButtonFormField<String>(
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
                    const SizedBox(height: 8),
                    // Фильтр по филиалу
                    if (_selectedEnterprise != null)
                      DropdownButtonFormField<String>(
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
                    if (_selectedEnterprise != null) const SizedBox(height: 8),
                    // Фильтр по цеху
                    if (_selectedBranch != null)
                      DropdownButtonFormField<String>(
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
                    if (_selectedBranch != null) const SizedBox(height: 8),
                    // Фильтр по типу оборудования
                    DropdownButtonFormField<String>(
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
                  // Если список пустой из-за фильтров
                  if (_selectedEnterprise != null || _selectedBranch != null || 
                      _selectedWorkshop != null || _selectedType != null || 
                      _searchController.text.isNotEmpty) {
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
                  
                  // Если список действительно пустой
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
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Обратитесь к администратору для назначения оборудования',
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => ref.invalidate(equipmentListProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Обновить'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3b82f6),
                            foregroundColor: Colors.white,
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
                    return _buildGroupItem(group, 0);
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
                    if (error.toString().contains('AUTH_INVALID') ||
                        error.toString().contains('Invalid authentication credentials') ||
                        error.toString().contains('401')) ...[
                      ElevatedButton.icon(
                        onPressed: () async {
                          await _authService.logout();
                          try {
                            await SyncService().clearOfflineCache();
                          } catch (_) {}
                          if (!mounted) return;
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('Войти заново'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3b82f6),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(equipmentListProvider),
                        child: const Text('Повторить'),
                      ),
                    ] else
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

