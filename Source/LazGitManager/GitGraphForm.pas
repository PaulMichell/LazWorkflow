Unit GitGraphForm;

{ Virtual commit history graph window (c) 2026 Michell Computing.

  Full history is indexed via rev-list (SHA/parents/lanes). Row labels and
  dates load on demand for the visible scroll window, like a virtual list. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, LCLIntf, LCLType, WorkflowEvents, StatusFooterFrame,
  GitGraphModel;

Type
  TGitGraphForm = Class(TForm, IWorkflowListener, IGitRepositoryChanged)
  Private
    FToolBar: TToolBar;
    FMainPanel: TPanel; { between toolbar and status – owns graph, splitter, details }
    FGraphHost: TPanel;
    FPaintBox: TPaintBox;
    FScrollBar: TScrollBar;
    FStatusFooter: TStatusFooterFrame;
    FSplitter: TSplitter;
    FDetailPanel: TPanel;
    FDetailMemo: TMemo;
    FActionList: TActionList;
    FRefreshAction: TAction;
    FDetailTimer: TTimer;
    FRepoPath: String;
    FBranch: String;
    FHeadSha: String;
    FClean: Boolean;
    FModel: TGitGraphModel;
    FSelectedIndex: Integer;
    FIndexing: Boolean;
    FDetailLoading: Boolean;
    FIndexThread: TThread;
    FDetailThread: TThread;
    FPendingIndexText: String;
    FPendingIndexOk: Boolean;
    FPendingDetailsText: String;
    FPendingDetailsOk: Boolean;
    FVisibleFirst: Integer;
    FVisibleLast: Integer;
    FLaneColors: Array[0..9] Of TColor;
    Procedure CreateUI;
    Procedure InitLaneColors;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure PaintBoxPaint(Sender: TObject);
    Procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    Procedure PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; Var Handled: Boolean);
    Procedure ScrollBarChange(Sender: TObject);
    Procedure GraphHostResize(Sender: TObject);
    Procedure DetailTimerTimer(Sender: TObject);
    Procedure RefreshActionExecute(Sender: TObject);
    Procedure UpdateStatus;
    Procedure RefreshRepositoryInfo;
    Procedure ApplyIndexLoaded;
    Procedure ApplyDetailsLoaded;
    Procedure StartIndexLoad;
    Procedure ScheduleVisibleDetails;
    Procedure StartDetailLoadIfNeeded;
    Procedure StopIndexThread;
    Procedure StopDetailThread;
    Procedure UpdateScrollRange;
    Procedure GetVisibleRange(Out FirstRow, LastRow: Integer);
    Procedure ShowCommitDetails(Index: Integer);
    Function ScrollOffset: Integer;
    Function RowAtY(Y: Integer): Integer;
    Function LaneX(Lane: Integer): Integer;
    Function RowMidY(Row: Integer): Integer;
    Function FormatCommitDate(Const CommitTime: Int64): String;
    { IGitRepositoryChanged }
    Procedure RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
    Procedure WorkingTreeChanged(Const RepoPath: String);
    Procedure HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
    Procedure RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure BindRepository(Const StartPath: String = '');
    Procedure SetRepository(Const ARepoPath: String);
    Property RepoPath: String Read FRepoPath;
  End;

Procedure RefreshOpenGitGraphForms;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, GitService, LazIDEIntf, ProjectIntf, DateUtils, Math;

Type
  TGitIndexThread = Class(TThread)
  Private
    FForm: TGitGraphForm;
    FRepoPath: String;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TGitGraphForm; Const ARepoPath: String);
  End;

  TGitDetailThread = Class(TThread)
  Private
    FForm: TGitGraphForm;
    FRepoPath: String;
    FShas: TStringList;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TGitGraphForm; Const ARepoPath: String; AShas: TStringList);
    Destructor Destroy; Override;
  End;

Constructor TGitIndexThread.Create(AForm: TGitGraphForm; Const ARepoPath: String);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FForm := AForm;
  FRepoPath := ARepoPath;
End;

Procedure TGitIndexThread.Execute;
Var
  Text: String;
  Ok: Boolean;
  Client: TGitService;
