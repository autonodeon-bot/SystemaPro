# Анализ кодовой базы SystemaPro (ES ТД НГО)

**Дата анализа:** 28.01.2025  
**Версия системы:** 3.12.0 (package.json) / 3.15.0 (UI, backend)

---

## 1. Общее описание системы

**Название:** Единая цифровая платформа «ТД НГО» (техническое диагностирование, нефтегазовое оборудование).

**Назначение:** Учёт оборудования, обследования/инспекции, задания инженерам, иерархия предприятий → филиалы → цеха → ОПО → оборудование, поверки СИ, компетенции, отчёты (DOCX/PDF), мобильное приложение с офлайн-режимом.

**Стек:**
- **Frontend:** React 18, TypeScript, Vite 5, Tailwind CSS, React Router (HashRouter), Lucide React, Leaflet, Recharts.
- **Backend:** FastAPI, SQLAlchemy (async + asyncpg), PostgreSQL (удалённая БД с SSL), JWT (python-jose), bcrypt.
- **Mobile:** Flutter (отдельная папка `mobile/`).
- **Инфраструктура:** Docker (backend + frontend nginx), удалённая PostgreSQL.

---

## 2. Структура проекта

```
SystemaPro/
├── App.tsx, index.tsx, index.html    # Точки входа React
├── vite.config.ts, tailwind.config.js, tsconfig.json
├── package.json                      # Версия 3.12.0
├── constants.ts                      # API_BASE, мок-данные, схемы (VESSEL_SCHEMA, HIERARCHY_TREE)
├── types.ts                          # Типы: EquipmentType, RiskLevel, HierarchyNode, InspectionTask и др.
├── contexts/
│   ├── AuthContext.tsx               # JWT, login/logout, hasRole/hasPermission
│   └── ThemeContext.tsx              # Тема (светлая/тёмная)
├── components/
│   └── ProtectedRoute.tsx            # Защита маршрутов по роли/правам
├── pages/                            # Страницы приложения (см. раздел 4)
├── backend/
│   ├── main.py                       # FastAPI app, ~10k+ строк, 146+ эндпоинтов
│   ├── database.py                   # Async SQLAlchemy, SSL к PostgreSQL
│   ├── models.py                     # SQLAlchemy модели (Equipment, User, Inspection, Report и др.)
│   ├── auth.py                       # JWT, hash/verify password, USERS_DB fallback
│   ├── report_generator.py           # Генерация отчётов
│   ├── access_management.py         # Роутер: доступ пользователей к объектам
│   ├── hierarchy_management.py      # Роутер: иерархия enterprises/branches/workshops/equipment
│   ├── assignments_api.py           # Роутер: задания
│   ├── report_templates_api.py      # Роутер: шаблоны отчётов
│   ├── equipment_history_api.py     # Роутер: история оборудования
│   ├── Dockerfile, requirements.txt
│   └── Множество миграций/скриптов  # create_*, add_*, fix_*, init_*
├── mobile/                           # Flutter: экраны, синхронизация, офлайн
├── docker-compose.yml                # backend:8000, frontend:80
├── frontend.Dockerfile
└── Документация: README, DATABASE-INFO, RBAC-SYSTEM, DEVELOPMENT-PROPOSALS и др.
```

---

## 3. Backend (FastAPI)

### 3.1 Роутеры (вынесены из main.py)

| Роутер | Файл | Назначение |
|--------|------|------------|
| auth_router | auth_api.py | Логин, /api/auth/me |
| access_router | access_management.py | Управление доступом пользователей |
| hierarchy_router | hierarchy_management.py | Предприятия, филиалы, цеха, оборудование, назначение инженеров |
| assignments_router | assignments_api.py | Задания на обследование |
| report_templates_router | report_templates_api.py | Шаблоны отчётов (CRUD) |
| equipment_history_router | equipment_history_api.py | История оборудования |

### 3.2 Основная логика в main.py

