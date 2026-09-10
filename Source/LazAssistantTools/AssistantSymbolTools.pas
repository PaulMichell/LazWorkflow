Unit AssistantSymbolTools;
{ Serialized, read-only queries against the IDE's existing CodeTools cache. }
{$mode objfpc}{$H+}
Interface
Uses Classes;
Type TAssistantSymbolQuery = (sqDeclaration, sqContext, sqReferences, sqLocalRename);
Function QueryAssistantSymbol(Const Path, SourceText: String; Line, Column: Integer;
  Kind: TAssistantSymbolQuery; SearchPaths: TStrings; MaxResults: Integer;
  Out ResultText, ErrorText: String; Const RenameTo: String = ''): Boolean;
Implementation
Uses SysUtils, LazUTF8, LazFileUtils, LazIDEIntf, SrcEditorIntf, CodeToolManager,
  CodeCache, CTUnitGraph, fpjson, AssistantTools, AssistantRenamePreview
  {$IFDEF UNIX}, BaseUnix{$ENDIF};
Const MaxFileBytes = 1048576; MaxSearchBytes = 8388608;
Var AssistantCodeToolsBusy: Boolean = False;
Type
  TSearchInput = Record
    Path, Text, DiskText: String;
    Code: TCodeBuffer;
    HadDisk: Boolean;
  End;
Function PascalPath(Const Path: String): Boolean;
Var Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.p') Or
    (Ext = '.lpr') Or (Ext = '.dpr') Or (Ext = '.inc');
End;
Function ReadDisk(Const Path: String; Out Text, ErrorText: String): Boolean;
Var Stream: TFileStream;
  {$IFDEF UNIX}Info: Stat;{$ENDIF}
Begin
  Result := False; Text := '';
  {$IFDEF UNIX}
  If (fpStat(Path, Info) <> 0) Or Not FPS_ISREG(Info.st_mode) Or (Info.st_size > MaxFileBytes) Then
    Begin ErrorText := 'Search requires regular project text files of at most 1 MiB.'; Exit; End;
  {$ENDIF}
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
  Try
    If Stream.Size > MaxFileBytes Then
      Begin ErrorText := 'Search file exceeds the 1 MiB limit.'; Exit; End;
    SetLength(Text, Stream.Size);
    If Text <> '' Then Stream.ReadBuffer(Text[1], Length(Text));
  Finally Stream.Free; End;
  If Pos(#0, Text) > 0 Then Begin ErrorText := 'Binary search files are not supported.'; Exit; End;
  Result := True;
End;
Function Location(Code: TCodeBuffer; X, Y, MaxChars: Integer): TJSONObject;
Var Resolved, Note, Text: String; InProject: Boolean;
Begin
  InProject := ResolveProjectPath(Code.Filename, Resolved, Note); Text := '';
  If InProject And (Y > 0) And (Y <= Code.LineCount) Then Text := UTF8Copy(Code.GetLine(Y - 1, False), 1, MaxChars);
  Result := TJSONObject.Create;
  Result.Add('path', Code.Filename); Result.Add('line', Y); Result.Add('column', X);
  Result.Add('columnEncoding', 'utf8-bytes'); Result.Add('inProject', InProject); Result.Add('lineText', Text);
End;
Function Context(Code: TCodeBuffer; Line, Radius: Integer): TJSONObject;
Var I, First, Last: Integer; Text, LineText: String; Truncated: Boolean;
Begin
  First := Line - Radius; If First < 1 Then First := 1;
  Last := Line + Radius; If Last > Code.LineCount Then Last := Code.LineCount;
  Text := ''; Truncated := False;
  For I := First To Last Do
    Begin
      LineText := Code.GetLine(I - 1, False);
      If UTF8Length(LineText) > 256 Then Truncated := True;
      If I > First Then Text := Text + LineEnding;
      Text := Text + UTF8Copy(LineText, 1, 256);
    End;
  Result := TJSONObject.Create;
  Result.Add('path', Code.Filename); Result.Add('startLine', First); Result.Add('endLine', Last);
  Result.Add('text', Text); Result.Add('linesTruncated', Truncated);
End;
Function QueryAssistantSymbol(Const Path, SourceText: String; Line, Column: Integer;
  Kind: TAssistantSymbolQuery; SearchPaths: TStrings; MaxResults: Integer;
  Out ResultText, ErrorText: String; Const RenameTo: String): Boolean;
Var Editor: TSourceEditorInterface; Code, Target: TCodeBuffer;
  X, Y, TopLine, BlockTop, BlockBottom, I, J, Bytes, OutputBytes: Integer;
  TargetPath, Note, LineText, Resolved, CurrentText, StopReason, Key: String;
  InProject, Truncated, Failed: Boolean; Deadline: QWord;
  Root, Entry: TJSONObject; Requested, Searched, Failures, Refs: TJSONArray;
  Paths, Seen: TStringList; Inputs: Array Of TSearchInput;
  RefList: TFPList; Cache: TFindIdentifierReferenceCache; Ref: PCodeXYPosition;
Begin
  Result := False; ResultText := ''; ErrorText := '';
  If Not Assigned(LazarusIDE) Or Not Assigned(CodeToolBoss) Or
    Not Assigned(SourceEditorManagerIntf) Or AssistantCodeToolsBusy Then
    Begin ErrorText := 'Lazarus CodeTools is unavailable or busy.'; Exit; End;
  If Not PascalPath(Path) Then Begin ErrorText := 'Symbol lookup requires a Pascal source buffer.'; Exit; End;
  If Length(SourceText) > MaxFileBytes Then Begin ErrorText := 'Source exceeds the 1 MiB lookup limit.'; Exit; End;
  AssistantCodeToolsBusy := True; Root := Nil; Paths := Nil; Seen := Nil; RefList := Nil; Cache := Nil;
  Try
    Paths := TStringList.Create; Paths.CaseSensitive := True;
    If Kind = sqReferences Then
      Begin
        If Not Assigned(SearchPaths) Or (SearchPaths.Count < 1) Or (SearchPaths.Count > 32) Or
          (MaxResults < 1) Or (MaxResults > 200) Then
          Begin ErrorText := 'Search needs 1-32 paths and a result limit from 1 to 200.'; Exit; End;
        For I := 0 To SearchPaths.Count - 1 Do
          Begin
            If (Trim(SearchPaths[I]) = '') Or (Pos(#0, SearchPaths[I]) > 0) Then
              Begin ErrorText := 'Each search path must be a nonempty project path without NUL bytes.'; Exit; End;
            If Not ResolveProjectPath(SearchPaths[I], Resolved, ErrorText) Then Exit;
            If Not PascalPath(Resolved) Then Begin ErrorText := 'Reference search requires Pascal source files.'; Exit; End;
            If Paths.IndexOf(Resolved) < 0 Then Paths.Add(Resolved);
          End;
      End;
    { Uses the IDE's project configuration and all unsaved editor buffers. }
    If Not LazarusIDE.BeginCodeTools Then
      Begin ErrorText := 'The IDE could not prepare CodeTools; finish the current IDE operation and retry.'; Exit; End;
    { A preceding create-file tool or external editor can add files after the
      IDE cached this directory. Refresh disk metadata without reverting buffers. }
    CodeToolBoss.DirectoryCachePool.IncreaseFileTimeStamp;
    Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Path);
    If Not Assigned(Editor) Or Not (Editor.CodeToolsBuffer Is TCodeBuffer) Then
      Begin ErrorText := 'The editor has no CodeTools source buffer.'; Exit; End;
    Code := TCodeBuffer(Editor.CodeToolsBuffer);
    If (Code.Source <> SourceText) Or (Editor.SourceText <> SourceText) Then
      Begin ErrorText := 'Source changed or CodeTools cache is not synchronized; read the buffer again.'; Exit; End;
    If (Line < 1) Or (Line > Code.LineCount) Then Begin ErrorText := 'Line is outside the current source buffer.'; Exit; End;
    LineText := Code.GetLine(Line - 1, False);
    If (Column < 1) Or (Column > Length(LineText)) Or ((Byte(LineText[Column]) And $C0) = $80) Then
      Begin ErrorText := 'Column is outside the line or inside a UTF-8 character.'; Exit; End;
    Target := Nil; X := Column; Y := Line;
    If (Kind = sqLocalRename) And IsVariableDeclaration(Code, X, Y) Then Target := Code;
    If Not Assigned(Target) And Not CodeToolBoss.FindDeclaration(Code, Column, Line, Target, X, Y, TopLine, BlockTop, BlockBottom) Then
      Begin
        ErrorText := 'CodeTools could not resolve this declaration.';
        If CodeToolBoss.ErrorMessage <> '' Then ErrorText := ErrorText + ' ' + UTF8Copy(CodeToolBoss.ErrorMessage, 1, 2000);
        Exit;
      End;
    If Not Assigned(Target) Or (Target.Filename = '') Or (X < 1) Or (Y < 1) Or (Y > Target.LineCount) Then
      Begin ErrorText := 'CodeTools returned no declaration location.'; Exit; End;
    InProject := ResolveProjectPath(Target.Filename, TargetPath, Note);
    If Kind = sqLocalRename Then
      Begin If Not PrepareLocalRename(Code, Target, X, Y, RenameTo, Root, ErrorText) Then Exit; End
    Else If Kind = sqDeclaration Then Root := Location(Target, X, Y, 2000)
    Else
      Begin
        Root := TJSONObject.Create; Root.Add('declaration', Location(Target, X, Y, 2000));
        If Kind = sqContext Then
          Begin
            Root.Add('sourceContext', Context(Code, Line, 3));
            If InProject Then
              Begin
                Root.Add('declarationContext', Context(Target, Y, 5));
                Root.Add('hint', UTF8Copy(CodeToolBoss.FindSmartHint(Code, Column, Line), 1, 2000));
              End
            Else Begin Root.Add('declarationContext', TJSONNull.Create); Root.Add('hint', ''); End;
          End
        Else
          Begin
            SetLength(Inputs, Paths.Count); Bytes := 0;
            { Validate and snapshot every requested input before searching. }
            For I := 0 To Paths.Count - 1 Do
              Begin
                Inputs[I].Path := Paths[I];
                Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Paths[I]);
                If Assigned(Editor) Then
                  Begin
                    If Not (Editor.CodeToolsBuffer Is TCodeBuffer) Then
                      Begin ErrorText := 'A search editor has no CodeTools buffer.'; Exit; End;
                    Inputs[I].Code := TCodeBuffer(Editor.CodeToolsBuffer);
                    If Inputs[I].Code.Source <> Editor.SourceText Then
                      Begin ErrorText := 'Search editor cache is stale; retry after reading its buffer.'; Exit; End;
                  End
                Else
                  Begin
                    If Not ReadDisk(Paths[I], Inputs[I].DiskText, ErrorText) Then
                      Begin ErrorText := Paths[I] + ': ' + ErrorText; Exit; End;
                    Inputs[I].HadDisk := True;
                    Inputs[I].Code := CodeToolBoss.LoadFile(Paths[I], True, False);
                  End;
                If Not Assigned(Inputs[I].Code) Then Begin ErrorText := 'CodeTools could not load a search file.'; Exit; End;
                Inputs[I].Text := Inputs[I].Code.Source;
                Inc(Bytes, Length(Inputs[I].Text) + Length(Inputs[I].DiskText));
                If (Length(Inputs[I].Text) > MaxFileBytes) Or (Bytes > MaxSearchBytes) Then
                  Begin ErrorText := 'Reference search snapshot exceeds its size limit; use fewer files.'; Exit; End;
              End;
            Requested := TJSONArray.Create; Root.Add('requestedFiles', Requested);
            Searched := TJSONArray.Create; Root.Add('searchedFiles', Searched);
            Failures := TJSONArray.Create; Root.Add('failedFiles', Failures);
            Refs := TJSONArray.Create; Root.Add('items', Refs);
            For I := 0 To Paths.Count - 1 Do Requested.Add(Paths[I]);
            Seen := TStringList.Create; Seen.CaseSensitive := True; Seen.Sorted := True;
            Truncated := False; StopReason := ''; OutputBytes := 0; Deadline := GetTickCount64 + 5000;
            For I := 0 To High(Inputs) Do
              Begin
                If GetTickCount64 >= Deadline Then Begin Truncated := True; StopReason := 'time budget'; Break; End;
                CodeToolBoss.FreeListOfPCodeXYPosition(RefList);
                Failed := Not CodeToolBoss.FindReferences(Target, X, Y, Inputs[I].Code, True, RefList, Cache, []);
                If Failed Or (CodeToolBoss.ErrorMessage <> '') Then
                  Begin
                    Entry := TJSONObject.Create; Entry.Add('path', Paths[I]);
                    Entry.Add('error', 'CodeTools could not search this file. ' + UTF8Copy(CodeToolBoss.ErrorMessage, 1, 1000));
                    Failures.Add(Entry); Continue;
                  End;
                Searched.Add(Paths[I]);
                If Assigned(RefList) Then For J := 0 To RefList.Count - 1 Do
                  Begin
                    Ref := PCodeXYPosition(RefList[J]);
                    If Not Assigned(Ref^.Code) Then Continue;
                    If (Ref^.Code = Target) And (Ref^.X = X) And (Ref^.Y = Y) Then Continue;
                    If Not ResolveProjectPath(Ref^.Code.Filename, Resolved, Note) Then Continue;
                    Key := Resolved + ':' + IntToStr(Ref^.Y) + ':' + IntToStr(Ref^.X);
                    If Seen.IndexOf(Key) >= 0 Then Continue;
                    If Refs.Count >= MaxResults Then Begin Truncated := True; StopReason := 'result limit'; Break; End;
                    Entry := Location(Ref^.Code, Ref^.X, Ref^.Y, 200);
                    Inc(OutputBytes, Length(Entry.AsJSON));
                    If OutputBytes > 60000 Then
                      Begin Entry.Free; Truncated := True; StopReason := 'output size limit'; Break; End;
                    Seen.Add(Key); Refs.Add(Entry);
                  End;
                If Truncated Then Break;
              End;
            { Reject stale search evidence, including changed closed-file bytes. }
            For I := 0 To High(Inputs) Do
              Begin
                If Not ResolveProjectPath(Inputs[I].Path, Resolved, ErrorText) Or
                  (Inputs[I].Code.Source <> Inputs[I].Text) Then
                  Begin ErrorText := 'Search inputs changed during lookup; retry.'; Exit; End;
                Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Inputs[I].Path);
                If Assigned(Editor) And (Editor.SourceText <> Inputs[I].Text) Then
                  Begin ErrorText := 'Search editor changed during lookup; retry.'; Exit; End;
                If Inputs[I].HadDisk Then
                  If Not ReadDisk(Inputs[I].Path, CurrentText, ErrorText) Or (CurrentText <> Inputs[I].DiskText) Then
                    Begin ErrorText := 'Search file changed during lookup; retry.'; Exit; End;
              End;
            Root.Add('scope', 'requested project files and their project includes; excludes resolved declaration, comments and form resources');
            Root.Add('truncated', Truncated); Root.Add('stopReason', StopReason);
            Root.Add('completeForRequestedFiles', Not Truncated And (Failures.Count = 0) And (Searched.Count = Requested.Count));
          End;
      End;
    ResultText := Root.AsJSON; Result := True;
  Finally
    Root.Free; Paths.Free; Seen.Free;
    CodeToolBoss.FreeListOfPCodeXYPosition(RefList); Cache.Free;
    AssistantCodeToolsBusy := False;
  End;
End;
End.