Begin
  Client := TGitService.Create;
  Try
    Ok := Client.FetchRevListParents(FRepoPath, Text);
    If Terminated Then
      Exit;
    FForm.FPendingIndexOk := Ok;
    FForm.FPendingIndexText := Text;
    If Not Terminated Then
      Synchronize(@FForm.ApplyIndexLoaded);
  Finally
    Client.Free;
  End;
End;

Constructor TGitDetailThread.Create(AForm: TGitGraphForm; Const ARepoPath: String;
  AShas: TStringList);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FForm := AForm;
  FRepoPath := ARepoPath;
  FShas := AShas; { takes ownership }
End;

Destructor TGitDetailThread.Destroy;
Begin
  FreeAndNil(FShas);
  Inherited Destroy;
End;

Procedure TGitDetailThread.Execute;
Var
  Text: String;
  Ok: Boolean;
  Client: TGitService;
Begin
  Client := TGitService.Create;
  Try
    Ok := Client.FetchCommitDetails(FRepoPath, FShas, Text);
    If Terminated Then
      Exit;
    FForm.FPendingDetailsOk := Ok;
    FForm.FPendingDetailsText := Text;
    If Not Terminated Then
      Synchronize(@FForm.ApplyDetailsLoaded);
  Finally
    Client.Free;
  End;
End;

Function DetectStartPathFromIDE: String;
Var
  Project: TLazProject;
Begin
  Result := '';
  If Not Assigned(LazarusIDE) Then
    Exit;
  Project := LazarusIDE.ActiveProject;
  If Not Assigned(Project) Or Project.IsVirtual Then
    Exit;
  If Project.ProjectInfoFile <> '' Then
    Result := ExtractFilePath(ExpandFileName(Project.ProjectInfoFile));
  If (Result = '') And Assigned(Project.MainFile) And (Project.MainFile.Filename <> '') Then
    Result := ExtractFilePath(ExpandFileName(Project.MainFile.Filename));
End;

Procedure RefreshOpenGitGraphForms;
Var
  I: Integer;
Begin
  For I := 0 To Screen.CustomFormCount - 1 Do
    If Screen.CustomForms[I] Is TGitGraphForm Then
      TGitGraphForm(Screen.CustomForms[I]).BindRepository;
End;

Constructor TGitGraphForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FClean := True;
  FSelectedIndex := -1;
  FIndexing := False;
  FDetailLoading := False;
  FIndexThread := Nil;
  FDetailThread := Nil;
  FVisibleFirst := 0;
  FVisibleLast := 0;
  FModel := TGitGraphModel.Create;
  InitLaneColors;
  CreateUI;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TGitGraphForm.Destroy;
Begin
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  StopDetailThread;
  StopIndexThread;
  WorkflowEventBus.RemoveListener(Self);
  FreeAndNil(FModel);
  Inherited Destroy;
End;

Procedure TGitGraphForm.InitLaneColors;
Begin
  FLaneColors[0] := RGBToColor(33, 150, 243);
  FLaneColors[1] := RGBToColor(76, 175, 80);
  FLaneColors[2] := RGBToColor(255, 152, 0);
  FLaneColors[3] := RGBToColor(156, 39, 176);
  FLaneColors[4] := RGBToColor(244, 67, 54);
  FLaneColors[5] := RGBToColor(0, 150, 136);
  FLaneColors[6] := RGBToColor(63, 81, 181);
  FLaneColors[7] := RGBToColor(233, 30, 99);
  FLaneColors[8] := RGBToColor(121, 85, 72);
  FLaneColors[9] := RGBToColor(96, 125, 139);
End;

