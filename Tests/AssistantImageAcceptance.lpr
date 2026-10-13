Program AssistantImageAcceptance;

{ GTK3 composer image acceptance. No Grok or Codex process is started. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cmem, cthreads,
  {$ENDIF}
  Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Clipbrd, Graphics, LCLType, LCLIntf,
  InterfaceBase, Classes, SysUtils, FileUtil, LazFileUtils, Menus, fpimage, fpwritepng, fpwritejpeg,
  AssistantTestIDEHost, LazIDEIntf, ProjectIntf, BaseIDEIntf, LazConfigStorage, WorkflowSettings,
  ProjectAssistantForm, AssistantWorkTarget, AssistantConversation, AssistantImages, AssistantService,
  AssistantProtocol, AssistantConfig, AssistantConversationSurface, AssistantImageView;

Type
  TAcceptanceConfig = Class(TConfigMemStorage)
    Procedure WriteToDisk; Override;
  End;
  TAcceptanceIDE = Class(TLazIDEInterface)
    Function GetActiveProject: TLazProject; Override;
    Class Function GetPrimaryConfigPath: String; Override;
  End;

Var
  Failures: Integer;
  ConfigRoot, ProjectRoot, SavedClipboard: String;
  DialogTimer: TTimer;
  LastDialogText: String;
  HostForm: TProjectAssistantForm;

Procedure TAcceptanceConfig.WriteToDisk;
Begin
End;

Function MemoryConfig(Const Filename: String; LoadFromDisk: Boolean): TConfigStorage;
Begin
  Result := TAcceptanceConfig.Create('', False);
End;

Function TAcceptanceIDE.GetActiveProject: TLazProject;
Begin
  Result := Nil;
End;

Class Function TAcceptanceIDE.GetPrimaryConfigPath: String;
Begin
  Result := ConfigRoot;
End;

Procedure Check(Const Title: String; OK: Boolean);
Begin
  If OK Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(Failures);
    End;
End;

Procedure Pump;
Var
  I: Integer;
Begin
  For I := 1 To 30 Do
    Begin
      Application.ProcessMessages;
      CheckSynchronize;
      Sleep(15);
    End;
End;

Procedure ClosePrompt(Sender: TObject);
Var
  I, J: Integer;
  Prompt: TCustomForm;
  Button: TButton;
  CaptionText: String;
Begin
  For I := 0 To Screen.CustomFormCount - 1 Do
    Begin
      Prompt := Screen.CustomForms[I];
      If Prompt = HostForm Then Continue;
      For J := 0 To Prompt.ComponentCount - 1 Do
        If Prompt.Components[J] Is TLabel Then
          LastDialogText := LastDialogText + TLabel(Prompt.Components[J]).Caption + LineEnding;
      For J := 0 To Prompt.ComponentCount - 1 Do
        If Prompt.Components[J] Is TButton Then
          Begin
            Button := TButton(Prompt.Components[J]);
            CaptionText := StringReplace(Button.Caption, '&', '', [rfReplaceAll]);
            If (CaptionText = 'Yes') Or (CaptionText = 'OK') Then
              Begin
                Button.Click;
                Exit;
              End;
          End;
    End;
End;

Function ThumbnailCount(Form: TProjectAssistantForm): Integer;
Begin
  Result := 0;
  If Assigned(Form) And Assigned(Form.AttachmentStrip) Then Result := Form.AttachmentStrip.ControlCount;
End;

Function AttachmentHint(Form: TProjectAssistantForm; Index: Integer): String;
Begin
  Result := '';
  If Not Assigned(Form) Or Not Assigned(Form.AttachmentStrip) Then Exit;
  If (Index < 0) Or (Index >= Form.AttachmentStrip.ControlCount) Then Exit;
  Result := Form.AttachmentStrip.Controls[Index].Hint;
End;

Function ClickRemove(Form: TProjectAssistantForm): Boolean;
Begin
  Result := False;
  If ThumbnailCount(Form) < 1 Then Exit;
  If Not Assigned(Form.RemoveAttachmentAction) Then Exit;
  Form.RemoveAttachmentAction.Tag := 0;
  Form.RemoveAttachmentAction.Enabled := True;
  Form.RemoveAttachmentAction.Execute;
  Result := True;
End;

Procedure PasteKey(Form: TProjectAssistantForm);
Var
  Key: Word;
Begin
  Key := VK_V;
  Form.InputMemo.SetFocus;
  Application.ProcessMessages;
  If Assigned(Form.InputMemo.OnKeyDown) Then Form.InputMemo.OnKeyDown(Form.InputMemo, Key, [ssCtrl]);
  Application.ProcessMessages;
End;

Procedure WritePng(Const FileName: String; Width, Height: Integer);
Var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  Stream: TFileStream;
  X, Y: Integer;
  Pixel: TFPColor;
Begin
  Img := TFPMemoryImage.Create(Width, Height);
  Writer := TFPWriterPNG.Create;
  Stream := TFileStream.Create(FileName, fmCreate);
  Try
    Pixel.Red := 0;
    Pixel.Green := $FFFF;
    Pixel.Blue := 0;
    Pixel.Alpha := $FFFF;
    For Y := 0 To Height - 1 Do
      For X := 0 To Width - 1 Do
        Img.Colors[X, Y] := Pixel;
    Img.SaveToStream(Stream, Writer);
  Finally
    Stream.Free;
    Writer.Free;
    Img.Free;
  End;
End;

Procedure WriteJpeg(Const FileName: String; Width, Height: Integer);
Var
  Img: TFPMemoryImage;
  Writer: TFPWriterJPEG;
  Stream: TFileStream;
  X, Y: Integer;
  Pixel: TFPColor;
Begin
  Img := TFPMemoryImage.Create(Width, Height);
  Writer := TFPWriterJPEG.Create;
  Stream := TFileStream.Create(FileName, fmCreate);
  Try
    Pixel.Red := $FFFF;
    Pixel.Green := 0;
    Pixel.Blue := 0;
    Pixel.Alpha := $FFFF;
    For Y := 0 To Height - 1 Do
      For X := 0 To Width - 1 Do
        Img.Colors[X, Y] := Pixel;
    Img.SaveToStream(Stream, Writer);
  Finally
    Stream.Free;
    Writer.Free;
    Img.Free;
  End;
End;

Procedure PutPngOnClipboard(Const FileName: String);
Var
  Stream: TMemoryStream;
Begin
  Stream := TMemoryStream.Create;
  Try
    Stream.LoadFromFile(FileName);
    Stream.Position := 0;
    Clipboard.Open;
    Try
      Clipboard.Clear;
      If Not Clipboard.AddFormat(RegisterClipboardFormat('image/png'), Stream) Then
        Raise Exception.Create('Could not place a PNG on the clipboard.');
    Finally
      Clipboard.Close;
    End;
  Finally
    Stream.Free;
  End;
End;

Function ImageDirectory: String;
Begin
  Result := IncludeTrailingPathDelimiter(ProjectRoot) + AssistantStoreFolderName + PathDelim +
    AssistantImagesFolderName + PathDelim;
End;

Function CountImageFiles: Integer;
Var
  Rec, Inner: TSearchRec;
  StoreDir, Child: String;
Begin
  Result := 0;
  StoreDir := IncludeTrailingPathDelimiter(ProjectRoot) + AssistantStoreFolderName + PathDelim;
  If FindFirstUTF8(StoreDir + '*', faAnyFile, Rec) <> 0 Then Exit;
  Try
    Repeat
      If (Rec.Name = '.') Or (Rec.Name = '..') Then Continue;
      If (Rec.Attr And faDirectory) = 0 Then Continue;
      If (Rec.Name <> AssistantImagesFolderName) And (Copy(Rec.Name, 1, 7) <> 'images-') Then Continue;
      Child := StoreDir + Rec.Name + PathDelim;
      If FindFirstUTF8(Child + '*', faAnyFile, Inner) <> 0 Then Continue;
      Try
        Repeat
          If (Inner.Name <> '.') And (Inner.Name <> '..') And ((Inner.Attr And faDirectory) = 0) Then Inc(Result);
        Until FindNextUTF8(Inner) <> 0;
      Finally
        FindCloseUTF8(Inner);
      End;
    Until FindNextUTF8(Rec) <> 0;
  Finally
    FindCloseUTF8(Rec);
  End;
End;

Function RefsFromStore: TAssistantImageRefArray;
Var
  Rec: TSearchRec;
  Img: TFPMemoryImage;
  ErrorText, Id, UploadName: String;
  N: Integer;
Begin
  SetLength(Result, 0);
  If FindFirstUTF8(ImageDirectory + '*', faAnyFile, Rec) <> 0 Then Exit;
  Try
    Repeat
      If (Rec.Name = '.') Or (Rec.Name = '..') Or ((Rec.Attr And faDirectory) <> 0) Then Continue;
      If Pos('-upload', Rec.Name) > 0 Then Continue;
      Id := ChangeFileExt(Rec.Name, '');
      UploadName := Id + '-upload.png';
      If Not FileExistsUTF8(ImageDirectory + UploadName) Then UploadName := Id + '-upload.jpg';
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].Id := Id;
      Result[N].Name := Rec.Name;
      Result[N].Mime := 'image/png';
      If LowerCase(ExtractFileExt(Rec.Name)) = '.jpg' Then Result[N].Mime := 'image/jpeg';
      Result[N].DisplayPath := AssistantStoreFolderName + '/' + AssistantImagesFolderName + '/' + Rec.Name;
      Result[N].UploadPath := AssistantStoreFolderName + '/' + AssistantImagesFolderName + '/' + UploadName;
      Result[N].UploadMime := 'image/png';
      Img := Nil;
      If LoadStoredAssistantImage(ProjectRoot, Result[N].DisplayPath, Img, ErrorText) And Assigned(Img) Then
        Begin
          Result[N].Width := Img.Width;
          Result[N].Height := Img.Height;
          Img.Free;
        End;
    Until FindNextUTF8(Rec) <> 0;
  Finally
    FindCloseUTF8(Rec);
  End;
