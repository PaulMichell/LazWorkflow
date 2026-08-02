Unit AssistantTools;

{ Built-in IDE tools for LazAssistantTools: read, Plan Markdown, Code source edit (c) 2026 Michell Computing. }

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
  AssistantToolMaxWriteChars = 400000;
  AssistantToolMaxSearchMatches = 50;
  AssistantToolMaxSearchFiles = 2500;

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
{ Last run_compile outcome for Code-mode auto Status: complete (seq bumps each run). }
Function AssistantLastCompileSeq: Integer;
Function AssistantLastCompileWasClean: Boolean;

Implementation

Uses
  Forms, Controls, Dialogs, Process, LazFileUtils, FileUtil, LazIDEIntf, ProjectIntf,
  SrcEditorIntf, IDEMsgIntf, IDEExternToolIntf, CompOptsIntf, WorkflowLog,
  AssistantMarkdownForm, AssistantPlan, AssistantConfig, fpjson, jsonparser;

Var
  GActivePlanRelative: String;
  GLastCompileSeq: Integer;
  GLastCompileClean: Boolean;

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

Function AssistantLastCompileSeq: Integer;
Begin
  Result := GLastCompileSeq;
End;

Function AssistantLastCompileWasClean: Boolean;
Begin
  Result := GLastCompileClean;
End;

Function ToolIsReadOnly(Const ToolName: String): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(ToolName));
  Result := (Name = 'read_file') Or (Name = 'list_directory') Or
    (Name = 'open_markdown') Or (Name = 'get_project_info') Or
    (Name = 'list_plans') Or (Name = 'get_active_plan') Or
    (Name = 'search_in_project') Or (Name = 'open_file');
End;

Function ToolRequiresApproval(Const ToolName: String): Boolean;
Begin
  Result := Not ToolIsReadOnly(ToolName);
End;

Function ApproveToolIfNeeded(Const ToolName, ArgumentsJson: String; Out ErrorText: String): Boolean;
Var
  Mode: TAssistantApprovalMode;
  Summary, Name: String;
