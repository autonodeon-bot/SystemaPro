/// Глобальная конфигурация мобильного приложения.
///
/// Значения берутся из `--dart-define=...` при сборке. Если не заданы —
/// безопасные дефолты (SENTRY_DSN = пусто → Sentry выключен).
class AppConfig {
  AppConfig._();

  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String sentryEnvironment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'production',
  );
  static const double sentryTracesSampleRate = 0.1;

  static bool get isSentryEnabled => sentryDsn.isNotEmpty;
}
