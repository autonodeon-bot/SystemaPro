import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

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
      var opos = await _syncService.getOfflineOpos();

      try {
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
        if (msg.contains('403') ||
            msg.contains('Not authenticated') ||
            msg.contains('Токен авторизации не найден')) {
          if (opos.isNotEmpty && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Режим офлайн: показаны сохранённые ОПО.'),
                backgroundColor: AppColors.warning,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else if (opos.isEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Не удалось загрузить список ОПО: $e'),
              backgroundColor: AppColors.warning,
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
          backgroundColor: AppColors.warning,
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
        title: const Text(
          'ОПО',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadOpos,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Поиск по названию или коду',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Row(
                children: [
                  Text(
                    '${_filteredOpos.length} объектов',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _filteredOpos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 44,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Нет ОПО для отображения'
                                  : 'Ничего не найдено',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadOpos,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: _filteredOpos.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final opo = _filteredOpos[index];
                            final opoId = opo['id']?.toString() ?? '';
                            final opoName = opo['name']?.toString() ?? 'Без названия';
                            final opoCode = opo['code']?.toString() ?? '';

                            return Material(
                              color: AppColors.darkSurface,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () async {
                                  final result = await context.push<bool>('/opo-survey', extra: {
                                    'opoId': opoId,
                                    'opoName': opoName,
                                  });
                                  if (result == true) {
                                    await _loadOpos();
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.darkBorder, width: 1),
                                  ),
                                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: AppColors.warning.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.dangerous_outlined,
                                          color: AppColors.warning,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              opoName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13.5,
                                                letterSpacing: -0.1,
                                                height: 1.25,
                                              ),
                                            ),
                                            if (opoCode.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                opoCode,
                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                  fontSize: 11,
                                                  fontFeatures: [FontFeature.tabularFigures()],
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: AppColors.textSecondary,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
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
