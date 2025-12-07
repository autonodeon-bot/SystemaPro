# Инструкция по ручному обновлению версии на сервере

## Описание
Эта инструкция поможет вам вручную обновить версию frontend на сервере до 3.1.0 (2025-Q4).

## Предварительные требования
- Установлен PuTTY (plink.exe и pscp.exe должны быть в PATH)
- Доступ к серверу по SSH
- Docker и Docker Compose установлены на сервере

## Шаги обновления

### 1. Проверка версии в исходном коде
Убедитесь, что в файле `pages/TechSpecs.tsx` указана версия **3.1.0 (2025-Q4)**:
```tsx
<p className="text-sm sm:text-base text-slate-400">Версия архитектуры: 3.1.0 (2025-Q4)</p>
```

### 2. Запуск bat-файла
Запустите файл `deploy-new-version.bat` из корневой папки проекта.

### 3. Что делает скрипт
1. Копирует все необходимые файлы на сервер в `/opt/es-td-ngo/`
2. Останавливает старый контейнер frontend
3. Удаляет старый контейнер
4. Пересобирает образ frontend БЕЗ КЭША
5. Запускает новый контейнер
6. Проверяет версию в собранном JS файле

### 4. Проверка результата
После завершения скрипта:
1. Откройте браузер
2. Перейдите на http://5.129.203.182/#/specs
3. Проверьте, что версия отображается как **3.1.0 (2025-Q4)**

## Ручное выполнение команд (если bat-файл не работает)

### Шаг 1: Копирование файлов
```bash
# Копирование папок
pscp -batch -pw ydR9+CL3?S@dgH -r pages root@5.129.203.182:/opt/es-td-ngo/
pscp -batch -pw ydR9+CL3?S@dgH -r components root@5.129.203.182:/opt/es-td-ngo/
pscp -batch -pw ydR9+CL3?S@dgH -r nginx root@5.129.203.182:/opt/es-td-ngo/

# Копирование файлов
pscp -batch -pw ydR9+CL3?S@dgH index.html index.tsx App.tsx package.json package-lock.json vite.config.ts constants.ts frontend.Dockerfile docker-compose.yml root@5.129.203.182:/opt/es-td-ngo/
```

### Шаг 2: Пересборка на сервере
```bash
plink -batch -ssh -pw ydR9+CL3?S@dgH root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose stop frontend && docker-compose rm -f frontend && docker-compose build --no-cache frontend && docker-compose up -d frontend"
```

### Шаг 3: Проверка версии
```bash
plink -batch -ssh -pw ydR9+CL3?S@dgH root@5.129.203.182 "docker exec es_td_ngo_frontend sh -c 'JS_FILE=\$(ls /usr/share/nginx/html/assets/*.js 2>/dev/null | head -1); if [ -f \"\$JS_FILE\" ]; then if grep -q \"3.1.0\" \"\$JS_FILE\"; then echo \"OK: Версия 3.1.0 найдена\"; else echo \"ERROR: Версия 3.1.0 НЕ найдена\"; grep -o \"3\.[0-9]\.[0-9]\" \"\$JS_FILE\" | sort -u | head -1; fi; else echo \"JS файл не найден\"; fi'"
```

## Устранение проблем

### Проблема: Версия все еще 3.0.0
**Решение:**
1. Убедитесь, что в `pages/TechSpecs.tsx` указана версия 3.1.0
2. Проверьте, что все файлы скопированы на сервер
3. Убедитесь, что образ пересобран БЕЗ КЭША (флаг `--no-cache`)
4. Подождите 2-5 минут после пересборки (сборка может занять время)
5. Очистите кэш браузера (Ctrl+Shift+Delete)

### Проблема: Ошибка при копировании файлов
**Решение:**
1. Проверьте подключение к серверу: `plink -batch -ssh -pw ydR9+CL3?S@dgH root@5.129.203.182 "echo test"`
2. Убедитесь, что путь `/opt/es-td-ngo/` существует на сервере
3. Проверьте права доступа к папке

### Проблема: Docker не собирает образ
**Решение:**
1. Проверьте, что Docker запущен на сервере
2. Проверьте логи: `docker-compose logs frontend`
3. Убедитесь, что все файлы скопированы правильно

## Время выполнения
- Копирование файлов: 1-2 минуты
- Пересборка образа: 3-5 минут
- **Общее время: 5-7 минут**

## Контакты
При возникновении проблем проверьте логи на сервере:
```bash
plink -batch -ssh -pw ydR9+CL3?S@dgH root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose logs frontend --tail 50"
```










