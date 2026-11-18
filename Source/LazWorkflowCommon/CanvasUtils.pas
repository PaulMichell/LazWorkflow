Unit CanvasUtils;

{ Anti-aliased canvas drawing (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Graphics, IntfGraphics, Types;

Const
  { A cached marker centre is quantised to 1/SmoothMarkerCentreSteps of a logical pixel. }
  SmoothMarkerCentreSteps = 4;

Type
  { One cached marker. Dest is the logical rectangle it covers, relative to the whole-pixel part of the centre. }
  TSmoothMarkerEntry = Record
    Edge: TColor;
    OuterRadius, InnerRadius, Scale: Single;
    StepX, StepY: Integer;
    Bitmap: TBitmap;
    Dest: TRect;
  End;

  { A bounded cache of the straight-alpha bitmaps DrawSmoothDisk and DrawSmoothRing would build. The key is the edge
    colour (resolved to RGB), the outer radius, the inner radius (or none), the clamped pixel scale and the sub-pixel
    offset of the centre. That offset changes the pixels, because the bitmap starts at Floor(Centre - Radius - Pad),
    so it is quantised to 1/SmoothMarkerCentreSteps of a logical pixel rather than snapped to the physical grid.
    The owner calls Prepare before each paint; Prepare empties the cache when the scale or the theme colours change.
    When the cache is full the oldest entry is dropped. }
  TSmoothMarkerCache = Class
  Private
    FCapacity: Integer;
    FCount: Integer;
    Entries: Array Of TSmoothMarkerEntry;
    PreparedScale: Single;
    PreparedColors: Array Of TColor;
    Function IndexOf(Edge: TColor; OuterRadius, InnerRadius, Scale: Single; StepX, StepY: Integer): Integer;
    Procedure DropOldest;
  Protected
    { An empty 32-bit image, RGB plus alpha with no mask, for one marker to be rendered into. }
    Function NewMarkerImage: TLazIntfImage; Virtual;
    { Uploads one rendered marker. Called once per entry; the bitmap is never changed afterwards. }
    Function NewMarkerBitmap(Image: TLazIntfImage): TBitmap; Virtual;
  Public
    Constructor Create(MaxEntries: Integer = 48);
    Destructor Destroy; Override;
    Procedure Clear;
    { Empties the cache when PixelScale (clamped) or any of ThemeColors (resolved to RGB) differs from last time. }
    Procedure Prepare(PixelScale: Single; Const ThemeColors: Array Of TColor);
    { The cached bitmap for a disk (InnerRadius < 0) or ring band, rendering it on a miss. Dest receives the logical
      rectangle to draw it in. Nil, with an empty Dest, when nothing is drawn. The cache owns the bitmap. }
    Function Marker(CentreX, CentreY, OuterRadius, InnerRadius: Single; Edge: TColor; PixelScale: Single;
      Out Dest: TRect): TBitmap;
    { The cached equivalents of DrawSmoothDisk and DrawSmoothRing. }
    Procedure DrawDisk(Target: TCanvas; CentreX, CentreY, Radius: Single; Fill: TColor; PixelScale: Single);
    Procedure DrawRing(Target: TCanvas; CentreX, CentreY, Radius, StrokeWidth: Single; Stroke: TColor;
      PixelScale: Single);
    Property Capacity: Integer Read FCapacity;
    Property Count: Integer Read FCount;
  End;

/// Draws a symmetric rounded rectangle. Blend against Background, the colour just painted under Bounds.
/// The first paint cannot read those pixels: a canvas read comes back black and darkens the edge.
/// Rasterised into an opaque RGB bitmap and copied once (Cocoa-safe; no mask, no alpha channel needed).
/// PixelScale is the control canvas scale (Retina 2). Values <= 1 keep a 1x buffer.
Procedure DrawSmoothRoundRect(Target: TCanvas; Const Bounds: TRect; Radius: Single; Fill, Border, Background: TColor;
  PixelScale: Single = 1);

/// Draws an antialiased disk over what is already painted. Radius is the 50% edge.
/// Uses the same coverage grid as DrawSmoothRing. Uncovered pixels use alpha 0 so paths remain.
/// Partial pixels hold the fill colour with alpha equal to their coverage; the widgetset composites them.
/// Drawn via an 8-bit straight-alpha bitmap (not a 1-bit mask): Cocoa ignores masks on plain Draw.
/// PixelScale is the control canvas scale (Retina 2). Values <= 1 keep a 1x buffer.
Procedure DrawSmoothDisk(Target: TCanvas; CentreX, CentreY, Radius: Single; Fill: TColor; PixelScale: Single = 1);

/// Draws an antialiased ring over what is already painted. Radius is the stroke centreline.
/// StrokeWidth is the full thickness. Uncovered pixels use alpha 0 so lane dots and paths remain.
/// Partial pixels hold the stroke colour with alpha equal to their coverage; the widgetset composites them.
/// Drawn via an 8-bit straight-alpha bitmap (not a 1-bit mask): Cocoa ignores masks on plain Draw.
/// PixelScale is the control canvas scale (Retina 2). Values <= 1 keep a 1x buffer.
Procedure DrawSmoothRing(Target: TCanvas; CentreX, CentreY, Radius, StrokeWidth: Single; Stroke: TColor;
  PixelScale: Single = 1);

/// Rasterises the image DrawSmoothRoundRect copies for a LogicalW x LogicalH rectangle. Image is resized to the
/// backing size. Returns False, leaving Image unchanged, when the rectangle is too small to draw.
/// SkipUniform False supersamples every pixel; tests compare it with the default, which must match exactly.
Function RenderSmoothRoundRect(Image: TLazIntfImage; LogicalW, LogicalH: Integer; Radius: Single;
  Fill, Border, Background: TColor; PixelScale: Single; SkipUniform: Boolean = True): Boolean;

/// Rasterises the image DrawSmoothDisk (InnerRadius < 0) or DrawSmoothRing (the band between the radii) copies.
/// Image needs an alpha channel and is resized to the backing size; Dest receives the logical rectangle it covers.
/// Every drawn pixel is Edge with straight (not premultiplied) alpha equal to its coverage.
/// Returns False when nothing is drawn. SkipUniform False supersamples every pixel, as for RenderSmoothRoundRect.
Function RenderCoverageCircle(Image: TLazIntfImage; CentreX, CentreY, OuterRadius, InnerRadius: Single;
  Edge: TColor; PixelScale: Single; Out Dest: TRect; SkipUniform: Boolean = True): Boolean;

Implementation

Uses
  SysUtils, fpimage, GraphType, Math;

Const
  { Full width of the coverage ramp of a disk or ring, in physical pixels. }
  SmoothCoverageWidth = 0.5;
  { Half a pixel diagonal, rounded up. No supersample lies farther than this from its pixel centre. }
  PixelReach = 0.7072;
  { An uncovered disk or ring pixel. }
  ClearPixel: TFPColor = (Red: 0; Green: 0; Blue: 0; Alpha: 0);

Function ClampSmoothScale(Scale: Single): Single;
Begin
  If Scale < 1 Then
    Result := 1
  Else If Scale > 4 Then
    Result := 4
  Else
    Result := Scale;
End;

{ Distance is a pixel centre's signed distance from a coverage edge, positive outside, and HalfRamp is half the width
  of that edge's coverage ramp. The distance must change no faster than position does, as a true distance does.
  True when every sample in the pixel then has the same coverage, 0 or 1, returned in Coverage. }
Function UniformCoverage(Distance, HalfRamp: Single; Out Coverage: Single): Boolean;
Begin
  Result := True;
  If Distance > HalfRamp + PixelReach Then
    Coverage := 0
  Else If Distance < -(HalfRamp + PixelReach) Then
    Coverage := 1
  Else
    Begin
      Coverage := 0;
      Result := False;
    End;
End;

Procedure BlitSmoothImage(Target: TCanvas; Const Dest: TRect; Image: TLazIntfImage; Scale: Single);
Var
  Bitmap: TBitmap;
Begin
  Bitmap := TBitmap.Create;
  Try
    Bitmap.LoadFromIntfImage(Image);
    Bitmap.Transparent := False;
    If Abs(Scale - 1) <= 1E-3 Then
      Target.Draw(Dest.Left, Dest.Top, Bitmap)
    Else
      Target.StretchDraw(Dest, Bitmap);
  Finally
    Bitmap.Free;
  End;
End;

Function RenderSmoothRoundRect(Image: TLazIntfImage; LogicalW, LogicalH: Integer; Radius: Single;
  Fill, Border, Background: TColor; PixelScale: Single; SkipUniform: Boolean): Boolean;

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

  { The exact signed distance from a rounded box, so it changes no faster than position does. }
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
  PhysW, PhysH, X, Y, SampleX, SampleY: Integer;
  Scale, CX, CY, HalfW, HalfH, UsedRadius, BorderWidth, SD, Outer, Inner, OuterSum, InnerSum: Single;
  FillColor, BorderColor, BackColor: TFPColor;
Begin
  Result := False;
  If (Not Assigned(Image)) Or (LogicalW < 2) Or (LogicalH < 2) Then
    Exit;
  Scale := ClampSmoothScale(PixelScale);
  PhysW := Max(2, Ceil(LogicalW * Scale - 1E-6));
  PhysH := Max(2, Ceil(LogicalH * Scale - 1E-6));
  HalfW := PhysW / 2;
  HalfH := PhysH / 2;
  UsedRadius := Radius * Scale;
  If UsedRadius > MinSingle(HalfW, HalfH) - Scale Then
    UsedRadius := MinSingle(HalfW, HalfH) - Scale;
  If UsedRadius < Scale Then
    UsedRadius := Scale;
  { One logical pixel of border, in physical samples. }
  BorderWidth := Scale;
  CX := PhysW / 2;
  CY := PhysH / 2;
  FillColor := ColorToFP(Fill);
  BorderColor := ColorToFP(Border);
  BackColor := ColorToFP(Background);
  { Rasterise at backing resolution so Retina does not upscale a soft 1x fringe. }
  Image.SetSize(PhysW, PhysH);
  For Y := 0 To PhysH - 1 Do
    For X := 0 To PhysW - 1 Do
      Begin
        { A pixel well clear of both edges has one coverage throughout; its 16 samples would all agree. }
        SD := RoundRectDistance(X + 0.5 - CX, Y + 0.5 - CY, HalfW, HalfH, UsedRadius);
        If Not (SkipUniform And UniformCoverage(SD, 0.5, Outer) And UniformCoverage(SD + BorderWidth, 0.5, Inner)) Then
          Begin
            OuterSum := 0;
            InnerSum := 0;
            For SampleY := 0 To 3 Do
              For SampleX := 0 To 3 Do
                Begin
                  SD := RoundRectDistance(
                    (X + (SampleX + 0.5) / 4) - CX,
                    (Y + (SampleY + 0.5) / 4) - CY,
                    HalfW, HalfH, UsedRadius);
                  OuterSum := OuterSum + Clamp01(0.5 - SD);
                  InnerSum := InnerSum + Clamp01(0.5 - (SD + BorderWidth));
                End;
            Outer := OuterSum / 16;
            Inner := InnerSum / 16;
          End;
        Image.Colors[X, Y] := MixCoverage(BackColor, BorderColor, FillColor, Outer, Inner);
      End;
  Result := True;
End;

Procedure DrawSmoothRoundRect(Target: TCanvas; Const Bounds: TRect; Radius: Single; Fill, Border, Background: TColor;
  PixelScale: Single);
Var
  Image: TLazIntfImage;
Begin
  If Not Assigned(Target) Then
    Exit;
  { Every pixel is opaque, so the image needs no alpha channel and draws on any widgetset. }
  Image := TLazIntfImage.Create(0, 0, [riqfRGB]);
  Try
    If RenderSmoothRoundRect(Image, Bounds.Right - Bounds.Left, Bounds.Bottom - Bounds.Top, Radius, Fill, Border,
      Background, PixelScale) Then
      BlitSmoothImage(Target, Bounds, Image, ClampSmoothScale(PixelScale));
  Finally
    Image.Free;
  End;
End;

{ InnerRadius < 0 fills a disk of OuterRadius. Otherwise the stroke is the band between the two radii.
  Both shapes use one 8x8 coverage grid so a lane dot cannot be softer or harder than the checkout ring.
  Partial pixels carry the edge colour with straight alpha equal to their coverage, and the widgetset composites them
  over whatever is already painted, so nothing here needs to know what lies underneath.
  Geometry is logical; PixelScale rasterises at backing resolution. }
Function RenderCoverageCircle(Image: TLazIntfImage; CentreX, CentreY, OuterRadius, InnerRadius: Single;
  Edge: TColor; PixelScale: Single; Out Dest: TRect; SkipUniform: Boolean): Boolean;

  Function Clamp01(Value: Single): Single;
  Begin
    If Value <= 0 Then
      Result := 0
    Else If Value >= 1 Then
      Result := 1
    Else
      Result := Value;
  End;

  Function CoverageAlpha(Coverage: Single): Word;
  Begin
    If Coverage <= 0 Then
      Result := 0
    Else If Coverage >= 1 Then
      Result := 65535
    Else
      Result := Round(65535 * Coverage);
  End;

  Function SampleCoverage(Dist, OuterR, InnerR: Single): Single;

    Function EdgeCoverage(Edge: Single): Single;
    Begin
      Result := Clamp01((Edge + SmoothCoverageWidth / 2 - Dist) / SmoothCoverageWidth);
    End;

  Begin
    If InnerR < 0 Then
      Result := EdgeCoverage(OuterR)
    Else
      Begin
        Result := EdgeCoverage(OuterR) - EdgeCoverage(InnerR);
        If Result < 0 Then
          Result := 0;
      End;
  End;

Var
  Scale: Single;
  Left, Top, Right, Bottom, PhysW, PhysH, X, Y, SampleX, SampleY, SampleGrid, Samples, MaxExtent: Integer;
  SampleScale, Dx, Dy, Dist, CoverageSum: Single;
  PhysCentreX, PhysCentreY, PhysOuter, PhysInner, Pad, OuterCoverage, InnerCoverage: Single;
  EdgeColor, Pixel: TFPColor;
Begin
  Result := False;
  Dest := Rect(0, 0, 0, 0);
  If (Not Assigned(Image)) Or (OuterRadius <= 0) Then
    Exit;
  If Image.DataDescription.AlphaPrec < 1 Then
    Exit;
  Scale := ClampSmoothScale(PixelScale);
  Pad := SmoothCoverageWidth / 2;
  Left := Floor(CentreX - OuterRadius - Pad);
  Top := Floor(CentreY - OuterRadius - Pad);
  Right := Ceil(CentreX + OuterRadius + Pad);
  Bottom := Ceil(CentreY + OuterRadius + Pad);
  PhysW := Max(2, Ceil((Right - Left) * Scale - 1E-6));
  PhysH := Max(2, Ceil((Bottom - Top) * Scale - 1E-6));
  MaxExtent := Max(256, Ceil(256 * Scale));
  If (PhysW > MaxExtent) Or (PhysH > MaxExtent) Then
    Exit;
  Dest := Rect(Left, Top, Right, Bottom);
  PhysCentreX := (CentreX - Left) * Scale;
  PhysCentreY := (CentreY - Top) * Scale;
  PhysOuter := OuterRadius * Scale;
  If InnerRadius < 0 Then
    PhysInner := -1
  Else
    PhysInner := InnerRadius * Scale;
  EdgeColor := TColorToFPColor(ColorToRGB(Edge));
  SampleGrid := 8;
  Samples := SampleGrid * SampleGrid;
  SampleScale := 1 / SampleGrid;
  Image.SetSize(PhysW, PhysH);
  For Y := 0 To PhysH - 1 Do
    For X := 0 To PhysW - 1 Do
      Begin
        { A pixel well clear of every edge has one coverage throughout: opaque edge colour, or transparent. }
        Dx := X + 0.5 - PhysCentreX;
        Dy := Y + 0.5 - PhysCentreY;
        Dist := Sqrt(Dx * Dx + Dy * Dy);
        If SkipUniform And UniformCoverage(Dist - PhysOuter, Pad, OuterCoverage) And
          ((PhysInner < 0) Or UniformCoverage(Dist - PhysInner, Pad, InnerCoverage)) Then
          Begin
            If PhysInner < 0 Then
              InnerCoverage := 0;
            If OuterCoverage > InnerCoverage Then
              Begin
                Pixel := EdgeColor;
                Pixel.Alpha := 65535;
              End
            Else
              Pixel := ClearPixel;
            Image.Colors[X, Y] := Pixel;
            Continue;
          End;
        CoverageSum := 0;
        For SampleY := 0 To SampleGrid - 1 Do
          For SampleX := 0 To SampleGrid - 1 Do
            Begin
              Dx := X + (SampleX + 0.5) * SampleScale - PhysCentreX;
              Dy := Y + (SampleY + 0.5) * SampleScale - PhysCentreY;
              Dist := Sqrt(Dx * Dx + Dy * Dy);
              CoverageSum := CoverageSum + SampleCoverage(Dist, PhysOuter, PhysInner);
            End;
        If CoverageSum <= 0 Then
          Pixel := ClearPixel
        Else
          Begin
            Pixel := EdgeColor;
            Pixel.Alpha := CoverageAlpha(CoverageSum / Samples);
          End;
        Image.Colors[X, Y] := Pixel;
      End;
  Result := True;
End;

{ The outer and inner radii of a ring band. False when there is nothing to draw. }
Function RingRadii(Radius, StrokeWidth: Single; Out OuterRadius, InnerRadius: Single): Boolean;
Begin
  OuterRadius := Radius + StrokeWidth / 2;
  InnerRadius := Radius - StrokeWidth / 2;
  If InnerRadius < 0 Then
    InnerRadius := 0;
  Result := (StrokeWidth > 0) And (Radius > 0);
End;

Procedure DrawCoverageCircle(Target: TCanvas; CentreX, CentreY, OuterRadius, InnerRadius: Single; Edge: TColor;
  PixelScale: Single);
Var
  Image: TLazIntfImage;
  Dest: TRect;
Begin
  If Not Assigned(Target) Then
    Exit;
  { RGB plus alpha with no mask. A BGRA description is not premultiplied on Cocoa, and a masked image is declared
    premultiplied under Qt on macOS; either would darken the straight-alpha fringe. }
  Image := TLazIntfImage.Create(0, 0, [riqfRGB, riqfAlpha]);
  Try
    If RenderCoverageCircle(Image, CentreX, CentreY, OuterRadius, InnerRadius, Edge, PixelScale, Dest) Then
      BlitSmoothImage(Target, Dest, Image, ClampSmoothScale(PixelScale));
  Finally
    Image.Free;
  End;
End;

Procedure DrawSmoothDisk(Target: TCanvas; CentreX, CentreY, Radius: Single; Fill: TColor; PixelScale: Single);
Begin
  If Radius <= 0 Then
    Exit;
  DrawCoverageCircle(Target, CentreX, CentreY, Radius, -1, Fill, PixelScale);
End;

Procedure DrawSmoothRing(Target: TCanvas; CentreX, CentreY, Radius, StrokeWidth: Single; Stroke: TColor;
  PixelScale: Single);
Var
  OuterRadius, InnerRadius: Single;
Begin
  If RingRadii(Radius, StrokeWidth, OuterRadius, InnerRadius) Then
    DrawCoverageCircle(Target, CentreX, CentreY, OuterRadius, InnerRadius, Stroke, PixelScale);
End;

{ TSmoothMarkerCache }

{ Splits a logical coordinate into its whole-pixel floor and a quantised fraction in 0..SmoothMarkerCentreSteps - 1.
  A fraction that rounds up to a whole step moves to the next pixel. }
Procedure QuantiseCentre(Value: Single; Out Base, Step: Integer);
Begin
  Base := Floor(Value);
  Step := Round((Value - Base) * SmoothMarkerCentreSteps);
  If Step >= SmoothMarkerCentreSteps Then
    Begin
      Inc(Base);
      Step := 0;
    End;
End;

Function SameRadius(A, B: Single): Boolean;
Begin
  Result := Abs(A - B) <= 1E-4;
End;

Constructor TSmoothMarkerCache.Create(MaxEntries: Integer);
Begin
  Inherited Create;
  FCapacity := Max(1, MaxEntries);
  FCount := 0;
  SetLength(Entries, FCapacity);
  PreparedScale := 0;
  PreparedColors := Nil;
End;

Destructor TSmoothMarkerCache.Destroy;
Begin
  Clear;
  Inherited Destroy;
End;

Procedure TSmoothMarkerCache.Clear;
Var
  I: Integer;
Begin
  For I := 0 To FCount - 1 Do
    FreeAndNil(Entries[I].Bitmap);
  FCount := 0;
End;

Procedure TSmoothMarkerCache.Prepare(PixelScale: Single; Const ThemeColors: Array Of TColor);
Var
  I: Integer;
  Scale: Single;
  Changed: Boolean;
Begin
  Scale := ClampSmoothScale(PixelScale);
  Changed := (Abs(Scale - PreparedScale) > 1E-3) Or (Length(PreparedColors) <> Length(ThemeColors));
  If Not Changed Then
    For I := 0 To High(ThemeColors) Do
      If ColorToRGB(ThemeColors[I]) <> PreparedColors[I] Then
        Begin
          Changed := True;
          Break;
        End;
  If Not Changed Then
    Exit;
  Clear;
  PreparedScale := Scale;
  SetLength(PreparedColors, Length(ThemeColors));
  For I := 0 To High(ThemeColors) Do
    PreparedColors[I] := ColorToRGB(ThemeColors[I]);
End;

Function TSmoothMarkerCache.IndexOf(Edge: TColor; OuterRadius, InnerRadius, Scale: Single; StepX, StepY: Integer): Integer;
Var
  I: Integer;
Begin
  For I := 0 To FCount - 1 Do
    If (Entries[I].Edge = Edge) And (Entries[I].StepX = StepX) And (Entries[I].StepY = StepY) And
      SameRadius(Entries[I].OuterRadius, OuterRadius) And SameRadius(Entries[I].InnerRadius, InnerRadius) And
      SameRadius(Entries[I].Scale, Scale) Then
      Exit(I);
  Result := -1;
End;

Procedure TSmoothMarkerCache.DropOldest;
Var
  I: Integer;
Begin
  If FCount = 0 Then
    Exit;
  FreeAndNil(Entries[0].Bitmap);
  For I := 1 To FCount - 1 Do
    Entries[I - 1] := Entries[I];
  Entries[FCount - 1].Bitmap := Nil;
  Dec(FCount);
End;

Function TSmoothMarkerCache.NewMarkerImage: TLazIntfImage;
Begin
  { No mask: a BGRA description is not premultiplied on Cocoa, and a masked image is declared premultiplied under Qt
    on macOS; either would darken the straight-alpha fringe. }
  Result := TLazIntfImage.Create(0, 0, [riqfRGB, riqfAlpha]);
End;

Function TSmoothMarkerCache.NewMarkerBitmap(Image: TLazIntfImage): TBitmap;
Begin
  { GTK2 keeps the 32-bit pixbuf only while nothing else touches the bitmap. Load it once and never set Transparent,
    Masked, BeginUpdate or Handle afterwards, or GTK2 falls back to a 1-bit mask. The cache keeps the bitmap alive,
    so its canvas DC keeps the pixbuf. }
  Result := TBitmap.Create;
  Try
    Result.LoadFromIntfImage(Image);
  Except
    Result.Free;
    Raise;
  End;
End;

Function TSmoothMarkerCache.Marker(CentreX, CentreY, OuterRadius, InnerRadius: Single; Edge: TColor; PixelScale: Single;
  Out Dest: TRect): TBitmap;
Var
  BaseX, BaseY, StepX, StepY, Index: Integer;
  Scale: Single;
  EdgeRGB: TColor;
  Image: TLazIntfImage;
  Local: TRect;
  Bitmap: TBitmap;
Begin
  Result := Nil;
  Dest := Rect(0, 0, 0, 0);
  If OuterRadius <= 0 Then
    Exit;
  If InnerRadius < 0 Then
    InnerRadius := -1;
  Scale := ClampSmoothScale(PixelScale);
  EdgeRGB := ColorToRGB(Edge);
  QuantiseCentre(CentreX, BaseX, StepX);
  QuantiseCentre(CentreY, BaseY, StepY);
  Index := IndexOf(EdgeRGB, OuterRadius, InnerRadius, Scale, StepX, StepY);
  If Index < 0 Then
    Begin
      { Rendered with the centre's whole-pixel part removed. RenderCoverageCircle is exact under a whole-pixel
        shift, so the result equals rendering at the quantised centre itself. }
      Image := NewMarkerImage;
      Try
        If Not RenderCoverageCircle(Image, StepX / SmoothMarkerCentreSteps, StepY / SmoothMarkerCentreSteps,
          OuterRadius, InnerRadius, EdgeRGB, Scale, Local) Then
          Exit;
        Bitmap := NewMarkerBitmap(Image);
      Finally
        Image.Free;
      End;
      If FCount >= FCapacity Then
        DropOldest;
      Index := FCount;
      Entries[Index].Edge := EdgeRGB;
      Entries[Index].OuterRadius := OuterRadius;
      Entries[Index].InnerRadius := InnerRadius;
      Entries[Index].Scale := Scale;
      Entries[Index].StepX := StepX;
      Entries[Index].StepY := StepY;
      Entries[Index].Bitmap := Bitmap;
      Entries[Index].Dest := Local;
      Inc(FCount);
    End;
  Result := Entries[Index].Bitmap;
  Dest := Entries[Index].Dest;
  OffsetRect(Dest, BaseX, BaseY);
End;

Procedure DrawMarkerBitmap(Target: TCanvas; Bitmap: TBitmap; Const Dest: TRect; PixelScale: Single);
Begin
  If (Not Assigned(Target)) Or (Not Assigned(Bitmap)) Then
    Exit;
  { Win32 still copies and premultiplies the bitmap on every blit, as it did before the cache. That cost is not a
    regression; the cache saves the rasterising, not the copy. }
  If Abs(ClampSmoothScale(PixelScale) - 1) <= 1E-3 Then
    Target.Draw(Dest.Left, Dest.Top, Bitmap)
  Else
    Target.StretchDraw(Dest, Bitmap);
End;

Procedure TSmoothMarkerCache.DrawDisk(Target: TCanvas; CentreX, CentreY, Radius: Single; Fill: TColor; PixelScale: Single);
Var
  Bitmap: TBitmap;
  Dest: TRect;
Begin
  If (Not Assigned(Target)) Or (Radius <= 0) Then
    Exit;
  Bitmap := Marker(CentreX, CentreY, Radius, -1, Fill, PixelScale, Dest);
  DrawMarkerBitmap(Target, Bitmap, Dest, PixelScale);
End;

Procedure TSmoothMarkerCache.DrawRing(Target: TCanvas; CentreX, CentreY, Radius, StrokeWidth: Single; Stroke: TColor;
  PixelScale: Single);
Var
  OuterRadius, InnerRadius: Single;
  Bitmap: TBitmap;
  Dest: TRect;
Begin
  If (Not Assigned(Target)) Or (Not RingRadii(Radius, StrokeWidth, OuterRadius, InnerRadius)) Then
    Exit;
  Bitmap := Marker(CentreX, CentreY, OuterRadius, InnerRadius, Stroke, PixelScale, Dest);
  DrawMarkerBitmap(Target, Bitmap, Dest, PixelScale);
End;

End.
