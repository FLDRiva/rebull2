library version;

{
  version.dll — прокси для DLL Hijacking.

  Кладётся в папку с L2.exe вместо оригинальной version.dll.
  При загрузке L2 Windows находит нашу DLL первой (search order).

  Что делает:
    1. Загружает оригинальный System32\version.dll → передаёт ему все вызовы
    2. Загружает rebull2.dll из той же папки (наш payload)
    3. При выгрузке — выгружает payload

  Экспорты форвардятся вручную через thunk-функции.
  Все 12 функций version.dll покрыты.
}

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

uses Windows, SysUtils;

var
  HOriginal : HMODULE = 0;   // System32\version.dll
  HPayload  : HMODULE = 0;   // rebull2.dll (наш payload)

{ ===== Форвардинг 12 экспортов version.dll ===== }

type
  // Прототипы экспортов version.dll
  TGetFileVersionInfoA     = function(lptstrFilename: PAnsiChar; dwHandle, dwLen: DWORD; lpData: Pointer): BOOL; stdcall;
  TGetFileVersionInfoW     = function(lptstrFilename: PWideChar; dwHandle, dwLen: DWORD; lpData: Pointer): BOOL; stdcall;
  TGetFileVersionInfoSizeA = function(lptstrFilename: PAnsiChar; lpdwHandle: PDWORD): DWORD; stdcall;
  TGetFileVersionInfoSizeW = function(lptstrFilename: PWideChar; lpdwHandle: PDWORD): DWORD; stdcall;
  TVerFindFileA            = function(uFlags: DWORD; szFileName, szWinDir, szAppDir: PAnsiChar; szCurDir: PAnsiChar; puCurDirLen: PUINT; szDestDir: PAnsiChar; puDestDirLen: PUINT): DWORD; stdcall;
  TVerFindFileW            = function(uFlags: DWORD; szFileName, szWinDir, szAppDir: PWideChar; szCurDir: PWideChar; puCurDirLen: PUINT; szDestDir: PWideChar; puDestDirLen: PUINT): DWORD; stdcall;
  TVerInstallFileA         = function(uFlags: DWORD; szSrcFileName, szDestFileName, szSrcDir, szDestDir, szCurDir: PAnsiChar; szTmpFile: PAnsiChar; puTmpFileLen: PUINT): DWORD; stdcall;
  TVerInstallFileW         = function(uFlags: DWORD; szSrcFileName, szDestFileName, szSrcDir, szDestDir, szCurDir: PWideChar; szTmpFile: PWideChar; puTmpFileLen: PUINT): DWORD; stdcall;
  TVerLanguageNameA        = function(wLang: DWORD; szLang: PAnsiChar; cchLang: DWORD): DWORD; stdcall;
  TVerLanguageNameW        = function(wLang: DWORD; szLang: PWideChar; cchLang: DWORD): DWORD; stdcall;
  TVerQueryValueA          = function(pBlock: Pointer; lpSubBlock: PAnsiChar; var lplpBuffer: Pointer; var puLen: UINT): BOOL; stdcall;
  TVerQueryValueW          = function(pBlock: Pointer; lpSubBlock: PWideChar; var lplpBuffer: Pointer; var puLen: UINT): BOOL; stdcall;

var
  // Адреса функций оригинала, заполняются при загрузке
  PGetFileVersionInfoA     : TGetFileVersionInfoA     = nil;
  PGetFileVersionInfoW     : TGetFileVersionInfoW     = nil;
  PGetFileVersionInfoSizeA : TGetFileVersionInfoSizeA = nil;
  PGetFileVersionInfoSizeW : TGetFileVersionInfoSizeW = nil;
  PVerFindFileA            : TVerFindFileA            = nil;
  PVerFindFileW            : TVerFindFileW            = nil;
  PVerInstallFileA         : TVerInstallFileA         = nil;
  PVerInstallFileW         : TVerInstallFileW         = nil;
  PVerLanguageNameA        : TVerLanguageNameA        = nil;
  PVerLanguageNameW        : TVerLanguageNameW        = nil;
  PVerQueryValueA          : TVerQueryValueA          = nil;
  PVerQueryValueW          : TVerQueryValueW          = nil;

{ ===== Thunk-функции экспортов ===== }

function GetFileVersionInfoA(lptstrFilename: PAnsiChar; dwHandle, dwLen: DWORD; lpData: Pointer): BOOL; stdcall;
begin
  Result := PGetFileVersionInfoA(lptstrFilename, dwHandle, dwLen, lpData);
end;

function GetFileVersionInfoW(lptstrFilename: PWideChar; dwHandle, dwLen: DWORD; lpData: Pointer): BOOL; stdcall;
begin
  Result := PGetFileVersionInfoW(lptstrFilename, dwHandle, dwLen, lpData);
end;

function GetFileVersionInfoSizeA(lptstrFilename: PAnsiChar; lpdwHandle: PDWORD): DWORD; stdcall;
begin
  Result := PGetFileVersionInfoSizeA(lptstrFilename, lpdwHandle);
end;

function GetFileVersionInfoSizeW(lptstrFilename: PWideChar; lpdwHandle: PDWORD): DWORD; stdcall;
begin
  Result := PGetFileVersionInfoSizeW(lptstrFilename, lpdwHandle);
end;

function VerFindFileA(uFlags: DWORD; szFileName, szWinDir, szAppDir: PAnsiChar; szCurDir: PAnsiChar; puCurDirLen: PUINT; szDestDir: PAnsiChar; puDestDirLen: PUINT): DWORD; stdcall;
begin
  Result := PVerFindFileA(uFlags, szFileName, szWinDir, szAppDir, szCurDir, puCurDirLen, szDestDir, puDestDirLen);
