import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

final certificationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authService = AuthService();
  final user = await authService.getCurrentUser();
  if (user == null) return [];
  
  // Используем engineer_id из пользователя, если есть, иначе используем id пользователя
  final engineerId = user.engineerId ?? user.id;
  if (engineerId.isEmpty) return [];
  
  final apiService = ApiService();
  return await apiService.getSpecialistCertifications(engineerId);
});

class CertificationsScreen extends ConsumerWidget {
  const CertificationsScreen({super.key});

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Не указана';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  bool _isExpired(String? expiryDate) {
    if (expiryDate == null || expiryDate.isEmpty) return false;
    try {
      return DateTime.parse(expiryDate).isBefore(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  bool _isExpiringSoon(String? expiryDate, {int days = 90}) {
    if (expiryDate == null || expiryDate.isEmpty) return false;
    try {
      final expiry = DateTime.parse(expiryDate);
      final now = DateTime.now();
      final diff = expiry.difference(now).inDays;
      return diff > 0 && diff <= days;
    } catch (e) {
      return false;
    }
  }

  int _daysUntilExpiry(String? expiryDate) {
    if (expiryDate == null || expiryDate.isEmpty) return 0;
    try {
      final expiry = DateTime.parse(expiryDate);
      final now = DateTime.now();
      return expiry.difference(now).inDays;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certificationsAsync = ref.watch(certificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои сертификаты'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: certificationsAsync.when(
        data: (certifications) {
          if (certifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 64,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Сертификаты не найдены',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(certificationsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: certifications.length,
              itemBuilder: (context, index) {
                final cert = certifications[index];
                final isExpired = _isExpired(cert['expiry_date']);
                final isExpiringSoon = _isExpiringSoon(cert['expiry_date']);
                final daysLeft = _daysUntilExpiry(cert['expiry_date']);

                return Card(
                  color: const Color(0xFF1e293b),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: Icon(
                      isExpired
                          ? Icons.error_outline
                          : isExpiringSoon
                              ? Icons.warning_amber_rounded
                              : Icons.verified,
                      color: isExpired
                          ? Colors.red
                          : isExpiringSoon
                              ? Colors.orange
                              : Colors.green,
                      size: 28,
                    ),
                    title: Text(
                      cert['certification_type'] ?? 'Сертификат',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (cert['method'] != null)
                          Text(
                            '${cert['method']} ${cert['level'] != null ? '- Уровень ${cert['level']}' : ''}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                        if (cert['number'] != null)
                          Text(
                            '№ ${cert['number']}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    trailing: isExpired
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Просрочен',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : isExpiringSoon
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Истекает через $daysLeft дн.',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(
                              'Выдан организацией',
                              cert['issued_by'] ?? 'Не указано',
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'Дата выдачи',
                              _formatDate(cert['issue_date']),
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'Действителен до',
                              _formatDate(cert['expiry_date']),
                              isExpired
                                  ? Colors.red
                                  : isExpiringSoon
                                      ? Colors.orange
                                      : Colors.green,
                            ),
                            if (cert['file_path'] != null) ...[
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  // TODO: Download certificate file
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Скачивание сертификата...'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.download),
                                label: const Text('Скачать документ'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3b82f6),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
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
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Ошибка загрузки сертификатов',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

