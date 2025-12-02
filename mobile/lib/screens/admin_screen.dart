import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_provider.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ панель'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Пользователь не найден', style: TextStyle(color: Colors.white)));
          }

          // Проверка доступа
          if (!AuthHelper.isAdmin(user) && !AuthHelper.hasAnyRole(user, ['chief_operator'])) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Доступ запрещен',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Эта страница доступна только администраторам',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ваша роль: ${_getRoleLabel(user.role)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView(
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
                      const Text(
                        'Административная панель',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Управление системой и пользователями',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Управление пользователями (только для admin)
              if (AuthHelper.isAdmin(user))
                _buildActionCard(
                  context,
                  icon: Icons.people,
                  title: 'Управление пользователями',
                  subtitle: 'Создание и редактирование пользователей',
                  color: const Color(0xFF3b82f6),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Функция будет доступна в следующей версии'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  },
                ),

              // Управление оборудованием
              if (AuthHelper.canManageEquipment(user))
                _buildActionCard(
                  context,
                  icon: Icons.inventory_2,
                  title: 'Управление оборудованием',
                  subtitle: 'Добавление и редактирование оборудования',
                  color: const Color(0xFF10b981),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Используйте веб-интерфейс для управления оборудованием'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  },
                ),

              // Управление доступом
              if (AuthHelper.canManageAccess(user))
                _buildActionCard(
                  context,
                  icon: Icons.security,
                  title: 'Управление доступом',
                  subtitle: 'Назначение доступа инженерам к цехам и оборудованию',
                  color: const Color(0xFFf59e0b),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Используйте веб-интерфейс для управления доступом'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  },
                ),

              // Статистика
              if (AuthHelper.canViewAll(user))
                _buildActionCard(
                  context,
                  icon: Icons.bar_chart,
                  title: 'Статистика системы',
                  subtitle: 'Просмотр статистики по диагностикам и отчетам',
                  color: const Color(0xFF8b5cf6),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Функция будет доступна в следующей версии'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  },
                ),

              const SizedBox(height: 24),
              const Text(
                'Примечание: Для полного управления системой используйте веб-интерфейс',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
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

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      color: const Color(0xFF1e293b),
      margin: const EdgeInsets.only(bottom: 12),
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
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
}

