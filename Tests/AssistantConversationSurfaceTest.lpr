Program AssistantConversationSurfaceTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, Math, Graphics, LCLType, Clipbrd, Menus, FileUtil, FPImage, FPWritePNG,
  StyledTextTypes, AssistantTrace, AssistantConversationSurface, AssistantImages, AssistantImageView;
Procedure Check(Const Name:String; OK:Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ',Name); Halt(1); End; WriteLn('ok ',Name); End;
Type
  TImageSurface=Class(TAssistantConversationSurface)
  Public
    OpenedName:String;
    Procedure Press(Key:Word);
    Procedure PressShift(Key:Word; Shift:TShiftState);
    Procedure MoveTo(X, Y:Integer);
    Procedure OpenDouble;
    Procedure OpenAttachment(Const Ref:TTraceImageRef); Override;
  End;
Procedure TImageSurface.Press(Key:Word);
Begin
  KeyDown(Key,[]);
End;
Procedure TImageSurface.PressShift(Key:Word; Shift:TShiftState);
Begin
  KeyDown(Key, Shift);
End;
Procedure TImageSurface.MoveTo(X, Y:Integer);
Begin
  MouseMove([], X, Y);
End;
Procedure TImageSurface.OpenDouble;
Begin
  DblClick;
End;
Procedure TImageSurface.OpenAttachment(Const Ref:TTraceImageRef);
Begin
  OpenedName:=Ref.Name;
End;
Var Host:TForm; View:TImageSurface; Trace:TAssistantTrace; I,J,ControlsBefore:Integer; Body,Key:String;
  BeforeHeight,BeforeTop:Int64; Parses,Started,ParsedAt:QWord; Bitmap:TBitmap; PNG:TPortableNetworkGraphic; A,B:TConversationPosition;
Function MenuByCaption(Const Caption:String):TMenuItem;
Var N:Integer;
Begin
  Result:=Nil;
  If Not Assigned(View) Or Not Assigned(View.PopupMenu) Then Exit;
  For N:=0 To View.PopupMenu.Items.Count-1 Do
    If View.PopupMenu.Items[N].Caption=Caption Then Exit(View.PopupMenu.Items[N]);
End;
Procedure Sync;
Var N:Integer;
Begin
 View.BeginDocument; For N:=0 To Trace.Count-1 Do View.AddBlock(Trace[N].ID,Trace[N]); View.EndDocument;
 View.CompleteLayout; Application.ProcessMessages;
 Check('extent equals the height index',View.ContentHeight=View.Layout.TotalHeight);
 Check('scroll position in range',(View.ScrollTop>=0) And (View.ScrollTop<=Max(Int64(0),View.ContentHeight-View.ViewRect.Height)));
End;
Procedure CheckImages;
Var Refs:TTraceImageRefArray; Plain,TextY:Int64; W,H,X,Y,PPI,ContentW:Integer; Hit:TConversationPointerHit; SavedWidth:Integer;
Begin
 Check('1:1 cap at 96 DPI',ScaledImageExtent(100,50,400,96,W,H) And (W=100) And (H=50));
 Check('wider than the bubble scales down',ScaledImageExtent(100,50,40,96,W,H) And (W=40) And (H=20));
 Check('surface DPI is not an extra enlargement',ScaledImageExtent(100,50,400,192,W,H) And (W=200) And (H=100));
 Check('DPI scale still fits the bubble',ScaledImageExtent(100,50,80,192,W,H) And (W=80) And (H=40));
 Trace.Clear; View.Clear;
 Trace.AddUser('A short user message'); Trace.EnsureAnswer.Body:='Reply'; Sync;
 Plain:=View.Layout.Heights.Values[0];
 SetLength(Refs,1);
 Refs[0].Id:='known-size'; Refs[0].Name:='diagram.png'; Refs[0].Width:=100; Refs[0].Height:=50; Refs[0].Missing:=False;
 Trace.SetUserImageRefs(Refs); Sync;
 PPI:=View.Layout.PixelsPerInch; ContentW:=View.Layout.ImageContentWidth(0);
 Check('known image size sets the row',View.Layout.ImageRowHeight(0)=UserImageSlotHeight(Refs[0],ContentW,PPI));
 Check('present image increases the section height',View.Layout.Heights.Values[0]=Plain+View.Layout.ImageRowHeight(0));
 Check('100 by 50 image is taller than the same text',View.Layout.Heights.Values[0]>Plain);
 Check('present image is not enlarged past 1:1',ScaledImageExtent(100,50,ContentW,PPI,W,H) And (W<=Round(100*PPI/96)) And (H<=Round(50*PPI/96)));
 Check('image row is inside the section, not an overlay',
   View.Layout.Heights.Values[0]=View.Layout[0].FullHeight+View.Layout.ImageRowHeight(0)+2*View.Layout[0].Padding+Round(10*PPI/96));
 View.JumpToStart;
 X:=View.ViewRect.Left+View.Layout[0].Left+View.Layout[0].Padding+4;
 Y:=View.ViewRect.Top+View.Layout[0].Padding+4;
 Check('pointer in the picture row hits the picture',View.PointerHit(X,Y).ImageIndex=0);
 TextY:=View.ViewRect.Top+View.Layout[0].Padding+View.Layout.ImageRowHeight(0)+4;
 Hit:=View.PointerHit(X,TextY);
 Check('pointer below the pictures hits the text',(Hit.ImageIndex<0) And (Hit.Position.Key=Trace[0].ID) And (Hit.Position.Text.Paragraph=0));
 Refs[0].Missing:=True; Trace.SetUserImageRefs(Refs); Sync;
 Check('missing file uses the fixed tile height',View.Layout.Heights.Values[0]=Plain+MissingImageTileHeight(PPI));
 Check('missing file is still inside the section height',View.Layout.ImageRowHeight(0)=MissingImageTileHeight(PPI));
 Body:='First words of the user.';
 For J:=1 To 40 Do Body:=Body+LineEnding+LineEnding+'Paragraph '+IntToStr(J)+' stays below the picture.';
 Trace.Clear; View.Clear; Trace.AddUser(Body);
 Refs[0].Width:=100; Refs[0].Height:=400; Refs[0].Missing:=False; Trace.SetUserImageRefs(Refs); Sync;
 View.JumpToStart;
 X:=View.ViewRect.Left+View.Layout[0].Left+View.Layout[0].Padding+4;
 Y:=View.ViewRect.Top+View.Layout[0].Padding+View.Layout.ImageRowHeight(0)+4;
 Hit:=View.PointerHit(X,Y);
 Check('text below a tall picture is the start of the words',(Hit.ImageIndex<0) And (Hit.Position.Text.Paragraph=0));
 View.JumpToStart; BeforeTop:=View.ScrollTop; View.Press(VK_DOWN);
 Check('keyboard scroll moves through the image row',View.ScrollTop>BeforeTop);
 View.ScrollTop:=View.Layout[0].Padding+View.Layout.ImageRowHeight(0);
 Hit:=View.PointerHit(X,View.ViewRect.Top+4);
 Check('scrolling past the pictures lands on the text',(Hit.ImageIndex<0) And (Hit.Position.Text.Paragraph=0));
 SavedWidth:=Host.Width; BeforeTop:=View.ScrollTop;
 Host.Width:=640; Application.ProcessMessages; View.CompleteLayout;
 Check('resize keeps the text below the pictures',View.ScrollTop>=View.Layout[0].Padding+View.Layout.ImageRowHeight(0));
 Host.Width:=SavedWidth; Application.ProcessMessages; View.CompleteLayout;
End;
Procedure CheckPainted;
Var Root, ErrorText: String; Img: TFPMemoryImage; Writer: TFPWriterPNG; Stream: TMemoryStream;
  Stored: TAssistantStoredImage; Refs: TTraceImageRefArray; X, Y, W, H, PPI, ContentW, SampleX, SampleY, NativeW: Integer;
  Shot: TBitmap; Color: TColor; Pixel: TFPColor; Dialog: TAssistantImageView; KeyCode: Word;
 Function IsRed(Value: TColor): Boolean;
 Begin
  Result := (Red(Value) > 200) And (Green(Value) < 80) And (Blue(Value) < 80);
 End;
Begin
 Root := GetTempFileName(GetTempDir, 'paint-images-');
 DeleteFile(Root);
 ForceDirectories(Root);
 Img := TFPMemoryImage.Create(16, 8);
 Stream := TMemoryStream.Create;
 Writer := TFPWriterPNG.Create;
 Try
  Pixel.Red := $FFFF;
  Pixel.Green := 0;
  Pixel.Blue := 0;
  Pixel.Alpha := $FFFF;
  For Y := 0 To Img.Height - 1 Do
   For X := 0 To Img.Width - 1 Do
    Img.Colors[X, Y] := Pixel;
  Img.SaveToStream(Stream, Writer);
  Stream.Position := 0;
  Check('store a picture for the user block', StoreAssistantImageFromStream(Root, 'red.png', Stream, Stored, ErrorText));
 Finally
  Writer.Free;
  Stream.Free;
  Img.Free;
 End;
 View.ImageRoot := Root;
 Trace.Clear; View.Clear;
 Trace.AddUser('Words under the picture');
 SetLength(Refs, 1);
 Refs[0].Id := Stored.Id;
 Refs[0].Name := Stored.OriginalName;
 Refs[0].DisplayPath := Stored.DisplayRelativePath;
 Refs[0].Width := Stored.Width;
 Refs[0].Height := Stored.Height;
 Refs[0].Missing := False;
 Trace.SetUserImageRefs(Refs);
 Sync;
 View.JumpToStart;
 Application.ProcessMessages;
 PPI := View.Layout.PixelsPerInch;
 ContentW := View.Layout.ImageContentWidth(0);
 Check('stored picture has a display size', ScaledImageExtent(Stored.Width, Stored.Height, ContentW, PPI, W, H) And (W > 0) And (H > 0));
 SampleX := View.ViewRect.Left + View.Layout[0].Left + View.Layout[0].Padding + W Div 2;
 SampleY := View.ViewRect.Top + View.Layout[0].Padding + H Div 2;
 Shot := TBitmap.Create;
 Try
  Shot.SetSize(Max(1, View.ClientWidth), Max(1, View.ClientHeight));
  View.PaintTo(Shot.Canvas, 0, 0);
  If (SampleX >= 0) And (SampleY >= 0) And (SampleX < Shot.Width) And (SampleY < Shot.Height) Then
   Color := Shot.Canvas.Pixels[SampleX, SampleY]
  Else
   Color := clNone;
 Finally
  Shot.Free;
 End;
 WriteLn('painted sample ', Red(Color), ',', Green(Color), ',', Blue(Color), ' at ', SampleX, ',', SampleY);
 Check('present file is painted inside the user bubble', IsRed(Color));
 Check('save name is the original file', AttachmentSaveName(Stored.OriginalName, Stored.Id) = Stored.OriginalName);
 Check('unnamed image still has a save name', AttachmentSaveName('', '') = 'Image.png');
 View.OpenedName := '';
 View.MoveTo(SampleX, SampleY);
 View.Press(VK_RETURN);
 Check('Enter on an attachment opens it', View.OpenedName = Stored.OriginalName);
 View.OpenedName := '';
 View.OpenDouble;
 Check('double-click opens the attachment', View.OpenedName = Stored.OriginalName);
 View.PopupMenu.OnPopup(View.PopupMenu);
 Check('Copy Image appears on an attachment', Assigned(MenuByCaption('Copy Image')) And MenuByCaption('Copy Image').Visible);
 Check('Save Image appears on an attachment', Assigned(MenuByCaption('Save Image')) And MenuByCaption('Save Image').Visible);
 MenuByCaption('Copy Image').OnClick(MenuByCaption('Copy Image'));
 Check('copy places a PNG on the clipboard', Clipboard.HasFormat(RegisterClipboardFormat('image/png')));
 A.Key := Trace[0].ID; A.Text := StyledPosition(0, 0); B.Key := Trace[0].ID; B.Text := StyledPosition(0, 5);
 View.SelectRange(A, B);
 View.PressShift(VK_C, [ssCtrl]);
 Check('Ctrl+C on a text selection still copies text', Pos('Words', Clipboard.AsText) > 0);
 View.MoveTo(SampleX, View.ViewRect.Top + View.Layout[0].Padding + View.Layout.ImageRowHeight(0) + 4);
 View.PopupMenu.OnPopup(View.PopupMenu);
 Check('Copy Image hides off the attachment', Assigned(MenuByCaption('Copy Image')) And Not MenuByCaption('Copy Image').Visible);
 Check('Save Image hides off the attachment', Assigned(MenuByCaption('Save Image')) And Not MenuByCaption('Save Image').Visible);
 View.OpenedName := '';
 View.Press(VK_RETURN);
 Check('Enter on the words does not open the picture', View.OpenedName = '');
 Dialog := TAssistantImageView.Create(Nil);
 Try
  Dialog.LoadImage(Root, Trace[0].ImageRefs[0]);
  PPI := Dialog.Font.PixelsPerInch;
  If PPI < 1 Then PPI := 96;
  NativeW := Round(Int64(Stored.Width) * PPI / 96);
  If NativeW < 1 Then NativeW := 1;
  Check('viewer is 1:1 at the surface DPI', ScaledImageExtent(Stored.Width, Stored.Height, NativeW, PPI, W, H) And
    (Dialog.ImagePaint.Width = W) And (Dialog.ImagePaint.Height = H));
  KeyCode := VK_ESCAPE;
  Dialog.FormKeyDown(Dialog, KeyCode, []);
  Check('Esc closes the image view', (KeyCode = 0) And (Dialog.ModalResult = mrCancel));
 Finally
  Dialog.Free;
 End;
 Refs[0].Missing := True;
 Trace.SetUserImageRefs(Refs);
 Sync;
 View.JumpToStart;
 Application.ProcessMessages;
 Shot := TBitmap.Create;
 Try
  Shot.SetSize(Max(1, View.ClientWidth), Max(1, View.ClientHeight));
  View.PaintTo(Shot.Canvas, 0, 0);
  SampleY := View.ViewRect.Top + View.Layout[0].Padding + MissingImageTileHeight(PPI) Div 2;
  SampleX := View.ViewRect.Left + View.Layout[0].Left + View.Layout[0].Padding + Max(8, ContentW - 8);
  If (SampleX >= 0) And (SampleY >= 0) And (SampleX < Shot.Width) And (SampleY < Shot.Height) Then
   Color := Shot.Canvas.Pixels[SampleX, SampleY]
  Else
   Color := clNone;
 Finally
  Shot.Free;
 End;
 Check('missing file is a tile, not the stored picture', Not IsRed(Color));
 DeleteDirectory(Root, False);
End;
Begin
 Application.Initialize; Host:=TForm.CreateNew(nil); Trace:=TAssistantTrace.Create;
 Try
 Host.SetBounds(0,0,800,600); View:=TImageSurface.Create(Host); View.Parent:=Host; View.Align:=alClient;
 Host.Show; Application.ProcessMessages; ControlsBefore:=View.ControlCount;
 Trace.AddTool('failure','read_file','{}').Body:='Failed output';
 Trace.FindTool('failure').OK:=False; Trace.FindTool('failure').Collapsed:=False;
 Sync; Check('failed tool defaults closed',View.Layout[0].Collapsed);
 View.Toggle(0); Sync; Check('user can open failed tool',Not View.Layout[0].Collapsed);
 Trace.FindTool('failure').Body:='Later output'; Trace.FindTool('failure').Collapsed:=True;
 Sync; Check('updates preserve user expansion',Not View.Layout[0].Collapsed);
 View.Toggle(0); Trace.FindTool('failure').Collapsed:=False;
 Sync; Check('updates preserve user collapse',View.Layout[0].Collapsed);
 Trace.Clear; View.Clear;
 Trace.AddUser('A short user message'); Trace.EnsureAnswer.Body:='A short **assistant** reply'; Sync;
 Check('user bubble aligns right',View.Layout[0].Left>View.Layout[1].Left);
 Check('bubble padding is included in extent',View.Layout.Heights.Values[0]=View.Layout[0].FullHeight+2*View.Layout[0].Padding+10);
 Check('bubble text fits its measured width',View.Layout[0].Full.Width=View.Layout[0].OuterWidth-2*View.Layout[0].Padding);
 Check('body font has readable default size',View.Font.Size>=10);
 Trace.AddSteer('Please look at the right edge'); Sync;
 Check('steer uses the user prompt bubble',(View.Layout[2].Kind=tbkSteer) And (View.Layout[2].Left=View.Layout[0].Left) And
   (View.Layout[2].OuterWidth=View.Layout[0].OuterWidth) And (View.Layout[2].Left>View.Layout[1].Left));
 Trace.Clear; View.Clear;
 Trace.StartThinking(0); Sync; Check('empty thinking takes no height',View.ContentHeight=0);
 Trace.CurrentThinking.Body:='Actual reasoning summary'; Sync; Check('received thinking appears',View.ContentHeight>0);
 Body:=''; For J:=1 To 600 Do Body+='Paragraph '+IntToStr(J)+': **bold** words and café text.'+#10+#10;
 For I:=1 To 10 Do Begin Trace.EnsureAnswer.Body:=Body; Trace.AddTool(IntToStr(I),'read_file','{}').Body:='Tool result'; End;
 Sync; Check('long conversation exceeds old coordinate cap',View.ContentHeight>30000);
 Check('first full answer exceeds old card-height cap',View.Layout[1].FullHeight>4000);
 Check('native child-control count is constant',View.ControlCount=ControlsBefore);
 Check('all answers remain visible',View.Layout[View.Layout.Count-2].Visible);
 View.JumpToEnd; Check('end reaches exact last content pixel',View.ScrollTop=View.ContentHeight-View.ViewRect.Height);
 View.ScrollTop:=1000; BeforeTop:=View.ScrollTop; Check('user scroll disables following',Not View.FollowTail);
 Trace.EnsureAnswer.Body:='New appended answer'; Sync;
 Check('append preserves earlier reading position',Abs(View.ScrollTop-BeforeTop)<=1);
 Parses:=View.Layout.ParseCount; Sync; Check('unchanged sync does not reparse Markdown',View.Layout.ParseCount=Parses);
 Trace[1].Title:='Assistant — updated metadata'; Sync; Check('header-only changes do not reparse body',View.Layout.ParseCount=Parses);
 BeforeHeight:=View.ContentHeight; View.ShowToolUse:=False;
 Check('hiding tools shrinks the extent',View.ContentHeight<BeforeHeight);
 Check('hidden tools keep source',Trace.FindTool('1').Body='Tool result');
 View.ShowToolUse:=True; View.CompleteLayout; Check('show restores measured extent',View.ContentHeight=BeforeHeight);
 Key:=Trace[1].ID; View.NavigateTo(Key); View.ScrollTop:=View.ScrollTop+80;
 BeforeHeight:=View.ContentHeight;
 Host.Width:=620; Application.ProcessMessages;
 Check('resize does not collapse to the initial line height',View.ContentHeight>BeforeHeight Div 2);
 View.CompleteLayout;
 Check('width change keeps anchor in same block',View.Layout[View.Layout.AtY(View.ScrollTop)].Key=Key);
 A.Key:=Trace[1].ID; A.Text:=StyledPosition(1,0); B.Key:=Trace[3].ID; B.Text:=StyledPosition(1,10);
 View.SelectRange(A,B); Check('cross-message selection copies text',(Pos('Paragraph',View.SelectedText)>0) And (Pos('read_file',View.SelectedText)>0));
 View.ShowToolUse:=False; Check('filter clears potentially hidden selection',View.SelectedText='');
 Check('Markdown export preserves hidden tools',Pos('Tool result',View.MarkdownText)>0);
 View.JumpToEnd; Trace.EnsureAnswer.Body:=Trace.EnsureAnswer.Body+' after end'; Sync;
 Check('tail remains at end after update',View.FollowTail And (View.ScrollTop=View.ContentHeight-View.ViewRect.Height));
 View.Clear; Check('clear resets extent and offset',(View.ContentHeight=0) And (View.ScrollTop=0));
 CheckImages;
 CheckPainted;
 Trace.Clear; View.ShowToolUse:=True;
 For I:=1 To 10000 Do Trace.AddTool(IntToStr(I),'read_file','{}');
 Started:=GetTickCount64; Sync;
 WriteLn('benchmark 10000 sections: ',GetTickCount64-Started,' ms, height=',View.ContentHeight,', child controls=',View.ControlCount);
 Check('10000 sections remain addressable',(View.Layout.Count=10000) And (View.ContentHeight>30000) And (View.ControlCount=ControlsBefore));
 Check('painting uses the published layout revision',View.PaintRevision=View.LayoutRevision);
 If GetEnvironmentVariable('LAZ_CONVERSATION_BENCHMARK')<>'' Then
   Begin
     Trace.Clear; View.Clear; Body:='';
     While Length(Body)<2*1024*1024 Do Body+='A **formatted** paragraph with `code` and UTF-8 café. '+StringOfChar('x',160)+#10+#10+
       '| Column | Value |'+#10+'| --- | --- |'+#10+'| One | Two |'+#10+#10+
       '```pascal'+#10+'Result := Length(Text);'+#10+'```'+#10+#10;
     Trace.EnsureAnswer.Body:=Body; Trace.AddTool('middle','read_file','{}'); Trace.EnsureAnswer.Body:=Body;
     Started:=GetTickCount64; View.BeginDocument;
     For I:=0 To Trace.Count-1 Do View.AddBlock(Trace[I].ID,Trace[I]);
     View.EndDocument; ParsedAt:=GetTickCount64;
     View.CompleteLayout; Application.ProcessMessages;
     WriteLn('benchmark two large answers: bytes=',Length(Body)*2,', initial sync=',ParsedAt-Started,
       ' ms, complete layout=',GetTickCount64-ParsedAt,' ms, height=',View.ContentHeight);
     Check('large answers retain all content',View.Layout[0].Body=Body);
     Check('large answer extent stays coherent',View.ContentHeight=View.Layout.TotalHeight);
     View.JumpToEnd; Check('large answer end reachable',View.ScrollTop=View.ContentHeight-View.ViewRect.Height);
   End;
 If GetEnvironmentVariable('LAZ_CONVERSATION_CAPTURE')<>'' Then
   Begin
     Trace.Clear; Trace.AddUser('Please review the output renderer.');
     Trace.StartThinking(0).Body:='Check that the conversation and scrollbar use the same measured geometry.'; Trace.FinishCurrentThinking;
     Trace.EnsureAnswer.Body:='The conversation now uses **one StyledText canvas**.'+#10+#10+
       '| Check | Result |'+#10+'| --- | --- |'+#10+'| Long messages | Fully reachable |'+#10+'| Hidden tools | No blank gaps |'+#10+#10+
       '1. Preserve the reading position.'+#10+'2. Keep **bold** text and `code` readable.'+#10+#10+
       '```pascal'+#10+'ScrollTop := Max(0, ContentHeight - ViewHeight);'+#10+'```';
     Trace.AddTool('capture','read_file','{"path":"Source/Main.pas"}').Body:='Tool result retained for expansion';
     Trace.FindTool('capture').Running:=False;
     Trace.EnsureAnswer.Body:='Ready for your next message.'; Trace.ApplyWorkedFooter(1200);
     View.ShowToolUse:=True; Sync; View.JumpToStart; Application.ProcessMessages;
     Bitmap:=Host.GetFormImage; PNG:=TPortableNetworkGraphic.Create;
     Try PNG.Assign(Bitmap); PNG.SaveToFile('/tmp/laz-conversation-canvas.png'); Finally PNG.Free; Bitmap.Free; End;
   End;
 Finally Host.Free; Trace.Free; End;
End.