Begin
  Result := True;
  ErrorText := '';
  Name := LowerCase(Trim(ToolName));
  If Not ToolRequiresApproval(Name) Then
    Exit;
  Mode := aamAlways;
  If Assigned(AssistantChatConfig) Then
    Mode := AssistantChatConfig.GetApprovalMode;
  If Mode = aamAlways Then
    Exit;
  If Mode = aamAuto Then
    { Auto: allow all project tools without a prompt (sandbox still applies). }
    Exit;
  { Ask: confirm mutating tools. }
  Summary := Copy(Trim(ArgumentsJson), 1, 240);
  If Length(Trim(ArgumentsJson)) > 240 Then
    Summary := Summary + '…';
  If MessageDlg(
    'Project Assistant wants to run tool:' + LineEnding + LineEnding +
    Name + LineEnding + LineEnding +
    Summary + LineEnding + LineEnding +
    'Allow this action? (Approval mode: Ask)',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
    Begin
      Result := False;
      ErrorText := 'User denied tool "' + Name + '" (approval mode: Ask).';
    End;
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
  { Plan workspace tools — Plan and Code (Code uses them for Status: updates). }
  If (Name = 'write_markdown') Or (Name = 'update_markdown') Or
    (Name = 'list_plans') Or (Name = 'set_active_plan') Or
    (Name = 'get_active_plan') Then
    Begin
      Result := Mode In [amPlan, amCode];
      Exit;
    End;
  { Code-mode source tools — never Chat or Plan. }
  If (Name = 'write_file') Or (Name = 'replace_in_file') Or
    (Name = 'search_in_project') Or (Name = 'run_compile') Or
    (Name = 'add_unit_to_project') Or (Name = 'open_file') Or
    (Name = 'ensure_form_component') Then
    Begin
      Result := Mode = amCode;
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

Function BuildCodeToolsJson: String;
Begin
  Result :=
    '{"type":"function","function":{' +
      '"name":"search_in_project",' +
      '"description":"Search project source/text files for a string (case-insensitive). Prefer this before many read_file calls.",' +
      '"parameters":{"type":"object","properties":{' +
        '"query":{"type":"string","description":"Text to find"},' +
        '"path":{"type":"string","description":"Subfolder under project root (empty = whole project)"},' +
        '"glob":{"type":"string","description":"Optional extension filter e.g. .pas or .lfm (default: common text/source types)"},' +
        '"max_matches":{"type":"integer","description":"Max matches to return (default 50)"}' +
      '},"required":["query"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"write_file",' +
      '"description":"Create or overwrite a real project file. Never create empty files or ApiProbe/scratch/temp units — use search_in_project, list_directory, and read_file to discover APIs. Prefer replace_in_file for small edits.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative path e.g. Source/Foo.pas"},' +
        '"content":{"type":"string","description":"Full non-empty contents (reject empty/probe files)"},' +
        '"open":{"type":"boolean","description":"Open/reuse a single editor tab after write (default false)"},' +
        '"add_to_project":{"type":"boolean","description":"Add Pascal unit to the active project (default true only for non-empty units)"}' +
      '},"required":["path","content"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"replace_in_file",' +
      '"description":"Exact text replacement in a project source/text file. Prefer small unique old_text. Updates open editor buffer when the file is open (Undoable in IDE).",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative file path"},' +
        '"old_text":{"type":"string","description":"Exact text to find"},' +
        '"new_text":{"type":"string","description":"Replacement text"},' +
        '"replace_all":{"type":"boolean","description":"Replace every match (default false)"}' +
      '},"required":["path","old_text","new_text"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"run_compile",' +
      '"description":"Compile the active project. Default is quiet non-visual lazbuild (no Messages UI, does not steal focus). Set ui=true only for a final IDE Messages build.",' +
      '"parameters":{"type":"object","properties":{' +
        '"kind":{"type":"string","description":"compile (default) or build (rebuild-all when quiet)"},' +
        '"ui":{"type":"boolean","description":"If true, use IDE DoBuildProject and Messages window (default false = quiet lazbuild)"}' +
      '},"required":[]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"add_unit_to_project",' +
      '"description":"Register an existing Pascal unit file with the active Lazarus project (.lpi).",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative .pas/.pp path"},' +
        '"add_to_uses":{"type":"boolean","description":"Also add to main uses clause when possible (default false)"}' +
      '},"required":["path"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"open_file",' +
      '"description":"Open a project source file in the Lazarus source editor.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative file path"}' +
      '},"required":["path"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"ensure_form_component",' +
      '"description":"Add or update a published form component in BOTH the .pas unit and matching .lfm. Required when adding TTimer, TButton, etc. so events fire. Prefer this over hand-editing LFM alone.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Form unit path (.pas or .lfm), e.g. unit1.pas"},' +
        '"name":{"type":"string","description":"Component name, e.g. ColorTimer"},' +
        '"class_name":{"type":"string","description":"Component class, e.g. TTimer"},' +
        '"properties":{"type":"string","description":"Optional JSON object of LFM properties, e.g. {\"Interval\":1000,\"OnTimer\":\"ColorTimerTimer\",\"Enabled\":true}. TTimer Interval is milliseconds (1000 = 1 second)."},' +
        '"event_method":{"type":"string","description":"Optional event handler method name to declare/implement (e.g. ColorTimerTimer). Defaults from On* properties when omitted."},' +
        '"uses_unit":{"type":"string","description":"Optional unit to add to interface Uses (e.g. ExtCtrls for TTimer)"}' +
      '},"required":["path","name","class_name"]}' +
    '}}';
End;

Function BuildAssistantToolsJson: String;
Begin
  Result := '[' + BuildReadToolsJson + ']';
End;

Function BuildAssistantToolsJsonForMode(Mode: TAssistantMode): String;
Begin
  Case Mode Of
    amPlan:
      Result := '[' + BuildReadToolsJson + ',' + BuildPlanToolsJson + ']';
    amCode:
      Result := '[' + BuildReadToolsJson + ',' + BuildPlanToolsJson + ',' + BuildCodeToolsJson + ']';
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
  S: String;
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
      If Not Assigned(Node) Or (Node.JSONType = jtNull) Then
        Exit;
      If Node.JSONType = jtBoolean Then
        Result := Node.AsBoolean
      Else If Node.JSONType = jtString Then
        Begin
          S := LowerCase(Trim(Node.AsString));
          Result := (S = '1') Or (S = 'true') Or (S = 'yes');
        End
      Else If Node.JSONType = jtNumber Then
        Result := Node.AsInteger <> 0;
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

Function IsBlockedBinaryExtension(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '.o') Or (Ext = '.ppu') Or (Ext = '.a') Or (Ext = '.so') Or
    (Ext = '.dll') Or (Ext = '.exe') Or (Ext = '.or') Or (Ext = '.rsj') Or
    (Ext = '.compiled') Or (Ext = '.zip') Or (Ext = '.png') Or (Ext = '.jpg') Or
    (Ext = '.jpeg') Or (Ext = '.gif') Or (Ext = '.ico') Or (Ext = '.pdf') Or
    (Ext = '.bmp') Or (Ext = '.wasm') Or (Ext = '.dbg');
End;

Function IsSearchableTextExtension(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '') Or (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.lpr') Or
    (Ext = '.lfm') Or (Ext = '.lrs') Or (Ext = '.inc') Or (Ext = '.txt') Or
    (Ext = '.md') Or (Ext = '.json') Or (Ext = '.xml') Or (Ext = '.lpi') Or
    (Ext = '.lpk') Or (Ext = '.rc') Or (Ext = '.sql') Or (Ext = '.sh') Or
    (Ext = '.bat') Or (Ext = '.csv') Or (Ext = '.ini') Or (Ext = '.cfg') Or
    (Ext = '.yml') Or (Ext = '.yaml') Or (Ext = '.html') Or (Ext = '.css');
End;

Function IsPascalUnitPath(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.lpr');
End;

Function LoadProjectFileText(Const Resolved: String; Out Body: String; Out FromEditor: Boolean;
  Out ErrorText: String): Boolean;
Var
  Ed: TSourceEditorInterface;
  SL: TStringList;
Begin
  Result := False;
  Body := '';
  FromEditor := False;
  ErrorText := '';
  If Assigned(SourceEditorManagerIntf) Then
    Begin
      Ed := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Resolved);
      If Assigned(Ed) Then
        Begin
          Body := Ed.SourceText;
          FromEditor := True;
          Result := True;
          Exit;
        End;
    End;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'File not found: ' + Resolved;
      Exit;
    End;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(Resolved);
      Body := SL.Text;
      Result := True;
    Except
      On E: Exception Do
        ErrorText := E.Message;
    End;
  Finally
    SL.Free;
  End;
End;

Function ExpandResolvedPath(Const Path: String): String;
Begin
  Result := ExpandFileNameUTF8(Path);
End;

Function FindOpenEditor(Const Resolved: String): TSourceEditorInterface;
Var
  FullPath: String;
Begin
  Result := Nil;
  If Not Assigned(SourceEditorManagerIntf) Then
    Exit;
  FullPath := ExpandResolvedPath(Resolved);
  Result := SourceEditorManagerIntf.SourceEditorIntfWithFilename(FullPath);
  If Not Assigned(Result) And (FullPath <> Resolved) Then
    Result := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Resolved);
End;

Function LooksLikeScratchProbePath(Const Path: String): Boolean;
Var
  Base: String;
Begin
  Base := LowerCase(ChangeFileExt(ExtractFileName(Path), ''));
  { Model-invented disposable units (ApiProbe, _ApiProbe, WP4ApiProbe, …). }
  Result := (Pos('probe', Base) > 0) Or (Pos('scratch', Base) > 0) Or
    (Pos('tmpunit', Base) > 0) Or (Pos('tempunit', Base) > 0) Or
    (Copy(Base, 1, 1) = '_') And ((Pos('test', Base) > 0) Or (Pos('api', Base) > 0));
End;

Function OpenEditorReuse(Const Resolved: String; Out Note: String): Boolean;
Var
  Ed: TSourceEditorInterface;
  FullPath: String;
Begin
  Result := False;
  Note := '';
  FullPath := ExpandResolvedPath(Resolved);
  Ed := FindOpenEditor(FullPath);
  If Assigned(Ed) Then
    Begin
      Note := 'Already open in editor (reused existing tab, focus not stolen).';
      Result := True;
      Exit;
    End;
  If Not Assigned(LazarusIDE) Then
    Begin
      Note := 'LazarusIDE not available.';
      Exit;
    End;
  { ofDoNotActivateSourceEditor keeps focus on the user's current window. }
  If LazarusIDE.DoOpenEditorFile(FullPath, -1, -1,
    [ofOnlyIfExists, ofQuiet, ofDoNotLoadResource, ofRegularFile,
     ofDoNotActivateSourceEditor]) = mrOk Then
    Begin
      Note := 'Opened in editor (background, no focus steal).';
      Result := True;
    End
  Else
    Note := 'Could not open editor.';
End;

Function FindLazbuildExecutable: String;
Var
  Cand: String;
Begin
  Result := FindDefaultExecutablePath('lazbuild');
  If (Result <> '') And FileExistsUTF8(Result) Then
    Exit;
  Cand := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'lazbuild'{$IFDEF WINDOWS}+'.exe'{$ENDIF};
  If FileExistsUTF8(Cand) Then
    Begin
      Result := Cand;
      Exit;
    End;
  Result := '';
End;

Function RunProcessCapture(Const Exe, WorkDir: String; Const Args: Array Of String;
  Out OutputText: String; Out ExitCode: Integer; Out ErrorText: String): Boolean;
Var
  Proc: TProcess;
  I, BytesRead: Integer;
  Mem: TMemoryStream;
  Buf: Array[0..8191] Of Byte;
Begin
  Result := False;
  OutputText := '';
  ExitCode := -1;
  ErrorText := '';
  FillChar(Buf, SizeOf(Buf), 0);
  If (Exe = '') Or (Not FileExistsUTF8(Exe)) Then
    Begin
      ErrorText := 'Executable not found: ' + Exe;
      Exit;
    End;
  Proc := TProcess.Create(Nil);
  Mem := TMemoryStream.Create;
  Try
    Proc.Executable := Exe;
    If WorkDir <> '' Then
      Proc.CurrentDirectory := WorkDir;
    Proc.Options := [poUsePipes, poNoConsole, poStderrToOutPut];
    Proc.Parameters.Clear;
    For I := 0 To High(Args) Do
      Proc.Parameters.Add(Args[I]);
    Try
      Proc.Execute;
      While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
        Begin
          If Proc.Output.NumBytesAvailable > 0 Then
            Begin
              BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
              If BytesRead > 0 Then
                Mem.WriteBuffer(Buf[0], BytesRead);
            End
          Else If Proc.Running Then
            Sleep(5);
        End;
      While Proc.Output.NumBytesAvailable > 0 Do
        Begin
          BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
          If BytesRead > 0 Then
            Mem.WriteBuffer(Buf[0], BytesRead)
          Else
            Break;
        End;
      ExitCode := Proc.ExitStatus;
      SetLength(OutputText, Mem.Size);
      If Mem.Size > 0 Then
        Move(Mem.Memory^, OutputText[1], Mem.Size);
      Result := True;
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Failed to run ' + ExtractFileName(Exe) + ': ' + E.Message;
          Result := False;
        End;
    End;
  Finally
    Mem.Free;
    Proc.Free;
  End;
End;

Function CountCompilerDiagnostics(Const OutputText: String; Out ErrorCount, WarningCount, HintCount: Integer): String;
Var
  SL: TStringList;
  I: Integer;
  Line, LowLine: String;
  Keep: TStringList;
Begin
  ErrorCount := 0;
  WarningCount := 0;
  HintCount := 0;
  Keep := TStringList.Create;
  SL := TStringList.Create;
  Try
    SL.Text := OutputText;
    For I := 0 To SL.Count - 1 Do
      Begin
        Line := SL[I];
        LowLine := LowerCase(Line);
        If (Pos('fatal:', LowLine) > 0) Or (Pos('error:', LowLine) > 0) Then
          Begin
            Inc(ErrorCount);
            Keep.Add(Line);
          End
        Else If Pos('warning:', LowLine) > 0 Then
          Begin
            Inc(WarningCount);
            If Keep.Count < 80 Then
              Keep.Add(Line);
          End
        Else If (Pos('hint:', LowLine) > 0) Or (Pos('note:', LowLine) > 0) Then
          Begin
            Inc(HintCount);
            If Keep.Count < 80 Then
              Keep.Add(Line);
          End
        Else If (Pos('compiling ', LowLine) > 0) Or (Pos('linking ', LowLine) > 0) Or
          (Pos('error while', LowLine) > 0) Then
          If Keep.Count < 80 Then
            Keep.Add(Line);
      End;
    If Keep.Count = 0 Then
      Result := TrimRight(OutputText)
    Else
      Result := TrimRight(Keep.Text);
    If Length(Result) > 12000 Then
      Result := Copy(Result, 1, 12000) + LineEnding + '[… compile output truncated …]';
  Finally
    Keep.Free;
    SL.Free;
  End;
End;

Function SaveProjectFileText(Const Resolved, Content: String; OpenAfter: Boolean;
  Out Note: String; Out ErrorText: String): Boolean;
Var
  Ed: TSourceEditorInterface;
  SL: TStringList;
  Dir, FullPath, OpenNote: String;
Begin
  Result := False;
  Note := '';
  ErrorText := '';
  FullPath := ExpandResolvedPath(Resolved);
  If IsBlockedBinaryExtension(FullPath) Then
    Begin
      ErrorText := 'Refusing to write blocked/binary extension: ' + FullPath;
      Exit;
    End;
  If Length(Content) > AssistantToolMaxWriteChars Then
    Begin
      ErrorText := Format('Content too large (%d chars; max %d).',
        [Length(Content), AssistantToolMaxWriteChars]);
      Exit;
    End;
  Ed := FindOpenEditor(FullPath);
  If Assigned(Ed) Then
    Begin
      Try
        Ed.SourceText := Content;
        Note := 'Updated open editor buffer (IDE Undo available).';
        Result := True;
        Exit;
      Except
        On E: Exception Do
          Begin
            ErrorText := 'Editor update failed: ' + E.Message;
            Exit;
          End;
      End;
    End;
  Dir := ExtractFilePath(FullPath);
  If (Dir <> '') And (Not DirectoryExistsUTF8(Dir)) Then
    If Not ForceDirectoriesUTF8(Dir) Then
      Begin
        ErrorText := 'Could not create directory: ' + Dir;
        Exit;
      End;
  SL := TStringList.Create;
  Try
    Try
      SL.Text := Content;
      SL.SaveToFile(FullPath);
      Note := 'Wrote file on disk.';
      Result := True;
    Except
      On E: Exception Do
        Begin
          ErrorText := E.Message;
          Exit;
        End;
    End;
  Finally
    SL.Free;
  End;
  If OpenAfter Then
    Begin
      If OpenEditorReuse(FullPath, OpenNote) Then
        Begin
          Ed := FindOpenEditor(FullPath);
          If Assigned(Ed) Then
            Try
              Ed.SourceText := Content;
            Except
            End;
          Note := Note + ' ' + OpenNote;
        End
      Else
        Note := Note + ' (' + OpenNote + ')';
    End;
End;

Procedure FlushOpenEditorsUnderProject;
Var
  I: Integer;
  Ed: TSourceEditorInterface;
  FullPath, Root, Note, Err: String;
Begin
  { Write modified open buffers to disk without activating source editor windows.
    Quiet lazbuild needs on-disk content, not only editor RAM. }
  If Not Assigned(SourceEditorManagerIntf) Then
    Exit;
  Root := ProjectRootPath;
  If Root = '' Then
    Exit;
  For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
    Begin
      Ed := SourceEditorManagerIntf.SourceEditors[I];
      If Not Assigned(Ed) Or Not Ed.Modified Then
        Continue;
      FullPath := ExpandResolvedPath(Ed.FileName);
      If FullPath = '' Then
        Continue;
      If Not IsPathUnderRoot(Root, FullPath) Then
        Continue;
      SaveProjectFileText(FullPath, Ed.SourceText, False, Note, Err);
    End;
End;

Function RunQuietLazbuild(KindBuild: Boolean; Out ResultText, ErrorText: String;
  Out ErrorCount, WarningCount, HintCount: Integer; Out BuildOk: Boolean): Boolean;
Var
  Lazbuild, Lpi, WorkDir, OutputText, Diag: String;
  ExitCode: Integer;
  Args: Array Of String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  ErrorCount := 0;
  WarningCount := 0;
  HintCount := 0;
  BuildOk := False;
  If Not Assigned(LazarusIDE) Or Not Assigned(LazarusIDE.ActiveProject) Then
    Begin
      ErrorText := 'No active Lazarus project.';
      Exit;
    End;
  Lpi := LazarusIDE.ActiveProject.ProjectInfoFile;
  If (Lpi = '') Or (Not FileExistsUTF8(Lpi)) Then
    Begin
      ErrorText := 'Project .lpi not found for quiet compile.';
      Exit;
    End;
  Lazbuild := FindLazbuildExecutable;
  If Lazbuild = '' Then
    Begin
      ErrorText := 'lazbuild not found on PATH or next to the IDE. Use ui=true for IDE compile.';
      Exit;
    End;
  FlushOpenEditorsUnderProject;
  WorkDir := ExtractFilePath(Lpi);
  If KindBuild Then
    Begin
      SetLength(Args, 2);
      Args[0] := '--build-all';
      Args[1] := Lpi;
    End
  Else
    Begin
      SetLength(Args, 1);
      Args[0] := Lpi;
    End;
  If Not RunProcessCapture(Lazbuild, WorkDir, Args, OutputText, ExitCode, ErrorText) Then
    Exit;
  Diag := CountCompilerDiagnostics(OutputText, ErrorCount, WarningCount, HintCount);
  BuildOk := (ExitCode = 0) And (ErrorCount = 0);
  ResultText :=
    Format('quiet lazbuild finished: ok=%s exit=%d errors=%d warnings=%d hints/notes=%d',
      [BoolToStr(BuildOk, True), ExitCode, ErrorCount, WarningCount, HintCount]) +
    LineEnding +
    '(non-visual compile — Messages window not updated; use ui=true for IDE Messages build)' +
    LineEnding + LineEnding + Diag;
  Result := True;
End;

Function FormatIdeMessageLine(Line: TMessageLine): String;
Var
  Loc: String;
Begin
  Result := '';
  If Not Assigned(Line) Then
    Exit;
  If Trim(Line.OriginalLine) <> '' Then
    Begin
      Result := Line.OriginalLine;
      Exit;
    End;
  Loc := '';
  If Line.Filename <> '' Then
    Begin
      Loc := Line.GetFullFilename;
      If Line.Line > 0 Then
        Begin
          Loc := Loc + '(' + IntToStr(Line.Line);
          If Line.Column > 0 Then
            Loc := Loc + ',' + IntToStr(Line.Column);
          Loc := Loc + ')';
        End;
    End;
  If Loc <> '' Then
    Result := Loc + ' '
  Else
    Result := '';
  If Line.Urgency In [mluHint..mluPanic] Then
    Result := Result + MessageLineUrgencyNames[Line.Urgency] + ': ';
  If Line.TranslatedMsg <> '' Then
    Result := Result + Line.TranslatedMsg
  Else
    Result := Result + Line.Msg;
  Result := Trim(Result);
End;

Function CollectIdeMessagesSummary(Out ErrorCount, WarningCount, HintCount: Integer): String;
Var
  ViewIndex, LineIndex: Integer;
  View: TExtToolView;
  Line: TMessageLine;
  Parts: TStringList;
  Formatted: String;
Begin
  Result := '';
  ErrorCount := 0;
  WarningCount := 0;
  HintCount := 0;
  If Not Assigned(IDEMessagesWindow) Then
    Begin
      Result := '(IDE Messages window is not available.)';
      Exit;
    End;
  Parts := TStringList.Create;
  Try
    For ViewIndex := 0 To IDEMessagesWindow.ViewCount - 1 Do
      Begin
        View := IDEMessagesWindow.Views[ViewIndex];
        If Not Assigned(View) Then
          Continue;
        If View.Caption <> '' Then
          Parts.Add('--- ' + View.Caption + ' ---');
        View.Lines.EnterCriticalSection;
        Try
          For LineIndex := 0 To View.Lines.Count - 1 Do
            Begin
              Line := View.Lines.Items[LineIndex];
              If Not Assigned(Line) Then
                Continue;
              Case Line.Urgency Of
                mluError, mluFatal, mluPanic: Inc(ErrorCount);
                mluWarning: Inc(WarningCount);
                mluHint, mluNote: Inc(HintCount);
              Else
                { }
              End;
              Formatted := FormatIdeMessageLine(Line);
              If Formatted <> '' Then
                Parts.Add(Formatted);
            End;
        Finally
          View.Lines.LeaveCriticalSection;
        End;
        If View.SummaryMsg <> '' Then
          Parts.Add(View.SummaryMsg);
      End;
    If Parts.Count = 0 Then
      Parts.Add('(No messages were recorded in the IDE Messages window.)');
    Result := TrimRight(Parts.Text);
  Finally
    Parts.Free;
  End;
End;

Function ToolSearchInProject(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Query, Path, Resolved, Glob, Rel, LineText, LowerQuery: String;
  MaxMatches, MatchCount, FileCount, LineNo, I: Integer;
  Files: TStringList;
  SL: TStringList;
  ExtFilter: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Query := JsonArgString(ArgumentsJson, 'query');
  If Trim(Query) = '' Then
    Begin
      ErrorText := 'search_in_project requires query.';
      Exit;
    End;
  Path := JsonArgString(ArgumentsJson, 'path');
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  If Not DirectoryExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'Directory not found: ' + Resolved;
      Exit;
    End;
  Glob := Trim(JsonArgString(ArgumentsJson, 'glob'));
  ExtFilter := LowerCase(Glob);
  If (ExtFilter <> '') And (ExtFilter[1] <> '.') Then
    ExtFilter := '.' + ExtFilter;
  MaxMatches := JsonArgInt(ArgumentsJson, 'max_matches', AssistantToolMaxSearchMatches);
  If MaxMatches < 1 Then
    MaxMatches := AssistantToolMaxSearchMatches;
  If MaxMatches > 200 Then
    MaxMatches := 200;
  LowerQuery := LowerCase(Query);
  Files := FindAllFiles(Resolved, '*', True);
  SL := TStringList.Create;
  Try
    MatchCount := 0;
    FileCount := 0;
    ResultText := Format('Search for "%s" under %s', [Query, Resolved]) + LineEnding;
    For I := 0 To Files.Count - 1 Do
      Begin
        If FileCount >= AssistantToolMaxSearchFiles Then
          Begin
            ResultText := ResultText + Format('[… stopped after scanning %d files …]',
              [AssistantToolMaxSearchFiles]) + LineEnding;
            Break;
          End;
        If Not IsSearchableTextExtension(Files[I]) Then
          Continue;
        If (ExtFilter <> '') And (LowerCase(ExtractFileExt(Files[I])) <> ExtFilter) Then
          Continue;
        Inc(FileCount);
        Try
          SL.LoadFromFile(Files[I]);
        Except
          Continue;
        End;
        Rel := ProjectRelativePath(Files[I]);
        If Rel = '' Then
          Rel := Files[I];
        For LineNo := 0 To SL.Count - 1 Do
          Begin
            LineText := SL[LineNo];
            If Pos(LowerQuery, LowerCase(LineText)) > 0 Then
              Begin
                Inc(MatchCount);
                ResultText := ResultText + Format('%s:%d: %s',
                  [Rel, LineNo + 1, Trim(LineText)]) + LineEnding;
                If MatchCount >= MaxMatches Then
                  Begin
                    ResultText := ResultText + Format('[… capped at %d matches …]', [MaxMatches]);
                    Result := True;
                    Exit;
                  End;
              End;
          End;
      End;
    ResultText := ResultText + Format('Matches: %d (scanned %d text files).', [MatchCount, FileCount]);
    Result := True;
  Finally
    SL.Free;
    Files.Free;
  End;
End;

{ Must appear before ToolWriteFile / ToolReplaceInFile. }
Function FormLfmEditReminder(Const PasPath, PasBody: String): String;
Var
  LfmPath, RelPas: String;
Begin
  Result := '';
  If (LowerCase(ExtractFileExt(PasPath)) <> '.pas') And
    (LowerCase(ExtractFileExt(PasPath)) <> '.pp') Then
    Exit;
  LfmPath := ChangeFileExt(PasPath, '.lfm');
  If Not FileExistsUTF8(LfmPath) Then
    Exit;
  If (Pos('TTimer', PasBody) > 0) Or (Pos('TButton', PasBody) > 0) Or
    (Pos('TEdit', PasBody) > 0) Or (Pos('TLabel', PasBody) > 0) Or
    (Pos('TMemo', PasBody) > 0) Or (Pos('TAction', PasBody) > 0) Or
    (Pos('TImageList', PasBody) > 0) Or (Pos('TActionList', PasBody) > 0) Then
    Begin
      RelPas := ProjectRelativePath(PasPath);
      If RelPas = '' Then
        RelPas := ExtractFileName(PasPath);
      Result := LineEnding +
        'IMPORTANT: This form unit has a sibling ' + ExtractFileName(LfmPath) +
        '. Published components and On* events only fire if that .lfm is updated too. ' +
        'Do not claim the form works until you call ensure_form_component (preferred), e.g. ' +
        'ensure_form_component path=' + RelPas +
        ' name=ColorTimer class_name=TTimer ' +
        'properties={"Interval":1000,"Enabled":true,"OnTimer":"ColorTimerTimer"} ' +
        'event_method=ColorTimerTimer uses_unit=ExtCtrls — or replace_in_file on the .lfm. ' +
        'TTimer.Interval is milliseconds (1000 = once per second).';
    End;
End;

Function ToolWriteFile(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved, Content, Note: String;
  OpenAfter, AddToProject, Created: Boolean;
  Proj: TLazProject;
  PF: TLazProjectFile;
  Meaningful: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  Content := JsonArgString(ArgumentsJson, 'content');
  If Path = '' Then
    Begin
      ErrorText := 'write_file requires path.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  Resolved := ExpandResolvedPath(Resolved);
  Meaningful := Length(Trim(Content)) >= 20;
  { Empty / near-empty files are never useful deliverables and pollute the project. }
  If Not Meaningful Then
    Begin
      ErrorText :=
        'Refusing empty or near-empty write_file for ' + ProjectRelativePath(Resolved) +
        '. Do not create probe/scratch units. Use search_in_project, list_directory, and read_file ' +
        'to discover APIs; write real unit content only.';
      Exit;
    End;
  If LooksLikeScratchProbePath(Resolved) Then
    Begin
      ErrorText :=
        'Refusing scratch/probe path "' + ProjectRelativePath(Resolved) +
        '". Do not create ApiProbe/Temp/Scratch units. Discover existing units with search tools.';
      Exit;
    End;
  { Default: do not open a new editor tab for every write (avoids tab storms). }
  OpenAfter := JsonArgBool(ArgumentsJson, 'open', False);
  Created := Not FileExistsUTF8(Resolved);
  If Not SaveProjectFileText(Resolved, Content, OpenAfter, Note, ErrorText) Then
    Exit;
  ResultText := Format('Wrote %s (%d chars). %s',
    [ProjectRelativePath(Resolved), Length(Content), Note]);
  { Only auto-add substantial Pascal units — never empty probes. }
  AddToProject := JsonArgBool(ArgumentsJson, 'add_to_project',
    IsPascalUnitPath(Resolved) And Meaningful);
  If AddToProject And IsPascalUnitPath(Resolved) And Assigned(LazarusIDE) And
    Assigned(LazarusIDE.ActiveProject) Then
    Begin
      Proj := LazarusIDE.ActiveProject;
      If Assigned(Proj.FindFile(Resolved, [pfsfOnlyProjectFiles])) Then
        ResultText := ResultText + ' Already in project.'
      Else
        Try
          PF := Proj.CreateProjectFile(Resolved);
          If Assigned(PF) Then
            Begin
              Proj.AddFile(PF, False);
              ResultText := ResultText + ' Added to project.';
            End;
        Except
          On E: Exception Do
            ResultText := ResultText + ' (add_to_project failed: ' + E.Message + ')';
        End;
    End;
  If Created Then
    ResultText := ResultText + ' (new file)';
  ResultText := ResultText + FormLfmEditReminder(Resolved, Content);
  Result := True;
  WorkflowLogger.Info('AssistantTools', 'write_file ' + Resolved);
End;

Function ToolReplaceInFile(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved, OldText, NewText, Body, Note: String;
  ReplaceAll, FromEditor: Boolean;
  Count, P: Integer;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  OldText := JsonArgString(ArgumentsJson, 'old_text');
  NewText := JsonArgString(ArgumentsJson, 'new_text');
  If Path = '' Then
    Begin
      ErrorText := 'replace_in_file requires path.';
      Exit;
    End;
  If OldText = '' Then
    Begin
      ErrorText := 'replace_in_file requires non-empty old_text.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  If IsBlockedBinaryExtension(Resolved) Then
    Begin
      ErrorText := 'Refusing to edit blocked/binary extension: ' + Resolved;
      Exit;
    End;
  ReplaceAll := JsonArgBool(ArgumentsJson, 'replace_all', False);
  If Not LoadProjectFileText(Resolved, Body, FromEditor, ErrorText) Then
    Exit;
  If Pos(OldText, Body) < 1 Then
    Begin
      ErrorText := 'old_text not found in ' + Resolved;
      Exit;
    End;
  If ReplaceAll Then
    Begin
      Count := 0;
      P := 1;
      While P <= Length(Body) Do
        If Copy(Body, P, Length(OldText)) = OldText Then
          Begin
            Inc(Count);
            Inc(P, Length(OldText));
          End
        Else
          Inc(P);
      Body := StringReplace(Body, OldText, NewText, [rfReplaceAll]);
    End
  Else
    Begin
      P := Pos(OldText, Body);
      Body := Copy(Body, 1, P - 1) + NewText + Copy(Body, P + Length(OldText), MaxInt);
      Count := 1;
    End;
  If Not SaveProjectFileText(Resolved, Body, False, Note, ErrorText) Then
    Exit;
  ResultText := Format('Replaced %d occurrence(s) in %s. %s',
    [Count, ProjectRelativePath(Resolved), Note]);
  If FromEditor Then
    ResultText := ResultText + ' (edited open buffer)';
  ResultText := ResultText + FormLfmEditReminder(Resolved, Body);
  Result := True;
  WorkflowLogger.Info('AssistantTools', Format('replace_in_file %s n=%d', [Resolved, Count]));
End;

Function ToolRunCompile(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Kind: String;
  Reason: TCompileReason;
  BuildResult: TModalResult;
  MsgText: String;
  ErrorCount, WarningCount, HintCount: Integer;
  BuildOk, UseUi: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Not Assigned(LazarusIDE) Or Not Assigned(LazarusIDE.ActiveProject) Then
    Begin
      ErrorText := 'No active Lazarus project.';
      Exit;
    End;
  Kind := LowerCase(Trim(JsonArgString(ArgumentsJson, 'kind')));
  If Kind = '' Then
    Kind := 'compile';
  { Default quiet (lazbuild, no Messages UI). ui=true runs the full IDE compile
    for a final visual check. }
  UseUi := JsonArgBool(ArgumentsJson, 'ui', False);
  If (Not UseUi) And (Kind = 'build') And (JsonArgString(ArgumentsJson, 'ui') = '') Then
    UseUi := False; { still quiet unless ui=true }
  If Not UseUi Then
    Begin
      If Not RunQuietLazbuild(Kind = 'build', ResultText, ErrorText,
        ErrorCount, WarningCount, HintCount, BuildOk) Then
        Begin
          { Fall back to IDE compile if lazbuild missing. }
          If Pos('lazbuild not found', ErrorText) = 0 Then
            Exit;
          WorkflowLogger.Warning('AssistantTools', ErrorText + ' — falling back to IDE compile.');
          UseUi := True;
          ErrorText := '';
        End
      Else
        Begin
          Inc(GLastCompileSeq);
          GLastCompileClean := BuildOk And (ErrorCount = 0);
          If GLastCompileClean Then
            ResultText := ResultText + LineEnding +
              'COMPILE_CLEAN=1 (errors=0; Code mode may auto-mark the active plan package complete).'
          Else
            ResultText := ResultText + LineEnding +
              'COMPILE_CLEAN=0 (fix errors before treating the work package as done).';
          Result := True;
          WorkflowLogger.Info('AssistantTools',
            Format('run_compile quiet ok=%s e=%d w=%d',
              [BoolToStr(GLastCompileClean, True), ErrorCount, WarningCount]));
          Exit;
        End;
    End;

  If Kind = 'build' Then
    Reason := crBuild
  Else
    Reason := crCompile;
  Try
    { pbfDoNotSaveEditorFiles: we already flushed project buffers when quiet path ran;
      for pure UI path, IDE still saves as usual. }
    BuildResult := LazarusIDE.DoBuildProject(Reason, []);
    BuildOk := BuildResult = mrOk;
  Except
    On E: Exception Do
      Begin
        ErrorText := 'Build failed to start: ' + E.Message;
        Exit;
      End;
  End;
  MsgText := CollectIdeMessagesSummary(ErrorCount, WarningCount, HintCount);
  Inc(GLastCompileSeq);
  GLastCompileClean := BuildOk And (ErrorCount = 0);
  ResultText :=
    Format('IDE %s finished: ok=%s errors=%d warnings=%d hints/notes=%d',
      [Kind, BoolToStr(GLastCompileClean, True), ErrorCount, WarningCount, HintCount]) +
    LineEnding + LineEnding + MsgText;
  If GLastCompileClean Then
    ResultText := ResultText + LineEnding +
      'COMPILE_CLEAN=1 (errors=0; Code mode may auto-mark the active plan package complete).'
  Else
    ResultText := ResultText + LineEnding +
      'COMPILE_CLEAN=0 (fix errors before treating the work package as done).';
  Result := True;
  WorkflowLogger.Info('AssistantTools',
    Format('run_compile ui ok=%s e=%d w=%d',
      [BoolToStr(GLastCompileClean, True), ErrorCount, WarningCount]));
End;

Function ToolAddUnitToProject(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved: String;
  AddToUses: Boolean;
  Proj: TLazProject;
  PF: TLazProjectFile;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  If Path = '' Then
    Begin
      ErrorText := 'add_unit_to_project requires path.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'File not found: ' + Resolved;
      Exit;
    End;
  If Not IsPascalUnitPath(Resolved) Then
    Begin
      ErrorText := 'Only Pascal units (.pas/.pp/.lpr) can be added to the project.';
      Exit;
    End;
  If Not Assigned(LazarusIDE) Or Not Assigned(LazarusIDE.ActiveProject) Then
    Begin
      ErrorText := 'No active Lazarus project.';
      Exit;
    End;
  Proj := LazarusIDE.ActiveProject;
  AddToUses := JsonArgBool(ArgumentsJson, 'add_to_uses', False);
  If Assigned(Proj.FindFile(Resolved, [pfsfOnlyProjectFiles])) Then
    Begin
      ResultText := 'Already in project: ' + ProjectRelativePath(Resolved);
      Result := True;
      Exit;
    End;
  Try
    PF := Proj.CreateProjectFile(Resolved);
    If Not Assigned(PF) Then
      Begin
        ErrorText := 'CreateProjectFile returned nil.';
        Exit;
      End;
    Proj.AddFile(PF, AddToUses);
    ResultText := 'Added to project: ' + ProjectRelativePath(Resolved);
    If AddToUses Then
      ResultText := ResultText + ' (requested add_to_uses=true)';
    Result := True;
  Except
    On E: Exception Do
      ErrorText := E.Message;
  End;
End;

Function ToolOpenFile(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved, Note: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  If Path = '' Then
    Begin
      ErrorText := 'open_file requires path.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  Resolved := ExpandResolvedPath(Resolved);
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'File not found: ' + Resolved;
      Exit;
    End;
  If Not OpenEditorReuse(Resolved, Note) Then
    Begin
      ErrorText := 'Failed to open editor for ' + Resolved + ' (' + Note + ')';
      Exit;
    End;
  ResultText := Note + ' ' + ProjectRelativePath(Resolved);
  Result := True;
End;

Function SiblingFormPaths(Const AnyPath: String; Out PasPath, LfmPath: String): Boolean;
Var
  Base, Ext: String;
Begin
  Result := False;
  PasPath := '';
  LfmPath := '';
  Ext := LowerCase(ExtractFileExt(AnyPath));
  Base := ChangeFileExt(AnyPath, '');
  If (Ext = '.pas') Or (Ext = '.pp') Then
    Begin
      PasPath := AnyPath;
      LfmPath := Base + '.lfm';
      Result := True;
    End
  Else If Ext = '.lfm' Then
    Begin
      LfmPath := AnyPath;
      PasPath := Base + '.pas';
      If Not FileExistsUTF8(PasPath) Then
        PasPath := Base + '.pp';
      Result := True;
    End;
End;

Function EnsureUsesHasUnit(Var PasBody: String; Const UnitName: String): Boolean;
Var
  UsesPos, SemiPos: Integer;
  Slice, LowerBody, Needle: String;
Begin
  Result := False;
  If Trim(UnitName) = '' Then
    Exit;
  LowerBody := LowerCase(PasBody);
  Needle := LowerCase(UnitName);
  { Already present as a whole word-ish token. }
  If Pos(',' + Needle + ',', StringReplace(StringReplace(LowerBody, ' ', '', [rfReplaceAll]),
    LineEnding, '', [rfReplaceAll])) > 0 Then
    Exit;
  If Pos(' ' + Needle + ',', LowerBody) > 0 Then
    Exit;
  If Pos(',' + Needle + ' ', LowerBody) > 0 Then
    Exit;
  If Pos('uses' + Needle, StringReplace(LowerBody, ' ', '', [rfReplaceAll])) > 0 Then
    Exit;
  UsesPos := Pos('uses', LowerBody);
  If UsesPos < 1 Then
    Exit;
  SemiPos := Pos(';', Copy(PasBody, UsesPos, MaxInt));
  If SemiPos < 1 Then
    Exit;
  SemiPos := UsesPos + SemiPos - 1;
  Slice := Copy(PasBody, UsesPos, SemiPos - UsesPos);
  If Pos(LowerCase(UnitName), LowerCase(Slice)) > 0 Then
    Exit;
  Insert(', ' + UnitName, PasBody, SemiPos);
  Result := True;
End;

Function EnsurePublishedField(Var PasBody: String; Const CompName, ClassName: String): Boolean;
Var
  FieldLine, Needle: String;
  ClassPos, PubPos, InsertAt: Integer;
Begin
  Result := False;
  FieldLine := '    ' + CompName + ': ' + ClassName + ';';
  Needle := LowerCase(CompName + ':');
  If Pos(Needle, LowerCase(PasBody)) > 0 Then
    Exit;
  ClassPos := Pos('= class(', LowerCase(PasBody));
  If ClassPos < 1 Then
    ClassPos := Pos('= class', LowerCase(PasBody));
  If ClassPos < 1 Then
    Exit;
  PubPos := Pos('published', LowerCase(Copy(PasBody, ClassPos, MaxInt)));
  If PubPos > 0 Then
    Begin
      InsertAt := ClassPos + PubPos - 1 + Length('published');
      While (InsertAt <= Length(PasBody)) And (PasBody[InsertAt] In [#10, #13, ' ']) Do
        Inc(InsertAt);
      Insert(LineEnding + FieldLine, PasBody, InsertAt);
      Result := True;
      Exit;
    End;
  { Fallback: insert before first private/public after class. }
  PubPos := Pos('private', LowerCase(Copy(PasBody, ClassPos, MaxInt)));
  If PubPos < 1 Then
    PubPos := Pos('public', LowerCase(Copy(PasBody, ClassPos, MaxInt)));
  If PubPos < 1 Then
    Exit;
  InsertAt := ClassPos + PubPos - 1;
  Insert(LineEnding + '  published' + LineEnding + FieldLine + LineEnding, PasBody, InsertAt);
  Result := True;
End;

Function EnsureEventMethodDecl(Var PasBody: String; Const MethodName: String): Boolean;
Var
  Decl, Needle: String;
  ClassPos, PubPos, InsertAt: Integer;
Begin
  Result := False;
  If Trim(MethodName) = '' Then
    Exit;
  Decl := '    Procedure ' + MethodName + '(Sender: TObject);';
  Needle := LowerCase('procedure ' + MethodName + '(');
  If Pos(Needle, LowerCase(PasBody)) > 0 Then
    Exit;
  ClassPos := Pos('= class(', LowerCase(PasBody));
  If ClassPos < 1 Then
    ClassPos := Pos('= class', LowerCase(PasBody));
  If ClassPos < 1 Then
    Exit;
  PubPos := Pos('published', LowerCase(Copy(PasBody, ClassPos, MaxInt)));
  If PubPos < 1 Then
    Exit;
  InsertAt := ClassPos + PubPos - 1 + Length('published');
  While (InsertAt <= Length(PasBody)) And (PasBody[InsertAt] In [#10, #13, ' ']) Do
    Inc(InsertAt);
  Insert(LineEnding + Decl, PasBody, InsertAt);
  Result := True;
End;

Function EnsureEventMethodImpl(Var PasBody: String; Const FormClass, MethodName: String): Boolean;
Var
  Needle, Stub: String;
  ImplPos: Integer;
Begin
  Result := False;
  If (Trim(FormClass) = '') Or (Trim(MethodName) = '') Then
    Exit;
  Needle := LowerCase('procedure ' + FormClass + '.' + MethodName);
  If Pos(Needle, LowerCase(PasBody)) > 0 Then
    Exit;
  Stub :=
    LineEnding +
    'Procedure ' + FormClass + '.' + MethodName + '(Sender: TObject);' + LineEnding +
    'Begin' + LineEnding +
    '  { TODO: implement }' + LineEnding +
    'End;' + LineEnding;
  ImplPos := Pos(LineEnding + 'implementation', LowerCase(PasBody));
  If ImplPos < 1 Then
    ImplPos := Pos('implementation', LowerCase(PasBody));
  If ImplPos < 1 Then
    Exit;
  { Insert before finalization/end. of unit if present, else append before last End. }
  If Pos(LineEnding + 'initialization', LowerCase(PasBody)) > 0 Then
    Insert(Stub, PasBody, Pos(LineEnding + 'initialization', LowerCase(PasBody)))
  Else If Pos(LineEnding + 'finalization', LowerCase(PasBody)) > 0 Then
    Insert(Stub, PasBody, Pos(LineEnding + 'finalization', LowerCase(PasBody)))
  Else
    Begin
      { Before last "End." }
      ImplPos := Length(PasBody);
      While (ImplPos > 1) And (PasBody[ImplPos] In [#10, #13, ' ']) Do
        Dec(ImplPos);
      If (ImplPos >= 4) And (LowerCase(Copy(PasBody, ImplPos - 3, 4)) = 'end.') Then
        Insert(Stub, PasBody, ImplPos - 3)
      Else
        PasBody := PasBody + Stub;
    End;
  Result := True;
End;

Function DetectFormClassName(Const PasBody: String): String;
Var
  P, StartPos, I: Integer;
  Slice: String;
Begin
  Result := '';
  P := Pos('= class(', LowerCase(PasBody));
  If P < 1 Then
    P := Pos('= class', LowerCase(PasBody));
  If P < 1 Then
    Exit;
  StartPos := P - 1;
  While (StartPos > 1) And (PasBody[StartPos] In [' ', #9]) Do
    Dec(StartPos);
  I := StartPos;
  While (I > 1) And (PasBody[I] In ['A'..'Z', 'a'..'z', '0'..'9', '_']) Do
    Dec(I);
  If Not (PasBody[I] In ['A'..'Z', 'a'..'z', '0'..'9', '_']) Then
    Inc(I);
  Slice := Copy(PasBody, I, StartPos - I + 1);
  Result := Trim(Slice);
End;

Function BuildLfmPropertyLines(Const PropsJson: String; Out Lines: String; Out EventMethod: String): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  I: Integer;
  Key, Val: String;
  Node: TJSONData;
  IsEvent, IsIdent: Boolean;
  Ch: Char;
  J: Integer;
Begin
  Result := False;
  Lines := '';
  EventMethod := '';
  If Trim(PropsJson) = '' Then
    Begin
      Result := True;
      Exit;
    End;
  Data := Nil;
  Try
    Try
      Data := GetJSON(PropsJson);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      For I := 0 To Obj.Count - 1 Do
        Begin
          Key := Obj.Names[I];
          Node := Obj.Items[I];
          If Not Assigned(Node) Then
            Continue;
          If Node.JSONType = jtString Then
            Begin
              Val := Node.AsString;
              IsEvent := (Length(Key) >= 2) And (LowerCase(Copy(Key, 1, 2)) = 'on');
              If IsEvent And (EventMethod = '') Then
                EventMethod := Val;
              { Event method names and bare identifiers (clNone, etc.) stay unquoted; captions need quotes. }
              IsIdent := Val <> '';
              For J := 1 To Length(Val) Do
                Begin
                  Ch := Val[J];
                  If Not (Ch In ['A'..'Z', 'a'..'z', '0'..'9', '_']) Then
                    Begin
                      IsIdent := False;
                      Break;
                    End;
                End;
              If IsEvent Or IsIdent Then
                Lines := Lines + '    ' + Key + ' = ' + Val + LineEnding
              Else
                Lines := Lines + '    ' + Key + ' = ''' +
                  StringReplace(Val, '''', '''''', [rfReplaceAll]) + '''' + LineEnding;
            End
          Else If Node.JSONType = jtBoolean Then
            Lines := Lines + '    ' + Key + ' = ' + BoolToStr(Node.AsBoolean, True) + LineEnding
          Else If Node.JSONType = jtNumber Then
            Lines := Lines + '    ' + Key + ' = ' + Node.AsString + LineEnding
          Else
            Lines := Lines + '    ' + Key + ' = ' + Node.AsString + LineEnding;
        End;
      Result := True;
    Except
      Result := False;
    End;
  Finally
    Data.Free;
  End;
End;

Function UpsertLfmComponent(Var LfmBody: String; Const CompName, ClassName, PropLines: String): Boolean;
Var
  Lower, Marker, Block: String;
  StartPos, EndPos, Depth, I, InsertAt: Integer;
  LineStart: Integer;
Begin
  Result := False;
  Lower := LowerCase(LfmBody);
  Marker := 'object ' + LowerCase(CompName) + ':';
  StartPos := Pos(Marker, Lower);
  Block :=
    '  object ' + CompName + ': ' + ClassName + LineEnding +
    PropLines +
    '    Left = 40' + LineEnding +
    '    Top = 40' + LineEnding +
    '  end' + LineEnding;
  { If PropLines already has Left/Top, still OK to have defaults after — LFM last wins? Actually duplicate keys bad.
    Prefer only add Left/Top if not in PropLines. }
  If Pos('left =', LowerCase(PropLines)) > 0 Then
    Block :=
      '  object ' + CompName + ': ' + ClassName + LineEnding +
      PropLines +
      '  end' + LineEnding;
  If StartPos > 0 Then
    Begin
      { Replace existing object block. }
      Depth := 0;
      I := StartPos;
      EndPos := 0;
      While I <= Length(LfmBody) Do
        Begin
          If (I = 1) Or (LfmBody[I - 1] In [#10, #13]) Then
            Begin
              LineStart := I;
              If (LowerCase(Copy(LfmBody, LineStart, 6)) = 'object') Or
                (LowerCase(Copy(LfmBody, LineStart, 8)) = 'inherited') Then
                Inc(Depth)
              Else If (LowerCase(Copy(LfmBody, LineStart, 3)) = 'end') And
                ((LineStart + 3 > Length(LfmBody)) Or (LfmBody[LineStart + 3] In [#10, #13, ' ', #9])) Then
                Begin
                  Dec(Depth);
                  If Depth = 0 Then
                    Begin
                      EndPos := LineStart;
                      While (EndPos <= Length(LfmBody)) And (Not (LfmBody[EndPos] In [#10, #13])) Do
                        Inc(EndPos);
                      While (EndPos <= Length(LfmBody)) And (LfmBody[EndPos] In [#10, #13]) Do
                        Inc(EndPos);
                      Break;
                    End;
                End;
            End;
          Inc(I);
        End;
      If EndPos > StartPos Then
        Begin
          Delete(LfmBody, StartPos, EndPos - StartPos);
          Insert(Block, LfmBody, StartPos);
          Result := True;
          Exit;
        End;
      { Fall through and insert if the existing block could not be bounded. }
    End;
  { Insert before final root "end". }
  InsertAt := Length(LfmBody);
  While (InsertAt > 1) And (LfmBody[InsertAt] In [#10, #13, ' ']) Do
    Dec(InsertAt);
  { Find last standalone end }
  I := InsertAt;
  While I > 1 Do
    Begin
      If (LowerCase(Copy(LfmBody, I, 3)) = 'end') And
        ((I = 1) Or (LfmBody[I - 1] In [#10, #13, ' '])) Then
        Begin
          InsertAt := I;
          Break;
        End;
      Dec(I);
    End;
  Insert(Block, LfmBody, InsertAt);
  Result := True;
End;

Function ToolEnsureFormComponent(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved, PasPath, LfmPath, CompName, ClassName, PropsJson, UsesUnit: String;
  EventMethod, PropLines, DetectedEvent, FormClass: String;
  PasBody, LfmBody, Note: String;
  FromEditor: Boolean;
  ChangedPas, ChangedLfm: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  CompName := Trim(JsonArgString(ArgumentsJson, 'name'));
  ClassName := Trim(JsonArgString(ArgumentsJson, 'class_name'));
  PropsJson := JsonArgString(ArgumentsJson, 'properties');
  EventMethod := Trim(JsonArgString(ArgumentsJson, 'event_method'));
  UsesUnit := Trim(JsonArgString(ArgumentsJson, 'uses_unit'));
  If (Path = '') Or (CompName = '') Or (ClassName = '') Then
    Begin
      ErrorText := 'ensure_form_component requires path, name, and class_name.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  If Not SiblingFormPaths(Resolved, PasPath, LfmPath) Then
    Begin
      ErrorText := 'path must be a form .pas/.pp or .lfm file.';
      Exit;
    End;
  If Not FileExistsUTF8(PasPath) Then
    Begin
      ErrorText := 'Form unit not found: ' + PasPath;
      Exit;
    End;
  If Not FileExistsUTF8(LfmPath) Then
    Begin
      ErrorText := 'Matching .lfm not found: ' + LfmPath +
        ' (create the form in Lazarus first, or write the .lfm with write_file).';
      Exit;
    End;
  If ClassName[1] <> 'T' Then
    ClassName := 'T' + ClassName;
  If UsesUnit = '' Then
    Begin
      If SameText(ClassName, 'TTimer') Or SameText(ClassName, 'TImageList') Then
        UsesUnit := 'ExtCtrls'
      Else If SameText(ClassName, 'TAction') Or SameText(ClassName, 'TActionList') Then
        UsesUnit := 'ActnList';
    End;
  If Not BuildLfmPropertyLines(PropsJson, PropLines, DetectedEvent) Then
    Begin
      ErrorText := 'properties must be a JSON object string when provided.';
      Exit;
    End;
  If EventMethod = '' Then
    EventMethod := DetectedEvent;
  If Not LoadProjectFileText(PasPath, PasBody, FromEditor, ErrorText) Then
    Exit;
  If Not LoadProjectFileText(LfmPath, LfmBody, FromEditor, ErrorText) Then
    Exit;
  FormClass := DetectFormClassName(PasBody);
  ChangedPas := False;
  ChangedLfm := False;
  If UsesUnit <> '' Then
    If EnsureUsesHasUnit(PasBody, UsesUnit) Then
      ChangedPas := True;
  If EnsurePublishedField(PasBody, CompName, ClassName) Then
    ChangedPas := True;
  If EventMethod <> '' Then
    Begin
      If EnsureEventMethodDecl(PasBody, EventMethod) Then
        ChangedPas := True;
      If EnsureEventMethodImpl(PasBody, FormClass, EventMethod) Then
        ChangedPas := True;
    End;
  If UpsertLfmComponent(LfmBody, CompName, ClassName, PropLines) Then
    ChangedLfm := True;
  { Write without opening new tabs; reuse one editor for the form unit if needed. }
  If ChangedPas Then
    If Not SaveProjectFileText(PasPath, PasBody, False, Note, ErrorText) Then
      Exit;
  If ChangedLfm Then
    If Not SaveProjectFileText(LfmPath, LfmBody, False, Note, ErrorText) Then
      Exit;
  If ChangedPas Or ChangedLfm Then
    OpenEditorReuse(PasPath, Note);
  ResultText := Format(
    'ensure_form_component %s: %s (%s). pas_changed=%s lfm_changed=%s form_class=%s event=%s',
    [ProjectRelativePath(PasPath), CompName, ClassName,
     BoolToStr(ChangedPas, True), BoolToStr(ChangedLfm, True), FormClass, EventMethod]);
  If SameText(ClassName, 'TTimer') And (Pos('interval =', LowerCase(PropLines)) > 0) Then
    ResultText := ResultText +
      ' Note: TTimer.Interval is milliseconds (1000 = once per second).';
  If Not ChangedPas And Not ChangedLfm Then
    ResultText := ResultText + ' (already present; LFM block refreshed if found)';
  Result := True;
  WorkflowLogger.Info('AssistantTools', ResultText);
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
  If Not ApproveToolIfNeeded(Name, ArgumentsJson, ErrorText) Then
    Exit;
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
  Else If Name = 'search_in_project' Then
    Result := ToolSearchInProject(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'write_file' Then
    Result := ToolWriteFile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'replace_in_file' Then
    Result := ToolReplaceInFile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'run_compile' Then
    Result := ToolRunCompile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'add_unit_to_project' Then
    Result := ToolAddUnitToProject(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'open_file' Then
    Result := ToolOpenFile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'ensure_form_component' Then
    Result := ToolEnsureFormComponent(ArgumentsJson, ResultText, ErrorText)
  Else
    ErrorText := 'Unknown tool: ' + ToolName;
End;

Initialization

GActivePlanRelative := '';
GLastCompileSeq := 0;
GLastCompileClean := False;

End.
