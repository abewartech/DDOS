@echo off
:: ============================================================
::  DDOS / Pentmenu - Windows Launcher
::  Automatically detects WSL, Git Bash, or Cygwin
::  and launches the ddos script through the right environment.
:: ============================================================
setlocal EnableDelayedExpansion

title DDOS - Pentmenu Tools (Windows Launcher)

:: -------------------------------------------------------
:: Check for Administrator privileges (recommended for
:: raw-socket attacks which need elevated rights)
:: -------------------------------------------------------
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  [WARNING] Not running as Administrator.
    echo  Some modules ^(flood attacks, raw sockets^) may fail without elevation.
    echo  Consider right-clicking ddos.bat and choosing "Run as administrator".
    echo.
)

cls
echo.
echo  =========================================================
echo   DDOS / Pentmenu - Windows Launcher
echo  =========================================================
echo.
echo  Detecting available Linux environments...
echo.

:: -------------------------------------------------------
:: Priority 1: WSL (Windows Subsystem for Linux)
::
:: IMPORTANT: We don't just check that wsl.exe exists.
:: We run "wsl echo ok" first to confirm WSL actually works.
:: If the Hyper-V / HCS service is missing or disabled, WSL
:: will return an error (HCS_E_SERVICE_NOT_AVAILABLE) and we
:: fall through gracefully to Git Bash instead of hanging.
:: -------------------------------------------------------
where wsl >nul 2>&1
if %errorLevel% equ 0 (
    echo  [..] WSL binary found. Probing WSL health...

    :: Write WSL probe output to a temp file so we can inspect it
    set "WSL_TEST=%TEMP%\_ddos_wsl_probe.txt"
    wsl echo wsl_ok > "!WSL_TEST!" 2>&1
    set "WSL_ERR=!errorLevel!"

    :: Scan output for known WSL failure strings
    findstr /i "HCS_E SERVICE_NOT_AVAILABLE not installed vmcompute 0x80070422 enable-feature WSL 2 requires virtual machine" "!WSL_TEST!" >nul 2>&1
    if !errorLevel! equ 0 (
        set "WSL_ERR=1"
    )

    :: Also check if the output DOES contain our expected "wsl_ok" string
    findstr /i "wsl_ok" "!WSL_TEST!" >nul 2>&1
    if !errorLevel! neq 0 (
        if "!WSL_ERR!" == "0" set "WSL_ERR=1"
    )

    del /q "!WSL_TEST!" 2>nul

    if "!WSL_ERR!" == "0" (
        echo  [OK] WSL is healthy. Launching via WSL...
        echo.

        :: Convert Windows path to WSL /mnt/<drive>/... path
        set "WIN_PATH=%~dp0ddos"
        set "WIN_PATH=!WIN_PATH:\=/!"
        set "DRIVE_LETTER=!WIN_PATH:~0,1!"
        :: Force lowercase drive letter
        for %%L in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do (
            if /i "!DRIVE_LETTER!" == "%%L" set "DRIVE_LC=%%L"
        )
        set "WSL_PATH=/mnt/!DRIVE_LC!!WIN_PATH:~2!"
        wsl bash "!WSL_PATH!"
        goto :end
    ) else (
        echo  [WARN] WSL is installed but failed the health check.
        echo.
        echo         This is usually caused by one of:
        echo           ^> Hyper-V or virtualization disabled in BIOS/UEFI
        echo           ^> HCS/vmcompute service not running
        echo           ^> WSL installed but not yet configured after reboot
        echo.
        echo         Quick fixes ^(run PowerShell as Administrator^):
        echo           wsl --update
        echo           wsl --set-default-version 1    ^(WSL 1 -- no Hyper-V needed^)
        echo.
        echo  [..] Falling through to Git Bash...
        echo.
    )
)

:: -------------------------------------------------------
:: Priority 2: Git Bash (comes with Git for Windows)
:: -------------------------------------------------------
set "GIT_BASH="
for %%G in (
    "C:\Program Files\Git\bin\bash.exe"
    "C:\Program Files (x86)\Git\bin\bash.exe"
    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    "%ProgramW6432%\Git\bin\bash.exe"
) do (
    if exist %%G (
        set "GIT_BASH=%%~G"
        goto :found_gitbash
    )
)
goto :no_gitbash

:found_gitbash
echo  [OK] Git Bash found: !GIT_BASH!
echo  [!!] Note: Raw-socket flood modules need WSL for full support.
echo  Launching via Git Bash...
echo.
"!GIT_BASH!" --login -i "%~dp0ddos"
goto :end

:no_gitbash
:: -------------------------------------------------------
:: Priority 3: Cygwin
:: -------------------------------------------------------
set "CYGWIN_BASH="
for %%C in (
    "C:\cygwin64\bin\bash.exe"
    "C:\cygwin\bin\bash.exe"
) do (
    if exist %%C (
        set "CYGWIN_BASH=%%~C"
        goto :found_cygwin
    )
)
goto :not_found

:found_cygwin
echo  [OK] Cygwin found: !CYGWIN_BASH!
echo  Launching via Cygwin...
echo.
"!CYGWIN_BASH!" --login -i -c "cd '%~dp0' && bash ddos"
goto :end

:: -------------------------------------------------------
:: Nothing found - show setup instructions
:: -------------------------------------------------------
:not_found
echo  [ERROR] No compatible Linux environment found on this system.
echo.
echo  Install ONE of the following:
echo.
echo  OPTION 1 - WSL ^(Recommended -- full raw-socket support^):
echo    1. Open PowerShell as Administrator and run:
echo         wsl --install
echo    2. Restart your PC
echo    3. In Ubuntu, run:
echo         sudo apt update ^&^& sudo apt install -y ^
echo           bash curl nmap hping3 netcat-openbsd openssl stunnel whois
echo    4. Re-run this launcher
echo.
echo    If WSL errors with Hyper-V/HCS issues, try WSL version 1:
echo         wsl --set-default-version 1
echo.
echo  OPTION 2 - Git for Windows ^(Recon + Extraction modules only^):
echo    https://git-scm.com/download/win
echo.
echo  OPTION 3 - Cygwin ^(moderate support^):
echo    https://www.cygwin.com/
echo    Install packages: bash curl nmap netcat openssl whois
echo.

:end
echo.
pause
endlocal
