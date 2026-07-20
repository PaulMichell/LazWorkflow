Unit GitGraphModel;

{ Commit graph data, fast log parsing and lane layout (c) 2026 Michell Computing.

  Performance notes:
  - Parsing uses a single scan with SOH field separators (no regex, no TStringList per line).
  - SHA lookup is a hash table; lane layout is O(n * lanes).
  - Layout runs on the worker thread before the UI is notified. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs;

Const
  GitGraphFieldSep = #1;
  GitGraphDefaultChunk = 400;
  GitGraphMaxAutoLoad = 5000;
  GitGraphRowHeight = 22;
  GitGraphLaneWidth = 16;
  GitGraphLeftMargin = 12;
  GitGraphNodeRadius = 4;
  GitGraphTextGap = 10;

Type
  TGitCommitRec = Record
    Sha: String;
    ShortSha: String;
    ParentCount: Integer;
    Parents: Array[0..3] Of String;
    Subject: String;
    Author: String;
    CommitTime: Int64;
    Refs: String;
    Lane: Integer;
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
    { Parse SOH-delimited git log text from GitService.FetchLogText. }
    Function ParseLogText(Const LogText: String): Integer;
    Procedure RebuildLayout;
    Function Commit(Index: Integer): TGitCommitRec;
    Function Edge(Index: Integer): TGitGraphEdge;
    Function TotalHeight: Integer;
    Function GraphWidth: Integer;
    Function LaneColorIndex(Lane: Integer): Integer;
    Property Count: Integer Read FCount;
    Property EdgeCount: Integer Read FEdgeCount;
    Property LaneCount: Integer Read FLaneCount;
  End;

Implementation

Constructor TGitGraphModel.Create;
Begin
  Inherited Create;
  FShaIndex := TFPDataHashTable.CreateWith(2048, @RSHash);
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
    Cap := 256;
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
    Cap := 256;
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
    Result := NativeInt(P) - 1; { stored as Index+1 so Nil means missing }
End;

Procedure TGitGraphModel.BuildShaIndex;
Var
  I: Integer;
Begin
  ClearIndex;
  For I := 0 To FCount - 1 Do
    FShaIndex.Add(FCommits[I].Sha, Pointer(NativeUInt(I + 1)));
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

Function TGitGraphModel.ParseLogText(Const LogText: String): Integer;
Var
  Pos, L, PCount, K: Integer;
  LineSha, ParentField, Subject, Author, TimeField, Refs, ParentPart: String;
  ParentBuf: Array[0..3] Of String;
  PStart, PPos, PL: Integer;
  TimeVal: Int64;
Begin
  Clear;
  Result := 0;
  L := Length(LogText);
  Pos := 1;
  While Pos <= L Do
    Begin
      If (LogText[Pos] = #10) Or (LogText[Pos] = #13) Then
        Begin
          SkipLineEnd(LogText, Pos);
          Continue;
        End;

      LineSha := NextField(LogText, Pos, GitGraphFieldSep);
      ParentField := NextField(LogText, Pos, GitGraphFieldSep);
      Subject := NextField(LogText, Pos, GitGraphFieldSep);
      Author := NextField(LogText, Pos, GitGraphFieldSep);
      TimeField := NextField(LogText, Pos, GitGraphFieldSep);
      Refs := NextField(LogText, Pos, GitGraphFieldSep);
      SkipLineEnd(LogText, Pos);

      If Length(LineSha) < 7 Then
        Continue;

      PCount := 0;
      For K := 0 To 3 Do
        ParentBuf[K] := '';
      PPos := 1;
      PL := Length(ParentField);
      While (PPos <= PL) And (PCount <= 3) Do
        Begin
          While (PPos <= PL) And (ParentField[PPos] = ' ') Do
            Inc(PPos);
          PStart := PPos;
          While (PPos <= PL) And (ParentField[PPos] <> ' ') Do
            Inc(PPos);
          If PPos > PStart Then
            Begin
              ParentPart := Copy(ParentField, PStart, PPos - PStart);
              ParentBuf[PCount] := ParentPart;
              Inc(PCount);
            End;
        End;

      TimeVal := StrToInt64Def(TimeField, 0);
      EnsureCapacity(FCount + 1);
      FCommits[FCount].Sha := LineSha;
      FCommits[FCount].ShortSha := Copy(LineSha, 1, 7);
      FCommits[FCount].ParentCount := PCount;
      For K := 0 To 3 Do
        FCommits[FCount].Parents[K] := ParentBuf[K];
      FCommits[FCount].Subject := Subject;
      FCommits[FCount].Author := Author;
      FCommits[FCount].CommitTime := TimeVal;
      FCommits[FCount].Refs := Refs;
      FCommits[FCount].Lane := 0;
      Inc(FCount);
    End;

  RebuildLayout;
  Result := FCount;
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
      Result.ShortSha := '';
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

Function TGitGraphModel.TotalHeight: Integer;
Begin
  Result := FCount * GitGraphRowHeight;
  If Result < GitGraphRowHeight Then
    Result := GitGraphRowHeight;
End;

Function TGitGraphModel.GraphWidth: Integer;
Begin
  Result := GitGraphLeftMargin + FLaneCount * GitGraphLaneWidth + GitGraphLaneWidth;
End;

Function TGitGraphModel.LaneColorIndex(Lane: Integer): Integer;
Begin
  If Lane < 0 Then
    Result := 0
  Else
    Result := Lane Mod 10;
End;

End.
