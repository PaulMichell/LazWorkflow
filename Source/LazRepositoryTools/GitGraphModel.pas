Unit GitGraphModel;

{ Virtual commit graph model (c) 2026 Michell Computing.

  Index phase: rev-list --parents builds SHA/parent skeleton + lane layout for the
  entire history (compact). Detail phase: subject/author/time/refs filled on demand
  for visible rows only. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs;

Const
  GitGraphFieldSep = #1;
  { Design metrics at 96 DPI. Scale with TControl.Scale96ToForm before painting or hit-testing. }
  GitGraphRowHeight = 22;
  GitGraphLaneWidth = 16;
  GitGraphLeftMargin = 12;
  GitGraphNodeRadius = 4;
  GitGraphTextGap = 10;
  GitGraphDateGap = 12; { padding after the measured date column }
  GitGraphDetailBatch = 80;
  GitGraphPrefetchRows = 30;

Type
  TGitCommitRec = Record
    Sha: String;
    ParentCount: Integer;
    Parents: Array Of String;
    Subject: String;
    Author: String;
    CommitTime: Int64;
    Refs: String;
    Lane: Integer;
    DetailsLoaded: Boolean;
  End;

  TGitGraphEdge = Record
    ChildIndex: Integer;
    ParentIndex: Integer;
    ChildLane: Integer;
    ParentLane: Integer;
  End;

  TGitEdgeIndices = Array Of Integer;

  TGitGraphModel = Class
  Private
    FCommits: Array Of TGitCommitRec;
    FEdges: Array Of TGitGraphEdge;
    FCount: Integer;
    FEdgeCount: Integer;
    FEdgeMaxParent: Array Of Integer;
    FLaneCount: Integer;
    FPrimarySha: String;
    FShaIndex: TFPDataHashTable;
    Function BuildEdgeIntervals(Node, First, Last: Integer): Integer;
    Procedure ClearIndex;
    Procedure EnsureCapacity(MinCount: Integer);
    Procedure EnsureEdgeCapacity(MinCount: Integer);
    Function IndexOfSha(Const Sha: String): Integer;
    Procedure BuildShaIndex;
    Procedure LayoutLanes;
    Procedure BuildEdges;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Clear;
    { Parse `git rev-list --topo-order --parents` output (full history index).
      PrimarySha, when present, keeps that commit's first-parent line on lane 0. }
    Function ParseRevListParents(Const RevListText: String; Const PrimarySha: String = ''): Integer;
    { Merge SOH-delimited detail lines from FetchCommitDetails into matching rows. }
    Function ApplyDetailsText(Const DetailsText: String): Integer;
    { Collect SHAs in [First..Last] that still need details (inclusive). }
    Function CollectMissingShas(FirstIndex, LastIndex: Integer; Out Shas: TStringList): Integer;
    Procedure RebuildLayout;
    Function Commit(Index: Integer): TGitCommitRec;
    /// Row of a commit SHA, or -1. Match is case-insensitive.
    Function IndexOf(Const Sha: String): Integer;
    Function VisibleEdges(FirstRow, LastRow: Integer): TGitEdgeIndices;
    Function Edge(Index: Integer): TGitGraphEdge;
    { RowHeight / LeftMargin / LaneWidth must already be DPI-scaled device pixels. }
    Function TotalHeight(RowHeight: Integer): Integer;
    Function GraphWidth(LeftMargin, LaneWidth: Integer): Integer;
    Function LaneColorIndex(Lane: Integer): Integer;
    Property Count: Integer Read FCount;
    Property EdgeCount: Integer Read FEdgeCount;
    Property LaneCount: Integer Read FLaneCount;
  End;

Implementation

Constructor TGitGraphModel.Create;
Begin
  Inherited Create;
  FShaIndex := TFPDataHashTable.CreateWith(4096, @RSHash);
  FCount := 0;
  FEdgeCount := 0;
  FLaneCount := 0;
End;

Destructor TGitGraphModel.Destroy;
Begin
  Clear;
  FreeAndNil(FShaIndex);
  Inherited Destroy;
End;

Procedure TGitGraphModel.ClearIndex;
Begin
  If Assigned(FShaIndex) Then
    FShaIndex.Clear;
End;

Procedure TGitGraphModel.Clear;
Begin
  ClearIndex;
  SetLength(FCommits, 0);
  SetLength(FEdges, 0);
  FEdgeMaxParent := Nil;
  FCount := 0;
  FEdgeCount := 0;
  FLaneCount := 0;
  FPrimarySha := '';
End;

Procedure TGitGraphModel.EnsureCapacity(MinCount: Integer);
Var
  Cap: Integer;
Begin
  Cap := Length(FCommits);
  If Cap >= MinCount Then
    Exit;
  If Cap = 0 Then
    Cap := 512;
  While Cap < MinCount Do
    Cap := Cap * 2;
  SetLength(FCommits, Cap);
End;

Procedure TGitGraphModel.EnsureEdgeCapacity(MinCount: Integer);
Var
  Cap: Integer;
Begin
  Cap := Length(FEdges);
  If Cap >= MinCount Then
    Exit;
  If Cap = 0 Then
    Cap := 512;
  While Cap < MinCount Do
    Cap := Cap * 2;
  SetLength(FEdges, Cap);
End;

Function TGitGraphModel.IndexOfSha(Const Sha: String): Integer;
Var
  P: Pointer;
Begin
  Result := -1;
  If (Sha = '') Or Not Assigned(FShaIndex) Then
    Exit;
  P := FShaIndex.Items[Sha];
  If P <> Nil Then
    Result := Integer(PtrUInt(P) - 1);
End;

Procedure TGitGraphModel.BuildShaIndex;
Var
  I: Integer;
Begin
  ClearIndex;
  For I := 0 To FCount - 1 Do
    FShaIndex.Add(FCommits[I].Sha, Pointer(PtrUInt(I + 1)));
End;

Procedure SkipLineEnd(Const S: String; Var Pos: Integer);
Var
  L: Integer;
Begin
  L := Length(S);
  If (Pos <= L) And (S[Pos] = #13) Then
    Inc(Pos);
  If (Pos <= L) And (S[Pos] = #10) Then
    Inc(Pos);
End;

Function NextToken(Const S: String; Var Pos: Integer): String;
Var
  StartPos, L: Integer;
Begin
  L := Length(S);
  While (Pos <= L) And ((S[Pos] = ' ') Or (S[Pos] = #9)) Do
    Inc(Pos);
  StartPos := Pos;
  While (Pos <= L) And (S[Pos] <> ' ') And (S[Pos] <> #9) And (S[Pos] <> #10) And (S[Pos] <> #13) Do
    Inc(Pos);
  Result := Copy(S, StartPos, Pos - StartPos);
End;

Function TGitGraphModel.ParseRevListParents(Const RevListText: String; Const PrimarySha: String): Integer;
Var
  Pos, L, PCount, K: Integer;
  Sha, Tok: String;
  ParentBuf: Array Of String;
Begin
  Clear;
  FPrimarySha := Trim(PrimarySha);
  Result := 0;
  L := Length(RevListText);
  Pos := 1;
  While Pos <= L Do
    Begin
      If (RevListText[Pos] = #10) Or (RevListText[Pos] = #13) Then
        Begin
          SkipLineEnd(RevListText, Pos);
          Continue;
        End;

      Sha := NextToken(RevListText, Pos);
      If Sha = '#primary' Then
        Begin
          Tok := NextToken(RevListText, Pos);
          If (FPrimarySha = '') And (Tok <> '') Then
            FPrimarySha := Tok;
          While (Pos <= L) And (RevListText[Pos] <> #10) And (RevListText[Pos] <> #13) Do
            Inc(Pos);
          SkipLineEnd(RevListText, Pos);
          Continue;
        End;
      If Length(Sha) < 7 Then
        Begin
          While (Pos <= L) And (RevListText[Pos] <> #10) And (RevListText[Pos] <> #13) Do
            Inc(Pos);
          SkipLineEnd(RevListText, Pos);
          Continue;
        End;

      PCount := 0;
      SetLength(ParentBuf, 0);
      While (Pos <= L) And (RevListText[Pos] <> #10) And (RevListText[Pos] <> #13) Do
        Begin
          Tok := NextToken(RevListText, Pos);
          If Tok = '' Then
            Break;
          Inc(PCount);
          SetLength(ParentBuf, PCount);
          ParentBuf[PCount - 1] := Tok;
        End;
      SkipLineEnd(RevListText, Pos);

      EnsureCapacity(FCount + 1);
      FCommits[FCount].Sha := Sha;
      FCommits[FCount].ParentCount := PCount;
      SetLength(FCommits[FCount].Parents, PCount);
      For K := 0 To PCount - 1 Do
        FCommits[FCount].Parents[K] := ParentBuf[K];
      FCommits[FCount].Subject := '';
      FCommits[FCount].Author := '';
      FCommits[FCount].CommitTime := 0;
      FCommits[FCount].Refs := '';
      FCommits[FCount].Lane := 0;
      FCommits[FCount].DetailsLoaded := False;
      Inc(FCount);
    End;

  RebuildLayout;
  Result := FCount;
End;

Function NextField(Const S: String; Var Pos: Integer; Sep: Char): String;
Var
  StartPos, L: Integer;
Begin
  L := Length(S);
  StartPos := Pos;
  While (Pos <= L) And (S[Pos] <> Sep) And (S[Pos] <> #10) And (S[Pos] <> #13) Do
    Inc(Pos);
  Result := Copy(S, StartPos, Pos - StartPos);
  If (Pos <= L) And (S[Pos] = Sep) Then
    Inc(Pos);
End;

Function TGitGraphModel.ApplyDetailsText(Const DetailsText: String): Integer;
Var
  Pos, L, Idx: Integer;
  LineSha, Subject, Author, TimeField, Refs: String;
  TimeVal: Int64;
Begin
  Result := 0;
  L := Length(DetailsText);
  Pos := 1;
  While Pos <= L Do
    Begin
      If (DetailsText[Pos] = #10) Or (DetailsText[Pos] = #13) Then
        Begin
          SkipLineEnd(DetailsText, Pos);
          Continue;
        End;

      LineSha := NextField(DetailsText, Pos, GitGraphFieldSep);
      Subject := NextField(DetailsText, Pos, GitGraphFieldSep);
      Author := NextField(DetailsText, Pos, GitGraphFieldSep);
      TimeField := NextField(DetailsText, Pos, GitGraphFieldSep);
      Refs := NextField(DetailsText, Pos, GitGraphFieldSep);
      SkipLineEnd(DetailsText, Pos);

      Idx := IndexOfSha(LineSha);
      If Idx < 0 Then
        Continue;

      TimeVal := StrToInt64Def(TimeField, 0);
      FCommits[Idx].Subject := Subject;
      FCommits[Idx].Author := Author;
      FCommits[Idx].CommitTime := TimeVal;
      FCommits[Idx].Refs := Refs;
      FCommits[Idx].DetailsLoaded := True;
      Inc(Result);
    End;
End;

Function TGitGraphModel.CollectMissingShas(FirstIndex, LastIndex: Integer; Out Shas: TStringList): Integer;
Var
  I: Integer;
Begin
  Shas := TStringList.Create;
  Shas.Capacity := GitGraphDetailBatch;
  Result := 0;
  If FCount = 0 Then
    Exit;
  If FirstIndex < 0 Then
    FirstIndex := 0;
  If LastIndex >= FCount Then
    LastIndex := FCount - 1;
  If FirstIndex > LastIndex Then
    Exit;

  For I := FirstIndex To LastIndex Do
    If Not FCommits[I].DetailsLoaded Then
      Begin
        Shas.Add(FCommits[I].Sha);
        Inc(Result);
        If Result >= GitGraphDetailBatch Then
          Break;
      End;
End;

Procedure TGitGraphModel.LayoutLanes;
Var
  Active: Array Of String;
  OnSpine: Array Of Boolean;
  I, J, Lane, P, ParentLane, SpineAt, MinLane: Integer;
  Sha: String;
  HasSpine: Boolean;

  Function CommitOnSpine(Const CommitSha: String): Boolean;
  Var
    Idx: Integer;
  Begin
    Idx := IndexOfSha(CommitSha);
    Result := (Idx >= 0) And OnSpine[Idx];
  End;

  Function TakeFreeLane(Lowest: Integer): Integer;
  Var
    Slot: Integer;
  Begin
    For Slot := Lowest To High(Active) Do
      If Active[Slot] = '' Then
        Exit(Slot);
    Result := Length(Active);
    If Result < Lowest Then
      Result := Lowest;
    SetLength(Active, Result + 1);
    Active[Result] := '';
  End;

Begin
  FLaneCount := 0;
  If FCount = 0 Then
    Exit;

  { Lane 0 is the first-parent line of main (or HEAD when main is absent).
    Diverging tips use the lanes to its right, whatever rev-list order they arrive in. }
  HasSpine := False;
  SetLength(OnSpine, FCount);
  For I := 0 To FCount - 1 Do
    OnSpine[I] := False;
  If FPrimarySha <> '' Then
    Begin
      SpineAt := IndexOf(FPrimarySha);
      While SpineAt >= 0 Do
        Begin
          OnSpine[SpineAt] := True;
          HasSpine := True;
          If FCommits[SpineAt].ParentCount < 1 Then
            Break;
          SpineAt := IndexOf(FCommits[SpineAt].Parents[0]);
        End;
    End;

  Active := Nil;
  If HasSpine Then
    Begin
      SetLength(Active, 1);
      Active[0] := '';
    End;
  For I := 0 To FCount - 1 Do
    Begin
      Sha := FCommits[I].Sha;
      If HasSpine Then
        MinLane := 1
      Else
        MinLane := 0;

      If OnSpine[I] Then
        Lane := 0
      Else
        Begin
          Lane := -1;
          For J := MinLane To High(Active) Do
            If Active[J] = Sha Then
              Begin
                Lane := J;
                Break;
              End;
          If Lane < 0 Then
            Lane := TakeFreeLane(MinLane);
        End;

      FCommits[I].Lane := Lane;
      If Lane + 1 > FLaneCount Then
        FLaneCount := Lane + 1;

      For J := 0 To High(Active) Do
        If Active[J] = Sha Then
          Active[J] := '';

      If OnSpine[I] Then
        Begin
          If Length(Active) < 1 Then
            Begin
              SetLength(Active, 1);
              Active[0] := '';
            End;
          If FCommits[I].ParentCount > 0 Then
            Active[0] := FCommits[I].Parents[0]
          Else
            Active[0] := '';
        End
      Else If (FCommits[I].ParentCount > 0) And Not CommitOnSpine(FCommits[I].Parents[0]) Then
        Active[Lane] := FCommits[I].Parents[0]
      Else If Lane <= High(Active) Then
        Active[Lane] := '';

      For P := 1 To FCommits[I].ParentCount - 1 Do
        Begin
          If CommitOnSpine(FCommits[I].Parents[P]) Then
            Continue;
          ParentLane := -1;
          For J := MinLane To High(Active) Do
            If Active[J] = FCommits[I].Parents[P] Then
              Begin
                ParentLane := J;
                Break;
              End;
          If ParentLane < 0 Then
            Begin
              ParentLane := TakeFreeLane(MinLane);
              Active[ParentLane] := FCommits[I].Parents[P];
              If ParentLane + 1 > FLaneCount Then
                FLaneCount := ParentLane + 1;
            End;
        End;
    End;

  If Length(Active) > FLaneCount Then
    FLaneCount := Length(Active);
  If FLaneCount < 1 Then
    FLaneCount := 1;
End;

Procedure TGitGraphModel.BuildEdges;
Var
  I, P, ParentIdx: Integer;
Begin
  FEdgeCount := 0;
  For I := 0 To FCount - 1 Do
    For P := 0 To FCommits[I].ParentCount - 1 Do
      Begin
        ParentIdx := IndexOfSha(FCommits[I].Parents[P]);
        If ParentIdx < 0 Then
          Continue;
        EnsureEdgeCapacity(FEdgeCount + 1);
        FEdges[FEdgeCount].ChildIndex := I;
        FEdges[FEdgeCount].ParentIndex := ParentIdx;
        FEdges[FEdgeCount].ChildLane := FCommits[I].Lane;
        FEdges[FEdgeCount].ParentLane := FCommits[ParentIdx].Lane;
        Inc(FEdgeCount);
      End;
  SetLength(FEdgeMaxParent, FEdgeCount * 4);
  If FEdgeCount > 0 Then BuildEdgeIntervals(0, 0, FEdgeCount - 1);
End;

Function TGitGraphModel.BuildEdgeIntervals(Node, First, Last: Integer): Integer;
Var Mid, LeftMax, RightMax: Integer;
Begin
  If First = Last Then Result := FEdges[First].ParentIndex
  Else
    Begin
      Mid := First + (Last - First) Div 2;
      LeftMax := BuildEdgeIntervals(Node * 2 + 1, First, Mid);
      RightMax := BuildEdgeIntervals(Node * 2 + 2, Mid + 1, Last);
      If LeftMax > RightMax Then Result := LeftMax Else Result := RightMax;
    End;
  FEdgeMaxParent[Node] := Result;
End;

Function TGitGraphModel.VisibleEdges(FirstRow, LastRow: Integer): TGitEdgeIndices;
Var Found: Integer;
  Procedure Visit(Node, First, Last: Integer);
  Var Mid: Integer;
  Begin
    If (FEdgeMaxParent[Node] < FirstRow) Or (FEdges[First].ChildIndex > LastRow) Then Exit;
    If First = Last Then
      Begin
        If Found = Length(Result) Then SetLength(Result, Found * 2 + 16);
        Result[Found] := First; Inc(Found); Exit;
      End;
    Mid := First + (Last - First) Div 2;
    Visit(Node * 2 + 1, First, Mid);
    Visit(Node * 2 + 2, Mid + 1, Last);
  End;
Begin
  Result := Nil; Found := 0;
  If (FEdgeCount > 0) And (LastRow >= FirstRow) Then Visit(0, 0, FEdgeCount - 1);
  SetLength(Result, Found);
End;

Procedure TGitGraphModel.RebuildLayout;
Begin
  BuildShaIndex;
  LayoutLanes;
  BuildEdges;
End;

Function TGitGraphModel.IndexOf(Const Sha: String): Integer;
Var
  I: Integer;
Begin
  Result := IndexOfSha(Sha);
  If Result >= 0 Then
    Exit;
  For I := 0 To FCount - 1 Do
    If SameText(FCommits[I].Sha, Sha) Then
      Exit(I);
  Result := -1;
End;

Function TGitGraphModel.Commit(Index: Integer): TGitCommitRec;
Begin
  If (Index < 0) Or (Index >= FCount) Then
    Begin
      Result.Sha := '';
      Result.ParentCount := 0;
      SetLength(Result.Parents, 0);
      Result.Subject := '';
      Result.Author := '';
      Result.CommitTime := 0;
      Result.Refs := '';
      Result.Lane := 0;
      Result.DetailsLoaded := False;
      Exit;
    End;
  Result := FCommits[Index];
End;

Function TGitGraphModel.Edge(Index: Integer): TGitGraphEdge;
Begin
  If (Index < 0) Or (Index >= FEdgeCount) Then
    Begin
      Result.ChildIndex := -1;
      Result.ParentIndex := -1;
      Result.ChildLane := 0;
      Result.ParentLane := 0;
      Exit;
    End;
  Result := FEdges[Index];
End;

Function TGitGraphModel.TotalHeight(RowHeight: Integer): Integer;
Var
  RH: Integer;
Begin
  If RowHeight > 0 Then
    RH := RowHeight
  Else
    RH := GitGraphRowHeight;
  Result := FCount * RH;
  If Result < RH Then
    Result := RH;
End;

Function TGitGraphModel.GraphWidth(LeftMargin, LaneWidth: Integer): Integer;
Var
  LM, LW: Integer;
Begin
  If LeftMargin > 0 Then
    LM := LeftMargin
  Else
    LM := GitGraphLeftMargin;
  If LaneWidth > 0 Then
    LW := LaneWidth
  Else
    LW := GitGraphLaneWidth;
  Result := LM + FLaneCount * LW + LW;
End;

Function TGitGraphModel.LaneColorIndex(Lane: Integer): Integer;
Begin
  If Lane < 0 Then
    Result := 0
  Else
    Result := Lane Mod 10;
End;

End.
