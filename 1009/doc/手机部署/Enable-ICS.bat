@echo off
setlocal enabledelayedexpansion
title Enable ICS sharing for Raspberry Pi

net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo   [!] Administrator rights required. Requesting elevation...
  echo       Click "Yes" in the UAC dialog.
  echo.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set REGFILE=%~dp0Enable-ICS.reg

echo ============================================================
echo   Enable Internet Connection Sharing
echo   WLAN  --^>  Ethernet  (to Raspberry Pi)
echo ============================================================
echo.

echo [1/6] Set SharedAccess service to auto and ensure it runs
sc config SharedAccess start= auto >nul 2>&1
net start SharedAccess >nul 2>&1
sc query SharedAccess | findstr /i "STATE"
echo.

echo [2/6] Import ICS configuration from:
echo       %REGFILE%
if not exist "%REGFILE%" (
  echo   [!] reg file not found, aborting.
  goto :end
)
reg import "%REGFILE%"
if errorlevel 1 (
  echo   [!] registry import FAILED
) else (
  echo   registry import OK
)
echo.

echo [3/6] Restart SharedAccess service to apply
net stop SharedAccess >nul 2>&1
net start SharedAccess >nul 2>&1
sc query SharedAccess | findstr /i "STATE"
echo.

echo [4/6] Waiting for the DHCP allocator on the Ethernet adapter
timeout /t 8 /nobreak >nul
echo.

echo [5/6] All adapter addresses now (expect 192.168.137.1 on Ethernet)
echo ------------------------------------------------------------
ipconfig
echo ------------------------------------------------------------
echo.

echo [6/6] Ethernet link state (index 5 should read connected)
netsh interface ipv4 show interfaces | findstr /r "^ *5 "
echo.
echo   If it shows disconnected, plug the network cable into the Pi first.
echo   No lease renew is needed: ICS assigns 192.168.137.1 itself.
echo.

echo ============================================================
echo   NEXT STEP: power-cycle the Raspberry Pi
echo   so it requests a fresh 192.168.137.x address from this PC.
echo ============================================================
echo.
echo Registry check:
reg query "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\SharedAccess" 2>nul

:end
echo.
echo Press any key to close...
pause >nul
