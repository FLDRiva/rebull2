program rebull2_injector;

{
  rebull2_injector.exe — инжектор DLL в процесс Lineage 2.

  Алгоритм:
    1. Найти PID процесса l2.exe (или lineage2.exe)
    2. OpenProcess с PROCESS_ALL_ACCESS
    3. VirtualAllocEx — выделить память под путь к DLL
    4. WriteProcessMemory — записать путь
    5. CreateRemoteThread(LoadLibraryA) — загрузить DLL в процесс
    6. WaitForSingleObject + GetExitCodeThread — проверить успех
    7. VirtualFreeEx — освободить память

  Использование:
    rebull2_injector.exe [путь_к_dll]
    Если путь не указан — ищет rebull2.dll рядом с инжектором.
}

{$APPTYPE CONSOLE}

uses
  Windows, SysUtils, TlHelp32;

// Найти PID процесса по имени (без учёта регистра)
function FindProcessPID(const AName: string): DWORD;
var
  Snap    : THandle;
  Entry   : TProcessEntry32;
begin
  Result := 0;
  Snap   := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then
    Exit;

  try
    Entry.dwSize := SizeOf(Entry);
    if not Process32First(Snap, Entry) then
      Exit;

    repeat
      if AnsiSameText(Entry.szExeFile, AName) then
      begin
        Result := Entry.th32ProcessID;
        Exit;
      end;
    until not Process32Next(Snap, Entry);
  finally
    CloseHandle(Snap);
  end;
end;

// Инжектировать DLL в процесс с заданным PID
function InjectDLL(APID: DWORD; const ADLLPath: string): Boolean;
var
  hProcess   : THandle;
  RemoteMem  : Pointer;
  PathBytes  : AnsiString;
  PathLen    : SIZE_T;
  Written    : SIZE_T;
  hThread    : THandle;
  ThreadID   : DWORD;
  ExitCode   : DWORD;
  LoadLibAddr: Pointer;
begin
  Result := False;

  PathBytes := AnsiString(ADLLPath);
  PathLen   := Length(PathBytes) + 1; // +1 для нуль-терминатора

  hProcess := OpenProcess(PROCESS_ALL_ACCESS, False, APID);
  if hProcess = 0 then
  begin
    Writeln('Ошибка OpenProcess: ', GetLastError);
    Exit;
  end;

  try
    // Выделяем память под путь к DLL
    RemoteMem := VirtualAllocEx(hProcess, nil, PathLen, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
    if RemoteMem = nil then
    begin
      Writeln('Ошибка VirtualAllocEx: ', GetLastError);
      Exit;
    end;

    try
      // Записываем путь в память процесса
      if not WriteProcessMemory(hProcess, RemoteMem, @PathBytes[1], PathLen, Written) then
      begin
        Writeln('Ошибка WriteProcessMemory: ', GetLastError);
        Exit;
      end;

      // Адрес LoadLibraryA (одинаков для всех процессов в пределах одной ОС)
      LoadLibAddr := GetProcAddress(GetModuleHandle('kernel32.dll'), 'LoadLibraryA');
      if LoadLibAddr = nil then
      begin
        Writeln('LoadLibraryA не найден');
        Exit;
      end;

      // Запускаем LoadLibraryA в удалённом потоке
      hThread := CreateRemoteThread(hProcess, nil, 0,
        LPTHREAD_START_ROUTINE(LoadLibAddr), RemoteMem, 0, ThreadID);

      if hThread = 0 then
      begin
        Writeln('Ошибка CreateRemoteThread: ', GetLastError);
        Exit;
      end;

      try
        // Ждём завершения загрузки (не более 10 секунд)
        if WaitForSingleObject(hThread, 10000) = WAIT_TIMEOUT then
        begin
          Writeln('Таймаут ожидания загрузки DLL');
          Exit;
        end;

        GetExitCodeThread(hThread, ExitCode);
        // ExitCode = базовый адрес загруженного модуля (0 = ошибка)
        if ExitCode = 0 then
        begin
          Writeln('LoadLibrary вернул 0 — DLL не загружена (проверьте путь и зависимости)');
          Exit;
        end;

        Writeln(Format('DLL загружена по адресу $%08X', [ExitCode]));
        Result := True;
      finally
        CloseHandle(hThread);
      end;

    finally
      VirtualFreeEx(hProcess, RemoteMem, 0, MEM_RELEASE);
    end;

  finally
    CloseHandle(hProcess);
  end;
end;

var
  PID     : DWORD;
  DLLPath : string;
  ProcNames: array[0..2] of string = ('l2.exe', 'lineage2.exe', 'LineageII.exe');
  Found   : Boolean;
  I       : Integer;
begin
  Writeln('rebull2 injector v0.1');
  Writeln('');

  // Определяем путь к DLL
  if ParamCount >= 1 then
    DLLPath := ParamStr(1)
  else
    DLLPath := ExtractFilePath(ParamStr(0)) + 'rebull2.dll';

  if not FileExists(DLLPath) then
  begin
    Writeln('DLL не найдена: ', DLLPath);
    Halt(1);
  end;

  Writeln('DLL: ', DLLPath);

  // Ищем процесс клиента
  PID   := 0;
  Found := False;
  for I := 0 to High(ProcNames) do
  begin
    PID := FindProcessPID(ProcNames[I]);
    if PID <> 0 then
    begin
      Writeln('Найден процесс: ', ProcNames[I], ' (PID: ', PID, ')');
      Found := True;
      Break;
    end;
  end;

  if not Found then
  begin
    Writeln('Процесс Lineage 2 не найден. Запустите клиент и попробуйте снова.');
    Halt(1);
  end;

  if InjectDLL(PID, DLLPath) then
  begin
    Writeln('Инжекция выполнена успешно.');
    Halt(0);
  end
  else
  begin
    Writeln('Инжекция не удалась.');
    Halt(2);
  end;
end.
