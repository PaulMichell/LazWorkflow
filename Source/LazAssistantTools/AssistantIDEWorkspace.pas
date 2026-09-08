Unit AssistantIDEWorkspace;

{ Main-thread adapter for the shared tool broker. Open editor buffers only:
  no hidden disk mutation or automatic opening/saving of unrelated editors. }
{$mode objfpc}{$H+}
Interface
Uses AssistantToolBroker, AssistantBuildJob;
Type
  TAssistantIDEWorkspace = Class(TAssistantWorkspaceAdapter)
  Private
    FBuild: IAssistantBuildJob;
    FBuildInputs: TBuildInputs;
    FBuildIdentity, FBuildMode: String;
  Public
    Destructor Destroy; Override;
    Function CanBuild: Boolean; Override;
    Function StartBuild(Out ResultText, ErrorText: String): Boolean; Override;
    Function BuildStatus(Out ResultText, ErrorText: String): Boolean; Override;
    Procedure CancelBuild; Override;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
  End;
Implementation
Uses Classes, SysUtils, Forms, Controls, LazFileUtils, FileUtil, LazIDEIntf, ProjectIntf, SrcEditorIntf, AssistantTools,
  AssistantEditorEdits, AssistantIDEContext, AssistantProtocol;
Destructor TAssistantIDEWorkspace.Destroy;
Begin CancelBuild; Inherited Destroy; End;
Procedure TAssistantIDEWorkspace.CancelBuild;
Begin
  If Assigned(FBuild) Then FBuild.Cancel;
  FBuild := Nil;
  SetLength(FBuildInputs, 0);
End;
Function TAssistantIDEWorkspace.CanBuild: Boolean;
Begin Result := True; End;
Function TAssistantIDEWorkspace.StartBuild(Out ResultText, ErrorText: String): Boolean;
Var Editor: TSourceEditorInterface; I, N, Bytes: Integer; Exe, ProjectFile: String;
  Stream: TFileStream;
Begin
  Result := False; ResultText := ''; ErrorText := '';
  If Assigned(FBuild) And Not FBuild.Snapshot.Done Then
    Begin ErrorText := 'A build is already running.'; Exit; End;
  If Not Assigned(LazarusIDE) Or Not Assigned(LazarusIDE.ActiveProject) Or
    Not Assigned(SourceEditorManagerIntf) Then
    Begin ErrorText := 'No active Lazarus project.'; Exit; End;
  If LazarusIDE.ActiveProject.Modified Then
    Begin ErrorText := 'Save project settings explicitly before building.'; Exit; End;
  ProjectFile := LazarusIDE.ActiveProject.ProjectInfoFile;
  Exe := FindDefaultExecutablePath('lazbuild');
  If Exe = '' Then Exe := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'lazbuild';
  If Not FileExistsUTF8(Exe) Then
    Begin ErrorText := 'lazbuild was not found.'; Exit; End;
  SetLength(FBuildInputs, 0); Bytes := 0;
  For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
    Begin
      Editor := SourceEditorManagerIntf.SourceEditors[I];
      If Not Assigned(Editor) Then Continue;
      { Conservative: reject any dirty open input instead of guessing which
        external unit search paths the compiler might resolve. }
      If Editor.Modified Then
        Begin ErrorText := 'Save changed editor buffers explicitly before building.'; Exit; End;
      If Editor.FileName = '' Then Continue;
      N := Length(FBuildInputs);
      If N >= 64 Then Begin ErrorText := 'Too many open buffers for the build snapshot.'; Exit; End;
      SetLength(FBuildInputs, N + 1);
      FBuildInputs[N].Path := Editor.FileName;
      FBuildInputs[N].Text := Editor.SourceText;
      Inc(Bytes, Length(FBuildInputs[N].Text));
      If Bytes > 8388608 Then Begin ErrorText := 'Build snapshot size limit exceeded.'; Exit; End;
    End;
  Stream := TFileStream.Create(ProjectFile, fmOpenRead Or fmShareDenyNone);
  Try
    If Stream.Size > 1048576 Then Begin ErrorText := 'Project file size limit exceeded.'; Exit; End;
    N := Length(FBuildInputs); SetLength(FBuildInputs, N + 1);
    FBuildInputs[N].Path := ProjectFile; SetLength(FBuildInputs[N].Text, Stream.Size);
    If Stream.Size > 0 Then Stream.ReadBuffer(FBuildInputs[N].Text[1], Stream.Size);
  Finally Stream.Free; End;
  FBuildIdentity := Identity;
  FBuildMode := LazarusIDE.ActiveProject.ActiveBuildModeID;
  FBuild := StartAssistantBuild(Exe, ProjectFile, FBuildMode, FBuildInputs);
  ResultText := '{"started":true,"savedBuffers":false}'; Result := True;
