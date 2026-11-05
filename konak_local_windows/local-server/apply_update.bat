@echo off
cd /d "C:\konak_backend\local-server"
echo [%date% %time%] yangilanish 260905.0341-53200f4 boshlandi >> update.log
ping -n 4 127.0.0.1 >nul
if exist "server.exe.bak" del /f /q "server.exe.bak" >> update.log 2>&1
if exist "server.exe" ren "server.exe" "server.exe.bak" >> update.log 2>&1
ren "server.update.exe" "server.exe" >> update.log 2>&1
if not exist "server.exe" (
  echo [%date% %time%] XATO: yangi exe joyiga tushmadi, eskisi qaytarilmoqda >> update.log
  ren "server.exe.bak" "server.exe" >> update.log 2>&1
)
echo [%date% %time%] fayl almashtirildi, server qayta ishga tushirilmoqda >> update.log
schtasks /Run /TN KonakBackend >> update.log 2>&1
ping -n 7 127.0.0.1 >nul
schtasks /Run /TN KonakBackend >> update.log 2>&1
ping -n 9 127.0.0.1 >nul
schtasks /Run /TN KonakBackend >> update.log 2>&1
echo [%date% %time%] qayta ishga tushirish buyurildi >> update.log
