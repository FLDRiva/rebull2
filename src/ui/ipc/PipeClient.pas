unit PipeClient;

{
  Named Pipe клиент — сторона UI.

  Работает в отдельном потоке: подключается к DLL, читает сообщения,
  уведомляет через callback. Автоматически переподключается при обрыве.
}

interface

uses
  Windows, SysUtils, Classes, Protocol;

type
  // Событие: получен пакет от DLL
  TOnPacket  = procedure(Direction: Byte; Timestamp: Int64; Data: TBytes) of object;
  // Событие: строка лога от DLL
  TOnLog     = procedure(const Msg: string) of object;
  // Событие: изменение состояния подключения
  TOnConnect = procedure(Connected: Boolean) of object;

  { TPipeClient — клиент Named Pipe, работает в фоновом потоке }
  TPipeClient = class
  private
    FThread     : TThread;
    FOnPacket   : TOnPacket;
    FOnLog      : TOnLog;
    FOnConnect  : TOnConnect;
    FConnected  : Boolean;

    procedure WorkerProc;
    procedure DispatchMessage(const AHeader: TIPCHeader; AData: TBytes);
  public
    constructor Create;
    destructor Destroy; override;

    { Отправить команду в DLL }
    procedure SendCommand(ACmd: Byte; AData: PByte = nil; ALen: Cardinal = 0);

    property Connected  : Boolean      read FConnected;
    property OnPacket   : TOnPacket    read FOnPacket   write FOnPacket;
    property OnLog      : TOnLog       read FOnLog      write FOnLog;
    property OnConnect  : TOnConnect   read FOnConnect  write FOnConnect;
  end;

implementation

type
  TPipeWorker = class(TThread)
  private
    FOwner: TPipeClient;
    FPipe : THandle;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TPipeClient);
    procedure SendRaw(AMsgType: Byte; AData: PByte; ALen: Cardinal);
    property Pipe: THandle read FPipe;
  end;

{ TPipeWorker }

constructor TPipeWorker.Create(AOwner: TPipeClient);
begin
  inherited Create(False);
  FOwner := AOwner;
  FPipe  := INVALID_HANDLE_VALUE;
  FreeOnTerminate := False;
end;

procedure TPipeWorker.SendRaw(AMsgType: Byte; AData: PByte; ALen: Cardinal);
var
  Header  : TIPCHeader;
  Written : DWORD;
begin
  if FPipe = INVALID_HANDLE_VALUE then
    Exit;

  Header.MsgType    := AMsgType;
  Header.PayloadLen := ALen;
  WriteFile(FPipe, Header, SizeOf(Header), Written, nil);
  if (ALen > 0) and (AData <> nil) then
    WriteFile(FPipe, AData^, ALen, Written, nil);
end;

procedure TPipeWorker.Execute;
var
  Header    : TIPCHeader;
  Data      : TBytes;
  BytesRead : DWORD;
begin
  while not Terminated do
  begin
    // Пытаемся подключиться к DLL
    FPipe := CreateFile(PIPE_NAME, GENERIC_READ or GENERIC_WRITE, 0, nil,
      OPEN_EXISTING, 0, 0);

    if FPipe = INVALID_HANDLE_VALUE then
    begin
      // DLL ещё не загружена — ждём
      Sleep(500);
      Continue;
    end;

    // Переводим pipe в режим сообщений
    var Mode: DWORD := PIPE_READMODE_MESSAGE;
    SetNamedPipeHandleState(FPipe, Mode, nil, nil);

    FOwner.FConnected := True;
    if Assigned(FOwner.FOnConnect) then
      TThread.Synchronize(nil, procedure begin FOwner.FOnConnect(True); end);

    // Цикл чтения сообщений
    while not Terminated do
    begin
      if not ReadFile(FPipe, Header, SizeOf(Header), BytesRead, nil) then
        Break;
      if BytesRead <> SizeOf(Header) then
        Break;

      SetLength(Data, Header.PayloadLen);
      if Header.PayloadLen > 0 then
      begin
        if not ReadFile(FPipe, Data[0], Header.PayloadLen, BytesRead, nil) then
          Break;
      end;

      FOwner.DispatchMessage(Header, Data);
    end;

    CloseHandle(FPipe);
    FPipe := INVALID_HANDLE_VALUE;

    FOwner.FConnected := False;
    if Assigned(FOwner.FOnConnect) then
      TThread.Synchronize(nil, procedure begin FOwner.FOnConnect(False); end);

    Sleep(1000); // пауза перед переподключением
  end;
end;

{ TPipeClient }

constructor TPipeClient.Create;
begin
  inherited Create;
  FConnected := False;
  FThread    := TPipeWorker.Create(Self);
end;

destructor TPipeClient.Destroy;
begin
  FThread.Terminate;
  FThread.WaitFor;
  FThread.Free;
  inherited;
end;

procedure TPipeClient.SendCommand(ACmd: Byte; AData: PByte; ALen: Cardinal);
begin
  if FThread is TPipeWorker then
    TPipeWorker(FThread).SendRaw(ACmd, AData, ALen);
end;

procedure TPipeClient.DispatchMessage(const AHeader: TIPCHeader; AData: TBytes);
var
  Info : ^TPacketInfo;
  Pkt  : TBytes;
  Msg  : string;
begin
  case AHeader.MsgType of
    MSG_PACKET:
      begin
        if (Length(AData) < SizeOf(TPacketInfo)) or not Assigned(FOnPacket) then
          Exit;
        Info := @AData[0];
        SetLength(Pkt, Info^.DataLen);
        if Info^.DataLen > 0 then
          Move(AData[SizeOf(TPacketInfo)], Pkt[0], Info^.DataLen);
        var Dir := Info^.Direction;
        var Ts  := Info^.Timestamp;
        TThread.Synchronize(nil, procedure begin FOnPacket(Dir, Ts, Pkt); end);
      end;

    MSG_LOG:
      begin
        if not Assigned(FOnLog) then
          Exit;
        Msg := TEncoding.UTF8.GetString(AData);
        TThread.Synchronize(nil, procedure begin FOnLog(Msg); end);
      end;
  end;
end;

end.
