@echo off
setlocal enabledelayedexpansion

:: ========================================================
:: BUILD.bat — сборка rebull2 под Windows (Delphi или FPC)
:: Запускать из корня репозитория: BUILD.bat [delphi|fpc]
:: По умолчанию — delphi
:: ========================================================

set MODE=%1
if "%MODE%"=="" set MODE=delphi

echo.
echo === rebull2 Build Script ===
echo Mode: %MODE%
echo.

:: Создаём выходные директории
if not exist bin       mkdir bin
if not exist obj\dll   mkdir obj\dll
if not exist obj\inj   mkdir obj\inj
if not exist obj\ui    mkdir obj\ui

:: --------------------------------------------------------
:: DELPHI (dcc32.exe должен быть в PATH или прописан ниже)
:: --------------------------------------------------------
if /I "%MODE%"=="delphi" (

  :: Попытка найти dcc32.exe автоматически
  set DCC32=
  for /d %%D in ("%programfiles(x86)%\Embarcadero\Studio\*") do (
    if exist "%%D\bin\dcc32.exe" set DCC32=%%D\bin\dcc32.exe
  )
  for /d %%D in ("%programfiles%\Embarcadero\Studio\*") do (
    if exist "%%D\bin\dcc32.exe" set DCC32=%%D\bin\dcc32.exe
  )

  if "!DCC32!"=="" (
    echo [ERROR] dcc32.exe не найден. Укажите путь вручную в BUILD.bat
    exit /b 1
  )
  echo Используем: !DCC32!

  :: ---- rebull2.dll ----
  echo.
  echo [1/3] Сборка rebull2.dll...
  "!DCC32!" ^
    src\dll\rebull2.dpr ^
    -I include ^
    -U include;src\dll\core;src\dll\ipc ^
    -E bin ^
    -N obj\dll ^
    -DWIN32 ^
    -$O+ -$D- ^
    -WD
  if errorlevel 1 ( echo [FAIL] rebull2.dll && exit /b 1 )
  echo [OK] bin\rebull2.dll

  :: ---- rebull2_injector.exe ----
  echo.
  echo [2/3] Сборка rebull2_injector.exe...
  "!DCC32!" ^
    src\injector\rebull2_injector.dpr ^
    -E bin ^
    -N obj\inj ^
    -$O+ -$D-
  if errorlevel 1 ( echo [FAIL] rebull2_injector.exe && exit /b 1 )
  echo [OK] bin\rebull2_injector.exe

  :: ---- rebull2_ui.exe ----
  echo.
  echo [3/3] Сборка rebull2_ui.exe...
  "!DCC32!" ^
    src\ui\rebull2_ui.dpr ^
    -I include ^
    -U include;src\ui\ipc;src\ui\forms ^
    -E bin ^
    -N obj\ui ^
    -$O+ -$D-
  if errorlevel 1 ( echo [FAIL] rebull2_ui.exe && exit /b 1 )
  echo [OK] bin\rebull2_ui.exe

  goto :done
)

:: --------------------------------------------------------
:: FPC (fpc.exe должен быть в PATH)
:: --------------------------------------------------------
if /I "%MODE%"=="fpc" (

  where fpc >nul 2>&1
  if errorlevel 1 ( echo [ERROR] fpc.exe не найден в PATH && exit /b 1 )

  :: ---- rebull2.dll ----
  echo.
  echo [1/3] Сборка rebull2.dll...
  fpc ^
    -Twindows -Pi386 ^
    -WD ^
    -DWINDOWS ^
    -Fu include -Fu src\dll\core -Fu src\dll\ipc ^
    -FE bin -FU obj\dll ^
    src\dll\rebull2.dpr
  if errorlevel 1 ( echo [FAIL] rebull2.dll && exit /b 1 )
  echo [OK] bin\rebull2.dll

  :: ---- rebull2_injector.exe ----
  echo.
  echo [2/3] Сборка rebull2_injector.exe...
  fpc ^
    -Twindows -Pi386 ^
    -WC ^
    -FE bin -FU obj\inj ^
    src\injector\rebull2_injector.dpr
  if errorlevel 1 ( echo [FAIL] rebull2_injector.exe && exit /b 1 )
  echo [OK] bin\rebull2_injector.exe

  :: ---- rebull2_ui.exe ----
  echo.
  echo [3/3] Сборка rebull2_ui.exe...
  fpc ^
    -Twindows -Pi386 ^
    -DWINDOWS ^
    -Fu include -Fu src\ui\ipc -Fu src\ui\forms ^
    -FE bin -FU obj\ui ^
    src\ui\rebull2_ui.dpr
  if errorlevel 1 ( echo [FAIL] rebull2_ui.exe && exit /b 1 )
  echo [OK] bin\rebull2_ui.exe

  goto :done
)

echo [ERROR] Неизвестный режим: %MODE%. Используй: BUILD.bat delphi  или  BUILD.bat fpc
exit /b 1

:done
echo.
echo === Сборка завершена ===
echo Бинарники в папке bin\:
dir /b bin\
echo.
