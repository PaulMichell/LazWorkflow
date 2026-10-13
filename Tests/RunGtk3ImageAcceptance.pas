#!/usr/bin/env instantfpc
Program RunGtk3ImageAcceptance;

{ Compile and run the GTK3 image acceptance program. No model calls. (c) 2026 Michell Computing.

  instantfpc Tests/RunGtk3ImageAcceptance.pas [Lazarus checkout]
  LAZARUS_ROOT is used when the checkout is not passed. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  Classes, SysUtils, Process;

Function RepositoryRoot: String;
Var
  I: Integer;
  Probe, Dir: String;
Begin
  Result := '';
  Probe := ParamStr(0);
  If ExtractFileExt(Probe) = '.pas' Then
    Begin
      Dir := ExpandFileName(ExtractFilePath(Probe) + '..');
      If DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'Source') Then
        Exit(ExcludeTrailingPathDelimiter(Dir));
    End;
  Dir := GetCurrentDir;
  For I := 1 To 8 Do
    Begin
      If FileExists(IncludeTrailingPathDelimiter(Dir) + 'Tests' + PathDelim + 'RunGtk3ImageAcceptance.pas') Then
        Exit(ExcludeTrailingPathDelimiter(Dir));
      Probe := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + '..');
      If Probe = Dir Then
        Break;
      Dir := Probe;
    End;
End;

Procedure CollectUnitDirs(Const Root: String; Dirs: TStrings);
Const
  Excluded: Array[0..5] Of String = ('qt5', 'qt6', 'gtk2', 'nogui', 'win32', 'cocoa');
Var
  RootPrefix: String;

  Function Skipped(Const Relative: String): Boolean;
  Var
    Rest, Part: String;
    I: Integer;
  Begin
    Result := False;
    Rest := Relative;
    While Rest <> '' Do
      Begin
        If Pos(PathDelim, Rest) > 0 Then
          Begin
            Part := Copy(Rest, 1, Pos(PathDelim, Rest) - 1);
            Delete(Rest, 1, Length(Part) + 1);
          End
        Else
          Begin
            Part := Rest;
            Rest := '';
          End;
        For I := 0 To High(Excluded) Do
          If Part = Excluded[I] Then
            Exit(True);
      End;
  End;

  Procedure Walk(Const Directory: String; Depth: Integer);
  Var
    Info: TSearchRec;
    Child: String;
  Begin
    If Depth > 40 Then
      Exit;
    If FindFirst(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Info) <> 0 Then
      Exit;
    Try
      Repeat
        If (Info.Name = '.') Or (Info.Name = '..') Then
          Continue;
        Child := IncludeTrailingPathDelimiter(Directory) + Info.Name;
        If DirectoryExists(Child) Then
          Walk(Child, Depth + 1)
        Else If (LowerCase(ExtractFileExt(Info.Name)) = '.ppu') And
          Not Skipped(Copy(Child, Length(RootPrefix) + 1, MaxInt)) Then
          Dirs.Add(ExcludeTrailingPathDelimiter(ExtractFilePath(Child)));
      Until FindNext(Info) <> 0;
    Finally
      FindClose(Info);
    End;
  End;

Begin
  RootPrefix := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  Walk(Root, 0);
End;

Function HasGtk3(Dirs: TStrings): Boolean;
Var
  I: Integer;
  Part, Rest: String;
Begin
  Result := False;
  For I := 0 To Dirs.Count - 1 Do
    Begin
      Rest := Dirs[I];
      While Rest <> '' Do
        Begin
          If Pos(PathDelim, Rest) > 0 Then
            Begin
              Part := Copy(Rest, 1, Pos(PathDelim, Rest) - 1);
              Delete(Rest, 1, Length(Part) + 1);
            End
          Else
            Begin
              Part := Rest;
              Rest := '';
            End;
          If Part = 'gtk3' Then
            Exit(True);
        End;
    End;
End;

Procedure AddLinkerFlags(Command: TStrings);
Var
  Pkg, Probe, Exe: String;
  Proc: TProcess;
  Mem: TMemoryStream;
  Buf: Array[0..1023] Of Byte;
  Bytes, I: Integer;
  Parts: TStringList;
Begin
  Exe := ExeSearch('pkg-config', GetEnvironmentVariable('PATH'));
  If Exe = '' Then
    Exit;
  For Pkg In ['gtk+-3.0', 'gdk-pixbuf-2.0'] Do
    Begin
      Proc := TProcess.Create(Nil);
      Mem := TMemoryStream.Create;
      Try
        Proc.Executable := Exe;
        Proc.Parameters.Add('--libs');
        Proc.Parameters.Add(Pkg);
        Proc.Options := [poUsePipes, poNoConsole, poStderrToOutPut];
        Try
          Proc.Execute;
          While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
            Begin
              If Proc.Output.NumBytesAvailable > 0 Then
                Begin
                  Bytes := Proc.Output.Read(Buf[0], SizeOf(Buf));
                  If Bytes > 0 Then
                    Mem.WriteBuffer(Buf[0], Bytes);
                End
              Else
                Sleep(5);
            End;
          If Proc.ExitStatus <> 0 Then
            Continue;
          SetLength(Probe, Mem.Size);
          If Mem.Size > 0 Then
            Move(Mem.Memory^, Probe[1], Mem.Size);
        Except
          Continue;
        End;
      Finally
        Mem.Free;
        Proc.Free;
      End;
      Parts := TStringList.Create;
      Try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := Trim(Probe);
        For I := 0 To Parts.Count - 1 Do
          If Copy(Parts[I], 1, 2) = '-L' Then
            Command.Add('-Fl' + Copy(Parts[I], 3, MaxInt))
          Else If Copy(Parts[I], 1, 2) = '-l' Then
            Command.Add('-k-l' + Copy(Parts[I], 3, MaxInt));
      Finally
        Parts.Free;
      End;
    End;
