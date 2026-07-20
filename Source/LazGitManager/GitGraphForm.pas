Unit GitGraphForm;

{ High-quality commit history graph window (c) 2026 Michell Computing.

  Performance: git log runs on a worker thread; only the visible row range is
  painted; load is bounded (chunk growth) so large repos stay responsive. }

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
    FGraphPanel: TScrollBox;
    FPaintBox: TPaintBox;
    FStatusFooter: TStatusFooterFrame;
    FSplitter: TSplitter;
    FDetailPanel: TPanel;
    FDetailMemo: TMemo;
    FActionList: TActionList;
    FRefreshAction: TAction;
    FLoadMoreAction: TAction;
    FRepoPath: String;
    FBranch: String;
    FHeadSha: String;
    FClean: Boolean;
    FModel: TGitGraphModel;
    FSelectedIndex: Integer;
    FLoadLimit: Integer;
    FTotalCommits: Integer;
    FLoading: Boolean;
    FLoadThread: TThread;
    FPendingLogText: String;
    FPendingOk: Boolean;
    FLaneColors: Array[0..9] Of TColor;
    Procedure CreateUI;
    Procedure InitLaneColors;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure PaintBoxPaint(Sender: TObject);
    Procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    Procedure GraphPanelResize(Sender: TObject);
    Procedure RefreshActionExecute(Sender: TObject);
    Procedure LoadMoreActionExecute(Sender: TObject);
    Procedure UpdateStatus;
    Procedure RefreshRepositoryInfo;
    Procedure ApplyLoadedLog;
    Procedure StartLogLoad(NewLimit: Integer);
    Procedure StopLoadThread;
    Procedure UpdatePaintBoxSize;
    Procedure ShowCommitDetails(Index: Integer);
    Function RowAtY(Y: Integer): Integer;
    Function LaneX(Lane: Integer): Integer;
    Function RowMidY(Row: Integer): Integer;
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
  WorkflowLog, GitService, LazIDEIntf, ProjectIntf, DateUtils;

Type
  TGitLogLoadThread = Class(TThread)
  Private
    FForm: TGitGraphForm;
    FRepoPath: String;
    FMaxCount: Integer;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TGitGraphForm; Const ARepoPath: String; AMaxCount: Integer);
  End;

Constructor TGitLogLoadThread.Create(AForm: TGitGraphForm; Const ARepoPath: String;
  AMaxCount: Integer);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FForm := AForm;
  FRepoPath := ARepoPath;
  FMaxCount := AMaxCount;
End;

Procedure TGitLogLoadThread.Execute;
Var
  LogText: String;
  Ok: Boolean;
  LocalClient: TGitService;
Begin
  { Dedicated client instance – no shared mutable path state with the UI thread. }
  LocalClient := TGitService.Create;
  Try
    Ok := LocalClient.FetchLogText(FRepoPath, FMaxCount, LogText);
    If Terminated Then
      Exit;
    FForm.FPendingOk := Ok;
    FForm.FPendingLogText := LogText;
    If Not Terminated Then
      Synchronize(@FForm.ApplyLoadedLog);
  Finally
    LocalClient.Free;
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
  FLoadLimit := GitGraphDefaultChunk;
  FTotalCommits := -1;
  FLoading := False;
  FLoadThread := Nil;
  FModel := TGitGraphModel.Create;
  InitLaneColors;
  CreateUI;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TGitGraphForm.Destroy;
Begin
  StopLoadThread;
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

  FLoadMoreAction := TAction.Create(Self);
  FLoadMoreAction.Caption := 'Load more';
  FLoadMoreAction.OnExecute := @LoadMoreActionExecute;
  FLoadMoreAction.ActionList := FActionList;
  FLoadMoreAction.Enabled := False;

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
  With TToolButton.Create(FToolBar) Do
    Begin
      Parent := FToolBar;
      Action := FLoadMoreAction;
      Style := tbsButton;
    End;

  FStatusFooter := TStatusFooterFrame.Create(Self);
  FStatusFooter.Parent := Self;
  FStatusFooter.Align := alBottom;

  FDetailPanel := TPanel.Create(Self);
  With FDetailPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      Height := 140;
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
      Parent := Self;
      Align := alBottom;
      Height := 5;
    End;

  FGraphPanel := TScrollBox.Create(Self);
  With FGraphPanel Do
    Begin
      Parent := Self;
      Align := alClient;
      BorderStyle := bsNone;
      HorzScrollBar.Tracking := True;
      VertScrollBar.Tracking := True;
      OnResize := @GraphPanelResize;
    End;

  FPaintBox := TPaintBox.Create(Self);
  With FPaintBox Do
    Begin
      Parent := FGraphPanel;
      Left := 0;
      Top := 0;
      Width := 800;
      Height := GitGraphRowHeight;
      OnPaint := @PaintBoxPaint;
      OnMouseDown := @PaintBoxMouseDown;
    End;

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

