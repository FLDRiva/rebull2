unit PipeServer;

{
  Named Pipe сервер внутри DLL.

  DLL создаёт pipe-инстанс и ждёт подключения UI.
  Поддерживает одновременно одного клиента (UI).
  Работает в отдельном потоке, не блокирует игровой поток.

  Протокол: TIPCHeader + payload (см. include/Protocol.pas).
}

interface

uses
  Windows, SysUtils, Classes, Protocol;

type
  // Callback для приёма команды от UI
  TCommandCallback = procedure(Cmd: Byte; Data: PByte; Len: Cardinal);

  { TPipeServer — сервер Named Pipe, работает в фоновом потоке }
  TPipeServer = class
  private
    FPipe       : THandle;
    FThread     : TThread;
    FOnCommand  : TCommandCallback;
    FActive     : Boolean;

    procedure CreatePipeInstance;
    procedure WorkerProc;
    procedure HandleCommand(const AHeader: TIPCHeader; AData: PByte);
  public
    constructor Create(AOnCommand: TCommandCallback);
    destructor Destroy; override;

    { Отправить сообщение подключённому UI }
    procedure Send(AMsgType: Byte; AData: PByte; ALen: Cardinal);

    { Отправить информацию о пакете }
    procedure SendPacket(ADirection: Byte; AData: PByte; ALen: Cardinal);

    { Отправить строку лога }
    procedure SendLog(const AMsg: string);

    property Active: Boolean read FActive;
  end;

implementation

uses
  Protocol;

type
  TPipeWorker = class(TThread)
  private
    FOwner: TPipeServer;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TPipeServer);
  end;

{ TPipeWorker }

constructor TPipeWorker.Create(AOwner: TPipeServer);
begin
  inherited Create(False);
  FOwner := AOwner;
  FreeOnTerminate := False;
end;

procedure TPipeWorker.Execute;
begin
  FOwner.WorkerProc;
end;

{ TPipeServer }

constructor TPipeServer.Create(AOnCommand: TCommandCallback);
begin
  inherited Create;
  FPipe      := INVALID_HANDLE_VALUE;
  FOnCommand := AOnCommand;
  FActive    := False;
  FThread    := TPipeWorker.Create(Self);
end;

destructor TPipeServer.Destroy;
begin
  FActive := False;
  // Разбудить поток, создав временный клиент (чтобы ConnectNamedPipe вернулся)
  var hTmp := CreateFile(PIPE_NAME, GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);
  if hTmp <> INVALID_HANDLE_VALUE then
    CloseHandle(hTmp);

  FThread.Terminate;
  FThread.WaitFor;
  FThread.Free;

  if FPipe <> INVALID_HANDLE_VALUE then
    CloseHandle(FPipe);

  inherited;
end;

procedure TPipeServer.CreatePipeInstance;
begin
  if FPipe <> INVALID_HANDLE_VALUE then
    CloseHandle(FPipe);

  FPipe := CreateNamedPipe(
    PIPE_NAME,
    PIPE_ACCESS_DUPLEX or FILE_FLAG_WRITE_THROUGH,
    PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT,
    1,          // только один экземпляр
    65536,      // outgoing buffer
    65536,      // incoming buffer
    0,
    nil
  );
end;

procedure TPipeServer.WorkerProc;
var
  Header  : TIPCHeader;
  Data    : array of Byte;
  BytesRead: DWORD;
begin
  while not FThread.Terminated do
  begin
    CreatePipeInstance;
    if FPipe = INVALID_HANDLE_VALUE then
    begin
      Sleep(1000);
      Continue;
    end;

    FActive := False;
    // Ожидаем подключения UI
    if not ConnectNamedPipe(FPipe, nil) then
    begin
      if GetLastError <> ERROR_PIPE_CONNECTED then
        Continue;
    end;
    FActive := True;

    // Цикл чтения команд от UI
    while not FThread.Terminated do
    begin
      if not ReadFile(FPipe, Header, SizeOf(Header), BytesRead, nil) then
        Break;
      if BytesRead <> SizeOf(Header) then
        Break;

      if Header.PayloadLen > 0 then
      begin
        SetLength(Data, Header.PayloadLen);
        if not ReadFile(FPipe, Data[0], Header.PayloadLen, BytesRead, nil) then
          Break;
      end;

      if Header.PayloadLen > 0 then
        HandleCommand(Header, @Data[0])
      else
        HandleCommand(Header, nil);
    end;

    FActive := False;
    DisconnectNamedPipe(FPipe);
  end;
end;

procedure TPipeServer.HandleCommand(const AHeader: TIPCHeader; AData: PByte);
begin
  if Assigned(FOnCommand) then
    FOnCommand(AHeader.MsgType, AData, AHeader.PayloadLen);
end;

procedure TPipeServer.Send(AMsgType: Byte; AData: PByte; ALen: Cardinal);
var
  Header   : TIPCHeader;
  Written  : DWORD;
begin
  if not FActive or (FPipe = INVALID_HANDLE_VALUE) then
    Exit;

  Header.MsgType    := AMsgType;
  Header.PayloadLen := ALen;

  // Заголовок и данные — двумя отдельными WriteFile для атомарности сообщения
  if not WriteFile(FPipe, Header, SizeOf(Header), Written, nil) then
    Exit;

  if (ALen > 0) and (AData <> nil) then
    WriteFile(FPipe, AData^, ALen, Written, nil);
end;

procedure TPipeServer.SendPacket(ADirection: Byte; AData: PByte; ALen: Cardinal);
var
  Info    : TPacketInfo;
  Buf     : array of Byte;
begin
  if not FActive then
    Exit;

  Info.Direction := ADirection;
  Info.Timestamp := GetTickCount64;
  Info.DataLen   := ALen;

  SetLength(Buf, SizeOf(TPacketInfo) + ALen);
  Move(Info, Buf[0], SizeOf(TPacketInfo));
  if (ALen > 0) and (AData <> nil) then
    Move(AData^, Buf[SizeOf(TPacketInfo)], ALen);

  Send(MSG_PACKET, @Buf[0], Length(Buf));
end;

procedure TPipeServer.SendLog(const AMsg: string);
var
  Bytes: TBytes;
begin
  if not FActive then
    Exit;

  Bytes := TEncoding.UTF8.GetBytes(AMsg);
  Send(MSG_LOG, @Bytes[0], Length(Bytes));
end;

end.
