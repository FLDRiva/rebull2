unit Scanner;

{
  Signature Scanner — поиск байтовых паттернов в памяти процесса.

  Поддерживает wildcards (??) и кэширует результаты.
  Пример паттерна: '55 8B EC ?? ?? 8B 45 08 ?? 5D C3'
}

interface

uses
  Windows, SysUtils, Classes, Generics.Collections;

type
  // Байт паттерна: значение + флаг wildcard
  TPatternByte = record
    Value   : Byte;
    IsWild  : Boolean;
  end;

  TPatternBytes = array of TPatternByte;

  { TSignatureScanner }
  TSignatureScanner = class
  private
    FModuleBase : Pointer;
    FModuleSize : NativeUInt;
    FCache      : TDictionary<string, Pointer>;

    function ParsePattern(const APattern: string): TPatternBytes;
    function MatchAt(AAddr: PByte; const APattern: TPatternBytes): Boolean; inline;
  public
    constructor Create(AModule: HMODULE);
    destructor Destroy; override;

    { Найти первое вхождение паттерна, вернуть указатель или nil }
    function Find(const APattern: string): Pointer;

    { Найти все вхождения паттерна }
    function FindAll(const APattern: string): TArray<Pointer>;

    { Разрешить относительный вызов/прыжок: читает 4-байтный offset по AAddr+AOffset
      и возвращает абсолютный адрес назначения (для CALL/JMP E8/E9) }
    function ResolveRelCall(AAddr: Pointer; AOffset: Integer = 1): Pointer;

    { Прочитать DWORD-смещение и вернуть адрес (для MOV/LEA с абсолютным адресом) }
    function ResolveAbsRef(AAddr: Pointer; AOffset: Integer = 2): Pointer;

    procedure ClearCache;
  end;

implementation

{ TSignatureScanner }

constructor TSignatureScanner.Create(AModule: HMODULE);
var
  Info: TMemoryBasicInformation;
begin
  inherited Create;
  FCache := TDictionary<string, Pointer>.Create;

  FModuleBase := Pointer(AModule);

  // Определяем размер модуля через IMAGE_DOS_HEADER → IMAGE_NT_HEADERS
  var DosHdr  := PImageDosHeader(AModule);
  var NtHdrs  := PImageNtHeaders(PByte(AModule) + DosHdr^.e_lfanew);
  FModuleSize := NtHdrs^.OptionalHeader.SizeOfImage;
end;

destructor TSignatureScanner.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TSignatureScanner.ParsePattern(const APattern: string): TPatternBytes;
var
  Parts : TArray<string>;
  I     : Integer;
  PB    : TPatternByte;
begin
  Parts := APattern.Trim.Split([' ']);
  SetLength(Result, Length(Parts));
  for I := 0 to High(Parts) do
  begin
    if (Parts[I] = '??') or (Parts[I] = '?') then
    begin
      PB.IsWild := True;
      PB.Value  := 0;
    end
    else
    begin
      PB.IsWild := False;
      PB.Value  := StrToInt('$' + Parts[I]);
    end;
    Result[I] := PB;
  end;
end;

function TSignatureScanner.MatchAt(AAddr: PByte; const APattern: TPatternBytes): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(APattern) do
  begin
    if not APattern[I].IsWild and (AAddr[I] <> APattern[I].Value) then
      Exit(False);
  end;
  Result := True;
end;

function TSignatureScanner.Find(const APattern: string): Pointer;
var
  Pattern   : TPatternBytes;
  Base      : PByte;
  I         : NativeUInt;
  PatLen    : Integer;
begin
  // Проверяем кэш
  if FCache.TryGetValue(APattern, Result) then
    Exit;

  Result  := nil;
  Pattern := ParsePattern(APattern);
  PatLen  := Length(Pattern);
  Base    := PByte(FModuleBase);

  if PatLen = 0 then
    Exit;

  I := 0;
  while I <= FModuleSize - NativeUInt(PatLen) do
  begin
    if MatchAt(Base + I, Pattern) then
    begin
      Result := Base + I;
      FCache.AddOrSetValue(APattern, Result);
      Exit;
    end;
    Inc(I);
  end;
end;

function TSignatureScanner.FindAll(const APattern: string): TArray<Pointer>;
var
  Pattern   : TPatternBytes;
  Base      : PByte;
  I         : NativeUInt;
  PatLen    : Integer;
  Results   : TList<Pointer>;
begin
  Pattern := ParsePattern(APattern);
  PatLen  := Length(Pattern);
  Base    := PByte(FModuleBase);
  Results := TList<Pointer>.Create;
  try
    I := 0;
    while I <= FModuleSize - NativeUInt(PatLen) do
    begin
      if MatchAt(Base + I, Pattern) then
        Results.Add(Base + I);
      Inc(I);
    end;
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

function TSignatureScanner.ResolveRelCall(AAddr: Pointer; AOffset: Integer): Pointer;
var
  Rel : Integer;
begin
  // CALL rel32: E8 xx xx xx xx → dest = addr + offset + 4 + rel32
  Rel    := PInteger(PByte(AAddr) + AOffset)^;
  Result := PByte(AAddr) + AOffset + 4 + Rel;
end;

function TSignatureScanner.ResolveAbsRef(AAddr: Pointer; AOffset: Integer): Pointer;
begin
  Result := PPointer(PByte(AAddr) + AOffset)^;
end;

procedure TSignatureScanner.ClearCache;
begin
  FCache.Clear;
end;

end.
