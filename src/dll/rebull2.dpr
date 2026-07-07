library rebull2;

{
  rebull2.dll — инжектируемая DLL для перехвата пакетов Lineage 2 (хроника Main).

  Точка входа: DllMain обрабатывает DLL_PROCESS_ATTACH / DLL_PROCESS_DETACH.
  При загрузке:
    1. Создаёт именованный Pipe-сервер (IPC с UI)
    2. Устанавливает хуки на ws2_32.send/recv/WSASend/WSARecv
  При выгрузке:
    1. Снимает хуки
    2. Останавливает Pipe-сервер
}

uses
  Windows,
  SysUtils,
  Hooks     in 'core\Hooks.pas',
  PipeServer in 'ipc\PipeServer.pas',
  Protocol  in '..\..\include\Protocol.pas';

{$R *.res}

var
  GPipe : TPipeServer = nil;

// Callback из хуков → отправляем пакет в UI через pipe
procedure OnPacketCaptured(Direction: Byte; Data: PByte; Len: Integer);
begin
  try
    if Assigned(GPipe) then
      GPipe.SendPacket(Direction, Data, Cardinal(Len));
  except
    // Никогда не роняем клиент — глотаем все исключения в callback
  end;
end;

// Callback из UI → обрабатываем команды управления
procedure OnUICommand(Cmd: Byte; Data: PByte; Len: Cardinal);
begin
  case Cmd of
    CMD_START:
      begin
        HooksInstall(OnPacketCaptured);
        if Assigned(GPipe) then
          GPipe.SendLog('Перехват запущен');
      end;
    CMD_STOP:
      begin
        HooksRemove;
        if Assigned(GPipe) then
          GPipe.SendLog('Перехват остановлен');
      end;
  end;
end;

procedure DllMain(Reason: DWORD);
begin
  case Reason of
    DLL_PROCESS_ATTACH:
      begin
        DisableThreadLibraryCalls(HInstance);
        try
          // Pipe-сервер запускается первым — UI может подключиться до хуков
          GPipe := TPipeServer.Create(OnUICommand);
          // Хуки ставим сразу — перехватываем всё с момента загрузки
          HooksInstall(OnPacketCaptured);
        except
          // Провал инициализации не должен крашить клиент
        end;
      end;

    DLL_PROCESS_DETACH:
      begin
        try
          HooksRemove;
          FreeAndNil(GPipe);
        except
          // Аналогично — исключения при выгрузке недопустимы
        end;
      end;
  end;
end;

begin
  DllProc := @DllMain;
  DllMain(DLL_PROCESS_ATTACH);
end.
