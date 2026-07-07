unit Hooks;

{
  Хуки на ws2_32: send, recv, WSASend, WSARecv.

  Метод: inline patching (5-байтный JMP в начало функции).
  Защита от рекурсии через TLS-флаг на поток.

  Зависимость: MinHook.pas (или собственная реализация).
  Подключать MinHook как внешнюю DLL через dynamic import.
}

interface

uses
  Windows, WinSock2, SysUtils;

type
  // Прототипы оригинальных функций (для вызова через trampoline)
  TFnSend    = function(s: TSocket; const buf; len, flags: Integer): Integer; stdcall;
  TFnRecv    = function(s: TSocket; var buf; len, flags: Integer): Integer; stdcall;
  TFnWSASend = function(s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD;
                        var lpNumberOfBytesSent: DWORD; dwFlags: DWORD;
                        lpOverlapped: LPWSAOVERLAPPED;
                        lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
  TFnWSARecv = function(s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD;
                        var lpNumberOfBytesRecvd: DWORD; var lpFlags: DWORD;
                        lpOverlapped: LPWSAOVERLAPPED;
                        lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;

  // Callback для уведомления о перехваченном пакете
  TPacketCallback = procedure(Direction: Byte; Data: PByte; Len: Integer);

{ Установить хуки. ACallback вызывается при каждом пакете.
  Возвращает True при успехе. }
function HooksInstall(ACallback: TPacketCallback): Boolean;

{ Снять все хуки (вызывать при DLL_PROCESS_DETACH) }
procedure HooksRemove;

implementation

// TLS-индекс для защиты от рекурсии в хуках
var
  GTlsIndex       : DWORD = TLS_OUT_OF_INDEXES;
  GCallback       : TPacketCallback = nil;

  // Trampoline-указатели на оригинальные функции
  GOrig_send      : TFnSend    = nil;
  GOrig_recv      : TFnRecv    = nil;
  GOrig_WSASend   : TFnWSASend = nil;
  GOrig_WSARecv   : TFnWSARecv = nil;

  // Адреса хукнутых функций (для снятия хука)
  GHook_send      : Pointer = nil;
  GHook_recv      : Pointer = nil;
  GHook_WSASend   : Pointer = nil;
  GHook_WSARecv   : Pointer = nil;

  // Оригинальные байты (5 байт на JMP)
  GBak_send       : array[0..4] of Byte;
  GBak_recv       : array[0..4] of Byte;
  GBak_WSASend    : array[0..4] of Byte;
  GBak_WSARecv    : array[0..4] of Byte;

{ ===== Утилиты патчинга ===== }

// Записать JMP rel32 по адресу AFrom → ATo (снять защиту страницы временно)
procedure PatchJmp(AFrom, ATo: Pointer; ABak: PByte);
var
  OldProt : DWORD;
  Rel     : Integer;
  Jmp     : array[0..4] of Byte;
begin
  // Сохраняем оригинальные 5 байт
  Move(AFrom^, ABak^, 5);

  VirtualProtect(AFrom, 5, PAGE_EXECUTE_READWRITE, OldProt);
  try
    Rel    := Integer(PByte(ATo) - PByte(AFrom) - 5);
    Jmp[0] := $E9;
    Move(Rel, Jmp[1], 4);
    Move(Jmp, AFrom^, 5);
  finally
    VirtualProtect(AFrom, 5, OldProt, OldProt);
    FlushInstructionCache(GetCurrentProcess, AFrom, 5);
  end;
end;

// Восстановить оригинальные байты
procedure UnpatchJmp(AAddr: Pointer; ABak: PByte);
var
  OldProt: DWORD;
begin
  VirtualProtect(AAddr, 5, PAGE_EXECUTE_READWRITE, OldProt);
  try
    Move(ABak^, AAddr^, 5);
  finally
    VirtualProtect(AAddr, 5, OldProt, OldProt);
    FlushInstructionCache(GetCurrentProcess, AAddr, 5);
  end;
end;

{ ===== Защита от рекурсии ===== }

function InHook: Boolean; inline;
begin
  Result := TlsGetValue(GTlsIndex) <> nil;
end;

procedure SetInHook(AValue: Boolean); inline;
begin
  if AValue then
    TlsSetValue(GTlsIndex, Pointer(1))
  else
    TlsSetValue(GTlsIndex, nil);
end;

{ ===== Хук-функции ===== }

function Hook_send(s: TSocket; const buf; len, flags: Integer): Integer; stdcall;
begin
  if not InHook then
  begin
    SetInHook(True);
    try
      if Assigned(GCallback) then
        GCallback(0 {PKT_DIR_SEND}, @buf, len);
    finally
      SetInHook(False);
    end;
  end;
  // Вызываем оригинал через временное снятие хука
  UnpatchJmp(GHook_send, @GBak_send);
  try
    Result := TFnSend(GHook_send)(s, buf, len, flags);
  finally
    PatchJmp(GHook_send, @Hook_send, @GBak_send);
  end;
end;

function Hook_recv(s: TSocket; var buf; len, flags: Integer): Integer; stdcall;
begin
  Result := 0;
  if not InHook then
  begin
    SetInHook(True);
    try
      UnpatchJmp(GHook_recv, @GBak_recv);
      try
        Result := TFnRecv(GHook_recv)(s, buf, len, flags);
      finally
        PatchJmp(GHook_recv, @Hook_recv, @GBak_recv);
      end;
      if (Result > 0) and Assigned(GCallback) then
        GCallback(1 {PKT_DIR_RECV}, @buf, Result);
    finally
      SetInHook(False);
    end;
  end
  else
  begin
    UnpatchJmp(GHook_recv, @GBak_recv);
    try
      Result := TFnRecv(GHook_recv)(s, buf, len, flags);
    finally
      PatchJmp(GHook_recv, @Hook_recv, @GBak_recv);
    end;
  end;
end;

function Hook_WSASend(s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD;
    var lpNumberOfBytesSent: DWORD; dwFlags: DWORD;
    lpOverlapped: LPWSAOVERLAPPED;
    lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
var
  I: Integer;
begin
  if not InHook then
  begin
    SetInHook(True);
    try
      if Assigned(GCallback) then
        for I := 0 to Integer(dwBufferCount) - 1 do
          GCallback(0 {PKT_DIR_SEND}, PByte(lpBuffers[I].buf), lpBuffers[I].len);
    finally
      SetInHook(False);
    end;
  end;
  UnpatchJmp(GHook_WSASend, @GBak_WSASend);
  try
    Result := TFnWSASend(GHook_WSASend)(s, lpBuffers, dwBufferCount,
      lpNumberOfBytesSent, dwFlags, lpOverlapped, lpCompletionRoutine);
  finally
    PatchJmp(GHook_WSASend, @Hook_WSASend, @GBak_WSASend);
  end;
end;

function Hook_WSARecv(s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD;
    var lpNumberOfBytesRecvd: DWORD; var lpFlags: DWORD;
    lpOverlapped: LPWSAOVERLAPPED;
    lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
var
  I: Integer;
begin
  UnpatchJmp(GHook_WSARecv, @GBak_WSARecv);
  try
    Result := TFnWSARecv(GHook_WSARecv)(s, lpBuffers, dwBufferCount,
      lpNumberOfBytesRecvd, lpFlags, lpOverlapped, lpCompletionRoutine);
  finally
    PatchJmp(GHook_WSARecv, @Hook_WSARecv, @GBak_WSARecv);
  end;
  if (Result = 0) and not InHook and Assigned(GCallback) then
  begin
    SetInHook(True);
    try
      for I := 0 to Integer(dwBufferCount) - 1 do
        if lpBuffers[I].len > 0 then
          GCallback(1 {PKT_DIR_RECV}, PByte(lpBuffers[I].buf), lpBuffers[I].len);
    finally
      SetInHook(False);
    end;
  end;
end;

{ ===== Публичные функции ===== }

function HooksInstall(ACallback: TPacketCallback): Boolean;
var
  hWS2: HMODULE;
begin
  Result := False;

  GTlsIndex := TlsAlloc;
  if GTlsIndex = TLS_OUT_OF_INDEXES then
    Exit;

  hWS2 := GetModuleHandle('ws2_32.dll');
  if hWS2 = 0 then
    Exit;

  GCallback := ACallback;

  GHook_send    := GetProcAddress(hWS2, 'send');
  GHook_recv    := GetProcAddress(hWS2, 'recv');
  GHook_WSASend := GetProcAddress(hWS2, 'WSASend');
  GHook_WSARecv := GetProcAddress(hWS2, 'WSARecv');

  if (GHook_send = nil) or (GHook_recv = nil) then
    Exit;

  PatchJmp(GHook_send,    @Hook_send,    @GBak_send);
  PatchJmp(GHook_recv,    @Hook_recv,    @GBak_recv);
  if GHook_WSASend <> nil then
    PatchJmp(GHook_WSASend, @Hook_WSASend, @GBak_WSASend);
  if GHook_WSARecv <> nil then
    PatchJmp(GHook_WSARecv, @Hook_WSARecv, @GBak_WSARecv);

  Result := True;
end;

procedure HooksRemove;
begin
  if GHook_send <> nil then
    UnpatchJmp(GHook_send, @GBak_send);
  if GHook_recv <> nil then
    UnpatchJmp(GHook_recv, @GBak_recv);
  if GHook_WSASend <> nil then
    UnpatchJmp(GHook_WSASend, @GBak_WSASend);
  if GHook_WSARecv <> nil then
    UnpatchJmp(GHook_WSARecv, @GBak_WSARecv);

  GCallback := nil;

  if GTlsIndex <> TLS_OUT_OF_INDEXES then
  begin
    TlsFree(GTlsIndex);
    GTlsIndex := TLS_OUT_OF_INDEXES;
  end;
end;

end.
