# Сборка rebull2

## Требования

- **Delphi** 10.3 Rio+ (рекомендуется) или **Lazarus** 2.2+ с FPC 3.2+
- Целевая платформа: **Win32** (клиент L2 — 32-bit даже на 64-bit Windows)
- Запускать Delphi/Lazarus **от администратора** при тестировании

## Порядок сборки

### 1. rebull2.dll

В Delphi: открыть `src/dll/rebull2.dpr`, собрать как **Win32 DLL**.

Настройки проекта:
- Platform: Win32
- Configuration: Release
- Output dir: `bin/`
- Unit output dir: `obj/dll/`

Зависимости включены в проект:
- `core/Scanner.pas`
- `core/Hooks.pas`
- `ipc/PipeServer.pas`
- `../../include/Protocol.pas`

### 2. rebull2_injector.exe

Открыть `src/injector/rebull2_injector.dpr`, собрать как **Win32 Console Application**.

### 3. rebull2_ui.exe

Открыть `src/ui/rebull2_ui.dpr`, собрать как **Win32 GUI Application**.

## Структура bin/

После сборки в `bin/` должно быть:
```
bin/
├── rebull2.dll
├── rebull2_injector.exe
└── rebull2_ui.exe
```

Инжектор и UI автоматически ищут `rebull2.dll` в той же папке.

## Lazarus / FPC (альтернатива)

```bash
# Установка Lazarus на Ubuntu (для разработки на VPS)
sudo apt-get install lazarus fpc

# Кросс-компиляция под Win32
# Требует установленного кросс-компилятора FPC для Windows
apt-get install fpc-source binutils-mingw-w64-i686

# Компиляция DLL
fpc -Twindows -Pi386 -WD src/dll/rebull2.dpr -Fu src/dll/core -Fu src/dll/ipc -Fu include
```

## Замечания

- `Hooks.pas` использует inline JMP patching — не работает если функции ws2_32
  защищены CFG (Control Flow Guard). Для современных Windows 10/11 это не проблема,
  т.к. системные DLL не имеют CFG по умолчанию.
- При первом запуске Windows Defender может сработать на инжектор — добавьте в исключения.
