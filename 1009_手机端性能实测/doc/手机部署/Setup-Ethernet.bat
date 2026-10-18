@echo off
setlocal enabledelayedexpansion
title Set static IPs on Ethernet for Raspberry Pi

net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo   [!] Administrator rights required. Requesting elevation...
  echo       Click "Yes" in the UAC dialog.
  echo.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

rem ------------------------------------------------------------------
rem  The adapter is addressed by its numeric IPv4 interface index
rem  (5 on this machine) instead of by name, because the localized
rem  name contains non-ASCII characters that cmd.exe mangles.
rem ------------------------------------------------------------------
set IDX=5

echo ============================================================
echo   Assign static addresses to Ethernet (interface index %IDX%)
echo     192.168.137.1/24  (ICS pool range)
echo     192.168.43.1/24   (old hotspot range)
echo ============================================================
echo.

echo [1/5] All IPv4 interfaces (confirm index %IDX% is the Ethernet port)
netsh interface ipv4 show interfaces
echo.

echo [2/5] Current addresses before the change
netsh interface ipv4 show addresses
echo.

echo [3/5] Set primary address 192.168.137.1/24 on index %IDX%
netsh interface ipv4 set address %IDX% static 192.168.137.1 255.255.255.0
echo   exit code = %errorlevel%
echo.

echo [4/5] Add secondary address 192.168.43.1/24 on index %IDX%
netsh interface ipv4 add address %IDX% 192.168.43.1 255.255.255.0
echo   exit code = %errorlevel%
echo.

echo [5/5] Addresses after the change
echo ------------------------------------------------------------
netsh interface ipv4 show addresses
echo ------------------------------------------------------------
echo.

echo ============================================================
echo   NEXT STEPS
echo    1. Power-cycle the Raspberry Pi (unplug, wait 5s, replug)
echo    2. Wait about 30 seconds for it to boot and settle
echo    3. Then report back
echo.
echo   Expected results:
echo    - This PC Ethernet     192.168.137.1
echo    - Pi if it uses DHCP   192.168.137.x
echo    - Pi if it kept old IP 192.168.43.33
echo ============================================================
echo.
echo Quick reachability probes (may fail before the Pi boots):
ping -n 2 192.168.43.33
ping -n 2 192.168.137.2
ping -n 2 192.168.137.100

:end
echo.
echo Press any key to close...
pause >nul
