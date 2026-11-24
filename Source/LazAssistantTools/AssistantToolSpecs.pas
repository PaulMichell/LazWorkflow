Unit AssistantToolSpecs;

{ One declarative tool table. Names are the catalogue spellings from the harness
  review. Wire units render this table; they do not keep a second catalogue.
  (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The table is one record per tool
  so a wire format cannot drift from another. Splitting the rows would hide the
  catalogue. Reviewed 2026-11-23. }

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

{ The table is a function so long descriptions stay readable and the order is the broker order.
  Native callers pass an explicit name list; order there is the list, not this sequence. }
Function ToolAt(Index: Integer): TAssistantToolSpec;
Begin
  Result := Default(TAssistantToolSpec);
  Case Index Of
    0:
      Begin
        Result.Name := 'read_skill';
        Result.Description := 'Load the full body of an installed SKILL.md by name. A file that was not added is not a skill.';
        Result.Schema := '{"type":"object","properties":{"name":{"type":"string","description":"Skill directory name, e.g. free-pascal-engineer"}},' +
          '"required":["name"]}';
        Result.Modes := [amInspect, amDocument, amPlan, amBuild];
        Result.Role := brNone;
      End;
    1:
      Begin
        Result.Name := 'grep';
        Result.Description := 'Search project text files; return path:line:text. Prefer before many read_file calls. ' +
          'path may be a directory or a single file. glob accepts .pas, *.pas, and *.{pas,lfm}. ' +
          'A pattern containing | is treated as a regular expression.';
        Result.Schema := '{"type":"object","properties":{' +
          '"pattern":{"type":"string","description":"Text or regex to find"},' +
          '"query":{"type":"string","description":"Alias of pattern"},' +
          '"path":{"type":"string","description":"Project-relative directory or file (empty = project root)"},' +
          '"glob":{"type":"string","description":"Optional filter: .pas, *.pas, or *.{pas,lfm,sql}"},' +
          '"regex":{"type":"boolean","description":"Treat pattern as a regular expression (default false; auto if pattern contains |)"},' +
          '"max_matches":{"type":"integer","description":"Max matches to return (default 50)"}},"required":[]}';
        Result.Modes := [amInspect, amDocument, amPlan, amBuild];
        Result.Role := brNone;
        { The disk walk stays on the worker. Open buffers are snapshotted in a short IDE-thread pass. }
        Result.IdeThread := False;
      End;
    2:
      Begin
        Result.Name := 'read_file';
        Result.Description := 'Read a text file under the active Lazarus project. Uses the open editor buffer when the file is open, ' +
          'otherwise disk. Page with start_line plus end_line or limit. If end_line is smaller than start_line it is a line count. ' +
          'After truncation continue from the suggested line.';
        Result.BrokerDescription := '{ReadSource}Page with start_line plus end_line or limit. A call with only path returns the text and ' +
          'a revision token for a later edit. include_text false returns path, revision and line_count.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative or absolute file path"},' +
          '"start_line":{"type":"integer","description":"1-based first line to include (default 1)"},' +
          '"offset":{"type":"integer","description":"Alias of start_line"},' +
          '"end_line":{"type":"integer","description":"1-based last line, or a line count if smaller than start_line"},' +
          '"limit":{"type":"integer","description":"Max lines from start_line (preferred when paging by count)"},' +
          '"max_chars":{"type":"integer","description":"Optional max characters to return from the selected range"},' +
          '"include_text":{"type":"boolean","description":"When false, return path, revision and line_count only"}},"required":["path"]}';
        Result.Modes := [amInspect, amDocument, amPlan, amBuild];
        Result.Role := brBase;
        Result.IdeThread := True;
      End;
    3:
      Begin
        Result.Name := 'read_image';
        Result.Description := 'Read a project image into the next model turn. Resolves a project-relative path in the sandbox, ' +
          'refuses paths outside the root, symbolic links that leave the project, and files over the image limits, then copies the ' +
          'accepted still image into the conversation store. The result text is the name, dimensions, and id only. The picture is ' +
          'attached to the following user message, not written into the result. A PNG is not a text edit: do not use write_file or ' +
          'replace_in_file on images.';
        Result.Schema := '{"type":"object","properties":{"path":{"type":"string","description":' +
          '"Project-relative or absolute image path inside the project root"}},"required":["path"]}';
        Result.Modes := [amInspect, amDocument, amPlan, amBuild];
        Result.Role := brInspect;
      End;
    4:
      Begin
        Result.Name := 'list_directory';
        Result.Description := 'List files and subdirectories under a project folder.';
        Result.Schema := ListSchema;
        Result.Modes := [amInspect, amDocument, amPlan, amBuild];
        Result.Role := brInspect;
      End;
    5:
      Begin
        Result.Name := 'open_markdown';
        Result.Description := 'Open a Markdown document in an Assistant Markdown viewer window.';
        Result.BrokerDescription := 'Open a project Markdown file in its live viewer window, so the user can see it. During a plan run ' +
          'the viewer is not opened and the plan summary updates instead. Does not change the file.';
        Result.Schema := '{"type":"object","properties":{"path":{"type":"string","description":"Path to a .md file under the project"}},' +
          '"required":["path"]}';
        Result.Modes := [amInspect, amDocument, amPlan, amBuild];
        Result.Role := brOpen;
        Result.IdeThread := True;
      End;
    6:
      Begin
        Result.Name := 'get_project_info';
        Result.Description := 'Return the active project path, main file, and project info file.';
        Result.BrokerDescription := 'Describe the selected Lazarus project or package and relevant open buffer.';
        Result.Schema := EmptySchema;
        Result.Modes := [amInspect, amDocument, amPlan, amBuild];
        Result.Role := brBase;
        Result.IdeThread := True;
      End;
    7:
      Begin
        Result.Name := 'search_in_project';
        Result.Description := 'Search project source/text files (same engine as grep). Unsaved editor buffers are preferred over disk. ' +
          'Inspect and Build may call it. Returns path:line:text.';
        Result.Schema := '{"type":"object","properties":{' +
          '"query":{"type":"string","description":"Text to find"},' +
          '"path":{"type":"string","description":"Project-relative directory or file (empty = project root)"},' +
          '"glob":{"type":"string","description":"Optional filter: .pas, *.pas, or *.{pas,lfm} (default: common text types)"},' +
          '"max_matches":{"type":"integer","description":"Max matches to return (default 50)"}},"required":["query"]}';
        Result.Modes := [amInspect, amDocument, amBuild];
        Result.Role := brInspect;
        { Same split as grep: the walk is not IdeThread; the editor overlay is. }
        Result.IdeThread := False;
      End;
    8:
      Begin
        Result.Name := 'open_file';
        Result.Description := 'Open a project source file in the Lazarus source editor. Does not modify the file.';
        Result.BrokerDescription := 'Open a project file in the Lazarus source editor and bring it forward, so the user can see it. ' +
          'Reuses an open tab. Markdown files use open_markdown instead. Does not change the file.';
        Result.Schema := '{"type":"object","properties":{"path":{"type":"string","description":"Project-relative file path"}},' +
          '"required":["path"]}';
        Result.Modes := [amInspect, amDocument, amBuild];
        Result.Role := brOpen;
        Result.IdeThread := True;
      End;
    9:
      Begin
        Result.Name := 'find_declaration';
        Result.Description := 'Resolve a Pascal identifier from the already open buffer. Read-only. Positions are 1-based. ' +
          'Columns are UTF-8 bytes. No editor movement and no edit revision.';
        Result.BrokerDescription := 'Resolve a Pascal identifier using Lazarus CodeTools and the selected target configuration. ' +
          'First read the source and supply its revision. Coordinates are 1-based lines and UTF-8 byte columns. Read-only.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative Pascal source path"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when the broker checks the buffer."},' +
          '"line":{"type":"integer","minimum":1,"description":"1-based line"},' +
          '"column":{"type":"integer","minimum":1,"description":"1-based UTF-8 byte column"}},' +
          '"required":["path","line","column"]}';
        Result.Modes := [amInspect, amBuild];
        Result.Role := brDeclaration;
        Result.IdeThread := True;
      End;
    10:
      Begin
        Result.Name := 'symbol_context';
        Result.Description := 'Return the CodeTools hint and nearby source for a Pascal identifier. Read-only. Positions are 1-based. ' +
          'Columns are UTF-8 bytes. No editor movement and no edit revision.';
        Result.BrokerDescription := 'Get a CodeTools hint and bounded source for a Pascal symbol at this revision. Read-only. ' +
          'Positions are 1-based UTF-8 byte columns.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative Pascal source path"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when the broker checks the buffer."},' +
          '"line":{"type":"integer","minimum":1,"description":"1-based line"},' +
          '"column":{"type":"integer","minimum":1,"description":"1-based UTF-8 byte column"}},' +
          '"required":["path","line","column"]}';
        Result.Modes := [amInspect, amBuild];
        Result.Role := brSymbols;
        Result.IdeThread := True;
      End;
    11:
      Begin
        Result.Name := 'find_references';
        Result.Description := 'Find Pascal references in an explicit search_paths list of 1 to 32 project files. ' +
          'A truncated or partial search is not whole-project coverage. Read-only. Positions are 1-based. ' +
          'Columns are UTF-8 bytes. No editor movement and no edit revision.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative Pascal source path"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when the broker checks the buffer."},' +
          '"line":{"type":"integer","minimum":1,"description":"1-based line"},' +
          '"column":{"type":"integer","minimum":1,"description":"1-based UTF-8 byte column"},' +
          '"search_paths":{"type":"array","minItems":1,"maxItems":32,"items":{"type":"string"},' +
          '"description":"1 to 32 project files. A truncated or partial search is not whole-project coverage."},' +
          '"max_results":{"type":"integer","minimum":1,"maximum":200,"description":"Optional result cap. Default 100."}},' +
          '"required":["path","line","column","search_paths"]}';
        Result.Modes := [amInspect, amBuild];
        Result.Role := brSymbols;
        Result.IdeThread := True;
      End;
    12:
      Begin
        Result.Name := 'todo_write';
        Result.Description := 'Replace or merge the ephemeral in-turn todo list (dies with the turn; not plan Status:). ' +
          'status: pending, in_progress, completed, cancelled.';
        Result.BrokerDescription := 'Replace or update this turn''s short checklist. The whole list is returned. It ends with the turn ' +
          'and is not a plan Status: line. status is pending, in_progress, completed or cancelled. merge true updates items by id.';
        Result.Schema := '{"type":"object","properties":{' +
          '"merge":{"type":"boolean","description":"If true, upsert by id; if false, replace the list (default false)"},' +
          '"todos":{"type":"array","description":"Todo items","items":{"type":"object","properties":{' +
          '"id":{"type":"string"},"content":{"type":"string"},"status":{"type":"string"}}}}},"required":["todos"]}';
        Result.Modes := [amPlan, amBuild];
        Result.Role := brTodo;
      End;
    13:
      Begin
        Result.Name := 'write_markdown';
        Result.Description := 'Create or overwrite a Markdown file under the project (prefer Documents/). Opens a live Markdown window. ' +
          'Use for new or full rewrites of plans. Rejects a Status: line under a ## heading. A ### heading without Status is a note, ' +
          'not a todo. In a Git repository, Status: complete is refused until run_git commit has succeeded in this turn; commit the ' +
          'plan file after that change. Without a repository, complete needs no commit.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative .md path (default Documents/Plan.md)"},' +
          '"content":{"type":"string","description":"Full Markdown body to write"},' +
          '"open":{"type":"boolean","description":"Open live viewer after write (default true). Ignored during a plan run."}},' +
          '"required":["content"]}';
        Result.Modes := [amDocument, amPlan, amBuild];
        Result.Role := brMarkdown;
        Result.IdeThread := True;
      End;
    14:
      Begin
        Result.Name := 'update_markdown';
        Result.Description := 'Exact text replacement in a project Markdown file (surgical edit). Prefer this over rewrite when ' +
          'changing Status: lines or a single section. Rejects a Status: line under a ## heading. A ### heading without Status stays ' +
          'a note, not a todo. In a Git repository, Status: complete is refused until run_git commit has succeeded in this turn; ' +
          'commit the plan file after that change. Without a repository, complete needs no commit.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative .md path (default: active plan)"},' +
          '"old_text":{"type":"string","description":"Exact text to find"},' +
          '"new_text":{"type":"string","description":"Replacement text"},' +
          '"replace_all":{"type":"boolean","description":"Replace every match (default false)"},' +
          '"open":{"type":"boolean","description":"Open live viewer after update (default true). Ignored during a plan run."}},' +
          '"required":["old_text","new_text"]}';
        Result.Modes := [amDocument, amPlan, amBuild];
        Result.Role := brMarkdown;
        Result.IdeThread := True;
      End;
    15:
      Begin
        Result.Name := 'list_plans';
        Result.Description := 'List plans registered in the project .assistant settings. Missing files are dropped. ' +
          'The project folders are not scanned.';
        Result.Schema := EmptySchema;
        Result.Modes := [amPlan, amBuild];
        Result.Role := brPlans;
      End;
    16:
      Begin
        Result.Name := 'get_active_plan';
        Result.Description := 'Return the canonical active plan path for this project (from .assistant/config.json).';
        Result.Schema := EmptySchema;
        Result.Modes := [amPlan, amBuild];
        Result.Role := brPlans;
      End;
    17:
      Begin
        Result.Name := 'set_active_plan';
        Result.Description := 'Set the canonical active plan Markdown path for this project.';
        Result.Schema := '{"type":"object","properties":{"path":{"type":"string","description":"Project-relative .md path"}},' +
          '"required":["path"]}';
        Result.Modes := [amPlan, amBuild];
        Result.Role := brSetPlan;
        Result.IdeThread := True;
      End;
    18:
      Begin
        Result.Name := 'read_markdown_section';
        Result.Description := 'Read one Markdown section. path is optional and defaults to the active plan. heading is an ATX heading ' +
          'such as ### 3.2. Returns that section up to the next heading of the same or a higher level. A ### item is one block. ' +
          'A ## heading includes its items.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative Markdown path. Omit for the active plan."},' +
          '"heading":{"type":"string","description":"ATX heading, for example ### 3.2"}},"required":["heading"]}';
        Result.Modes := [amPlan, amBuild];
        Result.Role := brPlans;
        Result.IdeThread := True;
      End;
    19:
      Begin
        Result.Name := 'write_file';
        Result.Description := 'Create or overwrite a real project file. Never create empty files or ApiProbe/scratch/temp units — use ' +
          'search_in_project, list_directory, and read_file to discover APIs. Prefer replace_in_file for small edits. Creating a file ' +
          'that does not exist writes it. Replacing an existing buffer requires the revision token from read_file.';
        Result.BrokerNote := ' {SaveNote}{WriteNote}';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative path e.g. Source/Foo.pas"},' +
          '"content":{"type":"string","description":"Full non-empty contents (reject empty/probe files)"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when the file already exists."},' +
          '"open":{"type":"boolean","description":"A Markdown path opens in the Assistant Markdown viewer (default false); use open_markdown. A source file is never opened as a tab."},' +
          '"add_to_project":{"type":"boolean","description":"Add Pascal unit to the active project (default true only for non-empty units)"}},' +
          '"required":["path","content"]}';
        Result.Modes := [amDocument, amPlan, amBuild];
        Result.Role := brMutate;
        Result.IdeThread := True;
      End;
    20:
      Begin
        Result.Name := 'replace_in_file';
        Result.Description := 'Exact text replacement in a project source/text file. old_text must match the open editor buffer when ' +
          'the file is open (same source as read_file), including whitespace; keep it small and unique. Saves the buffer to disk so ' +
          'Review/Git see the edit. An existing buffer requires the revision token from read_file.';
        Result.BrokerNote := ' {SaveNote}{WriteNote}';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative file path"},' +
          '"revision":{"type":"string","description":"Revision from read_file. Required when editing an existing buffer."},' +
          '"old_text":{"type":"string","description":"Exact text to find"},' +
          '"new_text":{"type":"string","description":"Replacement text"},' +
          '"replace_all":{"type":"boolean","description":"Replace every match (default false)"},' +
          '"open":{"type":"boolean","description":"A Markdown path opens in the Assistant Markdown viewer (default false); use open_markdown. A source file is never opened as a tab."}},' +
          '"required":["path","old_text","new_text"]}';
        Result.Modes := [amDocument, amPlan, amBuild];
        Result.Role := brMutate;
        Result.IdeThread := True;
      End;
    21:
      Begin
        Result.Name := 'run_compile';
        Result.Description := 'Compile the work target. A project or package uses that manifest. A folder compiles every .lpk under ' +
          'the folder, or every .lpi when the folder has no package. It does not compile the IDE active project. Default is quiet ' +
          'lazbuild. Set ui=true only for a final IDE Messages check of a project or package. Pass job_id to poll a build already ' +
          'started through this tool; detail manifest returns the observed-input list.';
        Result.Schema := '{"type":"object","properties":{' +
          '"kind":{"type":"string","description":"compile (default) or build (rebuild-all when quiet)"},' +
          '"ui":{"type":"boolean","description":"If true, use IDE DoBuildProject and Messages window (default false = quiet lazbuild)"},' +
          '"package":{"type":"string","description":"Optional project-relative .lpk when the target is a folder"},' +
          '"job_id":{"type":"string","description":"Poll this build instead of starting one"},' +
          '"detail":{"type":"string","description":"manifest to include the observed-input list when polling"}},"required":[]}';
        Result.Modes := [amBuild];
        Result.Role := brBuild;
        Result.IdeThread := True;
      End;
    22:
      Begin
        Result.Name := 'add_unit_to_project';
        Result.Description := 'Register an existing Pascal unit file with the active Lazarus project (.lpi).';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative .pas/.pp path"},' +
          '"add_to_uses":{"type":"boolean","description":"Also add to main uses clause when possible (default false)"}},' +
          '"required":["path"]}';
        Result.Modes := [amBuild];
        Result.Role := brProject;
        Result.IdeThread := True;
      End;
    23:
      Begin
        Result.Name := 'ensure_form_component';
        Result.Description := 'Add or update a published form component in BOTH the .pas unit and matching .lfm. Required when adding ' +
          'TTimer, TButton, etc. so events fire. Prefer this over hand-editing LFM alone.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Form unit path (.pas or .lfm), e.g. unit1.pas"},' +
          '"name":{"type":"string","description":"Component name, e.g. ColorTimer"},' +
          '"class_name":{"type":"string","description":"Component class, e.g. TTimer"},' +
          '"properties":{"type":"string","description":"Optional JSON object of LFM properties, e.g. {\"Interval\":1000,\"OnTimer\":\"ColorTimerTimer\",\"Enabled\":true}. TTimer Interval is milliseconds (1000 = 1 second)."},' +
          '"event_method":{"type":"string","description":"Optional event handler method name to declare/implement (e.g. ColorTimerTimer). Defaults from On* properties when omitted."},' +
          '"uses_unit":{"type":"string","description":"Optional unit to add to interface Uses (e.g. ExtCtrls for TTimer)"}},' +
          '"required":["path","name","class_name"]}';
        Result.Modes := [amBuild];
        Result.Role := brProject;
        Result.IdeThread := True;
      End;
    24:
      Begin
        Result.Name := 'run_project';
        Result.Description := 'Start the active project executable directly. No shell and no debugger. The executable must already be ' +
          'built and must stay inside the project root.';
        Result.Schema := EmptySchema;
        Result.Modes := [amBuild];
        Result.Role := brRunProject;
        Result.IdeThread := True;
      End;
    25:
      Begin
        Result.Name := 'run_tests';
        Result.Description := 'Run the enabled test command for this target. Arguments are passed directly, not through a shell. The ' +
          'executable and working directory must stay inside the project root. When a build job id is supplied, run that build''s ' +
          'configured command and return a job to poll with job_id. only, memory_check, defines and gui apply only to ' +
          'Tests/RunAssistantTests.pas.';
        Result.Schema := '{"type":"object","properties":{' +
          '"build_job_id":{"type":"string","description":"Successful current build whose test command to run"},' +
          '"job_id":{"type":"string","description":"Poll this test job instead of starting one"},' +
          '"only":{"type":"array","items":{"type":"string"},"description":"Test program names, passed as --only"},' +
          '"memory_check":{"type":"string","enum":["none","heaptrc","valgrind"]},"defines":{"type":"array","items":{"type":"string"}},' +
          '"gui":{"type":"boolean","description":"Pass --gui so GUI test programs build and run"}},"required":[]}';
        Result.Modes := [amBuild];
        Result.Role := brTest;
        Result.IdeThread := True;
      End;
    26:
      Begin
        Result.Name := 'run_command';
        Result.Description := 'Run one program and its arguments for a one-off check. No shell is used. Python and shells are refused. ' +
          'A saved repeatable test is an InstantFPC program in Tests/, not under Source/. Invoke it as instantfpc plus the script path.';
        Result.BrokerDescription := 'Run one program with its arguments, for a one-off check. No shell is used, and Python and shells ' +
          'are refused. The program may be a name on PATH or a path. The working directory defaults to the project root and must stay ' +
          'inside it. Build mode only. Over MCP the call returns when the program ends. Called directly it returns a job_id to poll ' +
          'with command_status. timeout_seconds is 1 to {CommandMax}, default 600.';
        Result.Schema := '{"type":"object","properties":{' +
          '"program":{"type":"string","description":"Program name on PATH, or a path. Example: instantfpc."},' +
          '"arguments":{"type":"array","items":{"type":"string"},"description":"Arguments passed directly, not through a shell."},' +
          '"working_directory":{"type":"string","description":"Optional. Defaults to the project directory and must stay inside it."},' +
          '"timeout_seconds":{"type":"integer","description":"1 to 3600. Default 600."}},"required":["program"]}';
        Result.Modes := [amBuild];
        Result.Role := brCommand;
      End;
    27:
      Begin
        Result.Name := 'delete_path';
        Result.Description := 'Delete one file, symbolic link, or empty directory inside the project root. Refuses the project root, ' +
          'Git metadata, and the project or package file. Does not use a shell.';
        Result.Schema := '{"type":"object","properties":{"path":{"type":"string","description":' +
          '"Project-relative or absolute path inside the project root"}},"required":["path"]}';
        Result.Modes := [amBuild];
        Result.Role := brProject;
        Result.IdeThread := True;
      End;
    28:
      Begin
        Result.Name := 'rename_path';
        Result.Description := 'Rename or move a file or directory inside the project root. Both paths must stay in the project. ' +
          'Refuses the project root, Git metadata, and the project or package file. Does not use a shell.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Existing project path"},' +
          '"new_path":{"type":"string","description":"New path inside the project root"}},"required":["path","new_path"]}';
        Result.Modes := [amBuild];
        Result.Role := brProject;
        Result.IdeThread := True;
      End;
    29:
      Begin
        Result.Name := 'run_git';
        Result.Description := AssistantGitDescription;
        Result.Schema := AssistantGitSchema;
        Result.Modes := [amInspect, amBuild];
        Result.Role := brGitRead;
        Result.IdeThread := True;
      End;
    30:
      Begin
        Result.Name := 'stage_patch';
        Result.Description := AssistantStagePatchDescription;
        Result.Schema := AssistantStagePatchSchema;
        Result.Modes := [amBuild];
        Result.Role := brGitWrite;
        Result.IdeThread := True;
      End;
    31:
      Begin
        Result.Name := 'spawn_subagent';
        Result.Description := 'Start a depth-1 child agent and wait for its summary. Parent only; a child cannot spawn. At most 3 ' +
          'children run at once; extra spawn_subagent calls wait for a free slot. Kinds: explore (read-only research), plan ' +
          '(Markdown only), general-purpose (parent mode tools), pascal-naming, pascal-structure, pascal-review (read-only lenses). ' +
          'Use for parallel explore or Review lenses. Do not spawn for syntax (use run_compile) or every edit.';
        Result.Schema := '{"type":"object","properties":{' +
          '"kind":{"type":"string","description":"explore | plan | general-purpose | pascal-naming | pascal-structure | pascal-review"},' +
          '"subagent_type":{"type":"string","description":"Alias of kind"},' +
          '"title":{"type":"string","description":"Short label shown in the parent trace"},' +
          '"description":{"type":"string","description":"Alias of title"},' +
          '"prompt":{"type":"string","description":"Full instructions for the child"},' +
          '"files":{"type":"string","description":"Optional changed-file list the child should focus on"}},"required":["prompt"]}';
        Result.Modes := [amInspect, amDocument, amPlan, amBuild];
        Result.Role := brNone;
        Result.Gated := True;
        Result.Capability := acSubagents;
      End;
    32:
      Begin
        Result.Name := 'write_image';
        Result.Description := 'Draw one still image with this connection''s image model and save it. It is not a copy of a read_image ' +
          'attachment. The path may omit an extension. The image model chooses the format. A mismatched extension is saved with the ' +
          'matching extension instead of failing.';
        Result.Schema := '{"type":"object","properties":{' +
          '"path":{"type":"string","description":"Project-relative path. Omit the extension to let the image model choose the format."},' +
          '"prompt":{"type":"string","description":"What to draw."},' +
          '"overwrite":{"type":"boolean","description":"Replace an existing file. Default false."},' +
          '"shape":{"type":"string","description":"Short hint such as 1:1. Omit it to let the image model choose."}},' +
          '"required":["path","prompt"]}';
        Result.Modes := [amDocument, amPlan, amBuild];
        Result.Role := brNone;
        Result.Gated := True;
        Result.Capability := acImageOutput;
      End;
    33:
      Begin
        Result.Name := 'open_buffer';
        Result.Description := 'Get an edit revision for an existing project text file: the open editor''s text when it is open, ' +
          'otherwise the file on disk. Does not open an editor tab. Returns the text and a revision unless include_text is false. ' +
          'Does not create or save files.';
        Result.Schema := '{"type":"object","properties":{"path":{"type":"string"},"include_text":{"type":"boolean"}},' +
          '"required":["path"]}';
        Result.Role := brInspect;
        Result.IdeThread := True;
      End;
    34:
      Begin
        Result.Name := 'prepare_changes';
        Result.Description := 'Prepare one reviewed change set for 1-16 project text files, open in the editor or not. Read each ' +
          'buffer first and supply its revision and complete proposed text. Does not edit or save; returns a one-use change_set_id.';
        Result.Schema := '{"type":"object","properties":{"changes":{"type":"array","minItems":1,"maxItems":16,"items":{"type":"object",' +
          '"properties":{"path":{"type":"string"},"revision":{"type":"string"},"text":{"type":"string"}},' +
          '"required":["path","revision","text"]}}},"required":["changes"]}';
        Result.Role := brChanges;
      End;
    35:
      Begin
        Result.Name := 'change_status';
        Result.Description := 'Get an in-memory change-set receipt with per-file apply/recovery outcomes. Without an ID, lists ' +
          'receipts for this project. Receipts survive new chats/runs until the assistant panel closes; they are not durable.';
        Result.Schema := '{"type":"object","properties":{"change_set_id":{"type":"string"}},"required":[]}';
        Result.Role := brChanges;
      End;
    36:
      Begin
        Result.Name := 'apply_changes';
        Result.Description := 'Review and apply an exact prepared multi-editor change set in Build. Validates every source and editor ' +
          'stamp before each write. On success returns each file''s new revision and changed line range, not the buffer text.';
        Result.BrokerNote := ' {SaveNote}';
        Result.Schema := '{"type":"object","properties":{"change_set_id":{"type":"string"}},"required":["change_set_id"]}';
        Result.Role := brChangeWrite;
      End;
    37:
      Begin
        Result.Name := 'revert_changes';
        Result.Description := 'Review and restore confirmed edits from a retained change-set receipt in Build. Skips changed, closed ' +
          'or unverified editors; returns partial outcomes instead of overwriting user edits. Native Undo remains per editor.';
        Result.BrokerNote := ' {SaveNote}';
        Result.Schema := '{"type":"object","properties":{"change_set_id":{"type":"string"}},"required":["change_set_id"]}';
        Result.Role := brChangeWrite;
      End;
    38:
      Begin
        Result.Name := 'preview_local_rename';
        Result.Description := 'Preview a routine-local variable or constant rename using CodeTools. Requires a current buffer ' +
          'revision; coordinates are 1-based UTF-8 bytes. Returns exact changes and a one-use preview_id without editing.';
        Result.Schema := '{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"},' +
          '"line":{"type":"integer","minimum":1},"column":{"type":"integer","minimum":1},"new_name":{"type":"string"}},' +
          '"required":["path","revision","line","column","new_name"]}';
        Result.Role := brRename;
      End;
    39:
      Begin
        Result.Name := 'apply_local_rename';
        Result.Description := 'Apply the exact previously reviewed local rename preview in Build mode. Revalidates source and ' +
          'CodeTools results after approval. Consumes preview_id and returns the new revision and changed line range.';
        Result.BrokerNote := ' {SaveNote}';
        Result.Schema := '{"type":"object","properties":{"preview_id":{"type":"string"}},"required":["preview_id"]}';
        Result.Role := brRenameWrite;
      End;
    40:
      Begin
        Result.Name := 'save_file';
        Result.Description := '{SaveTool}{WriteNote}';
        Result.Schema := '{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"}},' +
          '"required":["path","revision"]}';
        Result.Role := brMutate;
        Result.IdeThread := True;
      End;
    41:
      Begin
        Result.Name := 'command_status';
        Result.Description := 'Poll a run_command job by its job_id: done, outcome (running, exited, failed or cancelled), exit_code, ' +
          'any error, and the last 48000 characters of output.';
        Result.Schema := '{"type":"object","properties":{"job_id":{"type":"string"}},"required":["job_id"]}';
        Result.Role := brCommand;
      End;
  Else
    Result.Name := '';
  End;
End;

Function TableCount: Integer;
Begin
  Result := 42;
End;

Function FindAssistantToolSpec(Const Name: String; Out Spec: TAssistantToolSpec): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  Spec := Default(TAssistantToolSpec);
  For I := 0 To TableCount - 1 Do
    Begin
      Spec := ToolAt(I);
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
  For I := 0 To TableCount - 1 Do
    Begin
      Spec := ToolAt(I);
      If (Spec.Role <> brNone) Or Not (Offer.Mode In Spec.Modes) Or Not CapabilityOffered(Spec, Offer) Then
        Continue;
      If Names.IndexOf(Spec.Name) < 0 Then
        Names.Add(Spec.Name);
    End;
End;

End.
