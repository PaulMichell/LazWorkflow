Program GitGraphModelTest;
{$mode objfpc}{$H+}
Uses Classes, SysUtils, GitGraphModel;
Var M:TGitGraphModel; Lines:TStringList; Edges:TGitEdgeIndices;
  I,J,K,First,Last:Integer; E:TGitGraphEdge; Started, IndexedMs, ScanMs:QWord; Hits:Int64;
Procedure Check(B:Boolean);
Begin If Not B Then Raise Exception.Create('visible edge mismatch'); End;
Begin
 M:=TGitGraphModel.Create; Lines:=TStringList.Create;
 Try
  For I:=0 To 49999 Do
    If I=49999 Then Lines.Add(IntToHex(I,40))
    Else If I Mod 500=0 Then Lines.Add(IntToHex(I,40)+' '+IntToHex(I+1,40)+' '+IntToHex(I+499,40))
    Else Lines.Add(IntToHex(I,40)+' '+IntToHex(I+1,40));
  Check(M.ParseRevListParents(Lines.Text)=50000);
  Check(M.EdgeCount=50099);
  For J:=0 To 300 Do
    Begin
      First:=J*163; Last:=First+30; Edges:=M.VisibleEdges(First,Last); K:=0;
      For I:=0 To M.EdgeCount-1 Do
        Begin
          E:=M.Edge(I);
          If (E.ChildIndex<=Last) And (E.ParentIndex>=First) Then
            Begin Check(K<Length(Edges)); Check(Edges[K]=I); Inc(K); End;
        End;
      Check(K=Length(Edges));
    End;
  Started:=GetTickCount64; Hits:=0;
  For J:=0 To 1999 Do Begin Edges:=M.VisibleEdges(J*23,J*23+30); Inc(Hits,Length(Edges)); End;
  IndexedMs:=GetTickCount64-Started; Started:=GetTickCount64;
  For J:=0 To 1999 Do
    For I:=0 To M.EdgeCount-1 Do
      Begin E:=M.Edge(I); If (E.ChildIndex<=J*23+30) And (E.ParentIndex>=J*23) Then Dec(Hits); End;
  ScanMs:=GetTickCount64-Started; Check(Hits=0);
  WriteLn('ok 50,000 commits, long edges and 301 viewport comparisons');
  WriteLn('2,000 queries: indexed ',IndexedMs,' ms; full scan ',ScanMs,' ms');
  M.Clear; Check(Length(M.VisibleEdges(0,10))=0);
  Lines.Clear;
  Lines.Add('#primary main1111');
  Lines.Add('side1111 side0000');
  Lines.Add('side0000 base0000');
  Lines.Add('main1111 main0000');
  Lines.Add('main0000 base0000');
  Lines.Add('base0000');
  Check(M.ParseRevListParents(Lines.Text)=5);
  Check(M.Commit(M.IndexOf('main1111')).Lane=0);
  Check(M.Commit(M.IndexOf('main0000')).Lane=0);
  Check(M.Commit(M.IndexOf('base0000')).Lane=0);
  Check(M.Commit(M.IndexOf('side1111')).Lane=1);
  Check(M.Commit(M.IndexOf('side0000')).Lane=1);
  WriteLn('ok main stays on lane 0 when another tip is listed first');
 Finally Lines.Free; M.Free; End;
End.
