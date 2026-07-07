@echo off
setlocal enabledelayedexpansion

:: ========================================================
:: BUILD.bat — сборка rebull2 под Windows
:: Запускать из корня репозитория: BUILD.bat [delphi|fpc]
::
:: Артефакты в bin\:
::   rebull2.dll      — payload (IAT hooks + pipe server)
::   version.dll      — прокси для DLL Hijacking
::   rebull2_ui.exe   — UI
::
:: Деплой: скопировать version.dll + rebull2.dll в папку L2.exe
:: ========================================================

set MODE=%1
if "%MODE%"=="" set MODE=delphi

echo.
echo === rebull2 Build Script ===
echo Mode: %MODE%
echo.

if not exist bin       mkdir bin
if not exist obj\dll   mkdir obj\dll
if not exist obj\proxy mkdir obj\proxy
if not exist obj\ui    mkdir obj\ui

:: --------------------------------------------------------
:: DELPHI
:: --------------------------------------------------------
if /I "%MODE%"=="delphi" (

  set DCC32=
  for /d %%D in ("%programfiles(x86)%\Embarcadero\Studio\*") do (
    if exist "%%D\bin\dcc32.exe" set DCC32=%%D\bin\dcc32.exe
  )
  for /d %%D in ("%programfiles%\Embarcadero\Studio\*") do (
    if exist "%%D\bin\dcc32.exe" set DCC32=%%D\bin\dcc32.exe
  )
  if "!DCC32!"=="" (
    echo [ERROR] dcc32.exe не найден. Укажите путь вручную.
    exit /b 1
  )
  echo Используем: !DCC32!

  echo.
  echo [1/3] Сборка rebull2.dll (payload)...
  "!DCC32!" ^
    src\dll\rebull2.dpr ^
    -I include ^
    -U include;src\dll\core;src\dll\ipc ^
    -E bin -N obj\dll ^
    -DWINDOWS -$O+ -$D- -WD
  if errorlevel 1 ( echo [FAIL] rebull2.dll && exit /b 1 )
  echo [OK] bin\rebull2.dll

  echo.
  echo [2/3] Сборка version.dll (proxy)...
  "!DCC32!" ^
    src\proxy\VersionProxy.dpr ^
    -E bin -N obj\proxy ^
    -$O+ -$D- -WD
  if errorlevel 1 ( echo [FAIL] version.dll && exit /b 1 )
  echo [OK] bin\version.dll

  echo.
  echo [3/3] Сборка rebull2_ui.exe...
  "!DCC32!" ^
    src\ui\rebull2_ui.dpr ^
    -I include ^
    -U include;src\ui\ipc;src\ui\forms ^
    -E bin -N obj\ui ^
    -$O+ -$D-
  if errorlevel 1 ( echo [FAIL] rebull2_ui.exe && exit /b 1 )
  echo [OK] bin\rebull2_ui.exe

  goto :done
)

:: --------------------------------------------------------
:: FPC
:: --------------------------------------------------------
if /I "%MODE%"=="fpc" (

  where fpc >nul 2>&1
  if errorlevel 1 ( echo [ERROR] fpc.exe не найден в PATH && exit /b 1 )

  echo.
  echo [1/3] Сборка rebull2.dll...
  fpc -Twindows -Pi386 -WD -DWINDOWS ^
    -Fu include -Fu src\dll\core -Fu src\dll\ipc ^
    -FE bin -FU obj\dll ^
    src\dll\rebull2.dpr
  if errorlevel 1 ( echo [FAIL] rebull2.dll && exit /b 1 )
  echo [OK] bin\rebull2.dll

  echo.
  echo [2/3] Сборка version.dll...
  fpc -Twindows -Pi386 -WD -DWINDOWS ^
    -FE bin -FU obj\proxy ^
    src\proxy\VersionProxy.dpr
  if errorlevel 1 ( echo [FAIL] version.dll && exit /b 1 )
  echo [OK] bin\version.dll

  echo.
  echo [3/3] Сборка rebull2_ui.exe...
  fpc -Twindows -Pi386 -WG -DWINDOWS ^
    -Fu include -Fu src\ui\ipc -Fu src\ui\forms ^
    -FE bin -FU obj\ui ^
    src\ui\rebull2_ui.dpr
  if errorlevel 1 ( echo [FAIL] rebull2_ui.exe && exit /b 1 )
  echo [OK] bin\rebull2_ui.exe

  goto :done
)

echo [ERROR] Неизвестный режим. Используй: BUILD.bat delphi  или  BUILD.bat fpc
exit /b 1

:done
echo.
echo === Готово ===
echo.
echo Деплой:
echo   1. Скопируй bin\version.dll  ^→ папка с L2.exe
echo   2. Скопируй bin\rebull2.dll  ^→ папка с L2.exe
echo   3. Запусти rebull2_ui.exe
echo   4. Запусти L2.exe
echo.
dir /b bin\
echo.