End;

Function FindSurface(Root: TWinControl): TAssistantConversationSurface;
Var
  I: Integer;
Begin
  Result := Nil;
  If Not Assigned(Root) Then Exit;
  If Root Is TAssistantConversationSurface Then Exit(TAssistantConversationSurface(Root));
  For I := 0 To Root.ControlCount - 1 Do
    If Root.Controls[I] Is TWinControl Then
      Begin
        Result := FindSurface(TWinControl(Root.Controls[I]));
        If Assigned(Result) Then Exit;
      End;
End;

Function SurfaceHasPresentImage(Surface: TAssistantConversationSurface): Boolean;
Var
  I, J: Integer;
Begin
  Result := False;
  If Not Assigned(Surface) Then Exit;
  For I := 0 To Surface.Layout.Count - 1 Do
    For J := 0 To High(Surface.Layout[I].Images) Do
      If (Not Surface.Layout[I].Images[J].Missing) And (Surface.Layout[I].Images[J].Width > 0) Then
        Exit(True);
End;

Function OpenForm: TProjectAssistantForm;
Var
  Note: String;
Begin
  If Not AssistantTarget.SelectFolder(ProjectRoot, Note) Then
    Raise Exception.Create(Note);
  Result := TProjectAssistantForm.Create(Nil);
  Result.SetBounds(40, 40, 980, 720);
  Result.BindToActiveProject;
  Result.Show;
  Pump;
