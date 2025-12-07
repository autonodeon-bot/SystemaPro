import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline_package_provider.dart';
import '../services/offline_auth_provider.dart';
import '../services/sync_provider.dart';
import '../database/app_database.dart';
import '../services/api_service.dart';
import 'dart:io';

/// Экран для управления офлайн-заданиями (командировками)
class OfflineTasksScreen extends ConsumerStatefulWidget {
  const OfflineTasksScreen({super.key});

  @override
  ConsumerState<OfflineTasksScreen> createState() => _OfflineTasksScreenState();
}

class _OfflineTasksScreenState extends ConsumerState<OfflineTasksScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      final token = await _apiService.getToken();
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Требуется авторизация')),
          );
        }
        return;
      }

      // TODO: Реализовать получение списка заданий с сервера
      // final response = await http.get(...);
      // _tasks = ...;

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки заданий: $e')),
        );
      }
    }
  }

  Future<void> _downloadPackage(Map<String, dynamic> task) async {
    // Показываем диалог для ввода PIN
    final pinController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Скачать offline-пакет'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Введите офлайн-PIN для шифрования пакета:'),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'PIN (6-8 цифр)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Скачать'),
          ),
        ],
      ),
    );

    if (confirmed != true || pinController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      // TODO: Реализовать скачивание пакета
      // final packageProvider = OfflinePackageProvider(database);
      // await packageProvider.downloadOfflinePackage(...);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пакет успешно скачан')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка скачивания: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Офлайн-задания'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTasks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? const Center(
                  child: Text('Нет доступных офлайн-заданий'),
                )
              : ListView.builder(
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) {
                    final task = _tasks[index];
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        title: Text(task['name'] ?? 'Без названия'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Оборудование: ${task['equipment_count'] ?? 0}'),
                            if (task['expires_at'] != null)
                              Text(
                                'Срок действия: ${task['expires_at']}',
                                style: TextStyle(
                                  color: _isExpired(task['expires_at'])
                                      ? Colors.red
                                      : null,
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () => _downloadPackage(task),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  bool _isExpired(String? expiresAt) {
    if (expiresAt == null) return false;
    try {
      final expires = DateTime.parse(expiresAt);
      return expires.isBefore(DateTime.now());
    } catch (e) {
      return false;
    }
  }
}

