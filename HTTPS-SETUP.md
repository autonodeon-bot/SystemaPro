# Настройка HTTPS для ЕС ТД НГО

## Что нужно от вас

1. **Сертификат и ключ** для домена (например от Let's Encrypt или вашего провайдера):
   - `fullchain.pem` — сертификат
   - `privkey.pem` — закрытый ключ

2. **Домен**, указывающий на IP сервера (A-запись), либо использование IP с самоподписанным сертификатом (браузер покажет предупреждение).

## Вариант 1: Let's Encrypt (certbot)

На сервере (Ubuntu/Debian):

```bash
apt install certbot
certbot certonly --standalone -d your-domain.com
# Сертификаты: /etc/letsencrypt/live/your-domain.com/fullchain.pem и privkey.pem
```

Скопируйте их в каталог проекта, например:

```bash
mkdir -p /opt/es-td-ngo/certs
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem /opt/es-td-ngo/certs/
cp /etc/letsencrypt/live/your-domain.com/privkey.pem /opt/es-td-ngo/certs/
chmod 600 /opt/es-td-ngo/certs/privkey.pem
```

## Вариант 2: Nginx с SSL

В проекте можно добавить конфиг `nginx/default-ssl.conf` (пример):

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    client_max_body_size 100m;
    proxy_connect_timeout 120s;
    proxy_send_timeout 120s;
    proxy_read_timeout 120s;

    location / {
        proxy_pass http://frontend:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/ {
        proxy_pass http://backend:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /mobile/ {
        alias /var/www/mobile-apk/;
        default_type application/vnd.android.package-archive;
    }
}
```

В `docker-compose` для nginx добавить монтирование сертификатов:

```yaml
volumes:
  - ./certs:/etc/nginx/certs:ro
```

И подключить конфиг `default-ssl.conf` в контейнере nginx.

## Редирект HTTP → HTTPS

В существующий `server { listen 80; ... }` в начале блока можно добавить:

```nginx
return 301 https://$host$request_uri;
```

(Тогда весь трафик по 80 порту будет перенаправляться на HTTPS.)

## Мобильное приложение

После перехода на HTTPS замените в настройках приложения (или в коде) `baseUrl` на `https://your-domain.com`, чтобы запросы шли по защищённому каналу.
