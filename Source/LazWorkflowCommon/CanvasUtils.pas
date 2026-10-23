Unit CanvasUtils;

{ Anti-aliased canvas drawing (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Graphics, Types;

/// Draws a symmetric rounded rectangle. Blend against Background, the colour just painted under Bounds.
/// The first paint cannot read those pixels: a canvas read comes back black and darkens the edge.
Procedure DrawSmoothRoundRect(Target: TCanvas; Const Bounds: TRect; Radius: Single; Fill, Border, Background: TColor);

Implementation

Uses
  fpimage, IntfGraphics;

Procedure DrawSmoothRoundRect(Target: TCanvas; Const Bounds: TRect; Radius: Single; Fill, Border, Background: TColor);

  Function Clamp01(Value: Single): Single;
  Begin
    If Value <= 0 Then
      Result := 0
    Else If Value >= 1 Then
      Result := 1
    Else
      Result := Value;
  End;

  Function ClampChannel(Value: Single): Word;
  Begin
    If Value <= 0 Then
      Result := 0
    Else If Value >= 65535 Then
      Result := 65535
    Else
      Result := Round(Value);
  End;

  Function MaxSingle(A, B: Single): Single;
  Begin
    If A > B Then
      Result := A
    Else
      Result := B;
  End;

  Function MinSingle(A, B: Single): Single;
  Begin
    If A < B Then
      Result := A
    Else
      Result := B;
  End;

  Function RoundRectDistance(PX, PY, HalfW, HalfH, CornerRadius: Single): Single;
  Var
    QX, QY, AX, AY: Single;
  Begin
    QX := Abs(PX) - HalfW + CornerRadius;
    QY := Abs(PY) - HalfH + CornerRadius;
    AX := MaxSingle(QX, 0);
    AY := MaxSingle(QY, 0);
    Result := MinSingle(MaxSingle(QX, QY), 0) + Sqrt(AX * AX + AY * AY) - CornerRadius;
  End;

  Function ColorToFP(C: TColor): TFPColor;
  Var
    RGB: TColor;
  Begin
    RGB := ColorToRGB(C);
    Result.Red := Word(RGB And $FF) * 257;
    Result.Green := Word((RGB Shr 8) And $FF) * 257;
    Result.Blue := Word((RGB Shr 16) And $FF) * 257;
    Result.Alpha := 65535;
  End;

  Function MixCoverage(Const Back, Edge, Inside: TFPColor; Outer, Inner: Single): TFPColor;
  Var
    BackWeight, EdgeWeight: Single;
  Begin
    BackWeight := 1 - Outer;
    EdgeWeight := Outer - Inner;
    Result.Red := ClampChannel(Back.Red * BackWeight + Edge.Red * EdgeWeight + Inside.Red * Inner);
    Result.Green := ClampChannel(Back.Green * BackWeight + Edge.Green * EdgeWeight + Inside.Green * Inner);
    Result.Blue := ClampChannel(Back.Blue * BackWeight + Edge.Blue * EdgeWeight + Inside.Blue * Inner);
    Result.Alpha := 65535;
  End;

Var
  W, H, X, Y, SampleX, SampleY: Integer;
  CX, CY, HalfW, HalfH, UsedRadius, SD, Outer, Inner, OuterSum, InnerSum: Single;
  FillColor, BorderColor, BackColor, Pixel: TFPColor;
  Bitmap: TBitmap;
  Image: TLazIntfImage;
Begin
  W := Bounds.Right - Bounds.Left;
  H := Bounds.Bottom - Bounds.Top;
  If (W < 2) Or (H < 2) Or Not Assigned(Target) Then
    Exit;
  HalfW := W / 2;
  HalfH := H / 2;
  UsedRadius := Radius;
  If UsedRadius > MinSingle(HalfW, HalfH) - 1 Then
    UsedRadius := MinSingle(HalfW, HalfH) - 1;
  If UsedRadius < 1 Then
    UsedRadius := 1;
  CX := (Bounds.Left + Bounds.Right) / 2;
  CY := (Bounds.Top + Bounds.Bottom) / 2;
  FillColor := ColorToFP(Fill);
  BorderColor := ColorToFP(Border);
  BackColor := ColorToFP(Background);
  { Rasterise in image memory so the widgetset cannot stroke or offset individual
    pixel writes. Include the background in every corner and copy once, opaquely. }
  Bitmap := TBitmap.Create;
  Try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(W, H);
    Bitmap.Transparent := False;
    Image := Bitmap.CreateIntfImage;
    Try
      For Y := 0 To H - 1 Do
        For X := 0 To W - 1 Do
          Begin
            OuterSum := 0;
            InnerSum := 0;
            For SampleY := 0 To 1 Do
              For SampleX := 0 To 1 Do
                Begin
                  SD := RoundRectDistance(
                    (Bounds.Left + X + 0.5 + (SampleX * 2 - 1) * 0.25) - CX,
                    (Bounds.Top + Y + 0.5 + (SampleY * 2 - 1) * 0.25) - CY,
                    HalfW, HalfH, UsedRadius);
                  OuterSum := OuterSum + Clamp01(0.5 - SD);
                  InnerSum := InnerSum + Clamp01(0.5 - (SD + 1));
                End;
            Outer := OuterSum / 4;
            Inner := InnerSum / 4;
            Pixel := MixCoverage(BackColor, BorderColor, FillColor, Outer, Inner);
            Image.Colors[X, Y] := Pixel;
          End;
      Bitmap.LoadFromIntfImage(Image);
    Finally
      Image.Free;
    End;
    Target.Draw(Bounds.Left, Bounds.Top, Bitmap);
  Finally
    Bitmap.Free;
  End;
End;

End.
