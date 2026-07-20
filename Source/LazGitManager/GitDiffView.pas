Unit GitDiffView;

{ SynEdit-based unified-diff viewer with file/hunk/line navigation (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, ComCtrls, StdCtrls, Forms,
  SynEdit, SynEditTypes, SynHighlighterDiff;

Type
  TGitDiffRange = Record
    StartLine: Integer; { 1-based inclusive }
    EndLine: Integer;
    Path: String;
    Caption: String;
  End;

  TGitDiffView = Class(TPanel)
  Private
    FTree: TTreeView;
    FEdit: TSynEdit;
    FHigh: TSynDiffSyn;
    FSplitter: TSplitter;
    FTreePanel: TPanel;
    FEditPanel: TPanel;
    FCaption: TLabel;
    FDiffText: String;
    Procedure BuildUI;
    Procedure ApplyIDEEditorAppearance;
    Procedure ConfigureDiffColors;
    Procedure TreeChange(Sender: TObject; Node: TTreeNode);
    Procedure ParseDiffIntoTree(Const DiffText: String);
    Procedure SelectLineRange(StartLine, EndLine: Integer);
    Function NodeRange(Node: TTreeNode): TGitDiffRange;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Procedure Clear;
    Procedure LoadDiff(Const Title, DiffText: String);
    Procedure LoadPlainText(Const Title, Content: String);
    Function SelectedPath: String;
    Property Tree: TTreeView Read FTree;
    Property Editor: TSynEdit Read FEdit;
  End;

Implementation

Uses
  EditorOptionsIntf;

Type
  PGitDiffRange = ^TGitDiffRange;

Constructor TGitDiffView.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  BevelOuter := bvNone;
  Caption := '';
  BuildUI;
End;

Procedure TGitDiffView.ConfigureDiffColors;
Begin
  { Soft green/red line marks; keep IDE font/size from GetSynEditorSettings. }
  FHigh.LineAddedAttri.Foreground := RGBToColor(27, 94, 32);
  FHigh.LineAddedAttri.Background := RGBToColor(232, 245, 233);
  FHigh.LineRemovedAttri.Foreground := RGBToColor(183, 28, 28);
  FHigh.LineRemovedAttri.Background := RGBToColor(255, 235, 238);
  FHigh.ChunkMarkerAttri.Foreground := RGBToColor(69, 90, 100);
  FHigh.ChunkMarkerAttri.Background := RGBToColor(236, 239, 241);
  FHigh.ChunkNewAttri.Foreground := RGBToColor(46, 125, 50);
  FHigh.ChunkOldAttri.Foreground := RGBToColor(198, 40, 40);
  FHigh.NewFileAttri.Foreground := RGBToColor(27, 94, 32);
  FHigh.NewFileAttri.Background := clNone;
  FHigh.OrigFileAttri.Foreground := RGBToColor(183, 28, 28);
  FHigh.OrigFileAttri.Background := clNone;
  FHigh.LineContextAttri.Foreground := clWindowText;
  FHigh.LineContextAttri.Background := clNone;
  FHigh.SpaceAttri.Background := clNone;
  FHigh.UnknownAttri.Background := clNone;
End;

Procedure TGitDiffView.ApplyIDEEditorAppearance;
Begin
  { Match main Lazarus source editors: font, size, quality, spacing, gutter. }
  If Assigned(IDEEditorOptions) Then
    Begin
      IDEEditorOptions.GetSynEditorSettings(FEdit);
      If Assigned(FHigh) Then
        IDEEditorOptions.GetHighlighterSettings(FHigh);
    End
  Else
    Begin
      { Fallback when IDE options are not yet available. }
      FEdit.Font.Size := 10;
      FEdit.Font.Name := 'Courier New';
      FEdit.Font.Pitch := fpFixed;
      FEdit.Font.Quality := fqCleartypeNatural;
    End;

  FEdit.ReadOnly := True;
  FEdit.WantTabs := True;
  FEdit.RightGutter.Visible := False;
  { Special-char glyphs make mono text look broken; keep plain source style. }
  FEdit.Options := FEdit.Options - [eoShowSpecialChars];
  If Assigned(FHigh) Then
    Begin
      FEdit.Highlighter := FHigh;
      ConfigureDiffColors;
    End;
End;

Procedure TGitDiffView.BuildUI;
Begin
  FCaption := TLabel.Create(Self);
  With FCaption Do
    Begin
      Parent := Self;
      Align := alTop;
      BorderSpacing.Left := 6;
      BorderSpacing.Top := 4;
      BorderSpacing.Bottom := 2;
      Caption := 'Diff';
    End;

  FTreePanel := TPanel.Create(Self);
  With FTreePanel Do
    Begin
      Parent := Self;
      Align := alLeft;
      Width := 220;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FTree := TTreeView.Create(Self);
  With FTree Do
    Begin
      Parent := FTreePanel;
      Align := alClient;
      BorderSpacing.Around := 4;
      ReadOnly := True;
      ScrollBars := ssAutoBoth;
      ShowLines := True;
      Options := Options + [tvoShowButtons, tvoShowRoot, tvoShowLines, tvoRowSelect, tvoReadOnly, tvoToolTips];
      OnChange := @TreeChange;
    End;

  FSplitter := TSplitter.Create(Self);
  With FSplitter Do
    Begin
      Parent := Self;
      Align := alLeft;
      Width := 5;
      Left := FTreePanel.Width;
    End;

  FEditPanel := TPanel.Create(Self);
  With FEditPanel Do
    Begin
      Parent := Self;
      Align := alClient;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FHigh := TSynDiffSyn.Create(Self);

  FEdit := TSynEdit.Create(Self);
  With FEdit Do
    Begin
      Parent := FEditPanel;
      Align := alClient;
      BorderSpacing.Around := 4;
      Highlighter := FHigh;
    End;

  ApplyIDEEditorAppearance;
End;

Procedure TGitDiffView.Clear;
Var
  Node: TTreeNode;
  Data: PGitDiffRange;
Begin
  FDiffText := '';
  FEdit.Lines.Clear;
  FCaption.Caption := 'Diff';

  Node := FTree.Items.GetFirstNode;
  While Assigned(Node) Do
    Begin
      If Assigned(Node.Data) Then
        Begin
          Data := PGitDiffRange(Node.Data);
          Dispose(Data);
          Node.Data := Nil;
        End;
      Node := Node.GetNext;
    End;
  FTree.Items.Clear;
End;

Function TGitDiffView.NodeRange(Node: TTreeNode): TGitDiffRange;
Begin
  Result.StartLine := 1;
  Result.EndLine := 1;
  Result.Path := '';
  Result.Caption := '';
  If Assigned(Node) And Assigned(Node.Data) Then
    Result := PGitDiffRange(Node.Data)^;
End;

Procedure TGitDiffView.SelectLineRange(StartLine, EndLine: Integer);
Var
  Y1, Y2: Integer;
Begin
  If StartLine < 1 Then
    StartLine := 1;
  If EndLine < StartLine Then
    EndLine := StartLine;
  If EndLine > FEdit.Lines.Count Then
    EndLine := FEdit.Lines.Count;
  If FEdit.Lines.Count = 0 Then
    Exit;

  FEdit.CaretY := StartLine;
  FEdit.TopLine := StartLine;
  { Select whole lines StartLine..EndLine }
  Y1 := StartLine;
  Y2 := EndLine;
  FEdit.BlockBegin := Point(1, Y1);
  If Y2 >= FEdit.Lines.Count Then
    FEdit.BlockEnd := Point(Length(FEdit.Lines[Y2 - 1]) + 1, Y2)
  Else
    FEdit.BlockEnd := Point(1, Y2 + 1);
  FEdit.SetFocus;
End;

Procedure TGitDiffView.ParseDiffIntoTree(Const DiffText: String);
Var
  Lines: TStringList;
  I, LineNo: Integer;
  Line, Path: String;
  Root, FileNode, HunkNode, LineNode: TTreeNode;
  FileRange, HunkRange, LineRange: PGitDiffRange;
  InFile: Boolean;

  Procedure CloseHunk;
  Begin
    If Assigned(HunkNode) And Assigned(HunkNode.Data) Then
      PGitDiffRange(HunkNode.Data)^.EndLine := LineNo - 1;
    HunkNode := Nil;
  End;

  Procedure CloseFile;
  Begin
    CloseHunk;
    If Assigned(FileNode) And Assigned(FileNode.Data) Then
      PGitDiffRange(FileNode.Data)^.EndLine := LineNo - 1;
    FileNode := Nil;
  End;

  Function NewRange(AStart: Integer; Const APath, ACaption: String): PGitDiffRange;
  Begin
    New(Result);
    Result^.StartLine := AStart;
    Result^.EndLine := AStart;
    Result^.Path := APath;
    Result^.Caption := ACaption;
  End;

Begin
  FTree.Items.BeginUpdate;
  Try
    Clear;
    FDiffText := DiffText;
    FEdit.Lines.Text := DiffText;

    Lines := TStringList.Create;
    Try
      Lines.Text := DiffText;
      Root := FTree.Items.Add(Nil, 'Diff');
      FileRange := NewRange(1, '', 'All');
      FileRange^.EndLine := Lines.Count;
      Root.Data := FileRange;

      FileNode := Nil;
      HunkNode := Nil;
      Path := '';
      InFile := False;

      For I := 0 To Lines.Count - 1 Do
        Begin
          LineNo := I + 1;
          Line := Lines[I];

          If (Copy(Line, 1, 11) = 'diff --git ') Or (Copy(Line, 1, 4) = '--- ') Or
             ((Copy(Line, 1, 4) = '+++ ') And Not InFile) Then
            Begin
              If Copy(Line, 1, 11) = 'diff --git ' Then
                Begin
                  CloseFile;
                  { diff --git a/path b/path }
                  Path := Trim(Copy(Line, 12, MaxInt));
                  If Pos(' b/', Path) > 0 Then
                    Path := Copy(Path, Pos(' b/', Path) + 3, MaxInt)
                  Else If Pos(' ', Path) > 0 Then
                    Path := Copy(Path, Pos(' ', Path) + 1, MaxInt);
                  If (Length(Path) > 2) And (Copy(Path, 1, 2) = 'a/') Then
                    Path := Copy(Path, 3, MaxInt);
                  FileRange := NewRange(LineNo, Path, Path);
                  FileNode := FTree.Items.AddChild(Root, Path);
                  FileNode.Data := FileRange;
                  InFile := True;
                  HunkNode := Nil;
                End
              Else If Copy(Line, 1, 6) = '+++ b/' Then
                Begin
                  Path := Copy(Line, 7, MaxInt);
                  If Assigned(FileNode) Then
                    Begin
                      FileNode.Text := Path;
                      If Assigned(FileNode.Data) Then
                        PGitDiffRange(FileNode.Data)^.Path := Path;
                    End
                  Else
                    Begin
                      FileRange := NewRange(LineNo, Path, Path);
                      FileNode := FTree.Items.AddChild(Root, Path);
                      FileNode.Data := FileRange;
                      InFile := True;
                    End;
                End;
            End
          Else If Copy(Line, 1, 2) = '@@' Then
            Begin
              CloseHunk;
              If Not Assigned(FileNode) Then
                Begin
                  FileRange := NewRange(1, '', 'Changes');
                  FileNode := FTree.Items.AddChild(Root, 'Changes');
                  FileNode.Data := FileRange;
                End;
              HunkRange := NewRange(LineNo, Path, Line);
              HunkNode := FTree.Items.AddChild(FileNode, Line);
              HunkNode.Data := HunkRange;
            End
          Else If Assigned(HunkNode) And ((Copy(Line, 1, 1) = '+') Or (Copy(Line, 1, 1) = '-')) And
                  (Copy(Line, 1, 3) <> '+++') And (Copy(Line, 1, 3) <> '---') Then
            Begin
              LineRange := NewRange(LineNo, Path, Line);
              LineRange^.EndLine := LineNo;
              If Line[1] = '+' Then
                LineNode := FTree.Items.AddChild(HunkNode, '  + ' + Copy(Line, 2, MaxInt))
              Else
                LineNode := FTree.Items.AddChild(HunkNode, '  − ' + Copy(Line, 2, MaxInt));
              LineNode.Data := LineRange;
            End;
        End;

      CloseFile;
      If Assigned(Root.Data) Then
        PGitDiffRange(Root.Data)^.EndLine := Lines.Count;
      Root.Expand(False);
      If Assigned(Root.GetFirstChild) Then
        Root.GetFirstChild.Expand(False);
    Finally
      Lines.Free;
    End;
  Finally
    FTree.Items.EndUpdate;
  End;
End;

Procedure TGitDiffView.TreeChange(Sender: TObject; Node: TTreeNode);
Var
  R: TGitDiffRange;
Begin
  If Not Assigned(Node) Then
    Exit;
  R := NodeRange(Node);
  If R.StartLine > 0 Then
    SelectLineRange(R.StartLine, R.EndLine);
End;

Procedure TGitDiffView.LoadDiff(Const Title, DiffText: String);
Begin
  If Title <> '' Then
    FCaption.Caption := Title
  Else
    FCaption.Caption := 'Diff';
  ApplyIDEEditorAppearance;
  If Trim(DiffText) = '' Then
    Begin
      Clear;
      FEdit.Lines.Text := '(no textual diff)';
      Exit;
    End;
  ParseDiffIntoTree(DiffText);
  FEdit.Highlighter := FHigh;
  ConfigureDiffColors;
End;

Procedure TGitDiffView.LoadPlainText(Const Title, Content: String);
Begin
  Clear;
  If Title <> '' Then
    FCaption.Caption := Title;
  ApplyIDEEditorAppearance;
  FEdit.Highlighter := Nil;
  FEdit.Lines.Text := Content;
End;

Function TGitDiffView.SelectedPath: String;
Var
  Node: TTreeNode;
  R: TGitDiffRange;
Begin
  Result := '';
  Node := FTree.Selected;
  While Assigned(Node) Do
    Begin
      R := NodeRange(Node);
      If R.Path <> '' Then
        Begin
          Result := R.Path;
          Exit;
        End;
      Node := Node.Parent;
    End;
End;

End.
