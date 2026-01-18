@echo off
chcp 65001 >nul
echo ========================================
echo   ОЧИСТКА СТАРЫХ ОТЧЕТОВ И ЗАДАНИЙ
echo ========================================
echo.
echo ВНИМАНИЕ: Этот скрипт удалит:
echo   - Все отчеты из базы данных
echo   - Все файлы отчетов
echo   - Все обследования (inspections)
echo   - Все задания (assignments)
echo   - Все опросные листы (questionnaires)
echo   - Данные опросников ОПО
echo.
echo Инженеры смогут заново создать задания и заполнить чек-листы.
echo.
set /p confirm="Вы уверены? (yes/no): "
if /i not "%confirm%"=="yes" (
    echo Отменено.
    pause
    exit /b 0
)

echo.
echo [*] Подключение к серверу и выполнение очистки...
echo.

plink -batch -ssh -pw "ydR9+CL3?S@dgH" "root@5.129.203.182" "cd /opt/es-td-ngo/backend && python3 cleanup_old_data.py"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo   ✓ Очистка завершена успешно!
    echo ========================================
) else (
    echo.
    echo ========================================
    echo   ✗ Ошибка при выполнении очистки
    echo ========================================
)

echo.
pause