End;

Procedure RecordCurrentImages(Const Prompt: String);
Var
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
  Refs: TAssistantImageRefArray;
Begin
  Refs := RefsFromStore;
  If Not Assigned(AssistantClient) Then Raise Exception.Create('No assistant client');
  AssistantClient.ClearHistory;
  AssistantClient.AddUserMessage(Prompt, Refs);
  Turn := Default(TConversationTurn);
  Turn.Id := NewConversationTurnId;
  Turn.Mode := 'inspect';
  Turn.Prompt := Prompt;
  Turn.CreatedAt := '2026-09-26T12:00:00Z';
  Turn.AttachmentsJson := AssistantImageRefsToJson(Refs);
  Turn.MessagesJson := AssistantClient.ExportUnstoredMessagesJson;
  AssistantClient.ClearHistory;
  If Not ProjectAssistantConversation.AppendTurn(Turn, Entry) Then
    Raise Exception.Create(ProjectAssistantConversation.LastError);
End;

Function RequestJson: String;
Var
  Options: TSamplerRequestOptions;
Begin
  Options := DefaultSamplerRequestOptions;
  Options.ProjectRoot := ProjectRoot;
  Options.Model := 'acceptance';
  Result := BuildResponsesRequestJson(AssistantClient.ExportSamplerItems(True), Options);
