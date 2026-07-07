unit MainForm;

{
  Главная форма rebull2_ui.exe.

  Тёмная тема реализована через ручное задание цветов VCL.
  Три вкладки: Пакеты / Лог / Настройки.
}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  ComCtrls, StdCtrls, ExtCtrls, Dialogs,
  PipeClient, Protocol;

type
  TFormMain = class(TForm)
    // Верхняя панель статуса
    PanelTop      : TPanel;
    LblStatus     : TLabel;
    LblPktCount   : TLabel;
    BtnStartStop  : TButton;

    // Вкладки
    PageCtrl      : TPageControl;
    TabPackets    : TTabSheet;
    TabLog        : TTabSheet;
    TabSettings   : TTabSheet;

    // Вкладка Пакеты
    LVPackets     : TListView;
    PanelFilter   : TPanel;
    ChkSend       : TCheckBox;
    ChkRecv       : TCheckBox;
    BtnClear      : TButton;

    // Вкладка Лог
    MemoLog       : TMemo;
    BtnClearLog   : TButton;

    // Вкладка Настройки
    LblDLLPath    : TLabel;
    EdDLLPath     : TEdit;
    BtnBrowse     : TButton;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BtnStartStopClick(Sender: TObject);
    procedure BtnClearClick(Sender: TObject);
    procedure BtnClearLogClick(Sender: TObject);
    procedure BtnBrowseClick(Sender: TObject);

  private
    FClient     : TPipeClient;
    FCapturing  : Boolean;
    FSendCount  : Integer;
    FRecvCount  : Integer;

    procedure ApplyDarkTheme;
    procedure CreateControls;
    procedure UpdateStatus;

    procedure OnPacket(Direction: Byte; Timestamp: Int64; Data: TBytes);
    procedure OnLog(const Msg: string);
    procedure OnConnect(Connected: Boolean);
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

// Цвета тёмной темы
const
  CLR_BG      = $001E1E1E;
  CLR_FG      = $00D4D4D4;
  CLR_ACCENT  = $00CC7A00;  // #007ACC в BGR
  CLR_SUCCESS = $00B0C94E;  // #4EC9B0 в BGR
  CLR_WARNING = $00AADCDC;  // #DCDCAA в BGR
  CLR_ERROR   = $004747F4;  // #F44747 в BGR
  CLR_PANEL   = $002D2D2D;
  CLR_ITEM    = $00252526;

procedure TFormMain.FormCreate(Sender: TObject);
begin
  Caption    := 'rebull2 — Lineage 2 Packet Monitor';
  Width      := 1024;
  Height     := 700;
  Position   := poScreenCenter;
  FCapturing := False;
  FSendCount := 0;
  FRecvCount := 0;

  CreateControls;
  ApplyDarkTheme;

  FClient           := TPipeClient.Create;
  FClient.OnPacket  := OnPacket;
  FClient.OnLog     := OnLog;
  FClient.OnConnect := OnConnect;
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FClient);
end;

