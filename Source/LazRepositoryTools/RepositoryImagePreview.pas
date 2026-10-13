Unit RepositoryImagePreview;

{ Shared image detection, load limits, and fitted paint for Manage Repository (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, Graphics, Types;

Const
  RepositoryImageUnavailable = 'Image preview unavailable (16 megapixel limit or unsupported image).';

Function FileExtensionIsImage(Const Ext: String): Boolean;
/// False when the stream is empty, undecodable, or over the History-tab size limits.
Function TryLoadRepositoryImage(Stream: TStream; Picture: TPicture): Boolean;
/// Window background, then the picture fitted inside Bounds without upscaling past 1:1.
Procedure PaintFittedRepositoryImage(Canvas: TCanvas; Const Bounds: TRect; Picture: TPicture);

Implementation

Uses
  SysUtils, Math, FPImage;

Function NormalizeExt(Const Ext: String): String;
Begin
  Result := LowerCase(Ext);
  If (Result <> '') And (Result[1] <> '.') Then
    Result := '.' + Result;
End;

Function FileExtensionIsImage(Const Ext: String): Boolean;
Var
  E: String;
Begin
  E := NormalizeExt(Ext);
  Result := (E = '.png') Or (E = '.jpg') Or (E = '.jpeg') Or (E = '.gif') Or
    (E = '.bmp') Or (E = '.ico') Or (E = '.xpm') Or (E = '.tif') Or (E = '.tiff') Or
    (E = '.pbm') Or (E = '.pgm') Or (E = '.ppm');
End;

Function TryLoadRepositoryImage(Stream: TStream; Picture: TPicture): Boolean;
Var
  Reader: TFPCustomImageReaderClass;
  Dimensions: TPoint;
Begin
  Result := False;
  If (Stream = Nil) Or (Stream.Size = 0) Or (Not Assigned(Picture)) Then
    Exit;
  Stream.Position := 0;
  Try
    Reader := TFPCustomImage.FindReaderFromStream(Stream);
    If Reader = Nil Then
      Exit;
    Stream.Position := 0;
    Dimensions := Reader.ImageSize(Stream);
    If (Dimensions.X < 1) Or (Dimensions.Y < 1) Or
      (Dimensions.X > 16384) Or (Dimensions.Y > 16384) Or
      (Int64(Dimensions.X) * Dimensions.Y > 16000000) Then
      Exit;
    Stream.Position := 0;
    Picture.LoadFromStream(Stream);
  Except
    Picture.Clear;
    Exit;
  End;
  If (Picture.Width < 1) Or (Picture.Height < 1) Then
    Begin
      Picture.Clear;
      Exit;
    End;
  Result := True;
End;

Procedure PaintFittedRepositoryImage(Canvas: TCanvas; Const Bounds: TRect; Picture: TPicture);
Var
  Dest: TRect;
  BoxW, BoxH, ImgW, ImgH: Integer;
  Scale, ScaleX, ScaleY: Double;
  DrawW, DrawH: Integer;
Begin
  If Not Assigned(Canvas) Then
    Exit;
  Canvas.Brush.Color := clWindow;
  Canvas.FillRect(Bounds);
  If (Not Assigned(Picture)) Or (Picture.Width < 1) Or (Picture.Height < 1) Then
    Exit;
  BoxW := Bounds.Right - Bounds.Left;
  BoxH := Bounds.Bottom - Bounds.Top;
  ImgW := Picture.Width;
  ImgH := Picture.Height;
  If (BoxW < 1) Or (BoxH < 1) Then
    Exit;
  ScaleX := BoxW / ImgW;
  ScaleY := BoxH / ImgH;
  If ScaleX < ScaleY Then
    Scale := ScaleX
  Else
    Scale := ScaleY;
  If Scale > 1 Then
    Scale := 1;
  DrawW := Max(1, Round(ImgW * Scale));
  DrawH := Max(1, Round(ImgH * Scale));
  Dest.Left := Bounds.Left + (BoxW - DrawW) Div 2;
  Dest.Top := Bounds.Top + (BoxH - DrawH) Div 2;
  Dest.Right := Dest.Left + DrawW;
  Dest.Bottom := Dest.Top + DrawH;
  Canvas.StretchDraw(Dest, Picture.Graphic);
End;

End.
