#!/bin/bash
# Скрипт для выполнения на удаленном сервере через SSH

set -e

APP_DIR="/opt/es-td-ngo"

echo "🔧 Настройка сервера для ES TD NGO Platform..."

# Обновление системы
echo "📦 Обновление системы..."
apt-get update -qq
apt-get upgrade -y -qq

# Установка необходимых пакетов
echo "📥 Установка необходимых пакетов..."
apt-get install -y -qq \
    curl \
    wget \
    git \
    ufw \
    htop \
    nano \
    ca-certificates

# Установка Docker
echo "🐳 Установка Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh
    systemctl enable docker
    systemctl start docker
    echo "✅ Docker установлен"
else
    echo "✅ Docker уже установлен"
fi

# Установка Docker Compose
echo "📦 Установка Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "✅ Docker Compose установлен"
else
    echo "✅ Docker Compose уже установлен"
fi

# Создание директории приложения
echo "📁 Создание директории приложения..."
mkdir -p $APP_DIR/backend/certs
chmod 755 $APP_DIR

# Настройка firewall
echo "🔥 Настройка firewall..."
ufw --force enable 2>/dev/null || true
ufw allow 22/tcp 2>/dev/null || true
ufw allow 80/tcp 2>/dev/null || true
ufw allow 8000/tcp 2>/dev/null || true
ufw reload 2>/dev/null || true

echo "✅ Настройка сервера завершена!"

