import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';

class OpoListScreen extends ConsumerStatefulWidget {
  const OpoListScreen({super.key});

  @override
  ConsumerState<OpoListScreen> createState() => _OpoListScreenState();
}

class _OpoListScreenState extends ConsumerState<OpoListScreen> {
  final ApiService _apiService = ApiService();
  final SyncService _syncService = SyncService();
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _opos = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOpos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOpos() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Сначала берём из офлайн-кэша (для режима без сети / PIN-вход)
      var opos = await _syncService.getOfflineOpos();

      try {
        // Пытаемся загрузить с сервера (если есть токен)
        final fromApi = await _apiService.getOpos();
        opos = fromApi;
        await _syncService.saveOposOffline(opos);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('AUTH_INVALID') ||
            msg.contains('Invalid authentication credentials') ||
            msg.contains('401')) {
          await _authService.logout();
          if (!mounted) return;
          context.go('/login');
          return;
        }
        // 403 / Not authenticated / нет токена — офлайн: используем кэш, не показываем ошибку
        if (msg.contains('403') ||
            msg.contains('Not authenticated') ||
            msg.contains('Токен авторизации не найден')) {
          if (opos.isNotEmpty && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Режим офлайн: показаны сохранённые ОПО. При появлении интернета выполните синхронизацию.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (opos.isEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Не удалось загрузить список ОПО: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _opos = opos;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _opos = [];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось загрузить список ОПО: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredOpos {
    if (_searchQuery.isEmpty) return _opos;
    final query = _searchQuery.toLowerCase();
    return _opos.where((opo) {
      final name = (opo['name'] ?? '').toString().toLowerCase();
      final code = (opo['code'] ?? '').toString().toLowerCase();
      return name.contains(query) || code.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ОПО (Опасные производственные объекты)'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOpos,
            tooltip: 'Обновить список',
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: Column(
        children: [
          // Поиск
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск по названию или коду ОПО...',
                hintStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF1e293b),
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
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          
          // Список ОПО
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredOpos.isEmpty
                    ? Center(
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
                              _searchQuery.isEmpty
                                  ? 'Нет ОПО для отображения'
                                  : 'Ничего не найдено',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadOpos,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredOpos.length,
                          itemBuilder: (context, index) {
                            final opo = _filteredOpos[index];
                            final opoId = opo['id']?.toString() ?? '';
                            final opoName = opo['name']?.toString() ?? 'Без названия';
                            final opoCode = opo['code']?.toString() ?? '';
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: const Color(0xFF1e293b),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.dangerous,
                                  color: Color(0xFF3b82f6),
                                  size: 32,
                                ),
                                title: Text(
                                  opoName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: opoCode.isNotEmpty
                                    ? Text(
                                        'Код: $opoCode',
                                        style: const TextStyle(color: Colors.white70),
                                      )
                                    : null,
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Color(0xFF3b82f6),
                                  ),
                                  onPressed: () async {
                                    final result = await context.push<bool>('/opo-survey', extra: {
                                      'opoId': opoId,
                                      'opoName': opoName,
                                    });
                                    if (result == true) {
                                      await _loadOpos();
                                    }
                                  },
                                  tooltip: 'Заполнить опросный лист ОПО',
                                ),
                                onTap: () async {
                                  final result = await context.push<bool>('/opo-survey', extra: {
                                    'opoId': opoId,
                                    'opoName': opoName,
                                  });
                                  if (result == true) {
                                    await _loadOpos();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
