# rebull2

Бот/пакетный монитор для Lineage 2 (хроника Main) с инжекцией DLL.

## Компоненты

| Компонент | Файл | Описание |
|---|---|---|
| DLL | `rebull2.dll` | Инжектируется в процесс L2, хукает ws2_32 |
| UI | `rebull2_ui.exe` | Отображение пакетов, управление |
| Инжектор | `rebull2_injector.exe` | Загружает DLL в процесс клиента |

## Быстрый старт

1. Запустить клиент Lineage 2 (arcaneworld.net или любой Main-сервер)
2. Запустить `rebull2_ui.exe`
3. Запустить `rebull2_injector.exe` (или указать путь к DLL через аргумент)
4. В UI нажать **Старт**

## Структура проекта

```
rebull2/
├── src/
│   ├── dll/               # rebull2.dll
│   │   ├── core/
│   │   │   ├── Scanner.pas   # Signature scanner (поиск паттернов)
│   │   │   └── Hooks.pas     # Хуки ws2_32 (inline patching)
│   │   ├── ipc/
│   │   │   └── PipeServer.pas # Named Pipe сервер
│   │   └── rebull2.dpr
│   ├── injector/
│   │   └── rebull2_injector.dpr
│   └── ui/
│       ├── forms/
│       │   └── MainForm.pas
│       ├── ipc/
│       │   └── PipeClient.pas
│       └── rebull2_ui.dpr
├── include/
│   └── Protocol.pas       # Общие типы IPC-протокола
├── docs/
│   ├── BUILD.md
│   ├── API.md
│   └── PATTERNS.md
└── patterns/              # JSON-база паттернов хроник
```

## Требования

- Windows 7/10/11 x86 (клиент L2 — 32-bit)
- Delphi 10.x+ или Lazarus/FPC для сборки
- Запуск с правами администратора (для инжекции)
