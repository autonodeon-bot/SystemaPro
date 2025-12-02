import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import 'equipment_list_screen.dart';
import 'profile_screen.dart';
import 'sync_screen.dart';
import '../models/user.dart';

final currentUserProvider = FutureProvider<User?>((ref) async {
  final authService = AuthService();
  return await authService.getCurrentUser();
});

final specialistStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final authService = AuthService();
  final user = await authService.getCurrentUser();
  if (user == null) return {};
  
  final apiService = ApiService();
  final engineerId = user.engineerId ?? user.id;
  return await apiService.getSpecialistStats(engineerId);
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Обновляем счетчик синхронизации при открытии экрана
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {});
    });
  }

  Future<int> _getPendingCount() async {
    final syncService = SyncService();
    final inspections = await syncService.getPendingInspections();
    final reports = await syncService.getPendingReports();
    final questionnaires = await syncService.getPendingQuestionnaires();
    return inspections.length + reports.length + questionnaires.length;
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final statsAsync = ref.watch(specialistStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Пользователь не найден'));
          }

          // Показываем роль пользователя для отладки
          print('Пользователь: ${user.username}, Роль: ${user.role}');

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(currentUserProvider);
              ref.invalidate(specialistStatsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Приветствие
                Card(
                  color: const Color(0xFF1e293b),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3b82f6),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Center(
                                child: Text(
                                  user.fullName.isNotEmpty
                                      ? user.fullName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Добро пожаловать,',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    user.fullName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (user.position != null)
                                    Text(
                                      user.position!,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 14,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Роль: ${_getRoleLabel(user.role)}',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Статистика
                statsAsync.when(
                  data: (stats) => _buildStatsGrid(stats),
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (_, __) => const SizedBox(),
                ),

                const SizedBox(height: 24),

                // Быстрые действия
                const Text(
                  'Быстрые действия',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionCard(
                  context,
                  icon: Icons.inventory_2,
                  title: 'Оборудование',
                  subtitle: 'Выбрать оборудование для диагностики',
                  color: const Color(0xFF3b82f6),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EquipmentListScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildActionCard(
                  context,
                  icon: Icons.assignment,
                  title: 'Мои диагностики',
                  subtitle: 'Просмотр выполненных диагностик',
                  color: const Color(0xFF10b981),
                  onTap: () {
                    // TODO: Navigate to inspections list
                  },
                ),
                const SizedBox(height: 12),
                _buildActionCard(
                  context,
                  icon: Icons.description,
                  title: 'Отчеты',
                  subtitle: 'Созданные отчеты и экспертизы',
                  color: const Color(0xFFf59e0b),
                  onTap: () {
                    // TODO: Navigate to reports
                  },
                ),
                const SizedBox(height: 12),
                _buildActionCard(
                  context,
                  icon: Icons.person,
                  title: 'Личный кабинет',
                  subtitle: 'Профиль, сертификаты, документы',
                  color: const Color(0xFF8b5cf6),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ProfileScreen()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                FutureBuilder<int>(
                  future: _getPendingCount(),
                  builder: (context, snapshot) {
                    final pendingCount = snapshot.data ?? 0;
                    return _buildActionCard(
                      context,
                      icon: Icons.sync,
                      title: 'Синхронизация',
                      subtitle: pendingCount > 0 
                          ? 'Ожидает: $pendingCount элементов'
                          : 'Все синхронизировано',
                      color: pendingCount > 0 
                          ? Colors.orange 
                          : Colors.green,
                      badge: pendingCount > 0 ? pendingCount.toString() : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SyncScreen()),
                        );
                      },
                    );
                  },
                ),
                
                // Версия приложения
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final packageInfo = snapshot.data!;
                      return Padding(
                        padding: const EdgeInsets.only(top: 24, bottom: 16),
                        child: Center(
                          child: Text(
                            'Версия: ${packageInfo.version}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'Ошибка загрузки: $error',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Администратор';
      case 'chief_operator':
        return 'Главный оператор';
      case 'operator':
        return 'Оператор';
      case 'engineer':
        return 'Инженер';
      default:
        return role;
    }
  }

  Widget _buildStatsGrid(Map<String, dynamic> stats) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Диагностики',
          stats['total_inspections']?.toString() ?? '0',
          Icons.checklist,
          const Color(0xFF3b82f6),
        ),
        _buildStatCard(
          'Отчеты',
          stats['total_reports']?.toString() ?? '0',
          Icons.description,
          const Color(0xFF10b981),
        ),
        _buildStatCard(
          'Проекты',
          stats['active_projects']?.toString() ?? '0',
          Icons.folder,
          const Color(0xFFf59e0b),
        ),
        _buildStatCard(
          'Сертификаты',
          stats['certifications_count']?.toString() ?? '0',
          Icons.verified,
          const Color(0xFF8b5cf6),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      color: const Color(0xFF1e293b),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Card(
      color: const Color(0xFF1e293b),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 16),
        onTap: onTap,
      ),
    );
  }
}