Procedure TGitGraphForm.CreateUI;
Begin
  Caption := 'Git Graph';
  Width := 900;
  Height := 600;
  Position := poDefaultPosOnly;

  FActionList := TActionList.Create(Self);

  FRefreshAction := TAction.Create(Self);
  FRefreshAction.Caption := 'Refresh';
  FRefreshAction.OnExecute := @RefreshActionExecute;
  FRefreshAction.ActionList := FActionList;

  FToolBar := TToolBar.Create(Self);
  With FToolBar Do
    Begin
      Parent := Self;
      Align := alTop;
      Height := 28;
      EdgeBorders := [];
      ShowCaptions := True;
    End;

  With TToolButton.Create(FToolBar) Do
    Begin
      Parent := FToolBar;
      Action := FRefreshAction;
      Style := tbsButton;
    End;

  { Fixed status strip on the form bottom – never a splitter target. }
  FStatusFooter := TStatusFooterFrame.Create(Self);
  With FStatusFooter Do
    Begin
      Parent := Self;
      Align := alBottom;
      Height := 22;
      Constraints.MinHeight := 22;
      Constraints.MaxHeight := 22;
    End;

  { Middle band: graph + splitter + details. Splitter only sees these siblings. }
  FMainPanel := TPanel.Create(Self);
  With FMainPanel Do
    Begin
      Parent := Self;
      Align := alClient;
      BevelOuter := bvNone;
      Caption := '';
    End;

  { Creation order for alBottom: edge control, then splitter, then alClient. }
  FDetailPanel := TPanel.Create(Self);
  With FDetailPanel Do
    Begin
      Parent := FMainPanel;
      Align := alBottom;
      Height := 140;
      Constraints.MinHeight := 48;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FDetailMemo := TMemo.Create(Self);
  With FDetailMemo Do
    Begin
      Parent := FDetailPanel;
      Align := alClient;
      ReadOnly := True;
      ScrollBars := ssAutoBoth;
      BorderSpacing.Around := 4;
      Font.Name := 'Monospace';
    End;

  FSplitter := TSplitter.Create(Self);
  With FSplitter Do
    Begin
      Parent := FMainPanel;
      Align := alBottom;
      Height := 5;
      AutoSnap := False;
      ResizeControl := FDetailPanel;
      MinSize := 48;
    End;

  FGraphHost := TPanel.Create(Self);
  With FGraphHost Do
    Begin
      Parent := FMainPanel;
      Align := alClient;
      BevelOuter := bvNone;
      Caption := '';
      OnResize := @GraphHostResize;
    End;

  FScrollBar := TScrollBar.Create(Self);
  With FScrollBar Do
    Begin
      Parent := FGraphHost;
      Kind := sbVertical;
      Align := alRight;
      Width := 16;
      Min := 0;
      Max := 0;
      PageSize := 0;
      OnChange := @ScrollBarChange;
    End;

  FPaintBox := TPaintBox.Create(Self);
  With FPaintBox Do
    Begin
      Parent := FGraphHost;
      Align := alClient;
      OnPaint := @PaintBoxPaint;
      OnMouseDown := @PaintBoxMouseDown;
      OnMouseWheel := @PaintBoxMouseWheel;
    End;

  FDetailTimer := TTimer.Create(Self);
  FDetailTimer.Enabled := False;
  FDetailTimer.Interval := 40;
  FDetailTimer.OnTimer := @DetailTimerTimer;

  OnCreate := @FormCreate;
  OnDestroy := @FormDestroy;
  OnShow := @FormShow;
End;

Procedure TGitGraphForm.FormCreate(Sender: TObject);
Begin
  WorkflowLogger.Info('GitGraph', 'Git Graph window created');
End;

Procedure TGitGraphForm.FormDestroy(Sender: TObject);
Begin
  WorkflowLogger.Info('GitGraph', 'Git Graph window destroyed');
End;

Procedure TGitGraphForm.FormShow(Sender: TObject);
Begin
  BindRepository;
End;

Function TGitGraphForm.ScrollOffset: Integer;
Begin
  Result := FScrollBar.Position;
End;

Procedure TGitGraphForm.StopIndexThread;
Begin
  If Assigned(FIndexThread) Then
    Begin
      FIndexThread.Terminate;
      FIndexThread.WaitFor;
      FreeAndNil(FIndexThread);
    End;
  FIndexing := False;
End;

