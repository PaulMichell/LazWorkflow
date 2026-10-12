Unit AssistantTools;

{ Built-in IDE tools for LazAssistantTools: read, Plan Markdown, Build source edit (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. Tool schemas, sandbox checks, and
  dispatch are one IDE tool surface. Reviewed 2026-09-26: read_image stays here
  with the other project-root tools. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantConversation, AssistantImages;

Const
  AssistantToolMaxReadChars = 48000;
  AssistantToolMaxListEntries = 400;
  AssistantToolMaxWriteChars = 400000;
  AssistantToolMaxSearchMatches = 50;
  AssistantToolMaxSearchFiles = 2500;
  AssistantToolMaxSearchMs = 8000;
  AssistantToolMaxSearchFileBytes = 2097152;
  AssistantToolMaxSearchLineChars = 512;
  AssistantToolMaxCompileMs = 600000;

Function BuildAssistantToolsJson: String;
Function BuildAssistantToolsJsonForMode(Mode: TAssistantMode): String;
Function BuildAssistantToolsJsonForSession(Mode: TAssistantMode; AllowSubagents: Boolean): String;
Function ToolAllowedInMode(Const ToolName: String; Mode: TAssistantMode): Boolean;
{ True when the tool must run on the IDE/LCL thread (editors, forms, project API). }
Function ToolNeedsIdeThread(Const ToolName: String): Boolean;
Function ExecuteAssistantToolForMode(Const ToolName, ArgumentsJson: String; Mode: TAssistantMode;
  Out ResultText: String; Out ErrorText: String): Boolean;
Function ExecuteAssistantToolForMode(Const ToolName, ArgumentsJson: String; Mode: TAssistantMode;
  Out ResultText: String; Out ErrorText: String; Out ImageRefs: TAssistantImageRefArray): Boolean;
Function FindLazbuildExecutable: String;
Function ProjectRootPath: String;
Function ResolveProjectPath(Const RelativeOrAbsolute: String; Out Resolved: String;
  Out ErrorText: String): Boolean;
{ Shared, bounded read helpers; these never dispatch arbitrary native tools. }
Function ToolRunGit(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Function ToolReadFile(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Function ToolListDirectory(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Function OpenEditorReuse(Const Resolved: String; Out Note: String): Boolean;
{ Active plan relative path for tools / UI (empty if unset). }
Function GetActivePlanRelativePath: String;
Procedure SetActivePlanRelativePath(Const RelativePath: String);
{ Last run_compile outcome. A clean compile does not close a plan item (seq bumps each run). }
Function AssistantLastCompileSeq: Integer;
Function AssistantLastCompileWasClean: Boolean;
{ Last run_compile text (quiet lazbuild or IDE Messages) for pascal-review children. }
Function AssistantLastCompileLog: String;
{ After add_unit / project-structure tools: save .lpi so disk matches IDE memory. }
Procedure AssistantFlushProjectIfDirty;
{ Suppress "project changed on disk" / file-diff dialogs during a chat send. }
Procedure AssistantBeginQuietIdeSession;
Procedure AssistantEndQuietIdeSession;
{ Restore disk checks even if a send was abandoned without SetSending(False). }
Procedure AssistantResetQuietIdeSession;
{ Bind the worker thread so grep/search abort when that actor is terminated. }
Procedure BindToolAbortThread(Worker: TThread);
Procedure UnbindToolAbortThread;
Function ToolsShouldStop: Boolean;

Implementation

Uses
  Forms, Controls, Dialogs, Process, LazFileUtils, FileUtil, LazIDEIntf, ProjectIntf,
  SrcEditorIntf, IDEMsgIntf, IDEExternToolIntf, CompOptsIntf, WorkflowLog, RegExpr,
  AssistantHarness, AssistantSkills, AssistantMarkdownForm, AssistantPlan, AssistantProtocol, AssistantConfig,
  AssistantLfm, AssistantWorkTarget, AssistantProjectPaths, PackageIntf, IDEOptionsIntf,
  AssistantSearchUtil, AssistantEditorEdits, AssistantGit, AssistantTestSettings, AssistantConnections,
  AssistantGeneratedImage, AssistantImageAdapters, fpjson, jsonparser;

Var
  GActivePlanRelative: String;
  GAssistantToolMode: TAssistantMode;
  GLastCompileSeq: Integer;
  GLastCompileClean: Boolean;
  GLastCompileLog: String;
  GProjectStructureDirty: Boolean;
  GQuietIdeDepth: Integer;
  GSavedCheckFilesOnDisk: Boolean;

Function QuietSaveTargetForGit(Out ErrorText: String): Boolean; Forward;

ThreadVar
  GToolAbortThread: TThread;

Type
  { Access TThread.Terminated, which is protected on FPC. }
  TToolAbortThread = Class(TThread)
  Public
    Function StopRequested: Boolean;
  End;

Function TToolAbortThread.StopRequested: Boolean;
Begin
  Result := Terminated;
End;

Procedure BindToolAbortThread(Worker: TThread);
Begin
  GToolAbortThread := Worker;
End;

Procedure UnbindToolAbortThread;
Begin
  GToolAbortThread := Nil;
End;

Function ToolsShouldStop: Boolean;
Begin
  Result := Assigned(GToolAbortThread) And TToolAbortThread(GToolAbortThread).StopRequested;
End;

Function ExpandResolvedPath(Const Path: String): String; Forward;
Function SymlinkLeavesProject(Const Resolved: String): Boolean; Forward;
Function FindOpenEditor(Const Resolved: String): TSourceEditorInterface; Forward;

Procedure MarkProjectStructureDirty;
Begin
  GProjectStructureDirty := True;
End;

Procedure AssistantFlushProjectIfDirty;
Begin
  If Not GProjectStructureDirty Then
    Exit;
  If Not Assigned(LazarusIDE) Or Not Assigned(LazarusIDE.ActiveProject) Then
    Begin
      GProjectStructureDirty := False;
      Exit;
    End;
  Try
    { Write in-memory project (.lpi) so external tools and disk checks stay aligned. }
    LazarusIDE.DoSaveProject([sfQuietUnitCheck]);
    WorkflowLogger.Info('AssistantTools', 'Saved project after structure change');
  Except
    On E: Exception Do
      WorkflowLogger.Warning('AssistantTools', 'DoSaveProject after structure change: ' + E.Message);
  End;
  GProjectStructureDirty := False;
End;

Procedure AssistantBeginQuietIdeSession;
Begin
  If Not Assigned(LazarusIDE) Then
    Exit;
  If GQuietIdeDepth = 0 Then
    Begin
      GSavedCheckFilesOnDisk := LazarusIDE.CheckFilesOnDiskEnabled;
      LazarusIDE.CheckFilesOnDiskEnabled := False;
      WorkflowLogger.Info('AssistantTools', 'IDE disk checks disabled for assistant send');
    End;
  Inc(GQuietIdeDepth);
End;

Procedure AssistantEndQuietIdeSession;
Begin
  If Not Assigned(LazarusIDE) Then
    Begin
      GQuietIdeDepth := 0;
      Exit;
    End;
  If GQuietIdeDepth <= 0 Then
    Exit;
  Dec(GQuietIdeDepth);
  If GQuietIdeDepth = 0 Then
    Begin
      AssistantFlushProjectIfDirty;
      LazarusIDE.CheckFilesOnDiskEnabled := GSavedCheckFilesOnDisk;
      WorkflowLogger.Info('AssistantTools', 'IDE disk checks restored');
    End;
End;

Procedure AssistantResetQuietIdeSession;
Begin
  If GQuietIdeDepth <= 0 Then
    Exit;
  GQuietIdeDepth := 1;
  AssistantEndQuietIdeSession;
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

Function AssistantLastCompileLog: String;
Begin
  Result := GLastCompileLog;
End;

Function ToolIsReadOnly(Const ToolName: String): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(ToolName));
  Result := (Name = 'read_file') Or (Name = 'read_image') Or (Name = 'list_directory') Or
    (Name = 'open_markdown') Or (Name = 'get_project_info') Or
    (Name = 'list_plans') Or (Name = 'get_active_plan') Or
    (Name = 'search_in_project') Or (Name = 'open_file') Or
    (Name = 'grep') Or (Name = 'read_skill') Or (Name = 'spawn_subagent');
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
  Mode := aamAsk;
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

Function ToolNeedsIdeThread(Const ToolName: String): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(ToolName));
  { Editors, forms, project API, compile, Markdown windows, and Ask-mode MessageDlg.
    read_file must see the open buffer; disk-only reads made replace_in_file miss. }
  Result := (Name = 'open_file') Or (Name = 'open_markdown') Or
    (Name = 'add_unit_to_project') Or (Name = 'ensure_form_component') Or
    (Name = 'write_file') Or (Name = 'replace_in_file') Or
    (Name = 'write_markdown') Or (Name = 'update_markdown') Or
    (Name = 'get_project_info') Or (Name = 'run_compile') Or (Name = 'run_git') Or
    (Name = 'run_project') Or (Name = 'run_tests') Or
    (Name = 'delete_path') Or (Name = 'rename_path') Or
    (Name = 'set_active_plan') Or (Name = 'read_file');
End;

Function ToolAllowedInMode(Const ToolName: String; Mode: TAssistantMode): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(ToolName));
  { Shared read tools for all project modes. }
  If (Name = 'read_file') Or (Name = 'read_image') Or (Name = 'list_directory') Or
    (Name = 'open_markdown') Or (Name = 'get_project_info') Or
    (Name = 'grep') Or (Name = 'read_skill') Or (Name = 'spawn_subagent') Then
    Begin
      Result := Mode In [amInspect, amDocument, amPlan, amBuild];
      Exit;
    End;
  { Document, Plan, and Build may write Markdown. Plan registry tools stay off Document. }
  If (Name = 'write_markdown') Or (Name = 'update_markdown') Then
    Begin
      Result := Mode In [amDocument, amPlan, amBuild];
      Exit;
    End;
  { Plan workspace tools — Plan and Build (Build uses them for Status: updates). }
  If (Name = 'list_plans') Or (Name = 'set_active_plan') Or
    (Name = 'get_active_plan') Or (Name = 'todo_write') Then
    Begin
      Result := Mode In [amPlan, amBuild];
      Exit;
    End;
  { Open and search are read-only. Document may use them before writing a report. }
  If (Name = 'search_in_project') Or (Name = 'open_file') Then
    Begin
      Result := Mode In [amInspect, amDocument, amBuild];
      Exit;
    End;
  { Build-mode source tools — never Inspect or Plan. }
  If (Name = 'write_file') Or (Name = 'replace_in_file') Or
    (Name = 'run_compile') Or (Name = 'run_git') Or
    (Name = 'run_project') Or (Name = 'run_tests') Or
    (Name = 'delete_path') Or (Name = 'rename_path') Or
    (Name = 'add_unit_to_project') Or
    (Name = 'ensure_form_component') Then
    Begin
      Result := Mode = amBuild;
      Exit;
    End;
  If Name = 'write_image' Then
    Begin
      Result := AssistantTurnOffersImageOutput(Mode);
      Exit;
    End;
  Result := False;
End;

Function BuildHarnessToolsJson: String;
Begin
  Result :=
    '{"type":"function","function":{' +
      '"name":"read_skill",' +
      '"description":"Load the full body of a catalogued SKILL.md by name. ' +
        'Search <working-root>/.assistant/skills, then ~/.grok/skills.",' +
      '"parameters":{"type":"object","properties":{' +
        '"name":{"type":"string","description":"Skill directory name, e.g. free-pascal-engineer"}' +
      '},"required":["name"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"grep",' +
      '"description":"Search project text files; return path:line:text. Prefer before many read_file calls. ' +
        'path may be a directory or a single file. glob accepts .pas, *.pas, and *.{pas,lfm}. ' +
        'A pattern containing | is treated as a regular expression.",' +
      '"parameters":{"type":"object","properties":{' +
        '"pattern":{"type":"string","description":"Text or regex to find"},' +
        '"query":{"type":"string","description":"Alias of pattern"},' +
        '"path":{"type":"string","description":"Project-relative directory or file (empty = project root)"},' +
        '"glob":{"type":"string","description":"Optional filter: .pas, *.pas, or *.{pas,lfm,sql}"},' +
        '"regex":{"type":"boolean","description":"Treat pattern as a regular expression (default false; auto if pattern contains |)"},' +
        '"max_matches":{"type":"integer","description":"Max matches to return (default 50)"}' +
      '},"required":[]}' +
    '}}';
End;

Function BuildSpawnToolJson: String;
Begin
  Result :=
    '{"type":"function","function":{' +
      '"name":"spawn_subagent",' +
      '"description":"Start a depth-1 child agent and wait for its summary. Parent only; a child cannot spawn. ' +
        'At most 3 children run at once; extra spawn_subagent calls wait for a free slot. ' +
        'Kinds: explore (read-only research), plan (Markdown only), general-purpose ' +
        '(parent mode tools), pascal-naming, pascal-structure, pascal-review (read-only lenses). ' +
        'Use for parallel explore or Review lenses. Do not spawn for syntax (use run_compile) or every edit.",' +
      '"parameters":{"type":"object","properties":{' +
        '"kind":{"type":"string","description":"explore | plan | general-purpose | pascal-naming | pascal-structure | pascal-review"},' +
        '"subagent_type":{"type":"string","description":"Alias of kind"},' +
        '"title":{"type":"string","description":"Short label shown in the parent trace"},' +
        '"description":{"type":"string","description":"Alias of title"},' +
        '"prompt":{"type":"string","description":"Full instructions for the child"},' +
        '"files":{"type":"string","description":"Optional changed-file list the child should focus on"}' +
      '},"required":["prompt"]}' +
    '}}';
End;

Function BuildTodoToolJson: String;
Begin
  Result :=
    '{"type":"function","function":{' +
      '"name":"todo_write",' +
      '"description":"Replace or merge the ephemeral in-turn todo list (dies with the turn; not plan Status:). ' +
        'status: pending, in_progress, completed, cancelled.",' +
      '"parameters":{"type":"object","properties":{' +
        '"merge":{"type":"boolean","description":"If true, upsert by id; if false, replace the list (default false)"},' +
        '"todos":{"type":"array","description":"Todo items","items":{"type":"object","properties":{' +
          '"id":{"type":"string"},' +
          '"content":{"type":"string"},' +
          '"status":{"type":"string"}' +
        '}}}' +
      '},"required":["todos"]}' +
    '}}';
End;

Function BuildReadToolsJson: String;
Begin
  Result :=
    BuildHarnessToolsJson + ',' +
    '{"type":"function","function":{' +
      '"name":"read_file",' +
      '"description":"Read a text file under the active Lazarus project. Uses the open editor buffer when ' +
        'the file is open, otherwise disk. Page with start_line plus end_line or limit. If end_line is ' +
        'smaller than start_line it is a line count. After truncation continue from the suggested line.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative or absolute file path"},' +
        '"start_line":{"type":"integer","description":"1-based first line to include (default 1)"},' +
        '"offset":{"type":"integer","description":"Alias of start_line"},' +
        '"end_line":{"type":"integer","description":"1-based last line, or a line count if smaller than start_line"},' +
        '"limit":{"type":"integer","description":"Max lines from start_line (preferred when paging by count)"},' +
        '"max_chars":{"type":"integer","description":"Optional max characters to return from the selected range"}' +
      '},"required":["path"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"read_image",' +
      '"description":"Read a project image into the next model turn. Resolves a project-relative path in the ' +
        'sandbox, refuses paths outside the root, symbolic links that leave the project, and files over the image ' +
        'limits, then copies the accepted still image into the conversation store. The result text is the name, ' +
        'dimensions, and id only. The picture is attached to the following user message, not written into the ' +
        'result. A PNG is not a text edit: do not use write_file or replace_in_file on images.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative or absolute image path inside the project root"}' +
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
    BuildTodoToolJson + ',' +
    '{"type":"function","function":{' +
      '"name":"write_markdown",' +
      '"description":"Create or overwrite a Markdown file under the project (prefer Documents/). Opens a live Markdown window. Use for new or full rewrites of plans. Rejects a Status: line under a ## heading. A ### heading without Status is a note, not a todo. In a Git repository, Status: complete is refused until run_git commit has succeeded in this turn; commit the plan file after that change. Without a repository, complete needs no commit.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative .md path (default Documents/Plan.md)"},' +
        '"content":{"type":"string","description":"Full Markdown body to write"},' +
        '"open":{"type":"boolean","description":"Open live viewer after write (default true). Ignored during a plan run."}' +
      '},"required":["content"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"update_markdown",' +
      '"description":"Exact text replacement in a project Markdown file (surgical edit). Prefer this over rewrite when changing Status: lines or a single section. Rejects a Status: line under a ## heading. A ### heading without Status stays a note, not a todo. In a Git repository, Status: complete is refused until run_git commit has succeeded in this turn; commit the plan file after that change. Without a repository, complete needs no commit.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative .md path (default: active plan)"},' +
        '"old_text":{"type":"string","description":"Exact text to find"},' +
        '"new_text":{"type":"string","description":"Replacement text"},' +
        '"replace_all":{"type":"boolean","description":"Replace every match (default false)"},' +
        '"open":{"type":"boolean","description":"Open live viewer after update (default true). Ignored during a plan run."}' +
      '},"required":["old_text","new_text"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"list_plans",' +
      '"description":"List plans registered in the project .assistant settings. Missing files are dropped. The project folders are not scanned.",' +
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

Function BuildNavigationToolsJson: String;
Begin
  Result :=
    '{"type":"function","function":{' +
      '"name":"search_in_project",' +
      '"description":"Search project source/text files (same engine as grep). ' +
        'Inspect and Build may call it. Returns path:line:text.",' +
      '"parameters":{"type":"object","properties":{' +
        '"query":{"type":"string","description":"Text to find"},' +
        '"path":{"type":"string","description":"Project-relative directory or file (empty = project root)"},' +
        '"glob":{"type":"string","description":"Optional filter: .pas, *.pas, or *.{pas,lfm} (default: common text types)"},' +
        '"max_matches":{"type":"integer","description":"Max matches to return (default 50)"}' +
      '},"required":["query"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"open_file",' +
      '"description":"Open a project source file in the Lazarus source editor. Does not modify the file.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative file path"}' +
      '},"required":["path"]}' +
    '}}';
End;

Function BuildSourceToolsJson: String;
Begin
  Result :=
    '{"type":"function","function":{' +
      '"name":"write_file",' +
      '"description":"Create or overwrite a real project file. Never create empty files or ApiProbe/scratch/temp units — use search_in_project, list_directory, and read_file to discover APIs. Prefer replace_in_file for small edits.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative path e.g. Source/Foo.pas"},' +
        '"content":{"type":"string","description":"Full non-empty contents (reject empty/probe files)"},' +
        '"open":{"type":"boolean","description":"After write, open a source tab (default false). A Markdown path opens in the Assistant Markdown viewer instead. Use open_markdown."},' +
        '"add_to_project":{"type":"boolean","description":"Add Pascal unit to the active project (default true only for non-empty units)"}' +
      '},"required":["path","content"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"replace_in_file",' +
      '"description":"Exact text replacement in a project source/text file. old_text must match the open ' +
        'editor buffer when the file is open (same source as read_file), including whitespace; keep it small ' +
        'and unique. Saves the buffer to disk so Review/Git see the edit.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative file path"},' +
        '"old_text":{"type":"string","description":"Exact text to find"},' +
        '"new_text":{"type":"string","description":"Replacement text"},' +
        '"replace_all":{"type":"boolean","description":"Replace every match (default false)"},' +
        '"open":{"type":"boolean","description":"After the edit, open a source tab (default false). A Markdown path opens in the Assistant Markdown viewer instead. Use open_markdown."}' +
      '},"required":["path","old_text","new_text"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"run_compile",' +
      '"description":"Compile the work target. A project or package uses that manifest. ' +
        'A folder compiles every .lpk under the folder, or every .lpi when the folder has no package. ' +
        'It does not compile the IDE active project. Default is quiet lazbuild. ' +
        'Set ui=true only for a final IDE Messages check of a project or package.",' +
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

Function BuildRunToolsJson: String;
Begin
  Result :=
    '{"type":"function","function":{' +
      '"name":"run_project",' +
      '"description":"Start the active project executable directly. No shell and no debugger. ' +
        'The executable must already be built and must stay inside the project root.",' +
      '"parameters":{"type":"object","properties":{},"required":[]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"run_tests",' +
      '"description":"Run the enabled test command for this target. Arguments are passed directly, not through a shell. ' +
        'The executable and working directory must stay inside the project root.",' +
      '"parameters":{"type":"object","properties":{},"required":[]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"delete_path",' +
      '"description":"Delete one file, symbolic link, or empty directory inside the project root. ' +
        'Refuses the project root, Git metadata, and the project or package file. Does not use a shell.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative or absolute path inside the project root"}' +
      '},"required":["path"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"rename_path",' +
      '"description":"Rename or move a file or directory inside the project root. Both paths must stay in the project. ' +
        'Refuses the project root, Git metadata, and the project or package file. Does not use a shell.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Existing project path"},' +
        '"new_path":{"type":"string","description":"New path inside the project root"}' +
      '},"required":["path","new_path"]}' +
    '}}';
End;

Function BuildWriteImageToolJson: String;
Var
  Fields, Required: String;
Begin
  If ActiveProfileImageDelivery = aidToolPrompt Then
    Begin
      Fields :=
        '"prompt":{"type":"string","description":"What this same model should draw."},' +
        '"size":{"type":"string","description":"Optional pixel size."}';
      Required := '["path","prompt"]';
    End
  Else
    Begin
      Fields :=
        '"image_id":{"type":"string","description":"Turn-local image id. Optional when the turn has exactly one image."}';
      Required := '["path"]';
    End;
  Result :=
    '{"type":"function","function":{' +
      '"name":"write_image",' +
      '"description":"Save a still image into the project. Do not use write_file or replace_in_file for images.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative path."},' +
        '"overwrite":{"type":"boolean","description":"Replace an existing file. Default false."},' +
        Fields +
      '},"required":' + Required + '}}}';
End;

Function BuildDocumentToolsJson: String;
Begin
  Result :=
    '{"type":"function","function":{' +
      '"name":"write_markdown",' +
      '"description":"Create or overwrite a free-form Markdown document under the project (prefer Documents/). ' +
        'Opens a live Markdown window. The user prompt decides the layout. Do not use the assistant plan format, ' +
        'the plan identity line, or Status lines. Do not write the active plan. Omit path to use the current document, ' +
        'or a new Documents/Report file when none exists.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative .md path. Omit for the current document."},' +
        '"content":{"type":"string","description":"Full Markdown body to write"},' +
        '"open":{"type":"boolean","description":"Open live viewer after write (default true)."}' +
      '},"required":["content"]}' +
    '}},' +
    '{"type":"function","function":{' +
      '"name":"update_markdown",' +
      '"description":"Exact text replacement in the current Markdown document, or in path when given. ' +
        'Prefer this for a section change. Do not use it on the active plan. Free format; no Status lines required.",' +
      '"parameters":{"type":"object","properties":{' +
        '"path":{"type":"string","description":"Project-relative .md path. Omit for the current document."},' +
        '"old_text":{"type":"string","description":"Exact text to find"},' +
        '"new_text":{"type":"string","description":"Replacement text"},' +
        '"replace_all":{"type":"boolean","description":"Replace every match (default false)"},' +
        '"open":{"type":"boolean","description":"Open live viewer after update (default true)."}' +
      '},"required":["old_text","new_text"]}' +
    '}}';
End;

Function BuildAssistantToolsJsonForSession(Mode: TAssistantMode; AllowSubagents: Boolean): String;
Var
  Body: String;
Begin
  Case Mode Of
    amChat:
      Begin
        Result := '';
        Exit;
      End;
    amDocument:
      Body := BuildReadToolsJson + ',' + BuildNavigationToolsJson + ',' + BuildDocumentToolsJson;
    amPlan:
      Body := BuildReadToolsJson + ',' + BuildPlanToolsJson;
    amBuild:
      Begin
        Body := BuildReadToolsJson + ',' + BuildPlanToolsJson + ',' + BuildNavigationToolsJson + ',' +
          BuildSourceToolsJson + ',' + BuildRunToolsJson +
          ',{"type":"function","function":{"name":"run_git","description":' +
          '"' + JsonEscapeText(AssistantGitDescription) + '"' + ',"parameters":' + AssistantGitSchema + '}}';
        If AssistantTurnOffersImageOutput(amBuild) Then
          Body := Body + ',' + BuildWriteImageToolJson;
      End;
    amInspect:
      Body := BuildReadToolsJson + ',' + BuildNavigationToolsJson;
  Else
    Body := '';
  End;
  If Body = '' Then
    Begin
      Result := '';
      Exit;
    End;
  If AllowSubagents Then
    Body := Body + ',' + BuildSpawnToolJson;
  Result := '[' + Body + ']';
End;

Function BuildAssistantToolsJson: String;
Begin
  Result := BuildAssistantToolsJsonForSession(amInspect, False);
End;

Function BuildAssistantToolsJsonForMode(Mode: TAssistantMode): String;
Begin
  Result := BuildAssistantToolsJsonForSession(Mode, True);
End;

Function ProjectRootPath: String;
Begin
  Result := ProjectAssistantRoot;
End;

Function IsPathUnderRoot(Const Root, Candidate: String): Boolean;
Var
  LexRoot, LexCand, Probe, PhysRoot, PhysCand: String;
Begin
  Result := False;
  LexRoot := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  LexCand := ExpandFileName(Candidate);
  If (LexCand = '') Or ((CompareFilenames(Copy(LexCand, 1, Length(LexRoot)), LexRoot) <> 0) And
     (CompareFilenames(ExcludeTrailingPathDelimiter(LexCand), ExcludeTrailingPathDelimiter(LexRoot)) <> 0)) Then
    Exit;
  PhysRoot := GetPhysicalFilename(ExcludeTrailingPathDelimiter(LexRoot), pfeOriginal);
  If PhysRoot = '' Then
    PhysRoot := ExcludeTrailingPathDelimiter(LexRoot);
  PhysRoot := IncludeTrailingPathDelimiter(ExpandFileName(PhysRoot));
  Probe := LexCand;
  While (Probe <> '') And (Not FileExistsUTF8(Probe)) And (Not DirectoryExistsUTF8(Probe)) Do
    Begin
      If ExtractFileDir(Probe) = Probe Then
        Break;
      Probe := ExcludeTrailingPathDelimiter(ExtractFileDir(Probe));
    End;
  If (Not FileExistsUTF8(Probe)) And (Not DirectoryExistsUTF8(Probe)) Then
    Begin
      Result := True;
      Exit;
    End;
  PhysCand := GetPhysicalFilename(Probe, pfeEmpty);
  If PhysCand = '' Then
    Exit;
  PhysCand := ExpandFileName(PhysCand);
  Result := (CompareFilenames(Copy(PhysCand, 1, Length(PhysRoot)), PhysRoot) = 0) Or
    (CompareFilenames(ExcludeTrailingPathDelimiter(PhysCand), ExcludeTrailingPathDelimiter(PhysRoot)) = 0);
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
  If Not AssistantTarget.Available Or (Root = '') Then
    Begin
      ErrorText := 'No available Assistant work target.';
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

Function ToolRunGit(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var Data, Args: TJSONData; I: Integer; Editor: TSourceEditorInterface; Root, Command, CheckReply, Staged, StagedPath: String; CheckData:TJSONData; StartPos,EndPos:Integer;
  Function CanStage(Const RelativePath:String):Boolean;
  Var FullPath:String;
  Begin
    FullPath := ExpandFileName(IncludeTrailingPathDelimiter(Root) + RelativePath);
    Result := AssistantTarget.AllowsWrite(FullPath) Or
      (CompareFilenames(FullPath,AssistantTarget.Manifest)=0);
  End;
Begin
  Result := False; ResultText := ''; ErrorText := ''; Root := ProjectRootPath;
  If Not AssistantTarget.Available Then
    Begin
      ErrorText := 'No available Assistant work target.';
      Exit;
    End;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ArgumentsJson); Command := '';
      If Data Is TJSONObject Then
        Begin
          Args := TJSONObject(Data).Find('arguments');
          If (Args Is TJSONArray) And (Args.Count > 0) Then Command := Args.Items[0].AsString;
        End;
      If (AssistantTarget.Kind=atkPackage) And (Command='add') And (Args Is TJSONArray) Then
        For I := 2 To Args.Count - 1 Do If Not CanStage(Args.Items[I].AsString) Then
          Begin
            ErrorText := AssistantTarget.ScopeRefusal('stage', Args.Items[I].AsString);
            Exit;
          End;
      If (AssistantTarget.Kind=atkPackage) And (Command='commit') And (Args Is TJSONArray) Then
        Begin
          { commit -- path records the work tree, so the cached diff cannot see it. }
          I := 1;
          While (I < Args.Count) And (Args.Items[I].AsString <> '--') Do
            Inc(I);
          Inc(I);
          While I < Args.Count Do
            Begin
              If Not CanStage(Args.Items[I].AsString) Then
                Begin
                  ErrorText := AssistantTarget.ScopeRefusal('commit', Args.Items[I].AsString);
                  Exit;
                End;
              Inc(I);
            End;
          If Not RunAssistantGit(Root,'{"arguments":["diff","--cached","--no-renames","--name-only","-z"]}',CheckReply,ErrorText) Then Exit;
          CheckData := GetJSON(CheckReply);
          Try
            If TJSONObject(CheckData).Get('truncated',True) Then
              Begin
                ErrorText := 'Staged path list is too large to verify package scope.';
                Exit;
              End;
            Staged := TJSONObject(CheckData).Get('output', ''); StartPos := 1;
            While StartPos<=Length(Staged) Do
              Begin
                EndPos := StartPos; While (EndPos <= Length(Staged)) And (Staged[EndPos] <> #0) Do Inc(EndPos);
                StagedPath := Copy(Staged, StartPos, EndPos - StartPos); StartPos := EndPos + 1;
                If Not CanStage(StagedPath) Then
                  Begin
                    ErrorText := AssistantTarget.ScopeRefusal('commit', StagedPath);
                    Exit;
                  End;
              End;
          Finally CheckData.Free;End;
        End;
      If (Command = 'add') Or (Command = 'commit') Then
        Begin
          If Not QuietSaveTargetForGit(ErrorText) Then
            Exit;
          If Assigned(SourceEditorManagerIntf) Then
            For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
              Begin
                Editor := SourceEditorManagerIntf.SourceEditors[I];
                If Assigned(Editor) And (Editor.Modified Or Editor.ModifiedDesign) And
                  ((Editor.FileName = '') Or IsPathUnderRoot(Root, Editor.FileName)) And
                  ((AssistantTarget.Kind=atkProject) Or AssistantTarget.ContainsFile(Editor.FileName)) Then
                  Begin
                    ErrorText := 'Save ' + Editor.FileName +
                      ' before staging or committing. Git reads the saved file, and this editor still has unsaved changes.';
                    Exit;
                  End;
              End;
        End;
      Result := RunAssistantGit(Root, ArgumentsJson, ResultText, ErrorText);
    Except On E: Exception Do ErrorText := E.Message; End;
  Finally Data.Free; End;
End;

Function ToolReadFile(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Const
  ReadBufSize = 65536;
Var
  Path, Resolved, Chunk, Carry: String;
  MaxChars, StartLine, EndLine, LineLimit, LineNo, FirstOut, LastOut, FileBytes: Integer;
  Stream: TFileStream;
  Buf: Array[0..ReadBufSize - 1] Of Byte;
  BytesRead, I: Integer;
  Truncated, HitEndLine, PendingCR: Boolean;
  RequestedEnd: Integer;
  Ed: TSourceEditorInterface;

  Function RemainingBudget: Integer;
  Begin
    Result := MaxChars - Length(Chunk);
    If Length(Chunk) > 0 Then
      Dec(Result);
    If Result < 0 Then
      Result := 0;
  End;

  Procedure EmitLine(Const LineText: String);
  Var
    Remain: Integer;
  Begin
    Inc(LineNo);
    If LineNo < StartLine Then
      Exit;
    If (EndLine > 0) And (LineNo > EndLine) Then
      Begin
        HitEndLine := True;
        Exit;
      End;
    Remain := RemainingBudget;
    If Remain < 1 Then
      Begin
        Truncated := True;
        Exit;
      End;
    If Length(Chunk) > 0 Then
      Chunk := Chunk + LineEnding;
    If Length(LineText) > Remain Then
      Begin
        Chunk := Chunk + Copy(LineText, 1, Remain);
        Truncated := True;
      End
    Else
      Chunk := Chunk + LineText;
    LastOut := LineNo;
    If Length(Chunk) >= MaxChars Then
      Truncated := True;
  End;

  Procedure FinishLine;
  Begin
    EmitLine(Carry);
    Carry := '';
  End;

  Procedure AppendCarryChar(C: Char);
  Var
    Remain: Integer;
  Begin
    If (LineNo + 1) < StartLine Then
      Exit;
    If (EndLine > 0) And (LineNo + 1 > EndLine) Then
      Exit;
    Remain := RemainingBudget;
    If Remain < 1 Then
      Begin
        Truncated := True;
        Exit;
      End;
    If Length(Carry) >= Remain Then
      Begin
        EmitLine(Copy(Carry, 1, Remain));
        Carry := '';
        Truncated := True;
        Exit;
      End;
    Carry := Carry + C;
  End;

  Procedure PageString(Const SourceText: String);
  Var
    Idx, StartAt: Integer;
    C: Char;
  Begin
    LineNo := 0;
    Truncated := False;
    HitEndLine := False;
    Chunk := '';
    FirstOut := StartLine;
    LastOut := StartLine - 1;
    StartAt := 1;
    Idx := 1;
    While Idx <= Length(SourceText) Do
      Begin
        C := SourceText[Idx];
        If C = #13 Then
          Begin
            EmitLine(Copy(SourceText, StartAt, Idx - StartAt));
            If (Idx < Length(SourceText)) And (SourceText[Idx + 1] = #10) Then
              Inc(Idx);
            StartAt := Idx + 1;
            If Truncated Or HitEndLine Then
              Break;
          End
        Else If C = #10 Then
          Begin
            EmitLine(Copy(SourceText, StartAt, Idx - StartAt));
            StartAt := Idx + 1;
            If Truncated Or HitEndLine Then
              Break;
          End;
        Inc(Idx);
      End;
    If (Not Truncated) And (Not HitEndLine) And (StartAt <= Length(SourceText)) Then
      EmitLine(Copy(SourceText, StartAt, MaxInt));
  End;

  Procedure FinishPagedResult(Const SourceLabel: String);
  Begin
    If LineNo < 1 Then
      Begin
        ResultText := Format('File: %s (empty, 0 lines)%s', [Resolved, SourceLabel]);
        Result := True;
        Exit;
      End;
    If StartLine > LineNo Then
      Begin
        ErrorText := Format('start_line %d is past end of file (%d lines): %s',
          [StartLine, LineNo, Resolved]);
        Exit;
      End;
    If RequestedEnd < 1 Then
      RequestedEnd := LastOut;
    If Truncated Or HitEndLine Then
      ResultText :=
        Format('File: %s (%d bytes)%s; lines %d–%d of requested %d–%d',
          [Resolved, FileBytes, SourceLabel, FirstOut, LastOut, StartLine, RequestedEnd])
    Else
      ResultText :=
        Format('File: %s (%d lines total)%s; lines %d–%d of requested %d–%d',
          [Resolved, LineNo, SourceLabel, FirstOut, LastOut, StartLine, RequestedEnd]);
    ResultText := ResultText + LineEnding + Chunk;
    If Truncated Or ((RequestedEnd > 0) And (LastOut < RequestedEnd) And (Not HitEndLine)) Then
      ResultText := ResultText + LineEnding + Format(
        '[… truncated. Continue with start_line=%d (same path). Do not re-read from line 1. …]',
        [LastOut + 1]);
    Result := True;
  End;

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
  MaxChars := JsonArgInt(ArgumentsJson, 'max_chars', AssistantToolMaxReadChars);
  If MaxChars < 1 Then
    MaxChars := AssistantToolMaxReadChars;
  If MaxChars > AssistantToolMaxReadChars Then
    MaxChars := AssistantToolMaxReadChars;
  StartLine := JsonArgInt(ArgumentsJson, 'start_line', 0);
  If StartLine < 1 Then
    StartLine := JsonArgInt(ArgumentsJson, 'offset', 1);
  EndLine := JsonArgInt(ArgumentsJson, 'end_line', 0);
  LineLimit := JsonArgInt(ArgumentsJson, 'limit', 0);
  ResolveReadLineRange(StartLine, EndLine, LineLimit);
  RequestedEnd := EndLine;
  Ed := FindOpenEditor(ExpandResolvedPath(Resolved));
  If Assigned(Ed) Then
    Begin
      FileBytes := Length(Ed.SourceText);
      PageString(Ed.SourceText);
      FinishPagedResult(' (open editor buffer)');
      Exit;
    End;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'File not found: ' + Resolved;
      Exit;
    End;
  Stream := Nil;
  Try
    Try
      Stream := TFileStream.Create(Resolved, fmOpenRead Or fmShareDenyNone);
      FillChar(Buf, SizeOf(Buf), 0);
      FileBytes := Stream.Size;
      If FileBytes < 1 Then
        Begin
          ResultText := Format('File: %s (empty, 0 lines)', [Resolved]);
          Result := True;
          Exit;
        End;
      Chunk := '';
      Carry := '';
      LineNo := 0;
      Truncated := False;
      HitEndLine := False;
      PendingCR := False;
      FirstOut := StartLine;
      LastOut := StartLine - 1;
      Repeat
        BytesRead := Stream.Read(Buf, SizeOf(Buf));
        If BytesRead < 1 Then
          Break;
        I := 0;
        While I < BytesRead Do
          Begin
            If PendingCR Then
              Begin
                PendingCR := False;
                If Buf[I] = 10 Then
                  Begin
                    FinishLine;
                    Inc(I);
                    If Truncated Or HitEndLine Then
                      Break;
                    Continue;
                  End;
                FinishLine;
                If Truncated Or HitEndLine Then
                  Break;
              End;
            If Buf[I] = 13 Then
              Begin
                If I = BytesRead - 1 Then
                  Begin
                    PendingCR := True;
                    Inc(I);
                  End
                Else If Buf[I + 1] = 10 Then
                  Begin
                    FinishLine;
                    Inc(I, 2);
                  End
                Else
                  Begin
                    FinishLine;
                    Inc(I);
                  End;
              End
            Else If Buf[I] = 10 Then
              Begin
                FinishLine;
                Inc(I);
              End
            Else
              Begin
                AppendCarryChar(Char(Buf[I]));
                Inc(I);
              End;
            If Truncated Or HitEndLine Then
              Break;
          End;
        If Truncated Or HitEndLine Then
          Break;
      Until BytesRead < SizeOf(Buf);
      If PendingCR And (Not Truncated) And (Not HitEndLine) Then
        FinishLine;
      If (Not Truncated) And (Not HitEndLine) And (Carry <> '') Then
        FinishLine;
      FinishPagedResult('');
    Except
      On E: Exception Do
        ErrorText := E.Message;
    End;
  Finally
    Stream.Free;
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
  If AssistantPlanViewerQuiet Then
    Begin
      If Assigned(FindMarkdownDocument(Resolved)) Then
        ReloadMarkdownDocument(Resolved, False, False);
      ResultText := 'Plan run in progress. The Markdown viewer was not opened. The plan summary updates from the file.';
      Result := True;
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
Begin
  Result := AssistantTarget.Available; ErrorText := ''; ResultText := '';
  If Not Result Then
    Begin
      ErrorText := 'No available Assistant work target.';
      Exit;
    End;
  ResultText := AssistantTarget.Describe;
  If GetActivePlanRelativePath <> '' Then ResultText := ResultText + LineEnding + 'Active plan: ' + GetActivePlanRelativePath;
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

Function NormalSlashPath(Const Path: String): String;
Begin
  Result := StringReplace(Trim(Path), '\', '/', [rfReplaceAll]);
End;

Function IsActivePlanPath(Const Path: String): Boolean;
Var
  Active: String;
Begin
  Active := NormalSlashPath(GetActivePlanRelativePath);
  Result := (Active <> '') And SameText(NormalSlashPath(Path), Active);
End;

Function ToolWriteMarkdown(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Content, Resolved, OldPlan, WrittenRel: String;
  OpenAfter, ShowThinking: Boolean;
  Mode: TAssistantMode;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Path := JsonArgString(ArgumentsJson, 'path');
  If GAssistantToolMode = amDocument Then
    Begin
      If Path = '' Then
        Path := GetDocumentRelativePath;
      If Path = '' Then
        Path := NewDocumentRelativePath;
      If IsActivePlanPath(Path) Then
        Begin
          ErrorText := 'Document mode will not write the active plan. Switch to Plan mode, or choose another path.';
          Exit;
        End;
    End
  Else
    Begin
      If Path = '' Then
        Path := GetActivePlanRelativePath;
      If Path = '' Then
        Path := DefaultPlanRelativePath;
    End;
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
  WrittenRel := ProjectRelativePath(Resolved);
  If (GAssistantToolMode <> amDocument) And TextIsAssistantPlan(Content) And
    ((GetActivePlanRelativePath = '') Or SameText(WrittenRel, GetActivePlanRelativePath)) Then
    Begin
      SetActivePlanRelativePath(WrittenRel);
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
  If GAssistantToolMode = amDocument Then
    RememberDocumentRelativePath(WrittenRel);
  ResultText := 'Wrote Markdown: ' + WrittenRel + ' (' + Resolved + ')';
  If (GAssistantToolMode <> amDocument) And TextIsAssistantPlan(Content) And
    SameText(WrittenRel, GetActivePlanRelativePath) Then
    Begin
      If Not AddAvailableAssistantPlan(Resolved, ErrorText) Then
        ResultText := ResultText + LineEnding + 'Warning: could not register the plan: ' + ErrorText;
      ErrorText := '';
    End
  Else If (GAssistantToolMode = amPlan) And (Not TextIsAssistantPlan(Content)) Then
    ResultText := ResultText + LineEnding +
      'Warning: this file is not registered in the plan list until it starts with an H1 and the line "' +
      AssistantPlanGeneratedLine + '", and is set as the active plan or added from the Plan sheet.';
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
  If GAssistantToolMode = amDocument Then
    Begin
      If Path = '' Then
        Path := GetDocumentRelativePath;
      If Path = '' Then
        Begin
          ErrorText := 'No document file yet. Call write_markdown first.';
          Exit;
        End;
      If IsActivePlanPath(Path) Then
        Begin
          ErrorText := 'Document mode will not edit the active plan. Switch to Plan mode, or choose another path.';
          Exit;
        End;
    End
  Else
    Begin
      If Path = '' Then
        Path := GetActivePlanRelativePath;
      If Path = '' Then
        Path := DefaultPlanRelativePath;
    End;
  OldText := JsonArgString(ArgumentsJson, 'old_text');
  NewText := JsonArgString(ArgumentsJson, 'new_text');
  ReplaceAll := JsonArgBool(ArgumentsJson, 'replace_all', False);
  OpenAfter := JsonArgBool(ArgumentsJson, 'open', True);
  If Not ReplaceInMarkdownFile(Path, OldText, NewText, ReplaceAll, OpenAfter, Resolved,
    ErrorText, Count) Then
    Exit;
  If GAssistantToolMode = amDocument Then
    RememberDocumentRelativePath(ProjectRelativePath(Resolved));
  ResultText := Format('Updated %s (%d replacement(s)).',
    [ProjectRelativePath(Resolved), Count]);
  Result := True;
End;

Function ToolListPlans(Out ResultText, ErrorText: String): Boolean;
Var
  Paths, Titles: TStringList;
  I: Integer;
  Active, CaptionText: String;
  ActiveMissing: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Paths := Nil;
  Titles := Nil;
  If Not ListAvailableAssistantPlans(GetActivePlanRelativePath, Paths, Titles, ActiveMissing, ErrorText) Then
    Begin
      Paths.Free;
      Titles.Free;
      Exit;
    End;
  Try
    Active := GetActivePlanRelativePath;
    ResultText := Format('Registered plans (%d):', [Paths.Count]) + LineEnding;
    If ActiveMissing Then
      ResultText := ResultText + 'Active plan file is missing and was removed from the list.' + LineEnding
    Else If Active <> '' Then
      ResultText := ResultText + 'Active plan: ' + Active + LineEnding;
    For I := 0 To Paths.Count - 1 Do
      Begin
        If I < Titles.Count Then
          CaptionText := FormatPlanListCaption(Titles[I], Paths[I])
        Else
          CaptionText := Paths[I];
        If SameText(Paths[I], Active) Then
          ResultText := ResultText + '* ' + CaptionText + '  (active)' + LineEnding
        Else
          ResultText := ResultText + '- ' + CaptionText + LineEnding;
      End;
    If Paths.Count = 0 Then
      ResultText := ResultText +
        '(none yet — add a recognised plan from the Plan sheet, or set_active_plan)' + LineEnding;
    Result := True;
  Finally
    Paths.Free;
    Titles.Free;
  End;
End;

Function ToolGetActivePlan(Out ResultText, ErrorText: String): Boolean;
Var
  Active, Resolved, Title, IdentityErr: String;
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
        Begin
          ResultText := ResultText + LineEnding + 'Exists: yes';
          If TryReadAssistantPlanIdentity(Resolved, Title, IdentityErr) Then
            ResultText := ResultText + LineEnding + 'Title: ' + Title + LineEnding + 'Recognised: yes'
          Else
            ResultText := ResultText + LineEnding + 'Recognised: no';
        End
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
  If Not TryReadAssistantPlanIdentity(Resolved, OldPlan, ErrorText) Then
    Begin
      ResultText := ResultText + LineEnding +
        'This file is not a recognised assistant plan and was not added to the plan list.';
      ErrorText := '';
    End
  Else
    Begin
      If Not AddAvailableAssistantPlan(Resolved, ErrorText) Then
        ResultText := ResultText + LineEnding + 'Warning: could not register the plan: ' + ErrorText
      Else
        ResultText := ResultText + LineEnding + 'Title: ' + OldPlan;
      ErrorText := '';
    End;
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

Function IsLazarusProjectInfoPath(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  { The IDE owns .lpi/.lps — tool writes desync memory vs disk and raise reload dialogs. }
  Result := (Ext = '.lpi') Or (Ext = '.lps');
End;

Function IsSearchableTextExtension(Const Path: String): Boolean; Forward;

Function IsSkippedSearchDirectory(Const DirName: String): Boolean;
Var
  N: String;
Begin
  N := LowerCase(DirName);
  Result := (N = '.git') Or (N = '.svn') Or (N = '.hg') Or (N = 'node_modules') Or
    (N = '__pycache__') Or (N = 'backup') Or (N = 'lib') Or (N = 'units') Or
    (N = '.grok') Or (N = '.assistant');
End;

Function CollectSearchableFiles(Const DirPath, Glob: String; Files: TStringList;
  Var FileCount, WalkCount: Integer): Boolean;
Var
  Info: TSearchRec;
  Child: String;
  Code: Integer;
Begin
  Result := True;
  If FileCount >= AssistantToolMaxSearchFiles Then
    Exit;
  Code := FindFirstUTF8(IncludeTrailingPathDelimiter(DirPath) + '*', faAnyFile, Info);
  Try
    While Code = 0 Do
      Begin
        If ToolsShouldStop Then
          Begin
            Result := False;
            Exit;
          End;
        Inc(WalkCount);
        If WalkCount > 20000 Then
          Begin
            Result := False;
            Exit;
          End;
        If (Info.Name <> '.') And (Info.Name <> '..') Then
          Begin
            Child := IncludeTrailingPathDelimiter(DirPath) + Info.Name;
            If (Info.Attr And faDirectory) <> 0 Then
              Begin
                If Not IsSkippedSearchDirectory(Info.Name) Then
                  If Not CollectSearchableFiles(Child, Glob, Files, FileCount, WalkCount) Then
                    Begin
                      Result := False;
                      Exit;
                    End;
              End
            Else If IsSearchableTextExtension(Child) And FileMatchesSearchGlob(Child, Glob) Then
              Begin
                Files.Add(Child);
                Inc(FileCount);
                If FileCount >= AssistantToolMaxSearchFiles Then
                  Exit;
              End;
          End;
        If FileCount >= AssistantToolMaxSearchFiles Then
          Exit;
        Code := FindNextUTF8(Info);
      End;
  Finally
    FindCloseUTF8(Info);
  End;
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
  I: Integer;
  Ed: TSourceEditorInterface;
  FullPath, EditorPath: String;
Begin
  Result := Nil;
  If Not Assigned(SourceEditorManagerIntf) Then
    Exit;
  FullPath := ExpandResolvedPath(Resolved);
  Result := SourceEditorManagerIntf.SourceEditorIntfWithFilename(FullPath);
  If Assigned(Result) Then Exit;
  If FullPath <> Resolved Then
    Result := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Resolved);
  If Assigned(Result) Then Exit;
  For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
    Begin
      Ed := SourceEditorManagerIntf.SourceEditors[I];
      If Not Assigned(Ed) Or (Ed.FileName = '') Then Continue;
      EditorPath := ExpandResolvedPath(Ed.FileName);
      If (EditorPath = FullPath) Or (Ed.FileName = Resolved) Or (Ed.FileName = FullPath) Then
        Exit(Ed);
    End;
End;

{ After a write, bring every unmodified open buffer for that path up to the new text.
  A dirty buffer is left alone so user edits are not discarded. }
Function RefreshUnmodifiedOpenEditor(Const FullPath, Content: String; Out Note: String): Boolean;
Var
  I: Integer;
  Ed: TSourceEditorInterface;
  EditorPath, SyncError: String;
  Refreshed, LeftDirty: Boolean;
Begin
  Result := False;
  Note := '';
  If Not Assigned(SourceEditorManagerIntf) Then Exit;
  Refreshed := False;
  LeftDirty := False;
  For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
    Begin
      Ed := SourceEditorManagerIntf.SourceEditors[I];
      If Not Assigned(Ed) Or (Ed.FileName = '') Or (Ed.SourceText = Content) Then Continue;
      EditorPath := ExpandResolvedPath(Ed.FileName);
      If (EditorPath <> FullPath) And (Ed.FileName <> FullPath) Then Continue;
      If Ed.Modified Then
        Begin
          LeftDirty := True;
          Continue;
        End;
      If Not ApplyAssistantEditorText(Ed, Ed.SourceText, Content, SyncError) Then
        Begin
          Note := SyncError;
          Exit;
        End;
      If Assigned(LazarusIDE) Then LazarusIDE.DoSaveEditorFile(Ed, [sfQuietUnitCheck]);
      Refreshed := True;
    End;
  If Refreshed Then
    Note := 'Refreshed the open editor from the written file so a later save cannot restore the old text.';
  If LeftDirty Then
    Begin
      If Note <> '' Then Note := Note + ' ';
      Note := Note + 'An open editor has unsaved edits and was not replaced. Do not save it over the newer disk copy.';
    End;
  Result := Refreshed Or LeftDirty;
End;

Function MarkdownEditorToolRefused(Const ToolName, ArgumentsJson: String; Out ErrorText: String): Boolean;
Var
  Name: String;
Begin
  Result := False;
  ErrorText := '';
  Name := LowerCase(Trim(ToolName));
  If (Name <> 'open_file') And (Name <> 'write_file') And (Name <> 'replace_in_file') And
    (Name <> 'ensure_form_component') And (Name <> 'delete_path') And (Name <> 'rename_path') And
    (Name <> 'add_unit_to_project') Then
    Exit;
  If IsMarkdownPath(JsonArgString(ArgumentsJson, 'path')) Or
    IsMarkdownPath(JsonArgString(ArgumentsJson, 'new_path')) Then
    Begin
      ErrorText :=
        'A plan or document is written with write_markdown or update_markdown, not by editing it in the source editor.';
      Result := True;
    End;
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
  { Markdown belongs in the Assistant viewer. Do not create or reuse a source tab. }
  If IsMarkdownPath(FullPath) Then
    Begin
      Note := 'Markdown files are not opened in the source editor. Use open_markdown.';
      Exit;
    End;
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
  If Assigned(IDEEnvironmentOptions) Then
    Begin
      Cand := IncludeTrailingPathDelimiter(IDEEnvironmentOptions.GetParsedLazarusDirectory) +
        'lazbuild'{$IFDEF WINDOWS}+'.exe'{$ENDIF};
      If FileExistsUTF8(Cand) Then Exit(Cand);
    End;
  Result := '';
End;

Function RunProcessCapture(Const Exe, WorkDir: String; Const Args: Array Of String;
  Out OutputText: String; Out ExitCode: Integer; Out ErrorText: String; TimeoutMs: QWord = 0): Boolean;
Var
  Proc: TProcess;
  I, BytesRead: Integer;
  Mem: TMemoryStream;
  Buf: Array[0..8191] Of Byte;
  StartTick: QWord;

  Function AbortRunning(Const Reason: String): Boolean;
  Begin
    Try
      Proc.Terminate(1);
    Except
    End;
    ErrorText := Reason;
    Result := False;
  End;

Begin
  Result := False;
  OutputText := '';
  ExitCode := -1;
  ErrorText := '';
  If TimeoutMs = 0 Then
    TimeoutMs := AssistantToolMaxCompileMs;
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
      StartTick := GetTickCount64;
      While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
        Begin
          If ToolsShouldStop Then
            Begin
              Result := AbortRunning('Cancelled.');
              Exit;
            End;
          If GetTickCount64 - StartTick >= TimeoutMs Then
            Begin
              Result := AbortRunning(Format('Timed out after %d s.', [TimeoutMs Div 1000]));
              Exit;
            End;
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
  Stream: TFileStream;
  Dir, FullPath, OpenNote: String;
Begin
  Result := False;
  Note := '';
  ErrorText := '';
  FullPath := ExpandResolvedPath(Resolved);
  If Not AssistantTarget.AllowsWrite(FullPath) Then
    Begin
      ErrorText := AssistantTarget.ScopeRefusal('write', FullPath);
      Exit;
    End;
  If IsLazarusProjectInfoPath(FullPath) Then
    Begin
      ErrorText :=
        'Refusing to write project info file (.lpi/.lps). The IDE owns the project file. ' +
        'Use add_unit_to_project to register units; never rewrite the .lpi with write_file.';
      Exit;
    End;
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
        If Not ApplyAssistantEditorText(Ed, Ed.SourceText, Content, ErrorText) Then
          Exit;
        If Assigned(LazarusIDE) And (LazarusIDE.DoSaveEditorFile(Ed, [sfQuietUnitCheck]) = mrOk) Then
          Begin
            Note := 'Updated open editor buffer and saved to disk (IDE Undo available).';
            RefreshUnmodifiedOpenEditor(FullPath, Content, OpenNote);
            If OpenNote <> '' Then Note := Note + ' ' + OpenNote;
          End
        Else
          Begin
            ErrorText := 'Updated open editor buffer (IDE Undo available), but disk save did not complete. ' +
              'The buffer is already changed; inspect/save it rather than repeating the edit.';
            Exit;
          End;
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
  Stream := Nil;
  Try
    Try
      Stream := TFileStream.Create(FullPath, fmCreate);
      If Length(Content) > 0 Then
        Stream.WriteBuffer(Content[1], Length(Content));
      Note := 'Wrote file on disk.';
      RefreshUnmodifiedOpenEditor(FullPath, Content, OpenNote);
      If OpenNote <> '' Then Note := Note + ' ' + OpenNote;
      Result := True;
    Except
      On E: Exception Do
        Begin
          ErrorText := E.Message;
          Exit;
        End;
    End;
  Finally
    Stream.Free;
  End;
  If OpenAfter Then
    Begin
      If IsMarkdownPath(FullPath) Then
        Begin
          { Same quiet rule as open_markdown: a plan run must not steal the window. }
          If AssistantPlanViewerQuiet Then
            Begin
              If Assigned(FindMarkdownDocument(FullPath)) Then
                ReloadMarkdownDocument(FullPath, False, False);
              Note := Note + ' Plan run in progress. The Markdown viewer was not opened. Use open_markdown.';
            End
          Else If OpenMarkdownDocument(FullPath) = Nil Then
            Note := Note + ' (Could not open the Markdown viewer. Use open_markdown.)'
          Else
            Note := Note + ' Opened in the Assistant Markdown viewer (open_markdown).';
        End
      Else If OpenEditorReuse(FullPath, OpenNote) Then
        Note := Note + ' ' + OpenNote
      Else
        Note := Note + ' (' + OpenNote + ')';
    End;
End;

Function FlushOpenEditorsUnderProject(Out ErrorText: String): Boolean;
Var
  I: Integer;
  Ed: TSourceEditorInterface;
  FullPath, Root: String;
Begin
  { Write remaining modified open buffers to disk (quiet lazbuild reads files).
    SaveProjectFileText now saves after a buffer update; this still covers user edits. }
  Result := True;
  ErrorText := '';
  If Not Assigned(SourceEditorManagerIntf) Or Not Assigned(LazarusIDE) Then
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
      If (AssistantTarget.Kind<>atkProject) And Not AssistantTarget.ContainsFile(FullPath) Then Continue;
      If LazarusIDE.DoSaveEditorFile(Ed, [sfQuietUnitCheck]) <> mrOk Then
        Begin
          Result := False;
          ErrorText := 'Could not save editor buffer to disk: ' + FullPath;
          Exit;
        End;
    End;
End;

Function QuietSaveTargetForGit(Out ErrorText: String): Boolean;
Var
  ForeignName: String;
  Selected, Other: TIDEPackage;
  Index: Integer;
Begin
  Result := False;
  ErrorText := '';
  If Not FlushOpenEditorsUnderProject(ErrorText) Then
    Exit;
  If AssistantTarget.Kind = atkProject Then
    Begin
      If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) And LazarusIDE.ActiveProject.Modified Then
        If LazarusIDE.DoSaveProject([sfQuietUnitCheck]) <> mrOk Then
          Begin
            ErrorText := 'Could not save project ' + LazarusIDE.ActiveProject.ProjectInfoFile +
              ' before staging or committing.';
            Exit;
          End;
      If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) And LazarusIDE.ActiveProject.Modified Then
        Begin
          ErrorText := 'Project ' + LazarusIDE.ActiveProject.ProjectInfoFile +
            ' is still modified after a quiet save. Save it in Lazarus before staging or committing.';
          Exit;
        End;
    End
  Else If Assigned(PackageEditingInterface) And AssistantTarget.Available Then
    Begin
      Selected := AssistantTarget.Package;
      If Assigned(Selected) And Selected.Modified Then
        Begin
          ForeignName := '';
          For Index := 0 To PackageEditingInterface.GetPackageCount - 1 Do
            Begin
              Other := PackageEditingInterface.GetPackages(Index);
              If (Not Assigned(Other)) Or (Not Other.Modified) Or Other.ReadOnly Or (Other = Selected) Then
                Continue;
              ForeignName := Other.Filename;
              If ForeignName = '' Then
                ForeignName := 'another package';
              Break;
            End;
          If ForeignName <> '' Then
            Begin
              ErrorText := 'Package ' + Selected.Filename + ' is unsaved, and ' + ForeignName +
                ' is also modified. Save ' + ExtractFileName(Selected.Filename) +
                ' in Lazarus before staging or committing. A quiet save would also write the other package.';
              Exit;
            End;
          If PackageEditingInterface.DoSaveAllPackages([]) <> mrOk Then
            Begin
              ErrorText := 'Could not save package ' + Selected.Filename + ' before staging or committing.';
              Exit;
            End;
          If Selected.Modified Then
            Begin
              ErrorText := 'Package ' + Selected.Filename +
                ' is still modified after a quiet save. Save it in Lazarus before staging or committing.';
              Exit;
            End;
        End;
    End;
  Result := True;
End;

Function CompileCleanSuffix(Clean: Boolean): String;
Begin
  If Clean Then
    Result := 'COMPILE_CLEAN=1 (errors=0). A clean compile does not close the work item. ' +
      'Set Status to complete when the item''s written acceptance criteria are met. ' +
      'A missing Validation line does not forbid that status change.'
  Else
    Result := 'COMPILE_CLEAN=0 (fix errors before treating the work package as done).';
End;

Function RunQuietLazbuild(KindBuild: Boolean; Out ResultText, ErrorText: String;
  Out ErrorCount, WarningCount, HintCount: Integer; Out BuildOk: Boolean): Boolean;
Var
  Lazbuild, Lpi, WorkDir, OutputText, Diag: String;
  ExitCode, I, Extra: Integer;
  Args: Array Of String;
  Manifests: TStringList;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  ErrorCount := 0;
  WarningCount := 0;
  HintCount := 0;
  BuildOk := False;
  If Not Assigned(LazarusIDE) Or Not AssistantTarget.Available Then
    Begin
      ErrorText := 'No active Lazarus project.';
      Exit;
    End;
  Manifests := TStringList.Create;
  Try
    If AssistantTarget.Kind = atkFolder Then
      Begin
        CollectFolderCompileFiles(AssistantTarget.Root, Manifests);
        If Manifests.Count = 0 Then
          Begin
            ErrorText := 'No Lazarus package or project file found under the target folder.';
            Exit;
          End;
        WorkDir := ExcludeTrailingPathDelimiter(AssistantTarget.Root);
      End
    Else
      Begin
        Lpi := AssistantTarget.Manifest;
        If (Lpi = '') Or (Not FileExistsUTF8(Lpi)) Then
          Begin
            ErrorText := 'Project .lpi not found for quiet compile.';
            Exit;
          End;
        Manifests.Add(Lpi);
        WorkDir := ExtractFilePath(Lpi);
      End;
    Lazbuild := FindLazbuildExecutable;
    If Lazbuild = '' Then
      Begin
        If AssistantTarget.Kind = atkFolder Then
          ErrorText := 'lazbuild not found on PATH or next to the IDE. A folder target is not compiled with the IDE active project.'
        Else
          ErrorText := 'lazbuild not found on PATH or next to the IDE. Use ui=true for IDE compile.';
        Exit;
      End;
    If Not FlushOpenEditorsUnderProject(ErrorText) Then
      Exit;
    Extra := 0;
    If KindBuild Then
      Extra := 1;
    Args := Nil;
    SetLength(Args, Manifests.Count + Extra);
    If KindBuild Then
      Args[0] := '--build-all';
    For I := 0 To Manifests.Count - 1 Do
      Args[I + Extra] := Manifests[I];
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
    If AssistantTarget.Kind = atkFolder Then
      Begin
        ResultText := ResultText + LineEnding + 'Compiled:';
        For I := 0 To Manifests.Count - 1 Do
          ResultText := ResultText + LineEnding + '  ' + Manifests[I];
        ResultText := ResultText + LineEnding +
          'Folder target: lazbuild compiled these files. The IDE active project was not used.';
      End;
    Result := True;
  Finally
    Manifests.Free;
  End;
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
  MaxMatches, MatchCount, FileCount, WalkCount, LineNo, I: Integer;
  Files: TStringList;
  SL: TStringList;
  WalkComplete, UseRegex, Hit, Stopped, SingleFile: Boolean;
  Re: TRegExpr;
  Deadline: QWord;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Re := Nil;
  Query := JsonArgString(ArgumentsJson, 'query');
  If Trim(Query) = '' Then
    Query := JsonArgString(ArgumentsJson, 'pattern');
  If Trim(Query) = '' Then
    Begin
      ErrorText := 'grep/search_in_project requires pattern or query.';
      Exit;
    End;
  Path := JsonArgString(ArgumentsJson, 'path');
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  Glob := Trim(JsonArgString(ArgumentsJson, 'glob'));
  MaxMatches := JsonArgInt(ArgumentsJson, 'max_matches', AssistantToolMaxSearchMatches);
  If MaxMatches < 1 Then
    MaxMatches := AssistantToolMaxSearchMatches;
  If MaxMatches > 200 Then
    MaxMatches := 200;
  UseRegex := JsonArgBool(ArgumentsJson, 'regex', False);
  If (Not UseRegex) And PatternLooksLikeRegex(Query) Then
    UseRegex := True;
  LowerQuery := LowerCase(Query);
  If UseRegex Then
    Begin
      Re := TRegExpr.Create;
      Try
        Re.ModifierI := True;
        Re.Expression := Query;
      Except
        On E: Exception Do
          Begin
            ErrorText := 'Invalid regular expression: ' + E.Message;
            FreeAndNil(Re);
            Exit;
          End;
      End;
    End;
  Files := TStringList.Create;
  SL := TStringList.Create;
  Deadline := GetTickCount64 + AssistantToolMaxSearchMs;
  Stopped := False;
  Try
    FileCount := 0;
    WalkCount := 0;
    WalkComplete := True;
    SingleFile := FileExistsUTF8(Resolved) And (Not DirectoryExistsUTF8(Resolved));
    If SingleFile Then
      Begin
        If FileMatchesSearchGlob(Resolved, Glob) Then
          Begin
            Files.Add(Resolved);
            FileCount := 1;
          End;
        ResultText := Format('Search for "%s" in %s', [Query, Resolved]) + LineEnding;
      End
    Else If DirectoryExistsUTF8(Resolved) Then
      Begin
        WalkComplete := CollectSearchableFiles(Resolved, Glob, Files, FileCount, WalkCount);
        ResultText := Format('Search for "%s" under %s', [Query, Resolved]) + LineEnding;
      End
    Else
      Begin
        ErrorText := 'Path not found: ' + Resolved;
        Exit;
      End;
    MatchCount := 0;
    If Not WalkComplete Then
      ResultText := ResultText + '[… directory walk capped before listing every file …]' + LineEnding;
    If FileCount >= AssistantToolMaxSearchFiles Then
      ResultText := ResultText + Format('[… stopped after listing %d text files …]',
        [AssistantToolMaxSearchFiles]) + LineEnding;
    For I := 0 To Files.Count - 1 Do
      Begin
        If ToolsShouldStop Or (GetTickCount64 >= Deadline) Then
          Begin
            Stopped := True;
            Break;
          End;
        If FileSizeUTF8(Files[I]) > AssistantToolMaxSearchFileBytes Then
          Continue;
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
            If Assigned(Re) Then
              Begin
                If Length(LineText) > AssistantToolMaxSearchLineChars Then
                  Continue;
                Hit := Re.Exec(LineText);
              End
            Else
              Hit := Pos(LowerQuery, LowerCase(LineText)) > 0;
            If Hit Then
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
    If Stopped Then
      ResultText := ResultText + Format('[… search stopped after %d ms (scanned %d files, %d matches) …]',
        [AssistantToolMaxSearchMs, I, MatchCount]) + LineEnding;
    ResultText := ResultText + Format('Matches: %d (scanned %d text files).', [MatchCount, Files.Count]);
    Result := True;
  Finally
    SL.Free;
    Files.Free;
    FreeAndNil(Re);
  End;
End;

Function ToolGrep(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Begin
  Result := ToolSearchInProject(ArgumentsJson, ResultText, ErrorText);
End;

Function ToolReadSkill(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  SkillName, Root: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  SkillName := JsonArgString(ArgumentsJson, 'name');
  If Trim(SkillName) = '' Then
    SkillName := JsonArgString(ArgumentsJson, 'skill');
  If Trim(SkillName) = '' Then
    Begin
      ErrorText := 'read_skill requires name.';
      Exit;
    End;
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  If Root = '' Then
    Root := ProjectRootPath;
  If Not Assigned(WorkflowAssistantHarness) Then
    Begin
      ErrorText := 'Harness is not available.';
      Exit;
    End;
  Result := WorkflowAssistantHarness.ReadSkill(SkillName, Root, ResultText, ErrorText);
End;

Function ToolTodoWrite(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Not Assigned(WorkflowAssistantHarness) Then
    Begin
      ErrorText := 'Harness is not available.';
      Exit;
    End;
  Result := WorkflowAssistantHarness.ApplyTodoWrite(ArgumentsJson, ResultText, ErrorText);
End;

{ Must appear before ToolWriteFile / ToolReplaceInFile. }
Function LooksLikeStreamedComponentEdit(Const ChangedText: String): Boolean;
Var
  Sample: String;
Begin
  Sample := ChangedText;
  Result := (Pos('TTimer', Sample) > 0) Or (Pos('TActionList', Sample) > 0) Or
    (Pos('TImageList', Sample) > 0) Or (Pos('TAction', Sample) > 0) Or
    (Pos('TButton', Sample) > 0) Or (Pos('object ', Sample) > 0) Or
    (Pos('OnTimer', Sample) > 0) Or (Pos('ensure_form_component', Sample) > 0);
End;

Function FormLfmEditReminder(Const PasPath, ChangedText: String): String;
Var
  LfmPath: String;
Begin
  Result := '';
  If (LowerCase(ExtractFileExt(PasPath)) <> '.pas') And
    (LowerCase(ExtractFileExt(PasPath)) <> '.pp') Then
    Exit;
  LfmPath := ChangeFileExt(PasPath, '.lfm');
  If Not FileExistsUTF8(LfmPath) Then
    Exit;
  If Not LooksLikeStreamedComponentEdit(ChangedText) Then
    Exit;
  Result := LineEnding +
    'Sibling ' + ExtractFileName(LfmPath) +
    ' exists. If this edit added or renamed a streamed control or On* handler, update that .lfm ' +
    '(ensure_form_component or replace_in_file).';
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
  If (AssistantTarget.Kind=atkProject) And AddToProject And IsPascalUnitPath(Resolved) And Assigned(LazarusIDE) And
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
              MarkProjectStructureDirty;
              AssistantFlushProjectIfDirty;
              ResultText := ResultText + ' Added to project (project file saved).';
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
  Path, Resolved, OldText, NewText, Body, Note, FileEol, AltOld: String;
  ReplaceAll, FromEditor, OpenAfter: Boolean;
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
  OpenAfter := JsonArgBool(ArgumentsJson, 'open', False);
  If Not LoadProjectFileText(Resolved, Body, FromEditor, ErrorText) Then
    Exit;
  FileEol := DetectFileEol(Body);
  If Pos(OldText, Body) < 1 Then
    Begin
      AltOld := NormalizeToEol(OldText, FileEol);
      If (AltOld <> OldText) And (Pos(AltOld, Body) > 0) Then
        OldText := AltOld
      Else
        Begin
          If FromEditor Then
            ErrorText := 'old_text not found in open editor buffer: ' + Resolved +
              '. Re-read this file (read_file uses the buffer); the buffer can differ from disk. ' +
              'Use a smaller unique snippet.'
          Else
            ErrorText := 'old_text not found in ' + Resolved +
              '. Re-read this file and use a smaller unique snippet.';
          Exit;
        End;
    End;
  NewText := NormalizeToEol(NewText, FileEol);
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
  If Not SaveProjectFileText(Resolved, Body, OpenAfter, Note, ErrorText) Then
    Exit;
  ResultText := Format('Replaced %d occurrence(s) in %s. %s',
    [Count, ProjectRelativePath(Resolved), Note]);
  ResultText := ResultText + FormLfmEditReminder(Resolved, NewText);
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
  If Not Assigned(LazarusIDE) Or Not AssistantTarget.Available Then
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
  { A folder has no single IDE project. ui=true would compile whatever project is open. }
  If AssistantTarget.Kind = atkFolder Then
    UseUi := False;
  If Not UseUi Then
    Begin
      If Not RunQuietLazbuild(Kind = 'build', ResultText, ErrorText,
        ErrorCount, WarningCount, HintCount, BuildOk) Then
        Begin
          { Fall back to IDE compile if lazbuild missing. A folder must not fall back:
            that compiles the open project instead of the packages under the target. }
          If (AssistantTarget.Kind = atkFolder) Or (Pos('lazbuild not found', ErrorText) = 0) Then
            Exit;
          WorkflowLogger.Warning('AssistantTools', ErrorText + ' — falling back to IDE compile.');
          UseUi := True;
          ErrorText := '';
        End
      Else
        Begin
          Inc(GLastCompileSeq);
          GLastCompileClean := BuildOk And (ErrorCount = 0);
          ResultText := ResultText + LineEnding + CompileCleanSuffix(GLastCompileClean);
          GLastCompileLog := ResultText;
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
    If AssistantTarget.Kind=atkPackage Then
    Begin
      If Reason=crBuild Then BuildResult := PackageEditingInterface.DoCompilePackage(AssistantTarget.Package,[pcfCleanCompile,pcfDoNotSaveEditorFiles],False)
      Else BuildResult := PackageEditingInterface.DoCompilePackage(AssistantTarget.Package,[pcfDoNotSaveEditorFiles],False);
    End
  Else BuildResult := LazarusIDE.DoBuildProject(Reason, []);
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
  ResultText := ResultText + LineEnding + CompileCleanSuffix(GLastCompileClean);
  GLastCompileLog := ResultText;
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
    MarkProjectStructureDirty;
    AssistantFlushProjectIfDirty;
    ResultText := 'Added to project and saved: ' + ProjectRelativePath(Resolved);
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
      { Markdown refusal is the tool error. Other failures keep the path. }
      If Pos('open_markdown', Note) > 0 Then
        ErrorText := Note
      Else
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

Function PathHasControlCharacter(Const Path: String): Boolean;
Begin
  Result := (Pos(#0, Path) > 0) Or (Pos(#10, Path) > 0) Or (Pos(#13, Path) > 0);
End;

Function IsGitMetadataPath(Const Resolved: String): Boolean;
Var
  GitDir, Cand: String;
Begin
  GitDir := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(ProjectRootPath)) + '.git';
  Cand := ExpandFileName(Resolved);
  Result := (CompareFilenames(ExcludeTrailingPathDelimiter(Cand), ExcludeTrailingPathDelimiter(GitDir)) = 0) Or
    (CompareFilenames(Copy(Cand, 1, Length(IncludeTrailingPathDelimiter(GitDir))), IncludeTrailingPathDelimiter(GitDir)) = 0);
End;

Function RefuseProtectedPath(Const Resolved: String; Out ErrorText: String): Boolean;
Var
  Root, Manifest: String;
Begin
  Result := True;
  ErrorText := '';
  Root := ExcludeTrailingPathDelimiter(ProjectRootPath);
  If CompareFilenames(ExcludeTrailingPathDelimiter(ExpandFileName(Resolved)), Root) = 0 Then
    Begin
      ErrorText := 'Refusing to change the project root.';
      Exit;
    End;
  If IsGitMetadataPath(Resolved) Then
    Begin
      ErrorText := 'Refusing to change Git metadata.';
      Exit;
    End;
  If AssistantTarget.Available Then
    Begin
      Manifest := AssistantTarget.Manifest;
      If (Manifest <> '') And (CompareFilenames(ExpandFileName(Manifest), ExpandFileName(Resolved)) = 0) Then
        Begin
          ErrorText := 'Refusing to change the project or package file.';
          Exit;
        End;
    End;
  Result := False;
End;

Function DirectoryIsEmpty(Const Directory: String): Boolean;
Var
  Info: TSearchRec;
  Found: Integer;
Begin
  Result := True;
  Found := FindFirstUTF8(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Info);
  If Found <> 0 Then
    Exit;
  Try
    Repeat
      If (Info.Name <> '.') And (Info.Name <> '..') Then
        Exit(False);
    Until FindNextUTF8(Info) <> 0;
  Finally
    FindCloseUTF8(Info);
  End;
End;

Function ToolDeletePath(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Resolved: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If PathHasControlCharacter(JsonArgString(ArgumentsJson, 'path')) Then
    Begin
      ErrorText := 'Path contains a control character.';
      Exit;
    End;
  If Not ResolveProjectPath(JsonArgString(ArgumentsJson, 'path'), Resolved, ErrorText) Then
    Exit;
  If RefuseProtectedPath(Resolved, ErrorText) Then
    Exit;
  If FileIsSymlink(Resolved) Then
    Begin
      If Not DeleteFileUTF8(Resolved) Then
        ErrorText := 'Could not delete the symbolic link.'
      Else
        Begin
          ResultText := 'Deleted symbolic link ' + Resolved;
          Result := True;
        End;
      Exit;
    End;
  If DirectoryExistsUTF8(Resolved) Then
    Begin
      If Not DirectoryIsEmpty(Resolved) Then
        Begin
          ErrorText := 'Directory is not empty. Delete its files first.';
          Exit;
        End;
      If Not RemoveDir(Resolved) Then
        ErrorText := 'Could not remove the directory.'
      Else
        Begin
          ResultText := 'Removed empty directory ' + Resolved;
          Result := True;
        End;
      Exit;
    End;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'Path does not exist.';
      Exit;
    End;
  If Not DeleteFileUTF8(Resolved) Then
    ErrorText := 'Could not delete the file.'
  Else
    Begin
      ResultText := 'Deleted ' + Resolved;
      Result := True;
    End;
End;

Function ToolRenamePath(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  SourcePath, DestPath: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If PathHasControlCharacter(JsonArgString(ArgumentsJson, 'path')) Or
    PathHasControlCharacter(JsonArgString(ArgumentsJson, 'new_path')) Then
    Begin
      ErrorText := 'Path contains a control character.';
      Exit;
    End;
  If Not ResolveProjectPath(JsonArgString(ArgumentsJson, 'path'), SourcePath, ErrorText) Then
    Exit;
  If Not ResolveProjectPath(JsonArgString(ArgumentsJson, 'new_path'), DestPath, ErrorText) Then
    Exit;
  If RefuseProtectedPath(SourcePath, ErrorText) Or RefuseProtectedPath(DestPath, ErrorText) Then
    Exit;
  If CompareFilenames(SourcePath, DestPath) = 0 Then
    Begin
      ErrorText := 'The new path is the same as the old path.';
      Exit;
    End;
  If (Not FileExistsUTF8(SourcePath)) And (Not DirectoryExistsUTF8(SourcePath)) Then
    Begin
      ErrorText := 'Path does not exist.';
      Exit;
    End;
  If FileExistsUTF8(DestPath) Or DirectoryExistsUTF8(DestPath) Then
    Begin
      ErrorText := 'The new path already exists.';
      Exit;
    End;
  If Not RenameFile(SourcePath, DestPath) Then
    ErrorText := 'Could not rename the path.'
  Else
    Begin
      ResultText := 'Renamed ' + SourcePath + ' to ' + DestPath;
      Result := True;
    End;
End;

Function ToolRunProject(Out ResultText, ErrorText: String): Boolean;
Var
  Proj: TLazProject;
  Exe, WorkDir: String;
  Proc: TProcess;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If AssistantTarget.Kind <> atkProject Then
    Begin
      ErrorText := 'Run starts the active project executable, not a package.';
      Exit;
    End;
  If (Not Assigned(LazarusIDE)) Or (Not Assigned(LazarusIDE.ActiveProject)) Then
    Begin
      ErrorText := 'No active Lazarus project.';
      Exit;
    End;
  Proj := LazarusIDE.ActiveProject;
  If Not Assigned(Proj.LazCompilerOptions) Then
    Begin
      ErrorText := 'The active project has no compiler options.';
      Exit;
    End;
  Exe := Proj.LazCompilerOptions.CreateTargetFilename;
  If Exe = '' Then
    Begin
      ErrorText := 'The active project has no target executable.';
      Exit;
    End;
  If Not FilenameIsAbsolute(Exe) Then
    Exe := ExpandFileName(ExtractFilePath(Proj.ProjectInfoFile) + Exe);
  If Not ResolveProjectPath(Exe, Exe, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Exe) Then
    Begin
      ErrorText := 'Build the project before running it. Executable not found: ' + Exe;
      Exit;
    End;
  WorkDir := ProjectRootPath;
  Proc := TProcess.Create(Nil);
  Try
    Proc.Executable := Exe;
    Proc.CurrentDirectory := WorkDir;
    Proc.Options := [poNoConsole];
    Proc.Execute;
    ResultText := 'Started ' + Exe + ' (pid ' + IntToStr(Proc.ProcessID) +
      '). No debugger is attached, and no shell was used.';
    Result := True;
  Except
    On E: Exception Do
      ErrorText := 'Could not start the project: ' + E.Message;
  End;
  Proc.Free;
End;

Function ToolRunTests(Out ResultText, ErrorText: String): Boolean;
Var
  Settings: TAssistantTestSettings;
  Exe, WorkDir, OutputText: String;
  Args: Array Of String;
  I, ExitCode: Integer;
  TimeoutMs: QWord;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Not AssistantTarget.Available Then
    Begin
      ErrorText := 'No available Assistant work target.';
      Exit;
    End;
  Settings := TAssistantTestSettings.Create(AssistantTarget.StoreDirectory, AssistantTarget.Manifest);
  Try
    Settings.Load;
    If Not Settings.Enabled Then
      Begin
        ErrorText := 'Configure and enable the test command for this target first.';
        Exit;
      End;
    If Not Settings.Validate(ErrorText) Then
      Exit;
    Exe := Settings.ResolvedExecutable;
    WorkDir := Settings.WorkingDirectory;
    If Not ResolveProjectPath(Exe, Exe, ErrorText) Then
      Exit;
    If Not ResolveProjectPath(WorkDir, WorkDir, ErrorText) Then
      Exit;
    If Not FileExistsUTF8(Exe) Then
      Begin
        ErrorText := 'Test executable not found: ' + Exe;
        Exit;
      End;
    SetLength(Args, Settings.Arguments.Count);
    For I := 0 To Settings.Arguments.Count - 1 Do
      Args[I] := Settings.Arguments[I];
    TimeoutMs := QWord(Settings.TimeoutSeconds) * 1000;
    If TimeoutMs > AssistantToolMaxCompileMs Then
      TimeoutMs := AssistantToolMaxCompileMs;
    If Not RunProcessCapture(Exe, WorkDir, Args, OutputText, ExitCode, ErrorText, TimeoutMs) Then
      Exit;
    If Length(OutputText) > AssistantToolMaxReadChars Then
      OutputText := Copy(OutputText, 1, AssistantToolMaxReadChars) + LineEnding + '… (output truncated)';
    ResultText := 'Test executable: ' + Exe + LineEnding +
      'Working directory: ' + WorkDir + LineEnding +
      'Exit code: ' + IntToStr(ExitCode) + LineEnding + LineEnding + OutputText;
    Result := True;
  Finally
    Settings.Free;
  End;
End;

Function ImageProjectRelative(Const Resolved: String): String;
Var
  Root, Full: String;
Begin
  Root := IncludeTrailingPathDelimiter(ExpandFileName(ProjectRootPath));
  Full := ExpandFileName(Resolved);
  If Copy(Full, 1, Length(Root)) = Root Then
    Result := StringReplace(Copy(Full, Length(Root) + 1, MaxInt), '\', '/', [rfReplaceAll])
  Else
    Result := StringReplace(Resolved, '\', '/', [rfReplaceAll]);
End;

Function ImageOutputPathRefused(Const RelativePath: String; Out ErrorText: String): Boolean;
Var
  Normal, Segment: String;
  Slash: Integer;
Begin
  Result := True;
  ErrorText := '';
  Normal := StringReplace(Trim(RelativePath), '\', '/', [rfReplaceAll]);
  While (Normal <> '') And (Normal[1] = '/') Do
    Delete(Normal, 1, 1);
  If Normal = '' Then
    Begin
      ErrorText := 'write_image requires a project-relative path.';
      Exit;
    End;
  While Normal <> '' Do
    Begin
      Slash := Pos('/', Normal);
      If Slash < 1 Then
        Segment := Normal
      Else
        Segment := Copy(Normal, 1, Slash - 1);
      If (Segment = '') Or (Segment = '.') Or (Segment = '..') Then
        Begin
          ErrorText := 'Image path is outside the project.';
          Exit;
        End;
      If SameText(Segment, '.git') Or SameText(Segment, '.assistant') Then
        Begin
          ErrorText := 'Refusing an image path in ' + Segment + '.';
          Exit;
        End;
      If SameText(Segment, 'lib') Or SameText(Segment, 'units') Then
        Begin
          ErrorText := 'Refusing a build-output path.';
          Exit;
        End;
      If Slash < 1 Then
        Break;
      Delete(Normal, 1, Slash);
    End;
  Result := False;
End;

Function ImageExtensionMime(Const Path: String; Out Mime: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  If Ext = '.png' Then
    Mime := 'image/png'
  Else If (Ext = '.jpg') Or (Ext = '.jpeg') Then
    Mime := 'image/jpeg'
  Else If Ext = '.gif' Then
    Mime := 'image/gif'
  Else If Ext = '.webp' Then
    Mime := 'image/webp'
  Else
    Mime := '';
  Result := Mime <> '';
End;

Function ImageDestinationBlocked(Const Resolved: String; Overwrite: Boolean; Out ErrorText: String): Boolean;
Begin
  Result := True;
  ErrorText := '';
  If FileIsSymlink(Resolved) Then
    Begin
      If SymlinkLeavesProject(Resolved) Then
        ErrorText := 'Refusing a symbolic link that leaves the project.'
      Else If Not Overwrite Then
        ErrorText := 'File already exists. Pass overwrite to replace it.'
      Else
        Result := False;
      Exit;
    End;
  If DirectoryExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'Image path is a directory.';
      Exit;
    End;
  If FileExistsUTF8(Resolved) And (Not Overwrite) Then
    Begin
      ErrorText := 'File already exists. Pass overwrite to replace it.';
      Exit;
    End;
  Result := False;
End;

Function PublishImageBytes(Const Resolved: String; Const Data: TBytes; Overwrite: Boolean;
  Out ErrorText: String): Boolean;
Var
  Parent, TempPath, BackupPath: String;
  Stream: TFileStream;
  Existed: Boolean;
Begin
  Result := False;
  ErrorText := '';
  If ImageDestinationBlocked(Resolved, Overwrite, ErrorText) Then
    Exit;
  Parent := ExtractFileDir(Resolved);
  If FileIsSymlink(Parent) And SymlinkLeavesProject(Parent) Then
    Begin
      ErrorText := 'Refusing a symbolic link that leaves the project.';
      Exit;
    End;
  If (Parent <> '') And (Not DirectoryExistsUTF8(Parent)) Then
    If Not ForceDirectoriesUTF8(Parent) Then
      Begin
        ErrorText := 'Could not create the image directory.';
        Exit;
      End;
  Existed := FileExistsUTF8(Resolved) Or FileIsSymlink(Resolved);
  TempPath := Resolved + '.writing';
  BackupPath := Resolved + '.bak';
  If FileExistsUTF8(TempPath) Or FileIsSymlink(TempPath) Then
    DeleteFileUTF8(TempPath);
  Stream := Nil;
  Try
    Try
      Stream := TFileStream.Create(TempPath, fmCreate);
      If Length(Data) > 0 Then
        Stream.WriteBuffer(Data[0], Length(Data));
    Except
      On E: Exception Do
        Begin
          DeleteFileUTF8(TempPath);
          ErrorText := 'Could not write the image.';
          Exit;
        End;
    End;
  Finally
    Stream.Free;
  End;
  If Existed Then
    Begin
      If FileExistsUTF8(BackupPath) Or FileIsSymlink(BackupPath) Then
        DeleteFileUTF8(BackupPath);
      If Not RenameFileUTF8(Resolved, BackupPath) Then
        Begin
          DeleteFileUTF8(TempPath);
          ErrorText := 'Could not replace the existing image.';
          Exit;
        End;
    End;
  If Not RenameFileUTF8(TempPath, Resolved) Then
    Begin
      If Existed Then
        RenameFileUTF8(BackupPath, Resolved);
      DeleteFileUTF8(TempPath);
      ErrorText := 'Could not write the image.';
      Exit;
    End;
  If Existed Then
    DeleteFileUTF8(BackupPath);
  Result := True;
End;

Function ToolWriteImage(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Path, Resolved, Relative, ExpectedMime, SniffedMime: String;
  Overwrite: Boolean;
  Image: TAssistantGeneratedImage;
  Width, Height: Integer;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  ClearGeneratedImage(Image);
  Path := Trim(JsonArgString(ArgumentsJson, 'path'));
  Overwrite := JsonArgBool(ArgumentsJson, 'overwrite', False);
  If Path = '' Then
    Begin
      ErrorText := 'write_image requires a project-relative path.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then
    Exit;
  Resolved := ExpandResolvedPath(Resolved);
  Relative := ImageProjectRelative(Resolved);
  If ImageOutputPathRefused(Relative, ErrorText) Then
    Exit;
  If SymlinkLeavesProject(Resolved) Then
    Begin
      ErrorText := 'Refusing a symbolic link that leaves the project.';
      Exit;
    End;
  If ImageDestinationBlocked(Resolved, Overwrite, ErrorText) Then
    Exit;
  If Not ImageExtensionMime(Resolved, ExpectedMime) Then
    Begin
      ErrorText := 'Image path must end in png, jpg, jpeg, webp, or gif.';
      Exit;
    End;
  If ActiveProfileImageDelivery = aidToolPrompt Then
    Begin
      If Not RequestProfileImage(JsonArgString(ArgumentsJson, 'prompt'), JsonArgString(ArgumentsJson, 'size'),
        Image, ErrorText) Then
        Exit;
    End
  Else If Not SelectTurnGeneratedImage(JsonArgString(ArgumentsJson, 'image_id'), Image, ErrorText) Then
    Exit;
  If (Length(Image.Bytes) = 0) Or (Length(Image.Bytes) > AssistantImageMaxFileBytes) Then
    Begin
      ErrorText := 'Generated image is over the size ceiling.';
      If Length(Image.Bytes) = 0 Then
        ErrorText := 'Generated image has no bytes.';
      Exit;
    End;
  If Not MeasureStillImage(Image.Bytes, SniffedMime, Width, Height) Then
    Begin
      ErrorText := 'Generated image bytes are not a still image.';
      Exit;
    End;
  If SniffedMime <> ExpectedMime Then
    Begin
      ErrorText := 'Image bytes do not match the file extension.';
      Exit;
    End;
  Image.Mime := SniffedMime;
  Image.Width := Width;
  Image.Height := Height;
  If Not PublishImageBytes(Resolved, Image.Bytes, Overwrite, ErrorText) Then
    Exit;
  ResultText := GeneratedImageResultText(Relative, Image);
  Result := True;
End;

Function ExecuteAssistantTool(Const ToolName, ArgumentsJson: String; Out ResultText: String;
  Out ErrorText: String; Out ImageRefs: TAssistantImageRefArray): Boolean; Forward;

Function ExecuteAssistantToolForMode(Const ToolName, ArgumentsJson: String; Mode: TAssistantMode;
  Out ResultText: String; Out ErrorText: String; Out ImageRefs: TAssistantImageRefArray): Boolean;
Var
  Name, Path, ResolvedPath, TargetIdentity: String;
  Function CheckTarget: Boolean;
  Begin
    Result := True;
    If AssistantTarget.Kind<>atkPackage Then Exit;
    If Name='add_unit_to_project' Then
      Begin
        ErrorText := 'Package membership is managed in the Lazarus package editor.';
        Exit(False);
      End;
    If (Name='write_file') Or (Name='replace_in_file') Or (Name='ensure_form_component') Or
      (Name='write_markdown') Or (Name='update_markdown') Or (Name='delete_path') Or (Name='rename_path') Then
      Begin
        Path := JsonArgString(ArgumentsJson, 'path');
        If Name = 'rename_path' Then
          Begin
            Result := ResolveProjectPath(Path, ResolvedPath, ErrorText);
            If Result Then Result := AssistantTarget.AllowsWrite(ResolvedPath);
            If Result Then
              Begin
                Path := JsonArgString(ArgumentsJson, 'new_path');
                Result := ResolveProjectPath(Path, ResolvedPath, ErrorText);
              End;
          End
        Else
          Result := ResolveProjectPath(Path, ResolvedPath, ErrorText);
        If Result Then Result := AssistantTarget.AllowsWrite(ResolvedPath);
        If Not Result And (ErrorText='') Then ErrorText := AssistantTarget.ScopeRefusal('write', Path);
      End;
  End;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  ImageRefs := Nil;
  Name := LowerCase(Trim(ToolName));
  GAssistantToolMode := Mode;
  { Not registered for this turn. A hallucinated name is unknown and writes nothing. }
  If (Name = 'write_image') And (Not AssistantTurnOffersImageOutput(Mode)) Then
    Begin
      ErrorText := 'Unknown tool: write_image';
      Exit;
    End;
  If Not ToolAllowedInMode(Name, Mode) Then
    Begin
      ErrorText := Format('Tool "%s" is not available in %s mode.',
        [ToolName, AssistantModeToStr(Mode)]);
      Exit;
    End;
  TargetIdentity := AssistantTarget.Identity;
  { Refuse a Markdown editor path before scope checks or an Ask dialog. }
  If MarkdownEditorToolRefused(Name, ArgumentsJson, ErrorText) Then Exit;
  If Not CheckTarget Then Exit;
  If Not ApproveToolIfNeeded(Name, ArgumentsJson, ErrorText) Then
    Exit;
  If TargetIdentity <> AssistantTarget.Identity Then
    Begin
      ErrorText := 'Assistant target changed during approval.';
      Exit;
    End;
  If Not CheckTarget Then Exit;
  Result := ExecuteAssistantTool(ToolName, ArgumentsJson, ResultText, ErrorText, ImageRefs);
End;

Function ExecuteAssistantToolForMode(Const ToolName, ArgumentsJson: String; Mode: TAssistantMode;
  Out ResultText: String; Out ErrorText: String): Boolean;
Var
  ImageRefs: TAssistantImageRefArray;
Begin
  Result := ExecuteAssistantToolForMode(ToolName, ArgumentsJson, Mode, ResultText, ErrorText, ImageRefs);
End;

Function SymlinkLeavesProject(Const Resolved: String): Boolean;
Var
  Physical: String;
Begin
  Result := False;
  If Not FileIsSymlink(Resolved) Then Exit;
  Physical := GetPhysicalFilename(Resolved, pfeEmpty);
  Result := (Physical = '') Or Not IsPathUnderRoot(ProjectRootPath, Physical);
End;

Function ToolReadImage(Const ArgumentsJson: String; Out ResultText, ErrorText: String;
  Out ImageRefs: TAssistantImageRefArray): Boolean;
Var
  Path, Resolved, Name: String;
  Stored: TAssistantStoredImage;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  ImageRefs := Nil;
  Path := JsonArgString(ArgumentsJson, 'path');
  If Trim(Path) = '' Then
    Begin
      ErrorText := 'read_image requires path.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then Exit;
  If SymlinkLeavesProject(Resolved) Then
    Begin
      ErrorText := 'Refusing a symbolic link that leaves the project.';
      Exit;
    End;
  If Not FileExistsUTF8(Resolved) Or DirectoryExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'Image file was not found.';
      Exit;
    End;
  If Not StoreAssistantImageFromFile(ProjectRootPath, Resolved, Stored, ErrorText) Then Exit;
  Name := Stored.OriginalName;
  If Name = '' Then Name := ExtractFileName(Resolved);
  ResultText := Name + ', ' + IntToStr(Stored.Width) + ' x ' + IntToStr(Stored.Height) + ', ' + Stored.Id;
  SetLength(ImageRefs, 1);
  ImageRefs[0] := ImageRefFromStored(Stored);
  Result := True;
End;

Function ExecuteAssistantTool(Const ToolName, ArgumentsJson: String; Out ResultText: String;
  Out ErrorText: String; Out ImageRefs: TAssistantImageRefArray): Boolean;
Var
  Name: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  ImageRefs := Nil;
  Name := LowerCase(Trim(ToolName));
  WorkflowLogger.Info('AssistantTools', 'Execute ' + Name);
  If Name = 'read_file' Then
    Result := ToolReadFile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'read_image' Then
    Result := ToolReadImage(ArgumentsJson, ResultText, ErrorText, ImageRefs)
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
  Else If Name = 'write_image' Then
    Result := ToolWriteImage(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'write_file' Then
    Result := ToolWriteFile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'replace_in_file' Then
    Result := ToolReplaceInFile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'run_git' Then
    Result := ToolRunGit(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'run_compile' Then
    Result := ToolRunCompile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'run_project' Then
    Result := ToolRunProject(ResultText, ErrorText)
  Else If Name = 'run_tests' Then
    Result := ToolRunTests(ResultText, ErrorText)
  Else If Name = 'delete_path' Then
    Result := ToolDeletePath(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'rename_path' Then
    Result := ToolRenamePath(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'add_unit_to_project' Then
    Result := ToolAddUnitToProject(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'open_file' Then
    Result := ToolOpenFile(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'ensure_form_component' Then
    Result := ToolEnsureFormComponent(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'read_skill' Then
    Result := ToolReadSkill(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'grep' Then
    Result := ToolGrep(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'todo_write' Then
    Result := ToolTodoWrite(ArgumentsJson, ResultText, ErrorText)
  Else If Name = 'spawn_subagent' Then
    ErrorText := 'spawn_subagent must run on the parent session actor.'
  Else
    ErrorText := 'Unknown tool: ' + ToolName;
End;

Initialization

GActivePlanRelative := '';
GLastCompileSeq := 0;
GLastCompileClean := False;
GLastCompileLog := '';
GProjectStructureDirty := False;
GQuietIdeDepth := 0;
GSavedCheckFilesOnDisk := True;

End.
