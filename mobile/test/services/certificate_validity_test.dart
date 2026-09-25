import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/certificate_validity.dart';

void main() {
  test('validity uses inspection day, not current day', () {
    expect(certificateDateWarning('Прибор', '18.09.2025', '2025-09-18'), isNull);
    expect(certificateDateWarning('Прибор', '17.09.2025', '2025-09-18'), contains('истек'));
    expect(certificateDateWarning('Прибор', null, '2025-09-18'), contains('срок'));
    expect(parseCertificateDate('31.02.2025'), isNull);
    expect(parseCertificateDate('2025-02-31'), isNull);
    expect(parseCertificateDate('2025-09-18T23:00:00-03:00'), DateTime(2025, 9, 18));
  });
}
