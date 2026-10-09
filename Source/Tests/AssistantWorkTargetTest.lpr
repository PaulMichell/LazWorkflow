Program AssistantWorkTargetTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Classes, SysUtils, BaseUnix, PackageIntf,
  LazIDEIntf, ProjectIntf, SrcEditorIntf, AssistantTestIDEHost, AssistantWorkTarget,
  AssistantConversation, AssistantIDEContext, AssistantIDEWorkspace,
  AssistantTools, AssistantTestSettings, fpjson, jsonparser, ProjectAssistantForm,
  StdCtrls, BaseIDEIntf, LazConfigStorage, FPImage, FPWritePNG, FileUtil,
  AssistantImages, AssistantService, AssistantProtocol, AssistantTrace, AssistantEvents,
  AssistantConfig, AssistantCodexClient;
Type
  TMemoryConfig=Class(TConfigMemStorage)
  Public
    Procedure WriteToDisk; Override;
  End;
  TMember=Class(TLazPackageFile)
  Public
    Path:String;
    Function GetFilename:String; Override;
    Procedure SetFilename(Const Value:String); Override;
  End;
  TPackage=Class(TIDEPackage)
  Public
    Member:TMember;
    Dirty:Boolean;
    Function GetFileCount:Integer; Override;
    Function GetPkgFiles(Index:Integer):TLazPackageFile; Override;
    Function GetModified:Boolean; Override;
    Procedure SetFilename(Const Value:String); Override;
    Function ReadOnly:Boolean; Override;
    Function IsVirtual:Boolean; Override;
    Procedure Bump;
  End;
  TPackages=Class(TPackageEditingInterface)
  Public
    First,Second:TPackage;
    Function GetPackageCount:Integer; Override;
    Function GetPackages(Index:Integer):TIDEPackage; Override;
    Procedure GetRequiredPackages(AnOwner:TObject; Out PkgList:TFPList; Flags:TPkgIntfRequiredFlags=[]); Override;
  End;
  TProject=Class(TLazProject)
  Public
    Path:String;
    Function GetProjectInfoFile:String; Override;
    Function GetMainFile:TLazProjectFile; Override;
    Function GetFileCount:Integer; Override;
  End;
  TIDE=Class(TLazIDEInterface)
  Public
    Proj:TProject;
    Function GetActiveProject:TLazProject; Override;
    Class Function GetPrimaryConfigPath:String; Override;
  End;
  TEditor=Class(TSourceEditorInterface)
  Public
    Path,Body:String;
    Dirty:Boolean;
    Function GetFileName:String; Override;
    Function GetSourceText:String; Override;
    Function GetModified:Boolean; Override;
    Function GetModifiedDesign:Boolean; Override;
  End;
  TEditors=Class(TSourceEditorManagerInterface)
  Public
    Editor:TEditor;
    Function SourceEditorCount:Integer; Override;
    Function GetSourceEditors(Index:Integer):TSourceEditorInterface; Override;
    Function SourceEditorIntfWithFilename(Const Filename:String):TSourceEditorInterface; Override;
    Function GetActiveEditor:TSourceEditorInterface; Override;
  End;
  TWorkspace=Class(TAssistantIDEWorkspace)
  Public
    Function BuildExecutable:String; Override;
  End;
