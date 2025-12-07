import React from 'react';
import { Calendar, CheckCircle, Code, Database, Smartphone, Users, Shield, FileText } from 'lucide-react';

interface ChangelogEntry {
  version: string;
  date: string;
  changes: {
    type: 'feature' | 'fix' | 'improvement' | 'security';
    category: string;
    description: string;
    icon?: React.ReactNode;
  }[];
}

const CHANGELOG: ChangelogEntry[] = [
  {
    version: '3.2.1',
    date: '07.12.2025',
    changes: [
      {
        type: 'fix',
        category: 'Мобильное приложение',
        description: 'КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Исправлена обработка ролей при логине - роль теперь всегда берется из /api/auth/me',
        icon: <Shield className="text-red-400" size={20} />,
      },
      {
        type: 'fix',
        category: 'Безопасность',
        description: 'Добавлена защита от неправильных ролей - по умолчанию устанавливается engineer, а не admin',
        icon: <Shield className="text-yellow-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Offline-first режим',
        description: 'Добавлена зависимость cryptography для шифрования offline-пакетов',
        icon: <Code className="text-blue-400" size={20} />,
      },
      {
        type: 'improvement',
        category: 'Backend',
        description: 'Реализованы функции для справочников и схем в offline-пакетах',
        icon: <Database className="text-green-400" size={20} />,
      },
      {
        type: 'improvement',
        category: 'Миграции БД',
        description: 'Выполнены все миграции для offline-first режима - создана таблица offline_tasks',
        icon: <Database className="text-purple-400" size={20} />,
      },
    ],
  },
  {
    version: '3.2.0',
    date: '04.12.2025',
    changes: [
      {
        type: 'feature',
        category: 'Иерархическая система доступа',
        description: 'Добавлена полная иерархическая структура: Enterprise → Branch → Workshop → EquipmentType → Equipment с возможностью назначения доступа на любом уровне',
        icon: <Shield className="text-blue-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Управление филиалами',
        description: 'Добавлено создание и управление филиалами (Branch) между предприятиями и цехами',
        icon: <FileText className="text-green-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Объединение обследований',
        description: 'Реализована возможность объединения нескольких обследований в один технический отчет',
        icon: <FileText className="text-purple-400" size={20} />,
      },
      {
        type: 'improvement',
        category: 'Интерфейс оборудования',
        description: 'Обновлен интерфейс управления оборудованием с древовидной структурой и визуальными иконками для каждого уровня',
        icon: <Code className="text-cyan-400" size={20} />,
      },
      {
        type: 'security',
        category: 'Система доступа',
        description: 'Улучшена система проверки доступа с учетом всех уровней иерархии (предприятие, филиал, цех, тип оборудования, оборудование)',
        icon: <Shield className="text-yellow-400" size={20} />,
      },
    ],
  },
  {
    version: '3.1.1',
    date: '02.12.2025',
    changes: [
      {
        type: 'feature',
        category: 'Опросные листы',
        description: 'Добавлен функционал заполнения опросных листов по объектам с возможностью прикрепления фото к каждому пункту',
        icon: <FileText className="text-blue-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Мобильное приложение',
        description: 'Реализован экран QuestionnaireScreen с 10 разделами опросного листа для диагностики сосудов',
        icon: <Smartphone className="text-green-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Генерация имен файлов',
        description: 'Автоматическая генерация имен фотофайлов в формате: {инв_номер}_{название_пункта}_{код}_{timestamp}.jpg',
        icon: <Code className="text-purple-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Offline режим',
        description: 'Опросные листы сохраняются локально при отсутствии интернета и автоматически синхронизируются при появлении связи',
        icon: <Smartphone className="text-orange-400" size={20} />,
      },
      {
        type: 'improvement',
        category: 'Роли и доступ',
        description: 'Исправлена проверка ролей - инженеры больше не видят админ панель, доступ корректно распределен по ролям',
        icon: <Shield className="text-yellow-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Панель инженера',
        description: 'Создана страница EngineerPanel для управления сертификатами НК инженерами',
        icon: <Users className="text-cyan-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'База данных',
        description: 'Добавлена таблица questionnaires для хранения опросных листов с поддержкой JSON данных',
        icon: <Database className="text-green-400" size={20} />,
      },
    ],
  },
  {
    version: '3.1.0',
    date: '26.11.2025',
    changes: [
      {
        type: 'feature',
        category: 'Авторизация',
        description: 'Реализована система авторизации и распределения ролей на веб-сайте',
        icon: <Shield className="text-blue-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Админ панель',
        description: 'Создана расширенная админ панель для управления пользователями, инженерами, сертификатами и отчетами',
        icon: <Shield className="text-purple-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Специалисты НК',
        description: 'Доработан раздел управления специалистами неразрушающего контроля с добавлением полей: метод контроля, уровень, дата окончания, фото документа',
        icon: <Users className="text-green-400" size={20} />,
      },
      {
        type: 'feature',
        category: 'Мобильное приложение',
        description: 'Добавлен экран просмотра сертификатов специалиста в мобильном приложении',
        icon: <Smartphone className="text-cyan-400" size={20} />,
      },
      {
        type: 'improvement',
        category: 'Offline режим',
        description: 'Улучшен offline режим в мобильном приложении - отчеты сохраняются локально и синхронизируются при появлении интернета',
        icon: <Smartphone className="text-orange-400" size={20} />,
      },
    ],
  },
];

