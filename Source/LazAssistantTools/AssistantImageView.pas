Unit AssistantImageView;

{ Sizable view of a stored conversation image (c) 2026 Michell Computing.

  Opens fitted to the current monitor. An image larger than that monitor is
  halved until it fits. Zoom lives on the picture popup. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, ActnList, Menus,
  AssistantTrace;

Type
  TAssistantImageView = Class(TForm)
    ActionList: TActionList;
    CloseAction: TAction;
    ZoomOutAction: TAction;
    ZoomInAction: TAction;
    ZoomActualAction: TAction;
    ImageScroll: TScrollBox;
    ImagePaint: TPaintBox;
    ZoomPopup: TPopupMenu;
    ZoomOutItem: TMenuItem;
    ZoomInItem: TMenuItem;
    ZoomActualItem: TMenuItem;
    Procedure CloseActionExecute(Sender: TObject);
    Procedure FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure FormResize(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure ImagePaintPaint(Sender: TObject);
    Procedure ZoomOutActionExecute(Sender: TObject);
    Procedure ZoomInActionExecute(Sender: TObject);
    Procedure ZoomActualActionExecute(Sender: TObject);
    Procedure ZoomPopupPopup(Sender: TObject);
  Private
    Picture: TPortableNetworkGraphic;
    FMissingCaption: String;
    FZoom: Double;
    FDisplayWidth: Integer;
    FDisplayHeight: Integer;
    FDrawLeft: Integer;
    FDrawTop: Integer;
    FPlacing: Boolean;
    Procedure ReleasePicture;
    Procedure ApplyBackdrop;
    Function ActualDisplaySize(Out ActualWidth, ActualHeight: Integer): Boolean;
    Function PreviewMonitorWorkArea(Out Work: TRect): Boolean;
    Procedure SetZoom(NewZoom: Double);
    Procedure PlaceDisplayedImage;
    Procedure FitWindowToImage;
    Procedure UpdateZoomActions;
  Public
    Destructor Destroy; Override;
    Procedure LoadImage(Const ProjectRoot: String; Const Ref: TTraceImageRef);
  End;

/// File name offered by Save Image. Never a path.
Function AttachmentSaveName(Const Name, Id: String): String;
/// Place a PNG of the stored display image on the clipboard. No pixel bytes are logged.
Function CopyStoredImagePng(Const ProjectRoot: String; Const Ref: TTraceImageRef; Out ErrorText: String): Boolean;
/// Write the stored display bytes to TargetPath. Refuses a missing or linked source.
Function WriteStoredImageFile(Const ProjectRoot, RelativePath, TargetPath: String; Out ErrorText: String): Boolean;
Procedure ShowAssistantImage(Const ProjectRoot: String; Const Ref: TTraceImageRef);
Procedure CopyAssistantImage(Const ProjectRoot: String; Const Ref: TTraceImageRef);
Procedure SaveAssistantImage(Const ProjectRoot: String; Const Ref: TTraceImageRef);

Implementation

{$R *.lfm}

Uses
  Math, LCLType, Clipbrd, FPImage, FPWritePNG, AssistantImages;

Const
  PreviewBackdrop = TColor($404040);
  PreviewMinZoom = 1.0 / 64;
  PreviewMaxZoom = 16;

Procedure ForceOpaqueIfBlank(Img: TFPCustomImage);
Var
  X, Y: Integer;
  Color: TFPColor;
Begin
  If (Not Assigned(Img)) Or (Img.Width < 1) Or (Img.Height < 1) Then Exit;
  For Y := 0 To Img.Height - 1 Do
    For X := 0 To Img.Width - 1 Do
      If Img.Colors[X, Y].Alpha <> 0 Then Exit;
  For Y := 0 To Img.Height - 1 Do
    For X := 0 To Img.Width - 1 Do
      Begin
        Color := Img.Colors[X, Y];
        Color.Alpha := 65535;
        Img.Colors[X, Y] := Color;
      End;
End;

Function PixelsPerInchOf(Control: TControl): Integer;
Begin
  Result := 96;
  If Not Assigned(Control) Then Exit;
  Result := Control.Font.PixelsPerInch;
  If Result < 1 Then Result := Screen.PixelsPerInch;
  If Result < 1 Then Result := 96;
End;

Function AttachmentSaveName(Const Name, Id: String): String;
Begin
  Result := Trim(Name);
  Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
  Result := Trim(ExtractFileName(Result));
  If Result = '' Then Result := Trim(Id);
  If Result = '' Then Result := 'Image.png';
  If ExtractFileExt(Result) = '' Then Result := Result + '.png';
End;

Function LoadDisplayImage(Const ProjectRoot: String; Const Ref: TTraceImageRef; Out Img: TFPMemoryImage;
  Out ErrorText: String): Boolean;
Begin
  Img := Nil;
  ErrorText := '';
  Result := False;
  If Ref.Missing Or (Trim(ProjectRoot) = '') Or (Trim(Ref.DisplayPath) = '') Then
    Begin
      ErrorText := 'The image is unavailable.';
      Exit;
    End;
  Result := LoadStoredAssistantImage(ProjectRoot, Ref.DisplayPath, Img, ErrorText) And Assigned(Img) And
    (Img.Width > 0) And (Img.Height > 0);
  If Not Result Then
    Begin
      FreeAndNil(Img);
      If ErrorText = '' Then ErrorText := 'The image is unavailable.';
    End
  Else
    ForceOpaqueIfBlank(Img);
End;

Function GraphicFromImage(Img: TFPCustomImage): TPortableNetworkGraphic;
Var
  Stream: TMemoryStream;
  Writer: TFPWriterPNG;
Begin
  Result := Nil;
  If Not Assigned(Img) Then Exit;
  Stream := TMemoryStream.Create;
  Writer := TFPWriterPNG.Create;
  Try
    Img.SaveToStream(Stream, Writer);
    Stream.Position := 0;
    Result := TPortableNetworkGraphic.Create;
    Result.LoadFromStream(Stream);
  Finally
    Writer.Free;
    Stream.Free;
  End;
End;

Function CopyStoredImagePng(Const ProjectRoot: String; Const Ref: TTraceImageRef; Out ErrorText: String): Boolean;
Var
  Img: TFPMemoryImage;
  Stream: TMemoryStream;
  Writer: TFPWriterPNG;
Begin
  Result := False;
  ErrorText := '';
  Img := Nil;
  If Not LoadDisplayImage(ProjectRoot, Ref, Img, ErrorText) Then Exit;
  Stream := TMemoryStream.Create;
  Writer := TFPWriterPNG.Create;
  Try
    Img.SaveToStream(Stream, Writer);
    If Stream.Size < 8 Then
      Begin
        ErrorText := 'The image is unavailable.';
        Exit;
      End;
    Stream.Position := 0;
    Clipboard.Open;
    Try
      Clipboard.Clear;
      Result := Clipboard.AddFormat(RegisterClipboardFormat('image/png'), Stream);
    Finally
      Clipboard.Close;
    End;
    If Not Result Then ErrorText := 'The image could not be copied.';
  Finally
    Writer.Free;
    Stream.Free;
    Img.Free;
  End;
End;

Function WriteStoredImageFile(Const ProjectRoot, RelativePath, TargetPath: String; Out ErrorText: String): Boolean;
Var
  Data: TBytes;
  Stream: TFileStream;
Begin
  Result := False;
  ErrorText := '';
  Data := Nil;
  SetLength(Data, 0);
  If Trim(TargetPath) = '' Then
    Begin
      ErrorText := 'The image could not be saved.';
      Exit;
    End;
  If Not ReadStoredAssistantImage(ProjectRoot, RelativePath, Data, ErrorText) Or (Length(Data) < 1) Then
    Begin
      SetLength(Data, 0);
      If ErrorText = '' Then ErrorText := 'The image is unavailable.';
      Exit;
    End;
  Stream := Nil;
  Try
    Try
      Stream := TFileStream.Create(TargetPath, fmCreate);
      Stream.WriteBuffer(Data[0], Length(Data));
      Result := True;
    Except
      ErrorText := 'The image could not be saved.';
      Result := False;
    End;
  Finally
    Stream.Free;
    SetLength(Data, 0);
  End;
End;

Procedure ShowAssistantImage(Const ProjectRoot: String; Const Ref: TTraceImageRef);
Var
  View: TAssistantImageView;
Begin
  View := TAssistantImageView.Create(Nil);
  Try
    View.LoadImage(ProjectRoot, Ref);
    View.ShowModal;
  Finally
    View.Free;
  End;
End;

Procedure CopyAssistantImage(Const ProjectRoot: String; Const Ref: TTraceImageRef);
Var
  ErrorText: String;
Begin
  If CopyStoredImagePng(ProjectRoot, Ref, ErrorText) Then Exit;
  If ErrorText = '' Then ErrorText := 'The image is unavailable.';
  MessageDlg(ErrorText, mtInformation, [mbOK], 0);
End;

Procedure SaveAssistantImage(Const ProjectRoot: String; Const Ref: TTraceImageRef);
Var
  Dlg: TSaveDialog;
  ErrorText, Ext: String;
Begin
  If Ref.Missing Or (Trim(Ref.DisplayPath) = '') Then
    Begin
      MessageDlg('The image is unavailable.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Dlg := TSaveDialog.Create(Nil);
  Try
    Dlg.Title := 'Save Image';
    Dlg.Filter := 'All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt, ofPathMustExist];
    Dlg.FileName := AttachmentSaveName(Ref.Name, Ref.Id);
    Ext := ExtractFileExt(Dlg.FileName);
    If Ext <> '' Then Dlg.DefaultExt := Copy(Ext, 2, MaxInt);
    If DirectoryExists(ProjectRoot) Then Dlg.InitialDir := ProjectRoot;
    If Not Dlg.Execute Then Exit;
    If Not WriteStoredImageFile(ProjectRoot, Ref.DisplayPath, Dlg.FileName, ErrorText) Then
      Begin
        If ErrorText = '' Then ErrorText := 'The image could not be saved.';
        MessageDlg(ErrorText, mtInformation, [mbOK], 0);
      End;
  Finally
    Dlg.Free;
  End;
End;

Procedure TAssistantImageView.ReleasePicture;
Begin
  FreeAndNil(Picture);
End;

Procedure TAssistantImageView.ApplyBackdrop;
Begin
  Color := PreviewBackdrop;
  If Assigned(ImageScroll) Then
    Begin
      ImageScroll.ParentColor := False;
      ImageScroll.ParentBackground := False;
      ImageScroll.Color := PreviewBackdrop;
    End;
End;

Function TAssistantImageView.ActualDisplaySize(Out ActualWidth, ActualHeight: Integer): Boolean;
Var
  PPI: Integer;
Begin
  ActualWidth := 0;
  ActualHeight := 0;
  Result := Assigned(Picture) And (Picture.Width > 0) And (Picture.Height > 0);
  If Not Result Then Exit;
  PPI := PixelsPerInchOf(Self);
  ActualWidth := Round(Int64(Picture.Width) * PPI / 96);
  ActualHeight := Round(Int64(Picture.Height) * PPI / 96);
  If ActualWidth < 1 Then ActualWidth := 1;
  If ActualHeight < 1 Then ActualHeight := 1;
End;

Function TAssistantImageView.PreviewMonitorWorkArea(Out Work: TRect): Boolean;
Var
  Current: TMonitor;
Begin
  Work := Rect(0, 0, 800, 600);
  Result := False;
  Current := Nil;
  If Assigned(Screen) And (Screen.MonitorCount > 0) Then
    Begin
      Current := Screen.MonitorFromPoint(Mouse.CursorPos, mdNearest);
      If Not Assigned(Current) Then Current := Screen.PrimaryMonitor;
    End;
  If Not Assigned(Current) Then Exit;
  Work := Current.WorkareaRect;
  Result := (Work.Right > Work.Left) And (Work.Bottom > Work.Top);
End;

Procedure TAssistantImageView.SetZoom(NewZoom: Double);
Var
  ActualW, ActualH: Integer;
Begin
  If NewZoom < PreviewMinZoom Then NewZoom := PreviewMinZoom;
  If NewZoom > PreviewMaxZoom Then NewZoom := PreviewMaxZoom;
  FZoom := NewZoom;
  If Not ActualDisplaySize(ActualW, ActualH) Then Exit;
  FDisplayWidth := Max(1, Round(ActualW * FZoom));
  FDisplayHeight := Max(1, Round(ActualH * FZoom));
  PlaceDisplayedImage;
  UpdateZoomActions;
End;

Procedure TAssistantImageView.PlaceDisplayedImage;
Var
  ViewW, ViewH, BoxW, BoxH: Integer;
Begin
  If Not Assigned(ImageScroll) Or Not Assigned(ImagePaint) Then Exit;
  ImageScroll.AutoScroll := False;
  ViewW := ImageScroll.ClientWidth;
  ViewH := ImageScroll.ClientHeight;
  If ViewW < 1 Then ViewW := 1;
  If ViewH < 1 Then ViewH := 1;
  If (FDisplayWidth < 1) Or (FDisplayHeight < 1) Then
    Begin
      FDrawLeft := 8;
      FDrawTop := 8;
      BoxW := ViewW;
      BoxH := ViewH;
    End
  Else If (FDisplayWidth <= ViewW) And (FDisplayHeight <= ViewH) Then
    Begin
      FDrawLeft := (ViewW - FDisplayWidth) Div 2;
      FDrawTop := (ViewH - FDisplayHeight) Div 2;
      BoxW := ViewW;
      BoxH := ViewH;
    End
  Else
    Begin
      ImageScroll.AutoScroll := True;
      If FDisplayWidth < ViewW Then
        Begin
          FDrawLeft := (ViewW - FDisplayWidth) Div 2;
          BoxW := ViewW;
        End
      Else
        Begin
          FDrawLeft := 0;
          BoxW := FDisplayWidth;
        End;
      If FDisplayHeight < ViewH Then
        Begin
          FDrawTop := (ViewH - FDisplayHeight) Div 2;
          BoxH := ViewH;
        End
      Else
        Begin
          FDrawTop := 0;
          BoxH := FDisplayHeight;
        End;
    End;
  ImagePaint.SetBounds(0, 0, BoxW, BoxH);
  ImagePaint.Invalidate;
End;

Procedure TAssistantImageView.FitWindowToImage;
Var
  Work: TRect;
  FrameW, FrameH, MaxW, MaxH, ActualW, ActualH, DispW, DispH, Margin, ClientW, ClientH: Integer;
  Zoom: Double;
Begin
  If Not PreviewMonitorWorkArea(Work) Then Exit;
  HandleNeeded;
  ApplyBackdrop;
  FrameW := Width - ClientWidth;
  FrameH := Height - ClientHeight;
  If FrameW < 0 Then FrameW := 0;
  If FrameH < 0 Then FrameH := 0;
  Margin := 16;
  MaxW := Work.Width - FrameW - Margin * 2;
  MaxH := Work.Height - FrameH - Margin * 2;
  If MaxW < 64 Then MaxW := 64;
  If MaxH < 64 Then MaxH := 64;
  If Not ActualDisplaySize(ActualW, ActualH) Then
    Begin
      FZoom := 1;
      FDisplayWidth := 240;
      FDisplayHeight := MissingImageTileHeight(PixelsPerInchOf(Self));
      If FDisplayHeight < 48 Then FDisplayHeight := 48;
    End
  Else
    Begin
      Zoom := 1;
      DispW := ActualW;
      DispH := ActualH;
      While ((DispW > MaxW) Or (DispH > MaxH)) And (Zoom * 0.5 >= PreviewMinZoom) Do
        Begin
          Zoom := Zoom * 0.5;
          DispW := Max(1, Round(ActualW * Zoom));
          DispH := Max(1, Round(ActualH * Zoom));
        End;
      FZoom := Zoom;
      FDisplayWidth := Max(1, DispW);
      FDisplayHeight := Max(1, DispH);
    End;
  ClientW := FDisplayWidth;
  ClientH := FDisplayHeight;
  If ClientW > MaxW Then ClientW := MaxW;
  If ClientH > MaxH Then ClientH := MaxH;
  If ClientW < 32 Then ClientW := 32;
  If ClientH < 32 Then ClientH := 32;
  FPlacing := True;
  Try
    Position := poDesigned;
    ClientWidth := ClientW;
    ClientHeight := ClientH;
    Left := Work.Left + (Work.Width - Width) Div 2;
    Top := Work.Top + (Work.Height - Height) Div 2;
  Finally
    FPlacing := False;
  End;
  PlaceDisplayedImage;
  UpdateZoomActions;
End;

Procedure TAssistantImageView.UpdateZoomActions;
Var
  HasPicture: Boolean;
Begin
  HasPicture := Assigned(Picture) And (Picture.Width > 0) And (Picture.Height > 0);
  If Assigned(ZoomOutAction) Then ZoomOutAction.Enabled := HasPicture And (FZoom * 0.5 >= PreviewMinZoom - 0.0001);
  If Assigned(ZoomInAction) Then ZoomInAction.Enabled := HasPicture And (FZoom * 2 <= PreviewMaxZoom + 0.0001);
  If Assigned(ZoomActualAction) Then ZoomActualAction.Enabled := HasPicture And (Abs(FZoom - 1) > 0.001);
End;

Destructor TAssistantImageView.Destroy;
Begin
  ReleasePicture;
  Inherited Destroy;
End;

Procedure TAssistantImageView.LoadImage(Const ProjectRoot: String; Const Ref: TTraceImageRef);
Var
  Img: TFPMemoryImage;
  ErrorText: String;
Begin
  ReleasePicture;
  FMissingCaption := '';
  FZoom := 1;
  Caption := AttachmentSaveName(Ref.Name, Ref.Id);
  HandleNeeded;
  ApplyBackdrop;
  If Not LoadDisplayImage(ProjectRoot, Ref, Img, ErrorText) Then
    Begin
      FMissingCaption := MissingImageTileCaption(Ref);
      FitWindowToImage;
      Exit;
    End;
  Try
    Picture := GraphicFromImage(Img);
  Finally
    Img.Free;
  End;
  FitWindowToImage;
End;

Procedure TAssistantImageView.CloseActionExecute(Sender: TObject);
Begin
  ModalResult := mrCancel;
  Close;
End;

Procedure TAssistantImageView.FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  If Key = VK_ESCAPE Then
    Begin
      CloseActionExecute(Sender);
      Key := 0;
    End;
End;

Procedure TAssistantImageView.FormResize(Sender: TObject);
Begin
  If Not FPlacing Then PlaceDisplayedImage;
End;

Procedure TAssistantImageView.FormShow(Sender: TObject);
Begin
  { The title frame is known only after the window is mapped. Fit again so a
    large picture still sits inside the monitor. }
  FitWindowToImage;
End;

Procedure TAssistantImageView.ZoomOutActionExecute(Sender: TObject);
Begin
  SetZoom(FZoom * 0.5);
End;

Procedure TAssistantImageView.ZoomInActionExecute(Sender: TObject);
Begin
  SetZoom(FZoom * 2);
End;

Procedure TAssistantImageView.ZoomActualActionExecute(Sender: TObject);
Begin
  SetZoom(1);
End;

Procedure TAssistantImageView.ZoomPopupPopup(Sender: TObject);
Begin
  UpdateZoomActions;
End;

Procedure TAssistantImageView.ImagePaintPaint(Sender: TObject);
Var
  Dest: TRect;
Begin
  ImagePaint.Canvas.Brush.Style := bsSolid;
  ImagePaint.Canvas.Brush.Color := PreviewBackdrop;
  ImagePaint.Canvas.FillRect(ImagePaint.ClientRect);
  If Assigned(Picture) And (FDisplayWidth > 0) And (FDisplayHeight > 0) Then
    Begin
      Dest := Rect(FDrawLeft, FDrawTop, FDrawLeft + FDisplayWidth, FDrawTop + FDisplayHeight);
      ImagePaint.Canvas.StretchDraw(Dest, Picture);
    End
  Else If FMissingCaption <> '' Then
    Begin
      ImagePaint.Canvas.Brush.Style := bsClear;
      ImagePaint.Canvas.Font.Assign(Font);
      ImagePaint.Canvas.Font.Color := clSilver;
      ImagePaint.Canvas.TextOut(FDrawLeft, FDrawTop, FMissingCaption);
    End;
End;

End.
