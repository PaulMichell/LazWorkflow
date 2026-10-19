Program AssistantMonitorAbsent;

{ Widgetset-free checks that the assistant package stands alone (c) 2026 Michell Computing.

  No Interfaces unit. The runner writes this binary with a temporary -FU and -FE,
  never under Source/. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, SyncObjs, fpjson, AssistantMonitorLinkStubs,
  AssistantSessionObserve, AssistantTools, WorkflowSettings;

Type
  TNoticeSink = Class
    Heard: Integer;
    LastKind: TAssistantSessionNoticeKind;
    Procedure Hear(Kind: TAssistantSessionNoticeKind);
  End;

Var
  FailCount: Integer;

Procedure TNoticeSink.Hear(Kind: TAssistantSessionNoticeKind);
Begin
  Inc(Heard);
  LastKind := Kind;
End;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Function PackagePath: String;
Var
  I: Integer;
  Dir, Probe: String;
Begin
  Result := 'Packages' + PathDelim + 'LazAssistantTools.lpk';
  If FileExists(Result) Then
    Exit(ExpandFileName(Result));
  Dir := GetCurrentDir;
  For I := 1 To 8 Do
    Begin
      Probe := IncludeTrailingPathDelimiter(Dir) + 'Packages' + PathDelim + 'LazAssistantTools.lpk';
      If FileExists(Probe) Then
        Exit(Probe);
      Probe := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + '..');
      If Probe = Dir Then
        Break;
      Dir := Probe;
    End;
  Result := '';
End;

Function FormSourcePath: String;
Var
  Package: String;
Begin
  Package := PackagePath;
  If Package = '' Then
    Exit('');
  Result := ExpandFileName(ExtractFilePath(Package) + '..' + PathDelim + 'Source' + PathDelim +
    'LazAssistantTools' + PathDelim + 'ProjectAssistantForm.pas');
End;

Function ReadText(Const Path: String): String;
Var
  Lines: TStringList;
Begin
  Result := '';
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Procedure TestNilListener;
Begin
  SetAssistantSessionListener(Nil);
  Check('nil listener is unassigned', Not AssistantSessionListenerAssigned);
  Check('nil listener observe returns false', Not AssistantSessionObserve.AssistantSessionObserve(asnStatus));
End;

Procedure TestOneNotice;
Var
  Sink: TNoticeSink;
Begin
  Sink := TNoticeSink.Create;
  Try
    Sink.Heard := 0;
    SetAssistantSessionListener(@Sink.Hear);
    Check('temporary listener receives the observe', AssistantSessionObserve.AssistantSessionObserve(asnTranscript));
    Check('temporary listener receives one notice', Sink.Heard = 1);
    Check('notice kind is the one passed', Sink.LastKind = asnTranscript);
  Finally
    SetAssistantSessionListener(Nil);
    Sink.Free;
  End;
  Check('cleared listener observe returns false', Not AssistantSessionObserve.AssistantSessionObserve(asnPhase));
End;

Procedure TestApprovalWait;
Var
  Event: PRTLEvent;
Begin
  Check('stored decision starts none', ReadAssistantApprovalDecision = aadNone);
  SignalAssistantApprovalWait;
  Check('nil event signal returns', True);
  Check('bare signal leaves none', ReadAssistantApprovalDecision = aadNone);
  StoreAssistantApprovalDecision(aadAllow);
  Check('first store writes allow', ReadAssistantApprovalDecision = aadAllow);
  StoreAssistantApprovalDecision(aadDeny);
  Check('second store leaves allow', ReadAssistantApprovalDecision = aadAllow);
  StoreAssistantApprovalDecision(aadStopped);
  Check('stopped does not replace allow', ReadAssistantApprovalDecision = aadAllow);
  Event := RTLEventCreate;
  Try
    ArmAssistantApprovalWait(Event);
    Check('arm resets to none', ReadAssistantApprovalDecision = aadNone);
    ArmAssistantApprovalWait(Nil);
    Check('nil arm leaves none', ReadAssistantApprovalDecision = aadNone);
  Finally
    RTLEventDestroy(Event);
  End;
