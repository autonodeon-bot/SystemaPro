import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_provider.dart';

class OperatorScreen extends ConsumerWidget {
  const OperatorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление доступом'),
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
          if (!AuthHelper.canManageAccess(user)) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.red, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Доступ запрещен',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Эта функция доступна только операторам и администраторам',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Информация
              const Card(
                color: Color(0xFF1e293b),
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Управление доступом',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Назначение доступа инженерам к цехам и оборудованию',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Информационное сообщение
              const Card(
                color: Color(0xFF1e293b),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF3b82f6)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Используйте веб-интерфейс',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Для назначения доступа к цехам и оборудованию используйте веб-интерфейс системы',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Ссылка на веб-интерфейс
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: Открыть веб-интерфейс в браузере
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Откройте http://5.129.203.182/#/equipment в браузере'),
                      duration: Duration(seconds: 5),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Открыть веб-интерфейс'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3b82f6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
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
}

