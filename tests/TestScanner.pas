program TestScanner;

{
  Unit-тесты для TSignatureScanner.
  Запускается на Linux (нативный FPC) и Windows.
  Тестирует: ParsePattern, Find, FindAll, wildcards, кэш, граничные случаи.
}

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

uses
  SysUtils, StrUtils, Scanner;

var
  GTests  : Integer = 0;
  GFailed : Integer = 0;

procedure Pass(const AName: string);
begin
  Inc(GTests);
  WriteLn('  [OK] ', AName);
end;

procedure Fail(const AName, AReason: string);
begin
  Inc(GTests);
  Inc(GFailed);
  WriteLn('  [FAIL] ', AName, ' — ', AReason);
end;

procedure Check(ACondition: Boolean; const AName: string; const AReason: string = '');
begin
  if ACondition then
    Pass(AName)
  else
    Fail(AName, IfThen(AReason <> '', AReason, 'условие не выполнено'));
end;

{ ===== Тест 1: точное совпадение ===== }
procedure Test_ExactMatch;
var
  Buf     : array[0..15] of Byte;
  Scanner : TSignatureScanner;
  Found   : Pointer;
begin
  WriteLn('Test_ExactMatch:');
  FillChar(Buf, SizeOf(Buf), 0);
  Buf[0]  := $55;
  Buf[1]  := $8B;
  Buf[2]  := $EC;
  Buf[3]  := $90;
  Buf[4]  := $C3;

  Scanner := TSignatureScanner.CreateFromBuffer(@Buf, SizeOf(Buf));
  try
    Found := Scanner.Find('55 8B EC 90 C3');
    Check(Found = @Buf[0], 'find at offset 0');

    Found := Scanner.Find('8B EC');
    Check(Found = @Buf[1], 'find at offset 1');

    Found := Scanner.Find('FF FF');
    Check(Found = nil, 'not found returns nil');
  finally
    Scanner.Free;
  end;
end;

{ ===== Тест 2: wildcards ===== }
procedure Test_Wildcards;
var
  Buf     : array[0..9] of Byte;
  Scanner : TSignatureScanner;
  Found   : Pointer;
begin
  WriteLn('Test_Wildcards:');
  Buf[0] := $55;
  Buf[1] := $8B;
  Buf[2] := $EC;
  Buf[3] := $11; // произвольный
  Buf[4] := $22; // произвольный
  Buf[5] := $8B;
  Buf[6] := $45;
  Buf[7] := $08;
  Buf[8] := $5D;
  Buf[9] := $C3;

  Scanner := TSignatureScanner.CreateFromBuffer(@Buf, SizeOf(Buf));
  try
    Found := Scanner.Find('55 8B EC ?? ?? 8B 45 08');
    Check(Found = @Buf[0], 'wildcard match');

    Found := Scanner.Find('55 8B EC ?? ?? 8B FF 08');
    Check(Found = nil, 'wildcard mismatch after wild bytes');

    Found := Scanner.Find('?? ?? ?? 11 22');
    Check(Found = @Buf[0], 'leading wildcards');
  finally
    Scanner.Free;
  end;
end;

{ ===== Тест 3: FindAll ===== }
procedure Test_FindAll;
var
  Buf     : array[0..19] of Byte;
  Scanner : TSignatureScanner;
  Results : TArray<Pointer>;
begin
  WriteLn('Test_FindAll:');
  FillChar(Buf, SizeOf(Buf), 0);
  // Паттерн AA BB встречается 3 раза
  Buf[2]  := $AA; Buf[3]  := $BB;
  Buf[8]  := $AA; Buf[9]  := $BB;
  Buf[15] := $AA; Buf[16] := $BB;

  Scanner := TSignatureScanner.CreateFromBuffer(@Buf, SizeOf(Buf));
  try
    Results := Scanner.FindAll('AA BB');
    Check(Length(Results) = 3, 'FindAll count = 3', Format('получено %d', [Length(Results)]));
    if Length(Results) >= 1 then Check(Results[0] = @Buf[2],  'FindAll[0] offset=2');
    if Length(Results) >= 2 then Check(Results[1] = @Buf[8],  'FindAll[1] offset=8');
    if Length(Results) >= 3 then Check(Results[2] = @Buf[15], 'FindAll[2] offset=15');

    Results := Scanner.FindAll('FF FF');
    Check(Length(Results) = 0, 'FindAll not found = empty');
  finally
    Scanner.Free;
  end;
