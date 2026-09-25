import 'package:flutter/material.dart';

class InspectionSectionNavigator extends StatefulWidget {
  const InspectionSectionNavigator({super.key, required this.labels, required this.currentPage,
    required this.onSelected, this.missingByPage = const {}});
  final List<String> labels;
  final int currentPage;
  final ValueChanged<int> onSelected;
  final Map<int, int> missingByPage;
  @override
  State<InspectionSectionNavigator> createState() => _InspectionSectionNavigatorState();
}

class _InspectionSectionNavigatorState extends State<InspectionSectionNavigator> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final visible = widget.labels.asMap().entries.where((entry) => entry.value.toLowerCase().contains(query.toLowerCase())).toList();
    return SafeArea(child: LayoutBuilder(builder: (context, constraints) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SizedBox(height: (constraints.maxHeight - MediaQuery.viewInsetsOf(context).bottom - 32)
          .clamp(0.0, MediaQuery.sizeOf(context).height * .7), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Разделы отчёта', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(decoration: const InputDecoration(labelText: 'Найти раздел', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            onChanged: (value) => setState(() => query = value)),
          const SizedBox(height: 8),
          Expanded(child: visible.isEmpty ? const Center(child: Text('Разделы не найдены')) : ListView(
            children: visible.map((entry) {
              final missing = widget.missingByPage[entry.key] ?? 0;
              return ListTile(
                selected: entry.key == widget.currentPage,
                title: Text(entry.value),
                subtitle: missing > 0 ? Text('Обязательных полей осталось: $missing') : null,
                leading: CircleAvatar(child: Text('${entry.key + 1}')),
                trailing: entry.key == widget.currentPage ? const Icon(Icons.chevron_right) : null,
                onTap: () => widget.onSelected(entry.key),
              );
            }).toList(),
          )),
        ],
      )),
    )));
  }
}