const Changelog = () => {
  const getTypeColor = (type: string) => {
    switch (type) {
      case 'feature':
        return 'bg-blue-500/20 text-blue-400 border-blue-500/50';
      case 'fix':
        return 'bg-red-500/20 text-red-400 border-red-500/50';
      case 'improvement':
        return 'bg-green-500/20 text-green-400 border-green-500/50';
      case 'security':
        return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/50';
      default:
        return 'bg-slate-500/20 text-slate-400 border-slate-500/50';
    }
  };

  const getTypeLabel = (type: string) => {
    switch (type) {
      case 'feature':
        return 'Новая функция';
      case 'fix':
        return 'Исправление';
      case 'improvement':
        return 'Улучшение';
      case 'security':
        return 'Безопасность';
      default:
        return type;
    }
  };

  return (
    <div className="max-w-5xl mx-auto space-y-6 px-4">
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-white mb-2 flex items-center gap-3">
          <FileText className="text-accent" size={32} />
          История изменений
        </h1>
        <p className="text-slate-400">Версия системы: 3.2.1 (2025-Q4)</p>
      </div>

      <div className="space-y-8">
        {CHANGELOG.map((entry, index) => (
          <div
            key={entry.version}
            className="bg-secondary rounded-xl overflow-hidden border border-slate-700 shadow-lg"
          >
            {/* Заголовок версии */}
            <div className="px-6 py-4 border-b border-slate-700 bg-slate-800/50">
              <div className="flex items-center justify-between flex-wrap gap-4">
                <div className="flex items-center gap-3">
                  <div className="p-2 bg-accent/20 rounded-lg">
                    <CheckCircle className="text-accent" size={24} />
                  </div>
                  <div>
                    <h2 className="text-xl font-bold text-white">Версия {entry.version}</h2>
                    <div className="flex items-center gap-2 mt-1">
                      <Calendar className="text-slate-400" size={14} />
                      <p className="text-sm text-slate-400">{entry.date}</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Список изменений */}
            <div className="p-6 space-y-4">
              {entry.changes.map((change, changeIndex) => (
                <div
                  key={changeIndex}
                  className="bg-primary/50 rounded-lg p-4 border border-slate-700 hover:border-slate-600 transition-colors"
                >
                  <div className="flex items-start gap-4">
                    {change.icon && (
                      <div className="mt-1 flex-shrink-0">{change.icon}</div>
                    )}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-2 flex-wrap">
                        <span
                          className={`px-2 py-1 rounded text-xs font-semibold border ${getTypeColor(
                            change.type
                          )}`}
                        >
                          {getTypeLabel(change.type)}
                        </span>
                        <span className="text-sm font-medium text-slate-300">
                          {change.category}
                        </span>
                      </div>
                      <p className="text-slate-200 leading-relaxed">{change.description}</p>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* Легенда */}
      <div className="mt-8 bg-secondary rounded-lg p-6 border border-slate-700">
        <h3 className="text-lg font-bold text-white mb-4">Легенда</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div className="flex items-center gap-2">
            <span className="px-2 py-1 rounded text-xs font-semibold border bg-blue-500/20 text-blue-400 border-blue-500/50">
              Новая функция
            </span>
            <span className="text-sm text-slate-400">Добавлен новый функционал</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="px-2 py-1 rounded text-xs font-semibold border bg-red-500/20 text-red-400 border-red-500/50">
              Исправление
            </span>
            <span className="text-sm text-slate-400">Исправлены ошибки</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="px-2 py-1 rounded text-xs font-semibold border bg-green-500/20 text-green-400 border-green-500/50">
              Улучшение
            </span>
            <span className="text-sm text-slate-400">Улучшена существующая функция</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="px-2 py-1 rounded text-xs font-semibold border bg-yellow-500/20 text-yellow-400 border-yellow-500/50">
              Безопасность
            </span>
            <span className="text-sm text-slate-400">Улучшения безопасности</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Changelog;



