import React from 'react';
import { Sparkles, CheckCircle, AlertCircle, Plus, Bug, Settings } from 'lucide-react';

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
  const versions: Version[] = [
    {
      version: '3.6.2',
      date: new Date().toLocaleDateString('ru-RU'),
      type: 'minor',
      changes: [
        { type: 'added', description: 'Система аннотирования изображений для всех методов НК: возможность фотографировать чертежи и обводить дефекты стилусом/пальцем' },
        { type: 'added', description: 'Специальный экран для дефектов сварных швов: выбор типа дефекта (пористость, трещина, включение, подрез и т.д.) с характеристиками' },
        { type: 'added', description: 'Аннотированные изображения включаются в отчеты: все схемы с обведенными дефектами автоматически добавляются в раздел "Фотоматериалы и аннотированные схемы"' },
        { type: 'improved', description: 'Генерация отчетов: улучшено отображение документов специалистов с полной информацией (тип, номер, организация, даты выдачи и окончания)' },
        { type: 'improved', description: 'Генерация отчетов: детальная информация об используемом оборудовании (производитель, модель, дата поверки, срок поверки)' },
        { type: 'improved', description: 'Чек-листы: улучшено отображение всех приложенных документов с размерами файлов и прямыми ссылками на просмотр' },
        { type: 'fixed', description: 'Календарь поверок: исправлена ошибка отображения (добавлены недостающие импорты)' },
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

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3 mb-6">
        <Sparkles className="text-accent" size={32} />
        <h1 className="text-3xl font-bold text-white">Что нового?</h1>
      </div>

      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <div className="mb-6 p-4 bg-slate-900 rounded-lg border border-slate-700">
          <h2 className="text-xl font-bold text-white mb-2">Версия системы</h2>
          <p className="text-2xl font-bold text-accent">3.6.0 (1)</p>
          <p className="text-sm text-slate-400 mt-1">Текущая версия платформы</p>
        </div>
        <p className="text-slate-300 mb-6">
          Здесь вы можете увидеть все изменения и обновления системы. Версии отсортированы от новых к старым.
        </p>

        <div className="space-y-8">
          {versions.map((version, index) => (
            <div
              key={index}
              className="bg-slate-900 rounded-lg border border-slate-700 p-6 hover:border-accent/50 transition-colors"
            >
              <div className="flex items-start justify-between mb-4">
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
                <span className="text-slate-400 text-sm">{version.date}</span>
              </div>

              <div className="space-y-2">
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
            </div>
          ))}
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
