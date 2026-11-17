Program CanvasSmoothShapesTest;

{ Checks that the smooth-shape rasterisers skip uniform pixels without changing one (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, SysUtils, Types, Graphics, GraphType, fpimage, IntfGraphics, CanvasUtils;

Const
  Scales: Array[0..1] Of Single = (1, 2);
  TimingRepeats = 200;

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

{ A lane line under the shape, so fringe pixels blend against two colours. }
Function LaneStroke(CentreX, CentreY: Single): TSmoothStrokeArray;
Begin
  SetLength(Result, 1);
  Result[0].X1 := CentreX;
  Result[0].Y1 := CentreY - 20;
  Result[0].X2 := CentreX + 0.4;
  Result[0].Y2 := CentreY + 20;
  Result[0].HalfWidth := 1;
  Result[0].Color := RGBToColor(40, 120, 220);
End;

Procedure CheckCircle(Const Title: String; CentreX, CentreY, OuterRadius, InnerRadius, Scale: Single);
Var
  Fast, Full: TLazIntfImage;
  FastDest, FullDest: TRect;
  FastDrawn, FullDrawn: Boolean;
  Strokes: TSmoothStrokeArray;
  Edge: TFPColor;
Begin
  Strokes := LaneStroke(CentreX, CentreY);
  Fast := NewImage;
  Full := NewImage;
  Try
    FastDrawn := RenderCoverageCircle(Fast, CentreX, CentreY, OuterRadius, InnerRadius, RGBToColor(230, 90, 30),
      RGBToColor(250, 250, 245), Strokes, Scale, FastDest, True);
    FullDrawn := RenderCoverageCircle(Full, CentreX, CentreY, OuterRadius, InnerRadius, RGBToColor(230, 90, 30),
      RGBToColor(250, 250, 245), Strokes, Scale, FullDest, False);
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

{ Informational only: the time for a run of history-sized rings at 2x, with and without the skip. }
Procedure ReportTiming;
Var
  Image: TLazIntfImage;
  Dest: TRect;
  Strokes: TSmoothStrokeArray;
  Started, FastMs, FullMs: QWord;
  I: Integer;
Begin
  Strokes := LaneStroke(10.3, 10.6);
  Image := NewImage;
  Try
    Started := GetTickCount64;
    For I := 1 To TimingRepeats Do
      RenderCoverageCircle(Image, 10.3, 10.6, 5.5, 4, clRed, clWhite, Strokes, 2, Dest, True);
    FastMs := GetTickCount64 - Started;
    Started := GetTickCount64;
    For I := 1 To TimingRepeats Do
      RenderCoverageCircle(Image, 10.3, 10.6, 5.5, 4, clRed, clWhite, Strokes, 2, Dest, False);
    FullMs := GetTickCount64 - Started;
  Finally
    Image.Free;
  End;
  WriteLn('info ', TimingRepeats, ' rings at 2x: ', FastMs, ' ms with the skip, ', FullMs, ' ms without');
End;

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
    End;
  ReportTiming;
  If FailCount > 0 Then
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
  WriteLn('All checks passed');
End.
