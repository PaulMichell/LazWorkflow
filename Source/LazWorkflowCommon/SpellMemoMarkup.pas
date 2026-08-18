Unit SpellMemoMarkup;

{ Portable Canvas helpers for TSpellMemo (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Graphics;

Type
  TSpellUnderlineRange = Record
    UTF8Start: Integer;
    UTF8Length: Integer;
  End;
  TSpellUnderlineRangeArray = Array Of TSpellUnderlineRange;

Function SpellByteToCharOffset(Const Value: String; ByteIndex: Integer): Integer;
Function SpellCharToByteIndex(Const Value: String; CharOffset: Integer): Integer;
Procedure DrawErrorUnderline(Canvas: TCanvas; X1, X2, Y: Integer);

Implementation

Uses
  LazUTF8;

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

Procedure DrawErrorUnderline(Canvas: TCanvas; X1, X2, Y: Integer);
Var
  X, Mid: Integer;
  Down: Boolean;
Begin
  If X2 < X1 + 2 Then
    X2 := X1 + 2;
  Canvas.Pen.Color := clRed;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Style := psSolid;
  Canvas.MoveTo(X1, Y);
  X := X1;
  Down := True;
  Mid := 2;
  While X < X2 Do
    Begin
      If Down Then
        Canvas.LineTo(X + Mid, Y + Mid)
      Else
        Canvas.LineTo(X + Mid, Y);
      Inc(X, Mid);
      Down := Not Down;
    End;
End;

End.