End;

Function MenuItemByCaption(Menu: TPopupMenu; Const CaptionText: String): TMenuItem;
Var
  I: Integer;
Begin
  Result := Nil;
  If Not Assigned(Menu) Then Exit;
  For I := 0 To Menu.Items.Count - 1 Do
    If Menu.Items[I].Caption = CaptionText Then Exit(Menu.Items[I]);
End;

Procedure CopyVisibleImage(Surface: TAssistantConversationSurface);
Var
  Index, X, Y: Integer;
  Item: TMenuItem;
  Ref: TTraceImageRef;
  ErrorText: String;
Begin
  Index := 0;
  While (Index < Surface.Layout.Count) And (Length(Surface.Layout[Index].Images) = 0) Do Inc(Index);
  If Index >= Surface.Layout.Count Then Exit;
  X := Surface.Layout[Index].Left + Surface.Layout[Index].Padding + 8;
  Y := Integer(Surface.Layout.Top(Index) + Surface.Layout[Index].Padding + 8);
  Surface.Perform(LM_MOUSEMOVE, 0, LongInt(X) Or (LongInt(Y) Shl 16));
  If Assigned(Surface.PopupMenu) And Assigned(Surface.PopupMenu.OnPopup) Then
    Surface.PopupMenu.OnPopup(Surface.PopupMenu);
  Item := MenuItemByCaption(Surface.PopupMenu, 'Copy Image');
  Check('Copy Image is offered on an attachment', Assigned(Item) And Item.Visible);
  If Assigned(Item) And Item.Visible Then Item.Click;
  Check('Save Image is offered on an attachment',
    Assigned(MenuItemByCaption(Surface.PopupMenu, 'Save Image')) And
    MenuItemByCaption(Surface.PopupMenu, 'Save Image').Visible);
  Ref.Id := Surface.Layout[Index].Images[0].Id;
  Ref.Name := Surface.Layout[Index].Images[0].Name;
  Ref.DisplayPath := Surface.Layout[Index].Images[0].DisplayPath;
  Ref.Width := Surface.Layout[Index].Images[0].Width;
  Ref.Height := Surface.Layout[Index].Images[0].Height;
  Ref.Missing := Surface.Layout[Index].Images[0].Missing;
  ErrorText := '';
  Check('save writes the transcript image',
    WriteStoredImageFile(ProjectRoot, Ref.DisplayPath,
      IncludeTrailingPathDelimiter(ProjectRoot) + 'saved-transcript.png', ErrorText) And
    FileExistsUTF8(IncludeTrailingPathDelimiter(ProjectRoot) + 'saved-transcript.png'));
End;

Procedure SelectHistory(Index: Integer);
Begin
  If (Index < 0) Or (Index >= HostForm.HistoryCombo.Items.Count) Then Exit;
  HostForm.HistoryCombo.ItemIndex := Index;
  HostForm.HistoryComboChange(Nil);
  Pump;
End;

Var
  IDE: TAcceptanceIDE;
  Surface: TAssistantConversationSurface;
  PngPath, JpegPath, BeforeText, Json, DisplayPath: String;
  BeforeFiles, I: Integer;
  Names: Array[0..0] Of String;
  Refs: TAssistantImageRefArray;