Var Root:String;
Procedure TMemoryConfig.WriteToDisk;
Begin End;
Function MemoryConfig(Const Filename:String; LoadFromDisk:Boolean):TConfigStorage;
Begin Result:=TMemoryConfig.Create('',False);End;
Function TProject.GetFileCount:Integer;Begin Result:=0;End;
Function TMember.GetFilename:String; Begin Result:=Path; End;
Procedure TMember.SetFilename(Const Value:String); Begin Path:=Value; End;
Function TPackage.GetFileCount:Integer; Begin Result:=1; End;
Function TPackage.GetPkgFiles(Index:Integer):TLazPackageFile; Begin Result:=Member; End;
Function TPackage.GetModified:Boolean; Begin Result:=Dirty; End;
Procedure TPackage.SetFilename(Const Value:String); Begin FFilename:=Value; End;
Function TPackage.ReadOnly:Boolean; Begin Result:=False; End;
Function TPackage.IsVirtual:Boolean; Begin Result:=False; End;
Procedure TPackage.Bump; Begin Inc(FChangeStamp); End;
Function TPackages.GetPackageCount:Integer; Begin Result:=2; End;
Function TPackages.GetPackages(Index:Integer):TIDEPackage;
Begin If Index=0 Then Result:=First Else Result:=Second; End;
Procedure TPackages.GetRequiredPackages(AnOwner:TObject; Out PkgList:TFPList; Flags:TPkgIntfRequiredFlags);
Begin PkgList:=TFPList.Create; If AnOwner=First Then PkgList.Add(Second); End;
Function TProject.GetProjectInfoFile:String; Begin Result:=Path; End;
Function TProject.GetMainFile:TLazProjectFile; Begin Result:=Nil; End;
Function TIDE.GetActiveProject:TLazProject; Begin Result:=Proj; End;
Class Function TIDE.GetPrimaryConfigPath:String; Begin Result:=Root+'/config/'; End;
Function TEditor.GetFileName:String; Begin Result:=Path; End;
Function TEditor.GetSourceText:String; Begin Result:=Body; End;
Function TEditor.GetModified:Boolean; Begin Result:=Dirty; End;
Function TEditor.GetModifiedDesign:Boolean; Begin Result:=False; End;
Function TEditors.SourceEditorCount:Integer; Begin Result:=1; End;
Function TEditors.GetSourceEditors(Index:Integer):TSourceEditorInterface; Begin Result:=Editor; End;
Function TEditors.GetActiveEditor:TSourceEditorInterface; Begin Result:=Editor; End;
Function TEditors.SourceEditorIntfWithFilename(Const Filename:String):TSourceEditorInterface;
Begin Result:=Nil; If Filename=Editor.Path Then Result:=Editor; End;
Function TWorkspace.BuildExecutable:String; Begin Result:=ParamStr(0); End;
Procedure Check(Const Name:String; OK:Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ',Name);Halt(1);End;WriteLn('ok ',Name);End;
Procedure TestReadImage;
Var Root, Outside, Note, Reply, Body:String; Img:TFPMemoryImage; Writer:TFPWriterPNG; Stream:TFileStream;
  Refs:TAssistantImageRefArray; Svc:TAssistantService; Items:TSamplerInputItemArray; Options:TSamplerRequestOptions;
  Trace:TAssistantTrace; Event, Parsed:TAssistantEvent; I:Integer; SawImage:Boolean;
  SavedApproval:TAssistantApprovalMode;
Begin
  Check('read_image is not available in Chat', Not ToolAllowedInMode('read_image', amChat));
  Check('Chat sends no tools', BuildAssistantToolsJsonForMode(amChat) = '');
  Check('read_image is available in Inspect', ToolAllowedInMode('read_image', amInspect));
  Check('read_image is available in Plan', ToolAllowedInMode('read_image', amPlan));
  Check('read_image is available in Build', ToolAllowedInMode('read_image', amBuild));
  Check('Inspect lists read_image', Pos('"name":"read_image"', BuildAssistantToolsJsonForMode(amInspect))>0);
  Check('Plan lists read_image', Pos('"name":"read_image"', BuildAssistantToolsJsonForMode(amPlan))>0);
  Check('Build lists read_image', Pos('"name":"read_image"', BuildAssistantToolsJsonForMode(amBuild))>0);
  Root:=GetTempFileName(GetTempDir,'read-image-'); DeleteFile(Root); ForceDirectories(Root);
  Outside:=GetTempFileName(GetTempDir,'read-image-out-'); DeleteFile(Outside);
  Img:=TFPMemoryImage.Create(8,4); Writer:=TFPWriterPNG.Create; Stream:=Nil;
  Try
    Img.Colors[0,0]:=FPColor($FFFF,$0000,$0000,$FFFF);
    Stream:=TFileStream.Create(Root+'/photo.png', fmCreate);
    Img.SaveToStream(Stream, Writer);
    FreeAndNil(Stream);
    Stream:=TFileStream.Create(Outside, fmCreate);
    Img.SaveToStream(Stream, Writer);
  Finally
    Stream.Free; Writer.Free; Img.Free;
  End;
  Check('folder target for read_image', AssistantTarget.SelectFolder(Root, Note));
  SetLength(Refs, 0);
  Check('read_image stores the picture', ExecuteAssistantToolForMode('read_image', '{"path":"photo.png"}', amInspect,
    Reply, Note, Refs) And (Length(Refs)=1));
  Check('result is the name', Pos('photo.png', Reply)>0);
  Check('result is the dimensions', Pos('8 x 4', Reply)>0);
  Check('result is the id', Pos(Refs[0].Id, Reply)>0);
  Check('result has no image bytes', (Pos('base64', LowerCase(Reply))=0) And (Pos('data:', LowerCase(Reply))=0) And
    (Pos(Root, Reply)=0));
  Svc:=TAssistantService.Create;
  Try
    Svc.AddToolResult('call_1', 'photo.png, 8 x 4, '+Refs[0].Id);
    Svc.AddUserMessage('', Refs);
    Items:=Svc.ExportSamplerItems(False);
    Options:=DefaultSamplerRequestOptions;
    Options.ProjectRoot:=Root;
    Body:=BuildChatCompletionsRequestJson(Items, Options);
    SawImage:=False;
    For I:=0 To High(Items) Do
      If (Items[I].Role='user') And (Length(Items[I].ImageRefs)>0) Then SawImage:=True;
    Check('following user input carries the image refs', SawImage);
    Check('following user input uses the content array', (Pos('"type":"image_url"', Body)>0) And
      (Pos('data:image/', Body)>0));
    Check('tool text in the request has no image bytes', Pos('base64', Copy(Body, 1, Pos('"role":"user"', Body)))=0);
  Finally
    Svc.Free;
  End;
  Trace:=TAssistantTrace.Create;
  Try
    Trace.AppendUserImages(AssistantImageRefsToJson(Refs));
    Check('user-visible block shows the picture without the look sentence', (Trace.Count=1) And
      (Trace[0].Kind=tbkUser) And (Trace[0].Body='') And (Length(Trace[0].ImageRefs)=1));
  Finally
    Trace.Free;
  End;
  Event:=Default(TAssistantEvent);
  Event.Kind:=aekToolCompleted;
  Event.Text:='photo.png, 8 x 4, id';
  Event.AttachmentsJson:=AssistantImageRefsToJson(Refs);
  Check('event round-trip keeps attachment refs', ParseAssistantEventJson(AssistantEventToJson(Event), Parsed) And
    (Pos(Refs[0].Id, Parsed.AttachmentsJson)>0) And (Pos('base64', Parsed.AttachmentsJson)=0));
  SavedApproval := AssistantChatConfig.GetApprovalMode;
  AssistantChatConfig.SetApprovalModeEnum(aamAlways);
  Try
    Check('png is still not a text edit', (Not ExecuteAssistantToolForMode('write_file',
      '{"path":"photo.png","content":"not an image"}', amBuild, Reply, Note)) And (Pos('blocked/binary', Note)>0));
    Check('replace_in_file still refuses a png', (Not ExecuteAssistantToolForMode('replace_in_file',
      '{"path":"photo.png","old_text":"a","new_text":"b"}', amBuild, Reply, Note)) And (Pos('blocked/binary', Note)>0));
  Finally
    AssistantChatConfig.SetApprovalModeEnum(SavedApproval);
  End;
  Check('escape link created', fpSymlink(PChar(Outside), PChar(Root+'/escape.png'))=0);
  SetLength(Refs, 0);
  Check('symbolic link that leaves the project is refused', Not ExecuteAssistantToolForMode('read_image',
    '{"path":"escape.png"}', amPlan, Reply, Note, Refs));
  Check('escape is refused by the sandbox', (Pos('symbolic link', LowerCase(Note))>0) Or
    (Pos('outside the active project', LowerCase(Note))>0));
  AssistantTarget.SelectProject;
  DeleteFile(Outside);
  DeleteDirectory(Root, False);
End;
Function CatalogueDescription(Const ToolsJson, Name: String; Nested: Boolean): String;
Var
  Data: TJSONData;
  Arr: TJSONArray;
  Obj, Fn: TJSONObject;
  I: Integer;
Begin
  Result := '';
  Data := GetJSON(ToolsJson);
  Try
    If Not (Data Is TJSONArray) Then Exit;
    Arr := TJSONArray(Data);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr[I] Is TJSONObject) Then Continue;
        Obj := TJSONObject(Arr[I]);
        If Nested Then
          Begin
            If Not (Obj.Find('function') Is TJSONObject) Then Continue;
            Fn := TJSONObject(Obj.Find('function'));
            If Fn.Get('name', '') = Name Then Exit(Fn.Get('description', ''));
          End
        Else If Obj.Get('name', '') = Name Then
          Exit(Obj.Get('description', ''));
      End;
  Finally
    Data.Free;
  End;
