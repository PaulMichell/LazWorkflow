Program MarkdownLayoutTest;

{ Console checks for mixed-style markdown run spacing (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Graphics, Classes, SysUtils, MarkDown.CanvasRender, Markdown.Processors;

Var
  FailCount: Integer;

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

Function LayoutOf(Const Markdown: String; Out Renderer: TMarkDownCanvasRenderer): Integer;
Var
  Bmp: TBitmap;
  SL: TStringList;
  W, H: Integer;
Begin
  Renderer := TMarkDownCanvasRenderer.Create(Nil);
  Bmp := TBitmap.Create;
  SL := TStringList.Create;
  Try
    Bmp.SetSize(800, 200);
    Bmp.Canvas.Font.Name := 'DejaVu Sans';
    Bmp.Canvas.Font.Size := 10;
    Renderer.FontName := 'DejaVu Sans';
    Renderer.MonoFontName := 'DejaVu Sans Mono';
    Renderer.BaseFontSize := 10;
    SL.Text := Markdown;
    Renderer.ParseMarkdown(SL);
    Renderer.CalculateLayout(Bmp.Canvas, 700, W, H);
    Result := Renderer.LayoutItemCount;
  Finally
    SL.Free;
    Bmp.Free;
  End;
End;

Procedure TestRunsAbutAcrossStyleChange;
Var
  R: TMarkDownCanvasRenderer;
  A, B: TLayoutItem;
  I, N: Integer;
Begin
  N := LayoutOf('- `Card.SetBounds` is called, then `LockControlWidth(Card, InnerW);` again.', R);
  Try
    Check('mixed-style has several runs', N >= 3);
    For I := 0 To N - 2 Do
      Begin
        A := R.LayoutItem(I);
        B := R.LayoutItem(I + 1);
        If (Not Assigned(A)) Or (Not Assigned(B)) Then
          Continue;
        If A.Y <> B.Y Then
          Continue;
        Check('same-line runs abut', B.X = A.X + A.Width);
      End;
  Finally
    R.Free;
  End;
End;

Procedure TestCollapsedSpacesAroundCode;
Var
  Tight, Padded: TMarkDownCanvasRenderer;
  TightW, PadW: Integer;
  I: Integer;
  Item: TLayoutItem;
Begin
  TightW := 0;
  PadW := 0;
  LayoutOf('- `Foo` bar `Baz` end.', Tight);
  LayoutOf('- `Foo`          bar          `Baz`          end.', Padded);
  Try
    For I := 0 To Tight.LayoutItemCount - 1 Do
      Begin
        Item := Tight.LayoutItem(I);
        If Assigned(Item) And (Item.Y = 0) Then
          If Item.X + Item.Width > TightW Then
            TightW := Item.X + Item.Width;
      End;
    For I := 0 To Padded.LayoutItemCount - 1 Do
      Begin
        Item := Padded.LayoutItem(I);
        If Assigned(Item) And (Item.Y = 0) Then
          If Item.X + Item.Width > PadW Then
            PadW := Item.X + Item.Width;
      End;
    Check('padded spaces do not explode width', Abs(PadW - TightW) <= 8);
  Finally
    Tight.Free;
    Padded.Free;
  End;
End;

Begin
  FailCount := 0;
  TestRunsAbutAcrossStyleChange;
  TestCollapsedSpacesAroundCode;
  If FailCount = 0 Then
    Begin
      WriteLn('All MarkdownLayout tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' MarkdownLayout test(s) failed.');
      Halt(1);
    End;
End.
