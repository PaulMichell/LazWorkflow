Unit StyledSurface;

{ Bounded bitmap viewport and shared scroll handling (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, Controls, Graphics, StdCtrls, Types, StyledCanvas;

Type
  TStyledSurface = Class(TCustomControl)
  Private
    Bitmap: TBitmap;
    VerticalBar, HorizontalBar: TScrollBar;
    UpdatingBars: Boolean;
    FRenderer: TStyledCanvas;
    FScrollTop: Int64;
    FScrollLeft: Integer;
    FContentHeight: Int64;
    FContentWidth: Integer;
    FShowVertical, FShowHorizontal: Boolean;
    FLastPaintMilliseconds: QWord;
    FPaintCount: QWord;
    Procedure DoScroll(Sender: TObject);
    Procedure SetScrollTop(Value: Int64);
    Procedure SetScrollLeft(Value: Integer);
    Function GetBufferCanvas: TCanvas;
  Protected
    Procedure Paint; Override;
    Procedure Resize; Override;
    Procedure FontChanged(Sender: TObject); Override;
    Function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePosition: TPoint): Boolean; Override;
    Procedure PaintContent(Const Clip: TRect; OriginX: Integer; OriginY: Int64); Virtual; Abstract;
    Procedure GeometryChanged; Virtual;
    Procedure Scrolled; Virtual;
    Procedure ConfigureCanvas;
    Procedure SetExtent(NewWidth: Integer; NewHeight: Int64);
    Procedure SetScrollbars(Vertical, Horizontal: Boolean);
    Property BufferCanvas: TCanvas Read GetBufferCanvas;
  Public
    Constructor Create(OwnerComponent: TComponent); Override;
    Destructor Destroy; Override;
    Function ViewRect: TRect;
    Procedure ScrollToStart;
    Procedure ScrollToEnd;
    Property Renderer: TStyledCanvas Read FRenderer;
    Property ScrollTop: Int64 Read FScrollTop Write SetScrollTop;
    Property ScrollLeft: Integer Read FScrollLeft Write SetScrollLeft;
    Property ContentHeight: Int64 Read FContentHeight;
    Property ContentWidth: Integer Read FContentWidth;
    Property LastPaintMilliseconds: QWord Read FLastPaintMilliseconds;
    Property PaintCount: QWord Read FPaintCount;
  Published
    Property Align;
    Property Anchors;
    Property BorderSpacing;
    Property Color;
    Property Constraints;
    Property Enabled;
    Property Font;
    Property ParentColor;
    Property ParentFont;
    Property PopupMenu;
    Property TabOrder;
    Property TabStop;
    Property Visible;
    Property OnEnter;
    Property OnExit;
    Property OnKeyDown;
    Property OnUTF8KeyPress;
  End;

Implementation

Uses
  Math, SysUtils, Forms;

Constructor TStyledSurface.Create(OwnerComponent: TComponent);
Begin
  Inherited Create(OwnerComponent);
  ControlStyle := ControlStyle + [csOpaque, csDoubleClicks];
  TabStop := True;
  Color := clWindow;
  Width := 240;
  Height := 100;
  Bitmap := TBitmap.Create;
  Bitmap.PixelFormat := pf32bit;
  Bitmap.SetSize(8, 8);
  FRenderer := TStyledCanvas.Create;
  VerticalBar := TScrollBar.Create(Nil);
  VerticalBar.Parent := Self;
  VerticalBar.Kind := sbVertical;
  VerticalBar.TabStop := False;
  VerticalBar.Visible := False;
  VerticalBar.OnChange := @DoScroll;
  HorizontalBar := TScrollBar.Create(Nil);
  HorizontalBar.Parent := Self;
  HorizontalBar.TabStop := False;
  HorizontalBar.Visible := False;
  HorizontalBar.OnChange := @DoScroll;
End;

Destructor TStyledSurface.Destroy;
Begin
  FreeAndNil(VerticalBar);
  FreeAndNil(HorizontalBar);
  FreeAndNil(FRenderer);
  FreeAndNil(Bitmap);
  Inherited Destroy;
End;

Function TStyledSurface.ViewRect: TRect;
Begin
  Result := Rect(7, 6, Max(7, ClientWidth - 7), Max(6, ClientHeight - 6));
  If FShowVertical Then Dec(Result.Right, 16);
  If FShowHorizontal Then Dec(Result.Bottom, 16);
  Result.Right := Max(Result.Left + 1, Result.Right);
  Result.Bottom := Max(Result.Top + 1, Result.Bottom);
End;

Procedure TStyledSurface.ConfigureCanvas;
Begin
  If Assigned(FRenderer) Then FRenderer.Configure(Bitmap.Canvas, Font);
End;

Procedure TStyledSurface.SetScrollbars(Vertical, Horizontal: Boolean);
Begin
  FShowVertical := Vertical;
  FShowHorizontal := Horizontal;
  VerticalBar.Visible := Vertical;
  HorizontalBar.Visible := Horizontal;
  Resize;
End;

Procedure TStyledSurface.Resize;
Begin
  Inherited Resize;
  If Not Assigned(VerticalBar) Then Exit;
  VerticalBar.SetBounds(Max(0, ClientWidth - 17), 1, 16, Max(1, ClientHeight - 2 - Ord(FShowHorizontal) * 16));
  HorizontalBar.SetBounds(1, Max(0, ClientHeight - 17), Max(1, ClientWidth - 2 - Ord(FShowVertical) * 16), 16);
  GeometryChanged;
  SetExtent(FContentWidth, FContentHeight);
  Invalidate;
End;

Procedure TStyledSurface.FontChanged(Sender: TObject);
Begin
  Inherited FontChanged(Sender);
  If Assigned(FRenderer) Then
    Begin
      ConfigureCanvas;
      GeometryChanged;
      Invalidate;
    End;
End;

Procedure TStyledSurface.GeometryChanged;
Begin
End;

Procedure TStyledSurface.Scrolled;
Begin
End;

Function TStyledSurface.GetBufferCanvas: TCanvas;
Begin
  Result := Bitmap.Canvas;
End;

Procedure TStyledSurface.SetExtent(NewWidth: Integer; NewHeight: Int64);
Var
  Bounds: TRect;
  Maximum: Int64;
  Page: Integer;
Begin
  FContentWidth := Max(0, NewWidth);
  FContentHeight := Max(Int64(0), NewHeight);
  Bounds := ViewRect;
  FScrollTop := EnsureRange(FScrollTop, Int64(0), Max(Int64(0), FContentHeight - Bounds.Height));
  FScrollLeft := EnsureRange(FScrollLeft, 0, Max(0, FContentWidth - Bounds.Width));
  If Not Assigned(VerticalBar) Then Exit;
  UpdatingBars := True;
  Try
    Maximum := Max(Int64(0), FContentHeight - Bounds.Height);
    Page := Max(1, Round(Bounds.Height / Max(Int64(1), FContentHeight) * 1000000));
    VerticalBar.SetParams(Round(FScrollTop / Max(Int64(1), Maximum) * 1000000), 0, 1000000 + Page - 1, Page);
    VerticalBar.Enabled := Maximum > 0;
    HorizontalBar.SetParams(FScrollLeft, 0, Max(Bounds.Width, FContentWidth), Bounds.Width);
    HorizontalBar.Enabled := FContentWidth > Bounds.Width;
  Finally
    UpdatingBars := False;
  End;
End;

Procedure TStyledSurface.DoScroll(Sender: TObject);
Begin
  If UpdatingBars Then Exit;
  If Sender = VerticalBar Then
    SetScrollTop(Round(VerticalBar.Position / 1000000 * Max(Int64(0), FContentHeight - ViewRect.Height)))
  Else SetScrollLeft(HorizontalBar.Position);
End;

Procedure TStyledSurface.SetScrollTop(Value: Int64);
Begin
  Value := EnsureRange(Value, Int64(0), Max(Int64(0), FContentHeight - ViewRect.Height));
  If FScrollTop = Value Then Exit;
  FScrollTop := Value;
  SetExtent(FContentWidth, FContentHeight);
  Scrolled;
  Invalidate;
End;

Procedure TStyledSurface.SetScrollLeft(Value: Integer);
Begin
  Value := EnsureRange(Value, 0, Max(0, FContentWidth - ViewRect.Width));
  If FScrollLeft = Value Then Exit;
  FScrollLeft := Value;
  SetExtent(FContentWidth, FContentHeight);
  Scrolled;
  Invalidate;
End;

Procedure TStyledSurface.ScrollToStart;
Begin
  ScrollTop := 0;
  ScrollLeft := 0;
End;

Procedure TStyledSurface.ScrollToEnd;
Begin
  ScrollTop := FContentHeight;
End;

Function TStyledSurface.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePosition: TPoint): Boolean;
Var
  PreviousTop: Int64;
  PreviousLeft: Integer;