end;

{ ===== Тест 4: кэш ===== }
procedure Test_Cache;
var
  Buf     : array[0..7] of Byte;
  Scanner : TSignatureScanner;
  P1, P2  : Pointer;
begin
  WriteLn('Test_Cache:');
  FillChar(Buf, SizeOf(Buf), $AA);
  Buf[2] := $BB;
  Buf[3] := $CC;

  Scanner := TSignatureScanner.CreateFromBuffer(@Buf, SizeOf(Buf));
  try
    P1 := Scanner.Find('BB CC');
    P2 := Scanner.Find('BB CC'); // из кэша
    Check(P1 = P2, 'cached result matches');
    Check(P1 = @Buf[2], 'cached pointer correct');

    Scanner.ClearCache;
    P2 := Scanner.Find('BB CC'); // снова из памяти
    Check(P1 = P2, 'after ClearCache same result');
  finally
    Scanner.Free;
  end;
end;

{ ===== Тест 5: граничные случаи ===== }
procedure Test_EdgeCases;
var
  Buf     : array[0..4] of Byte;
  Scanner : TSignatureScanner;
  Found   : Pointer;
begin
  WriteLn('Test_EdgeCases:');
  Buf[0] := $AA; Buf[1] := $BB; Buf[2] := $CC; Buf[3] := $DD; Buf[4] := $EE;

  Scanner := TSignatureScanner.CreateFromBuffer(@Buf, SizeOf(Buf));
  try
    // Паттерн точно в конце буфера
    Found := Scanner.Find('CC DD EE');
    Check(Found = @Buf[2], 'pattern at end of buffer');

    // Паттерн длиннее буфера — должен вернуть nil без AV
    Found := Scanner.Find('AA BB CC DD EE FF 00');
    Check(Found = nil, 'pattern longer than buffer');

    // Пустой паттерн
    Found := Scanner.Find('');
    Check(Found = nil, 'empty pattern returns nil');

    // Одиночный байт
    Found := Scanner.Find('DD');
    Check(Found = @Buf[3], 'single byte pattern');

    // Wildcard-only паттерн совпадает с первой позицией
    Found := Scanner.Find('?? ??');
    Check(Found = @Buf[0], 'all-wildcard matches at offset 0');
  finally
    Scanner.Free;
  end;
end;

{ ===== Тест 6: паттерн на границе размера ===== }
procedure Test_BoundaryBuf;
var
  Buf     : array[0..0] of Byte;
  Scanner : TSignatureScanner;
  Found   : Pointer;
begin
  WriteLn('Test_BoundaryBuf:');
  Buf[0] := $55;

  Scanner := TSignatureScanner.CreateFromBuffer(@Buf, 1);
  try
    Found := Scanner.Find('55');
    Check(Found = @Buf[0], 'single-byte buffer, found');

    Found := Scanner.Find('55 8B');
    Check(Found = nil, '2-byte pattern in 1-byte buffer');
  finally
    Scanner.Free;
  end;
end;

var
  T1: Double;
begin
  WriteLn('=== rebull2 :: TSignatureScanner Unit Tests ===');
  WriteLn('');

  T1 := Now;

  Test_ExactMatch;
  WriteLn('');
  Test_Wildcards;
  WriteLn('');
  Test_FindAll;
  WriteLn('');
  Test_Cache;
  WriteLn('');
  Test_EdgeCases;
  WriteLn('');
  Test_BoundaryBuf;

  WriteLn('');
  WriteLn(Format('=== Итог: %d/%d пройдено (%.0f мс) ===',
    [GTests - GFailed, GTests, (Now - T1) * 86400 * 1000]));

  if GFailed > 0 then
  begin
    WriteLn(Format('ПРОВАЛЕНО: %d тестов', [GFailed]));
    Halt(1);
  end
  else
    WriteLn('Все тесты пройдены.');
end.
