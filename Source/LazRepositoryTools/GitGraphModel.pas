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
    Parents: Array[0..3] Of String;
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

  TGitGraphModel = Class
  Private
    FCommits: Array Of TGitCommitRec;
    FEdges: Array Of TGitGraphEdge;
    FCount: Integer;
    FEdgeCount: Integer;
    FLaneCount: Integer;
    FShaIndex: TFPDataHashTable;
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
    { Parse `git rev-list --topo-order --parents` output (full history index). }
    Function ParseRevListParents(Const RevListText: String): Integer;
    { Merge SOH-delimited detail lines from FetchCommitDetails into matching rows. }
    Function ApplyDetailsText(Const DetailsText: String): Integer;
    { Collect SHAs in [First..Last] that still need details (inclusive). }
    Function CollectMissingShas(FirstIndex, LastIndex: Integer; Out Shas: TStringList): Integer;
    Procedure RebuildLayout;
    Function Commit(Index: Integer): TGitCommitRec;
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
  FCount := 0;
  FEdgeCount := 0;
  FLaneCount := 0;
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

Function TGitGraphModel.ParseRevListParents(Const RevListText: String): Integer;
Var
  Pos, L, PCount, K: Integer;
  Sha, Tok: String;
  ParentBuf: Array[0..3] Of String;
Begin
  Clear;
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
      If Length(Sha) < 7 Then
        Begin
          While (Pos <= L) And (RevListText[Pos] <> #10) And (RevListText[Pos] <> #13) Do
            Inc(Pos);
          SkipLineEnd(RevListText, Pos);
          Continue;
        End;

      PCount := 0;
      For K := 0 To 3 Do
        ParentBuf[K] := '';
      While (Pos <= L) And (RevListText[Pos] <> #10) And (RevListText[Pos] <> #13) Do
        Begin
          Tok := NextToken(RevListText, Pos);
          If Tok = '' Then
            Break;
          If PCount <= 3 Then
            Begin
              ParentBuf[PCount] := Tok;
              Inc(PCount);
            End;
        End;
      SkipLineEnd(RevListText, Pos);

      EnsureCapacity(FCount + 1);
      FCommits[FCount].Sha := Sha;
      FCommits[FCount].ParentCount := PCount;
      For K := 0 To 3 Do
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
  I, J, Lane, FreeLane, P, ParentLane: Integer;
  Sha: String;
Begin
  FLaneCount := 0;
  If FCount = 0 Then
    Exit;

  Active := Nil;
  For I := 0 To FCount - 1 Do
    Begin
      Sha := FCommits[I].Sha;

      Lane := -1;
      For J := 0 To High(Active) Do
        If Active[J] = Sha Then
          Begin
            Lane := J;
            Break;
          End;

      If Lane < 0 Then
        Begin
          FreeLane := -1;
          For J := 0 To High(Active) Do
            If Active[J] = '' Then
              Begin
                FreeLane := J;
                Break;
              End;
          If FreeLane >= 0 Then
            Lane := FreeLane
          Else
            Begin
              Lane := Length(Active);
              SetLength(Active, Lane + 1);
              Active[Lane] := '';
            End;
        End;

      FCommits[I].Lane := Lane;
      If Lane + 1 > FLaneCount Then
        FLaneCount := Lane + 1;

      For J := 0 To High(Active) Do
        If Active[J] = Sha Then
          Active[J] := '';

      If FCommits[I].ParentCount > 0 Then
        Active[Lane] := FCommits[I].Parents[0]
      Else
        Active[Lane] := '';

      For P := 1 To FCommits[I].ParentCount - 1 Do
        Begin
          ParentLane := -1;
          For J := 0 To High(Active) Do
            If Active[J] = FCommits[I].Parents[P] Then
              Begin
                ParentLane := J;
                Break;
              End;
          If ParentLane < 0 Then
            Begin
              FreeLane := -1;
              For J := 0 To High(Active) Do
                If Active[J] = '' Then
                  Begin
                    FreeLane := J;
                    Break;
                  End;
              If FreeLane >= 0 Then
                ParentLane := FreeLane
              Else
                Begin
                  ParentLane := Length(Active);
                  SetLength(Active, ParentLane + 1);
                End;
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
End;

Procedure TGitGraphModel.RebuildLayout;
Begin
  BuildShaIndex;
  LayoutLanes;
  BuildEdges;
End;

Function TGitGraphModel.Commit(Index: Integer): TGitCommitRec;
Begin
  If (Index < 0) Or (Index >= FCount) Then
    Begin
      Result.Sha := '';
      Result.ParentCount := 0;
      Result.Parents[0] := '';
      Result.Parents[1] := '';
      Result.Parents[2] := '';
      Result.Parents[3] := '';
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
