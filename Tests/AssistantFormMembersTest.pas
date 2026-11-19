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
    '  private FValue: Integer;' + LineEnding + '  end;' + LineEnding +
    'implementation' + LineEnding + '{$R *.lfm}' + LineEnding +
    'procedure THelper.Tick(Sender: TObject); begin end;' + LineEnding + 'end.' + LineEnding;
var
  Code: TCodeBuffer;
  Body, Lfm, Owner, ErrorText, FirstEdit, Directory: String;
  Output: TStringList;
begin
  Directory := IncludeTrailingPathDelimiter(ExpandFileName('Temporary/FormBinding'));
  ForceDirectories(Directory);
  Code := CodeToolBoss.CreateFile(Directory + 'BindingForm.pas');
  Body := FormSource;
  Code.Source := Body;
  Lfm := 'object BindingForm: TBindingForm' + LineEnding + 'end' + LineEnding;
  if not BindFormMembers(Code, Lfm, 'Clock', 'TTimer', 'Tick', Body, Owner, ErrorText) then
    raise Exception.Create(ErrorText);
  FirstEdit := Body;
  Code.Source := Body;
  if not BindFormMembers(Code, Lfm, 'Clock', 'TTimer', 'Tick', Body, Owner, ErrorText) then
    raise Exception.Create(ErrorText);
  if Body <> FirstEdit then raise Exception.Create('Repeated edit changed the unit');
  if not UpsertLfmComponent(Lfm, 'Clock', 'TTimer', '    Enabled = False' + LineEnding +
    '    OnTimer = Tick' + LineEnding) then raise Exception.Create('Missing LFM edit');
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
