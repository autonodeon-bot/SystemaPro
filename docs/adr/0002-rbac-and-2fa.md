# ADR 0002. Unified RBAC matrix + TOTP 2FA

- **Status:** Accepted
- **Date:** 2026-04-19

## Контекст

До 3.30 проверка прав была размазана: где-то проверялась роль строкой, где-то
`permission` из `USERS_DB`, где-то вообще отсутствовала. Для безопасности
нужна единая точка правды. Параллельно — ужесточение входа: бэкенд-админ,
подписант отчёта и инженер-оператор не должны входить только по паролю.

## Решение

### RBAC
- Матрица `PERMISSION_MATRIX: dict[str, set[str]]` в `backend/security.py`.
- Одна dependency-фабрика: `require_rbac("reports.sign")`.
- Fail-closed: неизвестный permission → доступ только admin.
- Старый `require_permission` из `auth.py` остаётся для обратной совместимости,
  постепенно мигрируем endpoint'ы на `require_rbac`.

### 2FA (TOTP)
- RFC 6238 (совместимо с Google / Yandex / Microsoft Authenticator).
- Секреты — в `users.totp_secret` (base32), активация — `users.totp_enabled`.
- 8 recovery-кодов, хранятся как sha256 (оригинал показывается один раз).
- Workflow:
  1. `POST /api/auth/2fa/setup` → secret + QR (base64 PNG) + otpauth URI
  2. `POST /api/auth/2fa/enable` → подтверждение, получение recovery-кодов
  3. `POST /api/auth/login` → если 2FA вкл., возвращает `two_factor_required`
  4. `POST /api/auth/2fa/verify` → выдаёт access_token
- Rate limit на /verify: 5/min (защита от перебора кодов).

### Блокировка аккаунта
- `users.failed_login_count` + `users.locked_until`.
- 5 провалов подряд → блок на 15 минут.
- Ответ: HTTP 423 Locked.

## Последствия

- Миграция добавляет 5 новых колонок в `users`.
- JWT claim `amr: ["pwd"]` или `["pwd","totp"]` — можно проверять на
  sensitive endpoints, если нужна gotta-have-2FA политика.