End;
Function TAssistantIDEWorkspace.BuildStatus(Out ResultText, ErrorText: String): Boolean;
Var Value: TBuildJobSnapshot; I: Integer; Editor: TSourceEditorInterface; Stale: Boolean;
Begin
  Result := False; ResultText := ''; ErrorText := '';
  If Not Assigned(FBuild) Then Begin ErrorText := 'No build has been started.'; Exit; End;
  Value := FBuild.Snapshot;
  If Not Value.Done Then Begin ResultText := '{"done":false}'; Exit(True); End;
  Stale := (Identity <> FBuildIdentity) Or Not Value.InputsUnchanged;
  If Not Stale Then
    Begin
      Stale := LazarusIDE.ActiveProject.Modified Or
        (LazarusIDE.ActiveProject.ActiveBuildModeID <> FBuildMode);
      For I := 0 To High(FBuildInputs) Do
        Begin
          Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(FBuildInputs[I].Path);
          If Assigned(Editor) And (Editor.Modified Or (Editor.SourceText <> FBuildInputs[I].Text)) Then Stale := True;
        End;
    End;
  ResultText := '{"done":true,"exitCode":' + IntToStr(Value.ExitCode) +
    ',"cancelled":' + LowerCase(BoolToStr(Value.Cancelled, True)) +
    ',"stale":' + LowerCase(BoolToStr(Stale, True)) +
    ',"verified":false,"validationScope":"Observed open buffers and project file; dependencies are not frozen",' +
    '"manifest":' + Value.Manifest + ',"diagnostics":"' + JsonEscapeText(Value.OutputText) +
    '","error":"' + JsonEscapeText(Value.ErrorText) + '"}';
  Result := True;
End;
Function TAssistantIDEWorkspace.Identity: String;
Begin
  Result := '';
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    Result := IntToHex(PtrUInt(LazarusIDE.ActiveProject), SizeOf(Pointer)*2) + ':' +
      LazarusIDE.ActiveProject.ProjectInfoFile;
End;
Function TAssistantIDEWorkspace.ReadBuffer(Const Path: String;
  Out CanonicalPath, Text, ErrorText: String): Boolean;
Var Editor: TSourceEditorInterface;
Begin
  Result := False; Text := ''; CanonicalPath := ''; ErrorText := '';
  If Not ResolveProjectPath(Path, CanonicalPath, ErrorText) Then Exit;
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin ErrorText := 'Source editor manager is unavailable.'; Exit; End;
  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(CanonicalPath);
  If Not Assigned(Editor) Then
    Begin ErrorText := 'Open this project file in the Lazarus editor before using buffer tools.'; Exit; End;
  Text := Editor.SourceText;
  Result := True;
End;
Function TAssistantIDEWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String;
  Out ErrorText: String): Boolean;
Begin
  Result := False;
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin ErrorText := 'Source editor manager is unavailable.'; Exit; End;
  Result := ApplyAssistantEditorText(SourceEditorManagerIntf.SourceEditorIntfWithFilename(Path),
    ExpectedText, NewText, ErrorText);
End;
Function TAssistantIDEWorkspace.SaveBuffer(Const Path, ExpectedText: String;
  Out ErrorText: String): Boolean;
Var Editor: TSourceEditorInterface;
Begin
  Result := False; ErrorText := '';
  If Not Assigned(LazarusIDE) Or Not Assigned(SourceEditorManagerIntf) Then
    Begin ErrorText := 'Lazarus editor is unavailable.'; Exit; End;
  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Path);
  If Not Assigned(Editor) Or Editor.ReadOnly Or (Editor.SourceText <> ExpectedText) Then
    Begin ErrorText := 'Buffer changed, closed, or became read-only before save.'; Exit; End;
  Result := LazarusIDE.DoSaveEditorFile(Editor, [sfQuietUnitCheck]) = mrOk;
  If Not Result Then ErrorText := 'Buffer remains edited but could not be saved.';
End;
Function TAssistantIDEWorkspace.Describe: String;
Begin Result := BuildIDEContextBlockLight; End;
End.
