Unit StyledBoxPainter;

{ Clipped solid and rounded box painting (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Graphics, Types, StyledTextTypes;

Procedure PaintStyledBox(Canvas: TCanvas; Const Geometry: TStyledBoxGeometry; Const Style: TStyledBoxStyle; Const Clip: TRect);
Function ClipStyledBoxText(Canvas: TCanvas; Const Geometry: TStyledBoxGeometry; Const Style: TStyledBoxStyle; Const Clip: TRect): Boolean;

Implementation

Uses
  Math, LCLIntf;

Function BoxRadius(Const Bounds: TStyledBoxRect; Radius: Integer): Integer;
Begin
  Result := Max(Int64(0), Min(Int64(Radius), Min(Bounds.Right - Bounds.Left, Bounds.Bottom - Bounds.Top) Div 2));
End;

Procedure BoxSpan(Const Bounds: TStyledBoxRect; Radius: Integer; Y: Int64; Out Left, Right: Int64);
Var
  Distance: Double;
  Inset: Integer;
Begin
  Left := Bounds.Left;
  Right := Bounds.Right;
  If (Y < Bounds.Top) Or (Y >= Bounds.Bottom) Then Begin Right := Left; Exit; End;
  Distance := Max(0.0, Max(Bounds.Top + Radius - (Y + 0.5), (Y + 0.5) - (Bounds.Bottom - Radius)));
  If (Radius > 0) And (Distance > 0) Then
    Begin
      Inset := Max(0, Ceil(Radius - Sqrt(Max(0.0, Sqr(Double(Radius)) - Sqr(Distance))) - 0.5));
      Inc(Left, Inset);
      Dec(Right, Inset);
    End;
End;

Procedure PaintStyledBox(Canvas: TCanvas; Const Geometry: TStyledBoxGeometry; Const Style: TStyledBoxStyle; Const Clip: TRect);
Var
  Radius, InnerRadius: Integer;
  Y, NextY, Finish, OuterLeft, OuterRight, InnerLeft, InnerRight: Int64;

  Procedure Fill(Left, Right: Int64; Color: TColor);
  Begin
    Left := Max(Left, Int64(Clip.Left));
    Right := Min(Right, Int64(Clip.Right));
    If (Color = clNone) Or (Left >= Right) Then Exit;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Color;
    Canvas.FillRect(Integer(Left), Integer(Y), Integer(Right), Integer(NextY));
  End;

Begin
  Radius := BoxRadius(Geometry.Border, Style.CornerRadius);
  InnerRadius := BoxRadius(Geometry.Padding, Max(0, Radius - Max(0, Style.BorderWidth)));
  Y := Max(Int64(Clip.Top), Geometry.Border.Top);
  Finish := Min(Int64(Clip.Bottom), Geometry.Border.Bottom);
  Canvas.SaveHandleState;
  Try
    IntersectClipRect(Canvas.Handle, Clip.Left, Clip.Top, Clip.Right, Clip.Bottom);
    While Y < Finish Do
      Begin
        NextY := Y + 1;
        If (Y >= Geometry.Border.Top + Radius) And (Y >= Geometry.Padding.Top + InnerRadius) Then
          NextY := Max(NextY, Min(Finish, Min(Geometry.Border.Bottom - Radius, Geometry.Padding.Bottom - InnerRadius)));
        BoxSpan(Geometry.Border, Radius, Y, OuterLeft, OuterRight);
        BoxSpan(Geometry.Padding, InnerRadius, Y, InnerLeft, InnerRight);
        Fill(OuterLeft, OuterRight, Style.Background);
        If InnerLeft >= InnerRight Then Fill(OuterLeft, OuterRight, Style.BorderColor)
        Else
          Begin
            Fill(OuterLeft, InnerLeft, Style.BorderColor);
            Fill(InnerRight, OuterRight, Style.BorderColor);
          End;
        Y := NextY;
      End;
  Finally
    Canvas.RestoreHandleState;
  End;
End;

Function ClipStyledBoxText(Canvas: TCanvas; Const Geometry: TStyledBoxGeometry; Const Style: TStyledBoxStyle; Const Clip: TRect): Boolean;
Var
  Radius: Integer;
  Y, Finish, Left, Right, NextY, ContentLeft, ContentRight: Int64;
Begin
  ContentLeft := Max(Geometry.Content.Left, Int64(Clip.Left));
  ContentRight := Min(Geometry.Content.Right, Int64(Clip.Right));
  Y := Max(Geometry.Content.Top, Int64(Clip.Top));
  Finish := Min(Geometry.Content.Bottom, Int64(Clip.Bottom));
  Result := (ContentLeft < ContentRight) And (Y < Finish);
  If Not Result Then Exit;
  IntersectClipRect(Canvas.Handle, Integer(ContentLeft), Integer(Y), Integer(ContentRight), Integer(Finish));
  Radius := BoxRadius(Geometry.Padding, Max(0, BoxRadius(Geometry.Border, Style.CornerRadius) - Max(0, Style.BorderWidth)));
  If Radius = 0 Then Exit;
  { Exclude corner bands in logical canvas coordinates. Selecting an HRGN uses
    device coordinates and loses the origin of a paintbox's parent canvas.
    Subtracting also preserves the caller's existing clip, including holes. }
  While Y < Finish Do
    Begin
      NextY := Y + 1;
      If Y >= Geometry.Padding.Top + Radius Then NextY := Max(NextY, Min(Finish, Geometry.Padding.Bottom - Radius));
      BoxSpan(Geometry.Padding, Radius, Y, Left, Right);
      If Left > ContentLeft Then
        ExcludeClipRect(Canvas.Handle, Integer(ContentLeft), Integer(Y), Integer(Min(Left, ContentRight)), Integer(NextY));
      If Right < ContentRight Then
        ExcludeClipRect(Canvas.Handle, Integer(Max(Right, ContentLeft)), Integer(Y), Integer(ContentRight), Integer(NextY));
      Y := NextY;
    End;
End;

End.
