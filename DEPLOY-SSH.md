# Деплой на сервер по SSH-ключу

Деплой без пароля: используется только SSH-ключ.

## 1. Проверка OpenSSH

В PowerShell выполните:

```powershell
ssh -V
scp
```

Должны быть доступны команды `ssh` и `scp` (входят в состав Windows 10/11).

## 2. Создание SSH-ключа (если ещё нет)

```powershell
# Ключ в папке пользователя: %USERPROFILE%\.ssh\
ssh-keygen -t ed25519 -C "deploy-systemapro" -f "$env:USERPROFILE\.ssh\id_ed25519_deploy" -N '""'
```

Или без указания файла (по умолчанию `id_ed25519` или `id_rsa`):

```powershell
ssh-keygen -t ed25519 -C "deploy"
# Enter — путь по умолчанию
# Enter — пустая парольная фраза (или введите свою)
```

## 3. Добавление ключа на сервер

**Сервер:** `root@5.129.203.182`

### Вариант A: ssh-copy-id (если есть)

```powershell
# Один раз ввести пароль — ключ скопируется
ssh-copy-id -i "$env:USERPROFILE\.ssh\id_ed25519.pub" root@5.129.203.182
```

### Вариант B: Вручную (если ssh-copy-id нет)

1. Показать публичный ключ:

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
# или id_rsa.pub
```

2. Подключиться к серверу по паролю:

```powershell
ssh root@5.129.203.182
```

3. На сервере выполнить (вставить свою строку из шага 1 вместо `ВАШ_ПУБЛИЧНЫЙ_КЛЮЧ`):

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "ВАШ_ПУБЛИЧНЫЙ_КЛЮЧ" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```

4. Проверить вход без пароля:

```powershell
ssh root@5.129.203.182 "echo OK"
```

Должно вывести `OK` без запроса пароля.

## 4. Запуск деплоя

Из корня проекта (где лежит `deploy-ssh.ps1`):

```powershell
.\deploy-ssh.ps1
```

Или с указанием политики (если скрипт не запускается):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\deploy-ssh.ps1
```

## 5. Если используется ключ с другим именем

В `deploy-ssh.ps1` можно не менять ничего: по умолчанию `ssh`/`scp` используют ключи из `~/.ssh/` (id_ed25519, id_rsa и т.д.).

Если ключ в своём файле, добавьте в начало скрипта или задайте переменную окружения:

```powershell
$env:SSH_KEY = "$env:USERPROFILE\.ssh\id_ed25519_deploy"
# и в командах: ssh -i $env:SSH_KEY ...
```

Либо настройте `~/.ssh/config`:

```
Host 5.129.203.182
  User root
  IdentityFile C:\Users\ВАШ_ПОЛЬЗОВАТЕЛЬ\.ssh\id_ed25519_deploy
```

## 6. Проверка после деплоя

- Сайт: http://5.129.203.182/
- API: http://5.129.203.182:8000/
- Мобильное приложение (APK): http://5.129.203.182/mobile/app-release.apk
- Контейнеры: `ssh root@5.129.203.182 "docker ps"`

## 7. Загрузка мобильного приложения на сервер

Скрипт `deploy-ssh.ps1` автоматически:

1. Создаёт на сервере каталог `mobile-apk` (монтируется в nginx как `/mobile/`).
2. Если в проекте уже есть собранный APK (`mobile\build\app\outputs\flutter-apk\app-release.apk`) — копирует его на сервер.
3. Если APK нет и в PATH установлен Flutter — выполняет `flutter build apk --release` и затем загружает APK.
4. По версии из `mobile/pubspec.yaml` создаёт копию с именем вида `es-td-ngo-3.21.0-21.apk` для скачивания по версии.

**Ручная сборка перед деплоем (если Flutter не в PATH или нужна только мобилка):**

```powershell
cd mobile
.\build-app.bat
cd ..
.\deploy-ssh.ps1
```

**Только загрузить уже собранный APK на сервер:**

```powershell
scp mobile\build\app\outputs\flutter-apk\app-release.apk root@5.129.203.182:/opt/es-td-ngo/mobile-apk/
```

После загрузки APK доступен по ссылке: http://5.129.203.182/mobile/app-release.apk

### Если APK не скачивается (404/403)

1. **Проверить наличие файла и права на сервере:**
   ```powershell
   ssh root@5.129.203.182 "ls -la /opt/es-td-ngo/mobile-apk/"
   ```
   Должны быть файлы `app-release.apk` и, при наличии, `es-td-ngo-3.21.0-21.apk`.

2. **Выставить права (nginx в контейнере читает как непривилегированный пользователь):**
   ```powershell
   ssh root@5.129.203.182 "chmod -R a+rX /opt/es-td-ngo/mobile-apk"
   ```

3. **Перезапустить frontend-контейнер (подхватить обновлённый nginx и том):**
   ```powershell
   ssh root@5.129.203.182 "cd /opt/es-td-ngo; docker-compose restart frontend"
   ```

4. **Если файлов нет** — загрузить APK вручную и снова выставить права:
   ```powershell
   scp mobile\build\app\outputs\flutter-apk\app-release.apk root@5.129.203.182:/opt/es-td-ngo/mobile-apk/
   ssh root@5.129.203.182 "chmod -R a+rX /opt/es-td-ngo/mobile-apk; docker-compose -f /opt/es-td-ngo/docker-compose.yml restart frontend"
   ```
