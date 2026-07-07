unit Protocol;

{
  Общие типы и константы IPC-протокола между rebull2.dll и rebull2_ui.exe.
  Используется как в DLL, так и в UI — не должен зависеть от WinAPI-специфики.
}

interface

const
  PIPE_NAME = '\\.\pipe\rebull2';

  // Направления пакета
  PKT_DIR_SEND    = 0;  // клиент → сервер
  PKT_DIR_RECV    = 1;  // сервер → клиент

  // Типы IPC-сообщений от DLL к UI
  MSG_PACKET      = $01;  // перехваченный пакет
  MSG_STATUS      = $02;  // статус DLL (подключена/отключена)
  MSG_LOG         = $03;  // строка лога

  // Команды от UI к DLL
  CMD_START       = $10;  // начать перехват
  CMD_STOP        = $11;  // остановить перехват
  CMD_FILTER_SET  = $12;  // установить фильтр пакетов

  MAX_PACKET_SIZE = 65535;

type
  // Заголовок каждого IPC-сообщения (фиксированный размер)
  TIPCHeader = packed record
    MsgType   : Byte;       // MSG_* или CMD_*
    PayloadLen: Cardinal;   // длина данных после заголовка
  end;

  // Перехваченный пакет (следует после TIPCHeader при MsgType=MSG_PACKET)
  TPacketInfo = packed record
    Direction  : Byte;      // PKT_DIR_SEND / PKT_DIR_RECV
    Timestamp  : Int64;     // GetTickCount64
    DataLen    : Cardinal;  // длина сырых байт
    // далее идут DataLen байт сырых данных пакета
  end;

  // Статус DLL (следует после TIPCHeader при MsgType=MSG_STATUS)
  TStatusInfo = packed record
    Connected  : Boolean;
    Capturing  : Boolean;
    SendCount  : Cardinal;
    RecvCount  : Cardinal;
  end;

implementation

end.
