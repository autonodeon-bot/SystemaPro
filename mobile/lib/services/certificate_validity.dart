/// Dates are compared as calendar dates, including the last valid day.
DateTime? parseCertificateDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final text = value.trim();
  final ru = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(text);
  if (ru != null) {
    final d = int.parse(ru[1]!); final m = int.parse(ru[2]!); final y = int.parse(ru[3]!);
    final date = DateTime(y, m, d);
    return date.year == y && date.month == m && date.day == d ? date : null;
  }
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|T| )').firstMatch(text);
  if (iso == null || DateTime.tryParse(text) == null) return null;
  final y = int.parse(iso[1]!); final m = int.parse(iso[2]!); final d = int.parse(iso[3]!);
  final date = DateTime(y, m, d);
  return date.year == y && date.month == m && date.day == d ? date : null;
}

String? certificateDateWarning(String label, String? expires, String? inspectionDate) {
  final performed = parseCertificateDate(inspectionDate);
  if (performed == null) return null;
  final end = parseCertificateDate(expires);
  if (end == null) return '$label: укажите корректный срок действия';
  if (end.isBefore(performed)) return '$label: срок действия истек до даты обследования';
  return null;
}
