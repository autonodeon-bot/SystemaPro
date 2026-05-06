# Монитор — SystemaPro (ЕС ТД НГО)

Единая система технической диагностики нефтегазового оборудования.
Веб-платформа для экспертных организаций, инженеров-дефектоскопистов
и заказчиков (добывающие/перерабатывающие предприятия).

- **Production:** https://neftcontrol.ru
- **API docs:** https://neftcontrol.ru/api/docs
- **Репозиторий:** внутренний (DIATEKS)

## Возможности

- Иерархия Предприятие → Филиал → Цех → ОПО → Оборудование.
- Задания на обследования: назначение, распределение, выполнение, архив.
- Опросные листы, чек-листы НК (ВИК, УЗТ, УЗК, МПД, ЦД).
- Шаблоны протоколов и чертежей с предопределёнными точками замера.
- Доменный движок расчётов: РД 09-539-03 (остаточный ресурс), СА 03-008-08 (ЭПБ сосудов).
- Генерация отчётов в PDF/Word, QR-штамп и публичная верификация подлинности.
- Мобильное приложение (Flutter) для выезжающих инженеров: offline-режим,
  фоновая синхронизация, биометрия, push-уведомления.
- RBAC (admin / chief_operator / engineer / client), 2FA TOTP,
  блокировка при переборе пароля.
- Наблюдаемость: Sentry + Prometheus `/metrics` + structured logging (loguru).

## Архитектура (коротко)

- **Frontend (web):** React 18 + TypeScript + Vite + Tailwind, собственный
  industrial-design system (`sp-surface`, `sp-stat`, `ind-*` классы), тёмная
  тема по умолчанию. Лента ~250 tsx-файлов.
- **Backend:** FastAPI (Python 3.11), SQLAlchemy 2 (async) + asyncpg,
  PostgreSQL, Alembic. ~30 роутеров, декомпозированных из `main.py`.
- **Mobile:** Flutter 3.x, `go_router`, `sqflite`, `workmanager`,
  `firebase_messaging`, `local_auth`, APK публикуется внутри образа frontend.
- **Infra:** Docker Compose (backend + frontend), nginx как reverse-proxy +
  TLS (Let's Encrypt). Deploy одним PowerShell-скриптом (`deploy-ssh.ps1`).

```
┌─ client browser ──┐       ┌─ mobile (Flutter) ──┐
│ neftcontrol.ru    │       │ offline-first       │
└────┬──────────────┘       └────┬────────────────┘
     │ https                     │ https
     ▼                           ▼
┌───────────────────────────────────────────────┐
│ nginx  (TLS, HSTS, rate-limit) — frontend img │
└────┬──────────────────────────────────────────┘
     │ /api/*
     ▼
┌───────────────────────────────────────────────┐
│ FastAPI  (main.py + routers)                  │
│  ├─ auth / 2FA / RBAC                         │
│  ├─ domain: diagnostic_engine/                │
│  ├─ reports + pdf_stamping + verify           │
│  └─ observability (Sentry, Prom, loguru)      │
└────┬──────────────────────────────────────────┘
     │
     ▼
┌───────────────┐   ┌──────────────────────────┐
│ PostgreSQL 15 │   │ filesystem: uploads/,     │
│               │   │ reports/, certs/          │
└───────────────┘   └──────────────────────────┘
```

## Быстрый старт (локально)

### Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
# создайте .env (см. .env.example)
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Swagger UI: http://localhost:8000/docs.

### Frontend

```powershell
npm ci
npm run dev                 # vite dev server :5173
# production build:
npm run build
```

### Mobile (Flutter)

```powershell
cd mobile
flutter pub get
flutter run                 # эмулятор или подключённое устройство
# release APK:
flutter build apk --release
```

### Тесты

```powershell
# backend
cd backend
pytest -q

# frontend типы
npx tsc -p tsconfig.json --noEmit

# mobile
cd mobile
flutter analyze
```

## Переменные окружения (основные)

| Переменная                | Где нужно  | Описание                                           |
| ------------------------- | ---------- | -------------------------------------------------- |
| `DATABASE_URL`            | backend    | `postgresql+asyncpg://user:pass@host:5432/db`      |
| `JWT_SECRET_KEY`          | backend    | **Обязательно сменить в проде**                    |
| `CORS_ORIGINS`            | backend    | CSV списки разрешённых origin                      |
| `SENTRY_DSN`              | backend/fe | Если пусто — Sentry отключён                       |
| `SENTRY_ENVIRONMENT`      | backend/fe | `production` / `staging` / `local`                 |
| `LOG_LEVEL`, `LOG_JSON`   | backend    | `INFO` / `1` для JSON-логов                        |
| `AUTH_RATE_LIMIT`         | backend    | `10/minute` (slowapi syntax)                       |
| `TOTP_ISSUER`             | backend    | Имя, отображаемое в Authenticator                  |
| `PADES_ENABLED`           | backend    | `1` → подписание PAdES-T (требует сертификат)      |
| `SMTP_HOST`/`_PORT`/...`  | backend    | Если пусто — email-service работает dry-run        |

Полный пример — в `.env.example`.

## Deploy

Один скрипт — `deploy-ssh.ps1`. Выполнение:

```powershell
pwsh .\deploy-ssh.ps1
```

Скрипт:
1. Копирует на VPS исходники (без `node_modules`, `mobile`, uploads —
   см. `.dockerignore`);
2. Собирает `backend` и `frontend` образы (последовательно — bypass OOM на
   малых VPS);
3. Перезапускает compose-стек, ждёт healthcheck `/health`.

Staging: добавить `-f docker-compose.staging.yml`, см. ADR 0001.

## Документация

- `docs/adr/` — архитектурные решения.
- `.cursor/rules/` — правила разработки (frontend, backend, mobile, security...).
- Swagger — `/api/docs`.

## Версия

Текущая — **3.30.2** (см. `constants.ts`, `backend/main.py`,
`mobile/pubspec.yaml`).
