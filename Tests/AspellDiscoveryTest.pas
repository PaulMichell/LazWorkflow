program AspellDiscoveryTest;
{$mode objfpc}{$H+}

uses Classes, SysUtils, SpellEngineAspell;

const
  DictionaryCount = 1024;
  Padding = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789--';
  FinalDictionary = 'final-fixture-dictionary';

procedure EmitDictionaries;
var
  Index: Integer;
begin
  if (ParamCount <> 2) or (ParamStr(2) <> 'dicts') then Halt(2);
  for Index := 1 to DictionaryCount do
  begin
    WriteLn(Padding + 'dictionary-', Index);
    WriteLn(StdErr, Padding + 'diagnostic-', Index);
    if Index mod 128 = 0 then
    begin
      Flush(Output);
      Flush(StdErr);
    end;
  end;
  WriteLn(FinalDictionary);
  if GetEnvironmentVariable('ASPELL_FIXTURE_FAIL') = '1' then Halt(7);
end;

var
  Names: TStringList;
  Index: Integer;
begin
  if ParamStr(1) = 'dump' then
  begin
    EmitDictionaries;
    Exit;
  end;
  Names := TStringList.Create;
  try
    ListAspellLanguages(Names);
    if GetEnvironmentVariable('ASPELL_FIXTURE_FAIL') = '1' then
    begin
      if Names.Count <> 0 then raise Exception.Create('Published failed output');
    end
    else
    begin
      if Names.Count <> DictionaryCount + 1 then raise Exception.Create('Wrong dictionary count');
      for Index := 1 to DictionaryCount do
        if Names[Index-1] <> Padding + 'dictionary-' + IntToStr(Index) then
          raise Exception.CreateFmt('Unexpected dictionary at %d', [Index]);
      if Names[DictionaryCount] <> FinalDictionary then raise Exception.Create('Missing final dictionary');
    end;
    WriteLn('PASS: ', Names.Count, ' dictionaries');
  finally
    Names.Free;
  end;
end.
