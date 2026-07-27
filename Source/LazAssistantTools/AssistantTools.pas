Unit AssistantTools;

{ Built-in IDE tools for LazAssistantTools (read + Plan-mode Markdown writes) (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantConversation;

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
{ Active plan relative path for tools / UI (empty if unset). }
Function GetActivePlanRelativePath: String;
Procedure SetActivePlanRelativePath(Const RelativePath: String);

Implementation

Uses
  LazFileUtils, FileUtil, LazIDEIntf, ProjectIntf, WorkflowLog, AssistantMarkdownForm,
  AssistantPlan, fpjson, jsonparser;

Var
  GActivePlanRelative: String;

Function JsonEscapeLocal(Const SourceText: String): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := '';
  For I := 1 To Length(SourceText) Do
    Begin
      C := SourceText[I];
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

Function GetActivePlanRelativePath: String;
Begin
  Result := Trim(GActivePlanRelative);
End;

Procedure SetActivePlanRelativePath(Const RelativePath: String);
Begin
  GActivePlanRelative := Trim(RelativePath);
  GActivePlanRelative := StringReplace(GActivePlanRelative, '\', '/', [rfReplaceAll]);
End;

Function ToolAllowedInMode(Const ToolName: String; Mode: TAssistantMode): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(ToolName));
  { Shared read tools for all modes. }
  If (Name = 'read_file') Or (Name = 'list_directory') Or
    (Name = 'open_markdown') Or (Name = 'get_project_info') Then
    Begin
      Result := Mode In [amChat, amPlan, amCode];
      Exit;
    End;
  { Plan workspace tools — Plan and Code (Code will use them for Status: updates). }
  If (Name = 'write_markdown') Or (Name = 'update_markdown') Or
    (Name = 'list_plans') Or (Name = 'set_active_plan') Or
    (Name = 'get_active_plan') Then
    Begin
      Result := Mode In [amPlan, amCode];
      Exit;
    End;
  Result := False;
End;

Function BuildReadToolsJson: String;
Begin
  Result :=
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
    '}}';
End;

Function BuildPlanToolsJson: String;
Begin
  Result :=
    '{"type":"function","function":{' +
      '"name":"write_markdown",' +
      '"description":"Create or overwrite a Markdown file under the project (prefer Documents/). Opens a live Markdown window. Use for new or full rewrites of plans.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative .md path (default Documents/Plan.md)"},' +
        '"content":{"type":"string","description":"Full Markdown body to write"},' +
        '"open":{"type":"boolean","description":"Open live viewer after write (default true)"}' +
      '},"required":["content"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"update_markdown",' +
      '"description":"Exact text replacement in a project Markdown file (surgical edit). Prefer this over rewrite when changing Status: lines or a single section.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative .md path (default: active plan)"},' +
        '"old_text":{"type":"string","description":"Exact text to find"},' +
        '"new_text":{"type":"string","description":"Replacement text"},' +
        '"replace_all":{"type":"boolean","description":"Replace every match (default false)"},' +
        '"open":{"type":"boolean","description":"Open live viewer after update (default true)"}' +
      '},"required":["old_text","new_text"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"list_plans",' +
      '"description":"List project-relative Markdown files (Documents/ plans first).",' +
      '"parameters":{"type":"object","properties":{},"required":[]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"get_active_plan",' +
      '"description":"Return the canonical active plan path for this project (from .assistant/config.json).",' +
      '"parameters":{"type":"object","properties":{},"required":[]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"set_active_plan",' +
      '"description":"Set the canonical active plan Markdown path for this project.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative .md path"}' +
      '},"required":["path"]}' +
    '}}';
End;

Function BuildAssistantToolsJson: String;
Begin
  Result := '[' + BuildReadToolsJson + ']';
End;

Function BuildAssistantToolsJsonForMode(Mode: TAssistantMode): String;
Begin
  Case Mode Of
    amPlan, amCode:
      Result := '[' + BuildReadToolsJson + ',' + BuildPlanToolsJson + ']';
    amChat:
      Result := BuildAssistantToolsJson;
  Else
    Result := '[]';
  End;
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
  If GetActivePlanRelativePath <> '' Then
    ResultText := ResultText + LineEnding + 'Active plan: ' + GetActivePlanRelativePath;
  Result := True;
End;

Function JsonArgBool(Const ArgumentsJson, FieldName: String; DefaultValue: Boolean): Boolean;
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
      If Assigned(Node) And (Node.JSONType = jtBoolean) Then
        Result := Node.AsBoolean
      Else If Assigned(Node) And (Node.JSONType = jtString) Then
        Result := SameText(Node.AsString, 'true') Or SameText(Node.AsString, '1');
    Except
      Result := DefaultValue;
    End;
  Finally
    Data.Free;
  End;
End;

Function ToolWriteMarkdown(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Content, Resolved, OldPlan: String;
  OpenAfter, ShowThinking: Boolean;
  Mode: TAssistantMode;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  If Path = '' Then
    Path := GetActivePlanRelativePath;
  If Path = '' Then
    Path := DefaultPlanRelativePath;
  Content := JsonArgString(ArgumentsJson, 'content');
  If Content = '' Then
    Begin
      ErrorText := 'write_markdown requires content.';
      Exit;
    End;
  OpenAfter := JsonArgBool(ArgumentsJson, 'open', True);
  If Not EnsureProjectDocumentsDir(ErrorText) Then
    { non-fatal if path is not under Documents }
    ErrorText := '';
  If Not WriteMarkdownFile(Path, Content, OpenAfter, Resolved, ErrorText) Then
    Exit;
  If GetActivePlanRelativePath = '' Then
    Begin
      SetActivePlanRelativePath(ProjectRelativePath(Resolved));
      If Assigned(ProjectAssistantConversation) And
        (ProjectAssistantConversation.ProjectRoot <> '') Then
        Begin
          ShowThinking := True;
          Mode := amPlan;
          OldPlan := '';
          If Not ProjectAssistantConversation.LoadShellConfig(ShowThinking, Mode, OldPlan) Then
            Begin
              ShowThinking := True;
              Mode := amPlan;
            End;
          ProjectAssistantConversation.SaveShellConfig(ShowThinking, Mode, GetActivePlanRelativePath);
        End;
    End;
  ResultText := 'Wrote Markdown: ' + ProjectRelativePath(Resolved) +
    ' (' + Resolved + ')';
  Result := True;
End;

Function ToolUpdateMarkdown(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, OldText, NewText, Resolved: String;
  ReplaceAll, OpenAfter: Boolean;
  Count: Integer;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  If Path = '' Then
    Path := GetActivePlanRelativePath;
  If Path = '' Then
    Path := DefaultPlanRelativePath;
  OldText := JsonArgString(ArgumentsJson, 'old_text');
  NewText := JsonArgString(ArgumentsJson, 'new_text');
  ReplaceAll := JsonArgBool(ArgumentsJson, 'replace_all', False);
  OpenAfter := JsonArgBool(ArgumentsJson, 'open', True);
  If Not ReplaceInMarkdownFile(Path, OldText, NewText, ReplaceAll, OpenAfter, Resolved,
    ErrorText, Count) Then
    Exit;
  ResultText := Format('Updated %s (%d replacement(s)).',
    [ProjectRelativePath(Resolved), Count]);
  Result := True;
End;

Function ToolListPlans(Out ResultText, ErrorText: String): Boolean;
Var
  Paths: TStringList;
  I: Integer;
  Active: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Paths := Nil;
  If Not ListProjectMarkdownPlans(Paths, ErrorText) Then
    Begin
      Paths.Free;
      Exit;
    End;
  Try
    Active := GetActivePlanRelativePath;
    ResultText := Format('Markdown files under project (%d):', [Paths.Count]) + LineEnding;
    If Active <> '' Then
      ResultText := ResultText + 'Active plan: ' + Active + LineEnding;
    For I := 0 To Paths.Count - 1 Do
      If SameText(Paths[I], Active) Then
        ResultText := ResultText + '* ' + Paths[I] + '  (active)' + LineEnding
      Else
        ResultText := ResultText + '- ' + Paths[I] + LineEnding;
    If Paths.Count = 0 Then
      ResultText := ResultText + '(none yet — use write_markdown to create Documents/Plan.md)' +
        LineEnding;
    Result := True;
  Finally
    Paths.Free;
  End;
End;

Function ToolGetActivePlan(Out ResultText, ErrorText: String): Boolean;
Var
  Active, Resolved: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Active := GetActivePlanRelativePath;
  If Active = '' Then
    Begin
      ResultText := 'No active plan set. Default path would be ' + DefaultPlanRelativePath +
        '. Use set_active_plan or write_markdown.';
      Result := True;
      Exit;
    End;
  If ResolvePlanPath(Active, Resolved, ErrorText) Then
    Begin
      ResultText := 'Active plan: ' + Active + LineEnding + 'Absolute: ' + Resolved;
      If FileExistsUTF8(Resolved) Then
        ResultText := ResultText + LineEnding + 'Exists: yes'
      Else
        ResultText := ResultText + LineEnding + 'Exists: no (file missing)';
      Result := True;
    End;
End;

Function ToolSetActivePlan(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved, OldPlan: String;
  ShowThinking: Boolean;
  Mode: TAssistantMode;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  If Path = '' Then
    Begin
      ErrorText := 'set_active_plan requires path.';
      Exit;
    End;
  If Not ResolvePlanPath(Path, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'Plan file does not exist yet: ' + Resolved;
      Exit;
    End;
  SetActivePlanRelativePath(ProjectRelativePath(Resolved));
  If Assigned(ProjectAssistantConversation) And
    (ProjectAssistantConversation.ProjectRoot <> '') Then
    Begin
      ShowThinking := True;
      Mode := amPlan;
      OldPlan := '';
      If Not ProjectAssistantConversation.LoadShellConfig(ShowThinking, Mode, OldPlan) Then
        Begin
          ShowThinking := True;
          Mode := amPlan;
        End;
      ProjectAssistantConversation.SaveShellConfig(ShowThinking, Mode, GetActivePlanRelativePath);
    End;
  ResultText := 'Active plan set to ' + GetActivePlanRelativePath;
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
  Else If Name = 'write_markdown' Then
    Result := ToolWriteMarkdown(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'update_markdown' Then
    Result := ToolUpdateMarkdown(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'list_plans' Then
    Result := ToolListPlans(ResultText, ErrorText)
  Else If Name = 'get_active_plan' Then
    Result := ToolGetActivePlan(ResultText, ErrorText)
  Else If Name = 'set_active_plan' Then
    Result := ToolSetActivePlan(ArgumentsJson, ResultText, ErrorText)
  Else
    ErrorText := 'Unknown tool: ' + ToolName;
End;

Initialization

GActivePlanRelative := '';

End.
