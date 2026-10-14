Program DirectoryListingTest;

{ Two threads listing the same directories must not fault. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}CThreads,{$ENDIF}
  Classes, SysUtils, DirectoryListing;

Type
  TScanThread = Class(TThread)
  Public
    Failures: Integer;
    Procedure Execute; Override;
  End;

Procedure Check(Const Name: String; Ok: Boolean);
Begin
  If Not Ok Then
    Raise Exception.Create(Name);
  WriteLn('ok ', Name);
End;

Procedure TScanThread.Execute;
Var
  Scan: TDirectoryScan;
  Round, Code: Integer;
Begin
  Failures := 0;
  For Round := 1 To 40 Do
    Begin
      Code := StartDirectoryScan('/usr/share/hunspell/*.dic', faAnyFile, Scan);
      Try
        While Code = 0 Do
          Begin
            If Scan.Name = '' Then
              Inc(Failures);
            Code := AdvanceDirectoryScan(Scan);
          End;
      Finally
        CloseDirectoryScan(Scan);
      End;
      Code := StartDirectoryScan('/no/such/directory/*', faAnyFile, Scan);
      CloseDirectoryScan(Scan);
      If Code = 0 Then
        Inc(Failures);
    End;
End;

Var
  Left, Right: TScanThread;
  Scan: TDirectoryScan;
  Code, Found: Integer;
  TempDir, DicPath: String;
Begin
  TempDir := IncludeTrailingPathDelimiter(GetTempDir) + 'directory-listing-test';
  ForceDirectories(TempDir);
  DicPath := IncludeTrailingPathDelimiter(TempDir) + 'en_GB.dic';
  If Not FileExists(DicPath) Then
    Begin
      With TStringList.Create Do
        Try
          Add('word');
          SaveToFile(DicPath);
        Finally
          Free;
        End;
    End;
  Code := StartDirectoryScan(IncludeTrailingPathDelimiter(TempDir) + '*.dic', faAnyFile, Scan);
  Found := 0;
  Try
    While Code = 0 Do
      Begin
        If Scan.Name = 'en_GB.dic' Then
          Inc(Found);
        Check('dictionary is not a directory', (Scan.Attr And faDirectory) = 0);
        Code := AdvanceDirectoryScan(Scan);
      End;
  Finally
    CloseDirectoryScan(Scan);
  End;
  Check('masked name found', Found = 1);
  Code := StartDirectoryScan('/no/such/directory/*', faDirectory, Scan);
  CloseDirectoryScan(Scan);
  Check('missing directory is not a hit', Code <> 0);
  Left := TScanThread.Create(True);
  Right := TScanThread.Create(True);
  Left.FreeOnTerminate := False;
  Right.FreeOnTerminate := False;
  Left.Start;
  Right.Start;
  Left.WaitFor;
  Right.WaitFor;
  Check('left scan stayed valid', Left.Failures = 0);
  Check('right scan stayed valid', Right.Failures = 0);
  Left.Free;
  Right.Free;
  DeleteFile(DicPath);
  RemoveDir(TempDir);
End.
