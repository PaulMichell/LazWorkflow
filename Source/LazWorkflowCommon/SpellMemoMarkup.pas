Unit SpellMemoMarkup;

{ Widgetset spelling underlines for TSpellMemo (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Controls, StdCtrls, Graphics;

Const
  SpellErrorTagName = 'lazworkflow-spell-error';

Type
  TSpellUnderlineRange = Record
    UTF8Start: Integer;
    UTF8Length: Integer;
  End;
  TSpellUnderlineRangeArray = Array Of TSpellUnderlineRange;

Function SpellByteToCharOffset(Const Value: String; ByteIndex: Integer): Integer;
Function SpellCharToByteIndex(Const Value: String; CharOffset: Integer): Integer;
Function SpellMemoApplyUnderlines(Memo: TCustomMemo; Const Value: String; Const Ranges: TSpellUnderlineRangeArray): Boolean;
Procedure SpellMemoClearUnderlines(Memo: TCustomMemo);
Function SpellMemoClientToByteIndex(Memo: TCustomMemo; Const Value: String; X, Y: Integer): Integer;
Procedure SpellMemoDrawWin32Waves(Memo: TCustomMemo; Const Value: String; Const Ranges: TSpellUnderlineRangeArray);

Implementation

Uses
  LazUTF8, LCLType, LCLIntf
  {$IFDEF LCLGTK3}, gtk3widgets, gtk3procs, LazGtk3, LazPango1, LazGObject2, LazGLib2{$ENDIF}
  {$IFDEF LCLGTK2}, gtk2, glib2, gdk2, pango, gtk2def, gtk2proc{$ENDIF}
  {$IFDEF MSWINDOWS}, Windows, Messages{$ENDIF}
  ;

Function SpellByteToCharOffset(Const Value: String; ByteIndex: Integer): Integer;
Begin
  If ByteIndex <= 1 Then
    Result := 0
  Else If ByteIndex > Length(Value) + 1 Then
    Result := UTF8Length(Value)
  Else
    Result := UTF8Length(PChar(Value), ByteIndex - 1);
End;

Function SpellCharToByteIndex(Const Value: String; CharOffset: Integer): Integer;
Var
  P: PChar;
Begin
  If CharOffset <= 0 Then
    Begin
      Result := 1;
      Exit;
    End;
  P := UTF8CodepointStart(PChar(Value), Length(Value), CharOffset);
  If P = Nil Then
    Result := Length(Value) + 1
  Else
    Result := (P - PChar(Value)) + 1;
End;

{$IFDEF LCLGTK3}
Function Gtk3TextView(Memo: TCustomMemo): PGtkTextView;
Var
  Widget: TGtk3Widget;
Begin
  Result := Nil;
  If Not Assigned(Memo) Or (Not Memo.HandleAllocated) Then
    Exit;
  Widget := TGtk3Widget(Memo.Handle);
  If Not Assigned(Widget) Then
    Exit;
  Result := PGtkTextView(Widget.GetContainerWidget);
End;

Procedure Gtk3EnsureErrorTag(Buffer: PGtkTextBuffer);
Var
  Table: PGtkTextTagTable;
  Tag: PGtkTextTag;
  Value: TGValue;
Begin
  Table := gtk_text_buffer_get_tag_table(Buffer);
  If Not Assigned(Table) Then
    Exit;
  Tag := gtk_text_tag_table_lookup(Table, Pgchar(SpellErrorTagName));
  If Assigned(Tag) Then
    Exit;
  Tag := gtk_text_tag_new(Pgchar(SpellErrorTagName));
  FillChar(Value, SizeOf(Value), 0);
  g_value_init(@Value, G_TYPE_INT);
  g_value_set_int(@Value, gint(PANGO_UNDERLINE_ERROR));
  g_object_set_property(PGObject(Tag), Pgchar('underline'), @Value);
  g_value_unset(@Value);
  gtk_text_tag_table_add(Table, Tag);
  g_object_unref(Tag);
End;

Function Gtk3ApplyUnderlines(Memo: TCustomMemo; Const Value: String; Const Ranges: TSpellUnderlineRangeArray): Boolean;
Var
  View: PGtkTextView;
  Buffer: PGtkTextBuffer;
  StartIter, EndIter: TGtkTextIter;
  Index, CharStart, CharEnd: Integer;
Begin
  Result := False;
  View := Gtk3TextView(Memo);
  If Not Assigned(View) Then
    Exit;
  Buffer := gtk_text_view_get_buffer(View);
  If Not Assigned(Buffer) Then
    Exit;
  Gtk3EnsureErrorTag(Buffer);
  gtk_text_buffer_get_bounds(Buffer, @StartIter, @EndIter);
  gtk_text_buffer_remove_tag_by_name(Buffer, Pgchar(SpellErrorTagName), @StartIter, @EndIter);
  For Index := 0 To High(Ranges) Do
    Begin
      CharStart := SpellByteToCharOffset(Value, Ranges[Index].UTF8Start);
      CharEnd := SpellByteToCharOffset(Value, Ranges[Index].UTF8Start + Ranges[Index].UTF8Length);
      gtk_text_buffer_get_iter_at_offset(Buffer, @StartIter, CharStart);
      gtk_text_buffer_get_iter_at_offset(Buffer, @EndIter, CharEnd);
      gtk_text_buffer_apply_tag_by_name(Buffer, Pgchar(SpellErrorTagName), @StartIter, @EndIter);
    End;
  Result := True;
End;

Procedure Gtk3ClearUnderlines(Memo: TCustomMemo);
Var
  View: PGtkTextView;
  Buffer: PGtkTextBuffer;
  StartIter, EndIter: TGtkTextIter;
Begin
  View := Gtk3TextView(Memo);
  If Not Assigned(View) Then
    Exit;
  Buffer := gtk_text_view_get_buffer(View);
  If Not Assigned(Buffer) Then
    Exit;
  gtk_text_buffer_get_bounds(Buffer, @StartIter, @EndIter);
  gtk_text_buffer_remove_tag_by_name(Buffer, Pgchar(SpellErrorTagName), @StartIter, @EndIter);
End;

Function Gtk3ClientToByteIndex(Memo: TCustomMemo; Const Value: String; X, Y: Integer): Integer;
Var
  View: PGtkTextView;
  Iter: TGtkTextIter;
  BufX, BufY: gint;
Begin
  Result := Memo.SelStart + 1;
  View := Gtk3TextView(Memo);
  If Not Assigned(View) Then
    Exit;
  gtk_text_view_window_to_buffer_coords(View, GTK_TEXT_WINDOW_WIDGET, X, Y, @BufX, @BufY);
  gtk_text_view_get_iter_at_location(View, @Iter, BufX, BufY);
  Result := SpellCharToByteIndex(Value, gtk_text_iter_get_offset(@Iter));
End;
{$ENDIF}

{$IFDEF LCLGTK2}
Const
  Gtk2UnderlineError = 4;

Function Gtk2TextView(Memo: TCustomMemo): PGtkTextView;
Var
  Info: PWidgetInfo;
Begin
  Result := Nil;
  If Not Assigned(Memo) Or (Not Memo.HandleAllocated) Then
    Exit;
  Info := GetWidgetInfo(Pointer(Memo.Handle));
  If Assigned(Info) And Assigned(Info^.CoreWidget) Then
    Result := PGtkTextView(Info^.CoreWidget);
End;

Function Gtk2ApplyUnderlines(Memo: TCustomMemo; Const Value: String; Const Ranges: TSpellUnderlineRangeArray): Boolean;
Var
  View: PGtkTextView;
  Buffer: PGtkTextBuffer;
  Table: PGtkTextTagTable;
  Tag: PGtkTextTag;
  StartIter, EndIter: TGtkTextIter;
  Index, CharStart, CharEnd: Integer;
Begin
  Result := False;
  View := Gtk2TextView(Memo);
  If Not Assigned(View) Then
    Exit;
  Buffer := gtk_text_view_get_buffer(View);
  If Not Assigned(Buffer) Then
    Exit;
  Table := gtk_text_buffer_get_tag_table(Buffer);
  Tag := gtk_text_tag_table_lookup(Table, SpellErrorTagName);
  If Tag = Nil Then
    Begin
      Tag := gtk_text_tag_new(SpellErrorTagName);
      g_object_set(PGObject(Tag), PChar('underline'), [Gtk2UnderlineError, Pointer(Nil)]);
      gtk_text_tag_table_add(Table, Tag);
      g_object_unref(Tag);
    End;
  gtk_text_buffer_get_bounds(Buffer, @StartIter, @EndIter);
  gtk_text_buffer_remove_tag_by_name(Buffer, SpellErrorTagName, @StartIter, @EndIter);
  For Index := 0 To High(Ranges) Do
    Begin
      CharStart := SpellByteToCharOffset(Value, Ranges[Index].UTF8Start);
      CharEnd := SpellByteToCharOffset(Value, Ranges[Index].UTF8Start + Ranges[Index].UTF8Length);
      gtk_text_buffer_get_iter_at_offset(Buffer, @StartIter, CharStart);
      gtk_text_buffer_get_iter_at_offset(Buffer, @EndIter, CharEnd);
      gtk_text_buffer_apply_tag_by_name(Buffer, SpellErrorTagName, @StartIter, @EndIter);
    End;
  Result := True;
End;

Procedure Gtk2ClearUnderlines(Memo: TCustomMemo);
Var
  View: PGtkTextView;
  Buffer: PGtkTextBuffer;
  StartIter, EndIter: TGtkTextIter;
Begin
  View := Gtk2TextView(Memo);
  If Not Assigned(View) Then
    Exit;
  Buffer := gtk_text_view_get_buffer(View);
  If Not Assigned(Buffer) Then
    Exit;
  gtk_text_buffer_get_bounds(Buffer, @StartIter, @EndIter);
  gtk_text_buffer_remove_tag_by_name(Buffer, SpellErrorTagName, @StartIter, @EndIter);
End;

Function Gtk2ClientToByteIndex(Memo: TCustomMemo; Const Value: String; X, Y: Integer): Integer;
Var
  View: PGtkTextView;
  Iter: TGtkTextIter;
  BufX, BufY: gint;
Begin
  Result := Memo.SelStart + 1;
  View := Gtk2TextView(Memo);
  If Not Assigned(View) Then
    Exit;
  gtk_text_view_window_to_buffer_coords(View, GTK_TEXT_WINDOW_WIDGET, X, Y, @BufX, @BufY);
  gtk_text_view_get_iter_at_location(View, @Iter, BufX, BufY);
  Result := SpellCharToByteIndex(Value, gtk_text_iter_get_offset(@Iter));
End;
{$ENDIF}

Function SpellMemoApplyUnderlines(Memo: TCustomMemo; Const Value: String; Const Ranges: TSpellUnderlineRangeArray): Boolean;
Begin
  Result := False;
  If Not Assigned(Memo) Then
    Exit;
  {$IFDEF LCLGTK3}
  Result := Gtk3ApplyUnderlines(Memo, Value, Ranges);
  {$ENDIF}
  {$IFDEF LCLGTK2}
  Result := Gtk2ApplyUnderlines(Memo, Value, Ranges);
  {$ENDIF}
End;

Procedure SpellMemoClearUnderlines(Memo: TCustomMemo);
Begin
  If Not Assigned(Memo) Then
    Exit;
  {$IFDEF LCLGTK3}
  Gtk3ClearUnderlines(Memo);
  {$ENDIF}
  {$IFDEF LCLGTK2}
  Gtk2ClearUnderlines(Memo);
  {$ENDIF}
End;

Function SpellMemoClientToByteIndex(Memo: TCustomMemo; Const Value: String; X, Y: Integer): Integer;
Begin
  Result := 1;
  If Not Assigned(Memo) Then
    Exit;
  Result := SpellCharToByteIndex(Value, Memo.SelStart);
  {$IFDEF LCLGTK3}
  Result := Gtk3ClientToByteIndex(Memo, Value, X, Y);
  {$ENDIF}
  {$IFDEF LCLGTK2}
  Result := Gtk2ClientToByteIndex(Memo, Value, X, Y);
  {$ENDIF}
End;

Procedure SpellMemoDrawWin32Waves(Memo: TCustomMemo; Const Value: String; Const Ranges: TSpellUnderlineRangeArray);
{$IFDEF MSWINDOWS}
Const
  EmPosFromChar = 214;
Var
  DC: HDC;
  Index, CharStart, CharEnd: Integer;
  StartPt, EndPt: TSmallPoint;
  X, Y, X2: Integer;
  Saved: HGDIOBJ;
  PenHandle: HPEN;
Begin
  If Not Assigned(Memo) Or (Not Memo.HandleAllocated) Then
    Exit;
  DC := GetDC(Memo.Handle);
  If DC = 0 Then
    Exit;
  PenHandle := CreatePen(PS_SOLID, 1, RGB(220, 0, 0));
  Saved := SelectObject(DC, PenHandle);
  Try
    For Index := 0 To High(Ranges) Do
      Begin
        CharStart := SpellByteToCharOffset(Value, Ranges[Index].UTF8Start);
        CharEnd := SpellByteToCharOffset(Value, Ranges[Index].UTF8Start + Ranges[Index].UTF8Length);
        StartPt := TSmallPoint(SendMessage(Memo.Handle, EmPosFromChar, CharStart, 0));
        EndPt := TSmallPoint(SendMessage(Memo.Handle, EmPosFromChar, CharEnd, 0));
        X := StartPt.x;
        Y := StartPt.y + 12;
        X2 := EndPt.x;
        If X2 <= X Then
          Continue;
        MoveToEx(DC, X, Y, Nil);
        While X < X2 Do
          Begin
            If ((X - StartPt.x) Div 2) Mod 2 = 0 Then
              LineTo(DC, X + 2, Y + 2)
            Else
              LineTo(DC, X + 2, Y);
            Inc(X, 2);
          End;
      End;
  Finally
    SelectObject(DC, Saved);
    DeleteObject(PenHandle);
    ReleaseDC(Memo.Handle, DC);
  End;
End;
{$ELSE}
Begin
End;
{$ENDIF}

End.