End;

Procedure TestCodexPlanTools;
Var
  Catalogue, Dynamic, Params, Name, SharedDesc: String;
  Data, Shared: TJSONData;
  Arr: TJSONArray;
  I: Integer;
Begin
  Catalogue := BuildAssistantToolsJsonForMode(amPlan);
  Dynamic := CodexDynamicToolsFromCatalogue(Catalogue);
  Check('plan dynamic tools include write_markdown', CatalogueDescription(Dynamic, 'write_markdown', False) <> '');
  Check('plan dynamic tools include open_markdown', CatalogueDescription(Dynamic, 'open_markdown', False) <> '');
  Check('plan dynamic tools omit open_file', CatalogueDescription(Dynamic, 'open_file', False) = '');
  Check('plan dynamic tools omit lazarus_', Pos('lazarus_', Dynamic) = 0);
  Check('write_markdown description matches', CatalogueDescription(Dynamic, 'write_markdown', False) =
    CatalogueDescription(Catalogue, 'write_markdown', True));
  Check('open_markdown description matches', CatalogueDescription(Dynamic, 'open_markdown', False) =
    CatalogueDescription(Catalogue, 'open_markdown', True));
  Data := GetJSON(Dynamic);
  Try
    Arr := TJSONArray(Data);
    Shared := GetJSON(Catalogue);
    Try
      Check('converted plan tool count', Arr.Count = TJSONArray(Shared).Count);
    Finally
      Shared.Free;
    End;
    For I := 0 To Arr.Count - 1 Do
      Begin
        Name := TJSONObject(Arr[I]).Get('name', '');
        SharedDesc := CatalogueDescription(Catalogue, Name, True);
        Check('description matches ' + Name, (SharedDesc <> '') And (TJSONObject(Arr[I]).Get('description', '') = SharedDesc));
      End;
  Finally
    Data.Free;
  End;
  Params := CodexThreadStartParams('/proj', 'model', Dynamic, 'Use write_markdown.');
  Check('thread/start embeds write_markdown', Pos('"name":"write_markdown"', Params) > 0);
  Check('thread/start embeds open_markdown', Pos('"name":"open_markdown"', Params) > 0);
  Check('thread/start instructions are the passed prompt', Pos('Use write_markdown.', Params) > 0);
  Check('thread/start has no lazarus tool essay', Pos('use the lazarus tools', LowerCase(Params)) = 0);
  Check('chat catalogue converts to an empty array', CodexDynamicToolsFromCatalogue(BuildAssistantToolsJsonForMode(amChat)) = '[]');
  Check('chat thread/start has an empty tool array', Pos('"dynamicTools":[]',
    CodexThreadStartParams('/proj', 'model', '[]', 'chat')) > 0);
  Check('document still offers open_file', CatalogueDescription(
    CodexDynamicToolsFromCatalogue(BuildAssistantToolsJsonForMode(amDocument)), 'open_file', False) <> '');
  Check('build still offers open_file', CatalogueDescription(
    CodexDynamicToolsFromCatalogue(BuildAssistantToolsJsonForMode(amBuild)), 'open_file', False) <> '');
