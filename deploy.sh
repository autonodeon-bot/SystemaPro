#!/bin/bash

# Скрипт деплоя на сервер
# Использование: ./deploy.sh

set -e

SERVER_IP="5.129.203.182"
SERVER_USER="root"
APP_DIR="/opt/es-td-ngo"
SSH_KEY=""

echo "🚀 Начинаем деплой на сервер $SERVER_IP..."

# Проверка наличия SSH ключа или использование пароля
if [ -n "$SSH_KEY" ]; then
    SSH_CMD="ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP"
    SCP_CMD="scp -i $SSH_KEY"
else
    SSH_CMD="ssh $SERVER_USER@$SERVER_IP"
    SCP_CMD="scp"
fi

echo "📦 Создаем структуру директорий на сервере..."
$SSH_CMD "mkdir -p $APP_DIR/backend/certs"

echo "📤 Копируем файлы проекта..."
# Создаем временный архив
tar -czf /tmp/es-td-ngo-deploy.tar.gz \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.env*' \
    .

# Копируем архив
$SCP_CMD /tmp/es-td-ngo-deploy.tar.gz $SERVER_USER@$SERVER_IP:/tmp/

# Распаковываем на сервере
$SSH_CMD "cd $APP_DIR && tar -xzf /tmp/es-td-ngo-deploy.tar.gz && rm /tmp/es-td-ngo-deploy.tar.gz"

echo "🔐 Настраиваем SSL сертификат для БД..."
# Создаем директорию для сертификатов если её нет
$SSH_CMD "mkdir -p $APP_DIR/backend/certs"

echo "⚠️  ВАЖНО: Необходимо скачать SSL сертификат и поместить его в $APP_DIR/backend/certs/root.crt"
echo "   Команда для скачивания:"
echo "   curl -o $APP_DIR/backend/certs/root.crt https://storage.yandexcloud.net/cloud-certs/CA.pem"

echo "🐳 Устанавливаем Docker и Docker Compose..."
$SSH_CMD "command -v docker >/dev/null 2>&1 || {
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
}"

$SSH_CMD "command -v docker-compose >/dev/null 2>&1 || {
    curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}"

echo "🔧 Настраиваем firewall..."
$SSH_CMD "ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 8000/tcp || true"

echo "🏗️  Собираем и запускаем контейнеры..."
$SSH_CMD "cd $APP_DIR && docker-compose down || true"
$SSH_CMD "cd $APP_DIR && docker-compose build --no-cache"
$SSH_CMD "cd $APP_DIR && docker-compose up -d"

echo "⏳ Ждем запуска сервисов..."
sleep 10

echo "🔍 Проверяем статус контейнеров..."
$SSH_CMD "cd $APP_DIR && docker-compose ps"

echo "✅ Деплой завершен!"
echo ""
echo "📋 Полезные команды:"
echo "   Просмотр логов: ssh $SERVER_USER@$SERVER_IP 'cd $APP_DIR && docker-compose logs -f'"
echo "   Остановка: ssh $SERVER_USER@$SERVER_IP 'cd $APP_DIR && docker-compose down'"
echo "   Перезапуск: ssh $SERVER_USER@$SERVER_IP 'cd $APP_DIR && docker-compose restart'"
echo ""
echo "🌐 Приложение доступно по адресу: http://$SERVER_IP"

