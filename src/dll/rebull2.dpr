library rebull2;

{
  rebull2.dll — payload для DLL Hijacking через version.dll.

  Загружается автоматически нашей version.dll при старте L2.
  Использует IAT hooking вместо inline patching:
    - ws2_32.dll остаётся нетронутым (GameGuard его сканирует)
    - Подменяем указатели в IAT самого L2.exe
}

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

uses
  Windows,
  SysUtils,
  IATHook  in 'core\IATHook.pas',
  PipeServer in 'ipc\PipeServer.pas',
  Protocol in '..\..\include\Protocol.pas';

var
  GPipe : TPipeServer = nil;

procedure OnPacketCaptured(Direction: Byte; Data: PByte; Len: Integer);
begin
  try
    if Assigned(GPipe) then
      GPipe.SendPacket(Direction, Data, Cardinal(Len));
  except end;
end;

procedure OnUICommand(Cmd: Byte; Data: PByte; Len: Cardinal);
var
  hL2: HMODULE;
begin
  case Cmd of
    CMD_START:
      begin
        // Хукаем IAT основного модуля (L2.exe = HInstance=0 → GetModuleHandle(nil))
        hL2 := GetModuleHandle(nil);
        if IATHooksInstall(hL2, OnPacketCaptured) then
        begin
          if Assigned(GPipe) then GPipe.SendLog('IAT хуки установлены');
        end
        else
          if Assigned(GPipe) then GPipe.SendLog('WARN: IAT хуки не найдены (ws2_32 не импортируется?)');
      end;

    CMD_STOP:
      begin
        IATHooksRemove;
        if Assigned(GPipe) then GPipe.SendLog('Хуки сняты');
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
          GPipe := TPipeServer.Create(OnUICommand);
          // Не ставим хуки сразу — ждём CMD_START от UI.
          // Это даёт время GameGuard завершить инициализацию и успокоиться.
          if Assigned(GPipe) then GPipe.SendLog('rebull2.dll загружена');
        except end;
      end;

    DLL_PROCESS_DETACH:
      begin
        try
          IATHooksRemove;
          FreeAndNil(GPipe);
        except end;
      end;
  end;
end;

begin
  DllProc := @DllMain;
  DllMain(DLL_PROCESS_ATTACH);
end.
