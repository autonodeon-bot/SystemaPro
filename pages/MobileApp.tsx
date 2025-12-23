import React from 'react';
import { Download, Smartphone, CheckCircle, AlertCircle } from 'lucide-react';

const MobileApp = () => {
  const downloadUrl = 'http://5.129.203.182/mobile/es-td-ngo-mobile-3.6.2-1.apk';

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3 mb-6">
        <Smartphone className="text-accent" size={32} />
        <h1 className="text-3xl font-bold text-white">Мобильное приложение</h1>
      </div>

      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6">
        <div className="flex items-start gap-4 mb-6">
          <div className="bg-accent/20 p-3 rounded-lg">
            <Smartphone className="text-accent" size={32} />
          </div>
          <div className="flex-1">
            <h2 className="text-xl font-bold text-white mb-2">ЕС ТД НГО - Мобильное приложение</h2>
            <p className="text-slate-400 mb-1">Версия: 3.6.2 (build 1) от {new Date().toLocaleDateString('ru-RU')} — последняя версия</p>
            <p className="text-sm text-green-400 mb-2">✓ Доступна новая версия для скачивания</p>
            <p className="text-slate-300">
              Мобильное приложение для инженеров диагностики. Позволяет заполнять и отправлять отчеты обследования оборудования прямо с мобильного устройства.
            </p>
          </div>
        </div>

        <div className="bg-slate-900 rounded-lg p-4 mb-6">
          <h3 className="text-lg font-bold text-white mb-3 flex items-center gap-2">
            <CheckCircle className="text-green-400" size={20} />
            Возможности приложения
          </h3>
          <ul className="space-y-2 text-slate-300">
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
              <ul className="text-sm text-slate-300 space-y-1">
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
            <h3 className="text-green-400 font-bold">Новая версия доступна!</h3>
          </div>
          <p className="text-sm text-slate-300 mb-4">
            Скачайте последнюю версию мобильного приложения (3.6.2 (build 1)) для получения всех обновлений и исправлений, включая:
          </p>
          <ul className="text-sm text-slate-300 space-y-1 ml-4">
            <li>• Улучшенная система заданий с иерархией и фильтрами</li>
            <li>• Управление поверками оборудования</li>
            <li>• Выбор поверенного оборудования перед началом работ</li>
            <li>• Расширенная сортировка и поиск заданий</li>
          </ul>
        </div>

        <div className="flex flex-col sm:flex-row gap-4">
          <a
            href={downloadUrl}
            download="es-td-ngo-mobile-3.6.2-1.apk"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center justify-center gap-3 bg-accent hover:bg-blue-600 text-white font-bold px-6 py-4 rounded-lg transition-colors shadow-lg"
          >
            <Download size={24} />
            <span>Скачать приложение v3.6.2 (build 1) (APK)</span>
          </a>
          
          <button
            onClick={() => {
              navigator.clipboard.writeText(downloadUrl);
              alert('Ссылка скопирована в буфер обмена!');
            }}
            className="flex items-center justify-center gap-3 bg-slate-700 hover:bg-slate-600 text-white font-bold px-6 py-4 rounded-lg transition-colors"
          >
            <span>Копировать ссылку</span>
          </button>
        </div>
        
        <div className="mt-4 text-sm text-slate-400">
          <p>Прямая ссылка: <a href={downloadUrl} target="_blank" rel="noopener noreferrer" className="text-accent hover:underline break-all">{downloadUrl}</a></p>
        </div>

        <div className="mt-6 pt-6 border-t border-slate-700">
          <h3 className="text-lg font-bold text-white mb-3">Инструкция по установке</h3>
          <ol className="space-y-2 text-slate-300 text-sm">
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
