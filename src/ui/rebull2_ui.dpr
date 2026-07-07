program rebull2_ui;

{
  rebull2_ui.exe — UI приложение для мониторинга пакетов Lineage 2.

  Подключается к rebull2.dll через Named Pipe.
  Тёмная тема, отображение перехваченных пакетов в реальном времени.
}

uses
  Forms,
  MainForm in 'forms\MainForm.pas' {FormMain},
  PipeClient in 'ipc\PipeClient.pas',
  Protocol in '..\..\include\Protocol.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'rebull2';
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
