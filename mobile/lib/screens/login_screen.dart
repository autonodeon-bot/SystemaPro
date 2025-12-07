import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() => _isLoading = true);

      try {
        final formData = _formKey.currentState!.value;
        final username = formData['username'];
        final password = formData['password'];

        // ВАЖНО: Проверяем, не пытается ли пользователь войти под другим логином
        final currentUser = await _authService.getCurrentUser();
        if (currentUser != null && currentUser.username != username) {
          // Если логин отличается - сначала выходим из старой сессии
          print('⚠️ Обнаружен другой логин. Выходим из старой сессии...');
          await _authService.logout();
        }

        final user = await _apiService.login(username, password);
        // Сохраняем нового пользователя (старый уже удален выше, если был другой)
        await _authService.saveUser(user);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
        }
      } catch (e) {
        if (mounted) {
          String errorMessage = 'Ошибка входа';
          if (e.toString().contains('401') || e.toString().contains('Incorrect')) {
            errorMessage = 'Неверный логин или пароль';
          } else if (e.toString().contains('Connection') || e.toString().contains('Failed')) {
            errorMessage = 'Нет подключения к серверу';
          } else if (e.toString().isNotEmpty) {
            errorMessage = e.toString().replaceAll('Exception: ', '');
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FormBuilder(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Логотип
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3b82f6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'ES',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Заголовок
                  const Text(
                    'ЕС ТД НГО',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Вход в систему',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Поле логина
                  FormBuilderTextField(
                    name: 'username',
                    decoration: InputDecoration(
                      labelText: 'Логин',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.person, color: Colors.white70),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1e293b),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: FormBuilderValidators.required(
                      errorText: 'Введите логин',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Поле пароля
                  FormBuilderTextField(
                    name: 'password',
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white70,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1e293b),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: FormBuilderValidators.required(
                      errorText: 'Введите пароль',
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Кнопка входа
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3b82f6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Войти',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // Подсказка
                  const Text(
                    'Тестовые учетные записи:\nadmin / admin123\nchief_operator / chief123\noperator / operator123\nengineer1 / engineer123',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

