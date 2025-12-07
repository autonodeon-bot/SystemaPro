@echo off
echo === ОБНОВЛЕНИЕ СЕРВЕРА ===
echo.

echo Копирую код на сервер...
pscp -batch -pw ydR9+CL3?S@dgH -r pages root@5.129.203.182:/opt/es-td-ngo/
pscp -batch -pw ydR9+CL3?S@dgH -r components root@5.129.203.182:/opt/es-td-ngo/
pscp -batch -pw ydR9+CL3?S@dgH -r nginx root@5.129.203.182:/opt/es-td-ngo/
pscp -batch -pw ydR9+CL3?S@dgH index.html index.tsx App.tsx package.json package-lock.json vite.config.ts constants.ts frontend.Dockerfile docker-compose.yml root@5.129.203.182:/opt/es-td-ngo/

echo.
echo Пересобираю frontend на сервере...
plink -batch -ssh -pw ydR9+CL3?S@dgH root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose stop frontend && docker-compose rm -f frontend && docker-compose build --no-cache frontend && docker-compose up -d frontend"

echo.
echo Готово!
pause