procedure TFormMain.CreateControls;
begin
  // Верхняя панель
  PanelTop             := TPanel.Create(Self);
  PanelTop.Parent      := Self;
  PanelTop.Align       := alTop;
  PanelTop.Height      := 40;
  PanelTop.BevelOuter  := bvNone;

  LblStatus            := TLabel.Create(Self);
  LblStatus.Parent     := PanelTop;
  LblStatus.Left       := 8;
  LblStatus.Top        := 12;
  LblStatus.Caption    := 'Ожидание DLL...';

  LblPktCount          := TLabel.Create(Self);
  LblPktCount.Parent   := PanelTop;
  LblPktCount.Left     := 200;
  LblPktCount.Top      := 12;
  LblPktCount.Caption  := 'S: 0  R: 0';

  BtnStartStop         := TButton.Create(Self);
  BtnStartStop.Parent  := PanelTop;
  BtnStartStop.Left    := PanelTop.Width - 130;
  BtnStartStop.Top     := 6;
  BtnStartStop.Width   := 120;
  BtnStartStop.Height  := 28;
  BtnStartStop.Caption := 'Старт';
  BtnStartStop.Anchors := [akTop, akRight];
  BtnStartStop.OnClick := BtnStartStopClick;

  // Вкладки
  PageCtrl             := TPageControl.Create(Self);
  PageCtrl.Parent      := Self;
  PageCtrl.Align       := alClient;

  TabPackets           := TTabSheet.Create(PageCtrl);
  TabPackets.PageControl := PageCtrl;
  TabPackets.Caption   := 'Пакеты';

  TabLog               := TTabSheet.Create(PageCtrl);
  TabLog.PageControl   := PageCtrl;
  TabLog.Caption       := 'Лог';

  TabSettings          := TTabSheet.Create(PageCtrl);
  TabSettings.PageControl := PageCtrl;
  TabSettings.Caption  := 'Настройки';

  // --- Вкладка Пакеты ---
  PanelFilter          := TPanel.Create(Self);
  PanelFilter.Parent   := TabPackets;
  PanelFilter.Align    := alTop;
  PanelFilter.Height   := 32;
  PanelFilter.BevelOuter := bvNone;

  ChkSend              := TCheckBox.Create(Self);
  ChkSend.Parent       := PanelFilter;
  ChkSend.Left         := 8;
  ChkSend.Top          := 6;
  ChkSend.Caption      := 'Send (C→S)';
  ChkSend.Checked      := True;

  ChkRecv              := TCheckBox.Create(Self);
  ChkRecv.Parent       := PanelFilter;
  ChkRecv.Left         := 120;
  ChkRecv.Top          := 6;
  ChkRecv.Caption      := 'Recv (S→C)';
  ChkRecv.Checked      := True;

  BtnClear             := TButton.Create(Self);
  BtnClear.Parent      := PanelFilter;
  BtnClear.Left        := 240;
  BtnClear.Top         := 4;
  BtnClear.Width       := 80;
  BtnClear.Height      := 24;
  BtnClear.Caption     := 'Очистить';
  BtnClear.OnClick     := BtnClearClick;

  LVPackets            := TListView.Create(Self);
  LVPackets.Parent     := TabPackets;
  LVPackets.Align      := alClient;
  LVPackets.ViewStyle  := vsReport;
  LVPackets.ReadOnly   := True;
  LVPackets.RowSelect  := True;
  LVPackets.GridLines  := True;
  with LVPackets.Columns.Add do begin Caption := '#';         Width := 60;  end;
  with LVPackets.Columns.Add do begin Caption := 'Напр.';     Width := 60;  end;
  with LVPackets.Columns.Add do begin Caption := 'Время';     Width := 100; end;
  with LVPackets.Columns.Add do begin Caption := 'Размер';    Width := 80;  end;
  with LVPackets.Columns.Add do begin Caption := 'ID пакета'; Width := 100; end;
  with LVPackets.Columns.Add do begin Caption := 'Данные (HEX)'; Width := 400; end;

  // --- Вкладка Лог ---
  BtnClearLog          := TButton.Create(Self);
  BtnClearLog.Parent   := TabLog;
  BtnClearLog.Align    := alTop;
  BtnClearLog.Height   := 28;
  BtnClearLog.Caption  := 'Очистить лог';
  BtnClearLog.OnClick  := BtnClearLogClick;

  MemoLog              := TMemo.Create(Self);
  MemoLog.Parent       := TabLog;
  MemoLog.Align        := alClient;
  MemoLog.ReadOnly     := True;
  MemoLog.ScrollBars   := ssVertical;
  MemoLog.Font.Name    := 'Consolas';
  MemoLog.Font.Size    := 9;

  // --- Вкладка Настройки ---
  LblDLLPath           := TLabel.Create(Self);
  LblDLLPath.Parent    := TabSettings;
  LblDLLPath.Left      := 16;
  LblDLLPath.Top       := 24;
  LblDLLPath.Caption   := 'Путь к rebull2.dll:';

  EdDLLPath            := TEdit.Create(Self);
  EdDLLPath.Parent     := TabSettings;
  EdDLLPath.Left       := 16;
  EdDLLPath.Top        := 44;
  EdDLLPath.Width      := 500;
  EdDLLPath.Text       := ExtractFilePath(ParamStr(0)) + 'rebull2.dll';

  BtnBrowse            := TButton.Create(Self);
  BtnBrowse.Parent     := TabSettings;
  BtnBrowse.Left       := 520;
  BtnBrowse.Top        := 42;
  BtnBrowse.Width      := 80;
  BtnBrowse.Caption    := 'Обзор...';
  BtnBrowse.OnClick    := BtnBrowseClick;
end;

procedure TFormMain.ApplyDarkTheme;

  procedure StyleControl(C: TControl);
  var
    I: Integer;
  begin
    if C is TWinControl then
    begin
      for I := 0 to TWinControl(C).ControlCount - 1 do
        StyleControl(TWinControl(C).Controls[I]);
    end;

    if C is TForm   then (C as TForm).Color   := CLR_BG;
    if C is TPanel  then with C as TPanel  do begin Color := CLR_PANEL; Font.Color := CLR_FG; end;
    if C is TMemo   then with C as TMemo   do begin Color := CLR_ITEM;  Font.Color := CLR_FG; end;
    if C is TEdit   then with C as TEdit   do begin Color := CLR_ITEM;  Font.Color := CLR_FG; end;
    if C is TLabel  then (C as TLabel).Font.Color := CLR_FG;
    if C is TCheckBox then (C as TCheckBox).Font.Color := CLR_FG;
    if C is TListView then with C as TListView do
    begin
      Color    := CLR_ITEM;
      Font.Color := CLR_FG;
    end;
    if C is TPageControl then (C as TPageControl).Font.Color := CLR_FG;
    if C is TTabSheet then (C as TTabSheet).Font.Color := CLR_FG;
  end;

