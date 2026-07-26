Unit AssistantTools;

{ Built-in IDE tools for LazAssistantTools (read/list/open Markdown) (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantHistory;

Const
  AssistantToolMaxReadChars = 48000;
  AssistantToolMaxListEntries = 400;

Function BuildAssistantToolsJson: String;
Function BuildAssistantToolsJsonForMode(Mode: TAssistantMode): String;
Function ToolAllowedInMode(Const ToolName: String; Mode: TAssistantMode): Boolean;
Function ExecuteAssistantTool(Const ToolName, ArgumentsJson: String; Out ResultText: String;
  Out ErrorText: String): Boolean;
Function ExecuteAssistantToolForMode(Const ToolName, ArgumentsJson: String; Mode: TAssistantMode;
  Out ResultText: String; Out ErrorText: String): Boolean;
Function ProjectRootPath: String;
Function ResolveProjectPath(Const RelativeOrAbsolute: String; Out Resolved: String;
  Out ErrorText: String): Boolean;

Implementation

Uses
  LazFileUtils, FileUtil, LazIDEIntf, ProjectIntf, WorkflowLog, AssistantMarkdownForm,
  fpjson, jsonparser;

Function JsonEscapeLocal(Const S: String): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := '';
  For I := 1 To Length(S) Do
    Begin
      C := S[I];
      Case C Of
        '"': Result := Result + '\"';
        '\': Result := Result + '\\';
        #8: Result := Result + '\b';
        #9: Result := Result + '\t';
        #10: Result := Result + '\n';
        #12: Result := Result + '\f';
        #13: Result := Result + '\r';
      Else
        If Ord(C) < 32 Then
          Result := Result + '\u' + IntToHex(Ord(C), 4)
        Else
          Result := Result + C;
      End;
    End;
End;

Function ToolAllowedInMode(Const ToolName: String; Mode: TAssistantMode): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(ToolName));
  { Chat / Plan / Code all share read tools today. Write tools will be Plan/Code only. }
  Result := (Name = 'read_file') Or (Name = 'list_directory') Or
    (Name = 'open_markdown') Or (Name = 'get_project_info');
  If Not Result Then
    Exit;
  Case Mode Of
    amChat, amPlan, amCode: Result := True;
  Else
    Result := False;
  End;
End;

Function BuildAssistantToolsJsonForMode(Mode: TAssistantMode): String;
Begin
  { Same read-only set for all modes until Plan/Code write tools land. }
  If Mode In [amChat, amPlan, amCode] Then
    Result := BuildAssistantToolsJson
  Else
    Result := '[]';
End;

Function BuildAssistantToolsJson: String;
Begin
  { OpenAI-compatible tools array for chat/completions. }
  Result :=
    '[' +
    '{"type":"function","function":{' +
      '"name":"read_file",' +
      '"description":"Read a text file under the active Lazarus project. Use start_line/end_line to page large files; do not re-read from line 1 after a truncation notice.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative or absolute file path"},' +
        '"start_line":{"type":"integer","description":"1-based first line to include (default 1)"},' +
        '"end_line":{"type":"integer","description":"1-based last line to include (default end of file or max_chars)"},' +
        '"max_chars":{"type":"integer","description":"Optional max characters to return from the selected range"}' +
      '},"required":["path"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"list_directory",' +
      '"description":"List files and subdirectories under a project folder.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative directory (empty = project root)"}' +
      '},"required":[]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"open_markdown",' +
      '"description":"Open a Markdown document in an Assistant Markdown viewer window.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Path to a .md file under the project"}' +
      '},"required":["path"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"get_project_info",' +
      '"description":"Return the active project path, main file, and project info file.",' +
      '"parameters":{"type":"object","properties":{},"required":[]}' +
    '}}' +
    ']';
End;

Function ProjectRootPath: String;
Var
  Proj: TLazProject;
Begin
  Result := '';
  If Not Assigned(LazarusIDE) Then
    Exit;
  Proj := LazarusIDE.ActiveProject;
  If Not Assigned(Proj) Then
    Exit;
  If Assigned(Proj.MainFile) And (Proj.MainFile.Filename <> '') Then
    Result := ExtractFilePath(ExpandFileName(Proj.MainFile.Filename));
  If Result = '' Then
    Result := ExtractFilePath(ExpandFileName(Proj.ProjectInfoFile));
  Result := IncludeTrailingPathDelimiter(Result);
End;

Function IsPathUnderRoot(Const Root, Candidate: String): Boolean;
Var
  R, C: String;
Begin
  R := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  C := ExpandFileName(Candidate);
  {$IFDEF WINDOWS}
  Result := SameText(Copy(C, 1, Length(R)), R) Or SameText(ExcludeTrailingPathDelimiter(C), ExcludeTrailingPathDelimiter(R));
  {$ELSE}
  Result := (Copy(C, 1, Length(R)) = R) Or (ExcludeTrailingPathDelimiter(C) = ExcludeTrailingPathDelimiter(R));
  {$ENDIF}
End;

Function ResolveProjectPath(Const RelativeOrAbsolute: String; Out Resolved: String;
  Out ErrorText: String): Boolean;
Var
  Root, Cand: String;
Begin
  Result := False;
  Resolved := '';
  ErrorText := '';
  Root := ProjectRootPath;
  If Root = '' Then
    Begin
      ErrorText := 'No active Lazarus project is open.';
      Exit;
    End;
  Cand := Trim(RelativeOrAbsolute);
  If Cand = '' Then
    Cand := Root
  Else If FilenameIsAbsolute(Cand) Then
    Cand := ExpandFileName(Cand)
  Else
    Cand := ExpandFileName(Root + Cand);
  If Not IsPathUnderRoot(Root, Cand) Then
    Begin
      ErrorText := 'Path is outside the active project root: ' + Cand;
      Exit;
    End;
  Resolved := Cand;
  Result := True;
End;

Function JsonArgString(Const ArgumentsJson, FieldName: String): String;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Node: TJSONData;
Begin
  Result := '';
  If Trim(ArgumentsJson) = '' Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ArgumentsJson);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      Node := Obj.Find(FieldName);
      If Assigned(Node) And (Node.JSONType <> jtNull) Then
        Result := Node.AsString;
    Except
      Result := '';
    End;
  Finally
    Data.Free;
  End;