End;

Procedure WriteFile(Const Path,Body:String);
Var F:TFileStream;
Begin ForceDirectories(ExtractFileDir(Path));F:=TFileStream.Create(Path,fmCreate);
  Try If Body<>'' Then F.WriteBuffer(Body[1],Length(Body));Finally F.Free;End;End;
Var IDE:TIDE; Packages:TPackages; Proj:TProject; Editors:TEditors; Workspace:TWorkspace;
  Store:TAssistantConversationStore; Settings1,Settings2:TAssistantTestSettings;
  Id:TGuid; Note,Key,ProjectStore,Reply,Identity,Path:String; Data:TJSONData;
  Dialog:TProjectAssistantForm;Combo:TComboBox;
  Thinking:Boolean; Mode:TAssistantMode; Deadline:QWord;
Begin
  { This executable also acts as a fake compiler: packages have no --build-mode. }
  If (ParamCount>0) And SameText(ExtractFileExt(ParamStr(ParamCount)),'.lpk') Then
    Begin If (ParamCount<>3) Or (Pos('--pcp=',ParamStr(1))<>1) Or (Pos('--widgetset=',ParamStr(2))<>1) Then Halt(2);WriteLn('package compile fixture');Halt(0);End;
  Application.Initialize;GetIDEConfigStorage:=@MemoryConfig;
  TestReadImage;
  TestCodexPlanTools;
  CreateGUID(Id);Root:=GetTempDir+'laz-target-'+GUIDToString(Id);
  WriteFile(Root+'/.git/HEAD','ref: refs/heads/main');
  WriteFile(Root+'/Packages/One.lpk','<package/>');WriteFile(Root+'/Packages/Two.lpk','<package/>');
  WriteFile(Root+'/Source/One/One.pas','unit One; interface implementation end.');
  WriteFile(Root+'/Source/Two/Two.pas','unit Two; interface implementation end.');
  WriteFile(Root+'/App/project.lpi','<project/>');WriteFile(Root+'/App/App.pas','unrelated source');
  IDE:=TIDE.Create(Nil);Proj:=TProject.Create(Nil);Proj.Path:=Root+'/App/project.lpi';IDE.Proj:=Proj;LazarusIDE:=IDE;
  Packages:=TPackages.Create(Nil);PackageEditingInterface:=Packages;
  Packages.First:=TPackage.Create;Packages.Second:=TPackage.Create;
  Packages.First.Filename:=Root+'/Packages/One.lpk';Packages.Second.Filename:=Root+'/Packages/Two.lpk';
  Packages.First.Member:=TMember.Create;Packages.First.Member.Path:=Root+'/Source/One/One.pas';
  Packages.Second.Member:=TMember.Create;Packages.Second.Member.Path:=Root+'/Source/Two/Two.pas';
  Editors:=TEditors.Create(Nil);Editors.Editor:=TEditor.Create;Editors.Editor.Path:=Root+'/App/App.pas';
  Editors.Editor.Body:='UNRELATED SECRET BUFFER';Editors.Editor.Dirty:=True;SourceEditorManagerIntf:=Editors;
  Workspace:=TWorkspace.Create;Store:=TAssistantConversationStore.Create;
  Try
    ProjectStore:=AssistantTarget.StoreDirectory;
    Check('project remains the default target',AssistantTarget.Kind=atkProject);
    Check('the open project directory can be chosen as a folder',
      AssistantTarget.SelectFolder(Root,Note) And (AssistantTarget.Kind=atkFolder) And
      (ExcludeTrailingPathDelimiter(AssistantTarget.Root)=ExcludeTrailingPathDelimiter(ExpandFileName(Root))));
    AssistantTarget.SelectProject;
    Check('select loaded package',AssistantTarget.SelectPackage(Packages.First.Filename,Note));
    Check('package root includes sibling Source and Documents',AssistantTarget.Root=Root+'/');
    Check('active project is unchanged',IDE.Proj=Proj);
    Check('package excludes unrelated active editor from full context',Pos('UNRELATED SECRET BUFFER',BuildIDEContextBlock)=0);
    Check('light context identifies package without unrelated editor text',
      (Pos('One.lpk',BuildIDEContextBlockLight)>0) And (Pos('UNRELATED SECRET BUFFER',BuildIDEContextBlockLight)=0));
    Check('members outside manifest directory are writable',AssistantTarget.AllowsWrite(Packages.First.Member.Path));
    Check('dependency directories do not become writable',Not AssistantTarget.AllowsWrite(Packages.Second.Member.Path));
    Check('unrelated project is not writable',Not AssistantTarget.AllowsWrite(Editors.Editor.Path));
    Check('new member-directory files allowed',AssistantTarget.AllowsWrite(Root+'/Source/One/New.pas'));
    Check('new Documents directory allowed for plans',AssistantTarget.AllowsWrite(Root+'/Documents/Plan.md'));
    Check('broker can create the first plan file',Workspace.CheckNewFile('Documents/Plan.md',Path,Note));
    fpSymlink(PChar(Root+'/Source/Two'),PChar(Root+'/Source/One/escape'));
    Check('symlink cannot extend write scope',Not AssistantTarget.AllowsWrite(Root+'/Source/One/escape/Two.pas'));
    Check('manifest editing requires package editor',Not AssistantTarget.AllowsWrite(Packages.First.Filename));
    Check('read resolver uses target root',ResolveProjectPath('Source/One/One.pas',Path,Note) And (Path=Packages.First.Member.Path));
    Check('legacy tools describe selected package',ExecuteAssistantToolForMode('get_project_info','{}',amInspect,Reply,Note) And (Pos('One.lpk',Reply)>0));
    Check('legacy package writes cannot alter unrelated source',Not ExecuteAssistantToolForMode('write_file','{"path":"App/App.pas","content":"bad"}',amBuild,Reply,Note));
    Check('Git cannot stage unrelated project source',Not ToolRunGit('{"arguments":["add","--","App/App.pas"]}',Reply,Note));
    Check('legacy membership tool cannot modify active project',Not ExecuteAssistantToolForMode('add_unit_to_project','{"path":"Source/One/One.pas"}',amBuild,Reply,Note));
    Store.SetProjectRoot(AssistantTarget.Root,AssistantTarget.StoreKey);
    Check('save package plan setting',Store.SaveShellConfig(True,amPlan,'Documents/One.md'));
    Key:=AssistantTarget.StoreKey;Path:=AssistantTarget.StoreDirectory;
    Check('package session uses isolated store',Pos('/targets/'+Key+'/',Path)>0);
    Settings1:=TAssistantTestSettings.Create(Root,AssistantTarget.Manifest);
    Check('select another package',AssistantTarget.SelectPackage(Packages.Second.Filename,Note));
    Settings2:=TAssistantTestSettings.Create(Root,AssistantTarget.Manifest);
    Try Check('test settings are independent',Settings1.StorageFilename<>Settings2.StorageFilename);
    Finally Settings1.Free;Settings2.Free;End;
    Check('package histories cannot collide',AssistantTarget.StoreKey<>Key);
    Store.SetProjectRoot(AssistantTarget.Root,AssistantTarget.StoreKey);
    Check('second package does not inherit plan',Not Store.LoadShellConfig(Thinking,Mode,Reply));
    Check('return to first package',AssistantTarget.SelectPackage(Packages.First.Filename,Note));
    Store.SetProjectRoot(AssistantTarget.Root,AssistantTarget.StoreKey);
    Check('first package plan restored',Store.LoadShellConfig(Thinking,Mode,Reply) And (Reply='Documents/One.md'));
    Identity:=AssistantTarget.Identity;IDE.Proj:=Nil;
    Check('closing unrelated project does not redirect package',AssistantTarget.Identity=Identity);
    Packages.Second.Dirty:=True;
    Check('unsaved dependency settings prevent a package build',Not Workspace.StartBuild(Reply,Note));
    Packages.Second.Dirty:=False;
    Check('package builds without an active project or unrelated buffer saves',Workspace.StartBuild(Reply,Note));
    Deadline:=GetTickCount64+5000;
    Repeat
      Sleep(10);If Not Workspace.BuildStatus(Reply,Note) Then Check('observe package build: '+Note,False);Data:=GetJSON(Reply);
      Try If Data.FindPath('done').AsBoolean Then Break;Finally Data.Free;End;
    Until GetTickCount64>=Deadline;
    Check('package build succeeds without project mode argument',Pos('compile_passed',Reply)>0);
    Check('dependency manifests captured',Pos('Two.lpk',Reply)>0);
    Packages.First.Bump;
    Check('package option changes invalidate build',Workspace.BuildStatus(Reply,Note) And (Pos('"stale" : true',Reply)>0));
    Check('restart package build',Workspace.StartBuild(Reply,Note));
    AssistantTarget.SelectPackage(Packages.Second.Filename,Note);
    Check('target switch invalidates previous build',Workspace.BuildStatus(Reply,Note) And (Pos('"stale" : true',Reply)>0));
    IDE.Proj:=Proj;AssistantTarget.SelectProject;
    If AssistantTarget.StoreDirectory<>ProjectStore Then WriteLn('storage before=',ProjectStore,' after=',AssistantTarget.StoreDirectory);
    Check('legacy project storage unchanged',AssistantTarget.StoreDirectory=ProjectStore);
    AssistantTarget.SelectPackage(Packages.First.Filename,Note);
    Dialog:=TProjectAssistantForm.Create(Nil);
    Try
      Dialog.Show;Application.ProcessMessages;Dialog.BindToActiveProject;
      Combo:=TComboBox(Dialog.FindComponent('TargetCombo'));
      Check('target selector is available in Assistant',Assigned(Combo));
      Check('package title is visible',Pos('One.lpk',Dialog.Caption)>0);
      Combo.OnDropDown(Combo);
      Check('current project is the default choice',(Combo.Items.Count>0) And (Combo.Items[0]='Current Project'));
      Check('packages are not target choices',(Pos('One.lpk',Combo.Items.Text)=0) And (Pos('Two.lpk',Combo.Items.Text)=0));
      Check('folder button sits with the target',Assigned(Dialog.FindComponent('TargetBrowseButton')));
      Check('select a folder as the target',AssistantTarget.SelectFolder(Root+'/Source/One',Note));
      Combo.OnDropDown(Combo);
      Check('folder choice shows the leaf name',(Combo.ItemIndex>=0) And (Combo.Items[Combo.ItemIndex]='One'));
      Check('folder choice hint is the full path',Combo.Hint=IncludeTrailingPathDelimiter(Root+'/Source/One'));
      Check('folder target is that directory',AssistantTarget.Root=Root+'/Source/One/');
      Check('files inside the folder are writable',AssistantTarget.AllowsWrite(Root+'/Source/One/New.pas'));
      Check('a sibling folder is outside the target',Not AssistantTarget.AllowsWrite(Root+'/Source/Two/Two.pas'));
      Check('the project file is outside the folder',Not AssistantTarget.AllowsWrite(Editors.Editor.Path));
      AssistantTarget.SelectPackage(Packages.First.Filename,Note);
      NotifyOpenProjectAssistantFormsProjectCleared;
      Check('project-close notification preserves pinned package',Pos('One.lpk',Dialog.Caption)>0);
      NotifyOpenProjectAssistantFormsProjectChanged;
      Check('project-open notification preserves pinned package',AssistantTarget.Manifest=Packages.First.Filename);
      Combo.ItemIndex:=0;Combo.OnChange(Combo);
      Check('selector restores current project and legacy store',
        (AssistantTarget.Kind=atkProject) And (ProjectAssistantConversation.TargetStoreKey=''));
    Finally Dialog.Free;End;

  Finally
    Workspace.Free;Store.Free;AssistantTarget.SelectProject;
    SourceEditorManagerIntf:=Nil;Editors.Editor.Free;Editors.Free;
    PackageEditingInterface:=Nil;Packages.First.Member.Free;Packages.Second.Member.Free;
    Packages.First.Free;Packages.Second.Free;Packages.Free;LazarusIDE:=Nil;Proj.Free;IDE.Free;
  End;
End.
