# Skill: Деплой проекта

## Описание
Процедура сборки и деплоя всех компонентов «Монитор» (SystemaPro).

## Когда использовать
- Пользователь просит задеплоить/обновить проект
- Нужно собрать Docker образы
- Нужно обновить мобильное приложение

## Компоненты деплоя

### 1. Backend + Frontend (Docker)

#### Сборка
```powershell
# Сборка обоих контейнеров
docker-compose build

# Или по отдельности
docker-compose build backend
docker-compose build frontend
```

#### Запуск
```powershell
docker-compose up -d
```

#### Проверка
```powershell
# Статус контейнеров
docker-compose ps

# Логи backend
docker-compose logs -f backend

# Логи frontend
docker-compose logs -f frontend

# Health check
curl http://localhost:8000/health
```

#### Перезапуск
```powershell
docker-compose restart backend
docker-compose restart frontend

# Или полный перезапуск
docker-compose down
docker-compose up -d
```

### 2. Mobile (Flutter APK)

#### Сборка APK
```powershell
cd mobile
flutter build apk --release
```

#### Размещение
```powershell
# Скопировать APK в директорию раздачи
Copy-Item "mobile\build\app\outputs\flutter-apk\app-release.apk" -Destination "mobile-apk\app.apk"
```

APK будет доступен по адресу: `https://neftcontrol.ru/mobile/app.apk`

### 3. Удалённый деплой (SSH)

#### Через PowerShell скрипт
```powershell
.\deploy-ssh.ps1
```

#### Ручной деплой
```powershell
# 1. Собрать образы локально
docker-compose build

# 2. Сохранить образы
docker save es_td_ngo_backend | gzip > backend.tar.gz
docker save es_td_ngo_frontend | gzip > frontend.tar.gz

# 3. Передать на сервер (SCP)
scp backend.tar.gz user@server:/path/
scp frontend.tar.gz user@server:/path/
scp docker-compose.yml user@server:/path/

# 4. На сервере загрузить и запустить
ssh user@server "cd /path; docker load < backend.tar.gz; docker load < frontend.tar.gz; docker-compose up -d"
```

### 4. SSL сертификаты (Let's Encrypt)

```bash
# На сервере
certbot renew
# Сертификаты автоматически монтируются в контейнер
docker-compose restart frontend
```

## Чек-лист деплоя
- [ ] Все изменения закоммичены
- [ ] Версия обновлена в package.json, pubspec.yaml, main.py
- [ ] Backend собирается без ошибок
- [ ] Frontend собирается без ошибок
- [ ] Docker образы созданы
- [ ] Контейнеры запущены
- [ ] Health check проходит
- [ ] API endpoints доступны
- [ ] Frontend загружается
- [ ] Mobile APK обновлён (если нужно)

## Откат
```powershell
# Вернуть предыдущую версию образов
docker-compose down
docker tag es_td_ngo_backend:previous es_td_ngo_backend:latest
docker tag es_td_ngo_frontend:previous es_td_ngo_frontend:latest
docker-compose up -d
```
