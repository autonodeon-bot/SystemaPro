import { useState } from 'react';
import { Sparkles, CheckCircle, AlertCircle, Plus, Bug, Settings, ChevronDown, ChevronUp } from 'lucide-react';

interface Version {
  version: string;
  date: string;
  type: 'major' | 'minor' | 'patch';
  changes: {
    type: 'added' | 'fixed' | 'changed' | 'improved';
    description: string;
  }[];
}

const Changelog = () => {
  /** Единственный источник для карточки «Версия системы» и списка ниже */
  const versions: Version[] = [
    {
      version: '3.28.0',
      date: '19.04.2026',
      type: 'minor',
      changes: [
        { type: 'improved', description: 'Web UI: редизайн AdminPanel и UsersManagement в индустриальной data-dense эстетике 2026 — единые стили sp-surface, sp-stat, sp-pill-nav, ind-chip с семантическими цветами и tabular-nums.' },
        { type: 'improved', description: 'Web UI: EquipmentHierarchyTree переведён на CSS-токены (var(--accent), var(--success), var(--warning)) вместо 32 hardcoded slate/blue/green цветов; вложенные уровни с пунктирными разделителями.' },
        { type: 'improved', description: 'Web UI: ReportsAndExpertise — breadcrumb и заголовок раздела переведены на дизайн-токены, добавлена плавная анимация sp-animate-in.' },
        { type: 'improved', description: 'Web CSS: добавлены алиасы ind-chip--success/--warning/--warn/--ok и sp-pill-nav__item для совместимости стилей между страницами.' },
        { type: 'improved', description: 'Mobile UI: equipment_list_screen — компактные плоские группы с ind-style border, dense type/дропдауны, chips счётчиков с AppColors.accent, 1-2 строки типографики вместо 4.' },
        { type: 'improved', description: 'Mobile UI: protocols_registry_screen — таблица реестра с 10.5px моноширинной датой, pill-статусами (success/warning с border), уплотнённая шапка и строки.' },
        { type: 'improved', description: 'Mobile UI: opo_list_screen — карточки со squircle-иконкой на warning-фоне, двухстрочное название с letter-spacing, chevron-стрелка вместо edit-кнопки.' },
        { type: 'fixed', description: 'Deploy: скрипт deploy-ssh.ps1 собирает backend и frontend последовательно без --no-cache — устранён OOM на VPS с 3–4 ГБ RAM, BUILD_REF по-прежнему инвалидирует frontend-слой.' },
        { type: 'changed', description: 'Системный релиз 3.28.0: синхронизированы версии web/backend/mobile.' },
      ],
    },
    {
      version: '3.27.0',
      date: '19.04.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Шаблоны чертежей с точками замеров: новый модуль «Шаблоны чертежей» (/drawing-templates) — загрузка растровых схем (PNG/JPG) с привязкой к конкретному оборудованию или типу оборудования, расстановка точек замеров прямо на изображении через интерактивный редактор с pan/zoom.' },
        { type: 'added', description: 'Бэкенд: новые модели DrawingTemplate и DrawingTemplatePoint, миграция Alembic 005, эндпоинты POST/GET/PATCH/DELETE /api/drawing-templates с отдачей изображений, загрузкой файлов и синхронизацией delta.' },
        { type: 'added', description: 'Мобильное: новые экраны выбора шаблона чертежа из библиотеки (drawing_template_picker) и аннотирования (drawing_annotation) с отображением предопределённых точек, перетаскиванием и добавлением новых; offline-кэш изображений и точек через sqflite.' },
        { type: 'added', description: 'Мобильное: интеграция «Шаблон из библиотеки» в экран толщинометрии (ThicknessMeasurementScreen) — точки замеров из веб-шаблона автоматически подтягиваются в форму замеров.' },
        { type: 'added', description: 'Мобильное: delta-синхронизация drawing templates в SyncService с префетчем для всех заданий инженера.' },
        { type: 'added', description: 'Карточка оборудования: новый блок «Шаблоны чертежей» показывает привязанные к объекту чертежи с переходом в редактор.' },
        { type: 'improved', description: 'Web UI: расширена индустриальная data-dense эстетика — новые CSS-токены sp-surface, sp-stat, sp-pill-nav, sp-progress, sp-skeleton, focus-visible; редизайн Dashboard, AssignmentsManagement, VerificationsManagement, EquipmentManagement с семантическими цветами и tabular-nums.' },
        { type: 'improved', description: 'Mobile UI: новая тема AppTheme 2026 — плотность −1/−1, современная типографика с отрицательным letter-spacing, плоские карточки; обновлённая карточка задания с 3px статусной полосой, pill-чипами статуса/приоритета и компактным индикатором sync.' },
        { type: 'fixed', description: 'Mobile: исправлены координаты точек на экранах ImageAnnotationScreen и WeldDefectAnnotationScreen — переход с глобальных координат на details.localPosition устранил смещение точек при тапе.' },
        { type: 'fixed', description: 'Mobile: VesselInspectionScreen — нижняя навигация страниц теперь корректно учитывает SafeArea и не перекрывается системной панелью Android.' },
        { type: 'fixed', description: 'Web: устранены все pre-existing TypeScript-ошибки (unused imports, import.meta.env, несовместимость LucideIcon) — tsc --noEmit проходит чисто, CI больше не засоряется.' },
        { type: 'changed', description: 'Системный релиз 3.27.0: синхронизированы версии web/backend/mobile.' },
      ],
    },
    {
      version: '3.26.0',
      date: '07.04.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Мобильное: меню «Создать» — пункт «Акт ТД (ЭПБ) оборудования» теперь открывает экран выбора объекта из базы (поиск, фильтр по типу) с прямым переходом к созданию акта.' },
        { type: 'added', description: 'Мобильное: новый экран «Новый протокол НК» — выбор методов контроля (ВИК, УЗТ; УЗК и ПВК/МПД — скоро), динамическая форма протокола по выбранным методам.' },
        { type: 'added', description: 'Мобильное: «Продолжить контроль» — реестр черновиков теперь открывает нужный экран (QuickControl / НК-протокол / Свой шаблон) с восстановлением всех заполненных данных.' },
        { type: 'added', description: 'Мобильное: «Ведомость дефектов» — официальный бланк результатов НК с автозаполнением из VIK-дефектов и UZT-замеров, статистикой, фильтром по степени, заключением и подписями.' },
        { type: 'added', description: 'Мобильное: PDF-экспорт ведомости дефектов с кириллическими шрифтами (NotoSans через printing/pdf), диалог печати и сохранения.' },
        { type: 'added', description: 'Мобильное: реестр протоколов/актов — переведён на единую таблицу (Дата | Объект | Вид контроля | Статус) с зелёным/красным цветом статуса, как в требованиях.' },
        { type: 'added', description: 'Мобильное: реестр приборов — переведён на компактную таблицу (№ | Наименование | Тип | Поверка до | Состояние | Специалист) с цветовой индикацией срока поверки и состояния.' },
        { type: 'added', description: 'Веб: новый раздел «Ведомость дефектов» (/defect-statement) — импорт из обследования, редактируемая таблица дефектов, автозаключение, фильтр по степени, печать/PDF через браузер.' },
        { type: 'added', description: 'Веб: конструктор протоколов/актов (/protocol-constructor) — создание и управление шаблонами протоколов с блочным редактором (секции, таблицы, поля, фото, подписи и др.).' },
        { type: 'added', description: 'Веб: корзина удалённых обследований (/inspections-trash) — просмотр мягко удалённых записей, восстановление в течение 60 дней, принудительная очистка для admin.' },
        { type: 'added', description: 'П.5.1 — Защита от случайного удаления: мягкое удаление (soft-delete) обследований с 60-дневным периодом восстановления; физическое удаление только по команде admin (purge). Все GET-запросы автоматически скрывают удалённые записи.' },
        { type: 'added', description: 'Бэкенд: новые endpoints — POST /api/inspections/{id}/restore, GET /api/inspections-trash, DELETE /api/inspections-trash/purge; миграция Alembic 004 (поля is_deleted, deleted_at, deleted_by в таблице inspections).' },
        { type: 'added', description: 'Мобильное: «Быстрый контроль ВИК/УЗТ» — реальное сохранение черновиков через AutoSaveService, восстановление всех полей, фотографий и таблиц при повторном открытии.' },
        { type: 'added', description: 'Мобильное: «Свой протокол / акт» — сохранение и восстановление черновиков шаблонных протоколов через AutoSaveService.' },
        { type: 'improved', description: 'Мобильное: AutoSaveService расширен методом saveGenericDraft с поддержкой типов экранов (quick_control, ndk_protocol, custom_protocol) для унифицированного сохранения черновиков.' },
      ],
    },
    {
      version: '3.25.0',
      date: '31.03.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Клиентский портал: фильтрация оборудования, обследований и отчётов по роли client; скачивание отчётов с Bearer; маршрут только для client; привязка через enterprises.client_id и проекты.' },
        { type: 'added', description: 'Календарь поверок: корректные локальные даты, неделя с понедельника, легенда сроков; API фильтр is_active по boolean.' },
        { type: 'added', description: 'Карта трубопроводов: GET /api/pipeline-map/segments из БД и coordinates в attributes оборудования; демо при отсутствии геоданных.' },
        { type: 'added', description: 'Миграция Alembic 003 (enterprises.client_id), загрузка .env в alembic/env.py; DB_SSLMODE=disable для локального Postgres без TLS.' },
        { type: 'changed', description: 'Имя продукта в интерфейсе: «Монитор» (кодовое имя SystemaPro / ЕС ТД НГО) — веб, мобильное приложение, OpenAPI.' },
        { type: 'added', description: 'Системный релиз 3.25.0: синхронизированы версии web/backend/mobile и обновлён раздел «Что нового».' },
        { type: 'improved', description: 'Web UI-kit (phase 1): добавлены единые классы sp-card, sp-card-soft, sp-section-title, sp-badge и sp-btn-subtle для сквозного современного интерфейса.' },
        { type: 'improved', description: 'Web отчёты: страницы ReportGeneration и ReportViewer переведены на унифицированный визуальный каркас без потери функциональности.' },
        { type: 'added', description: 'Web отчёты: предпросмотр PDF/DOCX, сохранение/сброс фильтров, фильтр по типу отчёта и единый формат дат (ДД.ММ.ГГГГ).' },
        { type: 'added', description: 'Проверка полноты отчёта в web: показ missing_fields/warnings в предпросмотре и просмотре отчёта перед генерацией.' },
        { type: 'improved', description: 'Backend валидация отчётов: обязательные поля (организация, исполнители, фото таблички, схема контроля) и предупреждения по данным толщинометрии.' },
        { type: 'improved', description: 'Backend загрузка фото НК: нормализация MIME и ограничение размера файлов для более надёжной обработки.' },
        { type: 'improved', description: 'Mobile синхронизация: ретраи отправки архивов, индикация online/offline, сводка готовности подписанных отчётов и быстрые подсказки на экране синхронизации.' },
        { type: 'improved', description: 'Mobile задания: сохранение фильтров/поиска, быстрый сброс фильтров, очистка поиска в одно нажатие и унифицированный формат дат.' },
        { type: 'fixed', description: 'Mobile фото: полностью переработан штамп метаданных — дата/время и GPS в отдельных блоках, без наложения строк.' },
        { type: 'improved', description: 'Mobile фото: размер текста для даты/GPS теперь рассчитывается пропорционально размеру изображения (~1/15) с автоподгонкой по ширине.' },
      ],
    },
    {
      version: '3.24.0',
      date: '21.02.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Релиз 3.24: полная пересборка backend/frontend контейнеров и перезапуск на сервере' },
        { type: 'added', description: 'Обновлён раздел «Что нового» с актуальной версией и детальным списком изменений' },
        { type: 'improved', description: 'Стабилизирован деплой: копирование `styles/` при публикации, чтобы дизайн-токены всегда попадали в docker-сборку' },
        { type: 'improved', description: 'Web: унифицировано отображение версии на Dashboard, Changelog и TechSpecs' },
        { type: 'improved', description: 'Mobile: версия APK обновлена до 3.24.0+24 и повторно выложена на сервер' },
      ],
    },
    {
      version: '3.23.0',
      date: '09.02.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Группировка обследований по типам (VISUAL/NDT/QUESTIONNAIRE) в API и web-интерфейсе' },
        { type: 'added', description: 'Мобильное: выбор типа обследования перед началом работы по заданию' },
        { type: 'added', description: 'Точки УЗК: координаты x_percent, y_percent на схеме, отрисовка в отчёте' },
        { type: 'added', description: 'Овальность: редактирование по сечению, улучшенные подсказки' },
        { type: 'added', description: 'Схема контроля: выбор файла / фото / встроенный шаблон / шаблон с сервера' },
        { type: 'improved', description: 'Web-редизайн: дизайн-токены, обновленные Login/Dashboard, улучшенная читаемость и навигация' },
        { type: 'improved', description: 'Mobile-редизайн: устранены перекрытия элементов в экранах аннотаций и фотофиксации' },
        { type: 'added', description: 'Чек-листы (web): сохранение фильтров между сессиями и экспорт отфильтрованных данных в CSV' },
        { type: 'fixed', description: 'Backend: устранен Windows-краш импорта (cp1251) в database.py при запуске модулей отчетов' },
      ],
    },
    {
      version: '3.22.0',
      date: '09.02.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Toast-уведомления (ToastContext) вместо alert' },
        { type: 'added', description: 'Модальные подтверждения (ConfirmModal) для критичных действий' },
        { type: 'added', description: 'Скелетоны загрузки (Skeleton, SkeletonCard, SkeletonTable)' },
        { type: 'added', description: 'Глоссарий терминов (ВИК, УЗТ, ОПО и др.) — страница /glossary' },
        { type: 'added', description: 'Панель статистики на дашборде: обследования, отчёты, задания за период (API /api/stats)' },
        { type: 'added', description: 'Подсказки (Tooltip) для сложных полей' },
        { type: 'added', description: 'Утилиты: fetchWithRetry (повтор при сетевых ошибках), cache (localStorage)' },
        { type: 'added', description: 'Мобильное: явный офлайн-статус при отсутствии сети' },
        { type: 'added', description: 'Мобильное: краткая сводка перед подписанием чек-листа' },
      ],
    },
    {
      version: '3.21.0',
      date: '09.02.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Проверка сети перед синхронизацией: перед отправкой данных проверяется доступность API (/health); при отсутствии интернета показывается «Нет интернета», синхронизация не запускается' },
        { type: 'improved', description: 'Экран «Синхронизация»: при нажатии «Синхронизировать» сначала проверка соединения, затем отправка — не тратятся попытки без сети' },
        { type: 'improved', description: 'Экран «Задания»: при нажатии кнопки синхронизации заданий — та же проверка; при отсутствии сети — сообщение без запросов к серверу' },
        { type: 'improved', description: 'Фоновая задача периодической синхронизации (Workmanager): при отсутствии доступа к API синхронизация не выполняется' },
        { type: 'added', description: 'Документ CHAT-SUMMARY.md: выжимка контекста системы, что сделано по улучшениям, приоритеты развития и следующие шаги' },
      ],
    },
    {
      version: '3.20.0',
      date: '03.02.2026',
      type: 'minor',
      changes: [
        { type: 'improved', description: 'Специалисты: API возвращает method_code как в БД (ВИК, УЗК и т.д.) — специалисты с удостоверениями корректно подходят при выборе по методу НК' },
        { type: 'improved', description: 'Отчёты: фото дефектов ВИК подставляются из загруженных document_files (ключи vd_i_j) при синхронизации с мобильного, если путь в data не разрешается' },
        { type: 'improved', description: 'Офлайн-вход: кнопка «Войти офлайн» всегда показывается при наличии сохранённого пользователя' },
        { type: 'added', description: 'Экран синхронизации: кнопка «Подключиться и синхронизировать» и сообщения при частичной синхронизации (чек отправлен, фото — повторить позже)' },
        { type: 'fixed', description: 'Мобильное приложение: фото таблички и схемы контроля сохраняются в постоянную папку приложения для корректной синхронизации' },
        { type: 'fixed', description: 'Список ожидающих синхронизации не очищается при выходе — можно повторить загрузку файлов после повторного входа' },
        { type: 'fixed', description: 'Устранён дубликат эндпоинта get_engineers — используется реализация с подтягиванием сертификатов из Certification' },
      ],
    },
    {
      version: '3.18.0',
      date: '28.01.2026',
      type: 'minor',
      changes: [
        { type: 'improved', description: 'Фото в заданиях и отчётах: корректное прикрепление фото заводской таблички и схемы контроля в опросном листе и при генерации отчётов' },
        { type: 'improved', description: 'Улучшено разрешение путей к изображениям в отчётах (questionnaire_documents) — фото надёжно подставляются в PDF и на сайте' },
        { type: 'fixed', description: 'Офлайн: при отсутствии токена открытие задания использует кэш оборудования, без ошибки «Токен авторизации не найден»' },
      ],
    },
    {
      version: '3.17.0',
      date: '30.01.2026',
      type: 'minor',
      changes: [
        { type: 'fixed', description: 'Офлайн-режим: при запуске без интернета больше не показываются ошибки — приложение запрашивает PIN и работает с сохранёнными данными' },
        { type: 'improved', description: 'При открытии задания без сети оборудование подгружается из кэша, экран обследования открывается без ошибки "Network is unreachable"' },
        { type: 'added', description: 'Возможность продолжить черновик отчёта: после "Сохранить черновик" можно снова открыть задание, отредактировать и подписать; при синхронизации отчёт отправляется на сервер' },
        { type: 'fixed', description: 'Картинки в отчётах: в отчёт и при просмотре на сайте подставляются схема УЗК с точками, фото заводской таблички и фото дефектов ВИК из базы' },
        { type: 'fixed', description: 'Исправлено создание опросного листа при отправке инспекции с сервера — картинки документов сохраняются и привязываются к отчёту' },
        { type: 'fixed', description: 'Ошибка "column questionnaires.assignment_id does not exist" при генерации отчёта устранена' },
      ],
    },
    {
      version: '3.12.0',
      date: '25.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Полный просмотр отчета в веб‑системе с отображением всех приложений и вложений' },
        { type: 'added', description: 'Централизованное хранение фото НК на сервере и загрузка через API' },
        { type: 'added', description: 'Миграция старых сканов поверок в новую структуру хранения' },
        { type: 'added', description: 'PIN‑вход в мобильном приложении с возможностью установки/отключения пользователем' },
      ],
    },
    {
      version: '3.11.0',
      date: '20.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Группировка отчетов и чек-листов по предприятиям и цехам с раскрывающимся списком' },
        { type: 'added', description: 'Архивирование и удаление отчетов и чек-листов' },
        { type: 'fixed', description: 'Исправлено дублирование отправки отчетов из мобильного приложения (черновики не отправляются автоматически)' },
        { type: 'improved', description: 'Логика "начать заново" для выполненных заданий: выбор между "пройти заново" и "внести изменения"' },
        { type: 'added', description: 'Группировка оборудования по ОПО на сервере и в мобильном приложении' },
        { type: 'added', description: 'Выбор ОПО при начале диагностики, если оно не задано на сервере' },
        { type: 'added', description: 'Автоматическая загрузка списка ОПО предприятия при синхронизации' },
        { type: 'improved', description: 'Чек-лист для ОПО: заполнение данных по ОПО (пункты 1-9) с возможностью прикрепления документов' },
        { type: 'improved', description: 'Синхронизация ОПО опросников с сервером' },
      ],
    },
    {
      version: '3.10.0',
      date: '20.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Новая генерация отчетов для сосудов и ресиверов по образцу технических отчетов с полной структурой разделов 1-15 и приложений' },
        { type: 'added', description: 'Автоматическое определение типа оборудования для генерации специализированных отчетов' },
        { type: 'added', description: 'Шаблоны чертежей сосудов: автоматическое использование шаблона, если не загружено фото схемы контроля' },
        { type: 'added', description: 'API для получения шаблонов чертежей с сервера в мобильном приложении' },
        { type: 'improved', description: 'Мобильное приложение: загрузка стандартных чертежей с сервера для работы с точками замера' },
        { type: 'improved', description: 'Отчеты для сосудов: добавлены все необходимые таблицы, протоколы и приложения согласно нормативной документации' },
        { type: 'improved', description: 'Структура отчетов: титульный лист, содержание, разделы 1-15, приложения с протоколами по каждому методу НК' },
        { type: 'added', description: 'Поддержка разных типов оборудования с возможностью расширения для других типов (трубопроводы, резервуары и т.д.)' },
      ],
    },
    {
      version: '3.9.0',
      date: '19.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Автосохранение черновиков при выходе/закрытии мобильного приложения' },
        { type: 'added', description: 'Фильтрация специалистов по методам контроля: показываются только те, у кого есть соответствующие удостоверения' },
        { type: 'added', description: 'Выбор методов контроля через галочки перед выбором специалистов' },
        { type: 'improved', description: 'Кнопки для фото таблички и схемы замеров теперь с понятными надписями' },
        { type: 'improved', description: 'Черновики отображаются в синхронизации как ожидающие синхронизации с детальной статистикой' },
        { type: 'improved', description: 'Генерация отчетов: добавлены чертежи с точками замера (координаты X, Y, толщина), фото заводской таблички в разделе ВИК' },
        { type: 'added', description: 'Отдельная вкладка ОПО для заполнения данных и привязки оборудования' },
        { type: 'added', description: 'Светлая тема для веб-системы с переключателем в боковом меню' },
        { type: 'improved', description: 'Офлайн вход: улучшена работа без интернета, вход по PIN/отпечатку' },
        { type: 'improved', description: 'Редизайн: улучшены переходы, анимации, расположение кнопок' },
      ],
    },
    {
      version: '3.8.1',
      date: '18.01.2026',
      type: 'patch',
      changes: [
        { type: 'added', description: 'Отдельные формы актов обследования по каждому методу НК в отчетах' },
        { type: 'improved', description: 'Расширена таблица технических характеристик по сосуду' },
        { type: 'improved', description: 'Опросный лист: документы и вложения прикрепляются в отчет' },
        { type: 'improved', description: 'ВИК: дефекты с фото/размерами добавлены в отчет' },
        { type: 'improved', description: 'УЗТ: схема контроля и таблицы точек измерения' },
        { type: 'improved', description: 'Синхронизация инженеров, заданий и поверок в мобильном приложении' },
        { type: 'added', description: 'Раздел "Что нового" на дашборде с переходом к истории изменений' },
      ],
    },
    {
      version: '3.8.0',
      date: '18.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Биометрическая аутентификация: вход по отпечатку пальца или PIN-коду в мобильном приложении' },
        { type: 'added', description: 'Привязка пользователя к устройству: безопасная локальная авторизация для офлайн-режима' },
        { type: 'improved', description: 'Офлайн-авторизация: пользователь может войти в приложение без интернета, используя биометрию или PIN' },
        { type: 'improved', description: 'Безопасность: токены и пароли хранятся в защищенном хранилище устройства' },
        { type: 'improved', description: 'UX мобильного приложения: автоматическое предложение биометрической аутентификации при первом входе' },
      ],
    },
    {
      version: '3.7.0',
      date: '13.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Задания (веб): для выполненных заданий добавлены действия “Просмотреть чек‑лист” и “Сгенерировать отчет”, чтобы всегда можно было открыть данные инженера и сделать диагностический отчет' },
        { type: 'added', description: 'Шаблоны отчетов: добавлен редактор макетов (визуальный + JSON), привязка шаблона к типу оборудования и загрузка логотипа для титульной страницы' },
        { type: 'improved', description: 'DOCX “Диагностический отчет”: генерация по структуре как в примере, подтягивание названия и характеристик из базы оборудования, поддержка логотипа на титуле' },
        { type: 'improved', description: 'Мобильное: сценарий “Сохранить (черновик)” и “Подписать/Завершить” (подписание готовит данные к отправке, а “выполнено” на сервере ставится только после успешной синхронизации)' },
        { type: 'improved', description: 'Мобильное: статусы по заданиям — “черновик локально / подписано локально / ожидает синхронизации”, чтобы не было путаницы' },
        { type: 'improved', description: 'Мобильное: иерархический список заданий (предприятие → филиал → цех) для удобной навигации' },
        { type: 'fixed', description: 'Версионирование и обновления: синхронизированы версии (web/backend/mobile) и улучшена автоматизация публикации APK' },
      ],
    },
    {
      version: '3.6.2',
      date: '12.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Система аннотирования изображений для всех методов НК: возможность фотографировать чертежи и обводить дефекты стилусом/пальцем' },
        { type: 'added', description: 'Специальный экран для дефектов сварных швов: выбор типа дефекта (пористость, трещина, включение, подрез и т.д.) с характеристиками' },
        { type: 'added', description: 'Аннотированные изображения включаются в отчеты: схемы с обведенными дефектами автоматически добавляются в отчет' },
        { type: 'improved', description: 'Генерация отчетов: улучшено отображение документов специалистов и поверенного оборудования с приложенными сканами' },
        { type: 'improved', description: 'Чек-листы: улучшено отображение всех приложенных документов с размерами файлов и прямыми ссылками на просмотр' },
        { type: 'fixed', description: 'Календарь поверок: исправлена ошибка отображения' },
      ],
    },
    {
      version: '3.6.0',
      date: '23.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Система управления поверками оборудования: полный цикл управления оборудованием для поверок' },
        { type: 'added', description: 'Календарь поверок: визуализация сроков поверок с цветовой индикацией (просрочено, истекает ≤7 дней, ≤30 дней)' },
        { type: 'added', description: 'Уведомления о сроках поверок на главной странице (Dashboard) с предупреждениями за 30, 14 и 7 дней' },
        { type: 'added', description: 'Мобильное приложение: выбор поверенного оборудования перед началом работ с валидацией' },
        { type: 'added', description: 'Мобильное приложение: автоматическое включение информации об используемом оборудовании в отчеты' },
        { type: 'added', description: 'Отчеты: автоматическое добавление раздела "Оборудование, использованное при диагностировании" с приложенными сканами поверок' },
        { type: 'added', description: 'История поверок: просмотр полной истории поверок для каждого оборудования' },
        { type: 'added', description: 'Экспорт списка оборудования для поверок в CSV с фильтрацией по срокам и типам' },
        { type: 'added', description: 'Статистика использования оборудования: анализ частоты использования оборудования в обследованиях' },
        { type: 'added', description: 'Категории оборудования: автоподстановка типов оборудования (ВИК, УЗК, ПВК, РК, МК, ВК, ТК)' },
        { type: 'improved', description: 'Валидация: нельзя начать обследование без выбора поверенного оборудования в мобильном приложении' },
        { type: 'improved', description: 'Интеграция: оборудование для поверок автоматически привязывается к обследованиям и включается в отчеты' },
      ],
    },
    {
      version: '3.5.1',
      date: '16.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Задания: обзор назначений по объектам (предприятие/филиал/цех/оборудование) + прогресс-бар выполнено/всего' },
        { type: 'added', description: 'Чек-листы: названия документов в “Перечень рассмотренных документов” как в мобильном приложении' },
        { type: 'added', description: 'Чек-листы: просмотр прикрепленных файлов (сканы/фото) прямо в браузере (inline view)' },
        { type: 'added', description: 'Чек-листы: отображение всех “прочих вложений” (помимо стандартных документов и системных фото)' },
        { type: 'added', description: 'Отчеты/чек-листы: удаление (RBAC) — admin/operator могут удалять любые, инженер только свои' },
        { type: 'added', description: 'Очистка: массовое удаление старых отчетов и чек-листов по сроку хранения' },
        { type: 'fixed', description: 'DOCX/PDF генерация: исправлены ошибки формирования и корректные MIME/имя файла для DOCX' },
        { type: 'fixed', description: 'PDF: исправлено отображение кириллицы (шрифты с поддержкой русского языка)' },
        { type: 'improved', description: 'Генератор отчетов: структура как у реальных отчетов (общая часть, акты НК, заключение, приложения)' },
        { type: 'improved', description: 'Отчеты: подтягиваются данные из мобильного (точки замера, фото таблички, карта обследования, арматура, фото/вложения методов НК)' },
        { type: 'improved', description: 'Мобильное: синхронизация заданий + обработка 401 (автовыход и повторная авторизация)' },
        { type: 'improved', description: 'Мобильное: автозаполнение карты обследования из базы оборудования и сохранение изменений обратно в оборудование' },
        { type: 'added', description: 'Мобильное: расширены методы НК (ЗРА, СППК, овальность, прогиб, твердость по точкам, ПВК/МК/УЗК сварных соединений)' },
        { type: 'added', description: 'API: утверждение отчетов/чек-листов (APPROVED) — после утверждения отображаются в карточке оборудования и в списках' },
      ],
    },
    {
      version: '3.5.0',
      date: '12.12.2025',
      type: 'major',
      changes: [
        { type: 'added', description: 'Мобильное приложение обновлено до 3.5.0 (release APK)' },
        { type: 'fixed', description: 'Ссылка на APK приведена к единому формату /mobile/* (исключены “старые”/битые ссылки)' },
        { type: 'added', description: 'Компетенции: прикрепление скана сертификата (фото/PDF) к карточке инженера' },
        { type: 'added', description: 'Оборудование: переход в карточку оборудования по клику (страница с полной информацией, как в Диагностике)' },
        { type: 'improved', description: 'Генерация отчетов: улучшена поддержка данных из мобильного (в т.ч. толщинометрия)' },
      ],
    },
    {
      version: '3.3.0',
      date: '11.12.2025',
      type: 'major',
      changes: [
        { type: 'added', description: 'Единая база оборудования с уникальными кодами (equipment_code)' },
        { type: 'added', description: 'Система заданий на диагностику/экспертизу (assignments)' },
        { type: 'added', description: 'История обследований оборудования (inspection_history)' },
        { type: 'added', description: 'Журнал ремонта оборудования (repair_journal)' },
        { type: 'added', description: 'Операторы могут создавать задания и назначать инженеров' },
        { type: 'added', description: 'Инженеры видят только назначенные им задания в мобильном приложении' },
        { type: 'added', description: 'Офлайн-режим: синхронизация скачивает назначенное оборудование' },
        { type: 'added', description: 'Работа с заданиями в мобильном приложении без интернета' },
        { type: 'added', description: 'Автоматическое обновление статуса задания при выполнении' },
        { type: 'improved', description: 'Все обследования привязаны к оборудованию по уникальному коду' },
        { type: 'improved', description: 'Полная история обследований и ремонтов для каждого оборудования' },
      ],
    },
    {
      version: '3.2.9',
      date: '11.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Добавлена кнопка выхода из системы в веб-приложении' },
        { type: 'added', description: 'Создан раздел "Что нового?" для отслеживания изменений версий' },
        { type: 'added', description: 'Добавлено отображение версии системы в интерфейсе (3.2.9 (10))' },
        { type: 'added', description: 'Реализовано автоматическое увеличение версии при загрузке мобильного приложения' },
        { type: 'added', description: 'Добавлено отображение версии приложения в мобильном приложении (профиль)' },
        { type: 'fixed', description: 'Исправлена ошибка загрузки списка пользователей (500 Internal Server Error)' },
        { type: 'fixed', description: 'Исправлена ошибка сравнения типа is_active в таблице users' },
        { type: 'fixed', description: 'Исправлена ошибка создания экспертизы (equipment_resources.resource_type)' },
        { type: 'fixed', description: 'Исправлена ошибка создания технического отчета (NDTMethod.inspection_id)' },
        { type: 'fixed', description: 'Исправлена проблема с пустым экраном оборудования в мобильном приложении' },
        { type: 'fixed', description: 'Исправлена ошибка загрузки leaflet.css (integrity attribute)' },
        { type: 'improved', description: 'Улучшена работа с назначением инженеров на оборудование' },
        { type: 'improved', description: 'Обновлен интерфейс управления доступом к оборудованию' },
        { type: 'improved', description: 'Обновлена версия мобильного приложения до 3.2.9 (build 10)' },
        { type: 'improved', description: 'Улучшена система версионирования APK файлов (автоматическое переименование)' },
        { type: 'improved', description: 'Оптимизирован фронтенд для работы с мобильных устройств' },
      ],
    },
    {
      version: '3.2.8',
      date: '10.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Добавлена иерархическая структура оборудования (Предприятия → Филиалы → Цеха → Оборудование)' },
        { type: 'added', description: 'Реализовано назначение инженеров на уровни иерархии оборудования' },
        { type: 'added', description: 'Добавлена офлайн-синхронизация оборудования в мобильном приложении' },
        { type: 'added', description: 'Реализована фильтрация оборудования по назначенным инженерам' },
        { type: 'improved', description: 'Улучшена работа мобильного приложения в офлайн-режиме' },
      ],
    },
    {
      version: '3.2.7',
      date: '09.12.2025',
      type: 'patch',
      changes: [
        { type: 'fixed', description: 'Исправлена ошибка генерации отчетов в формате DOCX' },
        { type: 'fixed', description: 'Исправлена проблема с отображением русских символов в PDF отчетах' },
        { type: 'added', description: 'Добавлен предпросмотр данных перед генерацией технического отчета' },
        { type: 'improved', description: 'Улучшена генерация отчетов с поддержкой всех методов НК' },
      ],
    },
    {
      version: '3.2.6',
      date: '08.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Добавлена генерация отчетов в формате Word (DOCX)' },
        { type: 'added', description: 'Реализована система управления доступом к оборудованию (RBAC)' },
        { type: 'added', description: 'Добавлено отображение ФИО инженера в карточках отчетов и чек-листов' },
        { type: 'improved', description: 'Улучшено отображение названий документов в чек-листах' },
        { type: 'improved', description: 'Добавлено хранение отчетов о толщинометрии и других методов НК' },
      ],
    },
    {
      version: '3.2.5',
      date: '07.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Восстановлена функция толщинометрии с указанием точек на схеме' },
        { type: 'added', description: 'Добавлена фильтрация оборудования по предприятиям и цехам в мобильном приложении' },
        { type: 'fixed', description: 'Исправлена ошибка отправки отчетов (project_id не существует)' },
        { type: 'improved', description: 'Восстановлен полный функционал мобильного приложения' },
      ],
    },
  ];

  const [expandedVersions, setExpandedVersions] = useState<Set<string>>(new Set([versions[0]?.version || '']));

  const toggleVersion = (version: string) => {
    setExpandedVersions((prev) => {
      const newSet = new Set(prev);
      if (newSet.has(version)) {
        newSet.delete(version);
      } else {
        newSet.add(version);
      }
      return newSet;
    });
  };

  const getChangeIcon = (type: string) => {
    switch (type) {
      case 'added':
        return <Plus className="text-green-400" size={16} />;
      case 'fixed':
        return <Bug className="text-red-400" size={16} />;
      case 'changed':
        return <Settings className="text-blue-400" size={16} />;
      case 'improved':
        return <CheckCircle className="text-yellow-400" size={16} />;
      default:
        return <CheckCircle className="text-slate-400" size={16} />;
    }
  };

  const getChangeLabel = (type: string) => {
    switch (type) {
      case 'added':
        return 'Добавлено';
      case 'fixed':
        return 'Исправлено';
      case 'changed':
        return 'Изменено';
      case 'improved':
        return 'Улучшено';
      default:
        return 'Изменение';
    }
  };

  const getVersionBadgeColor = (type: string) => {
    switch (type) {
      case 'major':
        return 'bg-red-500/20 text-red-400 border-red-500/30';
      case 'minor':
        return 'bg-blue-500/20 text-blue-400 border-blue-500/30';
      case 'patch':
        return 'bg-green-500/20 text-green-400 border-green-500/30';
      default:
        return 'bg-slate-500/20 text-slate-400 border-slate-500/30';
    }
  };

  const latest = versions[0];

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3 mb-6">
        <Sparkles className="text-accent" size={32} />
        <h1 className="text-3xl font-bold text-white">Что нового?</h1>
      </div>

      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <div className="mb-6 p-4 bg-slate-900 rounded-lg border border-slate-700">
          <h2 className="text-xl font-bold text-white mb-2">Версия системы</h2>
          <p className="text-2xl font-bold text-accent">
            {latest.version} ({latest.date})
          </p>
          <p className="text-sm text-slate-400 mt-1">Текущая версия платформы</p>
        </div>
        <p className="text-slate-300 mb-6">
          Здесь вы можете увидеть все изменения и обновления системы. Версии отсортированы от новых к старым.
        </p>

        <div className="space-y-4">
          {versions.map((version, index) => {
            const isExpanded = expandedVersions.has(version.version);
            return (
              <div
                key={index}
                className="bg-slate-900 rounded-lg border border-slate-700 hover:border-accent/50 transition-colors overflow-hidden"
              >
                <button
                  onClick={() => toggleVersion(version.version)}
                  className="w-full flex items-center justify-between p-6 hover:bg-slate-800/50 transition-colors text-left"
                >
                  <div className="flex items-center gap-3">
                    <div className="flex items-center justify-center w-8 h-8 rounded-full bg-slate-800 border border-slate-700">
                      {isExpanded ? (
                        <ChevronUp className="text-accent" size={20} />
                      ) : (
                        <ChevronDown className="text-slate-400" size={20} />
                      )}
                    </div>
                    <div className="flex items-center gap-3">
                      <h2 className="text-2xl font-bold text-white">Версия {version.version}</h2>
                      <span
                        className={`px-3 py-1 rounded-full text-xs font-semibold border ${getVersionBadgeColor(
                          version.type
                        )}`}
                      >
                        {version.type === 'major'
                          ? 'Крупное обновление'
                          : version.type === 'minor'
                          ? 'Обновление'
                          : 'Исправление'}
                      </span>
                    </div>
                  </div>
                  <span className="text-slate-400 text-sm">{version.date}</span>
                </button>

                {isExpanded && (
                  <div className="px-6 pb-6 pt-2 space-y-2 animate-in slide-in-from-top-2 duration-200">
                    {version.changes.map((change, changeIndex) => (
                      <div
                        key={changeIndex}
                        className="flex items-start gap-3 p-3 bg-slate-800/50 rounded-lg hover:bg-slate-800 transition-colors"
                      >
                        <div className="mt-0.5">{getChangeIcon(change.type)}</div>
                        <div className="flex-1">
                          <div className="flex items-center gap-2 mb-1">
                            <span className="text-xs font-semibold text-slate-400">
                              {getChangeLabel(change.type)}
                            </span>
                          </div>
                          <p className="text-slate-300 text-sm">{change.description}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        <div className="mt-8 pt-6 border-t border-slate-700">
          <div className="flex items-start gap-3">
            <AlertCircle className="text-yellow-400 mt-0.5" size={20} />
            <div>
              <h3 className="text-yellow-400 font-bold mb-2">Обратная связь</h3>
              <p className="text-sm text-slate-300">
                Если вы заметили ошибку или у вас есть предложения по улучшению системы, пожалуйста, свяжитесь с администратором.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Changelog;