End;

Function CaptureRun(Const Exe: String; Args: TStrings; Const WorkDir: String; Out OutputText: String): Integer;
Var
  Proc: TProcess;
  Mem: TMemoryStream;
  Buf: Array[0..8191] Of Byte;
  Bytes: Integer;
Begin
  Result := -1;
  OutputText := '';
  Proc := TProcess.Create(Nil);
  Mem := TMemoryStream.Create;
  Try
    Proc.Executable := Exe;
    Proc.CurrentDirectory := WorkDir;
    Proc.Options := [poUsePipes, poNoConsole, poStderrToOutPut];
    Proc.Parameters.Assign(Args);
    Proc.Execute;
    While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
      Begin
        If Proc.Output.NumBytesAvailable > 0 Then
          Begin
            Bytes := Proc.Output.Read(Buf[0], SizeOf(Buf));
            If Bytes > 0 Then
              Mem.WriteBuffer(Buf[0], Bytes);
          End
        Else
          Sleep(5);
      End;
    SetLength(OutputText, Mem.Size);
    If Mem.Size > 0 Then
      Move(Mem.Memory^, OutputText[1], Mem.Size);
    Result := Proc.ExitStatus;
  Finally
    Mem.Free;
    Proc.Free;
  End;
End;

Var
  Repo, Lazarus, Output, Fpc, Text, LogPath: String;
  Dirs, Command: TStringList;
  I, Code: Integer;
  Stream: TFileStream;
Begin
  Repo := RepositoryRoot;
  If Repo = '' Then
    Begin
      WriteLn('FAIL repository root not found');
      Halt(1);
    End;
  If ParamCount >= 1 Then
    Lazarus := ExpandFileName(ParamStr(1))
  Else
    Lazarus := GetEnvironmentVariable('LAZARUS_ROOT');
  If Lazarus = '' Then
    Lazarus := '/home/paul/Projects/FreePascal/Lazarus';
  If Not DirectoryExists(Lazarus) Then
    Begin
      WriteLn('FAIL lazarus root not found: ' + Lazarus);
      Halt(1);
    End;
  If (GetEnvironmentVariable('DISPLAY') = '') And (GetEnvironmentVariable('WAYLAND_DISPLAY') = '') Then
    Begin
      WriteLn('FAIL no display for GTK3 acceptance');
      Halt(1);
    End;
  Dirs := TStringList.Create;
  Dirs.Sorted := True;
  Dirs.Duplicates := dupIgnore;
  Command := TStringList.Create;
  Try
    CollectUnitDirs(Lazarus, Dirs);
    If Not HasGtk3(Dirs) Then
      Begin
        WriteLn('FAIL no GTK3 compiled Lazarus units');
        Halt(1);
      End;
    Output := IncludeTrailingPathDelimiter(GetTempDir) + 'gtk3-image-acceptance-' + IntToStr(GetProcessID);
    If Not ForceDirectories(Output) Then
      Begin
        WriteLn('FAIL could not create ' + Output);
        Halt(1);
      End;
    Fpc := ExeSearch('fpc', GetEnvironmentVariable('PATH'));
    If Fpc = '' Then
      Begin
        WriteLn('FAIL fpc was not found on PATH');
        Halt(1);
      End;
    Command.Add('-v0');
    Command.Add('-gl');
    Command.Add('-Cr');
    Command.Add('-Co');
    Command.Add('-Mobjfpc');
    Command.Add('-dLCLgtk3');
    Command.Add('-FU' + Output);
    Command.Add('-FE' + Output);
    Command.Add('-Fu' + IncludeTrailingPathDelimiter(Repo) + 'Source' + PathDelim + 'LazAssistantTools');
    Command.Add('-Fu' + IncludeTrailingPathDelimiter(Repo) + 'Source' + PathDelim + 'LazWorkflowCommon');
    Command.Add('-Fu' + IncludeTrailingPathDelimiter(Repo) + 'Source' + PathDelim + 'LazStyledText');
    Command.Add('-Fu' + IncludeTrailingPathDelimiter(Repo) + 'Source' + PathDelim + 'LazRepositoryTools');
    For I := 0 To Dirs.Count - 1 Do
      Command.Add('-Fu' + Dirs[I]);
    AddLinkerFlags(Command);
    Command.Add(IncludeTrailingPathDelimiter(Repo) + 'Source' + PathDelim + 'Tests' + PathDelim + 'AssistantImageAcceptance.lpr');
    Code := CaptureRun(Fpc, Command, Repo, Text);
    LogPath := IncludeTrailingPathDelimiter(Output) + 'build.log';
    Stream := TFileStream.Create(LogPath, fmCreate);
    Try
      If Text <> '' Then
        Stream.WriteBuffer(Text[1], Length(Text));
    Finally
      Stream.Free;
    End;
    If Code <> 0 Then
      Begin
        WriteLn(Text);
        WriteLn('FAIL build, see ' + LogPath);
        Halt(1);
      End;
    Command.Clear;
    {$IFDEF WINDOWS}
    Code := CaptureRun(IncludeTrailingPathDelimiter(Output) + 'AssistantImageAcceptance.exe', Command, Repo, Text);
    {$ELSE}
    Code := CaptureRun(IncludeTrailingPathDelimiter(Output) + 'AssistantImageAcceptance', Command, Repo, Text);
    {$ENDIF}
    WriteLn(Text);
    WriteLn('Logs: ' + Output);
    Halt(Code);
  Finally
    Command.Free;
    Dirs.Free;
  End;
End.