Procedure TGitGraphForm.StopDetailThread;
Begin
  If Assigned(FDetailThread) Then
    Begin
      FDetailThread.Terminate;
      FDetailThread.WaitFor;
      FreeAndNil(FDetailThread);
    End;
  FDetailLoading := False;
End;

Procedure TGitGraphForm.StartIndexLoad;
Begin
  If FRepoPath = '' Then
    Exit;
  StopDetailThread;
  StopIndexThread;
  FIndexing := True;
  FStatusFooter.SetRightText('Indexing…');
  FIndexThread := TGitIndexThread.Create(Self, FRepoPath);
  FIndexThread.Start;
End;

Procedure TGitGraphForm.ApplyIndexLoaded;
Var
  Parsed: Integer;
Begin
  FIndexing := False;
  If Not FPendingIndexOk Then
    Begin
      FStatusFooter.SetRightText('Index failed');
      WorkflowLogger.Warning('GitGraph', 'rev-list failed for ' + FRepoPath);
      Exit;
    End;

  Parsed := FModel.ParseRevListParents(FPendingIndexText);
  FPendingIndexText := '';
  FSelectedIndex := -1;
  If Parsed > 0 Then
    FSelectedIndex := 0;

  UpdateScrollRange;
  If FSelectedIndex >= 0 Then
    ShowCommitDetails(FSelectedIndex)
  Else
    FDetailMemo.Clear;

  UpdateStatus;
  FPaintBox.Invalidate;
  ScheduleVisibleDetails;
  WorkflowLogger.Info('GitGraph', Format('Indexed %d commits', [Parsed]));
End;

Procedure TGitGraphForm.ApplyDetailsLoaded;
Begin
  FDetailLoading := False;
  If FPendingDetailsOk Then
    FModel.ApplyDetailsText(FPendingDetailsText);
  FPendingDetailsText := '';
  If (FSelectedIndex >= 0) And FModel.Commit(FSelectedIndex).DetailsLoaded Then
    ShowCommitDetails(FSelectedIndex);
  FPaintBox.Invalidate;
  { More rows may still be missing after scrolling. }
  ScheduleVisibleDetails;
End;

Procedure TGitGraphForm.GetVisibleRange(Out FirstRow, LastRow: Integer);
Var
  ViewH: Integer;
Begin
  FirstRow := 0;
  LastRow := -1;
  If FModel.Count = 0 Then
    Exit;
  ViewH := FPaintBox.ClientHeight;
  If ViewH < 1 Then
    ViewH := 1;
  FirstRow := ScrollOffset Div GitGraphRowHeight;
  LastRow := (ScrollOffset + ViewH) Div GitGraphRowHeight;
  If FirstRow < 0 Then
    FirstRow := 0;
  If LastRow >= FModel.Count Then
    LastRow := FModel.Count - 1;
End;

Procedure TGitGraphForm.ScheduleVisibleDetails;
Begin
  If FIndexing Or (FRepoPath = '') Or (FModel.Count = 0) Then
    Exit;
  GetVisibleRange(FVisibleFirst, FVisibleLast);
  FDetailTimer.Enabled := False;
  FDetailTimer.Enabled := True;
End;

Procedure TGitGraphForm.DetailTimerTimer(Sender: TObject);
Begin
  FDetailTimer.Enabled := False;
  StartDetailLoadIfNeeded;
End;

Procedure TGitGraphForm.StartDetailLoadIfNeeded;
Var
  First, Last: Integer;
  Shas: TStringList;
  Missing: Integer;
Begin
  If FDetailLoading Or FIndexing Or (FRepoPath = '') Then
    Exit;

  GetVisibleRange(First, Last);
  First := Max(0, First - GitGraphPrefetchRows);
  Last := Min(FModel.Count - 1, Last + GitGraphPrefetchRows);
  Missing := FModel.CollectMissingShas(First, Last, Shas);
  If Missing = 0 Then
    Begin
      Shas.Free;
      Exit;
    End;

  FDetailLoading := True;
  FDetailThread := TGitDetailThread.Create(Self, FRepoPath, Shas);
  FDetailThread.Start;
End;

Procedure TGitGraphForm.UpdateScrollRange;
Var
  ViewH, ContentH, MaxPos: Integer;
