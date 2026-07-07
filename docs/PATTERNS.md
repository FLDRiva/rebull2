# Формат паттернов для Signature Scanner

Паттерны хранятся в `patterns/` в формате JSON.

## Формат файла

```json
{
  "chronicle": "Main",
  "version": "1.0",
  "patterns": {
    "имя_паттерна": {
      "pattern": "55 8B EC ?? ?? 8B 45 08",
      "offset": 0,
      "description": "Что находит этот паттерн"
    }
  }
}
```

## Wildcards

`??` — любой байт. Пример:
```
55 8B EC ?? ?? 8B 45 08 ?? 5D C3
```

## Текущие паттерны (Main)

Файл: `patterns/main.json`

| Имя | Описание |
|---|---|
| `send_packet` | Функция отправки пакета клиентом |
| `recv_packet` | Функция обработки входящего пакета |
| `blowfish_init` | Инициализация Blowfish-ключа |
| `blowfish_key` | Буфер с текущим Blowfish-ключом |

## Как найти новые паттерны

1. Открыть клиент в x32dbg / IDA
2. Поставить breakpoint на `ws2_32.send`
3. Найти вызывающую функцию (call stack)
4. Выделить уникальные байты вокруг точки входа
5. Заменить изменяемые байты на `??`
6. Добавить в JSON

## Использование в коде

```pascal
var
  Scanner: TSignatureScanner;
  Addr: Pointer;
begin
  Scanner := TSignatureScanner.Create(GetModuleHandle(nil));
  try
    Addr := Scanner.Find('55 8B EC ?? ?? 8B 45 08');
    if Addr <> nil then
      // нашли, используем
  finally
    Scanner.Free;
  end;
end;
```
