Unit AssistantComposerSend;

{ Composer layout and send chrome for the project assistant (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The composer, the attachment strip, and the send
  chrome are one job. Reviewed 2026-07-14. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, Controls, Graphics, StdCtrls, ExtCtrls, LCLType, Menus, Clipbrd, ProjectAssistantForm, AssistantPlanRun;

Procedure Seam_InputMemoChange(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_InputRedoClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_InputUndoClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_InputSelectAllClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_InputMemoPaste(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_InputPasteClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_QueueComposerPaste(Form: TProjectAssistantForm);
Procedure Seam_PasteComposer(Form: TProjectAssistantForm);
Function Seam_TryAttachClipboardImage(Form: TProjectAssistantForm; Reader: TClipboard; Out ErrorText: String): Boolean;
Procedure Seam_InputPanelDropFiles(Form: TProjectAssistantForm; Sender: TObject; Const FileNames: Array Of String);
Procedure Seam_AttachImageActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_AttachmentImageDblClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_AttachmentImageMouseDown(Form: TProjectAssistantForm; Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Procedure Seam_PreviewAttachmentActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_SaveAttachmentActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_RemoveAttachmentActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_AttachmentPopupPopup(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_PreviewComposerImage(Form: TProjectAssistantForm; Index: Integer);
Procedure Seam_SaveComposerImage(Form: TProjectAssistantForm; Index: Integer);
Procedure Seam_RemoveComposerImageAt(Form: TProjectAssistantForm; Index: Integer);
Procedure Seam_ClearUnsentComposerImages(Form: TProjectAssistantForm);
Procedure Seam_RefreshComposerImages(Form: TProjectAssistantForm);
Function Seam_ComposerImageIndexUnder(Form: TProjectAssistantForm; Const ScreenPoint: TPoint): Integer;
Procedure Seam_SelectComposerImage(Form: TProjectAssistantForm; Index: Integer);
Procedure Seam_ApplyComposerImageSelection(Form: TProjectAssistantForm);
Procedure Seam_PlaceComposerThumbnails(Form: TProjectAssistantForm);
Function Seam_AttachmentStripHeight(Form: TProjectAssistantForm): Integer;
Function Seam_AttachImageFile(Form: TProjectAssistantForm; Const SourcePath: String; Out ErrorText: String): Boolean;
Function Seam_AttachImageStream(Form: TProjectAssistantForm; Const OriginalName: String; Stream: TStream; Out ErrorText: String): Boolean;
Function Seam_ComposerStoreReady(Form: TProjectAssistantForm; Out Root, StoreDir, ErrorText: String): Boolean;
Function Seam_ComposerAttachAllowed(Form: TProjectAssistantForm; Out Reason: String): Boolean;
Procedure Seam_RefreshAttachAction(Form: TProjectAssistantForm);
Procedure Seam_ApplyInputPanelHeight(Form: TProjectAssistantForm);
Procedure Seam_PromptHostResize(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_ComposerStackResize(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_StatusFooterResize(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_LayoutComposer(Form: TProjectAssistantForm);
Procedure Seam_PlacePromptChildren(Form: TProjectAssistantForm);
Procedure Seam_PlaceComposerChildren(Form: TProjectAssistantForm);
Function Seam_ComposerChromeHeight(Form: TProjectAssistantForm): Integer;
Procedure Seam_InputCopyClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_InputCutClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_InputPopupPopup(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_UpdateInputUndoItems(Form: TProjectAssistantForm);
Procedure Seam_EnsureInputPopup(Form: TProjectAssistantForm);
Procedure Seam_EnsureChatView(Form: TProjectAssistantForm);

Implementation

Uses
  SysUtils, DateUtils, Contnrs, ComCtrls, Dialogs, Forms, LCLIntf,
  WorkflowLog, CanvasUtils, LazFileUtils, FileUtil, fpimage, AssistantImages, AssistantConversation,
  AssistantTrace, AssistantTraceView, AssistantImageView, AssistantCodexClient, AssistantService, AssistantRecovery;

Procedure Seam_InputMemoChange(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    UpdateInputUndoItems;
    End;
End;

Procedure Seam_InputRedoClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Assigned(InputMemo) Then
      Begin
        InputMemo.NoteMenuShortcut;
        InputMemo.Redo;
      End;
    End;
End;

Procedure Seam_InputUndoClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Assigned(InputMemo) Then
      Begin
        InputMemo.NoteMenuShortcut;
        InputMemo.Undo;
      End;
    End;
End;

Procedure Seam_InputSelectAllClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Assigned(InputMemo) Then
      InputMemo.SelectAll;
    End;
End;

Procedure Seam_InputMemoPaste(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    QueueComposerPaste;
    End;
End;

Procedure Seam_InputPasteClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    QueueComposerPaste;
    End;
End;

Procedure Seam_QueueComposerPaste(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    PasteComposer;
    End;
End;

Procedure Seam_PasteComposer(Form: TProjectAssistantForm);
Var
  Reader: TClipboard;
  Attached, SawImage: Boolean;
  PastedText, ImageError, LocalPath: String;
Begin
  With Form Do
    Begin
    If Not Assigned(InputMemo) Or InputMemo.ReadOnly Then Exit;
    { Ctrl+V can arrive both as the memo key and as the popup shortcut. }
    If FPasteComposerBusy Then Exit;
    FPasteComposerBusy := True;
    Reader := OpenClipboardReader;
    Try
      Attached := False;
      ImageError := '';
      SawImage := False;
      Try
        { Picture before text. Some widgetsets only return the mime that was asked for first. }
        SawImage := ClipboardOffersImage(Reader);
        Attached := TryAttachClipboardImage(Reader, ImageError);
      Except
        Attached := False;
        If ImageError = '' Then ImageError := 'The clipboard image could not be read.';
      End;
      PastedText := '';
      { The global Clipboard.AsText is the previous item on Qt after an image copy. }
      If Not (Attached Or SawImage) And Reader.HasFormat(CF_TEXT) Then
        PastedText := Reader.AsText;
      If (Not Attached) And ClipboardTextIsImageFile(PastedText, LocalPath) Then
        Attached := AttachImageFile(LocalPath, ImageError);
      If Attached Then PastedText := '';
      { SelText, not PasteFromClipboard: OnPaste calls back into this method. }
      If PastedText <> '' Then
        InputMemo.SelText := PastedText;
      If (Not Attached) And (ImageError <> '') Then
        RunAssistantModal(ImageError, mtInformation, [mbOK], 0);
    Finally
      Reader.Free;
      FPasteComposerBusy := False;
    End;
    End;
End;

Function Seam_TryAttachClipboardImage(Form: TProjectAssistantForm; Reader: TClipboard; Out ErrorText: String): Boolean;
Var
  Stream: TMemoryStream;
  Reason, MimeName: String;
  Names: TStringList;
  Picture: TPicture;
  I: Integer;
  FormatID: TClipboardFormat;
  SawImage, TriedPng: Boolean;

  Function TryStream(Const FileName: String): Boolean;
  Begin
    With Form Do
    Begin
    Result := False;
    Stream.Position := 0;
    If Stream.Size < 8 Then Exit;
    ErrorText := '';
    Result := AttachImageStream(FileName, Stream, ErrorText);
    If Result Then Exit;
    { GetFormat already returned the bytes. TPicture identifies the file format. }
    Picture := TPicture.Create;
    Try
      Try
        Stream.Position := 0;
        Picture.LoadFromStream(Stream);
      Except
        Exit;
      End;
      If Not GraphicToPngStream(Picture.Graphic, Stream) Then Exit;
      ErrorText := '';
      Result := AttachImageStream('Clipboard.png', Stream, ErrorText);
    Finally
      Picture.Free;
    End;
    End;
  End;

  Function TryFormat(Const Mime: String): Boolean;
  Begin
    With Form Do
    Begin
    Result := False;
    If Mime = '' Then Exit;
    FormatID := Reader.FindFormatID(Mime);
    If FormatID = 0 Then FormatID := RegisterClipboardFormat(Mime);
    If Not ReadClipboardFormat(Reader, FormatID, Stream) Then Exit;
    Result := TryStream(ClipboardImageName(Mime));
    End;
  End;

Begin
  With Form Do
    Begin
    Result := False;
    ErrorText := '';
    If Reader = Nil Then Exit;
    SawImage := ClipboardOffersImage(Reader);
    If Not ComposerAttachAllowed(Reason) Then
      Begin
        If SawImage Then
          Begin
            ErrorText := Reason;
            If ErrorText = '' Then ErrorText := 'Attach is disabled.';
          End;
        Exit;
      End;
    If Not SawImage Then Exit;
    Stream := TMemoryStream.Create;
    Names := TStringList.Create;
    TriedPng := False;
    Try
      FormatID := Reader.FindPictureFormatID;
      If (FormatID <> 0) And ReadClipboardFormat(Reader, FormatID, Stream) Then
        Begin
          MimeName := ClipboardFormatToMimeType(FormatID);
          If TryStream(ClipboardImageName(MimeName)) Then Exit(True);
        End;
      Reader.SupportedFormats(Names);
      For I := 0 To Names.Count - 1 Do
        Begin
          MimeName := Names[I];
          If Not MimeLooksLikeStillImage(MimeName) Then Continue;
          If SameText(MimeName, 'image/png') Or SameText(MimeName, 'image/x-png') Then TriedPng := True;
          If TryFormat(MimeName) Then Exit(True);
        End;
      { Qt serves application/x-qt-image and converts it when image/png is requested. }
      If (Not TriedPng) And TryFormat('image/png') Then Exit(True);
      If ErrorText = '' Then ErrorText := 'The clipboard image could not be read.';
    Finally
      Names.Free;
      Stream.Free;
    End;
    End;
End;

Procedure Seam_InputPanelDropFiles(Form: TProjectAssistantForm; Sender: TObject; Const FileNames: Array Of String);
Var
  I: Integer;
  Reason, ErrorText, LocalName: String;
  SawImage: Boolean;
Begin
  With Form Do
    Begin
    SawImage := False;
    For I := 0 To High(FileNames) Do
      If StillImageExtension(DroppedLocalPath(FileNames[I])) Then SawImage := True;
    If Not SawImage Then Exit;
    If Not ComposerAttachAllowed(Reason) Then
      Begin
        If Reason = '' Then Reason := 'Attach is disabled.';
        RunAssistantModal(Reason, mtInformation, [mbOK], 0);
        Exit;
      End;
    For I := 0 To High(FileNames) Do
      Begin
        LocalName := DroppedLocalPath(FileNames[I]);
        If Not StillImageExtension(LocalName) Then Continue;
        If AttachImageFile(LocalName, ErrorText) Then Continue;
        If ErrorText = '' Then ErrorText := 'That file is not an image.';
        RunAssistantModal(ErrorText, mtInformation, [mbOK], 0);
      End;
    End;
End;

Procedure Seam_AttachImageActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Var
  Dialog: TOpenDialog;
  Reason, ErrorText: String;
  I: Integer;
Begin
  With Form Do
    Begin
    If Not ComposerAttachAllowed(Reason) Then
      Begin
        If Reason = '' Then Reason := 'Attach is disabled.';
        RunAssistantModal(Reason, mtInformation, [mbOK], 0);
        Exit;
      End;
    EnsureConversationStore;
    If ProjectAssistantRoot = '' Then
      Begin
        RunAssistantModal('Open a project before attaching an image.', mtInformation, [mbOK], 0);
        Exit;
      End;
    Dialog := TOpenDialog.Create(Nil);
    Try
      Dialog.Title := 'Attach image';
      Dialog.InitialDir := ProjectAssistantRoot;
      Dialog.Options := [ofAllowMultiSelect, ofFileMustExist, ofEnableSizing];
      Dialog.Filter := 'Images|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.ico;*.xpm;*.tif;*.tiff;*.pbm;*.pgm;*.ppm';
      If Not Dialog.Execute Then Exit;
      For I := 0 To Dialog.Files.Count - 1 Do
        If Not AttachImageFile(Dialog.Files[I], ErrorText) Then
          Begin
            If ErrorText = '' Then ErrorText := 'That file is not an image.';
            RunAssistantModal(ErrorText, mtInformation, [mbOK], 0);
          End;
    Finally
      Dialog.Free;
    End;
    End;
End;

Procedure Seam_AttachmentImageDblClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Sender Is TControl Then
      Begin
        SelectComposerImage(TControl(Sender).Tag);
        PreviewComposerImage(TControl(Sender).Tag);
      End;
    End;
End;

Procedure Seam_AttachmentImageMouseDown(Form: TProjectAssistantForm; Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  With Form Do
    Begin
    If Sender Is TControl Then SelectComposerImage(TControl(Sender).Tag);
    End;
End;

Procedure Seam_PreviewAttachmentActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Sender Is TComponent Then PreviewComposerImage(TComponent(Sender).Tag);
    End;
End;

Procedure Seam_SaveAttachmentActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Sender Is TComponent Then SaveComposerImage(TComponent(Sender).Tag);
    End;
End;

Procedure Seam_RemoveAttachmentActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Sender Is TComponent Then RemoveComposerImageAt(TComponent(Sender).Tag);
    End;
End;

Procedure Seam_AttachmentPopupPopup(Form: TProjectAssistantForm; Sender: TObject);
Var
  Index: Integer;
  Refs: TAssistantImageRefArray;
  HasImage: Boolean;
Begin
  With Form Do
    Begin
    Index := ComposerImageIndexUnder(Mouse.CursorPos);
    ParseAssistantImageRefs(FComposerImagesJson, Refs);
    HasImage := (Index >= 0) And (Index <= High(Refs));
    If HasImage Then SelectComposerImage(Index);
    If Assigned(RemoveAttachmentAction) Then
      Begin
        RemoveAttachmentAction.Tag := Index;
        RemoveAttachmentAction.Enabled := HasImage;
      End;
    If Assigned(SaveAttachmentAction) Then
      Begin
        SaveAttachmentAction.Tag := Index;
        SaveAttachmentAction.Enabled := HasImage;
      End;
    If Assigned(PreviewAttachmentAction) Then
      Begin
        PreviewAttachmentAction.Tag := Index;
        PreviewAttachmentAction.Enabled := HasImage;
      End;
    End;
End;

Procedure Seam_PreviewComposerImage(Form: TProjectAssistantForm; Index: Integer);
Var
  Ref: TAssistantImageRef;
  TraceRef: TTraceImageRef;
  Root: String;
Begin
  With Form Do
    Begin
    If Not ComposerRefAt(Form, Index, Ref) Then Exit;
    Root := '';
    If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
    TraceRef := Default(TTraceImageRef);
    TraceRef.Id := Ref.Id;
    TraceRef.Name := Ref.Name;
    TraceRef.DisplayPath := Ref.DisplayPath;
    TraceRef.Width := Ref.Width;
    TraceRef.Height := Ref.Height;
    TraceRef.Missing := False;
    ShowAssistantImage(Root, TraceRef);
    End;
End;

Procedure Seam_SaveComposerImage(Form: TProjectAssistantForm; Index: Integer);
Var
  Ref: TAssistantImageRef;
  Dialog: TSaveDialog;
  Root, ErrorText, FileName, Ext: String;
Begin
  With Form Do
    Begin
    If Not ComposerRefAt(Form, Index, Ref) Then Exit;
    Root := '';
    If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
    If (Root = '') Or (Trim(Ref.DisplayPath) = '') Then
      Begin
        RunAssistantModal('The image is unavailable.', mtInformation, [mbOK], 0);
        Exit;
      End;
    FileName := AttachmentSaveName(Ref.Name, Ref.Id);
    Dialog := TSaveDialog.Create(Nil);
    Try
      Dialog.Title := 'Save As';
      Dialog.Filter := 'PNG image|*.png|JPEG image|*.jpg;*.jpeg|GIF image|*.gif|Bitmap image|*.bmp|' +
        'TIFF image|*.tif;*.tiff|XPM image|*.xpm|PNM image|*.pbm;*.pgm;*.ppm|Icon|*.ico|All files|*.*';
      Dialog.FilterIndex := ComposerSaveFilterIndex(FileName);
      Dialog.FileName := FileName;
      Ext := ExtractFileExt(FileName);
      If Ext <> '' Then Dialog.DefaultExt := Copy(Ext, 2, MaxInt);
      Dialog.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing, ofHideReadOnly];
      If DirectoryExists(Root) Then Dialog.InitialDir := Root;
      If Not Dialog.Execute Then Exit;
      If Not WriteStoredImageFile(Root, Ref.DisplayPath, Dialog.FileName, ErrorText) Then
        Begin
          If ErrorText = '' Then ErrorText := 'The image could not be saved.';
          RunAssistantModal(ErrorText, mtInformation, [mbOK], 0);
        End;
    Finally
      Dialog.Free;
    End;
    End;
End;

Procedure Seam_RemoveComposerImageAt(Form: TProjectAssistantForm; Index: Integer);
Var
  I, N: Integer;
  Refs, Kept: TAssistantImageRefArray;
  Root, ErrorText: String;
Begin
  With Form Do
    Begin
    ParseAssistantImageRefs(FComposerImagesJson, Refs);
    If (Index < 0) Or (Index > High(Refs)) Then Exit;
    If Index < FComposerSelectedIndex Then
      Dec(FComposerSelectedIndex)
    Else If Index = FComposerSelectedIndex Then
      If FComposerSelectedIndex > High(Refs) - 1 Then FComposerSelectedIndex := High(Refs) - 1;
    Root := '';
    If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
    If (Root <> '') And (Not FSending) And (Not TurnReferencesImage(Refs[Index].Id)) Then
      DeleteStoredAssistantImage(Root, Refs[Index], ErrorText);
    SetLength(Kept, Length(Refs) - 1);
    N := 0;
    For I := 0 To High(Refs) Do
      If I <> Index Then
        Begin
          Kept[N] := Refs[I];
          Inc(N);
        End;
    FComposerImagesJson := AssistantImageRefsToJson(Kept);
    RefreshComposerImages;
    End;
End;

Procedure Seam_ClearUnsentComposerImages(Form: TProjectAssistantForm);
Var
  Refs: TAssistantImageRefArray;
  I: Integer;
  Root, ErrorText: String;
Begin
  With Form Do
    Begin
    ParseAssistantImageRefs(FComposerImagesJson, Refs);
    Root := '';
    If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
    If (Root <> '') And (Not FSending) Then
      For I := 0 To High(Refs) Do
        If Not TurnReferencesImage(Refs[I].Id) Then
          If Not DeleteStoredAssistantImage(Root, Refs[I], ErrorText) And (ErrorText <> '') Then
            WorkflowLogger.Warning('ProjectAssistant', 'Unsent image: ' + ErrorText);
    FComposerImagesJson := '';
    RefreshComposerImages;
    End;
End;

Procedure Seam_RefreshComposerImages(Form: TProjectAssistantForm);
Var
  Refs: TAssistantImageRefArray;
  I, Side, Border, Inner: Integer;
  Root, HintText: String;
  Frame: TPanel;
  Thumb: TImage;
  Control: TControl;
Begin
  With Form Do
    Begin
    If Not Assigned(AttachmentStrip) Then Exit;
    { A visibility change realigns the stack. Ignore that until the height below
      includes the strip, or the text row is shrunk by the strip height. }
    FComposerLayoutLock := True;
    AttachmentStrip.DisableAlign;
    Try
      For I := AttachmentStrip.ControlCount - 1 DownTo 0 Do
        Begin
          Control := AttachmentStrip.Controls[I];
          Control.Parent := Nil;
          Control.Free;
        End;
      ParseAssistantImageRefs(FComposerImagesJson, Refs);
      If Length(Refs) < 1 Then
        FComposerSelectedIndex := -1
      Else If (FComposerSelectedIndex < 0) Or (FComposerSelectedIndex > High(Refs)) Then
        FComposerSelectedIndex := 0;
      AttachmentStrip.Visible := Length(Refs) > 0;
      AttachmentStrip.PopupMenu := AttachmentPopup;
      AttachmentStrip.ChildSizing.Layout := cclNone;
      If AttachmentStrip.Visible Then
        AttachmentStrip.Height := AttachmentStripHeight;
      If AttachmentStrip.Visible Then
        Begin
          Root := '';
          Side := Scale96ToForm(72);
          Border := Scale96ToForm(2);
          If Border < 1 Then Border := 1;
          Inner := Side - (Border * 2);
          If Inner < 8 Then Inner := Side;
          If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
          For I := 0 To High(Refs) Do
            Begin
              HintText := ComposerImageHint(Refs[I].Name);
              Frame := TPanel.Create(Nil);
              Frame.Parent := AttachmentStrip;
              Frame.BevelOuter := bvNone;
              Frame.Caption := '';
              Frame.Align := alNone;
              Frame.Anchors := [akLeft, akTop];
              Frame.Tag := I;
              Frame.ParentShowHint := False;
              Frame.ShowHint := True;
              Frame.Hint := HintText;
              Frame.PopupMenu := AttachmentPopup;
              Frame.OnMouseDown := @AttachmentImageMouseDown;
              Frame.OnDblClick := @AttachmentImageDblClick;
              Thumb := TImage.Create(Frame);
              Thumb.Parent := Frame;
              Thumb.Align := alNone;
              Thumb.Anchors := [akLeft, akTop];
              Thumb.AutoSize := False;
              Thumb.SetBounds(Border, Border, Inner, Inner);
              Thumb.Constraints.MinWidth := Inner;
              Thumb.Constraints.MaxWidth := Inner;
              Thumb.Constraints.MinHeight := Inner;
              Thumb.Constraints.MaxHeight := Inner;
              Thumb.Tag := I;
              Thumb.ParentShowHint := False;
              Thumb.ShowHint := True;
              Thumb.Hint := HintText;
              Thumb.PopupMenu := AttachmentPopup;
              Thumb.OnMouseDown := @AttachmentImageMouseDown;
              Thumb.OnDblClick := @AttachmentImageDblClick;
              AssignThumbImage(Thumb, Root, Refs[I]);
            End;
          ApplyComposerImageSelection;
        End;
    Finally
      AttachmentStrip.EnableAlign;
      FComposerLayoutLock := False;
    End;
    LayoutComposer;
    End;
End;

Function Seam_ComposerImageIndexUnder(Form: TProjectAssistantForm; Const ScreenPoint: TPoint): Integer;
Var
  Local: TPoint;
  Control: TControl;
  I: Integer;
Begin
  With Form Do
    Begin
    Result := -1;
    If Not Assigned(AttachmentStrip) Then Exit;
    Local := AttachmentStrip.ScreenToClient(ScreenPoint);
    Control := AttachmentStrip.ControlAtPos(Local, True, True);
    If Not Assigned(Control) Or (Control = AttachmentStrip) Then
      For I := AttachmentStrip.ControlCount - 1 DownTo 0 Do
        If PtInRect(AttachmentStrip.Controls[I].BoundsRect, Local) Then
          Begin
            Control := AttachmentStrip.Controls[I];
            Break;
          End;
    If Assigned(Control) And (Control <> AttachmentStrip) Then Result := Control.Tag;
    End;
End;

Procedure Seam_SelectComposerImage(Form: TProjectAssistantForm; Index: Integer);
Var
  Refs: TAssistantImageRefArray;
Begin
  With Form Do
    Begin
    ParseAssistantImageRefs(FComposerImagesJson, Refs);
    If Length(Refs) < 1 Then
      FComposerSelectedIndex := -1
    Else If (Index >= 0) And (Index <= High(Refs)) Then
      FComposerSelectedIndex := Index
    Else If (FComposerSelectedIndex < 0) Or (FComposerSelectedIndex > High(Refs)) Then
      FComposerSelectedIndex := 0;
    ApplyComposerImageSelection;
    End;
End;

Procedure Seam_ApplyComposerImageSelection(Form: TProjectAssistantForm);
Var
  I: Integer;
  Frame: TPanel;
  Selected: Boolean;
Begin
  With Form Do
    Begin
    If Not Assigned(AttachmentStrip) Then Exit;
    For I := 0 To AttachmentStrip.ControlCount - 1 Do
      Begin
        If Not (AttachmentStrip.Controls[I] Is TPanel) Then Continue;
        Frame := TPanel(AttachmentStrip.Controls[I]);
        Selected := (FComposerSelectedIndex >= 0) And (Frame.Tag = FComposerSelectedIndex);
        Frame.ParentBackground := Not Selected;
        Frame.ParentColor := Not Selected;
        If Selected Then
          Begin
            Frame.ParentBackground := False;
            Frame.ParentColor := False;
            Frame.Color := clHighlight;
          End;
        Frame.Invalidate;
      End;
    End;
End;

Procedure Seam_PlaceComposerThumbnails(Form: TProjectAssistantForm);
Var
  I, Gap, Side, X: Integer;
  Control: TControl;
Begin
  With Form Do
    Begin
    If Not Assigned(AttachmentStrip) Then Exit;
    { ChildSizing would give the only picture the whole strip. Keep a fixed tile. }
    AttachmentStrip.ChildSizing.Layout := cclNone;
    Gap := Scale96ToForm(4);
    Side := Scale96ToForm(72);
    X := Gap;
    For I := 0 To AttachmentStrip.ControlCount - 1 Do
      Begin
        Control := AttachmentStrip.Controls[I];
        Control.Align := alNone;
        Control.Anchors := [akLeft, akTop];
        Control.Constraints.MinWidth := Side;
        Control.Constraints.MaxWidth := Side;
        Control.Constraints.MinHeight := Side;
        Control.Constraints.MaxHeight := Side;
        Control.SetBounds(X, Gap, Side, Side);
        X := X + Side + Gap;
      End;
    ApplyComposerImageSelection;
    End;
End;

Function Seam_AttachmentStripHeight(Form: TProjectAssistantForm): Integer;
Begin
  With Form Do
    Begin
    { 4px padding, a 72px thumbnail, 4px padding. }
    Result := Scale96ToForm(80);
    End;
End;

Function Seam_AttachImageFile(Form: TProjectAssistantForm; Const SourcePath: String; Out ErrorText: String): Boolean;
Var
  Root, StoreDir: String;
  Stored: TAssistantStoredImage;
  Refs: TAssistantImageRefArray;
Begin
  With Form Do
    Begin
    Result := False;
    ErrorText := '';
    ParseAssistantImageRefs(FComposerImagesJson, Refs);
    If Length(Refs) >= AssistantImageMaxAttachments Then
      Begin
        ErrorText := 'At most 8 images can be attached.';
        Exit;
      End;
    If Not ComposerStoreReady(Root, StoreDir, ErrorText) Then Exit;
    If Not StoreAssistantImageInStore(Root, StoreDir, SourcePath, Stored, ErrorText) Then Exit;
    AppendComposerStored(Form, Stored);
    Result := True;
    End;
End;

Function Seam_AttachImageStream(Form: TProjectAssistantForm; Const OriginalName: String; Stream: TStream; Out ErrorText: String): Boolean;
Var
  Root, StoreDir: String;
  Stored: TAssistantStoredImage;
  Refs: TAssistantImageRefArray;
Begin
  With Form Do
    Begin
    Result := False;
    ErrorText := '';
    ParseAssistantImageRefs(FComposerImagesJson, Refs);
    If Length(Refs) >= AssistantImageMaxAttachments Then
      Begin
        ErrorText := 'At most 8 images can be attached.';
        Exit;
      End;
    If Not ComposerStoreReady(Root, StoreDir, ErrorText) Then Exit;
    Stream.Position := 0;
    If Not StoreAssistantImageStreamInStore(Root, StoreDir, OriginalName, Stream, Stored, ErrorText) Then Exit;
    AppendComposerStored(Form, Stored);
    Result := True;
    End;
End;

Function Seam_ComposerStoreReady(Form: TProjectAssistantForm; Out Root, StoreDir, ErrorText: String): Boolean;
Begin
  With Form Do
    Begin
    Result := False;
    Root := '';
    StoreDir := '';
    ErrorText := '';
    EnsureConversationStore;
    Root := ProjectAssistantRoot;
    If Assigned(ProjectAssistantConversation) Then StoreDir := ProjectAssistantConversation.AssistantDirectory;
    If (Root = '') Or (StoreDir = '') Then
      Begin
        ErrorText := 'Open a project before attaching an image.';
        Exit;
      End;
    If Not ForceDirectoriesUTF8(ExcludeTrailingPathDelimiter(StoreDir)) Then
      Begin
        ErrorText := 'The image store could not be created.';
        Exit;
      End;
    Result := True;
    End;
End;

Function Seam_ComposerAttachAllowed(Form: TProjectAssistantForm; Out Reason: String): Boolean;
Begin
  With Form Do
    Begin
    Reason := '';
    { One capability check. Codex reads inputModalities; Grok reads the same kind of list. A missing list allows attach. }
    If (FActiveBackend = 'claude') Then
      { Claude Code's model list names no input modalities, so it is unknown, which allows attach. }
      Result := AssistantImageAttachAllowed(aiiUnknown, Reason)
    Else If (FActiveBackend = 'codex') Then
      Result := AssistantImageAttachAllowed(CodexModelImageInput(FCodexModelsJson, FCodexModel), Reason)
    Else If Assigned(AssistantClient) Then
      Result := AssistantClient.ImagesAttachAllowed(Reason)
    Else
      Result := True;
    End;
End;

Procedure Seam_RefreshAttachAction(Form: TProjectAssistantForm);
Var
  Reason: String;
Begin
  With Form Do
    Begin
    If Not Assigned(AttachImageAction) Then Exit;
    AttachImageAction.Enabled := ComposerAttachAllowed(Reason);
    If AttachImageAction.Enabled Then
      AttachImageAction.Hint := 'Attach an image to the next message'
    Else If Reason <> '' Then
      AttachImageAction.Hint := Reason
    Else
      AttachImageAction.Hint := 'Attach is disabled.';
    End;
End;

Procedure Seam_ApplyInputPanelHeight(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    If Not Assigned(InputPanel) Then Exit;
    FInputHeight := Scale96ToForm(75);
    LayoutComposer;
    End;
End;

Procedure Seam_PromptHostResize(Form: TProjectAssistantForm; Sender: TObject);
Var
  Available, Minimum, Strip: Integer;
Begin
  With Form Do
    Begin
    If FComposerLayoutLock Or (csLoading In ComponentState) Or (csDestroying In ComponentState) Then Exit;
    If Not Assigned(PromptHost) Then Exit;
    Minimum := Scale96ToForm(48);
    Strip := 0;
    If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
      Strip := AttachmentStripHeight;
    Available := PromptHost.ClientHeight - Strip;
    If Available < Minimum Then Available := Minimum;
    FInputHeight := Available;
    FComposerLayoutLock := True;
    Try
      PlacePromptChildren;
    Finally
      FComposerLayoutLock := False;
    End;
    End;
End;

Procedure Seam_ComposerStackResize(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If FComposerLayoutLock Or (csLoading In ComponentState) Or (csDestroying In ComponentState) Then Exit;
    FComposerLayoutLock := True;
    Try
      PlaceComposerChildren;
    Finally
      FComposerLayoutLock := False;
    End;
    End;
End;

Procedure Seam_StatusFooterResize(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If (Sender <> StatusFooter) Or FComposerLayoutLock Or (csLoading In ComponentState) Or
      (csDestroying In ComponentState) Then
      Exit;
    { Growing the footer must grow the stack before children are placed, preserving
      the command row's height when the inherited font or display scale changes. }
    LayoutComposer;
    End;
End;

Procedure Seam_LayoutComposer(Form: TProjectAssistantForm);
Var
  StackHeight, PromptHeight: Integer;
Begin
  With Form Do
    Begin
    If Not Assigned(ComposerStack) Or FComposerLayoutLock Then Exit;
    If csDestroying In ComponentState Then Exit;
    FComposerLayoutLock := True;
    DisableAlign;
    Try
      Try
        If FInputHeight < Scale96ToForm(48) Then FInputHeight := Scale96ToForm(75);
        If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
          AttachmentStrip.Height := AttachmentStripHeight;
        StackHeight := ComposerChromeHeight;
        ComposerStack.Height := StackHeight;
        PlaceComposerChildren;
        If Assigned(PromptHost) Then
          Begin
            PromptHeight := FInputHeight;
            If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
              Inc(PromptHeight, AttachmentStripHeight);
            PromptHost.Height := PromptHeight;
            PlacePromptChildren;
          End;
      Except
        On E: Exception Do
          If ClassifyFormFault(Form, afoPaintLayout, 'TProjectAssistantForm.LayoutComposer', E, False) <> araIgnore Then
            Exit;
      End;
    Finally
      EnableAlign;
      FComposerLayoutLock := False;
    End;
    End;
End;

Procedure Seam_PlacePromptChildren(Form: TProjectAssistantForm);
Var
  Y, StripHeight, BandWidth: Integer;
Begin
  With Form Do
    Begin
    { The memo and its pictures stay in the left column. Align is not used here:
      showing the picture strip must not push the memo out of the column. }
    If Not Assigned(PromptHost) Then Exit;
    BandWidth := PromptHost.ClientWidth;
    If BandWidth < 1 Then BandWidth := PromptHost.Width;
    Y := PromptHost.ClientHeight;
    StripHeight := 0;
    If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
      StripHeight := AttachmentStripHeight;
    If Assigned(AttachmentStrip) Then
      Begin
        AttachmentStrip.Align := alNone;
        If StripHeight > 0 Then
          AttachmentStrip.SetBounds(0, Y - StripHeight, BandWidth, StripHeight)
        Else
          AttachmentStrip.SetBounds(0, Y, BandWidth, 0);
        If StripHeight > 0 Then Y := AttachmentStrip.Top;
        PlaceComposerThumbnails;
      End;
    If Assigned(InputPanel) Then
      Begin
        InputPanel.Align := alNone;
        If Y < 1 Then Y := 1;
        InputPanel.SetBounds(0, 0, BandWidth, Y);
      End;
    End;
End;

Procedure Seam_PlaceComposerChildren(Form: TProjectAssistantForm);
Var
  Y, BandWidth: Integer;
Begin
  With Form Do
    Begin
    { Align stays alNone. LCL sorts alBottom siblings by the current bottom edge,
      so growing one of them docks the buttons under the status bar. }
    If Not Assigned(ComposerStack) Then Exit;
    BandWidth := ComposerStack.ClientWidth;
    If BandWidth < 1 Then BandWidth := ComposerStack.Width;
    Y := ComposerStack.ClientHeight;
    If Assigned(StatusFooter) Then
      Begin
        StatusFooter.Align := alNone;
        StatusFooter.SetBounds(0, Y - StatusFooter.Height, BandWidth, StatusFooter.Height);
        Y := StatusFooter.Top;
      End;
    If Assigned(BottomBar) Then
      Begin
        BottomBar.Align := alNone;
        BottomBar.SetBounds(0, 0, BandWidth, Y);
      End;
    End;
End;

Function Seam_ComposerChromeHeight(Form: TProjectAssistantForm): Integer;
Begin
  With Form Do
    Begin
    Result := 0;
    If Assigned(BottomBar) And (BottomBar.Height > 0) Then
      Inc(Result, BottomBar.Height)
    Else
      Inc(Result, Scale96ToForm(36));
    If Assigned(StatusFooter) And (StatusFooter.Height > 0) Then
      Inc(Result, StatusFooter.Height)
    Else
      Inc(Result, Scale96ToForm(22));
    End;
End;

Procedure Seam_InputCopyClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Assigned(InputMemo) Then
      InputMemo.CopyToClipboard;
    End;
End;

Procedure Seam_InputCutClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Assigned(InputMemo) And (Not InputMemo.ReadOnly) Then
      InputMemo.CutToClipboard;
    End;
End;

Procedure Seam_InputPopupPopup(Form: TProjectAssistantForm; Sender: TObject);
Var
  HasSel: Boolean;
  CanEdit: Boolean;
Begin
  With Form Do
    Begin
    HasSel := Assigned(InputMemo) And (InputMemo.SelLength > 0);
    CanEdit := Assigned(InputMemo) And (Not InputMemo.ReadOnly);
    If Assigned(InputCutItem) Then
      InputCutItem.Enabled := HasSel And CanEdit;
    If Assigned(InputCopyItem) Then
      InputCopyItem.Enabled := HasSel;
    If Assigned(InputPasteItem) Then
      { Always offer Paste while the memo can edit. A disabled Ctrl+V shortcut
        swallows the key before the composer can read an image. }
      InputPasteItem.Enabled := CanEdit;
    RefreshAttachAction;
    If Assigned(InputSelectAllItem) Then
      InputSelectAllItem.Enabled := Assigned(InputMemo) And (InputMemo.GetTextLen > 0);
    UpdateInputUndoItems;
    End;
End;

Procedure Seam_UpdateInputUndoItems(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    If Assigned(InputUndoItem) Then
      InputUndoItem.Enabled := Assigned(InputMemo) And InputMemo.CanUndo;
    If Assigned(InputRedoItem) Then
      InputRedoItem.Enabled := Assigned(InputMemo) And InputMemo.CanRedo;
    End;
End;

Procedure Seam_EnsureInputPopup(Form: TProjectAssistantForm);
Var
  Sep: TMenuItem;
Begin
  With Form Do
    Begin
    If Assigned(InputPopup) Or (Not Assigned(InputMemo)) Then
      Exit;
    InputPopup := TPopupMenu.Create(Form);
    InputPopup.OnPopup := @InputPopupPopup;
    InputUndoItem := TMenuItem.Create(InputPopup);
    InputUndoItem.Caption := 'Undo';
    InputUndoItem.ShortCut := ShortCut(Ord('Z'), [ssCtrl]);
    InputUndoItem.OnClick := @InputUndoClick;
    InputPopup.Items.Add(InputUndoItem);
    InputRedoItem := TMenuItem.Create(InputPopup);
    InputRedoItem.Caption := 'Redo';
    InputRedoItem.ShortCut := ShortCut(Ord('Z'), [ssCtrl, ssShift]);
    InputRedoItem.OnClick := @InputRedoClick;
    InputPopup.Items.Add(InputRedoItem);
    Sep := TMenuItem.Create(InputPopup);
    Sep.Caption := '-';
    InputPopup.Items.Add(Sep);
    InputCutItem := TMenuItem.Create(InputPopup);
    InputCutItem.Caption := 'Cut';
    InputCutItem.ShortCut := ShortCut(Ord('X'), [ssCtrl]);
    InputCutItem.OnClick := @InputCutClick;
    InputPopup.Items.Add(InputCutItem);
    InputCopyItem := TMenuItem.Create(InputPopup);
    InputCopyItem.Caption := 'Copy';
    InputCopyItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
    InputCopyItem.OnClick := @InputCopyClick;
    InputPopup.Items.Add(InputCopyItem);
    InputPasteItem := TMenuItem.Create(InputPopup);
    InputPasteItem.Caption := 'Paste';
    { No shortcut. Ctrl+V is handled by the memo so a disabled item cannot eat the key. }
    InputPasteItem.OnClick := @InputPasteClick;
    InputPopup.Items.Add(InputPasteItem);
    InputAttachImageItem := TMenuItem.Create(InputPopup);
    InputAttachImageItem.Action := AttachImageAction;
    InputPopup.Items.Add(InputAttachImageItem);
    Sep := TMenuItem.Create(InputPopup);
    Sep.Caption := '-';
    InputPopup.Items.Add(Sep);
    InputSelectAllItem := TMenuItem.Create(InputPopup);
    InputSelectAllItem.Caption := 'Select All';
    InputSelectAllItem.ShortCut := ShortCut(Ord('A'), [ssCtrl]);
    InputSelectAllItem.OnClick := @InputSelectAllClick;
    InputPopup.Items.Add(InputSelectAllItem);
    InputMemo.PopupMenu := InputPopup;
    InputMemo.WantTabs := False;
    UpdateInputUndoItems;
    End;
End;

Procedure Seam_EnsureChatView(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    If Assigned(FTraceView) Then
      Exit;
    If Not Assigned(ChatHost) Then
      Exit;
    ChatHost.BorderSpacing.Around := 0;
    ChatHost.Color := clWindow;
    ChatHost.ParentColor := False;
    ChatHost.ParentBackground := False;
    FTraceView := TAssistantTraceView.Create(Form);
    FTraceView.Parent := ChatHost;
    FTraceView.Align := alClient;
    FTraceView.BorderSpacing.Around := 0;
    FTraceView.ShowThinking := FShowThinking;
    FTraceView.ShowToolUse := FShowToolUse;
    If Not Assigned(FTrace) Then
      FTrace := TAssistantTrace.Create;
    End;
End;

End.
