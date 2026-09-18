Program PascalStyle;

{ Command-line Michell Computing Pascal formatter (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  CWString,
  {$ENDIF}
  Classes, SysUtils, PascalStyleFormat;

Var
  CheckTokens, DryRun, ToStdout, Recursive: Boolean;
  FailCount, WriteCount, Index: Integer;
  Paths: TStringList;

Procedure WriteUsage;
Begin
  WriteLn('Usage: PascalStyle [options] FILE...');
  WriteLn('Format Free Pascal units to Michell Computing house style.');
  WriteLn;
  WriteLn('  -c, --check       Compare token fingerprints after formatting');
  WriteLn('  -n, --dry-run     Do not rewrite files');
  WriteLn('  -s, --stdout      Print formatted source (single file)');
  WriteLn('  -r, --recursive   Format .pas .pp .lpr under directories');
  WriteLn('  -h, --help        Show this help');
End;

Function LoadText(Const FileName: String): String;
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(FileName, fmOpenRead Or fmShareDenyWrite);
  Try
    SetLength(Result, Stream.Size);
    If Stream.Size > 0 Then
      Stream.ReadBuffer(Result[1], Stream.Size);
  Finally
    Stream.Free;
  End;
End;

Procedure SaveText(Const FileName, Text: String);
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(FileName, fmCreate);
  Try
    If Length(Text) > 0 Then
      Stream.WriteBuffer(Text[1], Length(Text));
  Finally
    Stream.Free;
  End;
End;

Function IsPascalName(Const FileName: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.lpr') Or (Ext = '.dpr');
End;

Procedure AddTree(Const Directory: String; Files: TStrings);
Var
  Search: TSearchRec;
  Child: String;
Begin
  If FindFirst(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Search) = 0 Then
    Try
      Repeat
        If (Search.Name = '.') Or (Search.Name = '..') Then
          Continue;
        Child := IncludeTrailingPathDelimiter(Directory) + Search.Name;
        If (Search.Attr And faDirectory) <> 0 Then
          Begin
            If SameText(Search.Name, 'Backup') Then
              Continue;
            AddTree(Child, Files);
          End
        Else If IsPascalName(Search.Name) Then
          Files.Add(Child);
      Until FindNext(Search) <> 0;
    Finally
      FindClose(Search);
    End;
End;

Procedure CollectPath(Const Path: String; Files: TStrings);
Begin
  If DirectoryExists(Path) Then
    Begin
      If Not Recursive Then
        Raise Exception.Create('Directory requires --recursive: ' + Path);
      AddTree(Path, Files);
    End
  Else If FileExists(Path) Then
    Files.Add(Path)
  Else
    Raise Exception.Create('File not found: ' + Path);
End;

Function ProcessFile(Const FileName: String): Boolean;
Var
  Original, Formatted: String;
  Left, Right: TStringList;
  Index: Integer;
Begin
  Result := True;
  Original := LoadText(FileName);
  Formatted := FormatPascalSource(Original);
  If CheckTokens Then
    Begin
      Left := TStringList.Create;
      Right := TStringList.Create;
      Try
        CollectTokenFingerprint(Original, Left);
        CollectTokenFingerprint(Formatted, Right);
        If Left.Count <> Right.Count Then
          Begin
            WriteLn('TOKEN MISMATCH ', FileName, ' (', Left.Count, ' vs ', Right.Count, ')');
            Result := False;
          End
        Else
          For Index := 0 To Left.Count - 1 Do
            If Left[Index] <> Right[Index] Then
              Begin
                WriteLn('TOKEN MISMATCH ', FileName);
                WriteLn('  first diff at ', Index, ': ', Left[Index], ' vs ', Right[Index]);
                Result := False;
                Break;
              End;
        If Result Then
          WriteLn('ok ', FileName);
      Finally
        Left.Free;
        Right.Free;
      End;
    End;
  If ToStdout Then
    Write(Formatted)
  Else If Not DryRun Then
    Begin
      If Formatted <> Original Then
        Begin
          SaveText(FileName, Formatted);
          Inc(WriteCount);
          If Not CheckTokens Then
            WriteLn('formatted ', FileName);
        End
      Else If Not CheckTokens Then
        WriteLn('unchanged ', FileName);
    End
  Else If Not CheckTokens Then
    Begin
      If Formatted <> Original Then
        WriteLn('would format ', FileName)
      Else
        WriteLn('unchanged ', FileName);
    End;
End;

Begin
  CheckTokens := False;
  DryRun := False;
  ToStdout := False;
  Recursive := False;
  FailCount := 0;
  WriteCount := 0;
  Paths := TStringList.Create;
  Try
    If ParamCount < 1 Then
      Begin
        WriteUsage;
        Halt(2);
      End;
    For Index := 1 To ParamCount Do
      Begin
        If (ParamStr(Index) = '-h') Or (ParamStr(Index) = '--help') Then
          Begin
            WriteUsage;
            Halt(0);
          End;
        If (ParamStr(Index) = '-c') Or (ParamStr(Index) = '--check') Then
          CheckTokens := True
        Else If (ParamStr(Index) = '-n') Or (ParamStr(Index) = '--dry-run') Then
          DryRun := True
        Else If (ParamStr(Index) = '-s') Or (ParamStr(Index) = '--stdout') Then
          ToStdout := True
        Else If (ParamStr(Index) = '-r') Or (ParamStr(Index) = '--recursive') Then
          Recursive := True
        Else If Copy(ParamStr(Index), 1, 1) = '-' Then
          Begin
            WriteLn('Unknown option: ', ParamStr(Index));
            WriteUsage;
            Halt(2);
          End
        Else
          CollectPath(ParamStr(Index), Paths);
      End;
    If Paths.Count = 0 Then
      Begin
        WriteLn('No input files.');
        Halt(2);
      End;
    If ToStdout And (Paths.Count <> 1) Then
      Begin
        WriteLn('--stdout requires exactly one file.');
        Halt(2);
      End;
    For Index := 0 To Paths.Count - 1 Do
      If Not ProcessFile(Paths[Index]) Then
        Inc(FailCount);
    If FailCount > 0 Then
      Halt(1);
  Finally
    Paths.Free;
  End;
End.