begin
  Color := CLR_BG;
  Font.Color := CLR_FG;
  StyleControl(Self);

  LblStatus.Font.Color  := CLR_WARNING;
  BtnStartStop.Font.Color := CLR_FG;
end;

procedure TFormMain.UpdateStatus;
begin
  LblPktCount.Caption := Format('S: %d  R: %d', [FSendCount, FRecvCount]);
end;

procedure TFormMain.OnPacket(Direction: Byte; Timestamp: Int64; Data: TBytes);
var
  Item    : TListItem;
  HexStr  : string;
  I       : Integer;
  PktID   : string;
  MaxHex  : Integer;
begin
  // Фильтр
  if (Direction = PKT_DIR_SEND) and not ChkSend.Checked then Exit;
  if (Direction = PKT_DIR_RECV) and not ChkRecv.Checked then Exit;

  // ID пакета — первые 2 байта (little-endian)
  if Length(Data) >= 2 then
    PktID := Format('0x%04X', [Data[0] or (Data[1] shl 8)])
  else if Length(Data) = 1 then
    PktID := Format('0x%02X', [Data[0]])
  else
    PktID := '-';

  // HEX первых 16 байт
  MaxHex := Min(16, Length(Data));
  HexStr := '';
  for I := 0 to MaxHex - 1 do
    HexStr := HexStr + Format('%02X ', [Data[I]]);
  if Length(Data) > 16 then
    HexStr := HexStr + '...';

  Item := LVPackets.Items.Add;
  Item.Caption    := IntToStr(LVPackets.Items.Count);
  Item.SubItems.Add(IfThen(Direction = PKT_DIR_SEND, 'SEND', 'RECV'));
  Item.SubItems.Add(FormatDateTime('hh:nn:ss.zzz', Now));
  Item.SubItems.Add(IntToStr(Length(Data)) + ' б');
  Item.SubItems.Add(PktID);
  Item.SubItems.Add(Trim(HexStr));

  // Цвет строки по направлению
  if Direction = PKT_DIR_SEND then
    Item.ImageIndex := 0  // условный цвет через OwnerDraw (TODO)
  else
    Item.ImageIndex := 1;

  if Direction = PKT_DIR_SEND then
    Inc(FSendCount)
  else
    Inc(FRecvCount);

  UpdateStatus;

  // Автопрокрутка (не чаще чем нужно)
  if LVPackets.Items.Count mod 10 = 0 then
    LVPackets.Scroll(0, 10000);
end;

procedure TFormMain.OnLog(const Msg: string);
begin
  MemoLog.Lines.Add(FormatDateTime('[hh:nn:ss] ', Now) + Msg);
end;

procedure TFormMain.OnConnect(Connected: Boolean);
begin
  if Connected then
  begin
    LblStatus.Caption    := 'DLL подключена';
    LblStatus.Font.Color := CLR_SUCCESS;
  end
  else
  begin
    LblStatus.Caption    := 'Ожидание DLL...';
    LblStatus.Font.Color := CLR_WARNING;
    FCapturing           := False;
    BtnStartStop.Caption := 'Старт';
  end;
end;

procedure TFormMain.BtnStartStopClick(Sender: TObject);
begin
  if not FClient.Connected then
  begin
    ShowMessage('DLL не подключена. Запустите инжектор.');
    Exit;
  end;

  if not FCapturing then
  begin
    FClient.SendCommand(CMD_START);
    FCapturing           := True;
    BtnStartStop.Caption := 'Стоп';
    OnLog('Перехват запущен');
  end
  else
  begin
    FClient.SendCommand(CMD_STOP);
    FCapturing           := False;
    BtnStartStop.Caption := 'Старт';
    OnLog('Перехват остановлен');
  end;
end;

procedure TFormMain.BtnClearClick(Sender: TObject);
begin
  LVPackets.Items.Clear;
  FSendCount := 0;
  FRecvCount := 0;
  UpdateStatus;
end;

procedure TFormMain.BtnClearLogClick(Sender: TObject);
begin
  MemoLog.Clear;
end;

procedure TFormMain.BtnBrowseClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter      := 'DLL файлы (*.dll)|*.dll|Все файлы (*.*)|*.*';
    Dlg.FileName    := EdDLLPath.Text;
    if Dlg.Execute then
      EdDLLPath.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

end.
