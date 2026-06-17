#!/bin/bash
# Обновление Let's Encrypt для neftcontrol.ru (webroot, nginx в Docker).
set -euo pipefail

CERT_NAME="neftcontrol.ru"
WEBROOT="/var/www/certbot"
APP_DIR="/opt/es-td-ngo"

mkdir -p "${WEBROOT}/.well-known/acme-challenge"
chmod -R a+rX "${WEBROOT}"

certbot renew --quiet --webroot -w "${WEBROOT}" --cert-name "${CERT_NAME}" || {
  echo "webroot renew failed, trying standalone..."
  cd "${APP_DIR}"
  docker compose stop frontend
  certbot renew --quiet --cert-name "${CERT_NAME}"
  docker compose up -d frontend
}

docker exec es_td_ngo_frontend nginx -s reload 2>/dev/null || true
echo "SSL renewed: $(openssl x509 -in /etc/letsencrypt/live/${CERT_NAME}/fullchain.pem -noout -enddate)"
