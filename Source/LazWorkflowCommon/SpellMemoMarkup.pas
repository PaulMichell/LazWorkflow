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
Procedure SpellMemoDetach(Memo: TCustomMemo);
Function SpellMemoClientToByteIndex(Memo: TCustomMemo; Const Value: String; X, Y: Integer): Integer;
Procedure SpellMemoDrawWin32Waves(Memo: TCustomMemo; Const Value: String; Const Ranges: TSpellUnderlineRangeArray);

Implementation

Uses
  LazUTF8, LCLType, LCLIntf
  {$IFDEF LCLGTK3}, gtk3widgets, gtk3procs, LazGtk3, LazGdk3, LazPango1, LazPangoCairo1, LazCairo1,
    LazGObject2, LazGLib2{$ENDIF}
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
Const
  SpellOverlayKey = 'lazworkflow-spell-overlay';

Type
  TSpellGtk3Overlay = Class
    Ranges: TSpellUnderlineRangeArray;
    Body: String;
    SignalId: gulong;
  End;

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

Procedure Gtk3DrawSquiggle(Cr: Pcairo_t; View: PGtkTextView; Const StartIter, EndIter: TGtkTextIter);
Var
  Loc, EndLoc: TGdkRectangle;
  X1, Y1, X2, Y2: gint;
  Width: Double;
Begin
  gtk_text_view_get_iter_location(View, @StartIter, @Loc);
  gtk_text_view_get_iter_location(View, @EndIter, @EndLoc);
  gtk_text_view_buffer_to_window_coords(View, GTK_TEXT_WINDOW_TEXT, Loc.x, Loc.y + Loc.height, @X1, @Y1);
  gtk_text_view_buffer_to_window_coords(View, GTK_TEXT_WINDOW_TEXT, EndLoc.x, EndLoc.y + EndLoc.height, @X2, @Y2);
  If Y1 = Y2 Then
    Begin
      Width := X2 - X1;
      If Width < 4 Then
        Width := 4;
      cairo_set_source_rgb(Cr, 0.86, 0.10, 0.10);
      pango_cairo_show_error_underline(Cr, X1, Y1 - 2, Width, 3);
    End
  Else
    Begin
      cairo_set_source_rgb(Cr, 0.86, 0.10, 0.10);
      pango_cairo_show_error_underline(Cr, X1, Y1 - 2, 240, 3);
      If X2 > 0 Then
        pango_cairo_show_error_underline(Cr, 0, Y2 - 2, X2, 3);
    End;
End;

Function Gtk3SpellDraw(Widget: PGtkWidget; Cr: Pcairo_t; Data: gpointer): gboolean; CDecl;
Var
  Overlay: TSpellGtk3Overlay;
  View: PGtkTextView;
  Buffer: PGtkTextBuffer;
  StartIter, EndIter: TGtkTextIter;
  Index, CharStart, CharEnd: Integer;
Begin
  Result := False;
  Overlay := TSpellGtk3Overlay(Data);
  If Not Assigned(Overlay) Or (Length(Overlay.Ranges) = 0) Then
    Exit;
  View := PGtkTextView(Widget);
  Buffer := gtk_text_view_get_buffer(View);
  If Not Assigned(Buffer) Then
    Exit;
  For Index := 0 To High(Overlay.Ranges) Do
    Begin
      CharStart := SpellByteToCharOffset(Overlay.Body, Overlay.Ranges[Index].UTF8Start);
      CharEnd := SpellByteToCharOffset(Overlay.Body, Overlay.Ranges[Index].UTF8Start + Overlay.Ranges[Index].UTF8Length);
      gtk_text_buffer_get_iter_at_offset(Buffer, @StartIter, CharStart);
      gtk_text_buffer_get_iter_at_offset(Buffer, @EndIter, CharEnd);
      Gtk3DrawSquiggle(Cr, View, StartIter, EndIter);
    End;
End;

