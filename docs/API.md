# IPC протокол: rebull2.dll ↔ rebull2_ui.exe

Named Pipe: `\\.\pipe\rebull2`

## Формат сообщения

Каждое сообщение состоит из:

```
[TIPCHeader: 5 байт][Payload: PayloadLen байт]
```

### TIPCHeader

| Поле | Тип | Описание |
|---|---|---|
| MsgType | Byte | Тип сообщения (MSG_* или CMD_*) |
| PayloadLen | Cardinal (4 байта) | Длина следующего payload |

## Сообщения DLL → UI

### MSG_PACKET (0x01)

Payload: `TPacketInfo` + сырые байты пакета

```
[TPacketInfo: 13 байт][Data: DataLen байт]
```

| Поле | Тип | Описание |
|---|---|---|
| Direction | Byte | 0=SEND (C→S), 1=RECV (S→C) |
| Timestamp | Int64 | GetTickCount64 |
| DataLen | Cardinal | Длина сырых данных |

### MSG_LOG (0x03)

Payload: строка UTF-8 (без нуль-терминатора).

## Команды UI → DLL

### CMD_START (0x10)

Начать перехват. PayloadLen = 0.

### CMD_STOP (0x11)

Остановить перехват. PayloadLen = 0.

## Примечания

- Pipe работает в режиме `PIPE_TYPE_MESSAGE` — каждое WriteFile = одно сообщение.
- DLL поддерживает одновременно **одного** клиента.
- При обрыве соединения UI автоматически переподключается каждые 500 мс.
