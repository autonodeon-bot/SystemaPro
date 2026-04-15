import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'custom_protocol_screen.dart';

/// Экран выбора шаблона протокола/акта из конструктора (П.1.1.4)
class ProtocolTemplateSelectionScreen extends StatefulWidget {
  const ProtocolTemplateSelectionScreen({super.key});

  @override
  State<ProtocolTemplateSelectionScreen> createState() =>
      _ProtocolTemplateSelectionScreenState();
}

class _ProtocolTemplateSelectionScreenState
    extends State<ProtocolTemplateSelectionScreen> {
  final _apiService = ApiService();
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String? _selectedCategory;

  static const _categories = ['Все', 'ВИК', 'УЗТ', 'УЗК', 'ПВК(МПД)', 'ТД(ЭПБ)', 'Другое'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _apiService.getProtocolTemplates();
      if (mounted) {
        setState(() {
          _templates = List<Map<String, dynamic>>.from(data);
          _applyFilters();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applyFilters() {
    setState(() {
      _filtered = _templates.where((t) {
        final name = (t['name'] as String? ?? '').toLowerCase();
        final cat = (t['category'] as String? ?? '');
        final q = _searchQuery.toLowerCase();
        final matchSearch = q.isEmpty || name.contains(q);
        final matchCat = _selectedCategory == null ||
            _selectedCategory == 'Все' ||
            cat == _selectedCategory;
        return matchSearch && matchCat;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Выбрать шаблон протокола'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Поиск по названию...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0f172a),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.darkPrimary),
                ),
              ),
              onChanged: (v) {
                _searchQuery = v;
                _applyFilters();
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Фильтр категорий
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _categories.length,
              itemBuilder: (ctx, idx) {
                final cat = _categories[idx];
                final isActive = (_selectedCategory ?? 'Все') == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat,
                        style: TextStyle(
                            color: isActive ? Colors.white : Colors.white60,
                            fontSize: 12)),
                    selected: isActive,
                    onSelected: (_) {
                      setState(() => _selectedCategory = cat == 'Все' ? null : cat);
                      _applyFilters();
                    },
                    backgroundColor: const Color(0xFF1e293b),
                    selectedColor: AppColors.darkPrimary.withOpacity(0.3),
                    checkmarkColor: AppColors.darkPrimary,
                    side: BorderSide(
                      color: isActive ? AppColors.darkPrimary : Colors.white24,
                    ),
                  ),
                );
              },
            ),
          ),
          // Список шаблонов
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, color: Colors.white24, size: 56),
            const SizedBox(height: 12),
            const Text(
              'Шаблонов не найдено',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Шаблоны создаются через веб-интерфейс\nв разделе «Конструктор протоколов»',
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filtered.length,
      itemBuilder: (ctx, idx) => _buildTemplateCard(_filtered[idx]),
    );
  }

  Widget _buildTemplateCard(Map<String, dynamic> tmpl) {
    final name = (tmpl['name'] as String?) ?? 'Шаблон';
    final description = (tmpl['description'] as String?) ?? '';
    final category = (tmpl['category'] as String?) ?? '';
    final structure = tmpl['structure'] as List? ?? [];
    final blockCount = structure.length;
    final createdAt = (tmpl['created_at'] as String?) ?? '';
    final createdBy = (tmpl['created_by'] as String?) ?? '';

    return Card(
      color: const Color(0xFF1e293b),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomProtocolScreen(template: tmpl),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.darkPrimary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.darkPrimary.withOpacity(0.3)),
                ),
                child: Icon(Icons.description_outlined, color: AppColors.darkPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                        ),
                        if (category.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.darkPrimary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.darkPrimary.withOpacity(0.4)),
                            ),
                            child: Text(category,
                                style: TextStyle(
                                    color: AppColors.darkPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500)),
                          ),
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(description,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: [
                        _meta(Icons.view_module_outlined, '$blockCount блоков'),
                        if (createdAt.isNotEmpty)
                          _meta(Icons.calendar_today_outlined,
                              _formatDate(createdAt)),
                        if (createdBy.isNotEmpty)
                          _meta(Icons.person_outline, createdBy),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white38),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      );

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