End;

Function JsonArgInt(Const ArgumentsJson, FieldName: String; DefaultValue: Integer): Integer;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Node: TJSONData;
Begin
  Result := DefaultValue;
  If Trim(ArgumentsJson) = '' Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ArgumentsJson);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      Node := Obj.Find(FieldName);
      If Assigned(Node) And (Node.JSONType In [jtNumber, jtString]) Then
        Result := Node.AsInteger;
    Except
      Result := DefaultValue;
    End;
  Finally
    Data.Free;
  End;
End;

Function ToolReadFile(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved, Chunk, LineText: String;
  MaxChars, StartLine, EndLine, LastLine, I, FirstOut, LastOut: Integer;
  SL: TStringList;
  Truncated: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  If Path = '' Then
    Begin
      ErrorText := 'read_file requires path.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'File not found: ' + Resolved;
      Exit;
    End;
  MaxChars := JsonArgInt(ArgumentsJson, 'max_chars', AssistantToolMaxReadChars);
  If MaxChars < 1 Then
    MaxChars := AssistantToolMaxReadChars;
  If MaxChars > AssistantToolMaxReadChars Then
    MaxChars := AssistantToolMaxReadChars;
  StartLine := JsonArgInt(ArgumentsJson, 'start_line', 1);
  EndLine := JsonArgInt(ArgumentsJson, 'end_line', 0);
  If StartLine < 1 Then
    StartLine := 1;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(Resolved);
      LastLine := SL.Count;
      If LastLine < 1 Then
        Begin
          ResultText := Format('File: %s (empty, 0 lines)', [Resolved]);
          Result := True;
          Exit;
        End;
      If StartLine > LastLine Then
        Begin
          ErrorText := Format('start_line %d is past end of file (%d lines): %s',
            [StartLine, LastLine, Resolved]);
          Exit;
        End;
      If EndLine < 1 Then
        EndLine := LastLine
      Else If EndLine > LastLine Then
        EndLine := LastLine;
      If EndLine < StartLine Then
        Begin
          ErrorText := Format('end_line %d is before start_line %d.', [EndLine, StartLine]);
          Exit;
        End;
      Chunk := '';
      Truncated := False;
      FirstOut := StartLine;
      LastOut := StartLine - 1;
      For I := StartLine To EndLine Do
        Begin
          LineText := SL[I - 1];
          { +1 for the line ending we will append. }
          If (Length(Chunk) > 0) And (Length(Chunk) + Length(LineText) + 1 > MaxChars) Then
            Begin
              Truncated := True;
              Break;
            End;
          If Length(Chunk) > 0 Then
            Chunk := Chunk + LineEnding;
          Chunk := Chunk + LineText;
          LastOut := I;
          If Length(Chunk) >= MaxChars Then
            Begin
              Truncated := True;
              Break;
            End;
        End;
      ResultText :=
        Format('File: %s (%d lines total); lines %d–%d of requested %d–%d',
          [Resolved, LastLine, FirstOut, LastOut, StartLine, EndLine]) + LineEnding +
        Chunk;
      If Truncated Or (LastOut < EndLine) Then
        ResultText := ResultText + LineEnding + Format(
          '[… truncated. Continue with start_line=%d (same path). Do not re-read from line 1. …]',
          [LastOut + 1]);
      Result := True;
    Except
      On E: Exception Do
        ErrorText := E.Message;
    End;
  Finally
    SL.Free;
  End;
End;

Function ToolListDirectory(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved: String;
  Info: TSearchRec;
  Lines: TStringList;
  Counted: Integer;
  Entry: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  If Not DirectoryExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'Directory not found: ' + Resolved;
      Exit;
    End;
  Lines := TStringList.Create;
  Try
    Lines.Add('Directory: ' + Resolved);
    Counted := 0;
    If FindFirstUTF8(IncludeTrailingPathDelimiter(Resolved) + '*', faAnyFile, Info) = 0 Then
      Try
        Repeat
          If (Info.Name = '.') Or (Info.Name = '..') Then
            Continue;
          If (Info.Attr And faDirectory) <> 0 Then
            Entry := '[dir]  ' + Info.Name
          Else
            Entry := '[file] ' + Info.Name + Format(' (%d bytes)', [Info.Size]);
          Lines.Add(Entry);
          Inc(Counted);
          If Counted >= AssistantToolMaxListEntries Then
            Begin
              Lines.Add(Format('[… listing capped at %d entries …]', [AssistantToolMaxListEntries]));
              Break;
            End;
        Until FindNextUTF8(Info) <> 0;
      Finally
        FindCloseUTF8(Info);
      End;
    ResultText := Lines.Text;
    Result := True;
  Finally
    Lines.Free;
  End;
End;

Function ToolOpenMarkdown(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  If Path = '' Then
    Begin
      ErrorText := 'open_markdown requires path.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'Markdown file not found: ' + Resolved;
      Exit;
    End;
  If OpenMarkdownDocument(Resolved) = Nil Then
    Begin
      ErrorText := 'Failed to open Markdown window for ' + Resolved;
      Exit;
    End;
  ResultText := 'Opened Markdown viewer for ' + Resolved;
  Result := True;
End;

Function ToolGetProjectInfo(Out ResultText, ErrorText: String): Boolean;
Var
  Proj: TLazProject;
  Root: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Not Assigned(LazarusIDE) Or Not Assigned(LazarusIDE.ActiveProject) Then
    Begin
      ErrorText := 'No active Lazarus project.';
      Exit;
    End;
  Proj := LazarusIDE.ActiveProject;
  Root := ProjectRootPath;
  ResultText :=
    'Project root: ' + Root + LineEnding +
    'Project info: ' + Proj.ProjectInfoFile + LineEnding;
  If Assigned(Proj.MainFile) Then
    ResultText := ResultText + 'Main file: ' + Proj.MainFile.Filename + LineEnding;
  ResultText := ResultText + 'Title: ' + Proj.GetTitle;
  Result := True;
End;

Function ExecuteAssistantToolForMode(Const ToolName, ArgumentsJson: String; Mode: TAssistantMode;
  Out ResultText: String; Out ErrorText: String): Boolean;
Var
  Name: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Name := LowerCase(Trim(ToolName));
  If Not ToolAllowedInMode(Name, Mode) Then
    Begin
      ErrorText := Format('Tool "%s" is not available in %s mode.',
        [ToolName, AssistantModeToStr(Mode)]);
      Exit;
    End;
  Result := ExecuteAssistantTool(ToolName, ArgumentsJson, ResultText, ErrorText);
End;

Function ExecuteAssistantTool(Const ToolName, ArgumentsJson: String; Out ResultText: String;
  Out ErrorText: String): Boolean;
Var
  Name: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Name := LowerCase(Trim(ToolName));
  WorkflowLogger.Info('AssistantTools', 'Execute ' + Name);
  If Name = 'read_file' Then
    Result := ToolReadFile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'list_directory' Then
    Result := ToolListDirectory(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'open_markdown' Then
    Result := ToolOpenMarkdown(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'get_project_info' Then
    Result := ToolGetProjectInfo(ResultText, ErrorText)
  Else
    ErrorText := 'Unknown tool: ' + ToolName;
End;

End.