- Около **146 эндпоинтов** (`@app.get/post/put/delete/patch`).
- Подключение к БД: `database.get_db`, SSL к удалённому PostgreSQL (см. DATABASE-INFO.md).
- Авторизация: `verify_token`, `verify_token_optional` из `auth.py`.
- При старте: проверка БД, создание таблиц, авто-миграции (добавление колонок: `equipment_resources.resource_type`, `equipment.opo_id`, `inspections.is_archived` и др.).
- Основные группы API (по префиксам):
  - `/api/auth` — логин, /me
  - `/api/users` — пользователи
  - `/api/equipment`, `/api/equipment-types` — оборудование и типы
  - `/api/hierarchy/*` — предприятия, филиалы, цеха, назначения инженеров
  - `/api/assignments` — задания
  - `/api/inspections` — обследования
  - `/api/reports` — отчёты, генерация, скачивание
  - `/api/questionnaires` — опросные листы
  - `/api/verification-equipment` — поверки СИ
  - `/api/regulatory-documents` — нормативные документы
  - `/api/engineers`, `/api/certifications` — инженеры и сертификаты
  - `/api/report-templates`, `/api/report-templates-db` — шаблоны отчётов
  - `/api/mobile/*` — версия и обновления мобильного приложения

### 3.3 Модели БД (models.py)

- **Справочники/иерархия:** EquipmentType, Enterprise, Branch, Workshop, OPO.
- **Основные сущности:** Equipment, Client, Project, Engineer, User.
- **Работа:** Assignment, Inspection, Questionnaire, NDTMethod.
- **Отчёты и документы:** ReportTemplate, Report, RegulatoryDocument.
- **Сертификаты и поверки:** Certification, VerificationEquipment.
- **Доступ:** UserEquipmentAccess.
- **Прочее:** EquipmentResource, QuestionnaireDocumentFile, InspectionHistory, RepairJournal, VerificationHistory, InspectionEquipment и др. (импорты в main.py).

### 3.4 Аутентификация (auth.py)

- JWT (HS256), срок жизни 24 часа.
- Пароли: bcrypt (через passlib и напрямую).
- Fallback USERS_DB (admin/engineer/client) при недоступности БД.
- В продакшене пользователи и пароли — из таблицы `users`.

---

## 4. Frontend (React)

### 4.1 Маршруты (App.tsx)

- **Публичный:** `/login` — Login.
- **Под ProtectedRoute + Layout:**
  - `/` — Dashboard
  - `/equipment` — EquipmentManagement
  - `/equipment/:id` — EquipmentDetails
  - `/equipment-hierarchy` — EquipmentHierarchy
  - `/assignments` — AssignmentsManagement
  - `/inspections-list` — InspectionsList
  - `/projects` — ProjectsManagement
  - `/resources` — ResourceManagement
  - `/reports` — ReportGeneration
  - `/report-viewer/:inspectionId` — ReportViewer
  - `/verifications` — VerificationsManagement
  - `/verifications-calendar` — VerificationsCalendar
  - `/regulatory` — RegulatoryDocuments
  - `/competencies` — CompetenciesManagement
  - `/users` — UsersManagement (только `role === 'admin'`)
  - `/report-templates` — ReportTemplates (только admin)
  - `/inspection` — DynamicInspection
  - `/specs` — TechSpecs (архитектура)
  - `/mobile-app` — MobileApp
  - `/changelog` — Changelog
  - `/settings` — в Layout не выведен отдельной страницей (можно добавить).

### 4.2 Конфигурация API

- **API_BASE** задаётся в `constants.ts`: `http://5.129.203.182:8000`.
- Тот же URL дублируется в `contexts/AuthContext.tsx` и во многих страницах (`UsersManagement`, `ReportGeneration`, `EquipmentDetails`, `InspectionsList` и т.д.).
- **Рекомендация:** везде использовать `import { API_BASE } from '../constants'` (или из одного конфига), чтобы не хардкодить URL и упростить смену окружения.

### 4.3 Роли и доступ

