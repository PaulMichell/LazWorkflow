Unit SpellMemo;

{ TMemo with optional Hunspell/ASpell markup (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Controls, StdCtrls, Menus, ExtCtrls, Graphics, LMessages, SpellMemoMarkup;

Type
  TSpellMemo = Class(TMemo)
  Private
    FUseSharedConfig: Boolean;
    FDebounce: TTimer;
    FRanges: TSpellUnderlineRangeArray;
    FOwnedPopup: TPopupMenu;
    FSpellItemCount: Integer;
    FActiveToken: String;
    FActiveStart: Integer;
    FActiveLength: Integer;
    FHostPopupHandler: TNotifyEvent;
    FHookedPopup: TPopupMenu;
    Procedure DebounceTimer(Sender: TObject);
    Procedure ConfigChanged(Sender: TObject);
    Procedure RestartDebounce;
    Procedure ClearSpellMenu(Menu: TPopupMenu);
    Procedure RebuildSpellMenu(Menu: TPopupMenu);
    Procedure SuggestionClick(Sender: TObject);
    Procedure IgnoreClick(Sender: TObject);
    Procedure AddClick(Sender: TObject);
    Procedure PopupPopup(Sender: TObject);
    Procedure EnsurePopupHook;
    Function SpellActive: Boolean;
    Procedure ReplaceActiveWord(Const NewText: String);
    Procedure LocateTokenAtCaret;
  Protected
    Procedure Change; Override;
    Procedure Loaded; Override;
    Procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure DoContextPopup(MousePos: TPoint; Var Handled: Boolean); Override;
    Procedure WMPaint(Var Message: TLMPaint); Message LM_PAINT;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure Rescan;
  Published
    Property UseSharedConfig: Boolean Read FUseSharedConfig Write FUseSharedConfig Default True;
  End;

Implementation

Uses
  LCLType, LCLIntf, LazUTF8, SpellCheckerConfig, SpellWordBreaker, SpellEngine;

Constructor TSpellMemo.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FUseSharedConfig := True;
  ParentFont := True;
  WordWrap := True;
  WantTabs := False;
  ScrollBars := ssAutoVertical;
  FSpellItemCount := 0;
  FActiveStart := 0;
  FActiveLength := 0;
  FOwnedPopup := TPopupMenu.Create(Nil);
  FDebounce := TTimer.Create(Nil);
  FDebounce.Enabled := False;
  FDebounce.Interval := 200;
  FDebounce.OnTimer := @DebounceTimer;
  If Assigned(WorkflowSpellConfig) Then
    WorkflowSpellConfig.RegisterChangedHandler(@ConfigChanged);
End;

Destructor TSpellMemo.Destroy;
Begin
  If Assigned(WorkflowSpellConfig) Then
    WorkflowSpellConfig.UnregisterChangedHandler(@ConfigChanged);
  If Assigned(FHookedPopup) Then
    FHookedPopup.OnPopup := FHostPopupHandler;
  FreeAndNil(FDebounce);
  FreeAndNil(FOwnedPopup);
  Inherited Destroy;
End;

Procedure TSpellMemo.Loaded;
Begin
  Inherited Loaded;
  If csDesigning In ComponentState Then
    Exit;
  If FUseSharedConfig And Assigned(WorkflowSpellConfig) And (Not WorkflowSpellConfig.IsReady) Then
    WorkflowSpellConfig.Apply;
  EnsurePopupHook;
  RestartDebounce;
End;

Function TSpellMemo.SpellActive: Boolean;
Begin
  Result := FUseSharedConfig And Assigned(WorkflowSpellConfig) And WorkflowSpellConfig.IsReady And
    (Not (csDesigning In ComponentState));
End;

Procedure TSpellMemo.RestartDebounce;
Begin
  If Not Assigned(FDebounce) Then
    Exit;
  FDebounce.Enabled := False;
  If SpellActive And HandleAllocated Then
    FDebounce.Enabled := True
  Else
    Begin
      SetLength(FRanges, 0);
      SpellMemoClearUnderlines(Self);
    End;
End;

Procedure TSpellMemo.Change;
Begin
  Inherited Change;
  RestartDebounce;
End;

Procedure TSpellMemo.ConfigChanged(Sender: TObject);
Begin
  RestartDebounce;
End;

Procedure TSpellMemo.DebounceTimer(Sender: TObject);
Begin
  FDebounce.Enabled := False;
  Rescan;
End;

Procedure TSpellMemo.Rescan;
Var
  Tokens: TSpellTokenArray;
  Index, Count: Integer;
  Body: String;
Begin
  SetLength(FRanges, 0);
  If Not SpellActive Then
    Begin
      SpellMemoClearUnderlines(Self);
      Exit;
    End;
  Body := Text;
  Tokens := SpellBreakWords(Body);
  Count := 0;
  For Index := 0 To High(Tokens) Do
    If Not WorkflowSpellConfig.IsWordCorrect(Tokens[Index].Text) Then
      Begin
        If Count >= Length(FRanges) Then
          SetLength(FRanges, Count + 16);
        FRanges[Count].UTF8Start := Tokens[Index].ByteStart;
        FRanges[Count].UTF8Length := Tokens[Index].ByteLength;
        Inc(Count);
      End;
  SetLength(FRanges, Count);
  If Not SpellMemoApplyUnderlines(Self, Body, FRanges) Then
    Invalidate;
End;

Procedure TSpellMemo.WMPaint(Var Message: TLMPaint);
Begin
  Inherited;
  {$IFDEF MSWINDOWS}
  If SpellActive And (Length(FRanges) > 0) Then
    SpellMemoDrawWin32Waves(Self, Text, FRanges);
  {$ENDIF}
End;

Procedure TSpellMemo.EnsurePopupHook;
Begin
  If PopupMenu = Nil Then
    PopupMenu := FOwnedPopup;
  If PopupMenu = FHookedPopup Then
    Exit;
  If Assigned(FHookedPopup) Then
    FHookedPopup.OnPopup := FHostPopupHandler;
  FHookedPopup := PopupMenu;
  FHostPopupHandler := Nil;
  If Assigned(FHookedPopup) Then
    Begin
      FHostPopupHandler := FHookedPopup.OnPopup;
      FHookedPopup.OnPopup := @PopupPopup;
    End;
End;

Procedure TSpellMemo.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Var
  ByteIndex, CharIndex: Integer;
Begin
  If (Button = mbRight) And (SelLength = 0) Then
    Begin
      ByteIndex := SpellMemoClientToByteIndex(Self, Text, X, Y);
      CharIndex := SpellByteToCharOffset(Text, ByteIndex);
      SelStart := CharIndex;
      SelLength := 0;
    End;
  Inherited MouseDown(Button, Shift, X, Y);
  EnsurePopupHook;
End;

Procedure TSpellMemo.DoContextPopup(MousePos: TPoint; Var Handled: Boolean);
Begin
  EnsurePopupHook;
  Inherited DoContextPopup(MousePos, Handled);
End;

Procedure TSpellMemo.LocateTokenAtCaret;
Var
  Body: String;
  BytePos: Integer;
  Token: TSpellToken;
Begin
  FActiveToken := '';
  FActiveStart := 0;
  FActiveLength := 0;
  Body := Text;
  BytePos := SpellCharToByteIndex(Body, SelStart);
  If SpellTokenAt(Body, BytePos, Token) Then
    Begin
      FActiveToken := Token.Text;
      FActiveStart := Token.ByteStart;
      FActiveLength := Token.ByteLength;
    End;
End;

Procedure TSpellMemo.ClearSpellMenu(Menu: TPopupMenu);
Begin
  If Not Assigned(Menu) Then
    Exit;
  While (FSpellItemCount > 0) And (Menu.Items.Count > 0) Do
    Begin
      Menu.Items[0].Free;
      Dec(FSpellItemCount);
    End;
  FSpellItemCount := 0;
End;

Procedure TSpellMemo.RebuildSpellMenu(Menu: TPopupMenu);
Var
  Suggestions: TSpellStringArray;
  Index: Integer;
  Item: TMenuItem;
  Misspelled: Boolean;
Begin
  ClearSpellMenu(Menu);
  If Not Assigned(Menu) Or Not SpellActive Then
    Exit;
  LocateTokenAtCaret;
  If FActiveToken = '' Then
    Exit;
  Misspelled := Not WorkflowSpellConfig.IsWordCorrect(FActiveToken);
  If Not Misspelled Then
    Exit;
  Suggestions := WorkflowSpellConfig.GetSuggestions(FActiveToken, 12);
  For Index := 0 To High(Suggestions) Do
    Begin
      Item := TMenuItem.Create(Menu);
      Item.Caption := Suggestions[Index];
      Item.OnClick := @SuggestionClick;
      Menu.Items.Insert(FSpellItemCount, Item);
      Inc(FSpellItemCount);
    End;
  If FSpellItemCount > 0 Then
    Begin
      Item := TMenuItem.Create(Menu);
      Item.Caption := '-';
      Menu.Items.Insert(FSpellItemCount, Item);
      Inc(FSpellItemCount);
    End;
  Item := TMenuItem.Create(Menu);
  Item.Caption := 'Ignore "' + FActiveToken + '"';
  Item.OnClick := @IgnoreClick;
  Menu.Items.Insert(FSpellItemCount, Item);
  Inc(FSpellItemCount);
  Item := TMenuItem.Create(Menu);
  Item.Caption := 'Add "' + FActiveToken + '" to dictionary';
  Item.OnClick := @AddClick;
  Menu.Items.Insert(FSpellItemCount, Item);
  Inc(FSpellItemCount);
  If Menu.Items.Count > FSpellItemCount Then
    Begin
      Item := TMenuItem.Create(Menu);
      Item.Caption := '-';
      Menu.Items.Insert(FSpellItemCount, Item);
      Inc(FSpellItemCount);
    End;
End;

Procedure TSpellMemo.PopupPopup(Sender: TObject);
Begin
  RebuildSpellMenu(Sender As TPopupMenu);
  If Assigned(FHostPopupHandler) Then
    FHostPopupHandler(Sender);
End;

Procedure TSpellMemo.ReplaceActiveWord(Const NewText: String);
Var
  Body: String;
  CharStart, CharEnd: Integer;
Begin
  If (FActiveStart < 1) Or (FActiveLength <= 0) Then
    Exit;
  Body := Text;
  CharStart := SpellByteToCharOffset(Body, FActiveStart);
  CharEnd := SpellByteToCharOffset(Body, FActiveStart + FActiveLength);
  SelStart := CharStart;
  SelLength := CharEnd - CharStart;
  SelText := NewText;
End;

Procedure TSpellMemo.SuggestionClick(Sender: TObject);
Begin
  If Sender Is TMenuItem Then
    ReplaceActiveWord(StringReplace(TMenuItem(Sender).Caption, '&', '', [rfReplaceAll]));
End;

Procedure TSpellMemo.IgnoreClick(Sender: TObject);
Begin
  If Assigned(WorkflowSpellConfig) And (FActiveToken <> '') Then
    WorkflowSpellConfig.IgnoreWord(FActiveToken);
End;

Procedure TSpellMemo.AddClick(Sender: TObject);
Begin
  If Assigned(WorkflowSpellConfig) And (FActiveToken <> '') Then
    WorkflowSpellConfig.AddToPersonal(FActiveToken);
End;

Initialization

RegisterClass(TSpellMemo);

End.