Function Gtk3EnsureOverlay(View: PGtkTextView): TSpellGtk3Overlay;
Begin
  Result := TSpellGtk3Overlay(g_object_get_data(PGObject(View), Pgchar(SpellOverlayKey)));
  If Assigned(Result) Then
    Exit;
  Result := TSpellGtk3Overlay.Create;
  Result.SignalId := g_signal_connect_data(PGObject(View), 'draw', TGCallback(@Gtk3SpellDraw), Result, Nil, [G_CONNECT_AFTER]);
  g_object_set_data(PGObject(View), Pgchar(SpellOverlayKey), Result);
End;

Procedure Gtk3DetachOverlay(View: PGtkTextView);
Var
  Overlay: TSpellGtk3Overlay;
Begin
  Overlay := TSpellGtk3Overlay(g_object_get_data(PGObject(View), Pgchar(SpellOverlayKey)));
  If Not Assigned(Overlay) Then
    Exit;
  If Overlay.SignalId <> 0 Then
    g_signal_handler_disconnect(PGObject(View), Overlay.SignalId);
  g_object_set_data(PGObject(View), Pgchar(SpellOverlayKey), Nil);
  Overlay.Free;
End;

Procedure Gtk3EnsureErrorTag(Buffer: PGtkTextBuffer);
Var
  Table: PGtkTextTagTable;
  Tag: PGtkTextTag;
Begin
  Table := gtk_text_buffer_get_tag_table(Buffer);
  If Not Assigned(Table) Then
    Exit;
  Tag := gtk_text_tag_table_lookup(Table, Pgchar(SpellErrorTagName));
  If Assigned(Tag) Then
    Exit;
  Tag := gtk_text_tag_new(Pgchar(SpellErrorTagName));
  { g_object_set also flips underline-set; g_object_set_property(G_TYPE_INT) does not. }
  g_object_set(PGObject(Tag), Pgchar('underline'), [gint(PANGO_UNDERLINE_ERROR), Pointer(Nil)]);
  gtk_text_tag_table_add(Table, Tag);
  g_object_unref(Tag);
End;

Function Gtk3ApplyUnderlines(Memo: TCustomMemo; Const Value: String; Const Ranges: TSpellUnderlineRangeArray): Boolean;
Var
  View: PGtkTextView;
  Buffer: PGtkTextBuffer;
  StartIter, EndIter: TGtkTextIter;
  Index, CharStart, CharEnd: Integer;
  Overlay: TSpellGtk3Overlay;
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
  Overlay := Gtk3EnsureOverlay(View);
  Overlay.Body := Value;
  Overlay.Ranges := Copy(Ranges);
  gtk_widget_queue_draw(PGtkWidget(View));
  Result := True;
End;

Procedure Gtk3ClearUnderlines(Memo: TCustomMemo);
Var
  View: PGtkTextView;
  Buffer: PGtkTextBuffer;
  StartIter, EndIter: TGtkTextIter;
  Overlay: TSpellGtk3Overlay;
Begin
  View := Gtk3TextView(Memo);
  If Not Assigned(View) Then
    Exit;
  Buffer := gtk_text_view_get_buffer(View);
  If Not Assigned(Buffer) Then
    Exit;
  gtk_text_buffer_get_bounds(Buffer, @StartIter, @EndIter);
  gtk_text_buffer_remove_tag_by_name(Buffer, Pgchar(SpellErrorTagName), @StartIter, @EndIter);
  Overlay := TSpellGtk3Overlay(g_object_get_data(PGObject(View), Pgchar(SpellOverlayKey)));
  If Assigned(Overlay) Then
    Begin
      SetLength(Overlay.Ranges, 0);
      Overlay.Body := '';
    End;
  gtk_widget_queue_draw(PGtkWidget(View));
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

Procedure SpellMemoDetach(Memo: TCustomMemo);
{$IFDEF LCLGTK3}
Var
  View: PGtkTextView;
{$ENDIF}
Begin
  If Not Assigned(Memo) Then
    Exit;
  {$IFDEF LCLGTK3}
  View := Gtk3TextView(Memo);
  If Assigned(View) Then
    Gtk3DetachOverlay(View);
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
