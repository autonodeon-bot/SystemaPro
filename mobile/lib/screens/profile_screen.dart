import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/auth_provider.dart';
import '../models/user.dart';
import 'login_screen.dart';
import 'certifications_screen.dart';

final userDocumentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authService = AuthService();
  final user = await authService.getCurrentUser();
  if (user == null) return [];

  final apiService = ApiService();
  return await apiService.getSpecialistDocuments(user.id);
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  File? _profilePhoto;
  bool _isEditing = false;
  bool _isUploading = false;
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _fullNameController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData(User user) async {
    _phoneController.text = user.phone ?? '';
    _emailController.text = user.email ?? '';
    _fullNameController.text = user.fullName;
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          title: const Text('Выберите источник', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF3b82f6)),
                title: const Text('Камера', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF3b82f6)),
                title: const Text('Галерея', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _profilePhoto = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора фото: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadNDTDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isUploading = true);

        final authService = AuthService();
        final user = await authService.getCurrentUser();
        if (user == null) return;

        final apiService = ApiService();
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;

        // Загружаем документ через API
        await apiService.uploadNDTDocument(
          userId: user.id,
          file: file,
          fileName: fileName,
          documentType: 'ndt_certificate',
        );

        // Обновляем список документов
        ref.invalidate(userDocumentsProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Документ успешно загружен'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки документа: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _saveProfile(User user) async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() => _isUploading = true);

      final authService = AuthService();
      final apiService = ApiService();
      final token = await authService.getToken();

      // Обновляем профиль через API
      final updatedUser = await apiService.updateUserProfile(
        userId: user.id,
        phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
        email: _emailController.text.isNotEmpty ? _emailController.text : null,
        fullName: _fullNameController.text,
        photo: _profilePhoto,
        token: token ?? '',
      );

      // Обновляем локально сохраненного пользователя
      if (updatedUser != null) {
        await authService.saveUser(updatedUser);
        ref.invalidate(currentUserProvider);
      }

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Профиль успешно обновлен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления профиля: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final documentsAsync = ref.watch(userDocumentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Личный кабинет'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                userAsync.whenData((user) {
                  if (user != null) {
                    _loadUserData(user);
                    setState(() => _isEditing = true);
                  }
                });
              },
              tooltip: 'Редактировать профиль',
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _profilePhoto = null;
                });
              },
              tooltip: 'Отменить редактирование',
            ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(
              child: Text('Пользователь не найден', style: TextStyle(color: Colors.white)),
            );
          }

          if (!_isEditing && _phoneController.text.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadUserData(user);
            });
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(currentUserProvider);
              ref.invalidate(userDocumentsProvider);
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Профиль
                Card(
                  color: const Color(0xFF1e293b),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _isEditing ? _pickProfilePhoto : null,
                          child: Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3b82f6),
                                  borderRadius: BorderRadius.circular(50),
                                  image: _profilePhoto != null
                                      ? DecorationImage(
                                          image: FileImage(_profilePhoto!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: _profilePhoto == null
                                    ? Center(
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
                                      )
                                    : null,
                              ),
                              if (_isEditing)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF3b82f6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_isEditing)
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _fullNameController,
                                  decoration: InputDecoration(
                                    labelText: 'ФИО',
                                    labelStyle: const TextStyle(color: Colors.white70),
                                    filled: true,
                                    fillColor: const Color(0xFF0f172a),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Введите ФИО';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _phoneController,
                                  decoration: InputDecoration(
                                    labelText: 'Телефон',
                                    labelStyle: const TextStyle(color: Colors.white70),
                                    filled: true,
                                    fillColor: const Color(0xFF0f172a),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  keyboardType: TextInputType.phone,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _emailController,
                                  decoration: InputDecoration(
                                    labelText: 'Email',
                                    labelStyle: const TextStyle(color: Colors.white70),
                                    filled: true,
                                    fillColor: const Color(0xFF0f172a),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) {
                                    if (value != null && value.isNotEmpty) {
                                      if (!value.contains('@')) {
                                        return 'Введите корректный email';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isUploading ? null : () => _saveProfile(user),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF3b82f6),
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                    child: _isUploading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Сохранить изменения'),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Column(
                            children: [
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
                                      user.getRoleLabel(),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    backgroundColor:
                                        const Color(0xFF3b82f6).withOpacity(0.2),
                                    labelStyle:
                                        const TextStyle(color: Color(0xFF3b82f6)),
                                  ),
                                ],
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
                if (user.equipmentTypes != null &&
                    user.equipmentTypes!.isNotEmpty)
                  _buildSection(
                    'Специализация',
                    [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: user.equipmentTypes!.map((type) {
                          return Chip(
                            label: Text(type),
                            backgroundColor:
                                const Color(0xFF10b981).withOpacity(0.2),
                            labelStyle: const TextStyle(color: Color(0xFF10b981)),
                          );
                        }).toList(),
                      ),
                    ],
                  ),

                // Квалификации
                if (user.qualifications != null &&
                    user.qualifications!.isNotEmpty)
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
                _buildSection(
                  'Сертификаты',
                  [
                    ListTile(
                      leading:
                          const Icon(Icons.verified, color: Color(0xFFf59e0b)),
                      title: const Text(
                        'Просмотр сертификатов',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Мои сертификаты и допуски',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios,
                          size: 16, color: Colors.white38),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CertificationsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                // Документы по НК
                _buildSection(
                  'Документы по неразрушающему контролю',
                  [
                    ListTile(
                      leading: const Icon(Icons.upload_file, color: Color(0xFF3b82f6)),
                      title: const Text(
                        'Загрузить документ по НК',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Сертификаты, допуски, удостоверения',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      trailing: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_ios,
                              size: 16, color: Colors.white38),
                      onTap: _isUploading ? null : _uploadNDTDocument,
                    ),
                  ],
                ),

                // Документы
                documentsAsync.when(
                  data: (documents) {
                    if (documents.isEmpty) return const SizedBox();
                    return _buildSection(
                      'Мои документы',
                      documents.map((doc) {
                        return ListTile(
                          leading: const Icon(Icons.description,
                              color: Color(0xFF8b5cf6)),
                          title: Text(
                            doc['name'] ?? 'Документ',
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            doc['type'] ?? '',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.download,
                              color: Color(0xFF3b82f6)),
                          onTap: () async {
                            // TODO: Download document
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Скачивание документа...')),
                              );
                            }
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

                const SizedBox(height: 16),

                // Версия приложения
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final packageInfo = snapshot.data!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'Версия приложения: ${packageInfo.version} (${packageInfo.buildNumber})',
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

                const SizedBox(height: 16),

                // Кнопка выхода - исправлена для видимости
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF1e293b),
                            title: const Text(
                              'Выход из системы',
                              style: TextStyle(color: Colors.white),
                            ),
                            content: const Text(
                              'Вы уверены, что хотите выйти?',
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Выйти'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          final authService = AuthService();
                          await authService.logout();
                          if (mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const LoginScreen()),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Выйти'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.2),
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Ошибка: $error',
              style: const TextStyle(color: Colors.white70)),
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