Begin
  ViewH := FPaintBox.ClientHeight;
  If ViewH < 1 Then
    ViewH := 1;
  ContentH := FModel.TotalHeight;
  MaxPos := ContentH - ViewH;
  If MaxPos < 0 Then
    MaxPos := 0;
  FScrollBar.Min := 0;
  FScrollBar.SmallChange := GitGraphRowHeight;
  FScrollBar.LargeChange := ViewH;
  { Position runs 0..Max; PageSize 0 avoids platform-specific range quirks. }
  FScrollBar.PageSize := 0;
  FScrollBar.Max := MaxPos;
  If FScrollBar.Position > MaxPos Then
    FScrollBar.Position := MaxPos;
  FScrollBar.Enabled := MaxPos > 0;
End;

Procedure TGitGraphForm.GraphHostResize(Sender: TObject);
Begin
  UpdateScrollRange;
  ScheduleVisibleDetails;
  FPaintBox.Invalidate;
End;

Procedure TGitGraphForm.ScrollBarChange(Sender: TObject);
Begin
  ScheduleVisibleDetails;
  FPaintBox.Invalidate;
End;

Procedure TGitGraphForm.PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; Var Handled: Boolean);
Var
  NewPos, MaxPos, ViewH: Integer;
Begin
  ViewH := FPaintBox.ClientHeight;
  MaxPos := FModel.TotalHeight - ViewH;
  If MaxPos < 0 Then
    MaxPos := 0;
  NewPos := FScrollBar.Position - (WheelDelta Div 120) * GitGraphRowHeight * 3;
  If NewPos < 0 Then
    NewPos := 0;
  If NewPos > MaxPos Then
    NewPos := MaxPos;
  If NewPos <> FScrollBar.Position Then
    FScrollBar.Position := NewPos;
  Handled := True;
End;

Function TGitGraphForm.LaneX(Lane: Integer): Integer;
Begin
  Result := GitGraphLeftMargin + Lane * GitGraphLaneWidth + GitGraphLaneWidth Div 2;
End;

Function TGitGraphForm.RowMidY(Row: Integer): Integer;
Begin
  Result := Row * GitGraphRowHeight + GitGraphRowHeight Div 2 - ScrollOffset;
End;

Function TGitGraphForm.RowAtY(Y: Integer): Integer;
Begin
  If FModel.Count = 0 Then
    Result := -1
  Else
    Begin
      Result := (Y + ScrollOffset) Div GitGraphRowHeight;
      If (Result < 0) Or (Result >= FModel.Count) Then
        Result := -1;
    End;
End;

Function TGitGraphForm.FormatCommitDate(Const CommitTime: Int64): String;
Begin
  If CommitTime <= 0 Then
    Result := '…'
  Else
    Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(CommitTime));
End;

Procedure TGitGraphForm.PaintBoxPaint(Sender: TObject);
Var
  FirstRow, LastRow, I, TextX, Y, X, Off: Integer;
  C: TGitCommitRec;
  E: TGitGraphEdge;
  Col: TColor;
  LabelText, DateText: String;
