#!/bin/bash
# Обновление Let's Encrypt для neftcontrol.ru (webroot).
# Порт 80 занят nginx в Docker, поэтому standalone (занятие :80) использовать нельзя —
# из‑за этого сертификат ранее истёк: системный certbot.timer не смог продлить.
set -euo pipefail

CERT_NAME="neftcontrol.ru"
WEBROOT="/var/www/certbot"
LIVE="/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem"

mkdir -p "${WEBROOT}/.well-known/acme-challenge"
chmod -R a+rX "${WEBROOT}"

# После продления nginx в контейнере должен перечитать pem (симлинки live/).
HOOK="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > "${HOOK}" << 'EOF'
#!/bin/bash
docker exec es_td_ngo_frontend nginx -s reload 2>/dev/null || true
EOF
chmod +x "${HOOK}"

# Явно webroot: certbot запомнит authenticator и таймер systemd сможет продлевать
# не останавливая сайт.
certbot certonly --webroot -w "${WEBROOT}" \
  -d "${CERT_NAME}" -d "www.${CERT_NAME}" \
  --non-interactive --agree-tos --keep-until-expiring \
  --deploy-hook "${HOOK}"

docker exec es_td_ngo_frontend nginx -s reload 2>/dev/null || true
echo "SSL: $(openssl x509 -in "${LIVE}" -noout -enddate)"