Begin
  Failures := 0;
  HostForm := Nil;
  IDE := Nil;
  DialogTimer := Nil;
  SavedClipboard := '';
  Try
    Application.Initialize;
    Check('widgetset is GTK3', WidgetSet.LCLPlatform = lpGtk3);
    If WidgetSet.LCLPlatform <> lpGtk3 Then Halt(1);
    If Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn Then
      Begin
        WriteLn('FAIL refusing to run while a provider token is loaded');
        Halt(2);
      End;
    ConfigRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-image-acceptance-config' + PathDelim;
    ProjectRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-image-acceptance-project' + PathDelim;
    ForceDirectories(ConfigRoot);
    ForceDirectories(ProjectRoot + 'Documents' + PathDelim + 'Images');
    SetWorkflowSettingsDirectory(ConfigRoot);
    GetIDEConfigStorage := @MemoryConfig;
    IDE := TAcceptanceIDE.Create(Nil);
    LazarusIDE := IDE;
    PngPath := ProjectRoot + 'Documents' + PathDelim + 'Images' + PathDelim + 'drop.png';
    JpegPath := ProjectRoot + 'Documents' + PathDelim + 'Images' + PathDelim + 'sample.jpg';
    WritePng(PngPath, 24, 16);
    WriteJpeg(JpegPath, 20, 12);
    WritePng(ProjectRoot + 'clip.png', 32, 18);
    HostForm := OpenForm;
    Check('the form accepts file drops', HostForm.AllowDropFiles);
    Check('image list popup offers attach, remove, save, and preview',
      Assigned(HostForm.AttachmentPopup) And (HostForm.AttachmentPopup.Items.Count = 4) And
      (HostForm.AttachImageAction.Caption = 'Attach Image') And (HostForm.RemoveAttachmentAction.Caption = 'Remove') And
      (HostForm.SaveAttachmentAction.Caption = 'Save') And (HostForm.PreviewAttachmentAction.Caption = 'Preview'));
    If Clipboard.HasFormat(CF_TEXT) Then SavedClipboard := Clipboard.AsText;
    PutPngOnClipboard(ProjectRoot + 'clip.png');
    HostForm.InputMemo.Clear;
    PasteKey(HostForm);
    Check('clipboard PNG attaches to an empty prompt', ThumbnailCount(HostForm) = 1);
    Check('clipboard thumbnail hints Clipboard', AttachmentHint(HostForm, 0) = 'Clipboard');
    Check('image-only paste does not insert text', Trim(HostForm.InputMemo.Text) = '');
    LastDialogText := '';
    DialogTimer := TTimer.Create(Nil);
    DialogTimer.Interval := 40;
    DialogTimer.OnTimer := @ClosePrompt;
    DialogTimer.Enabled := True;
    HostForm.SendAction.Execute;
    Pump;
    DialogTimer.Enabled := False;
    Check('empty image send reaches sign-in and does not call a model', Pos('Sign in', LastDialogText) > 0);
    Check('refused send keeps the pasted thumbnail', ThumbnailCount(HostForm) = 1);
    Names[0] := JpegPath;
    HostForm.OnDropFiles(HostForm, Names);
    Application.ProcessMessages;
    Check('JPEG from Documents/Images attaches', ThumbnailCount(HostForm) = 2);
    Check('file thumbnail hints the file name', AttachmentHint(HostForm, 1) = 'sample.jpg');
    Names[0] := 'file://' + PngPath;
    HostForm.OnDropFiles(HostForm, Names);
    Application.ProcessMessages;
    Check('dropped PNG attaches', ThumbnailCount(HostForm) = 3);
    Names[0] := ProjectRoot + 'skip.pas';
    With TStringList.Create Do
      Try
        Text := 'Unit Skip; Interface Implementation End.';
        SaveToFile(Names[0]);
      Finally
        Free;
      End;
    BeforeFiles := ThumbnailCount(HostForm);
    HostForm.OnDropFiles(HostForm, Names);
    Application.ProcessMessages;
    Check('dropped pascal file is ignored', ThumbnailCount(HostForm) = BeforeFiles);
    BeforeFiles := CountImageFiles;
    Check('remove deletes one unsent thumbnail', ClickRemove(HostForm) And (ThumbnailCount(HostForm) = 2));
    Check('remove deletes the unsent store file', CountImageFiles < BeforeFiles);
    Clipboard.AsText := 'Ordinary paste still lands';
    BeforeText := HostForm.InputMemo.Text;
    PasteKey(HostForm);
    Check('ordinary text paste lands in the memo', Pos('Ordinary paste still lands', HostForm.InputMemo.Text) > 0);
    Check('text paste keeps the remaining thumbnails', ThumbnailCount(HostForm) = 2);
    RecordCurrentImages('acceptance image');
    HostForm.Free;
    HostForm := OpenForm;
    Surface := FindSurface(HostForm);
    Pump;
    Check('reload shows the pictures on the turn', SurfaceHasPresentImage(Surface));
    Json := RequestJson;
    Check('reloaded pictures are in the next native request', Pos('data:image', Json) > 0);
    Check('image-only model text is the look sentence', Pos(AssistantImageLookText, Json) > 0);
    Refs := RefsFromStore;
    If Length(Refs) > 0 Then DisplayPath := IncludeTrailingPathDelimiter(ProjectRoot) +
      StringReplace(Refs[0].DisplayPath, '/', PathDelim, [rfReplaceAll]);
    For I := 1 To 16 Do
      AssistantClient.AddMessage(amrUser, StringOfChar('x', 20000));
    AssistantClient.MaxPromptTokens := 1000;
    AssistantClient.CompactOlderHistory;
    Json := RequestJson;
    Check('compacted history omits the image from the next request', Pos('data:image', Json) = 0);
    Check('compact names the omitted image', Pos(AssistantImageOmittedPrefix, Json) > 0);
    Check('compact keeps the display file', (DisplayPath <> '') And FileExistsUTF8(DisplayPath));
    HostForm.NewChatAction.Execute;
    Pump;
    Check('new chat archives the pictured conversation', HostForm.HistoryCombo.Items.Count >= 2);
    SelectHistory(1);
    Surface := FindSurface(HostForm);
    Check('archived conversation still shows the pictures', SurfaceHasPresentImage(Surface));
    If Assigned(Surface) Then
      Begin
        Surface.Invalidate;
        Surface.Update;
        CopyVisibleImage(Surface);
        Check('copy places a PNG on the clipboard', Clipboard.HasFormat(RegisterClipboardFormat('image/png')));
      End;
    SelectHistory(1);
    SelectHistory(1);
    Surface := FindSurface(HostForm);
    Check('switching back still shows the pictures', SurfaceHasPresentImage(Surface));
    BeforeFiles := CountImageFiles;
    DialogTimer.Enabled := True;
    HostForm.DeleteHistoryAction.Execute;
    Pump;
    DialogTimer.Enabled := False;
    Check('deleting the conversation removes its unreferenced image files', CountImageFiles < BeforeFiles);
    HostForm.Free;
    HostForm := Nil;
    With TStringList.Create Do
      Try
        Text := '{"assistant":{"active_connection":"chatgpt1","connections":[' +
          '{"id":"grok","name":"Grok","backend":"grok","model":"grok-test","thinking":"low","approval":"ask"},' +
          '{"id":"chatgpt1","name":"ChatGPT","backend":"codex","model":"gpt-test","thinking":"low",' +
          '"approval":"ask","runtime":"codex"}]}}';
        SaveToFile(WorkflowSettingsPath);
      Finally
        Free;
      End;
    HostForm := OpenForm;
    Pump;
    Check('ChatGPT disables Attach', Not HostForm.AttachImageAction.Enabled);
    Check('Attach explains that this runtime cannot see images',
      Pos('cannot see', HostForm.AttachImageAction.Hint) > 0);
    HostForm.AttachImageAction.Enabled := True;
    LastDialogText := '';
    DialogTimer.Enabled := True;
    HostForm.AttachImageAction.Execute;
    Pump;
    DialogTimer.Enabled := False;
    Check('clicking Attach explains the same limit', Pos('cannot see', LastDialogText) > 0);
  Except
    On E: Exception Do
      Begin
        WriteLn('FAIL ', E.ClassName, ': ', E.Message);
        DumpExceptionBackTrace;
        Inc(Failures);
      End;
  End;
  If Assigned(DialogTimer) Then DialogTimer.Free;
  If Assigned(HostForm) Then HostForm.Free;
  LazarusIDE := Nil;
  If Assigned(IDE) Then IDE.Free;
  If SavedClipboard <> '' Then Clipboard.AsText := SavedClipboard;
  If Failures > 0 Then Halt(1);
  WriteLn('PASS GTK3 image acceptance');
End.
