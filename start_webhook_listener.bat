@echo off
title uz_ai_dev - GitHub Webhook Listener
cd /d "%~dp0"

REM Listener yiqilib qolsa avtomatik qayta ishga tushadi
:loop
echo [%date% %time%] Webhook listener ishga tushmoqda...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0github_webhook_listener.ps1"
echo [%date% %time%] Listener to'xtadi. 5 soniyada qayta urinaman... (yopish uchun oynani yoping)
timeout /t 5 /nobreak >nul
goto loop
