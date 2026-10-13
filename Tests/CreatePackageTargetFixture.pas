#!/usr/bin/env instantfpc
Program CreatePackageTargetFixture;

{ Create a new disposable workspace for Tests/CodexPackageFixture.pas.
  (c) 2026 Michell Computing.

  instantfpc Tests/CreatePackageTargetFixture.pas /tmp/package-target-check
  Refuses to overwrite an existing directory. Does not configure accounts or IDEs.
  The disposable test command is instantfpc with argument RunTests.pas. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  Classes, SysUtils;

Procedure WriteLines(Const Path: String; Lines: Array Of String);
Var
  List: TStringList;
  I: Integer;
Begin
  List := TStringList.Create;
  Try
    For I := 0 To High(Lines) Do
      List.Add(Lines[I]);
    List.SaveToFile(Path);
  Finally
    List.Free;
  End;
End;

Procedure CreateFixture(Const Root: String);
Begin
  If DirectoryExists(Root) Or FileExists(Root) Then
    Begin
      WriteLn(StdErr, 'Refusing to overwrite ' + Root);
      Halt(1);
    End;
  If Not ForceDirectories(Root) Then
    Begin
      WriteLn(StdErr, 'Could not create ' + Root);
      Halt(1);
    End;
  ForceDirectories(IncludeTrailingPathDelimiter(Root) + 'Packages');
  ForceDirectories(IncludeTrailingPathDelimiter(Root) + 'Source');
  ForceDirectories(IncludeTrailingPathDelimiter(Root) + 'App');
  ForceDirectories(IncludeTrailingPathDelimiter(Root) + 'Documents');
  WriteLines(IncludeTrailingPathDelimiter(Root) + 'Packages' + PathDelim + 'PackageTargetCheck.lpk',
    ['<?xml version="1.0"?>',
    '<CONFIG><Package Version="5">',
    '<Name Value="PackageTargetCheck"/><Type Value="RunTimeOnly"/>',
    '<CompilerOptions><Version Value="11"/><SearchPaths>',
    '<OtherUnitFiles Value="../Source"/>',
    '<UnitOutputDirectory Value="../lib/$(TargetCPU)-$(TargetOS)"/>',
    '</SearchPaths></CompilerOptions>',
    '<Files Count="1"><Item1><Filename Value="../Source/PackageUnit.pas"/>',
    '<UnitName Value="PackageUnit"/></Item1></Files>',
    '<UsageOptions><UnitPath Value="$(PkgOutDir)"/></UsageOptions>',
    '</Package></CONFIG>']);
  WriteLines(IncludeTrailingPathDelimiter(Root) + 'Source' + PathDelim + 'PackageUnit.pas',
    ['unit PackageUnit;',
    '{$mode objfpc}',
    'interface',
    'function Answer: Integer;',
    'implementation',
    'function Answer: Integer;',
    'begin',
    '  Result := 42;',
    'end;',
    'end.']);
  WriteLines(IncludeTrailingPathDelimiter(Root) + 'App' + PathDelim + 'Unrelated.lpr',
    ['program Unrelated;',
    'begin',
    '  WriteLn(''unrelated'');',
    'end.']);
  WriteLines(IncludeTrailingPathDelimiter(Root) + 'App' + PathDelim + 'Unrelated.lpi',
    ['<?xml version="1.0"?>',
    '<CONFIG><ProjectOptions><Version Value="12"/><General>',
    '<MainUnit Value="0"/><Title Value="Unrelated"/><UseAppBundle Value="False"/>',
    '</General><Units Count="1"><Unit0><Filename Value="Unrelated.lpr"/>',
    '<IsPartOfProject Value="True"/></Unit0></Units></ProjectOptions>',
    '<CompilerOptions><Version Value="11"/><Target><Filename Value="Unrelated"/>',
    '</Target></CompilerOptions></CONFIG>']);
  WriteLines(IncludeTrailingPathDelimiter(Root) + 'TestAnswer.pas',
    ['program TestAnswer;',
    'uses PackageUnit;',
    'begin if Answer <> 43 then Halt(1); WriteLn(''Answer behaviour passed''); end.']);
  WriteLines(IncludeTrailingPathDelimiter(Root) + 'RunTests.pas',
    ['#!/usr/bin/env instantfpc',
    'Program RunTests;',
    '{$IFDEF FPC} {$MODE OBJFPC} {$LONGSTRINGS ON} {$ENDIF}',
    'Uses Classes, SysUtils, Process;',
    'Function Capture(Const Exe: String; Const Args: Array Of String): String;',
    'Var Proc: TProcess; Mem: TMemoryStream; Buf: Array[0..1023] Of Byte; Bytes, I: Integer;',
    'Begin',
    '  Result := '''';',
    '  Proc := TProcess.Create(Nil); Mem := TMemoryStream.Create;',
    '  Try',
    '    Proc.Executable := Exe; Proc.Options := [poUsePipes, poNoConsole, poStderrToOutPut];',
    '    For I := 0 To High(Args) Do Proc.Parameters.Add(Args[I]);',
    '    Proc.Execute;',
    '    While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do',
    '      If Proc.Output.NumBytesAvailable > 0 Then',
    '        Begin Bytes := Proc.Output.Read(Buf[0], SizeOf(Buf)); If Bytes > 0 Then Mem.WriteBuffer(Buf[0], Bytes); End',
    '      Else Sleep(5);',
    '    If Proc.ExitStatus <> 0 Then Halt(Proc.ExitStatus);',
    '    SetLength(Result, Mem.Size); If Mem.Size > 0 Then Move(Mem.Memory^, Result[1], Mem.Size);',
    '    Result := Trim(Result);',
    '  Finally Mem.Free; Proc.Free; End;',
    'End;',
    'Var Root, Fpc, Cpu, OsName, Lib, Binary: String; Code: Integer; Proc: TProcess;',
    'Begin',
    '  Root := GetCurrentDir;',
    '  If Not FileExists(IncludeTrailingPathDelimiter(Root) + ''TestAnswer.pas'') Then',
    '    Begin WriteLn(''RunTests must start in the disposable fixture directory.''); Halt(1); End;',
    '  Fpc := ExeSearch(''fpc'', GetEnvironmentVariable(''PATH''));',
    '  If Fpc = '''' Then Begin WriteLn(''fpc was not found on PATH''); Halt(1); End;',
    '  Cpu := Capture(Fpc, [''-iTP'']); OsName := Capture(Fpc, [''-iTO'']);',
    '  Lib := IncludeTrailingPathDelimiter(Root) + ''lib'' + PathDelim + Cpu + ''-'' + OsName;',
    '  ForceDirectories(Lib);',
    '  Proc := TProcess.Create(Nil);',
    '  Try',
    '    Proc.Executable := Fpc; Proc.Options := [poWaitOnExit];',
    '    Proc.Parameters.Add(''-Fu'' + Lib); Proc.Parameters.Add(''-FE'' + IncludeTrailingPathDelimiter(Root) + ''lib'');',
    '    Proc.Parameters.Add(''-FU'' + IncludeTrailingPathDelimiter(Root) + ''lib'');',
    '    Proc.Parameters.Add(IncludeTrailingPathDelimiter(Root) + ''TestAnswer.pas'');',
    '    Proc.Execute; Code := Proc.ExitStatus;',
    '  Finally Proc.Free; End;',
    '  If Code <> 0 Then Halt(Code);',
    '  Binary := IncludeTrailingPathDelimiter(Root) + ''lib'' + PathDelim + ''TestAnswer'';',
    '  {$IFDEF WINDOWS} Binary := Binary + ''.exe''; {$ENDIF}',
    '  Proc := TProcess.Create(Nil);',
    '  Try Proc.Executable := Binary; Proc.Options := [poWaitOnExit]; Proc.Execute; Halt(Proc.ExitStatus);',
    '  Finally Proc.Free; End;',
    'End.']);
  WriteLn(ExpandFileName(Root));
End;

Begin
  If ParamCount <> 1 Then
    Begin
      WriteLn(StdErr, 'Usage: instantfpc Tests/CreatePackageTargetFixture.pas <new-directory>');
      Halt(2);
    End;
  CreateFixture(ExpandFileName(ParamStr(1)));
End.
