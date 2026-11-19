program MacSpellEngineTest;
{$mode objfpc}{$H+}
{$ifdef Darwin}{$modeswitch objectivec1}{$endif}
uses
  {$ifdef Darwin}CocoaAll, SpellEngineMacOS, SpellEngine,{$endif}
  SysUtils;
{$ifdef Darwin}
var
  Engine: TMacSpellEngine;
  Suggestions: TSpellStringArray;
  Pool: NSAutoreleasePool;
{$endif}
begin
  {$ifdef Darwin}
  Pool := NSAutoreleasePool.alloc.init;
  Engine := TMacSpellEngine.Create('en_US');
  try
    if not Engine.Load then raise Exception.Create(Engine.LastError);
    if not Engine.CheckWord('spelling') then raise Exception.Create('Known word rejected');
    if Engine.CheckWord('spelingg') then raise Exception.Create('Misspelling accepted');
    Suggestions := Engine.GetSuggestions('spelingg', 1);
    if Length(Suggestions) <> 1 then raise Exception.Create('Expected one suggestion');
    WriteLn('Passed native macOS checks for ', Engine.ResolvedLanguage);
  finally
    Engine.Free;
    Pool.drain;
  end;
  {$endif}
end.
