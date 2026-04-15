# Skill: Создание нового экрана (Mobile Flutter)

## Описание
Создание нового экрана для мобильного приложения «Монитор» на Flutter.

## Когда использовать
- Пользователь просит добавить новый экран в мобильное приложение
- Нужна новая функциональность в mobile app

## Шаги выполнения

### 1. Создать файл экрана `mobile/lib/screens/new_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class NewScreen extends ConsumerStatefulWidget {
  const NewScreen({super.key});

  @override
  ConsumerState<NewScreen> createState() => _NewScreenState();
}

class _NewScreenState extends ConsumerState<NewScreen> {
  final _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() { _isLoading = true; _error = null; });
      // final data = await _apiService.getItems();
      // setState(() { _items = data; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Название экрана'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _buildBody(isDark),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text('Нет данных'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (context, index) => _buildItem(_items[index], isDark),
      ),
    );
  }

  Widget _buildItem(dynamic item, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(item['name'] ?? ''),
        subtitle: Text(item['description'] ?? ''),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _onItemTap(item),
      ),
    );
  }

  void _onItemTap(dynamic item) {
    // Навигация или действие
  }

  void _showAddDialog() {
    // Диалог добавления
  }
}
```

### 2. Добавить навигацию

В `dashboard_screen.dart` или другом экране добавить навигацию:
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const NewScreen()),
);
```

### 3. API метод (если нужен)

В `mobile/lib/services/api_service.dart` добавить:
```dart
Future<List<dynamic>> getNewItems() async {
  await ensureValidToken();
  final response = await _dio.get('/api/new-items');
  return response.data as List;
}
```

### 4. Модель данных (если нужна)

Создать `mobile/lib/models/new_model.dart`:
```dart
class NewModel {
  final String id;
  final String name;

  NewModel({required this.id, required this.name});

  factory NewModel.fromJson(Map<String, dynamic> json) {
    return NewModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
  };
}
```

### 5. Офлайн поддержка (если нужна)

В `sync_service.dart` добавить синхронизацию для нового типа данных.

### Чек-лист
- [ ] Экран создан в `screens/`
- [ ] Навигация работает
- [ ] API метод добавлен в `api_service.dart`
- [ ] Модель данных создана (если нужна)
- [ ] Поддержка тёмной темы
- [ ] Состояние загрузки (CircularProgressIndicator)
- [ ] Обработка ошибок
- [ ] Pull-to-refresh
