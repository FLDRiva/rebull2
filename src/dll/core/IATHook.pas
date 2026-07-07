unit IATHook;

{
  IAT Hooking — подмена адресов в Import Address Table целевого модуля.

  Зачем вместо inline patching:
    GameGuard периодически проверяет байты в ws2_32.dll на изменения.
    IAT хранится внутри L2.exe и GG её реже сканирует.
    ws2_32.dll при этом остаётся нетронутым.

  Принцип:
    PE-заголовок L2.exe содержит IMAGE_IMPORT_DESCRIPTOR для каждой DLL.
    Для ws2_32 в IAT хранятся адреса функций (указатели).
    Меняем указатель на нашу функцию через VirtualProtect + запись.
    Оригинальный адрес сохраняем — через него вызываем настоящую функцию.
}

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses Windows, SysUtils;

type
  TPacketCallback = procedure(Direction: Byte; Data: PByte; Len: Integer);

{ Установить IAT-хуки в модуле ATargetModule на функции ws2_32.
  ACallback вызывается при каждом перехваченном пакете.
  Возвращает True при успехе хотя бы одного хука. }
function IATHooksInstall(ATargetModule: HMODULE; ACallback: TPacketCallback): Boolean;

{ Снять все IAT-хуки (восстановить оригинальные указатели) }
procedure IATHooksRemove;

implementation

var
  GCallback : TPacketCallback = nil;

  // Сохранённые оригинальные адреса IAT
  GSlot_send    : ^Pointer = nil;
  GSlot_recv    : ^Pointer = nil;
  GSlot_WSASend : ^Pointer = nil;
  GSlot_WSARecv : ^Pointer = nil;

  GOrig_send    : Pointer = nil;
  GOrig_recv    : Pointer = nil;
  GOrig_WSASend : Pointer = nil;
  GOrig_WSARecv : Pointer = nil;

{ ===== PE-парсинг: поиск слота IAT ===== }

// Возвращает указатель на ячейку IAT (не на функцию, а на ячейку с адресом функции)
function FindIATSlot(AModule: HMODULE; const ADllName, AFuncName: string): ^Pointer;
var
  DosHdr    : PImageDosHeader;
  NtHdrs    : PImageNtHeaders;
  ImportDir : PImageImportDescriptor;
  ImpDLL    : PAnsiChar;
  OrigThunk : PImageThunkData;
  IATThunk  : PImageThunkData;
  ByName    : PImageImportByName;
  ModBase   : PByte;
begin
  Result  := nil;
  ModBase := PByte(AModule);

  DosHdr := PImageDosHeader(AModule);
  if DosHdr^.e_magic <> IMAGE_DOS_SIGNATURE then Exit;

  NtHdrs := PImageNtHeaders(ModBase + DosHdr^.e_lfanew);
  if NtHdrs^.Signature <> IMAGE_NT_SIGNATURE then Exit;

  // Директория импортов
  var ImpRVA  := NtHdrs^.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
  var ImpSize := NtHdrs^.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].Size;
  if (ImpRVA = 0) or (ImpSize = 0) then Exit;

  ImportDir := PImageImportDescriptor(ModBase + ImpRVA);

  while ImportDir^.Name <> 0 do
  begin
    ImpDLL := PAnsiChar(ModBase + ImportDir^.Name);

    if AnsiSameText(ImpDLL, ADllName) then
    begin
      OrigThunk := PImageThunkData(ModBase + ImportDir^.OriginalFirstThunk);
      IATThunk  := PImageThunkData(ModBase + ImportDir^.FirstThunk);

      while OrigThunk^.Function_ <> 0 do
      begin
        // Импорт по имени (не по ординалу)
        if (OrigThunk^.Function_ and IMAGE_ORDINAL_FLAG32) = 0 then
        begin
          ByName := PImageImportByName(ModBase + NativeUInt(OrigThunk^.Function_));
          if AnsiSameText(ByName^.Name, AFuncName) then
          begin
            Result := @IATThunk^.Function_;
            Exit;
          end;
        end;
        Inc(OrigThunk);
        Inc(IATThunk);
      end;
    end;

    Inc(ImportDir);
  end;
end;

// Атомарно заменить указатель в IAT
function PatchIATSlot(ASlot: ^Pointer; ANewFunc: Pointer): Pointer;
var
  OldProt  : DWORD;
  OldValue : Pointer;
begin
  OldValue := ASlot^;
  VirtualProtect(ASlot, SizeOf(Pointer), PAGE_EXECUTE_READWRITE, OldProt);
  try
    ASlot^ := ANewFunc;
  finally
    VirtualProtect(ASlot, SizeOf(Pointer), OldProt, OldProt);
  end;
  Result := OldValue;
