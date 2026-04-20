# ADR 0001. Observability stack: Sentry + Prometheus + loguru

- **Status:** Accepted
- **Date:** 2026-04-19
- **Context:** До версии 3.30 инциденты (500-е, падения фоновых задач,
  застрявшие подписания) отлавливались по жалобам пользователей. Логи
  хранились только в stdout контейнера, ротации не было, корреляции между
  event-логом, трейсом и метрикой не существовало.

## Решение

1. **Sentry** — как источник истины для ошибок и трейсов.
   - FastAPI / SQLAlchemy / Asyncio integrations.
   - Релизы маркируются `APP_VERSION` (sentry release tracking).
   - PII по умолчанию выключен (`send_default_pii=False`).
2. **Prometheus** — для числовых метрик и SLA.
   - Стандартный `prometheus_client`.
   - Кастомные метрики: `http_requests_total`, `http_request_duration_seconds`,
     `report_generation_seconds`, `auth_login_total{result=...}`.
   - Endpoint: `GET /metrics` (сам FastAPI, через `metrics_router`).
3. **loguru** — структурированные логи.
   - JSON-режим (`LOG_JSON=1`) — для продакшена, агрегируется любым log-shipper.
   - Текстовый (цветной) режим — для локальной разработки.
   - `uvicorn.*` перенаправляется в loguru через `InterceptHandler`.

## Что НЕ выбрали и почему

- **OpenTelemetry**: богаче, но требует отдельного коллектора. Sentry даёт
  достаточно трейсов на текущем масштабе (1 backend-инстанс, 5-50 RPS).
- **ELK/Loki**: на текущем размере (один контейнер backend) — излишне.
  `docker logs` + Sentry достаточно; при росте нагрузки поверх JSON-логов
  легко навесить Loki, менять код не придётся.
- **StatsD/InfluxDB**: Prometheus — индустриальный стандарт; легко
  интегрируется с Grafana, алерт-правилами и Kubernetes.

## Последствия

- Новая зависимость на `SENTRY_DSN` (но модуль работает и без неё).
- `/metrics` стал Prometheus-форматом; старый JSON переехал в `/metrics/legacy`.
- Появился `/ready` endpoint для k8s/monitoring.
- Повышены требования к ENV: см. `deploy-ssh.ps1` и `.env` на сервере.
