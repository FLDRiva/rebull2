unit Scanner;

{
  Signature Scanner — поиск байтовых паттернов в памяти процесса.

  Поддерживает wildcards (??) и кэширует результаты.
  Пример паттерна: '55 8B EC ?? ?? 8B 45 08 ?? 5D C3'

  Совместим с Delphi 10.x+ и FPC 3.2+ (через {$MODE DELPHI}).
}

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

{$IFDEF WINDOWS}
uses Windows, SysUtils, Generics.Collections;
{$ELSE}
uses SysUtils, Generics.Collections;
{$ENDIF}

type
  TPatternByte = record
    Value  : Byte;
    IsWild : Boolean;
  end;

  TPatternBytes = array of TPatternByte;

  { TSignatureScanner }
  TSignatureScanner = class
  private
    FBase  : PByte;
    FSize  : NativeUInt;
    FCache : TDictionary<string, Pointer>;

    function ParsePattern(const APattern: string): TPatternBytes;
    function MatchAt(AAddr: PByte; const APattern: TPatternBytes): Boolean; inline;
  public
{$IFDEF WINDOWS}
    { Создать по HMODULE — читает IMAGE_NT_HEADERS для размера }
    constructor CreateFromModule(AModule: HMODULE);
{$ENDIF}
    { Создать по произвольному буферу (тесты и произвольные регионы памяти) }
    constructor CreateFromBuffer(ABase: Pointer; ASize: NativeUInt);
    destructor Destroy; override;

    { Найти первое вхождение, вернуть указатель или nil }
    function Find(const APattern: string): Pointer;

    { Найти все вхождения }
    function FindAll(const APattern: string): TArray<Pointer>;

{$IFDEF WINDOWS}
    { Разрешить CALL/JMP rel32 (E8/E9 xx xx xx xx) }
    function ResolveRelCall(AAddr: Pointer; AOffset: Integer = 1): Pointer;
    { Прочитать DWORD-ссылку (MOV/LEA с абсолютным адресом) }
    function ResolveAbsRef(AAddr: Pointer; AOffset: Integer = 2): Pointer;
{$ENDIF}

    procedure ClearCache;

    property Base: PByte     read FBase;
    property Size: NativeUInt read FSize;
  end;

implementation

{$IFDEF WINDOWS}
constructor TSignatureScanner.CreateFromModule(AModule: HMODULE);
var
  DosHdr : PImageDosHeader;
  NtHdrs : PImageNtHeaders;
begin
  inherited Create;
  FCache  := TDictionary<string, Pointer>.Create;
  FBase   := PByte(AModule);
  DosHdr  := PImageDosHeader(AModule);
  NtHdrs  := PImageNtHeaders(FBase + DosHdr^.e_lfanew);
  FSize   := NtHdrs^.OptionalHeader.SizeOfImage;
end;
{$ENDIF}

constructor TSignatureScanner.CreateFromBuffer(ABase: Pointer; ASize: NativeUInt);
begin
  inherited Create;
  FCache := TDictionary<string, Pointer>.Create;
  FBase  := PByte(ABase);
  FSize  := ASize;
end;

destructor TSignatureScanner.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TSignatureScanner.ParsePattern(const APattern: string): TPatternBytes;
var
  Parts   : TArray<string>;
  I, Cnt  : Integer;
  PB      : TPatternByte;
  Trimmed : string;
begin
  Trimmed := APattern.Trim;
  if Trimmed = '' then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  Parts := Trimmed.Split([' ']);
  Cnt   := 0;
  SetLength(Result, Length(Parts));

  for I := 0 to High(Parts) do
  begin
    if Parts[I] = '' then Continue; // пропускаем пустые токены (двойные пробелы)

    if (Parts[I] = '??') or (Parts[I] = '?') then
    begin
      PB.IsWild := True;
      PB.Value  := 0;
    end
    else
    begin
      PB.IsWild := False;
      PB.Value  := Byte(StrToInt('$' + Parts[I]));
    end;
    Result[Cnt] := PB;
    Inc(Cnt);
  end;

  SetLength(Result, Cnt);
end;

function TSignatureScanner.MatchAt(AAddr: PByte; const APattern: TPatternBytes): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(APattern) do
    if not APattern[I].IsWild and (AAddr[I] <> APattern[I].Value) then
      Exit(False);
  Result := True;
end;

function TSignatureScanner.Find(const APattern: string): Pointer;
var
  Pattern : TPatternBytes;
  I       : NativeUInt;
  PatLen  : NativeUInt;
begin
  if FCache.TryGetValue(APattern, Result) then
    Exit;

  Result  := nil;
  Pattern := ParsePattern(APattern);
  PatLen  := NativeUInt(Length(Pattern));

  if (PatLen = 0) or (PatLen > FSize) then
    Exit;

  I := 0;
  while I <= FSize - PatLen do
  begin
    if MatchAt(FBase + I, Pattern) then
    begin
      Result := FBase + I;
      FCache.AddOrSetValue(APattern, Result);
      Exit;
    end;
    Inc(I);
  end;
end;

function TSignatureScanner.FindAll(const APattern: string): TArray<Pointer>;
var
  Pattern : TPatternBytes;
  I       : NativeUInt;
  PatLen  : NativeUInt;
  Results : TList<Pointer>;
begin
  Pattern := ParsePattern(APattern);
  PatLen  := NativeUInt(Length(Pattern));
  Results := TList<Pointer>.Create;
  try
    if (PatLen > 0) and (PatLen <= FSize) then
    begin
      I := 0;
      while I <= FSize - PatLen do
      begin
        if MatchAt(FBase + I, Pattern) then
          Results.Add(FBase + I);
        Inc(I);
      end;
    end;
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

{$IFDEF WINDOWS}
function TSignatureScanner.ResolveRelCall(AAddr: Pointer; AOffset: Integer): Pointer;
var
  Rel: Integer;
begin
  Rel    := PInteger(PByte(AAddr) + AOffset)^;
  Result := PByte(AAddr) + AOffset + 4 + Rel;
end;

function TSignatureScanner.ResolveAbsRef(AAddr: Pointer; AOffset: Integer): Pointer;
begin
  Result := PPointer(PByte(AAddr) + AOffset)^;
end;
{$ENDIF}

procedure TSignatureScanner.ClearCache;
begin
  FCache.Clear;
end;

end.