- **AuthContext:** user.role, user.permissions, hasRole(), hasPermission().
- **ProtectedRoute:** проверка isAuthenticated, requiredRole, requiredPermission.
- В сайдбаре пункты «Сотрудники» и «Шаблоны отчётов» отображаются только при `user?.role === 'admin'`.

### 4.4 Версии в коде

- В шапке Layout: `v3.15.0`.
- В package.json: `3.12.0`.
- Имеет смысл держать одну версию (например, в constants или package.json) и подставлять её в UI и при сборке.

---

## 5. База данных

- **Подключение:** удалённый PostgreSQL (хост из DATABASE-INFO.md), SSL (сертификат в `backend/certs/root.crt`).
- **Настройки:** через переменные окружения в docker-compose (DB_USER, DB_PASS, DB_HOST, DB_NAME, DB_SSLMODE, DB_SSLCERT).
- **Локального контейнера PostgreSQL в docker-compose нет** — только удалённая БД.

---

## 6. Мобильное приложение (Flutter)

- Расположение: `mobile/`.
- Экраны: логин, дашборд, список оборудования, задания, опросные листы, сосуды, поверки, синхронизация, профиль и др.
- Версия и URL скачивания APK задаются в backend (main.py) и на странице MobileApp.

---

## 7. Замечания и рекомендации для разработки

### 7.1 Архитектура

- **main.py** очень большой (~10k+ строк). Часть эндпоинтов вынесена в роутеры: `auth_api.py` (login, me), `access_management.py`, `hierarchy_management.py`, `assignments_api.py`, `report_templates_api.py`, `equipment_history_api.py`. Имеет смысл продолжать выносить группы (inspections, reports, users и т.д.) в отдельные файлы.
- Константы (URL API, версия приложения) централизованы в `constants.ts` и при необходимости в .env (VITE_API_BASE, VITE_MOBILE_APK_URL).

### 7.2 API_BASE (исправлено)

- Единый источник: `constants.ts` — `API_BASE` (с поддержкой `VITE_API_BASE` из .env). Все страницы импортируют `API_BASE` из `../constants`. Для мобильного APK используется `MOBILE_APK_URL`.

### 7.3 Версионирование (исправлено)

- Единая версия: `APP_VERSION = '3.15.0'` в `constants.ts`, в UI (App.tsx) и в `package.json`. В MobileApp отображается та же версия.

### 7.4 Безопасность

- В продакшене ограничить CORS в FastAPI конкретными доменами.
- JWT_SECRET_KEY и пароли БД не коммитить в репозиторий; использовать секреты/окружение.

### 7.5 Документация

- **DEVELOPMENT-PROPOSALS.md** содержит приоритизированные идеи: уведомления, QR-коды, история жизненного цикла оборудования, улучшения мобильного приложения и др. — удобно использовать как бэклог.
- **RBAC-SYSTEM.md** описывает роли (admin, chief_operator, operator, engineer) и таблицы доступа.

### 7.6 Страницы без маршрута

- В `pages/` есть компоненты, не подключённые в App.tsx: AdminPanel, ClientPortal, EngineerPanel, PipelineMap, ReportsAndExpertise, SpecialistsManagement. Либо добавить маршруты, либо удалить/архивировать, чтобы не путать при поддержке.

---

## 8. Краткий чек-лист для продолжения разработки

- [x] Вынести группы эндпоинтов из main.py: auth вынесен в `auth_api.py`; остальные группы (inspections, reports, users и т.д.) выносить по мере необходимости.
- [x] Единый API_BASE в constants.ts + VITE_API_BASE в .env.
- [x] Унифицирована версия приложения (constants.APP_VERSION, package.json, UI).
- [x] AdminPanel и EngineerPanel подключены (маршруты и сайдбар по ролям).
- [ ] При добавлении фич ориентироваться на DEVELOPMENT-PROPOSALS.md и RBAC-SYSTEM.md.
- [ ] Для деплоя использовать существующие скрипты (deploy-*.bat, hard-redeploy-*.bat) и docker-compose; секреты хранить в окружении.

---

Документ подготовлен для продолжения разработки системы в данном репозитории.
