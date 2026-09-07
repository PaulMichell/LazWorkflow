Unit StyledMemoLayout;

{ Paragraph layout and contiguous message-box geometry (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Types, StyledTextTypes, StyledTextDocument, StyledCanvas;

Type
  TStyledMemoLayout = Class
  Private
    Document: TStyledDocument;
    Renderer: TStyledCanvas;
    Groups: Array Of QWord;
    Width, EstimateHeight: Integer;
    WordWrap: Boolean;
    Procedure RebuildGroups;
  Public
    Paragraphs: Array Of TStyledLayout;
    Heights: TStyledHeightIndex;
    GroupFirst, GroupLast: TStyledIntegers;
    RestartParagraph, RestartOffset: Integer;
    Constructor Create(NewDocument: TStyledDocument; NewRenderer: TStyledCanvas);
    Destructor Destroy; Override;
    Procedure Reset(NewWidth: Integer; NewWordWrap: Boolean; Estimate: Integer);
    Function DocumentChanged(First, Removed, Added: Integer): Boolean;
    Procedure Ensure(Index: Integer; Finish: Boolean);
    Function Spacing(Index: Integer): TStyledInsets;
    Function TextLeft(Index: Integer): Integer;
    Function TextTop(Index: Integer): Int64;
    Procedure Paint(Const Clip: TRect; OriginX: Integer; OriginY: Int64; Const First, Last: TStyledPosition; Selected: Boolean);
  End;

Implementation

Uses
  SysUtils, Math;

Constructor TStyledMemoLayout.Create(NewDocument: TStyledDocument; NewRenderer: TStyledCanvas);
Begin
  Inherited Create;
  RestartParagraph := -1;
  Document := NewDocument;
  Renderer := NewRenderer;
  SetLength(Paragraphs, Document.Count);
  RebuildGroups;
End;

Destructor TStyledMemoLayout.Destroy;
Var
  Layout: TStyledLayout;
Begin
  For Layout In Paragraphs Do Layout.Free;
  Inherited Destroy;
End;

Procedure TStyledMemoLayout.RebuildGroups;
Var
  First, Last, Index: Integer;
  Group: QWord;
Begin
  SetLength(Groups, Document.Count);
  SetLength(GroupFirst, Document.Count);
  SetLength(GroupLast, Document.Count);
  First := 0;
  While First < Document.Count Do
    Begin
      Group := Document[First]^.Box.Group;
      Last := First;
      If Group <> 0 Then
        While (Last + 1 < Document.Count) And (Document[Last + 1]^.Box.Group = Group) Do Inc(Last);
      For Index := First To Last Do
        Begin
          Groups[Index] := Group;
          GroupFirst[Index] := First;
          GroupLast[Index] := Last;
        End;
      First := Last + 1;
    End;
End;

Function TStyledMemoLayout.Spacing(Index: Integer): TStyledInsets;
Var
  Style: TStyledBoxStyle;
Begin
  Result := StyledInsets(0);
  If (Document[Index]^.Box.Group = 0) Or (Length(Document[Index]^.Box.Columns) > 0) Then Exit;
  Style := Document[GroupFirst[Index]]^.Box.Style;
  Result.Left := Max(0, Style.Margin.Left) + Max(0, Style.BorderWidth) + Max(0, Style.Padding.Left);
  Result.Right := Max(0, Style.Margin.Right) + Max(0, Style.BorderWidth) + Max(0, Style.Padding.Right);
  If Index = GroupFirst[Index] Then Result.Top := Max(0, Style.Margin.Top) + Max(0, Style.BorderWidth) + Max(0, Style.Padding.Top);
  If Index = GroupLast[Index] Then Result.Bottom := Max(0, Style.Margin.Bottom) + Max(0, Style.BorderWidth) + Max(0, Style.Padding.Bottom);
End;

Function TStyledMemoLayout.TextLeft(Index: Integer): Integer;
Begin
  Result := Min(Width, Spacing(Index).Left);
End;

Function TStyledMemoLayout.TextTop(Index: Integer): Int64;
Begin
  Result := HeightBefore(Heights, Index) + Spacing(Index).Top;
End;

Procedure TStyledMemoLayout.Reset(NewWidth: Integer; NewWordWrap: Boolean; Estimate: Integer);
Var
  Index: Integer;
  Insets: TStyledInsets;
Begin
  Width := Max(1, NewWidth);
  WordWrap := NewWordWrap;
  EstimateHeight := Estimate;
  ResetHeights(Heights, Document.Count, Estimate);
  For Index := 0 To Document.Count - 1 Do
    If Document[Index]^.Box.Group <> 0 Then
      Begin
        Insets := Spacing(Index);
        SetHeight(Heights, Index, Int64(Estimate) + Insets.Top + Insets.Bottom);
      End;
End;

Function TStyledMemoLayout.DocumentChanged(First, Removed, Added: Integer): Boolean;
Var
  Index, OldCount, NewCount, Delta: Integer;
  GroupsChanged: Boolean;
Begin
  OldCount := Length(Paragraphs);
  NewCount := Document.Count;
  Delta := Added - Removed;
  If OldCount <> NewCount - Delta Then
    Begin
      For Index := 0 To OldCount - 1 Do Paragraphs[Index].Free;
      Paragraphs := Nil;
      SetLength(Paragraphs, NewCount);
    End
  Else If Delta <> 0 Then
    Begin
      For Index := First To First + Removed - 1 Do FreeAndNil(Paragraphs[Index]);
      If Delta > 0 Then
        Begin
          SetLength(Paragraphs, NewCount);
          For Index := OldCount - 1 DownTo First + Removed Do Paragraphs[Index + Delta] := Paragraphs[Index];
        End
      Else
        Begin
          For Index := First + Removed To OldCount - 1 Do Paragraphs[Index + Delta] := Paragraphs[Index];
          SetLength(Paragraphs, NewCount);
        End;
      For Index := First To First + Added - 1 Do Paragraphs[Index] := Nil;
    End;
  GroupsChanged := Length(Groups) <> NewCount;
  If Not GroupsChanged Then
    For Index := First To First + Added - 1 Do
      If Groups[Index] <> Document[Index]^.Box.Group Then Begin GroupsChanged := True; Break; End;
  If GroupsChanged Then RebuildGroups;
  Result := (Delta <> 0) Or GroupsChanged Or (Length(Heights.Values) <> NewCount);
  If Result Then Reset(Width, WordWrap, EstimateHeight);
End;

Procedure TStyledMemoLayout.Ensure(Index: Integer; Finish: Boolean);
Var
  Wrap: TStyledWrap;
  Insets: TStyledInsets;
  Estimate: Int64;
  Restart: Integer;
Begin
  If Not Assigned(Paragraphs[Index]) Then Paragraphs[Index] := TStyledLayout.Create;
  Insets := Spacing(Index);
  If WordWrap Or (Document[Index]^.Box.Group <> 0) Then Wrap := swWord Else Wrap := swNone;
  Restart := 0;
  If Index = RestartParagraph Then Begin Restart := RestartOffset; RestartParagraph := -1; End;
  Renderer.BeginLayout(Paragraphs[Index], Document[Index]^, Max(1, Width - Insets.Left - Insets.Right), Wrap, Restart);
  If Finish Then Renderer.ContinueLayout(Paragraphs[Index], Document[Index]^, 0)
  Else Renderer.ContinueLayout(Paragraphs[Index], Document[Index]^, 8);
  Estimate := Paragraphs[Index].Height;
  If Not Paragraphs[Index].Complete Then
    Estimate := Max(Estimate, Round(Estimate * (Length(Document[Index]^.Text) / Max(1, Paragraphs[Index].NextOffset))));
  SetHeight(Heights, Index, Estimate + Insets.Top + Insets.Bottom);
End;

Procedure TStyledMemoLayout.Paint(Const Clip: TRect; OriginX: Integer; OriginY: Int64;
  Const First, Last: TStyledPosition; Selected: Boolean);
Var
  Index, LastVisible, Item, FirstGroup, LastGroup, FirstOffset, LastOffset: Integer;
  Geometry: TStyledBoxGeometry;
  Style: TStyledBoxStyle;
  Boxed: Boolean;
Begin
  Index := ItemAtHeight(Heights, Clip.Top - OriginY);
  While Index < Document.Count Do
    Begin
      If OriginY + HeightBefore(Heights, Index) >= Clip.Bottom Then Break;
      FirstGroup := GroupFirst[Index];
      LastGroup := GroupLast[Index];
      Boxed := (Document[Index]^.Box.Group <> 0) And (Length(Document[Index]^.Box.Columns) = 0);
      If Length(Document[Index]^.Box.Columns) > 0 Then LastGroup := Index;
      LastVisible := Index;
      While LastVisible <= LastGroup Do
        Begin
          If OriginY + HeightBefore(Heights, LastVisible) >= Clip.Bottom Then Break;
          Ensure(LastVisible, False);
          Inc(LastVisible);
        End;
      If Boxed Then
        Begin
          Style := Document[FirstGroup]^.Box.Style;
          Geometry := GetStyledBoxGeometry(OriginX, OriginY + HeightBefore(Heights, FirstGroup), Width,
            HeightBefore(Heights, LastGroup + 1) - HeightBefore(Heights, FirstGroup), Style);
          Renderer.DrawBoxFrame(Geometry, Style, Clip);
        End;
      For Item := Index To LastVisible - 1 Do
        Begin
          FirstOffset := -1;
          LastOffset := -1;
          If Selected And (Item >= First.Paragraph) And (Item <= Last.Paragraph) Then
            Begin
              FirstOffset := 0;
              LastOffset := Length(Document[Item]^.Text) + 1;
              If Item = First.Paragraph Then FirstOffset := First.Offset;
              If Item = Last.Paragraph Then LastOffset := Last.Offset;
            End;
          If Boxed Then
            Renderer.DrawBoxText(Paragraphs[Item], OriginX + TextLeft(Item), OriginY + TextTop(Item), Geometry, Style,
              Clip, FirstOffset, LastOffset)
          Else Renderer.Draw(Paragraphs[Item], OriginX, OriginY + TextTop(Item), Clip, FirstOffset, LastOffset);
        End;
      Index := LastVisible;
    End;
End;

End.
