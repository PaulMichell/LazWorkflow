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
    FWantVertical: Boolean;
    FAutoHideVertical, FAdjustingAutoBar: Boolean;
    FScrollStyle: TScrollStyle;
    FLastPaintMilliseconds: QWord;
    FPaintCount: QWord;
    { Non-nil only during Paint: content draws on the control canvas so HiDPI
      backings rasterise text at native resolution. The bitmap is for measure. }
    FPaintCanvas: TCanvas;
    Procedure UpdateScrollbarBounds;
    Procedure EnsureBuffer;
    Procedure DoScroll(Sender: TObject);
    Procedure SetScrollTop(Value: Int64);
    Procedure SetScrollLeft(Value: Integer);
    Procedure SetScrollStyle(Value: TScrollStyle);
    Function UpdateAutoVerticalBar: Boolean;
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
    { Descendants return False while a partial layout must not show or hide the bar. }
    Function IsLayoutSettled: Boolean; Virtual;
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
    { ssAutoVertical hides the bar when the content fits. Other styles keep the previous always-on bars. }
    Property ScrollBars: TScrollStyle Read FScrollStyle Write SetScrollStyle;
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
  Math, SysUtils, Forms, LCLIntf, LCLType;

Constructor TStyledSurface.Create(OwnerComponent: TComponent);
Begin
  Inherited Create(OwnerComponent);
  ControlStyle := ControlStyle + [csOpaque, csDoubleClicks];
  {$IFDEF LCLWin32}
  { Windows only: Paint fills ClientRect before drawing, and Win32 does not buffer a TCustomControl, so every
    Invalidate would show a blank frame. The Win32 backing is 1x, so the memory buffer costs no text sharpness.
    Cocoa and GTK supply a ready (HiDPI) paint DC, which a 1x buffer would blur. }
  DoubleBuffered := True;
  {$ENDIF}
  TabStop := True;
  Color := clWindow;
  Width := 240;
  Height := 100;
  Bitmap := TBitmap.Create;
  Bitmap.PixelFormat := pf32bit;
  Bitmap.SetSize(8, 8);
  FPaintCanvas := Nil;
  FRenderer := TStyledCanvas.Create;
  VerticalBar := TScrollBar.Create(Nil);
  VerticalBar.Parent := Self;
  VerticalBar.Cursor := crArrow;
  VerticalBar.Kind := sbVertical;
  VerticalBar.TabStop := False;
  VerticalBar.Visible := False;
  VerticalBar.OnChange := @DoScroll;
  HorizontalBar := TScrollBar.Create(Nil);
  HorizontalBar.Parent := Self;
  HorizontalBar.Cursor := crArrow;
  HorizontalBar.TabStop := False;
  HorizontalBar.Visible := False;
  HorizontalBar.OnChange := @DoScroll;
End;

Destructor TStyledSurface.Destroy;
Begin
  FPaintCanvas := Nil;
  FreeAndNil(VerticalBar);
  FreeAndNil(HorizontalBar);
  FreeAndNil(FRenderer);
  FreeAndNil(Bitmap);
  Inherited Destroy;
End;

Function TStyledSurface.ViewRect: TRect;
Begin
  Result := Rect(Scale96ToFont(7), Scale96ToFont(6),
    ClientWidth - Scale96ToFont(7), ClientHeight - Scale96ToFont(6));
  If FShowVertical Then Dec(Result.Right, VerticalBar.Width);
  If FShowHorizontal Then Dec(Result.Bottom, HorizontalBar.Height);
  Result.Right := Max(Result.Left + 1, Result.Right);
  Result.Bottom := Max(Result.Top + 1, Result.Bottom);
End;

Procedure TStyledSurface.EnsureBuffer;
Var
  BufferW, BufferH: Integer;
Begin
  If Not Assigned(Bitmap) Then Exit;
  { Logical size only. Measurement uses this canvas; paint uses the control canvas. }
  BufferW := Max(1, ClientWidth);
  BufferH := Max(1, Min(ClientHeight, 8 * 1024 * 1024 Div Max(4, ClientWidth * 4)));
  If (Bitmap.Width <> BufferW) Or (Bitmap.Height <> BufferH) Then Bitmap.SetSize(BufferW, BufferH);
End;

Procedure TStyledSurface.ConfigureCanvas;
Var
  Target: TCanvas;
Begin
  If Not Assigned(FRenderer) Then
    Exit;
  If Assigned(FPaintCanvas) Then
    Target := FPaintCanvas
  Else If Assigned(Bitmap) Then
    Target := Bitmap.Canvas
  Else
    Exit;
  { Always logical client size so metrics stay stable across paint vs measure. }
  FRenderer.Configure(Target, Font, Max(1, ClientWidth), Max(1, ClientHeight));
End;

Procedure TStyledSurface.SetScrollbars(Vertical, Horizontal: Boolean);
Begin
  FAutoHideVertical := False;
  FWantVertical := Vertical;
  FShowVertical := Vertical;
  FShowHorizontal := Horizontal;
  If Vertical And Horizontal Then
    FScrollStyle := ssBoth
  Else If Vertical Then
    FScrollStyle := ssVertical
  Else If Horizontal Then
    FScrollStyle := ssHorizontal
  Else
    FScrollStyle := ssNone;
  VerticalBar.Visible := Vertical;
  HorizontalBar.Visible := Horizontal;
  Resize;