End;

Procedure TestPackageOmitsMonitor;
Var
  Path, Text: String;
Begin
  Path := PackagePath;
  Check('assistant package file exists', Path <> '');
  If Path = '' Then
    Exit;
  Text := ReadText(Path);
  Check('package does not name LazAssistantMonitor', Pos('LazAssistantMonitor', Text) = 0);
End;

Procedure TestMonitorSectionLeavesAssistant;
Var
  Section: TJSONObject;
  ErrorText, Root: String;
  Guid: TGuid;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-absent-' + GUIDToString(Guid);
  If Not ForceDirectories(Root) Then
    Raise Exception.Create('Could not create ' + Root);
  SetWorkflowSettingsDirectory(Root);
  Try
    Section := TJSONObject.Create;
    Try
      Section.Add('marker', 'keep-assistant');
      Check('seed assistant marker', WriteWorkflowSection('assistant', Section, ErrorText));
      If ErrorText <> '' Then
        WriteLn(ErrorText);
    Finally
      Section.Free;
    End;
    Section := TJSONObject.Create;
    Try
      Section.Add('enabled', False);
      Check('write monitor section', WriteWorkflowSection('monitor', Section, ErrorText));
      If ErrorText <> '' Then
        WriteLn(ErrorText);
    Finally
      Section.Free;
    End;
    Section := ReadWorkflowSection('assistant');
    Try
      Check('assistant section survives', Assigned(Section));
      Check('assistant marker survives', Assigned(Section) And (Section.Get('marker', '') = 'keep-assistant'));
    Finally
      Section.Free;
    End;
  Finally
    DeleteFile(WorkflowSettingsPath);
    DeleteFile(WorkflowSettingsPath + '.tmp');
    SetWorkflowSettingsDirectory('');
    RemoveDir(ExcludeTrailingPathDelimiter(Root));
  End;
End;

Function AbsentWaiter(Const ToolName, ToolId, ArgumentsJson: String; Aborting: TAssistantApprovalAbort;
  Out ErrorText: String; Out Handled: Boolean): Boolean;
Begin
  Handled := True;
  ErrorText := ToolName + ' ' + ToolId + ' ' + ArgumentsJson;
  If Assigned(Aborting) Then
    ErrorText := ErrorText + ' abort';
  Result := False;
End;

Procedure TestNilWaiter;
Var
  ErrorText: String;
  Handled: Boolean;
  Before: TAssistantApprovalNotice;
  FormPath, FormText: String;
Begin
  SetAssistantSessionListener(Nil);
  SetAssistantRemoteApproval(@AbsentWaiter);
  Check('waiter can be assigned', AssistantRemoteApprovalAssigned);
  SetAssistantRemoteApproval(Nil);
  Check('nil waiter is unassigned', Not AssistantRemoteApprovalAssigned);
  Before := CurrentAssistantApproval;
  Handled := True;
  ErrorText := 'untouched';
  Check('nil waiter leaves approval unhandled',
    (Not QueryAssistantRemoteApproval('write_file', 'tool-absent', '{}', Nil, ErrorText, Handled)) And
    (Not Handled) And (ErrorText = ''));
  Check('nil waiter emits no notice', (CurrentAssistantApproval.Active = Before.Active) And
    (CurrentAssistantApproval.ToolId = Before.ToolId) And (CurrentAssistantApproval.Reason = Before.Reason));
  FormPath := FormSourcePath;
  Check('assistant form source exists', FileExists(FormPath));
  If Not FileExists(FormPath) Then
    Exit;
  FormText := ReadText(FormPath);
  Check('broker approval stays nil', Pos('OnApproval := Nil', FormText) > 0);
  Check('broker approval is not assigned a handler', Pos('OnApproval := @', FormText) = 0);
End;

Begin
  FailCount := 0;
  TestNilListener;
  TestOneNotice;
  TestApprovalWait;
  TestPackageOmitsMonitor;
  TestMonitorSectionLeavesAssistant;
  TestNilWaiter;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorAbsent tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorAbsent test(s) failed.');
      Halt(1);
    End;
End.
