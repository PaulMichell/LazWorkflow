Program CanvasSmoothShapesTest;

{ Checks the smooth-shape rasterisers: uniform pixels are skipped without changing one, straight-alpha markers
  composite like the old pre-blended ones, and the marker cache keys and bounds its bitmaps (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, SysUtils, Types, Math, Graphics, GraphType, fpimage, IntfGraphics, CanvasUtils;

Const
  Scales: Array[0..1] Of Single = (1, 2);
  TimingRepeats = 200;
  ClearPixel: TFPColor = (Red: 0; Green: 0; Blue: 0; Alpha: 0);

Type
  { Renders into a fixed BGRA description and hands out empty bitmaps, so no widgetset query or upload is needed.
    Captures whether each rendered marker matched Reference pixel for pixel. }
  TTestMarkerCache = Class(TSmoothMarkerCache)
  Protected
    Function NewMarkerImage: TLazIntfImage; Override;
    Function NewMarkerBitmap(Image: TLazIntfImage): TBitmap; Override;
  Public
    Reference: TLazIntfImage;
    ReferenceMatched: Boolean;
  End;

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

{ A 32-bit image with alpha, described here so the test needs no widgetset query. }
Function NewImage: TLazIntfImage;
Var
  Description: TRawImageDescription;
Begin
  Result := TLazIntfImage.Create(0, 0);
  Description.Init_BPP32_B8G8R8A8_BIO_TTB(0, 0);
  Result.DataDescription := Description;
End;

Function SamePixels(A, B: TLazIntfImage): Boolean;
Var
  X, Y: Integer;
  PA, PB: TFPColor;
Begin
  Result := (A.Width = B.Width) And (A.Height = B.Height) And (A.Width > 0) And (A.Height > 0);
  If Not Result Then
    Exit;
  For Y := 0 To A.Height - 1 Do
    For X := 0 To A.Width - 1 Do
      Begin
        PA := A.Colors[X, Y];
        PB := B.Colors[X, Y];
        If (PA.Red <> PB.Red) Or (PA.Green <> PB.Green) Or (PA.Blue <> PB.Blue) Or (PA.Alpha <> PB.Alpha) Then
          Begin
            WriteLn('     first difference at ', X, ',', Y);
            Exit(False);
          End;
      End;
End;

Function TTestMarkerCache.NewMarkerImage: TLazIntfImage;
Begin
  Result := NewImage;
End;

Function TTestMarkerCache.NewMarkerBitmap(Image: TLazIntfImage): TBitmap;
Begin
  If Assigned(Reference) Then
    ReferenceMatched := SamePixels(Image, Reference);
  Result := TBitmap.Create;
End;

{ True when the image holds both pixels equal to Solid and pixels that are not, so a match is not vacuous. }
Function HasSolidAndOther(Image: TLazIntfImage; Const Solid: TFPColor): Boolean;
Var
  X, Y: Integer;
  Pixel: TFPColor;
  SeenSolid, SeenOther: Boolean;
Begin
  SeenSolid := False;
  SeenOther := False;
  For Y := 0 To Image.Height - 1 Do
    For X := 0 To Image.Width - 1 Do
      Begin
        Pixel := Image.Colors[X, Y];
        If (Pixel.Red = Solid.Red) And (Pixel.Green = Solid.Green) And (Pixel.Blue = Solid.Blue) And
          (Pixel.Alpha = Solid.Alpha) Then
          SeenSolid := True
        Else
          SeenOther := True;
      End;
  Result := SeenSolid And SeenOther;
End;

{ The output markers had before they used straight alpha, with no strokes underneath: each fringe pixel mixes the
  edge colour into Background by its coverage and is opaque, and uncovered pixels are clear. Same geometry and 8x8
  grid as RenderCoverageCircle, every pixel supersampled. }
Function RenderPreBlended(Image: TLazIntfImage; CentreX, CentreY, OuterRadius, InnerRadius: Single;
  Edge, Background: TColor; Scale: Single; Out Dest: TRect): Boolean;

  Function EdgeCoverage(EdgeRadius, Dist: Single): Single;
  Begin
    Result := (EdgeRadius + 0.25 - Dist) / 0.5;
    If Result < 0 Then
      Result := 0
    Else If Result > 1 Then
      Result := 1;
  End;

  Function Average(Sum: Single): Word;
  Begin
    Sum := Sum / 64;
    If Sum <= 0 Then
      Result := 0
    Else If Sum >= 65535 Then
      Result := 65535
    Else
      Result := Round(Sum);
  End;

  Function Mix(Back, Over: Word; Coverage: Single): Single;
  Begin
    Result := Back + (Single(Over) - Single(Back)) * Coverage;
  End;

Var
  Left, Top, PhysW, PhysH, X, Y, SampleX, SampleY: Integer;
  PhysCentreX, PhysCentreY, PhysOuter, PhysInner, Dx, Dy, Dist, Coverage, CoverageSum, SumR, SumG, SumB: Single;
  EdgeColor, BackColor, Pixel: TFPColor;
Begin
  Left := Floor(CentreX - OuterRadius - 0.25);
  Top := Floor(CentreY - OuterRadius - 0.25);
  Dest := Rect(Left, Top, Ceil(CentreX + OuterRadius + 0.25), Ceil(CentreY + OuterRadius + 0.25));
  PhysW := Max(2, Ceil((Dest.Right - Left) * Scale - 1E-6));
  PhysH := Max(2, Ceil((Dest.Bottom - Top) * Scale - 1E-6));
  PhysCentreX := (CentreX - Left) * Scale;
  PhysCentreY := (CentreY - Top) * Scale;
  PhysOuter := OuterRadius * Scale;
  If InnerRadius < 0 Then
    PhysInner := -1
  Else
    PhysInner := InnerRadius * Scale;
  EdgeColor := TColorToFPColor(ColorToRGB(Edge));
  BackColor := TColorToFPColor(ColorToRGB(Background));
  Image.SetSize(PhysW, PhysH);
  For Y := 0 To PhysH - 1 Do
    For X := 0 To PhysW - 1 Do
      Begin
        CoverageSum := 0;
        SumR := 0;
        SumG := 0;
        SumB := 0;
        For SampleY := 0 To 7 Do
          For SampleX := 0 To 7 Do
            Begin
              Dx := X + (SampleX + 0.5) / 8 - PhysCentreX;
              Dy := Y + (SampleY + 0.5) / 8 - PhysCentreY;
              Dist := Sqrt(Dx * Dx + Dy * Dy);
              Coverage := EdgeCoverage(PhysOuter, Dist);
              If PhysInner >= 0 Then
                Begin
                  Coverage := Coverage - EdgeCoverage(PhysInner, Dist);
                  If Coverage < 0 Then
                    Coverage := 0;
                End;
              CoverageSum := CoverageSum + Coverage;
              SumR := SumR + Mix(BackColor.Red, EdgeColor.Red, Coverage);
              SumG := SumG + Mix(BackColor.Green, EdgeColor.Green, Coverage);
              SumB := SumB + Mix(BackColor.Blue, EdgeColor.Blue, Coverage);
            End;
        If CoverageSum <= 0 Then
          Pixel := ClearPixel
        Else
          Begin
            Pixel.Red := Average(SumR);
            Pixel.Green := Average(SumG);
            Pixel.Blue := Average(SumB);
            Pixel.Alpha := 65535;
          End;
        Image.Colors[X, Y] := Pixel;
      End;
  Result := True;
End;

{ Straight-alpha OVER on 8-bit channels, as the widgetset composites a marker. }
Function Over(Fore, Back, Alpha: Integer): Integer;
Begin
  Result := Round((Fore * Alpha + Back * (255 - Alpha)) / 255);
End;

{ Composites the straight-alpha marker over Background and compares every channel with the pre-blended output. }
Procedure CheckComposite(Const Title: String; CentreX, CentreY, OuterRadius, InnerRadius, Scale: Single;
  Edge, Background: TColor);
Var
  Straight, Blended: TLazIntfImage;
  StraightDest, BlendedDest: TRect;
  StraightDrawn, BlendedDrawn, EdgeOnly: Boolean;
  X, Y, Alpha, Worst, Partial, BackR, BackG, BackB, WantR, WantG, WantB: Integer;
  S, B, EdgeColor: TFPColor;
  BackRGB: TColor;
Begin
  BackRGB := ColorToRGB(Background);
  BackR := Red(BackRGB);
  BackG := Green(BackRGB);
  BackB := Blue(BackRGB);
  EdgeColor := TColorToFPColor(ColorToRGB(Edge));
  Straight := NewImage;
  Blended := NewImage;
  Try
    StraightDrawn := RenderCoverageCircle(Straight, CentreX, CentreY, OuterRadius, InnerRadius, Edge, Scale,
      StraightDest);
    BlendedDrawn := RenderPreBlended(Blended, CentreX, CentreY, OuterRadius, InnerRadius, Edge, Background, Scale,
      BlendedDest);
    Check(Title + ' renders both ways', StraightDrawn And BlendedDrawn);
    Check(Title + ' covers the same rectangle', EqualRect(StraightDest, BlendedDest) And
      (Straight.Width = Blended.Width) And (Straight.Height = Blended.Height));
    If (Straight.Width <> Blended.Width) Or (Straight.Height <> Blended.Height) Then
      Exit;
    Worst := 0;
    Partial := 0;
    EdgeOnly := True;
    For Y := 0 To Straight.Height - 1 Do
      For X := 0 To Straight.Width - 1 Do
        Begin
          S := Straight.Colors[X, Y];
          B := Blended.Colors[X, Y];
          Alpha := S.Alpha Shr 8;
          If (Alpha > 0) And (Alpha < 255) Then
            Inc(Partial);
          If (Alpha > 0) And ((S.Red <> EdgeColor.Red) Or (S.Green <> EdgeColor.Green) Or (S.Blue <> EdgeColor.Blue)) Then
            EdgeOnly := False;
          If B.Alpha = 0 Then
            Begin
              WantR := BackR;
              WantG := BackG;
              WantB := BackB;
            End
          Else
            Begin
              WantR := B.Red Shr 8;
              WantG := B.Green Shr 8;
              WantB := B.Blue Shr 8;
            End;
          Worst := Max(Worst, Abs(Over(S.Red Shr 8, BackR, Alpha) - WantR));
          Worst := Max(Worst, Abs(Over(S.Green Shr 8, BackG, Alpha) - WantG));
          Worst := Max(Worst, Abs(Over(S.Blue Shr 8, BackB, Alpha) - WantB));
        End;
    Check(Title + ' has partially covered pixels', Partial > 0);
    Check(Title + ' writes only the edge colour', EdgeOnly);
    Check(Title + ' composites within 1 of the pre-blended output (worst ' + IntToStr(Worst) + ')', Worst <= 1);
  Finally
    Straight.Free;
    Blended.Free;
  End;
End;

Procedure CheckCircle(Const Title: String; CentreX, CentreY, OuterRadius, InnerRadius, Scale: Single);
Var
  Fast, Full: TLazIntfImage;
  FastDest, FullDest: TRect;
  FastDrawn, FullDrawn: Boolean;
  Edge: TFPColor;
Begin
  Fast := NewImage;
  Full := NewImage;
  Try
    FastDrawn := RenderCoverageCircle(Fast, CentreX, CentreY, OuterRadius, InnerRadius, RGBToColor(230, 90, 30), Scale,
      FastDest, True);
    FullDrawn := RenderCoverageCircle(Full, CentreX, CentreY, OuterRadius, InnerRadius, RGBToColor(230, 90, 30), Scale,
      FullDest, False);
    Check(Title + ' renders both ways', FastDrawn And FullDrawn);
    Check(Title + ' covers the same rectangle', EqualRect(FastDest, FullDest));
    Check(Title + ' matches full supersampling pixel for pixel', SamePixels(Fast, Full));
    Edge := TColorToFPColor(RGBToColor(230, 90, 30));
    Edge.Alpha := 65535;
    Check(Title + ' has solid edge pixels and others', HasSolidAndOther(Full, Edge));
  Finally
    Fast.Free;
    Full.Free;
  End;
End;

Procedure CheckRoundRect(Const Title: String; LogicalW, LogicalH: Integer; Radius, Scale: Single);
Var
  Fast, Full: TLazIntfImage;
  FastDrawn, FullDrawn: Boolean;
  Fill: TFPColor;
Begin
  Fast := NewImage;
  Full := NewImage;
  Try
    FastDrawn := RenderSmoothRoundRect(Fast, LogicalW, LogicalH, Radius, RGBToColor(220, 235, 250),
      RGBToColor(70, 110, 160), RGBToColor(255, 255, 255), Scale, True);
    FullDrawn := RenderSmoothRoundRect(Full, LogicalW, LogicalH, Radius, RGBToColor(220, 235, 250),
      RGBToColor(70, 110, 160), RGBToColor(255, 255, 255), Scale, False);
    Check(Title + ' renders both ways', FastDrawn And FullDrawn);
    Check(Title + ' matches full supersampling pixel for pixel', SamePixels(Fast, Full));
    Fill := TColorToFPColor(RGBToColor(220, 235, 250));
    Fill.Alpha := 65535;
    Check(Title + ' has solid fill pixels and others', HasSolidAndOther(Full, Fill));
  Finally
    Fast.Free;
    Full.Free;
  End;
End;

Procedure CheckMarkerCache;
Var
  Cache: TTestMarkerCache;
  First, Again: TBitmap;
  FirstDest, AgainDest, Expected: TRect;
  I: Integer;
Begin
  Cache := TTestMarkerCache.Create(8);
  Try
    Check('cache capacity is the bound it was given', Cache.Capacity = 8);
    Cache.Prepare(1, [clWindowText]);
    { 10.3 and 10.6 quantise to 10.25 and 10.5; the cached image must equal a direct render there. }
    Cache.Reference := NewImage;
    RenderCoverageCircle(Cache.Reference, 10.25, 10.5, 5.5, -1, clRed, 1, Expected);
    Cache.ReferenceMatched := False;
    First := Cache.Marker(10.3, 10.6, 5.5, -1, clRed, 1, FirstDest);
    Check('cache renders a marker', Assigned(First) And (Cache.Count = 1));
    Check('cached image matches a direct render at the quantised centre', Cache.ReferenceMatched);
    Check('cached rectangle matches a direct render at the quantised centre', EqualRect(FirstDest, Expected));
    FreeAndNil(Cache.Reference);
    Again := Cache.Marker(10.26, 10.55, 5.5, -1, clRed, 1, AgainDest);
    Check('the same key returns the same bitmap', (Again = First) And (Cache.Count = 1) And
      EqualRect(AgainDest, FirstDest));
    Again := Cache.Marker(40.3, 30.6, 5.5, -1, clRed, 1, AgainDest);
    Expected := FirstDest;
    OffsetRect(Expected, 30, 20);
    Check('a whole-pixel move reuses the bitmap and shifts its rectangle', (Again = First) And
      EqualRect(AgainDest, Expected));
    Check('a scale below 1 is clamped to the same key', Cache.Marker(10.3, 10.6, 5.5, -1, clRed, 0.5, AgainDest) = First);
    Check('a different colour misses', Cache.Marker(10.3, 10.6, 5.5, -1, clBlue, 1, AgainDest) <> First);
    Check('a different radius misses', Cache.Marker(10.3, 10.6, 6, -1, clRed, 1, AgainDest) <> First);
    Check('a ring misses the disk', Cache.Marker(10.3, 10.6, 5.5, 4, clRed, 1, AgainDest) <> First);
    Check('a different fraction misses', Cache.Marker(10.5, 10.6, 5.5, -1, clRed, 1, AgainDest) <> First);
    Check('a different scale misses', Cache.Marker(10.3, 10.6, 5.5, -1, clRed, 2, AgainDest) <> First);
    Check('each miss adds one entry', Cache.Count = 6);
    For I := 1 To 40 Do
      Cache.Marker(10, 10, 5.5, -1, RGBToColor(I, 0, 0), 1, AgainDest);
    Check('the cache stays within its bound', Cache.Count = Cache.Capacity);
    Cache.Prepare(1, [clWindowText]);
    Check('an unchanged scale and theme keep the entries', Cache.Count = Cache.Capacity);
    Cache.Prepare(2, [clWindowText]);
    Check('a new scale empties the cache', Cache.Count = 0);
    Cache.Marker(10, 10, 5.5, -1, clRed, 2, AgainDest);
    Cache.Prepare(2, [RGBToColor(1, 2, 3)]);
    Check('a new theme colour empties the cache', Cache.Count = 0);
  Finally
    FreeAndNil(Cache.Reference);
    Cache.Free;
  End;
End;

{ Informational only: the time for a run of history-sized rings at 2x, with and without the skip. }
Procedure ReportTiming;
Var
  Image: TLazIntfImage;
  Dest: TRect;
  Started, FastMs, FullMs: QWord;
  I: Integer;
Begin
  Image := NewImage;
  Try
    Started := GetTickCount64;
    For I := 1 To TimingRepeats Do
      RenderCoverageCircle(Image, 10.3, 10.6, 5.5, 4, clRed, 2, Dest, True);
    FastMs := GetTickCount64 - Started;
    Started := GetTickCount64;
    For I := 1 To TimingRepeats Do
      RenderCoverageCircle(Image, 10.3, 10.6, 5.5, 4, clRed, 2, Dest, False);
    FullMs := GetTickCount64 - Started;
  Finally
    Image.Free;
  End;
  WriteLn('info ', TimingRepeats, ' rings at 2x: ', FastMs, ' ms with the skip, ', FullMs, ' ms without');
End;

Const
  LightRow = $00F5FAFA;
  DarkRow = $00241E1E;

Var
  ScaleIndex: Integer;
  ScaleText: String;
Begin
  FailCount := 0;
  For ScaleIndex := 0 To High(Scales) Do
    Begin
      ScaleText := ' at scale ' + FloatToStr(Scales[ScaleIndex]);
      CheckCircle('disk' + ScaleText, 10.3, 10.6, 5.5, -1, Scales[ScaleIndex]);
      CheckCircle('large disk' + ScaleText, 30, 30, 18, -1, Scales[ScaleIndex]);
      CheckCircle('ring' + ScaleText, 10.3, 10.6, 5.5, 4, Scales[ScaleIndex]);
      CheckCircle('thick ring' + ScaleText, 30.5, 30.25, 18, 9, Scales[ScaleIndex]);
      CheckRoundRect('round rectangle' + ScaleText, 60, 18, 4, Scales[ScaleIndex]);
      CheckRoundRect('large round rectangle' + ScaleText, 120, 50, 12, Scales[ScaleIndex]);
      CheckComposite('straight-alpha disk on a light row' + ScaleText, 10.3, 10.6, 5.5, -1, Scales[ScaleIndex],
        RGBToColor(230, 90, 30), LightRow);
      CheckComposite('straight-alpha disk on a dark row' + ScaleText, 10.3, 10.6, 5.5, -1, Scales[ScaleIndex],
        RGBToColor(33, 150, 243), DarkRow);
      CheckComposite('straight-alpha ring on a light row' + ScaleText, 10, 10, 7, 5, Scales[ScaleIndex], clBlack,
        LightRow);
      CheckComposite('straight-alpha ring on a dark row' + ScaleText, 10.3, 10.6, 7, 5, Scales[ScaleIndex],
        RGBToColor(240, 240, 240), DarkRow);
    End;
  CheckMarkerCache;
  ReportTiming;
  If FailCount > 0 Then
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
  WriteLn('All checks passed');
End.