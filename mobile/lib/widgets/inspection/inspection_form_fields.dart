import '../../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:intl/intl.dart' as intl;

const kInspectionDarkBg = Color(0xFF1e293b);
const kInspectionScaffoldBg = Color(0xFF0f172a);
const kInspectionBorderColor = Color(0xFF334155);
const kInspectionAccentBlue = Color(0xFF2563eb);

Widget buildSectionHeader(String title) {
  return Builder(builder: (context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: kInspectionAccentBlue,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  });
}

Widget buildSubsectionHeader(String title) {
  return Builder(builder: (context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.mutedText(context),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  });
}

InputDecoration _fieldDecoration(BuildContext context, String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: AppColors.mutedText(context)),
    filled: true,
    fillColor: AppColors.surface(context),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.border(context)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.border(context)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: kInspectionAccentBlue, width: 2),
    ),
  );
}

Widget buildInspectionTextField(
  String name,
  String label,
  Function(String?) onChanged, {
  String? initialValue,
}) {
  return Builder(builder: (context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderTextField(
        name: name,
        initialValue: initialValue,
        decoration: _fieldDecoration(context, label),
        style: TextStyle(color: AppColors.onSurface(context)),
        onChanged: onChanged,
      ),
    );
  });
}

Widget buildMultilineField(
    String name, String label, Function(String?) onChanged,
    {String? initialValue}) {
  return Builder(builder: (context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderTextField(
        name: name,
        initialValue: initialValue,
        maxLines: 5,
        decoration: _fieldDecoration(context, label),
        style: TextStyle(color: AppColors.onSurface(context)),
        onChanged: onChanged,
      ),
    );
  });
}

Widget buildDateField(
    String name, String label, Function(DateTime?) onChanged) {
  return Builder(builder: (context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderDateTimePicker(
        name: name,
        inputType: InputType.date,
        format: intl.DateFormat('yyyy-MM-dd'),
        decoration: _fieldDecoration(context, label).copyWith(
          suffixIcon:
              Icon(Icons.calendar_today, color: AppColors.mutedText(context)),
        ),
        style: TextStyle(color: AppColors.onSurface(context)),
        onChanged: onChanged,
      ),
    );
  });
}

Widget buildYesNoField(String name, String label, Function(String?) onChanged) {
  return Builder(builder: (context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderRadioGroup<String>(
        name: name,
        decoration: _fieldDecoration(context, label),
        options: [
          FormBuilderFieldOption(
              value: 'yes',
              child: Text('Да',
                  style: TextStyle(color: AppColors.onSurface(context)))),
          FormBuilderFieldOption(
              value: 'no',
              child: Text('Нет',
                  style: TextStyle(color: AppColors.onSurface(context)))),
        ],
        onChanged: onChanged,
      ),
    );
  });
}

Widget buildDropdownField(
    String name, String label, List<String> items, Function(String?) onChanged,
    {String? initialValue}) {
  return Builder(builder: (context) {
    final opts = List<String>.from(items);
    if (initialValue != null &&
        initialValue.isNotEmpty &&
        !opts.contains(initialValue)) {
      opts.insert(0, initialValue);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderDropdown<String>(
        name: name,
        initialValue: (initialValue != null && opts.contains(initialValue))
            ? initialValue
            : null,
        decoration: _fieldDecoration(context, label),
        // Формулировки заключений НК занимают до ~100 символов и без isExpanded
        // выходят за ширину поля.
        isExpanded: true,
        items: opts
            .map((item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    item,
                    style: TextStyle(color: AppColors.onSurface(context)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
        selectedItemBuilder: (context) => opts
            .map((item) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item,
                    style: TextStyle(color: AppColors.onSurface(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  });
}

/// Показывает диалог подтверждения удаления.
/// Возвращает true если пользователь нажал «Да».
Future<bool> showConfirmDeleteDialog(
  BuildContext context, {
  String title = 'Подтверждение удаления',
  String message = 'Вы уверены? Запись будет удалена.',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Нет'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Да'),
        ),
      ],
    ),
  );
  return result == true;
}

Widget buildListItemCard({
  required String title,
  required String subtitle,
  required VoidCallback onDelete,
  VoidCallback? onTap,
  BuildContext? deleteContext,
}) {
  return Builder(builder: (context) {
    void handleDelete() {
      if (deleteContext != null) {
        showConfirmDeleteDialog(deleteContext).then((confirmed) {
          if (confirmed) onDelete();
        });
      } else {
        onDelete();
      }
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: AppColors.onSurface(context),
                        fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle,
                        style: TextStyle(
                            color: AppColors.mutedText(context), fontSize: 12)),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: handleDelete,
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: 'Удалить',
          ),
        ],
      ),
    );
    return Card(
      color: AppColors.surface(context),
      margin: const EdgeInsets.only(bottom: 8),
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: content,
            )
          : content,
    );
  });
}

Widget buildAddItemButton(String label, VoidCallback onPressed) {
  return Builder(builder: (context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: kInspectionAccentBlue,
          side: const BorderSide(color: kInspectionAccentBlue),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  });
}

Widget buildDialogTextField(
  TextEditingController controller,
  String label, {
  TextInputType keyboard = TextInputType.text,
}) {
  return Builder(builder: (context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        style: TextStyle(color: AppColors.onSurface(context)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppColors.mutedText(context)),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border(context))),
          focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue)),
        ),
      ),
    );
  });
}