Begin
  Result := Inherited DoMouseWheel(Shift, WheelDelta, MousePosition);
  If Result Then Exit;
  PreviousTop := FScrollTop;
  PreviousLeft := FScrollLeft;
  If ssShift In Shift Then ScrollLeft := ScrollLeft - WheelDelta Div 2
  Else ScrollTop := ScrollTop - WheelDelta Div 2;
  Result := (FScrollTop <> PreviousTop) Or (FScrollLeft <> PreviousLeft);
End;

Procedure TStyledSurface.Paint;
Var
  Started: QWord;
  Clip, View, BufferRect: TRect;
  LogicalTop, CopyHeight, BufferHeight: Integer;
Begin
  Started := GetTickCount64;
  View := ViewRect;
  { At most 8 MiB per viewport. Normal desktop widths use horizontal strips. }
  BufferHeight := Max(1, Min(ClientHeight, 8 * 1024 * 1024 Div Max(4, ClientWidth * 4)));
  If (Bitmap.Width <> Max(1, ClientWidth)) Or (Bitmap.Height <> BufferHeight) Then Bitmap.SetSize(Max(1, ClientWidth), BufferHeight);
  LogicalTop := 0;
  While LogicalTop < ClientHeight Do
    Begin
      CopyHeight := Min(BufferHeight, ClientHeight - LogicalTop);
      BufferRect := Rect(0, 0, ClientWidth, CopyHeight);
      Bitmap.Canvas.Brush.Style := bsSolid;
      Bitmap.Canvas.Brush.Color := Color;
      Bitmap.Canvas.FillRect(BufferRect);
      ConfigureCanvas;
      Clip := View;
      OffsetRect(Clip, 0, -LogicalTop);
      If IntersectRect(Clip, Clip, BufferRect) Then PaintContent(Clip, View.Left - ScrollLeft, Int64(View.Top) - LogicalTop - ScrollTop);
      Bitmap.Canvas.Brush.Style := bsSolid;
      If Focused Then Bitmap.Canvas.Brush.Color := $00C08038 Else Bitmap.Canvas.Brush.Color := $00C8C5BE;
      Bitmap.Canvas.FillRect(0, -LogicalTop, ClientWidth, 1 - LogicalTop);
      Bitmap.Canvas.FillRect(0, ClientHeight - 1 - LogicalTop, ClientWidth, ClientHeight - LogicalTop);
      Bitmap.Canvas.FillRect(0, -LogicalTop, 1, ClientHeight - LogicalTop);
      Bitmap.Canvas.FillRect(ClientWidth - 1, -LogicalTop, ClientWidth, ClientHeight - LogicalTop);
      Canvas.CopyRect(Rect(0, LogicalTop, ClientWidth, LogicalTop + CopyHeight), Bitmap.Canvas, BufferRect);
      Inc(LogicalTop, CopyHeight);
    End;
  FLastPaintMilliseconds := GetTickCount64 - Started;
  Inc(FPaintCount);
End;

End.
