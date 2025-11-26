import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

final userDocumentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authService = AuthService();
  final user = await authService.getCurrentUser();
  if (user == null) return [];
  
  final apiService = ApiService();
  return await apiService.getSpecialistDocuments(user.id);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final documentsAsync = ref.watch(userDocumentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Личный кабинет'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Пользователь не найден'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Профиль
              Card(
                color: const Color(0xFF1e293b),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3b82f6),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Center(
                          child: Text(
                            user.fullName.isNotEmpty
                                ? user.fullName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (user.position != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          user.position!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Chip(
                            label: Text(
                              user.role.toUpperCase(),
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: const Color(0xFF3b82f6).withOpacity(0.2),
                            labelStyle: const TextStyle(color: Color(0xFF3b82f6)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Контактная информация
              _buildSection(
                'Контактная информация',
                [
                  if (user.email != null)
                    _buildInfoRow(Icons.email, 'Email', user.email!),
                  if (user.phone != null)
                    _buildInfoRow(Icons.phone, 'Телефон', user.phone!),
                ],
              ),

              // Специализация
              if (user.equipmentTypes != null && user.equipmentTypes!.isNotEmpty)
                _buildSection(
                  'Специализация',
                  [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: user.equipmentTypes!.map((type) {
                        return Chip(
                          label: Text(type),
                          backgroundColor: const Color(0xFF10b981).withOpacity(0.2),
                          labelStyle: const TextStyle(color: Color(0xFF10b981)),
                        );
                      }).toList(),
                    ),
                  ],
                ),

              // Квалификации
              if (user.qualifications != null && user.qualifications!.isNotEmpty)
                _buildSection(
                  'Квалификации',
                  user.qualifications!.entries.map((entry) {
                    return _buildInfoRow(
                      Icons.school,
                      entry.key,
                      entry.value.toString(),
                    );
                  }).toList(),
                ),

              // Сертификаты
              if (user.certifications != null && user.certifications!.isNotEmpty)
                _buildSection(
                  'Сертификаты',
                  user.certifications!.map((cert) {
                    return ListTile(
                      leading: const Icon(Icons.verified, color: Color(0xFFf59e0b)),
                      title: Text(cert, style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white38),
                    );
                  }).toList(),
                ),

              // Документы
              documentsAsync.when(
                data: (documents) {
                  if (documents.isEmpty) return const SizedBox();
                  return _buildSection(
                    'Документы',
                    documents.map((doc) {
                      return ListTile(
                        leading: const Icon(Icons.description, color: Color(0xFF8b5cf6)),
                        title: Text(
                          doc['name'] ?? 'Документ',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          doc['type'] ?? '',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.download, color: Color(0xFF3b82f6)),
                        onTap: () async {
                          // TODO: Download document
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Скачивание документа...')),
                          );
                        },
                      );
                    }).toList(),
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (_, __) => const SizedBox(),
              ),

              const SizedBox(height: 24),

              // Кнопка выхода
              ElevatedButton.icon(
                onPressed: () async {
                  final authService = AuthService();
                  await authService.logout();
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Выйти'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.2),
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Ошибка: $error', style: const TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Card(
          color: const Color(0xFF1e293b),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}