Procedure TGitGraphForm.StopLoadThread;
Begin
  If Assigned(FLoadThread) Then
    Begin
      FLoadThread.Terminate;
      FLoadThread.WaitFor;
      FreeAndNil(FLoadThread);
    End;
  FLoading := False;
End;

Procedure TGitGraphForm.StartLogLoad(NewLimit: Integer);
Begin
  If FRepoPath = '' Then
    Exit;
  StopLoadThread;
  FLoadLimit := NewLimit;
  If FLoadLimit < GitGraphDefaultChunk Then
    FLoadLimit := GitGraphDefaultChunk;
  If FLoadLimit > GitGraphMaxAutoLoad Then
    FLoadLimit := GitGraphMaxAutoLoad;
  FLoading := True;
  FLoadMoreAction.Enabled := False;
  FStatusFooter.SetRightText('Loading…');
  FLoadThread := TGitLogLoadThread.Create(Self, FRepoPath, FLoadLimit);
  FLoadThread.Start;
End;

Procedure TGitGraphForm.ApplyLoadedLog;
Var
  Parsed: Integer;
  ElapsedHint: String;
Begin
  { Called via Synchronize from the worker – do not free FLoadThread here. }
  FLoading := False;
  If Not FPendingOk Then
    Begin
      FStatusFooter.SetRightText('Log failed');
      WorkflowLogger.Warning('GitGraph', 'git log failed for ' + FRepoPath);
      Exit;
    End;

  Parsed := FModel.ParseLogText(FPendingLogText);
  FPendingLogText := '';
  FSelectedIndex := -1;
  If Parsed > 0 Then
    FSelectedIndex := 0;

  UpdatePaintBoxSize;
  If FSelectedIndex >= 0 Then
    ShowCommitDetails(FSelectedIndex)
  Else
    FDetailMemo.Clear;

  FLoadMoreAction.Enabled := (FModel.Count >= FLoadLimit) And (FLoadLimit < GitGraphMaxAutoLoad);
  If FTotalCommits > 0 Then
    ElapsedHint := Format('%d / %d commits', [FModel.Count, FTotalCommits])
  Else
    ElapsedHint := Format('%d commits', [FModel.Count]);
  If FClean Then
    FStatusFooter.SetRightText(ElapsedHint + ' · Clean')
  Else
    FStatusFooter.SetRightText(ElapsedHint + ' · Dirty');

  FPaintBox.Invalidate;
  WorkflowLogger.Info('GitGraph', Format('Loaded %d commits (limit %d)', [Parsed, FLoadLimit]));
End;

Procedure TGitGraphForm.UpdatePaintBoxSize;
Var
  NeedW, NeedH: Integer;
Begin
  NeedH := FModel.TotalHeight;
  NeedW := FModel.GraphWidth + 640;
  If NeedW < FGraphPanel.ClientWidth Then
    NeedW := FGraphPanel.ClientWidth;
  If NeedH < FGraphPanel.ClientHeight Then
    NeedH := FGraphPanel.ClientHeight;
  FPaintBox.SetBounds(0, 0, NeedW, NeedH);
End;

Procedure TGitGraphForm.GraphPanelResize(Sender: TObject);
Begin
  UpdatePaintBoxSize;
End;

Function TGitGraphForm.LaneX(Lane: Integer): Integer;
Begin
  Result := GitGraphLeftMargin + Lane * GitGraphLaneWidth + GitGraphLaneWidth Div 2;
End;

Function TGitGraphForm.RowMidY(Row: Integer): Integer;
Begin
  Result := Row * GitGraphRowHeight + GitGraphRowHeight Div 2;
End;

Function TGitGraphForm.RowAtY(Y: Integer): Integer;
Begin
  If (Y < 0) Or (FModel.Count = 0) Then
    Result := -1
  Else
    Begin
      Result := Y Div GitGraphRowHeight;
      If Result >= FModel.Count Then
        Result := -1;
    End;
End;

Procedure TGitGraphForm.PaintBoxPaint(Sender: TObject);
Var
  Clip: TRect;
  FirstRow, LastRow, I, TextX, Y, X: Integer;
  C: TGitCommitRec;
  E: TGitGraphEdge;
  Col: TColor;
  LabelText: String;
