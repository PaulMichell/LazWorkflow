Unit AssistantImageView;

{ Scrollable 1:1 view of a stored conversation image (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, ActnList,
  AssistantTrace;

Type
  TAssistantImageView = Class(TForm)
    ActionList: TActionList;
    CloseAction: TAction;
    ImageScroll: TScrollBox;
    ImagePaint: TPaintBox;
    Procedure CloseActionExecute(Sender: TObject);
    Procedure FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure ImagePaintPaint(Sender: TObject);
  Private
    Picture: TPortableNetworkGraphic;
    FMissingCaption: String;
    Procedure ReleasePicture;
    Procedure ApplyExtent(ImageWidth, ImageHeight: Integer);
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
  LCLType, Clipbrd, FPImage, FPWritePNG, AssistantImages;

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

Function ImageViewExtent(ImageWidth, ImageHeight, PixelsPerInch: Integer; Out DisplayWidth, DisplayHeight: Integer): Boolean;
Var
  NativeW: Integer;
Begin
  DisplayWidth := 0;
  DisplayHeight := 0;
  If PixelsPerInch < 1 Then PixelsPerInch := 96;
  NativeW := Round(Int64(ImageWidth) * PixelsPerInch / 96);
  If NativeW < 1 Then NativeW := 1;
  Result := ScaledImageExtent(ImageWidth, ImageHeight, NativeW, PixelsPerInch, DisplayWidth, DisplayHeight);
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

Procedure TAssistantImageView.ApplyExtent(ImageWidth, ImageHeight: Integer);
Var
  PPI, DisplayW, DisplayH: Integer;
Begin
  PPI := PixelsPerInchOf(Self);
  If Not ImageViewExtent(ImageWidth, ImageHeight, PPI, DisplayW, DisplayH) Then
    Begin
      DisplayW := 240;
      DisplayH := MissingImageTileHeight(PPI);
    End;
  If DisplayW < 1 Then DisplayW := 1;
  If DisplayH < 1 Then DisplayH := 1;
  ImagePaint.SetBounds(0, 0, DisplayW, DisplayH);
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
  Caption := AttachmentSaveName(Ref.Name, Ref.Id);
  HandleNeeded;
  If Not LoadDisplayImage(ProjectRoot, Ref, Img, ErrorText) Then
    Begin
      FMissingCaption := MissingImageTileCaption(Ref);
      ApplyExtent(0, 0);
      ImagePaint.Invalidate;
      Exit;
    End;
  Try
    Picture := GraphicFromImage(Img);
    ApplyExtent(Img.Width, Img.Height);
  Finally
    Img.Free;
  End;
  ImagePaint.Invalidate;
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

Procedure TAssistantImageView.ImagePaintPaint(Sender: TObject);
Var
  Dest: TRect;
Begin
  ImagePaint.Canvas.Brush.Style := bsSolid;
  ImagePaint.Canvas.Brush.Color := clWindow;
  ImagePaint.Canvas.FillRect(ImagePaint.ClientRect);
  If Assigned(Picture) And (Picture.Width > 0) And (Picture.Height > 0) Then
    Begin
      Dest := Rect(0, 0, ImagePaint.Width, ImagePaint.Height);
      ImagePaint.Canvas.StretchDraw(Dest, Picture);
    End
  Else If FMissingCaption <> '' Then
    Begin
      ImagePaint.Canvas.Brush.Style := bsClear;
      ImagePaint.Canvas.Font.Assign(Font);
      ImagePaint.Canvas.Font.Color := clGrayText;
      ImagePaint.Canvas.TextOut(8, 8, FMissingCaption);
    End;
End;

End.
