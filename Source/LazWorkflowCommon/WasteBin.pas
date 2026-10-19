Unit WasteBin;

{ Move a path to the waste bin. The LCL has no trash API.

  OpenDocument and OpenURL open a file or URL. They do not move it.
  Windows uses SHFileOperationW. Other hosts try gio, trash-put, then trash.
  Darwin also tries osascript Finder. A failed trash is not a permanent delete.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

/// Darwin Finder waste-bin arguments. The path is passed after --, never inside -e.
Procedure AppendFinderWasteBinArguments(Parameters: TStrings; Const FullPath: String);
Function MovePathToWasteBin(Const FullPath: String; Out ErrorText: String): Boolean;

Implementation

{$IFDEF WINDOWS}
Uses
  ShellApi;
{$ELSE}
Uses
  Process, FileUtil;
{$ENDIF}

Procedure AppendFinderWasteBinArguments(Parameters: TStrings; Const FullPath: String);
Begin
  If Parameters = Nil Then
    Exit;
  Parameters.Add('-e');
  Parameters.Add('on run argv');
  Parameters.Add('-e');
  Parameters.Add('tell application "Finder" to delete (POSIX file (item 1 of argv))');
  Parameters.Add('-e');
  Parameters.Add('end run');
  Parameters.Add('--');
  Parameters.Add(FullPath);
End;

Function MovePathToWasteBin(Const FullPath: String; Out ErrorText: String): Boolean;
{$IFDEF WINDOWS}
Var
  Op: TSHFileOpStructW;
  FromBuf: UnicodeString;
{$ELSE}
Var
  Proc: TProcess;
  Cmd: String;
{$ENDIF}
Begin
  Result := False;
  ErrorText := '';
  If FullPath = '' Then
    Begin
      ErrorText := 'Empty path';
      Exit;
    End;
  If (Not FileExists(FullPath)) And (Not DirectoryExists(FullPath)) Then
    Begin
      ErrorText := 'Path does not exist: ' + FullPath;
      Exit;
    End;
  {$IFDEF WINDOWS}
  FromBuf := UTF8Decode(FullPath) + #0#0;
  FillChar(Op, SizeOf(Op), 0);
  Op.Wnd := 0;
  Op.wFunc := FO_DELETE;
  Op.pFrom := PWideChar(FromBuf);
  Op.fFlags := FOF_ALLOWUNDO Or FOF_NOCONFIRMATION Or FOF_SILENT Or FOF_NOERRORUI;
  If SHFileOperationW(@Op) = 0 Then
    Result := Not (FileExists(FullPath) Or DirectoryExists(FullPath))
  Else
    ErrorText := 'Windows could not move the item to the Recycle Bin';
  {$ELSE}
  Proc := TProcess.Create(Nil);
  Try
    Proc.Options := [poWaitOnExit, poNoConsole];
    Cmd := FindDefaultExecutablePath('gio');
    If Cmd <> '' Then
      Begin
        Proc.Executable := Cmd;
        Proc.Parameters.Add('trash');
        Proc.Parameters.Add(FullPath);
        Try
          Proc.Execute;
          Result := Proc.ExitStatus = 0;
        Except
          Result := False;
        End;
      End;
    If Not Result Then
      Begin
        Proc.Parameters.Clear;
        Cmd := FindDefaultExecutablePath('trash-put');
        If Cmd = '' Then
          Cmd := FindDefaultExecutablePath('trash');
        If Cmd <> '' Then
          Begin
            Proc.Executable := Cmd;
            Proc.Parameters.Add(FullPath);
            Try
              Proc.Execute;
              Result := Proc.ExitStatus = 0;
            Except
              Result := False;
            End;
          End;
      End;
    If Not Result Then
      Begin
        {$IFDEF DARWIN}
        Proc.Parameters.Clear;
        Cmd := '/usr/bin/osascript';
        If Not FileExists(Cmd) Then
          Cmd := FindDefaultExecutablePath('osascript');
        If Cmd <> '' Then
          Begin
            Proc.Executable := Cmd;
            AppendFinderWasteBinArguments(Proc.Parameters, FullPath);
            Try
              Proc.Execute;
              Result := Proc.ExitStatus = 0;
            Except
              Result := False;
            End;
          End;
        {$ENDIF}
      End;
    If Not Result Then
      ErrorText := 'Could not move to the waste bin: ' + FullPath;
  Finally
    Proc.Free;
  End;
  {$ENDIF}
End;

End.
