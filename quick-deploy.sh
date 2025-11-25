#!/bin/bash

# Быстрый деплой - все в одной команде
# Использование: ./quick-deploy.sh

set -e

SERVER_IP="5.129.203.182"
SERVER_USER="root"
APP_DIR="/opt/es-td-ngo"

echo "🚀 Быстрый деплой ES TD NGO Platform"
echo "======================================"

# Шаг 1: Настройка сервера
echo ""
echo "📋 Шаг 1: Настройка сервера..."
ssh $SERVER_USER@$SERVER_IP "bash -s" << 'ENDSSH'
    # Обновление и установка Docker
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
    fi
    
    # Установка Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    # Создание директории
    mkdir -p /opt/es-td-ngo/backend/certs
    
    # Firewall
    ufw allow 22/tcp 2>/dev/null || true
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 8000/tcp 2>/dev/null || true
ENDSSH

# Шаг 2: Скачивание SSL сертификата
echo ""
echo "📋 Шаг 2: Скачивание SSL сертификата..."
ssh $SERVER_USER@$SERVER_IP "bash -s" << 'ENDSSH'
    if [ ! -f /opt/es-td-ngo/backend/certs/root.crt ]; then
        curl -o /opt/es-td-ngo/backend/certs/root.crt https://storage.yandexcloud.net/cloud-certs/CA.pem || {
            echo "⚠️  Не удалось скачать сертификат автоматически"
            echo "   Создайте файл вручную: /opt/es-td-ngo/backend/certs/root.crt"
        }
        chmod 644 /opt/es-td-ngo/backend/certs/root.crt
    fi
ENDSSH

# Шаг 3: Копирование файлов
echo ""
echo "📋 Шаг 3: Копирование файлов проекта..."
tar -czf /tmp/es-td-ngo-deploy.tar.gz \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.env*' \
    --exclude='backend/certs/*.crt' \
    . 2>/dev/null || true

scp /tmp/es-td-ngo-deploy.tar.gz $SERVER_USER@$SERVER_IP:/tmp/

ssh $SERVER_USER@$SERVER_IP "cd $APP_DIR && tar -xzf /tmp/es-td-ngo-deploy.tar.gz && rm /tmp/es-td-ngo-deploy.tar.gz"

# Шаг 4: Запуск контейнеров
echo ""
echo "📋 Шаг 4: Сборка и запуск контейнеров..."
ssh $SERVER_USER@$SERVER_IP "cd $APP_DIR && docker-compose down 2>/dev/null || true"
ssh $SERVER_USER@$SERVER_IP "cd $APP_DIR && docker-compose build --no-cache"
ssh $SERVER_USER@$SERVER_IP "cd $APP_DIR && docker-compose up -d"

# Шаг 5: Проверка
echo ""
echo "📋 Шаг 5: Проверка статуса..."
sleep 5
ssh $SERVER_USER@$SERVER_IP "cd $APP_DIR && docker-compose ps"

echo ""
echo "✅ Деплой завершен!"
echo ""
echo "🌐 Приложение доступно по адресу:"
echo "   Frontend: http://$SERVER_IP"
echo "   Backend API: http://$SERVER_IP:8000"
echo "   Health Check: http://$SERVER_IP:8000/health"
echo ""
echo "📋 Полезные команды:"
echo "   Логи: ssh $SERVER_USER@$SERVER_IP 'cd $APP_DIR && docker-compose logs -f'"
echo "   Статус: ssh $SERVER_USER@$SERVER_IP 'cd $APP_DIR && docker-compose ps'"
echo "   Перезапуск: ssh $SERVER_USER@$SERVER_IP 'cd $APP_DIR && docker-compose restart'"

