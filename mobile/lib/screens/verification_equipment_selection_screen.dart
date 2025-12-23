import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class VerificationEquipmentSelectionScreen extends StatefulWidget {
  final List<String>? preselectedIds; // Предварительно выбранные ID
  final Function(List<String> selectedIds)? onEquipmentSelected;

  const VerificationEquipmentSelectionScreen({
    super.key,
    this.preselectedIds,
    this.onEquipmentSelected,
  });

  @override
  State<VerificationEquipmentSelectionScreen> createState() =>
      _VerificationEquipmentSelectionScreenState();
}

class _VerificationEquipmentSelectionScreenState
    extends State<VerificationEquipmentSelectionScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _equipmentList = [];
  Set<String> _selectedIds = {};
  bool _loading = true;
  String? _error;
  String? _filterType;

  final List<String> _equipmentTypes = [
    'ВИК',
    'УЗК',
    'ПВК',
    'РК',
    'МК',
    'ВК',
    'ТК',
    'Другое',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.preselectedIds != null) {
      _selectedIds = Set.from(widget.preselectedIds!);
    }
    _loadEquipment();
  }

  Future<void> _loadEquipment() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final equipment = await _apiService.getVerificationEquipment(
        equipmentType: _filterType,
        isActive: true,
      );
      setState(() {
        _equipmentList = equipment;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        // Проверяем, не просрочено ли оборудование
        final equipment = _equipmentList.firstWhere(
          (eq) => eq['id'] == id,
          orElse: () => {},
        );
        final isExpired = equipment['is_expired'] == true;
        if (isExpired) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нельзя выбрать просроченное оборудование!'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        _selectedIds.add(id);
      }
    });
  }

  Color _getStatusColor(Map<String, dynamic> equipment) {
    if (equipment['is_expired'] == true) {
      return Colors.red;
    }
    final days = equipment['days_until_expiry'] as int?;
    if (days != null && days <= 7) {
      return Colors.orange;
    }
    if (days != null && days <= 30) {
      return Colors.yellow.shade700;
    }
    return Colors.green;
  }

  String _getStatusText(Map<String, dynamic> equipment) {
    if (equipment['is_expired'] == true) {
      return 'Просрочено';
    }
    final days = equipment['days_until_expiry'] as int?;
    if (days == null) {
      return 'Активно';
    }
    if (days <= 0) {
      return 'Просрочено';
    }
    if (days <= 7) {
      return 'Истекает через $days дн.';
    }
    if (days <= 30) {
      return 'Истекает через $days дн.';
    }
    return 'Активно ($days дн.)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Выбор оборудования для поверок'),
        backgroundColor: const Color(0xFF1e293b),
        actions: [
          if (_filterType != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _filterType = null;
                });
                _loadEquipment();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Фильтр по типу
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF1e293b),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Тип: ',
                    style: TextStyle(color: Colors.white70),
                  ),
                  ..._equipmentTypes.map((type) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(type),
                          selected: _filterType == type,
                          onSelected: (selected) {
                            setState(() {
                              _filterType = selected ? type : null;
                            });
                            _loadEquipment();
                          },
                          selectedColor: const Color(0xFF3b82f6),
                        ),
                      )),
                ],
              ),
            ),
          ),
          // Список оборудования
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Ошибка: $_error',
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadEquipment,
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      )
                    : _equipmentList.isEmpty
                        ? const Center(
                            child: Text(
                              'Оборудование не найдено',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _equipmentList.length,
                            itemBuilder: (context, index) {
                              final equipment = _equipmentList[index];
                              final id = equipment['id'] as String;
                              final isSelected = _selectedIds.contains(id);
                              final isExpired = equipment['is_expired'] == true;

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                color: const Color(0xFF1e293b),
                                child: ListTile(
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: isExpired
                                        ? null
                                        : (value) => _toggleSelection(id),
                                  ),
                                  title: Text(
                                    equipment['name'] ?? 'Без названия',
                                    style: TextStyle(
                                      color: isExpired
                                          ? Colors.grey
                                          : Colors.white,
                                    ),
                                  ),
                                  trailing: isExpired
                                      ? const Icon(
                                          Icons.error,
                                          color: Colors.red,
                                        )
                                      : null,
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (equipment['equipment_type'] != null)
                                        Text(
                                          'Тип: ${equipment['equipment_type']}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      if (equipment['serial_number'] != null)
                                        Text(
                                          'Серийный номер: ${equipment['serial_number']}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      if (equipment['next_verification_date'] !=
                                          null)
                                        Text(
                                          'Следующая поверка: ${_formatDate(equipment['next_verification_date'])}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(equipment)
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _getStatusText(equipment),
                                          style: TextStyle(
                                            color: _getStatusColor(equipment),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: isExpired
                                      ? null
                                      : () => _toggleSelection(id),
                                ),
                              );
                            },
                          ),
          ),
          // Кнопка подтверждения
          if (_selectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1e293b),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Выбрано: ${_selectedIds.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (widget.onEquipmentSelected != null) {
                        widget.onEquipmentSelected!(_selectedIds.toList());
                      }
                      Navigator.pop(context, _selectedIds.toList());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3b82f6),
                    ),
                    child: const Text('Подтвердить'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd.MM.yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }
}

