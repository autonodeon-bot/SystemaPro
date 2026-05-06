/// Глобальная конфигурация мобильного приложения.
///
/// Значения берутся из `--dart-define=...` при сборке. Если не заданы —
/// безопасные дефолты (SENTRY_DSN = пусто → Sentry выключен).
class AppConfig {
  AppConfig._();

  /// Базовый URL API без завершающего «/». Сборка: `--dart-define=API_BASE_URL=https://neftcontrol.ru`
  static const String _apiBaseUrlRaw = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://neftcontrol.ru',
  );

  static String get effectiveApiBaseUrl {
    var u = _apiBaseUrlRaw.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u.isEmpty ? 'https://neftcontrol.ru' : u;
  }

  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String sentryEnvironment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'production',
  );
  static const double sentryTracesSampleRate = 0.1;

  static bool get isSentryEnabled => sentryDsn.isNotEmpty;
}