Begin
  Clip := FPaintBox.Canvas.ClipRect;
  With FPaintBox.Canvas Do
    Begin
      Brush.Color := clWindow;
      FillRect(Clip);

      If FLoading And (FModel.Count = 0) Then
        Begin
          Font.Color := clGrayText;
          Font.Size := 11;
          TextOut(16, 16, 'Loading commit history…');
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

      FirstRow := Clip.Top Div GitGraphRowHeight;
      LastRow := Clip.Bottom Div GitGraphRowHeight + 1;
      If FirstRow < 0 Then
        FirstRow := 0;
      If LastRow >= FModel.Count Then
        LastRow := FModel.Count - 1;

      { Edges first (under nodes). Only those intersecting the visible band. }
      Pen.Width := 2;
      For I := 0 To FModel.EdgeCount - 1 Do
        Begin
          E := FModel.Edge(I);
          If (E.ChildIndex > LastRow) Or (E.ParentIndex < FirstRow) Then
            Continue;
          Col := FLaneColors[FModel.LaneColorIndex(E.ChildLane)];
          Pen.Color := Col;
          X := LaneX(E.ChildLane);
          Y := RowMidY(E.ChildIndex);
          If E.ChildLane = E.ParentLane Then
            Line(X, Y, LaneX(E.ParentLane), RowMidY(E.ParentIndex))
          Else
            Begin
              { Elbow: vertical then horizontal into parent lane. }
              Line(X, Y, X, RowMidY(E.ParentIndex));
              Line(X, RowMidY(E.ParentIndex), LaneX(E.ParentLane), RowMidY(E.ParentIndex));
            End;
        End;

      { Rows: selection, node, labels – visible only. }
      Font.Size := 9;
      For I := FirstRow To LastRow Do
        Begin
          C := FModel.Commit(I);
          Y := I * GitGraphRowHeight;

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
          TextOut(TextX, Y + 3, C.ShortSha);
          Font.Color := clWindowText;
          LabelText := C.Subject;
          If C.Refs <> '' Then
            LabelText := LabelText + '  (' + C.Refs + ')';
          TextOut(TextX + 70, Y + 3, LabelText);
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
  When := UnixToDateTime(C.CommitTime);
  FDetailMemo.Lines.BeginUpdate;
  Try
    FDetailMemo.Lines.Clear;
    FDetailMemo.Lines.Add('Commit:  ' + C.Sha);
    FDetailMemo.Lines.Add('Author:  ' + C.Author);
    FDetailMemo.Lines.Add('Date:    ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', When));
    If C.ParentCount > 0 Then
      Begin
        ParentLine := C.Parents[0];
        For I := 1 To C.ParentCount - 1 Do
          ParentLine := ParentLine + ' ' + C.Parents[I];
        FDetailMemo.Lines.Add('Parents: ' + ParentLine);
      End;
    If C.Refs <> '' Then
      FDetailMemo.Lines.Add('Refs:    ' + C.Refs);
    FDetailMemo.Lines.Add('');
    FDetailMemo.Lines.Add(C.Subject);
  Finally
    FDetailMemo.Lines.EndUpdate;
  End;
End;

Procedure TGitGraphForm.RefreshActionExecute(Sender: TObject);
Begin
  WorkflowLogger.Info('GitGraph', 'Manual refresh requested');
  BindRepository;
End;

Procedure TGitGraphForm.LoadMoreActionExecute(Sender: TObject);
Var
  NextLimit: Integer;
Begin
  If FLoading Or (FRepoPath = '') Then
    Exit;
  NextLimit := FLoadLimit + GitGraphDefaultChunk;
  If NextLimit > GitGraphMaxAutoLoad Then
    NextLimit := GitGraphMaxAutoLoad;
  If NextLimit = FLoadLimit Then
    Exit;
  StartLogLoad(NextLimit);
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

  If FLoading Then
    RightText := 'Loading…'
  Else If FModel.Count > 0 Then
    Begin
      If FTotalCommits > 0 Then
        RightText := Format('%d / %d', [FModel.Count, FTotalCommits])
      Else
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
  Total: Integer;
Begin
  FBranch := '';
  FHeadSha := '';
  FClean := True;
  FTotalCommits := -1;
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;

  GitClient.RepoPath := FRepoPath;
  If GitClient.GetCurrentBranch(Branch) Then
    FBranch := Branch;
  If GitClient.GetHeadSha(Sha) Then
    FHeadSha := Sha;
  If GitClient.GetStatus(Clean, Porcelain) Then
    FClean := Clean;
  { Cheap count for footer; ignore failure. }
  If GitClient.CountCommits(FRepoPath, Total) Then
    FTotalCommits := Total;
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
  StopLoadThread;
  FRepoPath := ARepoPath;
  FSelectedIndex := -1;
  FModel.Clear;
  FLoadLimit := GitGraphDefaultChunk;
  If Assigned(GitClient) Then
    GitClient.RepoPath := ARepoPath;
  RefreshRepositoryInfo;
  UpdateStatus;
  UpdatePaintBoxSize;
  FPaintBox.Invalidate;
  If FRepoPath <> '' Then
    StartLogLoad(FLoadLimit)
  Else
    Begin
      FDetailMemo.Clear;
      FLoadMoreAction.Enabled := False;
    End;
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