Begin
  Off := ScrollOffset;
  With FPaintBox.Canvas Do
    Begin
      Brush.Color := clWindow;
      FillRect(FPaintBox.ClientRect);

      If FIndexing And (FModel.Count = 0) Then
        Begin
          Font.Color := clGrayText;
          Font.Size := 11;
          TextOut(16, 16, 'Indexing commit history…');
          Exit;
        End;

      If FModel.Count = 0 Then
        Begin
          Font.Color := clGrayText;
          Font.Size := 11;
          If FRepoPath = '' Then
            TextOut(16, 16, 'No Git repository detected for the active project')
          Else
            TextOut(16, 16, 'No commits to display');
          Exit;
        End;

      GetVisibleRange(FirstRow, LastRow);
      If LastRow < FirstRow Then
        Exit;

      Pen.Width := 2;
      For I := 0 To FModel.EdgeCount - 1 Do
        Begin
          E := FModel.Edge(I);
          If (E.ChildIndex > LastRow) Or (E.ParentIndex < FirstRow) Then
            Continue;
          Col := FLaneColors[FModel.LaneColorIndex(E.ChildLane)];
          Pen.Color := Col;
          X := LaneX(E.ChildLane);
          If E.ChildLane = E.ParentLane Then
            Line(X, RowMidY(E.ChildIndex), LaneX(E.ParentLane), RowMidY(E.ParentIndex))
          Else
            Begin
              Line(X, RowMidY(E.ChildIndex), X, RowMidY(E.ParentIndex));
              Line(X, RowMidY(E.ParentIndex), LaneX(E.ParentLane), RowMidY(E.ParentIndex));
            End;
        End;

      Font.Size := 9;
      For I := FirstRow To LastRow Do
        Begin
          C := FModel.Commit(I);
          Y := I * GitGraphRowHeight - Off;

          If I = FSelectedIndex Then
            Begin
              Brush.Color := RGBToColor(227, 242, 253);
              FillRect(Bounds(0, Y, FPaintBox.Width, GitGraphRowHeight));
            End;

          Col := FLaneColors[FModel.LaneColorIndex(C.Lane)];
          X := LaneX(C.Lane);
          Brush.Color := Col;
          Pen.Color := Col;
          Ellipse(X - GitGraphNodeRadius, RowMidY(I) - GitGraphNodeRadius,
            X + GitGraphNodeRadius, RowMidY(I) + GitGraphNodeRadius);

          TextX := FModel.GraphWidth + GitGraphTextGap;
          Brush.Style := bsClear;
          Font.Color := clGrayText;
          DateText := FormatCommitDate(C.CommitTime);
          TextOut(TextX, Y + 3, DateText);
          Font.Color := clWindowText;
          If C.DetailsLoaded Then
            Begin
              LabelText := C.Subject;
              If C.Refs <> '' Then
                LabelText := LabelText + '  (' + C.Refs + ')';
            End
          Else
            LabelText := '…';
          TextOut(TextX + 130, Y + 3, LabelText);
          Brush.Style := bsSolid;
        End;
    End;
End;

Procedure TGitGraphForm.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
Var
  Row: Integer;
Begin
  If Button <> mbLeft Then
    Exit;
  Row := RowAtY(Y);
  If Row < 0 Then
    Exit;
  FSelectedIndex := Row;
  ShowCommitDetails(Row);
  FPaintBox.Invalidate;
  If Not FModel.Commit(Row).DetailsLoaded Then
    ScheduleVisibleDetails;
End;

Procedure TGitGraphForm.ShowCommitDetails(Index: Integer);
Var
  C: TGitCommitRec;
  When: TDateTime;
  I: Integer;
  ParentLine: String;
Begin
  If (Index < 0) Or (Index >= FModel.Count) Then
    Begin
      FDetailMemo.Clear;
      Exit;
    End;
  C := FModel.Commit(Index);
  FDetailMemo.Lines.BeginUpdate;
  Try
    FDetailMemo.Lines.Clear;
    FDetailMemo.Lines.Add('Commit:  ' + C.Sha);
    If C.DetailsLoaded Then
      Begin
        FDetailMemo.Lines.Add('Author:  ' + C.Author);
        If C.CommitTime > 0 Then
          Begin
            When := UnixToDateTime(C.CommitTime);
            FDetailMemo.Lines.Add('Date:    ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', When));
          End;
      End
    Else
      FDetailMemo.Lines.Add('(loading details…)');
    If C.ParentCount > 0 Then
      Begin
        ParentLine := C.Parents[0];
        For I := 1 To C.ParentCount - 1 Do
          ParentLine := ParentLine + ' ' + C.Parents[I];
        FDetailMemo.Lines.Add('Parents: ' + ParentLine);
      End;
    If C.DetailsLoaded And (C.Refs <> '') Then
      FDetailMemo.Lines.Add('Refs:    ' + C.Refs);
    If C.DetailsLoaded Then
      Begin
        FDetailMemo.Lines.Add('');
        FDetailMemo.Lines.Add(C.Subject);
      End;
  Finally
    FDetailMemo.Lines.EndUpdate;
  End;
