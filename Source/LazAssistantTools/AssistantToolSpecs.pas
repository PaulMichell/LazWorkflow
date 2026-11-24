Unit AssistantToolSpecs;

{ One declarative tool table. Names are the catalogue spellings from the harness
  review. Wire units render this table; they do not keep a second catalogue.
  The rows are built once, lazily, on first use.
  (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The table is one record per tool
  so a wire format cannot drift from another. Splitting the rows would hide the
  catalogue. Reviewed 2026-11-24. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantConversation, AssistantCapabilities;

Type
  { Which broker scopes and adapter flags offer the tool. brNone is native-only. }
  TAssistantBrokerRole = (brNone, brBase, brInspect, brDeclaration, brSymbols, brChanges, brChangeWrite,
    brRename, brRenameWrite, brMutate, brMarkdown, brBuild, brTest, brGitRead, brGitWrite, brPlans, brSetPlan,
    brTodo, brProject, brCommand, brRunProject, brOpen);
  TAssistantToolSpec = Record
    Name: String;
    Description: String;
    { Used instead of Description when the broker catalogue is rendered. Empty keeps Description. }
    BrokerDescription: String;
    { Appended to the broker description. May contain note tokens such as SaveNote. }
    BrokerNote: String;
    Schema: String;
    Modes: Set Of TAssistantMode;
    Role: TAssistantBrokerRole;
    IdeThread: Boolean;
    { When true, the tool is withheld unless the offer delivers Capability. }
    Gated: Boolean;
    Capability: TAssistantCapability;
  End;
  TAssistantToolRenderNotes = Record
    SaveNote, WriteNote, ReadSource, SaveTool: String;
    CommandMaxSeconds: Integer;
  End;
  TAssistantBrokerOffer = Record
    Scope: TAssistantWriteScope;
    Mode: TAssistantMode;
    InspectFiles, Declaration, Symbols, ChangeSets, Rename, Markdown, Build, Test, Git, Commands, RunProject,
      OpenEditors, Subagents, ImageOutput: Boolean;
  End;

Function FindAssistantToolSpec(Const Name: String; Out Spec: TAssistantToolSpec): Boolean;
Function AssistantToolNeedsIdeThread(Const Name: String): Boolean;
Function AssistantToolInMode(Const Name: String; Mode: TAssistantMode): Boolean;
Procedure CollectBrokerToolNames(Const Offer: TAssistantBrokerOffer; Names: TStrings);
Function EmptyToolRenderNotes: TAssistantToolRenderNotes;

Implementation

Uses
  AssistantGit;

Const
  EmptySchema = '{"type":"object","properties":{},"required":[]}';
  ListSchema = '{"type":"object","properties":{"path":{"type":"string","description":"Project-relative directory (empty = project root)"}},' +
    '"required":[]}';

Function EmptyToolRenderNotes: TAssistantToolRenderNotes;
Begin
  Result.SaveNote := '';
  Result.WriteNote := '';
  Result.ReadSource := '';
  Result.SaveTool := '';
  Result.CommandMaxSeconds := 600;
End;

{ One list, built once. Native callers pass an explicit name list; order there is the list, not this sequence. }
Var
  BuiltTools: Array Of TAssistantToolSpec;
  ToolsReady: Boolean;
  ToolLock: TRTLCriticalSection;

Procedure AddBuiltTool(Const Spec: TAssistantToolSpec);
Begin
  SetLength(BuiltTools, Length(BuiltTools) + 1);
  BuiltTools[High(BuiltTools)] := Spec;
End;

{ Built once. A new row is another AddBuiltTool call; there is no separate count. }
Procedure EnsureTools;
Var
  Spec: TAssistantToolSpec;
Begin
  If ToolsReady Then Exit;
  EnterCriticalSection(ToolLock);
  Try
    If ToolsReady Then Exit;
  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'read_skill';
        Spec.Description := 'Load the full body of an installed SKILL.md by name. A file that was not added is not a skill.';
        Spec.Schema := '{"type":"object","properties":{"name":{"type":"string","description":"Skill directory name, e.g. free-pascal-engineer"}},' +
          '"required":["name"]}';
        Spec.Modes := [amInspect, amDocument, amPlan, amBuild];
        Spec.Role := brNone;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'grep';
        Spec.Description := 'Search project text files; return path:line:text. Prefer before many read_file calls. ' +
          'path may be a directory or a single file. glob accepts .pas, *.pas, and *.{pas,lfm}. ' +
          'A pattern containing | is treated as a regular expression.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"pattern":{"type":"string","description":"Text or regex to find"},' +
          '"query":{"type":"string","description":"Alias of pattern"},' +
          '"path":{"type":"string","description":"Project-relative directory or file (empty = project root)"},' +
          '"glob":{"type":"string","description":"Optional filter: .pas, *.pas, or *.{pas,lfm,sql}"},' +
          '"regex":{"type":"boolean","description":"Treat pattern as a regular expression (default false; auto if pattern contains |)"},' +
          '"max_matches":{"type":"integer","description":"Max matches to return (default 50)"}},"required":[]}';
        Spec.Modes := [amInspect, amDocument, amPlan, amBuild];
        Spec.Role := brNone;
        { The disk walk stays on the worker. Open buffers are snapshotted in a short IDE-thread pass. }
        Spec.IdeThread := False;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'read_file';
        Spec.Description := 'Read a text file under the active Lazarus project. Uses the open editor buffer when the file is open, ' +
          'otherwise disk. Page with start_line plus end_line or limit. If end_line is smaller than start_line it is a line count. ' +
          'After truncation continue from the suggested line.';
        Spec.BrokerDescription := '{ReadSource}Page with start_line plus end_line or limit. A call with only path returns the text and ' +
          'a revision token for a later edit. include_text false returns path, revision and line_count.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative or absolute file path"},' +
          '"start_line":{"type":"integer","description":"1-based first line to include (default 1)"},' +
          '"offset":{"type":"integer","description":"Alias of start_line"},' +
          '"end_line":{"type":"integer","description":"1-based last line, or a line count if smaller than start_line"},' +
          '"limit":{"type":"integer","description":"Max lines from start_line (preferred when paging by count)"},' +
          '"max_chars":{"type":"integer","description":"Optional max characters to return from the selected range"},' +
          '"include_text":{"type":"boolean","description":"When false, return path, revision and line_count only"}},"required":["path"]}';
        Spec.Modes := [amInspect, amDocument, amPlan, amBuild];
        Spec.Role := brBase;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'read_image';
        Spec.Description := 'Read a project image into the next model turn. Resolves a project-relative path in the sandbox, ' +
          'refuses paths outside the root, symbolic links that leave the project, and files over the image limits, then copies the ' +
          'accepted still image into the conversation store. The result text is the name, dimensions, and id only. The picture is ' +
          'attached to the following user message, not written into the result. A PNG is not a text edit: do not use write_file or ' +
          'replace_in_file on images.';
        Spec.Schema := '{"type":"object","properties":{"path":{"type":"string","description":' +
          '"Project-relative or absolute image path inside the project root"}},"required":["path"]}';
        Spec.Modes := [amInspect, amDocument, amPlan, amBuild];
        Spec.Role := brInspect;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'list_directory';
        Spec.Description := 'List files and subdirectories under a project folder.';
        Spec.Schema := ListSchema;
        Spec.Modes := [amInspect, amDocument, amPlan, amBuild];
        Spec.Role := brInspect;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'open_markdown';
        Spec.Description := 'Open a Markdown document in an Assistant Markdown viewer window.';
        Spec.BrokerDescription := 'Open a project Markdown file in its live viewer window, so the user can see it. During a plan run ' +
          'the viewer is not opened and the plan summary updates instead. Does not change the file.';
        Spec.Schema := '{"type":"object","properties":{"path":{"type":"string","description":"Path to a .md file under the project"}},' +
          '"required":["path"]}';
        Spec.Modes := [amInspect, amDocument, amPlan, amBuild];
        Spec.Role := brOpen;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'get_project_info';
        Spec.Description := 'Return the active project path, main file, and project info file.';
        Spec.BrokerDescription := 'Describe the selected Lazarus project or package and relevant open buffer.';
        Spec.Schema := EmptySchema;
        Spec.Modes := [amInspect, amDocument, amPlan, amBuild];
        Spec.Role := brBase;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'search_in_project';
        Spec.Description := 'Search project source/text files (same engine as grep). Unsaved editor buffers are preferred over disk. ' +
          'Inspect and Build may call it. Returns path:line:text.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"query":{"type":"string","description":"Text to find"},' +
          '"path":{"type":"string","description":"Project-relative directory or file (empty = project root)"},' +
          '"glob":{"type":"string","description":"Optional filter: .pas, *.pas, or *.{pas,lfm} (default: common text types)"},' +
          '"max_matches":{"type":"integer","description":"Max matches to return (default 50)"}},"required":["query"]}';
        Spec.Modes := [amInspect, amDocument, amBuild];
        Spec.Role := brInspect;
        { Same split as grep: the walk is not IdeThread; the editor overlay is. }
        Spec.IdeThread := False;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'open_file';
        Spec.Description := 'Open a project source file in the Lazarus source editor. Does not modify the file.';
        Spec.BrokerDescription := 'Open a project file in the Lazarus source editor and bring it forward, so the user can see it. ' +
          'Reuses an open tab. Markdown files use open_markdown instead. Does not change the file.';
        Spec.Schema := '{"type":"object","properties":{"path":{"type":"string","description":"Project-relative file path"}},' +
          '"required":["path"]}';
        Spec.Modes := [amInspect, amDocument, amBuild];
        Spec.Role := brOpen;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'find_declaration';
        Spec.Description := 'Resolve a Pascal identifier from the already open buffer. Read-only. Positions are 1-based. ' +
          'Columns are UTF-8 bytes. No editor movement and no edit revision.';
        Spec.BrokerDescription := 'Resolve a Pascal identifier using Lazarus CodeTools and the selected target configuration. ' +
          'First read the source and supply its revision. Coordinates are 1-based lines and UTF-8 byte columns. Read-only.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative Pascal source path"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when the broker checks the buffer."},' +
          '"line":{"type":"integer","minimum":1,"description":"1-based line"},' +
          '"column":{"type":"integer","minimum":1,"description":"1-based UTF-8 byte column"}},' +
          '"required":["path","line","column"]}';
        Spec.Modes := [amInspect, amBuild];
        Spec.Role := brDeclaration;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'symbol_context';
        Spec.Description := 'Return the CodeTools hint and nearby source for a Pascal identifier. Read-only. Positions are 1-based. ' +
          'Columns are UTF-8 bytes. No editor movement and no edit revision.';
        Spec.BrokerDescription := 'Get a CodeTools hint and bounded source for a Pascal symbol at this revision. Read-only. ' +
          'Positions are 1-based UTF-8 byte columns.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative Pascal source path"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when the broker checks the buffer."},' +
          '"line":{"type":"integer","minimum":1,"description":"1-based line"},' +
          '"column":{"type":"integer","minimum":1,"description":"1-based UTF-8 byte column"}},' +
          '"required":["path","line","column"]}';
        Spec.Modes := [amInspect, amBuild];
        Spec.Role := brSymbols;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'find_references';
        Spec.Description := 'Find Pascal references in an explicit search_paths list of 1 to 32 project files. ' +
          'A truncated or partial search is not whole-project coverage. Read-only. Positions are 1-based. ' +
          'Columns are UTF-8 bytes. No editor movement and no edit revision.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative Pascal source path"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when the broker checks the buffer."},' +
          '"line":{"type":"integer","minimum":1,"description":"1-based line"},' +
          '"column":{"type":"integer","minimum":1,"description":"1-based UTF-8 byte column"},' +
          '"search_paths":{"type":"array","minItems":1,"maxItems":32,"items":{"type":"string"},' +
          '"description":"1 to 32 project files. A truncated or partial search is not whole-project coverage."},' +
          '"max_results":{"type":"integer","minimum":1,"maximum":200,"description":"Optional result cap. Default 100."}},' +
          '"required":["path","line","column","search_paths"]}';
        Spec.Modes := [amInspect, amBuild];
        Spec.Role := brSymbols;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'todo_write';
        Spec.Description := 'Replace or merge the ephemeral in-turn todo list (dies with the turn; not plan Status:). ' +
          'status: pending, in_progress, completed, cancelled.';
        Spec.BrokerDescription := 'Replace or update this turn''s short checklist. The whole list is returned. It ends with the turn ' +
          'and is not a plan Status: line. status is pending, in_progress, completed or cancelled. merge true updates items by id.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"merge":{"type":"boolean","description":"If true, upsert by id; if false, replace the list (default false)"},' +
          '"todos":{"type":"array","description":"Todo items","items":{"type":"object","properties":{' +
          '"id":{"type":"string"},"content":{"type":"string"},"status":{"type":"string"}}}}},"required":["todos"]}';
        Spec.Modes := [amPlan, amBuild];
        Spec.Role := brTodo;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'write_markdown';
        Spec.Description := 'Create or overwrite a Markdown file under the project (prefer Documents/). Opens a live Markdown window. ' +
          'Use for new or full rewrites of plans. Rejects a Status: line under a ## heading. A ### heading without Status is a note, ' +
          'not a todo. In a Git repository, Status: complete is refused until run_git commit has succeeded in this turn; commit the ' +
          'plan file after that change. Without a repository, complete needs no commit.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative .md path (default Documents/Plan.md)"},' +
          '"content":{"type":"string","description":"Full Markdown body to write"},' +
          '"open":{"type":"boolean","description":"Open live viewer after write (default true). Ignored during a plan run."}},' +
          '"required":["content"]}';
        Spec.Modes := [amDocument, amPlan, amBuild];
        Spec.Role := brMarkdown;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'update_markdown';
        Spec.Description := 'Exact text replacement in a project Markdown file (surgical edit). Prefer this over rewrite when ' +
          'changing Status: lines or a single section. Rejects a Status: line under a ## heading. A ### heading without Status stays ' +
          'a note, not a todo. In a Git repository, Status: complete is refused until run_git commit has succeeded in this turn; ' +
          'commit the plan file after that change. Without a repository, complete needs no commit.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative .md path (default: active plan)"},' +
          '"old_text":{"type":"string","description":"Exact text to find"},' +
          '"new_text":{"type":"string","description":"Replacement text"},' +
          '"replace_all":{"type":"boolean","description":"Replace every match (default false)"},' +
          '"open":{"type":"boolean","description":"Open live viewer after update (default true). Ignored during a plan run."}},' +
          '"required":["old_text","new_text"]}';
        Spec.Modes := [amDocument, amPlan, amBuild];
        Spec.Role := brMarkdown;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'list_plans';
        Spec.Description := 'List plans registered in the project .assistant settings. Missing files are dropped. ' +
          'The project folders are not scanned.';
        Spec.Schema := EmptySchema;
        Spec.Modes := [amPlan, amBuild];
        Spec.Role := brPlans;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'get_active_plan';
        Spec.Description := 'Return the canonical active plan path for this project (from .assistant/config.json).';
        Spec.Schema := EmptySchema;
        Spec.Modes := [amPlan, amBuild];
        Spec.Role := brPlans;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'set_active_plan';
        Spec.Description := 'Set the canonical active plan Markdown path for this project.';
        Spec.Schema := '{"type":"object","properties":{"path":{"type":"string","description":"Project-relative .md path"}},' +
          '"required":["path"]}';
        Spec.Modes := [amPlan, amBuild];
        Spec.Role := brSetPlan;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'read_markdown_section';
        Spec.Description := 'Read one Markdown section. path is optional and defaults to the active plan. heading is an ATX heading ' +
          'such as ### 3.2. Returns that section up to the next heading of the same or a higher level. A ### item is one block. ' +
          'A ## heading includes its items.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative Markdown path. Omit for the active plan."},' +
          '"heading":{"type":"string","description":"ATX heading, for example ### 3.2"}},"required":["heading"]}';
        Spec.Modes := [amPlan, amBuild];
        Spec.Role := brPlans;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'write_file';
        Spec.Description := 'Create or overwrite a real project file. Never create empty files or ApiProbe/scratch/temp units — use ' +
          'search_in_project, list_directory, and read_file to discover APIs. Prefer replace_in_file for small edits. Creating a file ' +
          'that does not exist writes it. Replacing an existing buffer requires the revision token from read_file.';
        Spec.BrokerNote := ' {SaveNote}{WriteNote}';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative path e.g. Source/Foo.pas"},' +
          '"content":{"type":"string","description":"Full non-empty contents (reject empty/probe files)"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when the file already exists."},' +
          '"open":{"type":"boolean","description":"A Markdown path opens in the Assistant Markdown viewer (default false); use open_markdown. A source file is never opened as a tab."},' +
          '"add_to_project":{"type":"boolean","description":"Add Pascal unit to the active project (default true only for non-empty units)"}},' +
          '"required":["path","content"]}';
        Spec.Modes := [amDocument, amPlan, amBuild];
        Spec.Role := brMutate;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'replace_in_file';
        Spec.Description := 'Exact text replacement in a project source/text file. old_text must match the open editor buffer when ' +
          'the file is open (same source as read_file), including whitespace; keep it small and unique. Saves the buffer to disk so ' +
          'Review/Git see the edit. An existing buffer requires the revision token from read_file.';
        Spec.BrokerNote := ' {SaveNote}{WriteNote}';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative file path"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when editing an existing buffer."},' +
          '"old_text":{"type":"string","description":"Exact text to find"},' +
          '"new_text":{"type":"string","description":"Replacement text"},' +
          '"replace_all":{"type":"boolean","description":"Replace every match (default false)"},' +
          '"open":{"type":"boolean","description":"A Markdown path opens in the Assistant Markdown viewer (default false); use open_markdown. A source file is never opened as a tab."}},' +
          '"required":["path","old_text","new_text"]}';
        Spec.Modes := [amDocument, amPlan, amBuild];
        Spec.Role := brMutate;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'run_compile';
        Spec.Description := 'Compile the work target. A project or package uses that manifest. A folder compiles every .lpk under ' +
          'the folder, or every .lpi when the folder has no package. It does not compile the IDE active project. Default is quiet ' +
          'lazbuild. Set ui=true only for a final IDE Messages check of a project or package. Pass job_id to poll a build already ' +
          'started through this tool; detail manifest returns the observed-input list.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"kind":{"type":"string","description":"compile (default) or build (rebuild-all when quiet)"},' +
          '"ui":{"type":"boolean","description":"If true, use IDE DoBuildProject and Messages window (default false = quiet lazbuild)"},' +
          '"package":{"type":"string","description":"Optional project-relative .lpk when the target is a folder"},' +
          '"job_id":{"type":"string","description":"Poll this build instead of starting one"},' +
          '"detail":{"type":"string","description":"manifest to include the observed-input list when polling"}},"required":[]}';
        Spec.Modes := [amBuild];
        Spec.Role := brBuild;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'add_unit_to_project';
        Spec.Description := 'Register an existing Pascal unit file with the active Lazarus project (.lpi).';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative .pas/.pp path"},' +
          '"add_to_uses":{"type":"boolean","description":"Also add to main uses clause when possible (default false)"}},' +
          '"required":["path"]}';
        Spec.Modes := [amBuild];
        Spec.Role := brProject;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'ensure_form_component';
        Spec.Description := 'Add or update a published form component in BOTH the .pas unit and matching .lfm. Required when adding ' +
          'TTimer, TButton, etc. so events fire. Prefer this over hand-editing LFM alone.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Form unit path (.pas or .lfm), e.g. unit1.pas"},' +
          '"name":{"type":"string","description":"Component name, e.g. ColorTimer"},' +
          '"class_name":{"type":"string","description":"Component class, e.g. TTimer"},' +
          '"properties":{"type":"string","description":"Optional JSON object of LFM properties, e.g. {\"Interval\":1000,\"OnTimer\":\"ColorTimerTimer\",\"Enabled\":true}. TTimer Interval is milliseconds (1000 = 1 second)."},' +
          '"event_method":{"type":"string","description":"Optional event handler method name to declare/implement (e.g. ColorTimerTimer). Defaults from On* properties when omitted."},' +
          '"uses_unit":{"type":"string","description":"Optional unit to add to interface Uses (e.g. ExtCtrls for TTimer)"}},' +
          '"required":["path","name","class_name"]}';
        Spec.Modes := [amBuild];
        Spec.Role := brProject;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'run_project';
        Spec.Description := 'Start the active project executable directly. No shell and no debugger. The executable must already be ' +
          'built and must stay inside the project root.';
        Spec.Schema := EmptySchema;
        Spec.Modes := [amBuild];
        Spec.Role := brRunProject;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'run_tests';
        Spec.Description := 'Run the enabled test command for this target. Arguments are passed directly, not through a shell. The ' +
          'executable and working directory must stay inside the project root. When a build job id is supplied, run that build''s ' +
          'configured command and return a job to poll with job_id. only, memory_check, defines and gui apply only to ' +
          'Tests/RunAssistantTests.pas.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"build_job_id":{"type":"string","description":"Successful current build whose test command to run"},' +
          '"job_id":{"type":"string","description":"Poll this test job instead of starting one"},' +
          '"only":{"type":"array","items":{"type":"string"},"description":"Test program names, passed as --only"},' +
          '"memory_check":{"type":"string","enum":["none","heaptrc","valgrind"]},"defines":{"type":"array","items":{"type":"string"}},' +
          '"gui":{"type":"boolean","description":"Pass --gui so GUI test programs build and run"}},"required":[]}';
        Spec.Modes := [amBuild];
        Spec.Role := brTest;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'run_command';
        Spec.Description := 'Run one program and its arguments for a one-off check. No shell is used. Python and shells are refused. ' +
          'A saved repeatable test is an InstantFPC program in Tests/, not under Source/. Invoke it as instantfpc plus the script path.';
        Spec.BrokerDescription := 'Run one program with its arguments, for a one-off check. No shell is used, and Python and shells ' +
          'are refused. The program may be a name on PATH or a path. The working directory defaults to the project root and must stay ' +
          'inside it. Build mode only. Over MCP the call returns when the program ends. Called directly it returns a job_id to poll ' +
          'with command_status. timeout_seconds is 1 to {CommandMax}, default 600.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"program":{"type":"string","description":"Program name on PATH, or a path. Example: instantfpc."},' +
          '"arguments":{"type":"array","items":{"type":"string"},"description":"Arguments passed directly, not through a shell."},' +
          '"working_directory":{"type":"string","description":"Optional. Defaults to the project directory and must stay inside it."},' +
          '"timeout_seconds":{"type":"integer","description":"1 to 3600. Default 600."}},"required":["program"]}';
        Spec.Modes := [amBuild];
        Spec.Role := brCommand;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'delete_path';
        Spec.Description := 'Delete one file, symbolic link, or empty directory inside the project root. Refuses the project root, ' +
          'Git metadata, and the project or package file. Does not use a shell.';
        Spec.Schema := '{"type":"object","properties":{"path":{"type":"string","description":' +
          '"Project-relative or absolute path inside the project root"}},"required":["path"]}';
        Spec.Modes := [amBuild];
        Spec.Role := brProject;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'rename_path';
        Spec.Description := 'Rename or move a file or directory inside the project root. Both paths must stay in the project. ' +
          'Refuses the project root, Git metadata, and the project or package file. Does not use a shell.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Existing project path"},' +
          '"new_path":{"type":"string","description":"New path inside the project root"}},"required":["path","new_path"]}';
        Spec.Modes := [amBuild];
        Spec.Role := brProject;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'run_git';
        Spec.Description := AssistantGitDescription;
        Spec.Schema := AssistantGitSchema;
        Spec.Modes := [amInspect, amBuild];
        Spec.Role := brGitRead;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'stage_patch';
        Spec.Description := AssistantStagePatchDescription;
        Spec.Schema := AssistantStagePatchSchema;
        Spec.Modes := [amBuild];
        Spec.Role := brGitWrite;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'spawn_subagent';
        Spec.Description := 'Start a depth-1 child agent and wait for its summary. Parent only; a child cannot spawn. At most 3 ' +
          'children run at once; extra spawn_subagent calls wait for a free slot. Kinds: explore (read-only research), plan ' +
          '(Markdown only), general-purpose (parent mode tools), pascal-naming, pascal-structure, pascal-review (read-only lenses). ' +
          'Use for parallel explore or Review lenses. Do not spawn for syntax (use run_compile) or every edit.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"kind":{"type":"string","description":"explore | plan | general-purpose | pascal-naming | pascal-structure | pascal-review"},' +
          '"subagent_type":{"type":"string","description":"Alias of kind"},' +
          '"title":{"type":"string","description":"Short label shown in the parent trace"},' +
          '"description":{"type":"string","description":"Alias of title"},' +
          '"prompt":{"type":"string","description":"Full instructions for the child"},' +
          '"files":{"type":"string","description":"Optional changed-file list the child should focus on"}},"required":["prompt"]}';
        Spec.Modes := [amInspect, amDocument, amPlan, amBuild];
        Spec.Role := brNone;
        Spec.Gated := True;
        Spec.Capability := acSubagents;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'write_image';
        Spec.Description := 'Draw one still image with this connection''s image model and save it. It is not a copy of a read_image ' +
          'attachment. The path may omit an extension. The image model chooses the format. A mismatched extension is saved with the ' +
          'matching extension instead of failing.';
        Spec.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative path. Omit the extension to let the image model choose the format."},' +
          '"prompt":{"type":"string","description":"What to draw."},' +
          '"overwrite":{"type":"boolean","description":"Replace an existing file. Default false."},' +
          '"shape":{"type":"string","description":"Short hint such as 1:1. Omit it to let the image model choose."}},' +
          '"required":["path","prompt"]}';
        Spec.Modes := [amDocument, amPlan, amBuild];
        Spec.Role := brNone;
        Spec.Gated := True;
        Spec.Capability := acImageOutput;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'open_buffer';
        Spec.Description := 'Get an edit revision for an existing project text file: the open editor''s text when it is open, ' +
          'otherwise the file on disk. Does not open an editor tab. Returns the text and a revision unless include_text is false. ' +
          'Does not create or save files.';
        Spec.Schema := '{"type":"object","properties":{"path":{"type":"string"},"include_text":{"type":"boolean"}},' +
          '"required":["path"]}';
        Spec.Role := brInspect;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'prepare_changes';
        Spec.Description := 'Prepare one reviewed change set for 1-16 project text files, open in the editor or not. Read each ' +
          'buffer first and supply its revision and complete proposed text. Does not edit or save; returns a one-use change_set_id.';
        Spec.Schema := '{"type":"object","properties":{"changes":{"type":"array","minItems":1,"maxItems":16,"items":{"type":"object",' +
          '"properties":{"path":{"type":"string"},"revision":{"type":"string"},"text":{"type":"string"}},' +
          '"required":["path","revision","text"]}}},"required":["changes"]}';
        Spec.Role := brChanges;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'change_status';
        Spec.Description := 'Get an in-memory change-set receipt with per-file apply/recovery outcomes. Without an ID, lists ' +
          'receipts for this project. Receipts survive new chats/runs until the assistant panel closes; they are not durable.';
        Spec.Schema := '{"type":"object","properties":{"change_set_id":{"type":"string"}},"required":[]}';
        Spec.Role := brChanges;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'apply_changes';
        Spec.Description := 'Review and apply an exact prepared multi-editor change set in Build. Validates every source and editor ' +
          'stamp before each write. On success returns each file''s new revision and changed line range, not the buffer text.';
        Spec.BrokerNote := ' {SaveNote}';
        Spec.Schema := '{"type":"object","properties":{"change_set_id":{"type":"string"}},"required":["change_set_id"]}';
        Spec.Role := brChangeWrite;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'revert_changes';
        Spec.Description := 'Review and restore confirmed edits from a retained change-set receipt in Build. Skips changed, closed ' +
          'or unverified editors; returns partial outcomes instead of overwriting user edits. Native Undo remains per editor.';
        Spec.BrokerNote := ' {SaveNote}';
        Spec.Schema := '{"type":"object","properties":{"change_set_id":{"type":"string"}},"required":["change_set_id"]}';
        Spec.Role := brChangeWrite;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'preview_local_rename';
        Spec.Description := 'Preview a routine-local variable or constant rename using CodeTools. Requires a current buffer ' +
          'revision; coordinates are 1-based UTF-8 bytes. Returns exact changes and a one-use preview_id without editing.';
        Spec.Schema := '{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"},' +
          '"line":{"type":"integer","minimum":1},"column":{"type":"integer","minimum":1},"new_name":{"type":"string"}},' +
          '"required":["path","revision","line","column","new_name"]}';
        Spec.Role := brRename;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'apply_local_rename';
        Spec.Description := 'Apply the exact previously reviewed local rename preview in Build mode. Revalidates source and ' +
          'CodeTools results after approval. Consumes preview_id and returns the new revision and changed line range.';
        Spec.BrokerNote := ' {SaveNote}';
        Spec.Schema := '{"type":"object","properties":{"preview_id":{"type":"string"}},"required":["preview_id"]}';
        Spec.Role := brRenameWrite;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'save_file';
        Spec.Description := '{SaveTool}{WriteNote}';
        Spec.Schema := '{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"}},' +
          '"required":["path","revision"]}';
        Spec.Role := brMutate;
        Spec.IdeThread := True;
  AddBuiltTool(Spec);

  Spec := Default(TAssistantToolSpec);
        Spec.Name := 'command_status';
        Spec.Description := 'Poll a run_command job by its job_id: done, outcome (running, exited, failed or cancelled), exit_code, ' +
          'any error, and the last 48000 characters of output.';
        Spec.Schema := '{"type":"object","properties":{"job_id":{"type":"string"}},"required":["job_id"]}';
        Spec.Role := brCommand;
  AddBuiltTool(Spec);

    ToolsReady := True;
  Finally
    LeaveCriticalSection(ToolLock);
  End;
End;

Function FindAssistantToolSpec(Const Name: String; Out Spec: TAssistantToolSpec): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  Spec := Default(TAssistantToolSpec);
  EnsureTools;
  For I := 0 To High(BuiltTools) Do
    Begin
      Spec := BuiltTools[I];
      If Spec.Name = Name Then
        Exit(True);
    End;
  Spec := Default(TAssistantToolSpec);
End;

Function AssistantToolNeedsIdeThread(Const Name: String): Boolean;
Var
  Spec: TAssistantToolSpec;
Begin
  Result := FindAssistantToolSpec(Name, Spec) And Spec.IdeThread;
End;

Function AssistantToolInMode(Const Name: String; Mode: TAssistantMode): Boolean;
Var
  Spec: TAssistantToolSpec;
Begin
  Result := FindAssistantToolSpec(Name, Spec) And (Mode In Spec.Modes);
End;

Function CapabilityOffered(Const Spec: TAssistantToolSpec; Const Offer: TAssistantBrokerOffer): Boolean;
Begin
  If Not Spec.Gated Then
    Result := True
  Else If Spec.Capability = acSubagents Then
    Result := Offer.Subagents
  Else If Spec.Capability = acImageOutput Then
    Result := Offer.ImageOutput
  Else
    Result := False;
End;

Function BrokerRoleOffered(Role: TAssistantBrokerRole; Const Offer: TAssistantBrokerOffer): Boolean;
Begin
  Result := False;
  If Offer.Scope = awsNone Then
    Exit;
  Case Role Of
    brNone: Result := False;
    brBase: Result := True;
    brInspect: Result := Offer.InspectFiles;
    brDeclaration: Result := Offer.Declaration;
    brSymbols: Result := Offer.Symbols;
    brChanges: Result := Offer.ChangeSets;
    brChangeWrite: Result := Offer.ChangeSets And (Offer.Scope = awsProject);
    brRename: Result := Offer.Rename;
    brRenameWrite: Result := Offer.Rename And (Offer.Scope = awsProject);
    brMutate: Result := Offer.Scope <> awsReadOnly;
    brMarkdown: Result := (Offer.Scope <> awsReadOnly) And Offer.Markdown;
    brBuild: Result := (Offer.Scope = awsProject) And Offer.Build;
    brTest: Result := (Offer.Scope = awsProject) And Offer.Build And Offer.Test;
    brGitRead: Result := ((Offer.Scope = awsProject) Or (Offer.Scope = awsReadOnly)) And Offer.Git;
    brGitWrite: Result := (Offer.Scope = awsProject) And Offer.Git;
    brPlans: Result := (Offer.Scope = awsMarkdown) Or (Offer.Scope = awsProject);
    brSetPlan: Result := Offer.Scope = awsMarkdown;
    brTodo: Result := (Offer.Scope = awsProject) Or ((Offer.Scope = awsMarkdown) And (Offer.Mode = amPlan));
    brProject: Result := Offer.Scope = awsProject;
    brCommand: Result := (Offer.Scope = awsProject) And Offer.Commands;
    brRunProject: Result := (Offer.Scope = awsProject) And Offer.RunProject;
    brOpen: Result := Offer.OpenEditors;
  End;
End;

Procedure CollectBrokerToolNames(Const Offer: TAssistantBrokerOffer; Names: TStrings);
Const
  Order: Array[0..37] Of String = (
    'get_project_info', 'read_file', 'list_directory', 'read_image', 'search_in_project', 'open_buffer',
    'find_declaration', 'symbol_context', 'find_references', 'prepare_changes', 'change_status', 'apply_changes',
    'revert_changes', 'preview_local_rename', 'apply_local_rename', 'write_file', 'replace_in_file', 'save_file',
    'write_markdown', 'update_markdown', 'run_compile', 'run_tests', 'run_git', 'stage_patch', 'list_plans',
    'get_active_plan', 'read_markdown_section', 'set_active_plan', 'todo_write', 'ensure_form_component',
    'delete_path', 'rename_path', 'add_unit_to_project', 'run_command', 'command_status', 'run_project', 'open_file',
    'open_markdown');
Var
  I: Integer;
  Spec: TAssistantToolSpec;
Begin
  If Not Assigned(Names) Then
    Exit;
  Names.Clear;
  If Offer.Scope = awsNone Then
    Exit;
  For I := 0 To High(Order) Do
    If FindAssistantToolSpec(Order[I], Spec) And BrokerRoleOffered(Spec.Role, Offer) And
      CapabilityOffered(Spec, Offer) Then
      Names.Add(Spec.Name);
  { Same table as Grok. A mode tool with no broker role is still offered, unless its capability is absent. }
  EnsureTools;
  For I := 0 To High(BuiltTools) Do
    Begin
      Spec := BuiltTools[I];
      If (Spec.Role <> brNone) Or Not (Offer.Mode In Spec.Modes) Or Not CapabilityOffered(Spec, Offer) Then
        Continue;
      If Names.IndexOf(Spec.Name) < 0 Then
        Names.Add(Spec.Name);
    End;
End;

Initialization
  InitCriticalSection(ToolLock);

Finalization
  DoneCriticalSection(ToolLock);

End.
