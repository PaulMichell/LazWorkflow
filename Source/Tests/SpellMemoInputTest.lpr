Program SpellMemoInputTest;
{$mode objfpc}{$H+}{$codepage utf8}

Uses
  cthreads, Interfaces, Forms, Controls, Classes, SysUtils, StdCtrls,
  LCLType, LazUTF8, Clipbrd, Menus, SpellMemo;

Type
  TInputMemo = Class(TSpellMemo)
  Public
    Procedure TypeText(Const Value: String);
    Procedure Press(Key: Word; Shift: TShiftState = []);
    Procedure CheckWrap(Const Value: String; AWidth: Integer);
    Procedure ApplyAmpersandSuggestion;
  End;

Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
End;

Procedure TInputMemo.TypeText(Const Value: String);
Var Offset, Count: Integer; Key: TUTF8Char;
Begin
  Offset := 1;
  While Offset <= Length(Value) Do
    Begin
      Count := UTF8CodepointSize(@Value[Offset]);
      Key := Copy(Value, Offset, Count);
      UTF8KeyPress(Key);
      Inc(Offset, Count);
    End;
End;

Procedure TInputMemo.Press(Key: Word; Shift: TShiftState);
Begin
  KeyDown(Key, Shift);
End;

Procedure TInputMemo.ApplyAmpersandSuggestion;
Var
  Menu: TPopupMenu;
  Item: TMenuItem;
Begin
  Text := 'wrod';
  SelStart := 1;
  LocateTokenAtCaret;
  Menu := TPopupMenu.Create(Self);
  Try
    Item := AddSpellSuggestion(Menu, 'AT&T');
    Check('caption escapes a literal ampersand', Item.Caption = 'AT&&T');
    Item.Caption := 'ATT';
    SuggestionClick(Item);
  Finally
    Menu.Free;
  End;
  Check('suggestion AT&T replaces the word', Text = 'AT&T');
End;

Procedure TInputMemo.CheckWrap(Const Value: String; AWidth: Integer);
Var
  ParaStart, ParaEnd, RowStart, Walk, CodeLen, BreakAt, LastSpace, MaxWidth: Integer;