End;

Procedure TStyledSurface.SetScrollStyle(Value: TScrollStyle);
Begin
  If FScrollStyle = Value Then
    Exit;
  If Value <> ssAutoVertical Then
    Begin
      Case Value Of
        ssHorizontal, ssAutoHorizontal: SetScrollbars(False, True);
        ssVertical: SetScrollbars(True, False);
        ssBoth, ssAutoBoth: SetScrollbars(True, True);
      Else
        SetScrollbars(False, False);
      End;
      Exit;
    End;
  FScrollStyle := ssAutoVertical;
  FAutoHideVertical := True;
  FWantVertical := True;
  FShowHorizontal := False;
  FShowVertical := False;
  HorizontalBar.Visible := False;
  VerticalBar.Visible := False;
  Resize;
End;

Function TStyledSurface.IsLayoutSettled: Boolean;
Begin
  Result := True;
End;

Function TStyledSurface.UpdateAutoVerticalBar: Boolean;
Var
  NeedBar: Boolean;
Begin
  Result := False;
  If (Not FAutoHideVertical) Or (Not FWantVertical) Or FAdjustingAutoBar Or (Not IsLayoutSettled) Then
    Exit;
  NeedBar := FContentHeight > ViewRect.Height;
  If NeedBar = FShowVertical Then
    Exit;
  Result := True;
  FAdjustingAutoBar := True;
  Try
    FShowVertical := NeedBar;
    VerticalBar.Visible := NeedBar;
    If Not NeedBar Then
      FScrollTop := 0;
    UpdateScrollbarBounds;
    GeometryChanged;
    Invalidate;
  Finally
    FAdjustingAutoBar := False;
  End;
End;

Procedure TStyledSurface.UpdateScrollbarBounds;
Var Edge, VWidth, HHeight: Integer;
Begin
  If Not Assigned(VerticalBar) Or Not Assigned(HorizontalBar) Then Exit;
  Edge := Max(1, Scale96ToFont(1));
  { Native themes may constrain the requested size. Reserve the actual bar
    dimensions so its thumb never overlaps the viewport. }
  VerticalBar.Width := Max(Scale96ToFont(16), GetSystemMetrics(SM_CXVSCROLL));
  HorizontalBar.Height := Max(Scale96ToFont(16), GetSystemMetrics(SM_CYHSCROLL));
  VWidth := VerticalBar.Width; HHeight := HorizontalBar.Height;
  VerticalBar.SetBounds(Max(0, ClientWidth - Edge - VWidth), Edge, VWidth,
    Max(1, ClientHeight - 2*Edge - Ord(FShowHorizontal)*HHeight));
  HorizontalBar.SetBounds(Edge, Max(0, ClientHeight - Edge - HHeight),
    Max(1, ClientWidth - 2*Edge - Ord(FShowVertical)*VWidth), HHeight);
End;

Procedure TStyledSurface.Resize;
Begin
  Inherited Resize;
  If Not Assigned(VerticalBar) Then Exit;
  UpdateScrollbarBounds;
  { Measure on the resized surface before layout. The first canvas must not
    keep its line height after the view changes size. }
  EnsureBuffer;
  ConfigureCanvas;
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
      UpdateScrollbarBounds;
      GeometryChanged;
      SetExtent(FContentWidth, FContentHeight);
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
  If Assigned(FPaintCanvas) Then
    Result := FPaintCanvas
  Else
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
  { A visibility change relayouts at the new width and publishes the bar from that pass. }
  If UpdateAutoVerticalBar Then
    Exit;
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
  Clip, View: TRect;
Begin
  Started := GetTickCount64;
  View := ViewRect;
  EnsureBuffer;
  { Paint on the control canvas. Cocoa/Qt HiDPI backings rasterise TextOut at
    native resolution; an offscreen 1x bitmap blit was soft, and a scaled CTM
    offscreen path left the conversation blank on Mac. }
  FPaintCanvas := Canvas;
  Try
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Color;
    Canvas.FillRect(ClientRect);
    ConfigureCanvas;
    Clip := View;
    If (Clip.Right > Clip.Left) And (Clip.Bottom > Clip.Top) Then
      PaintContent(Clip, View.Left - ScrollLeft, Int64(View.Top) - ScrollTop);
    Canvas.Brush.Style := bsSolid;
    If Focused Then
      Canvas.Brush.Color := $00C08038
    Else
      Canvas.Brush.Color := $00C8C5BE;
    Canvas.FillRect(0, 0, ClientWidth, 1);
    Canvas.FillRect(0, ClientHeight - 1, ClientWidth, ClientHeight);
    Canvas.FillRect(0, 0, 1, ClientHeight);
    Canvas.FillRect(ClientWidth - 1, 0, ClientWidth, ClientHeight);
  Finally
    FPaintCanvas := Nil;
    { Point the renderer back at the measure bitmap for layout work. }
    ConfigureCanvas;
  End;
  FLastPaintMilliseconds := GetTickCount64 - Started;
  Inc(FPaintCount);
End;

End.
