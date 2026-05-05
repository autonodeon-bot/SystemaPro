import { Download, Smartphone, CheckCircle, AlertCircle } from 'lucide-react';
import { MOBILE_APK_URL, MOBILE_APP_BUILD, MOBILE_APP_VERSION } from '../constants';

const MobileApp = () => {
  const downloadUrl = MOBILE_APK_URL;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3 mb-6">
        <Smartphone className="text-accent" size={32} />
        <h1 className="text-3xl font-bold text-white">Мобильное приложение</h1>
      </div>

      {/* Ссылка на скачивание вверху */}
      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <div className="flex flex-col sm:flex-row gap-4 mb-4">
          <a
            href={downloadUrl}
            download={`es-td-ngo-mobile-${MOBILE_APP_VERSION}-${MOBILE_APP_BUILD}.apk`}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center justify-center gap-3 bg-accent hover:bg-blue-600 text-white font-bold px-6 py-4 rounded-lg transition-colors shadow-lg"
          >
            <Download size={24} />
            <span>Скачать приложение v{MOBILE_APP_VERSION} (build {MOBILE_APP_BUILD}) (APK)</span>
          </a>
          
          <button
            onClick={() => {
              navigator.clipboard.writeText(downloadUrl);
              alert('Ссылка скопирована в буфер обмена!');
            }}
            className="flex items-center justify-center gap-3 bg-app-soft hover:bg-app-softer text-app-text font-bold px-6 py-4 rounded-lg transition-colors"
          >
            <span>Копировать ссылку</span>
          </button>
        </div>
        <div className="text-sm text-app-text3">
          <p>Прямая ссылка: <a href={downloadUrl} target="_blank" rel="noopener noreferrer" className="text-accent hover:underline break-all">{downloadUrl}</a></p>
        </div>
      </div>

      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <div className="flex items-start gap-4 mb-6">
          <div className="bg-accent/20 p-3 rounded-lg">
            <Smartphone className="text-accent" size={32} />
          </div>
          <div className="flex-1">
            <h2 className="text-xl font-bold text-white mb-2">Монитор — мобильное приложение</h2>
            <p className="text-app-text3 mb-1">Версия: {MOBILE_APP_VERSION} (build {MOBILE_APP_BUILD}) — последняя версия</p>
            <p className="text-sm text-green-400 mb-2">✓ Доступна новая версия для скачивания</p>
            <p className="text-app-text2">
              Мобильное приложение для инженеров диагностики. Позволяет заполнять и отправлять отчеты обследования оборудования прямо с мобильного устройства.
            </p>
          </div>
        </div>

        <div className="bg-app-deep rounded-lg p-4 mb-6">
          <h3 className="text-lg font-bold text-app-text mb-3 flex items-center gap-2">
            <CheckCircle className="text-green-400" size={20} />
            Возможности приложения
          </h3>
          <ul className="space-y-2 text-app-text2">
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Выбор оборудования из списка с фильтрацией по предприятиям и цехам</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Заполнение полного чек-листа обследования сосуда</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Толщинометрия с указанием точек на схеме</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Фотофиксация (заводская табличка, схема контроля)</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Добавление методов неразрушающего контроля</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Отправка отчетов на сервер</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Синхронизация данных с сервером</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Офлайн-режим для работы без интернета</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Выбор поверенного оборудования перед началом работ</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Автоматическое включение информации об оборудовании в отчеты</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Просмотр заданий с иерархией (предприятие → филиал → цех)</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Расширенные фильтры и сортировка заданий</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Поиск заданий по коду, названию, предприятию</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent mt-1">•</span>
              <span>Предупреждения о просроченных заданиях</span>
            </li>
          </ul>
        </div>

        <div className="bg-yellow-500/10 border border-yellow-500/20 rounded-lg p-4 mb-6">
          <div className="flex items-start gap-3">
            <AlertCircle className="text-yellow-400 mt-0.5" size={20} />
            <div>
              <h3 className="text-yellow-400 font-bold mb-2">Важно перед установкой</h3>
              <ul className="text-sm text-app-text2 space-y-1">
                <li>• Удалите старую версию приложения, если она установлена</li>
                <li>• Разрешите установку из неизвестных источников в настройках Android</li>
                <li>• Убедитесь, что на устройстве достаточно свободного места (минимум 100 MB)</li>
              </ul>
            </div>
          </div>
        </div>

        <div className="bg-green-500/10 border border-green-500/20 rounded-lg p-4 mb-6">
          <div className="flex items-center gap-3 mb-3">
            <CheckCircle className="text-green-400" size={20} />
            <h3 className="text-green-400 font-bold">Новая версия {MOBILE_APP_VERSION} доступна!</h3>
          </div>
          <p className="text-sm text-app-text2 mb-4">
            Скачайте последнюю версию мобильного приложения ({MOBILE_APP_VERSION} (build {MOBILE_APP_BUILD})) для получения всех обновлений и исправлений, включая:
          </p>
          <ul className="text-sm text-app-text2 space-y-1 ml-4">
            <li>• Новая генерация отчетов для сосудов с полной структурой разделов 1-15</li>
            <li>• Автоматическая загрузка шаблонов чертежей с сервера</li>
            <li>• Работа с шаблонами чертежей для нанесения точек замера</li>
            <li>• Автоопределение типа оборудования для специализированных отчетов</li>
            <li>• Вход по отпечатку пальца или PIN (офлайн‑режим)</li>
            <li>• Выбор инженера по методам НК и поверенного оборудования</li>
            <li>• Расширенные отчеты с таблицами замеров и приложениями</li>
          </ul>
        </div>


        <div className="mt-6 pt-6 border-t border-app-line">
          <h3 className="text-lg font-bold text-app-text mb-3">Инструкция по установке</h3>
          <ol className="space-y-2 text-app-text2 text-sm">
            <li className="flex items-start gap-2">
              <span className="font-bold text-accent">1.</span>
              <span>Скачайте APK файл на ваше Android устройство</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="font-bold text-accent">2.</span>
              <span>Откройте файл через файловый менеджер</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="font-bold text-accent">3.</span>
              <span>Если появится предупреждение о безопасности, нажмите "Разрешить из этого источника"</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="font-bold text-accent">4.</span>
              <span>Нажмите "Установить" и дождитесь завершения установки</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="font-bold text-accent">5.</span>
              <span>Запустите приложение и войдите в систему</span>
            </li>
          </ol>
        </div>
      </div>
    </div>
  );
};

export default MobileApp;