Begin
  Width := AWidth;
  Text := Value;
  Canvas.Font := Font;
  MaxWidth := ClientWidth - 6;
  If MaxWidth < 20 Then MaxWidth := 20;
  ParaStart := 1;
  While ParaStart <= Length(Value) Do
    Begin
      ParaEnd := ParaStart;
      While (ParaEnd <= Length(Value)) And (Value[ParaEnd] <> #10) Do Inc(ParaEnd);
      RowStart := ParaStart;
      Repeat
        { Independent reference: the former sequential full-prefix measurement.
          Verify observable End-key positions, not the new fit implementation. }
        Walk := RowStart;
        BreakAt := 0;
        LastSpace := 0;
        While Walk < ParaEnd Do
          Begin
            CodeLen := UTF8CodepointSize(@Value[Walk]);
            If (Canvas.TextWidth(Copy(Value, RowStart, Walk + CodeLen - RowStart)) > MaxWidth)
              And (BreakAt > 0) Then
              Begin
                If LastSpace > 0 Then BreakAt := LastSpace;
                Break;
              End;
            BreakAt := Walk + CodeLen - RowStart;
            If Value[Walk] In [' ', #9] Then LastSpace := BreakAt;
            Inc(Walk, CodeLen);
          End;
        SelStart := UTF8Length(PChar(Value), RowStart - 1);
        Press(VK_END);
        Check('wrapped End position at width ' + IntToStr(AWidth) +
          ', byte ' + IntToStr(RowStart) + ', got ' + IntToStr(SelStart) +
          ', expected ' + IntToStr(UTF8Length(PChar(Value), RowStart + BreakAt - 1)),
          SelStart = UTF8Length(PChar(Value), RowStart + BreakAt - 1));
        Inc(RowStart, BreakAt);
      Until (RowStart >= ParaEnd) Or (BreakAt = 0);
      ParaStart := ParaEnd + 1;
    End;
  Check('wrapping preserves source', Text = Value);
End;

Const
  WrapWidths: Array[0..3] Of Integer = (42, 80, 177, 420);
Var
  Host: TForm;
  Memo: TInputMemo;
  Prompt, SavedClipboard: String;
  Started: QWord;
  WidthValue: Integer;
Begin
  Application.Initialize;
  Host := TForm.CreateNew(Nil);
  Try
    Host.SetBounds(100, 100, 1000, 400);
    Memo := TInputMemo.Create(Host);
    Memo.Parent := Host;
    Memo.UseSharedConfig := False;
    Memo.SetBounds(10, 10, 880, 220);
    Memo.ScrollBars := ssNone;
    Host.Show;
    Memo.SetFocus;
    Application.ProcessMessages;
    Prompt := 'INPUT ACCEPTANCE ';
    For WidthValue := 1 To 8 Do
      Prompt := Prompt + 'The quick brown fox tests the complete input buffer. ';
    Prompt := Prompt + ' END INPUT CHECK';
    Started := GetTickCount64;
    Memo.TypeText(Prompt);
    Check('complete rapid input', Memo.Text = Prompt);
    Check('caret at input end', Memo.SelStart = Length(Prompt));
    Memo.Press(VK_END); { Flush the pending layout before reporting time. }
    WriteLn('457-character input and final layout: ', GetTickCount64 - Started, ' ms');
    Check('navigation flush preserves caret', Memo.SelStart = Length(Prompt));
    For WidthValue In WrapWidths Do
      Begin
        Memo.CheckWrap(Prompt, WidthValue);
        Memo.CheckWrap('AVATAR office WAVE dj café naïve Ελληνικά 日本語 😀'+#10+
          #10+'word'+#9+'tab  trailing spaces  '+#10+
          'supercalifragilisticexpialidocious', WidthValue);
      End;
    WriteLn('ok wrapping agrees with full-prefix reference at four widths');

    Memo.Clear;
    Memo.TypeText('café 😀');
    Check('UTF-8 text and caret', (Memo.Text = 'café 😀') And (Memo.SelStart = 6));
    Memo.Press(VK_BACK);
    Check('backspace removes whole emoji', Memo.Text = 'café ');
    Memo.Press(VK_HOME);
    Memo.Press(VK_DELETE);
    Check('delete at start', Memo.Text = 'afé ');
    Memo.SelectAll;
    Memo.TypeText('new');
    Check('typing replaces selection', Memo.Text = 'new');
    Memo.ReadOnly := True;
    Memo.TypeText('ignored');
    Memo.Press(VK_BACK);
    Check('read-only rejects edits', Memo.Text = 'new');
    Memo.ReadOnly := False;

    Memo.Clear;
    Memo.TypeText('first'+#13+'second');
    Memo.Press(VK_HOME);
    Check('Home sees pending hard-newline layout', Memo.SelStart = 6);
    Memo.Press(VK_UP);
    Check('Up uses current paragraph geometry', Memo.SelStart = 0);
    Memo.Clear;
    Memo.TypeText('pending text');
    Memo.Text := 'replacement';
    Started := GetTickCount64;
    Repeat
      Application.ProcessMessages;
      Sleep(1);
    Until GetTickCount64 - Started >= 40;
    Check('pending timer cannot restore replaced text', Memo.Text = 'replacement');

    SavedClipboard := Clipboard.AsText;
    Try
      Clipboard.AsText := 'pasted café'+#13#10+'second line';
      Memo.SelectAll;
      Memo.PasteFromClipboard;
      Check('paste normalizes line endings', Memo.Text = 'pasted café'+#10+'second line');
      Memo.SelectAll;
      Memo.CopyToClipboard;
      Check('copy preserves UTF-8 and lines', Clipboard.AsText = Memo.Text);
    Finally
      Clipboard.AsText := SavedClipboard;
    End;
    Memo.WordWrap := False;
    Memo.Text := Prompt;
    Memo.Press(VK_HOME);
    Memo.Press(VK_END);
    Check('unwrapped End', Memo.SelStart = Length(Prompt));
    Memo.ApplyAmpersandSuggestion;
    Memo.TypeText(' pending at destruction');
    Memo.Free;
    Application.ProcessMessages;
    WriteLn('ok UTF-8, selection replacement, deletion, paste/copy and read-only input');
  Finally
    Host.Free;
  End;
End.
