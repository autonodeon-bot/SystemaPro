/**
 * Sentry init для фронтенда.
 *
 * Включается, если задано `VITE_SENTRY_DSN` в build-окружении.
 * В dev-режиме (`import.meta.env.DEV`) Sentry выключен, чтобы не засорять проект.
 */
import * as Sentry from '@sentry/react';

export function initSentry() {
  const dsn = import.meta.env.VITE_SENTRY_DSN as string | undefined;
  if (!dsn || import.meta.env.DEV) return;

  const environment = (import.meta.env.VITE_SENTRY_ENVIRONMENT as string) || 'production';
  const release = (import.meta.env.VITE_APP_VERSION as string) || undefined;

  Sentry.init({
    dsn,
    environment,
    release,
    tracesSampleRate: Number(import.meta.env.VITE_SENTRY_TRACES_SAMPLE_RATE ?? '0.1'),
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({ maskAllText: true, blockAllMedia: true }),
    ],
    replaysSessionSampleRate: 0.0,
    replaysOnErrorSampleRate: 0.5,
  });
}

/** ErrorBoundary-friendly обёртка над captureException. */
export function reportError(error: unknown, context?: Record<string, unknown>) {
  try {
    if (context) Sentry.setContext('app', context);
    Sentry.captureException(error);
  } catch {
    // swallow — fallback на console
    // eslint-disable-next-line no-console
    console.error('reportError failed', error);
  }
}
