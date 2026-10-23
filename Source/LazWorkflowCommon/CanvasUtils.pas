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

/// Draws an antialiased ring. Radius is the stroke centreline; StrokeWidth is the full thickness.
/// DiskRadius > 0 also fills a disk at the same centre, on top of the hole. Partial pixels blend against
/// Background. Do not read the canvas: a read comes back black and darkens the edge.
Procedure DrawSmoothRing(Target: TCanvas; CentreX, CentreY, Radius, StrokeWidth, DiskRadius: Single; Stroke, Fill, Background: TColor);

Implementation

Uses
  fpimage, IntfGraphics, Math;

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

Procedure DrawSmoothRing(Target: TCanvas; CentreX, CentreY, Radius, StrokeWidth, DiskRadius: Single; Stroke, Fill, Background: TColor);

  Function Clamp01(Value: Single): Single;
  Begin
    If Value <= 0 Then
      Result := 0
    Else If Value >= 1 Then
      Result := 1
    Else
      Result := Value;
  End;

  Function MixChannel(Base, Over, Coverage: Single): Single;
  Begin
    Result := Base + (Over - Base) * Coverage;
  End;

  Function AverageChannel(Sum: Single; Count: Integer): Word;
  Var
    Value: Single;
  Begin
    Value := Sum / Count;
    If Value <= 0 Then
      Result := 0
    Else If Value >= 65535 Then
      Result := 65535
    Else
      Result := Round(Value);
  End;

Var
  Left, Top, Right, Bottom, W, H, X, Y, SampleX, SampleY, SampleGrid, Samples: Integer;
  OuterRadius, InnerRadius, SampleScale, Dx, Dy, Dist, RingCoverage, DiskCoverage: Single;
  SampleR, SampleG, SampleB, SumR, SumG, SumB: Single;
  StrokeColor, FillColor, BackColor, Pixel: TFPColor;
  Bitmap: TBitmap;
  Image: TLazIntfImage;
Begin
  If (Not Assigned(Target)) Or (StrokeWidth <= 0) Or (Radius <= 0) Then
    Exit;
  OuterRadius := Radius + StrokeWidth / 2;
  InnerRadius := Radius - StrokeWidth / 2;
  If InnerRadius < 0 Then
    InnerRadius := 0;
  If DiskRadius < 0 Then
    DiskRadius := 0;
  { Coverage falls to zero half a pixel outside the outer edge. Include those pixels. }
  Left := Floor(CentreX - OuterRadius - 0.5);
  Top := Floor(CentreY - OuterRadius - 0.5);
  Right := Ceil(CentreX + OuterRadius + 0.5);
  Bottom := Ceil(CentreY + OuterRadius + 0.5);
  W := Right - Left;
  H := Bottom - Top;
  If (W < 2) Or (H < 2) Or (W > 256) Or (H > 256) Then
    Exit;
  StrokeColor := TColorToFPColor(ColorToRGB(Stroke));
  FillColor := TColorToFPColor(ColorToRGB(Fill));
  BackColor := TColorToFPColor(ColorToRGB(Background));
  { Finer than the card grid: a checkout ring is only a few pixels across. }
  SampleGrid := 8;
  Samples := SampleGrid * SampleGrid;
  SampleScale := 1 / SampleGrid;
  { Rasterise in image memory so the widgetset cannot stroke the circle. Copy once, opaquely. }
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
            SumR := 0;
            SumG := 0;
            SumB := 0;
            For SampleY := 0 To SampleGrid - 1 Do
              For SampleX := 0 To SampleGrid - 1 Do
                Begin
                  Dx := (Left + X + (SampleX + 0.5) * SampleScale) - CentreX;
                  Dy := (Top + Y + (SampleY + 0.5) * SampleScale) - CentreY;
                  Dist := Sqrt(Dx * Dx + Dy * Dy);
                  RingCoverage := Clamp01(OuterRadius + 0.5 - Dist) - Clamp01(InnerRadius + 0.5 - Dist);
                  If RingCoverage < 0 Then
                    RingCoverage := 0;
                  If DiskRadius > 0 Then
                    DiskCoverage := Clamp01(DiskRadius + 0.5 - Dist)
                  Else
                    DiskCoverage := 0;
                  { Ring first, then the disk, matching the old paint order. }
                  SampleR := MixChannel(BackColor.Red, StrokeColor.Red, RingCoverage);
                  SampleG := MixChannel(BackColor.Green, StrokeColor.Green, RingCoverage);
                  SampleB := MixChannel(BackColor.Blue, StrokeColor.Blue, RingCoverage);
                  SumR := SumR + MixChannel(SampleR, FillColor.Red, DiskCoverage);
                  SumG := SumG + MixChannel(SampleG, FillColor.Green, DiskCoverage);
                  SumB := SumB + MixChannel(SampleB, FillColor.Blue, DiskCoverage);
                End;
            Pixel.Red := AverageChannel(SumR, Samples);
            Pixel.Green := AverageChannel(SumG, Samples);
            Pixel.Blue := AverageChannel(SumB, Samples);
            Pixel.Alpha := 65535;
            Image.Colors[X, Y] := Pixel;
          End;
      Bitmap.LoadFromIntfImage(Image);
    Finally
      Image.Free;
    End;
    Target.Draw(Left, Top, Bitmap);
  Finally
    Bitmap.Free;
  End;
End;

End.