end;

{ ===== Хук-функции ===== }

// Прототипы оригинальных функций
type
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

function Hook_send(s: TSocket; const buf; len, flags: Integer): Integer; stdcall;
begin
  try
    if Assigned(GCallback) then
      GCallback(0 {PKT_DIR_SEND}, @buf, len);
  except end;
  Result := TFnSend(GOrig_send)(s, buf, len, flags);
end;

function Hook_recv(s: TSocket; var buf; len, flags: Integer): Integer; stdcall;
begin
  Result := TFnRecv(GOrig_recv)(s, buf, len, flags);
  try
    if (Result > 0) and Assigned(GCallback) then
      GCallback(1 {PKT_DIR_RECV}, @buf, Result);
  except end;
end;

function Hook_WSASend(s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD;
    var lpNumberOfBytesSent: DWORD; dwFlags: DWORD;
    lpOverlapped: LPWSAOVERLAPPED;
    lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
var
  I: Integer;
begin
  Result := TFnWSASend(GOrig_WSASend)(s, lpBuffers, dwBufferCount,
    lpNumberOfBytesSent, dwFlags, lpOverlapped, lpCompletionRoutine);
  try
    if Assigned(GCallback) then
      for I := 0 to Integer(dwBufferCount) - 1 do
        if lpBuffers[I].len > 0 then
          GCallback(0 {PKT_DIR_SEND}, PByte(lpBuffers[I].buf), lpBuffers[I].len);
  except end;
end;

function Hook_WSARecv(s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD;
    var lpNumberOfBytesRecvd: DWORD; var lpFlags: DWORD;
    lpOverlapped: LPWSAOVERLAPPED;
    lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
var
  I: Integer;
begin
  Result := TFnWSARecv(GOrig_WSARecv)(s, lpBuffers, dwBufferCount,
    lpNumberOfBytesRecvd, lpFlags, lpOverlapped, lpCompletionRoutine);
  try
    if (Result = 0) and Assigned(GCallback) then
      for I := 0 to Integer(dwBufferCount) - 1 do
        if lpBuffers[I].len > 0 then
          GCallback(1 {PKT_DIR_RECV}, PByte(lpBuffers[I].buf), lpBuffers[I].len);
  except end;
end;

{ ===== Публичные функции ===== }

function IATHooksInstall(ATargetModule: HMODULE; ACallback: TPacketCallback): Boolean;
begin
  Result    := False;
  GCallback := ACallback;

  GSlot_send := FindIATSlot(ATargetModule, 'ws2_32.dll', 'send');
  if Assigned(GSlot_send) then
    GOrig_send := PatchIATSlot(GSlot_send, @Hook_send);

  GSlot_recv := FindIATSlot(ATargetModule, 'ws2_32.dll', 'recv');
  if Assigned(GSlot_recv) then
    GOrig_recv := PatchIATSlot(GSlot_recv, @Hook_recv);

  GSlot_WSASend := FindIATSlot(ATargetModule, 'ws2_32.dll', 'WSASend');
  if Assigned(GSlot_WSASend) then
    GOrig_WSASend := PatchIATSlot(GSlot_WSASend, @Hook_WSASend);

  GSlot_WSARecv := FindIATSlot(ATargetModule, 'ws2_32.dll', 'WSARecv');
  if Assigned(GSlot_WSARecv) then
    GOrig_WSARecv := PatchIATSlot(GSlot_WSARecv, @Hook_WSARecv);

  // Достаточно хотя бы одного успешного хука
  Result := Assigned(GOrig_send) or Assigned(GOrig_recv) or
            Assigned(GOrig_WSASend) or Assigned(GOrig_WSARecv);
end;

procedure IATHooksRemove;
begin
  if Assigned(GSlot_send)    and Assigned(GOrig_send)    then PatchIATSlot(GSlot_send,    GOrig_send);
  if Assigned(GSlot_recv)    and Assigned(GOrig_recv)    then PatchIATSlot(GSlot_recv,    GOrig_recv);
  if Assigned(GSlot_WSASend) and Assigned(GOrig_WSASend) then PatchIATSlot(GSlot_WSASend, GOrig_WSASend);
  if Assigned(GSlot_WSARecv) and Assigned(GOrig_WSARecv) then PatchIATSlot(GSlot_WSARecv, GOrig_WSARecv);

  GCallback     := nil;
  GSlot_send    := nil; GSlot_recv    := nil;
  GSlot_WSASend := nil; GSlot_WSARecv := nil;
  GOrig_send    := nil; GOrig_recv    := nil;
  GOrig_WSASend := nil; GOrig_WSARecv := nil;
end;

end.
