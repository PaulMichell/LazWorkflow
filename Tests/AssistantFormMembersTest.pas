program AssistantFormMembersTest;
{$mode objfpc}{$H+}
uses Classes, SysUtils, CodeToolManager, CodeCache, AssistantFormMembers, AssistantLfm;

const
  FormSource =
    'unit BindingForm;' + LineEnding + '{$mode objfpc}{$H+}' + LineEnding +
    'interface uses Classes, Forms, ExtCtrls;' + LineEnding +
    'type THelper = class(TObject)' + LineEnding +
    '  Clock: TTimer; procedure Tick(Sender: TObject); end;' + LineEnding +
    '  TBindingForm = class(TForm)' + LineEnding +
    '  procedure TimerTickFast(Origin: TObject);' + LineEnding +
    '  private FValue: Integer;' + LineEnding + '  end;' + LineEnding +
    'implementation' + LineEnding + '{$R *.lfm}' + LineEnding +
    'procedure TBindingForm.TimerTickFast(Origin: TObject); begin end;' + LineEnding +
    'procedure THelper.Tick(Sender: TObject); begin end;' + LineEnding + 'end.' + LineEnding;
var
  Code: TCodeBuffer;
  Body, Lfm, Owner, ErrorText, FirstEdit, Directory: String;
  Output: TStringList;
procedure CheckComponentImport(const UnitName, ComponentType, ExpectedImport: String);
var
  Source, Resource, FormClass, Error: String;
  Buffer: TCodeBuffer;
  Lines: TStringList;
begin
  Buffer := CodeToolBoss.CreateFile(Directory + UnitName + '.pas');
  Source := 'unit ' + UnitName + ';' + LineEnding + '{$mode objfpc}{$H+}' + LineEnding +
    'interface' + LineEnding + 'uses Forms;' + LineEnding + 'type' + LineEnding +
    '  TMainForm = class(TForm)' + LineEnding + '  end;' + LineEnding +
    'implementation' + LineEnding + '{$R *.lfm}' + LineEnding + 'end.' + LineEnding;
  Buffer.Source := Source;
  Resource := 'object MainForm: TMainForm' + LineEnding + 'end' + LineEnding;
  if not BindFormMembers(Buffer, Resource, 'Entry', ComponentType, '', Source, FormClass, Error) then
    raise Exception.Create(Error);
  if not EnsureComponentUses(Source, ComponentType, '') or
    (Pos('uses Forms, ' + ExpectedImport + ';', Source) = 0) then
    raise Exception.Create('Wrong import for ' + ComponentType);
  if Pos('Entry: ' + ComponentType + ';', Source) = 0 then
    raise Exception.Create('Missing field for ' + ComponentType);
  if not UpsertLfmComponent(Resource, 'Entry', ComponentType, '') then
    raise Exception.Create('Missing LFM entry for ' + ComponentType);
  Lines := TStringList.Create;
  try
    Lines.Text := Source;
    Lines.SaveToFile(Buffer.Filename);
    Lines.Text := Resource;
    Lines.SaveToFile(ChangeFileExt(Buffer.Filename, '.lfm'));
  finally
    Lines.Free;
  end;
end;

begin
  Directory := IncludeTrailingPathDelimiter(ExpandFileName('Temporary/FormBinding'));
  ForceDirectories(Directory);
  CheckComponentImport('ImageListImportForm', 'TImageList', 'Controls');
  CheckComponentImport('TimerImportForm', 'TTimer', 'ExtCtrls');
  Code := CodeToolBoss.CreateFile(Directory + 'BindingForm.pas');
  Body := FormSource;
  Code.Source := Body;
  Lfm := 'object BindingForm: TBindingForm' + LineEnding + 'end' + LineEnding;
  if not BindFormMembers(Code, Lfm, 'Clock', 'TTimer', 'TimerTick', Body, Owner, ErrorText) then
    raise Exception.Create(ErrorText);
  if Pos('Procedure TBindingForm.TimerTick(Sender: TObject);', Body) = 0 then
    raise Exception.Create('Missing exact TimerTick implementation');
  FirstEdit := Body;
  Code.Source := Body;
  if not BindFormMembers(Code, Lfm, 'Clock', 'TTimer', 'timertick', Body, Owner, ErrorText) then
    raise Exception.Create(ErrorText);
  if Body <> FirstEdit then raise Exception.Create('Repeated edit changed the unit');
  if not UpsertLfmComponent(Lfm, 'Clock', 'TTimer', '    Enabled = False' + LineEnding +
    '    OnTimer = TimerTick' + LineEnding) then raise Exception.Create('Missing LFM edit');
  Body := StringReplace(FirstEdit, 'TimerTick(Sender: TObject)', 'TimerTick(var Sender: TObject)', []);
  Code.Source := Body;
  if BindFormMembers(Code, Lfm, 'Clock', 'TTimer', 'TimerTick', Body, Owner, ErrorText) then
    raise Exception.Create('Accepted incompatible declaration');
  Body := StringReplace(FirstEdit, 'TBindingForm.TimerTick(Sender: TObject)',
    'TBindingForm.TimerTick(Sender: Integer)', []);
  Code.Source := Body;
  if BindFormMembers(Code, Lfm, 'Clock', 'TTimer', 'TimerTick', Body, Owner, ErrorText) then
    raise Exception.Create('Accepted incompatible implementation');
  Body := FirstEdit;
  Output := TStringList.Create;
  try
    Output.Text := Body;
    Output.SaveToFile(Code.Filename);
    Output.Text := Lfm;
    Output.SaveToFile(Directory + 'BindingForm.lfm');
  finally
    Output.Free;
  end;
end.