End;

Procedure TGitGraphForm.RefreshActionExecute(Sender: TObject);
Begin
  WorkflowLogger.Info('GitGraph', 'Manual refresh requested');
  BindRepository;
End;

Procedure TGitGraphForm.UpdateStatus;
Var
  LeftText, CentreText, RightText: String;
  ShortSha: String;
Begin
  If FRepoPath = '' Then
    Begin
      FStatusFooter.SetAll('No repository', '', 'Ready');
      Exit;
    End;

  If FBranch <> '' Then
    LeftText := FBranch
  Else
    LeftText := ExtractFileName(ExcludeTrailingPathDelimiter(FRepoPath));

  ShortSha := FHeadSha;
  If Length(ShortSha) > 7 Then
    ShortSha := Copy(ShortSha, 1, 7);
  If ShortSha <> '' Then
    CentreText := ShortSha + '  ·  ' + FRepoPath
  Else
    CentreText := FRepoPath;

  If FIndexing Then
    RightText := 'Indexing…'
  Else If FModel.Count > 0 Then
    Begin
      RightText := Format('%d commits', [FModel.Count]);
      If FClean Then
        RightText := RightText + ' · Clean'
      Else
        RightText := RightText + ' · Dirty';
    End
  Else If FClean Then
    RightText := 'Clean'
  Else
    RightText := 'Dirty';

  FStatusFooter.SetAll(LeftText, CentreText, RightText);
End;

Procedure TGitGraphForm.RefreshRepositoryInfo;
Var
  Branch, Sha, Porcelain: String;
  Clean: Boolean;
Begin
  FBranch := '';
  FHeadSha := '';
  FClean := True;
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;

  GitClient.RepoPath := FRepoPath;
  If GitClient.GetCurrentBranch(Branch) Then
    FBranch := Branch;
  If GitClient.GetHeadSha(Sha) Then
    FHeadSha := Sha;
  If GitClient.GetStatus(Clean, Porcelain) Then
    FClean := Clean;
End;

Procedure TGitGraphForm.BindRepository(Const StartPath: String);
Var
  SearchPath, Found: String;
Begin
  SearchPath := StartPath;
  If SearchPath = '' Then
    SearchPath := DetectStartPathFromIDE;
  If SearchPath = '' Then
    SearchPath := GetCurrentDir;

  Found := '';
  If Assigned(GitClient) And (SearchPath <> '') Then
    Found := GitClient.DetectRepository(SearchPath);

  If Found <> '' Then
    WorkflowLogger.Info('GitGraph', 'Bound repository: ' + Found)
  Else
    WorkflowLogger.Warning('GitGraph', 'No repository found from: ' + SearchPath);

  SetRepository(Found);
End;

Procedure TGitGraphForm.SetRepository(Const ARepoPath: String);
Begin
  StopDetailThread;
  StopIndexThread;
  FRepoPath := ARepoPath;
  FSelectedIndex := -1;
  FModel.Clear;
  FScrollBar.Position := 0;
  If Assigned(GitClient) Then
    GitClient.RepoPath := ARepoPath;
  RefreshRepositoryInfo;
  UpdateScrollRange;
  UpdateStatus;
  FPaintBox.Invalidate;
  If FRepoPath <> '' Then
    StartIndexLoad
  Else
    FDetailMemo.Clear;
End;

Procedure TGitGraphForm.RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
Begin
  If SameText(RepoPath, FRepoPath) Then
    BindRepository(FRepoPath);
End;

Procedure TGitGraphForm.WorkingTreeChanged(Const RepoPath: String);
Begin
  If SameText(RepoPath, FRepoPath) Then
    Begin
      RefreshRepositoryInfo;
      UpdateStatus;
    End;
End;

Procedure TGitGraphForm.HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
Begin
  If SameText(RepoPath, FRepoPath) Then
    BindRepository(FRepoPath);
End;

Procedure TGitGraphForm.RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
Begin
  If SameText(RepoPath, FRepoPath) Then
    FStatusFooter.SetRightText('Remote ' + RemoteName + ' updated');
End;

End.
