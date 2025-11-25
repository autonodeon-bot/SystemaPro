#!/bin/bash

# Скрипт для первоначальной настройки сервера
# Запускать на сервере: bash setup-server.sh

set -e

APP_DIR="/opt/es-td-ngo"

echo "🔧 Настройка сервера для ES TD NGO Platform..."

# Обновление системы
echo "📦 Обновление системы..."
apt-get update
apt-get upgrade -y

# Установка необходимых пакетов
echo "📥 Установка необходимых пакетов..."
apt-get install -y \
    curl \
    wget \
    git \
    ufw \
    htop \
    nano

# Установка Docker
echo "🐳 Установка Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
fi

# Установка Docker Compose
echo "📦 Установка Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Создание директории приложения
echo "📁 Создание директории приложения..."
mkdir -p $APP_DIR/backend/certs
chmod 755 $APP_DIR

# Настройка firewall
echo "🔥 Настройка firewall..."
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 8000/tcp
ufw reload

# Скачивание SSL сертификата для БД
echo "🔐 Скачивание SSL сертификата..."
if [ ! -f "$APP_DIR/backend/certs/root.crt" ]; then
    curl -o $APP_DIR/backend/certs/root.crt https://storage.yandexcloud.net/cloud-certs/CA.pem || {
        echo "⚠️  Не удалось скачать сертификат автоматически"
        echo "   Скачайте вручную и поместите в $APP_DIR/backend/certs/root.crt"
    }
    chmod 644 $APP_DIR/backend/certs/root.crt
fi

echo "✅ Настройка сервера завершена!"
echo ""
echo "📋 Следующие шаги:"
echo "   1. Загрузите проект в $APP_DIR"
echo "   2. Убедитесь, что SSL сертификат находится в $APP_DIR/backend/certs/root.crt"
echo "   3. Запустите: cd $APP_DIR && docker-compose up -d"

