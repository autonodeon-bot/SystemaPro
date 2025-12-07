import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import 'auth_service.dart';

// Провайдер для текущего пользователя
final currentUserProvider = FutureProvider<User?>((ref) async {
  final authService = AuthService();
  return await authService.getCurrentUser();
});

// Провайдер для проверки роли
final userRoleProvider = Provider<String>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    data: (user) => user?.role ?? 'engineer',
    loading: () => 'engineer',
    error: (_, __) => 'engineer',
  );
});

// Провайдер для проверки прав доступа
final userPermissionsProvider = Provider<List<String>>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    data: (user) {
      if (user == null) return [];
      // Админ имеет все права
      if (user.role == 'admin') {
        return ['manage_users', 'manage_equipment', 'manage_projects', 'view_all', 'manage_access'];
      }
      // Главный оператор
      if (user.role == 'chief_operator') {
        return ['manage_equipment', 'manage_projects', 'view_all', 'manage_access'];
      }
      // Оператор
      if (user.role == 'operator') {
        return ['manage_equipment', 'view_all', 'manage_access'];
      }
      // Инженер - только просмотр своего оборудования
      if (user.role == 'engineer') {
        return ['view_own_equipment', 'create_inspections', 'view_own_certifications'];
      }
      return [];
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// Хелпер функции для проверки роли и прав
class AuthHelper {
  static bool hasRole(User? user, String role) {
    if (user == null) return false;
    return user.role.toLowerCase() == role.toLowerCase();
  }

  static bool hasAnyRole(User? user, List<String> roles) {
    if (user == null) return false;
    return roles.any((role) => user.role.toLowerCase() == role.toLowerCase());
  }

  static bool hasPermission(User? user, String permission) {
    if (user == null) return false;
    // Админ имеет все права
    if (user.role == 'admin') return true;
    
    // Главный оператор
    if (user.role == 'chief_operator') {
      return ['manage_equipment', 'manage_projects', 'view_all', 'manage_access'].contains(permission);
    }
    
    // Оператор
    if (user.role == 'operator') {
      return ['manage_equipment', 'view_all', 'manage_access'].contains(permission);
    }
    
    // Инженер
    if (user.role == 'engineer') {
      return ['view_own_equipment', 'create_inspections', 'view_own_certifications'].contains(permission);
    }
    
    return false;
  }

  static bool canManageUsers(User? user) {
    return hasRole(user, 'admin');
  }

  static bool canManageEquipment(User? user) {
    return hasAnyRole(user, ['admin', 'chief_operator', 'operator']);
  }

  static bool canManageAccess(User? user) {
    return hasAnyRole(user, ['admin', 'chief_operator', 'operator']);
  }

  static bool canViewAll(User? user) {
    return hasAnyRole(user, ['admin', 'chief_operator', 'operator']);
  }

  static bool isEngineer(User? user) {
    return hasRole(user, 'engineer');
  }

  static bool isAdmin(User? user) {
    return hasRole(user, 'admin');
  }

  static bool isOperator(User? user) {
    return hasAnyRole(user, ['admin', 'chief_operator', 'operator']);
  }
}





