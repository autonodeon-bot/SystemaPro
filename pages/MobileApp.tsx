import React from 'react';
import { Smartphone, Download, QrCode } from 'lucide-react';

const MobileApp: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
        <div className="flex items-center gap-3 mb-4">
          <Smartphone className="text-accent" size={24} />
          <h1 className="text-2xl font-bold text-white">Мобильное приложение</h1>
        </div>
        <p className="text-slate-300 mb-6">
          Скачайте мобильное приложение для работы с системой диагностики оборудования прямо на ваше Android устройство.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* QR код */}
        <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
          <div className="flex items-center gap-3 mb-4">
            <QrCode className="text-accent" size={24} />
            <h2 className="text-xl font-semibold text-white">Сканируйте QR-код</h2>
          </div>
          <p className="text-slate-400 mb-4 text-sm">
            Отсканируйте QR-код камерой вашего Android устройства для скачивания приложения
          </p>
          <div className="flex justify-center items-center bg-white p-4 rounded-lg">
            <img 
              src="/QR/mobile.jpg" 
              alt="QR код для скачивания мобильного приложения"
              className="max-w-full h-auto"
              style={{ maxHeight: '400px' }}
              onError={(e) => {
                const target = e.target as HTMLImageElement;
                target.style.display = 'none';
                const parent = target.parentElement;
                if (parent) {
                  parent.innerHTML = '<p class="text-slate-400 text-center">QR-код не найден</p>';
                }
              }}
            />
          </div>
        </div>

        {/* Инструкция */}
        <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
          <div className="flex items-center gap-3 mb-4">
            <Download className="text-accent" size={24} />
            <h2 className="text-xl font-semibold text-white">Инструкция по установке</h2>
          </div>
          <div className="space-y-4 text-slate-300">
            <div className="flex gap-3">
              <div className="flex-shrink-0 w-8 h-8 bg-accent/20 rounded-full flex items-center justify-center text-accent font-bold">
                1
              </div>
              <div>
                <p className="font-medium">Откройте камеру на вашем Android устройстве</p>
                <p className="text-sm text-slate-400 mt-1">Или используйте приложение для сканирования QR-кодов</p>
              </div>
            </div>
            <div className="flex gap-3">
              <div className="flex-shrink-0 w-8 h-8 bg-accent/20 rounded-full flex items-center justify-center text-accent font-bold">
                2
              </div>
              <div>
                <p className="font-medium">Наведите камеру на QR-код</p>
                <p className="text-sm text-slate-400 mt-1">QR-код автоматически распознается</p>
              </div>
            </div>
            <div className="flex gap-3">
              <div className="flex-shrink-0 w-8 h-8 bg-accent/20 rounded-full flex items-center justify-center text-accent font-bold">
                3
              </div>
              <div>
                <p className="font-medium">Перейдите по ссылке и скачайте APK файл</p>
                <p className="text-sm text-slate-400 mt-1">Файл будет загружен в папку "Загрузки"</p>
              </div>
            </div>
            <div className="flex gap-3">
              <div className="flex-shrink-0 w-8 h-8 bg-accent/20 rounded-full flex items-center justify-center text-accent font-bold">
                4
              </div>
              <div>
                <p className="font-medium">Установите приложение</p>
                <p className="text-sm text-slate-400 mt-1">
                  При необходимости разрешите установку из неизвестных источников в настройках безопасности
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Возможности приложения */}
      <div className="bg-secondary/50 rounded-lg p-6 border border-slate-700">
        <h2 className="text-xl font-semibold text-white mb-4">Возможности мобильного приложения</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="flex gap-3">
            <div className="flex-shrink-0 w-6 h-6 bg-accent/20 rounded flex items-center justify-center">
              <div className="w-2 h-2 bg-accent rounded-full"></div>
            </div>
            <div>
              <p className="text-white font-medium">Авторизация и личный кабинет</p>
              <p className="text-slate-400 text-sm">Вход в систему с персональным профилем специалиста</p>
            </div>
          </div>
          <div className="flex gap-3">
            <div className="flex-shrink-0 w-6 h-6 bg-accent/20 rounded flex items-center justify-center">
              <div className="w-2 h-2 bg-accent rounded-full"></div>
            </div>
            <div>
              <p className="text-white font-medium">Просмотр оборудования</p>
              <p className="text-slate-400 text-sm">Список всего оборудования с фильтрацией и поиском</p>
            </div>
          </div>
          <div className="flex gap-3">
            <div className="flex-shrink-0 w-6 h-6 bg-accent/20 rounded flex items-center justify-center">
              <div className="w-2 h-2 bg-accent rounded-full"></div>
            </div>
            <div>
              <p className="text-white font-medium">Проведение диагностики</p>
              <p className="text-slate-400 text-sm">Заполнение чек-листов и отправка результатов</p>
            </div>
          </div>
          <div className="flex gap-3">
            <div className="flex-shrink-0 w-6 h-6 bg-accent/20 rounded flex items-center justify-center">
              <div className="w-2 h-2 bg-accent rounded-full"></div>
            </div>
            <div>
              <p className="text-white font-medium">Офлайн-режим</p>
              <p className="text-slate-400 text-sm">Работа без интернета с последующей синхронизацией</p>
            </div>
          </div>
          <div className="flex gap-3">
            <div className="flex-shrink-0 w-6 h-6 bg-accent/20 rounded flex items-center justify-center">
              <div className="w-2 h-2 bg-accent rounded-full"></div>
            </div>
            <div>
              <p className="text-white font-medium">Документы и сертификаты</p>
              <p className="text-slate-400 text-sm">Просмотр и скачивание документов специалиста</p>
            </div>
          </div>
          <div className="flex gap-3">
            <div className="flex-shrink-0 w-6 h-6 bg-accent/20 rounded flex items-center justify-center">
              <div className="w-2 h-2 bg-accent rounded-full"></div>
            </div>
            <div>
              <p className="text-white font-medium">Статистика и отчеты</p>
              <p className="text-slate-400 text-sm">Просмотр статистики работы и создание отчетов</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MobileApp;