end;

function VerFindFileW(uFlags: DWORD; szFileName, szWinDir, szAppDir: PWideChar; szCurDir: PWideChar; puCurDirLen: PUINT; szDestDir: PWideChar; puDestDirLen: PUINT): DWORD; stdcall;
begin
  Result := PVerFindFileW(uFlags, szFileName, szWinDir, szAppDir, szCurDir, puCurDirLen, szDestDir, puDestDirLen);
end;

function VerInstallFileA(uFlags: DWORD; szSrcFileName, szDestFileName, szSrcDir, szDestDir, szCurDir: PAnsiChar; szTmpFile: PAnsiChar; puTmpFileLen: PUINT): DWORD; stdcall;
begin
  Result := PVerInstallFileA(uFlags, szSrcFileName, szDestFileName, szSrcDir, szDestDir, szCurDir, szTmpFile, puTmpFileLen);
end;

function VerInstallFileW(uFlags: DWORD; szSrcFileName, szDestFileName, szSrcDir, szDestDir, szCurDir: PWideChar; szTmpFile: PWideChar; puTmpFileLen: PUINT): DWORD; stdcall;
begin
  Result := PVerInstallFileW(uFlags, szSrcFileName, szDestFileName, szSrcDir, szDestDir, szCurDir, szTmpFile, puTmpFileLen);
end;

function VerLanguageNameA(wLang: DWORD; szLang: PAnsiChar; cchLang: DWORD): DWORD; stdcall;
begin
  Result := PVerLanguageNameA(wLang, szLang, cchLang);
end;

function VerLanguageNameW(wLang: DWORD; szLang: PWideChar; cchLang: DWORD): DWORD; stdcall;
begin
  Result := PVerLanguageNameW(wLang, szLang, cchLang);
end;

function VerQueryValueA(pBlock: Pointer; lpSubBlock: PAnsiChar; var lplpBuffer: Pointer; var puLen: UINT): BOOL; stdcall;
begin
  Result := PVerQueryValueA(pBlock, lpSubBlock, lplpBuffer, puLen);
end;

function VerQueryValueW(pBlock: Pointer; lpSubBlock: PWideChar; var lplpBuffer: Pointer; var puLen: UINT): BOOL; stdcall;
begin
  Result := PVerQueryValueW(pBlock, lpSubBlock, lplpBuffer, puLen);
end;

{ ===== DllMain ===== }

procedure LoadOriginal;
var
  SysDir : array[0..MAX_PATH] of Char;
  Path   : string;
begin
  GetSystemDirectory(SysDir, MAX_PATH);
  Path       := SysDir + '\version.dll';
  HOriginal  := LoadLibrary(PChar(Path));
  if HOriginal = 0 then
    Exit; // критично, но не крашим процесс

  PGetFileVersionInfoA     := GetProcAddress(HOriginal, 'GetFileVersionInfoA');
  PGetFileVersionInfoW     := GetProcAddress(HOriginal, 'GetFileVersionInfoW');
  PGetFileVersionInfoSizeA := GetProcAddress(HOriginal, 'GetFileVersionInfoSizeA');
  PGetFileVersionInfoSizeW := GetProcAddress(HOriginal, 'GetFileVersionInfoSizeW');
  PVerFindFileA            := GetProcAddress(HOriginal, 'VerFindFileA');
  PVerFindFileW            := GetProcAddress(HOriginal, 'VerFindFileW');
  PVerInstallFileA         := GetProcAddress(HOriginal, 'VerInstallFileA');
  PVerInstallFileW         := GetProcAddress(HOriginal, 'VerInstallFileW');
  PVerLanguageNameA        := GetProcAddress(HOriginal, 'VerLanguageNameA');
  PVerLanguageNameW        := GetProcAddress(HOriginal, 'VerLanguageNameW');
  PVerQueryValueA          := GetProcAddress(HOriginal, 'VerQueryValueA');
  PVerQueryValueW          := GetProcAddress(HOriginal, 'VerQueryValueW');
end;

procedure LoadPayload;
var
  DllPath : array[0..MAX_PATH] of Char;
  Dir     : string;
begin
  // Ищем rebull2.dll рядом с нашей version.dll (т.е. в папке L2)
  GetModuleFileName(HInstance, DllPath, MAX_PATH);
  Dir      := ExtractFilePath(DllPath);
  HPayload := LoadLibrary(PChar(Dir + 'rebull2.dll'));
  // Намеренно не проверяем ошибку — если payload не нашли, игра продолжает работать
end;

procedure DllMain(Reason: DWORD);
begin
  case Reason of
    DLL_PROCESS_ATTACH:
      begin
        DisableThreadLibraryCalls(HInstance);
        try
          LoadOriginal;
          LoadPayload;
        except
          // Никогда не роняем процесс при загрузке прокси
        end;
      end;

    DLL_PROCESS_DETACH:
      begin
        try
          if HPayload  <> 0 then FreeLibrary(HPayload);
          if HOriginal <> 0 then FreeLibrary(HOriginal);
        except
        end;
      end;
  end;
end;

exports
  GetFileVersionInfoA,
  GetFileVersionInfoW,
  GetFileVersionInfoSizeA,
  GetFileVersionInfoSizeW,
  VerFindFileA,
  VerFindFileW,
  VerInstallFileA,
  VerInstallFileW,
  VerLanguageNameA,
  VerLanguageNameW,
  VerQueryValueA,
  VerQueryValueW;

begin
  DllProc := @DllMain;
  DllMain(DLL_PROCESS_ATTACH);
end.
