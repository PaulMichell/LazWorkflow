Program AssistantMonitorAbsent;

{ Widgetset-free checks that the assistant package stands alone (c) 2026 Michell Computing.

  No Interfaces unit. The runner writes this binary with a temporary -FU and -FE,
  never under Source/. LazAssistantTools pulls Forms, so the LCL widgetset units
  reference WSRegister symbols that Interfaces would define. Those symbols are
  defined here, only to satisfy the linker. They do not create a widgetset. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
  {$SMARTLINK OFF}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, SyncObjs, fpjson, AssistantSessionObserve, AssistantTools, WorkflowSettings;

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

Function CountText(Const Needle, Text: String): Integer;
Var
  At: Integer;
Begin
  Result := 0;
  At := Pos(Needle, Text);
  While At > 0 Do
    Begin
      Inc(Result);
      At := Pos(Needle, Text, At + Length(Needle));
    End;
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
Var
  Before: Int64;
Begin
  SetAssistantSessionListener(Nil);
  Check('nil listener is unassigned', Not AssistantSessionListenerAssigned);
  Check('nil listener observe returns false', Not AssistantSessionObserve.AssistantSessionObserve(asnStatus));
  Before := AssistantMirrorCounter;
  TouchAssistantMirror;
  Check('touch with no listener does not raise', AssistantMirrorCounter = Before + 1);
  Check('touch with no listener stays unassigned', Not AssistantSessionListenerAssigned);
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
  { A Claude turn asks through the IDE's own dialog (ApproveClaudeTool). No other handler, such as a remote
    waiter, may be wired to the broker from the form. }
  Check('broker approval is only the IDE dialog', CountText('OnApproval := @', FormText) =
    CountText('OnApproval := @ApproveClaudeTool;', FormText));
End;

{ Linker stand-ins for the LCL widgetset registration symbols. Not a widgetset. }
Function WSRegisterCustomImageListResolution: Boolean; Public Name 'WSRegisterCustomImageListResolution';
Begin Result := False; End;
Function WSRegisterDragImageListResolution: Boolean; Public Name 'WSRegisterDragImageListResolution';
Begin Result := False; End;
Function WSRegisterLazAccessibleObject: Boolean; Public Name 'WSRegisterLazAccessibleObject';
Begin Result := False; End;
Function WSRegisterControl: Boolean; Public Name 'WSRegisterControl';
Begin Result := False; End;
Function WSRegisterWinControl: Boolean; Public Name 'WSRegisterWinControl';
Begin Result := False; End;
Function WSRegisterGraphicControl: Boolean; Public Name 'WSRegisterGraphicControl';
Begin Result := False; End;
Function WSRegisterCustomControl: Boolean; Public Name 'WSRegisterCustomControl';
Begin Result := False; End;
Function WSRegisterStatusBar: Boolean; Public Name 'WSRegisterStatusBar';
Begin Result := False; End;
Function WSRegisterTabSheet: Boolean; Public Name 'WSRegisterTabSheet';
Begin Result := False; End;
Function WSRegisterPageControl: Boolean; Public Name 'WSRegisterPageControl';
Begin Result := False; End;
Function WSRegisterCustomListView: Boolean; Public Name 'WSRegisterCustomListView';
Begin Result := False; End;
Function WSRegisterCustomProgressBar: Boolean; Public Name 'WSRegisterCustomProgressBar';
Begin Result := False; End;
Function WSRegisterCustomUpDown: Boolean; Public Name 'WSRegisterCustomUpDown';
Begin Result := False; End;
Function WSRegisterCustomToolButton: Boolean; Public Name 'WSRegisterCustomToolButton';
Begin Result := False; End;
Function WSRegisterToolBar: Boolean; Public Name 'WSRegisterToolBar';
Begin Result := False; End;
Function WSRegisterCustomTrackBar: Boolean; Public Name 'WSRegisterCustomTrackBar';
Begin Result := False; End;
Function WSRegisterCustomTreeView: Boolean; Public Name 'WSRegisterCustomTreeView';
Begin Result := False; End;
Function WSRegisterCustomCalendar: Boolean; Public Name 'WSRegisterCustomCalendar';
Begin Result := False; End;
Function WSRegisterCommonDialog: Boolean; Public Name 'WSRegisterCommonDialog';
Begin Result := False; End;
Function WSRegisterFileDialog: Boolean; Public Name 'WSRegisterFileDialog';
Begin Result := False; End;
Function WSRegisterOpenDialog: Boolean; Public Name 'WSRegisterOpenDialog';
Begin Result := False; End;
Function WSRegisterSaveDialog: Boolean; Public Name 'WSRegisterSaveDialog';
Begin Result := False; End;
Function WSRegisterSelectDirectoryDialog: Boolean; Public Name 'WSRegisterSelectDirectoryDialog';
Begin Result := False; End;
Function WSRegisterColorDialog: Boolean; Public Name 'WSRegisterColorDialog';
Begin Result := False; End;
Function WSRegisterColorButton: Boolean; Public Name 'WSRegisterColorButton';
Begin Result := False; End;
Function WSRegisterFontDialog: Boolean; Public Name 'WSRegisterFontDialog';
Begin Result := False; End;
Function WSRegisterTaskDialog: Boolean; Public Name 'WSRegisterTaskDialog';
Begin Result := False; End;
Function WSRegisterCustomScrollBar: Boolean; Public Name 'WSRegisterCustomScrollBar';
Begin Result := False; End;
Function WSRegisterCustomGroupBox: Boolean; Public Name 'WSRegisterCustomGroupBox';
Begin Result := False; End;
Function WSRegisterCustomComboBox: Boolean; Public Name 'WSRegisterCustomComboBox';
Begin Result := False; End;
Function WSRegisterCustomListBox: Boolean; Public Name 'WSRegisterCustomListBox';
Begin Result := False; End;
Function WSRegisterCustomEdit: Boolean; Public Name 'WSRegisterCustomEdit';
Begin Result := False; End;
Function WSRegisterCustomMemo: Boolean; Public Name 'WSRegisterCustomMemo';
Begin Result := False; End;
Function WSRegisterButtonControl: Boolean; Public Name 'WSRegisterButtonControl';
Begin Result := False; End;
Function WSRegisterCustomButton: Boolean; Public Name 'WSRegisterCustomButton';
Begin Result := False; End;
Function WSRegisterCustomCheckBox: Boolean; Public Name 'WSRegisterCustomCheckBox';
Begin Result := False; End;
Function WSRegisterToggleBox: Boolean; Public Name 'WSRegisterToggleBox';
Begin Result := False; End;
Function WSRegisterRadioButton: Boolean; Public Name 'WSRegisterRadioButton';
Begin Result := False; End;
Function WSRegisterCustomStaticText: Boolean; Public Name 'WSRegisterCustomStaticText';
Begin Result := False; End;
Function WSRegisterCustomLabel: Boolean; Public Name 'WSRegisterCustomLabel';
Begin Result := False; End;
Function WSRegisterCustomPage: Boolean; Public Name 'WSRegisterCustomPage';
Begin Result := False; End;
Function WSRegisterCustomNotebook: Boolean; Public Name 'WSRegisterCustomNotebook';
Begin Result := False; End;
Function WSRegisterCustomShape: Boolean; Public Name 'WSRegisterCustomShape';
Begin Result := False; End;
Function WSRegisterCustomSplitter: Boolean; Public Name 'WSRegisterCustomSplitter';
Begin Result := False; End;
Function WSRegisterPaintBox: Boolean; Public Name 'WSRegisterPaintBox';
Begin Result := False; End;
Function WSRegisterCustomImage: Boolean; Public Name 'WSRegisterCustomImage';
Begin Result := False; End;
Function WSRegisterBevel: Boolean; Public Name 'WSRegisterBevel';
Begin Result := False; End;
Function WSRegisterCustomRadioGroup: Boolean; Public Name 'WSRegisterCustomRadioGroup';
Begin Result := False; End;
Function WSRegisterCustomCheckGroup: Boolean; Public Name 'WSRegisterCustomCheckGroup';
Begin Result := False; End;
Function WSRegisterCustomLabeledEdit: Boolean; Public Name 'WSRegisterCustomLabeledEdit';
Begin Result := False; End;
Function WSRegisterCustomPanel: Boolean; Public Name 'WSRegisterCustomPanel';
Begin Result := False; End;
Function WSRegisterCustomTrayIcon: Boolean; Public Name 'WSRegisterCustomTrayIcon';
Begin Result := False; End;
Function WSRegisterPreviewFileControl: Boolean; Public Name 'WSRegisterPreviewFileControl';
Begin Result := False; End;
Function WSRegisterPreviewFileDialog: Boolean; Public Name 'WSRegisterPreviewFileDialog';
Begin Result := False; End;
Function WSRegisterOpenPictureDialog: Boolean; Public Name 'WSRegisterOpenPictureDialog';
Begin Result := False; End;
Function WSRegisterSavePictureDialog: Boolean; Public Name 'WSRegisterSavePictureDialog';
Begin Result := False; End;
Function WSRegisterCalculatorDialog: Boolean; Public Name 'WSRegisterCalculatorDialog';
Begin Result := False; End;
Function WSRegisterCalculatorForm: Boolean; Public Name 'WSRegisterCalculatorForm';
Begin Result := False; End;
Function WSRegisterCalendarDialog: Boolean; Public Name 'WSRegisterCalendarDialog';
Begin Result := False; End;
Function WSRegisterCustomBitBtn: Boolean; Public Name 'WSRegisterCustomBitBtn';
Begin Result := False; End;
Function WSRegisterCustomSpeedButton: Boolean; Public Name 'WSRegisterCustomSpeedButton';
Begin Result := False; End;
Function WSRegisterCustomCheckListBox: Boolean; Public Name 'WSRegisterCustomCheckListBox';
Begin Result := False; End;
Function WSRegisterScrollingWinControl: Boolean; Public Name 'WSRegisterScrollingWinControl';
Begin Result := False; End;
Function WSRegisterScrollBox: Boolean; Public Name 'WSRegisterScrollBox';
Begin Result := False; End;
Function WSRegisterCustomFrame: Boolean; Public Name 'WSRegisterCustomFrame';
Begin Result := False; End;
Function WSRegisterCustomForm: Boolean; Public Name 'WSRegisterCustomForm';
Begin Result := False; End;
Function WSRegisterHintWindow: Boolean; Public Name 'WSRegisterHintWindow';
Begin Result := False; End;
Function WSRegisterCustomGrid: Boolean; Public Name 'WSRegisterCustomGrid';
Begin Result := False; End;
Function WSRegisterMenuItem: Boolean; Public Name 'WSRegisterMenuItem';
Begin Result := False; End;
Function WSRegisterMenu: Boolean; Public Name 'WSRegisterMenu';
Begin Result := False; End;
Function WSRegisterMainMenu: Boolean; Public Name 'WSRegisterMainMenu';
Begin Result := False; End;
Function WSRegisterPopupMenu: Boolean; Public Name 'WSRegisterPopupMenu';
Begin Result := False; End;
Function WSRegisterPairSplitterSide: Boolean; Public Name 'WSRegisterPairSplitterSide';
Begin Result := False; End;
Function WSRegisterCustomPairSplitter: Boolean; Public Name 'WSRegisterCustomPairSplitter';
Begin Result := False; End;
Function WSRegisterCustomFloatSpinEdit: Boolean; Public Name 'WSRegisterCustomFloatSpinEdit';
Begin Result := False; End;
Function WSRegisterCustomRubberBand: Boolean; Public Name 'WSRegisterCustomRubberBand';
Begin Result := False; End;
Function WSRegisterCustomShellTreeView: Boolean; Public Name 'WSRegisterCustomShellTreeView';
Begin Result := False; End;
Function WSRegisterCustomShellListView: Boolean; Public Name 'WSRegisterCustomShellListView';
Begin Result := False; End;
Function WSRegisterLazDeviceAPIs: Boolean; Public Name 'WSRegisterLazDeviceAPIs';
Begin Result := False; End;

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
