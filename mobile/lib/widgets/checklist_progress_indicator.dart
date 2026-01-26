import 'package:flutter/material.dart';

/// Виджет для отображения прогресса заполнения чек-листа
class ChecklistProgressIndicator extends StatelessWidget {
  final int completedFields;
  final int totalFields;
  final List<String>? missingRequiredFields;

  const ChecklistProgressIndicator({
    super.key,
    required this.completedFields,
    required this.totalFields,
    this.missingRequiredFields,
  });

  double get progress => totalFields > 0 ? completedFields / totalFields : 0.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: progress >= 1.0 ? Colors.green : Colors.orange,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Прогресс заполнения',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: progress >= 1.0 ? Colors.green : Colors.orange,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 1.0 ? Colors.green : Colors.orange,
            ),
            minHeight: 8,
          ),
          const SizedBox(height: 8),
          Text(
            '$completedFields из $totalFields полей заполнено',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
          if (missingRequiredFields != null && missingRequiredFields!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[900]?.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red[300], size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Не заполнены обязательные поля:',
                        style: TextStyle(
                          color: Colors.red[300],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ...missingRequiredFields!.take(3).map((field) => Padding(
                        padding: const EdgeInsets.only(left: 20, top: 2),
                        child: Text(
                          '• $field',
                          style: TextStyle(
                            color: Colors.red[200],
                            fontSize: 11,
                          ),
                        ),
                      )),
                  if (missingRequiredFields!.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 2),
                      child: Text(
                        '... и еще ${missingRequiredFields!.length - 3}',
                        style: TextStyle(
                          color: Colors.red[200],
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
