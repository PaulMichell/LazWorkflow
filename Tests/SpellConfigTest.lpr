program SpellConfigTest;
{$mode objfpc}{$H+}
uses cthreads, Classes, SysUtils, SpellCheckerConfig, SpellCheckerOptions, SpellEngine;
var C:TSpellCheckerConfig; O:TSpellCheckerOptions; P:TSpellEngine; T:QWord; Blocker:String; F:TFileStream;
procedure Check(const S:string; B:Boolean);
begin if not B then raise Exception.Create(S); WriteLn('ok ',S); end;
begin
 Blocker:=GetTempFileName(GetTempDir, 'spell-config-');
 F:=TFileStream.Create(Blocker,fmCreate); F.Free;
 C:=TSpellCheckerConfig.Create; O:=TSpellCheckerOptions.Create;
 try
  O.EngineKind:=sekHunspell; O.Language:='en_GB'; C.AssignOptions(O);
  T:=GetTickCount64;
  while not C.IsReady and (GetTickCount64-T<10000) do begin CheckSynchronize(10); end;
  Check('asynchronous engine loaded',C.IsReady); P:=C.Engine;
  C.AssignOptions(O); Check('unchanged options retain engine',C.Engine=P);
  Check('cached misspelling false',not C.IsWordCorrect('recieve'));
  Check('cached misspelling repeat false',not C.IsWordCorrect('recieve'));
  C.IgnoreWord('recieve'); Check('ignore invalidates cached result',C.IsWordCorrect('recieve'));
  O.PersonalFileName:=Blocker + '/dictionary'; C.AssignOptions(O);
  Check('save failure reported',not C.AddToPersonal('lookoing'));
  Check('failed save does not accept word',not C.IsWordCorrect('lookoing'));
  O.Language:='en_US'; C.AssignOptions(O);
  O.EngineKind:=sekNone; C.AssignOptions(O);
  for T:=1 to 20 do CheckSynchronize(10);
  Check('disabled engine ignores obsolete load',not C.IsReady);
 finally O.Free; C.Free; DeleteFile(Blocker); end;
end.
