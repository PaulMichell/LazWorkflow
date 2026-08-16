Unit GitDiffHighlighter;

{ Mixed Diff+language highlighter and overview gutter markers (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Graphics, SynEdit, SynHighlighterDiff, SynGutterLineOverview,
  LazEditHighlighter, LazEditTextAttributes, GitDiffPatch;

Type
  { Real TSynDiffSyn so SynEdit fold/markup stay valid; language HL only on context lines. }
  TGitMixedDiffHighlighter = Class(TSynDiffSyn)
  Private
    Lang: TLazEditCustomHighlighter; { not owned }
    FContextMode: Boolean;
    FPrefixDone: Boolean;
    FAtEol: Boolean;
    FPrefixLen: Integer;
    FPrefixStr: String;
  Public
    Procedure SetLanguageBackend(ALang: TLazEditCustomHighlighter);
    Procedure InitForScanningLine; Override;
    Procedure Next; Override;
    Function GetEol: Boolean; Override;
    Function GetToken: String; Override;
    Function GetTokenPos: Integer; Override;
    Function GetTokenKind: Integer; Override;
    Procedure GetTokenEx(Out TokenStart: PChar; Out TokenLength: Integer); Override;
    Function GetTokenAttribute: TLazEditTextAttribute; Override;
  End;

  { Right-gutter overview markers: green for added lines, red for removed. }
  TGitDiffOverviewProvider = Class(TSynGutterLineOverviewProvider)
  Private
    FColorAdded: TColor;
    FColorRemoved: TColor;
    RGBAdded: TColor;
    RGBRemoved: TColor;
    Procedure SetColorAdded(Const NewColor: TColor);
    Procedure SetColorRemoved(Const NewColor: TColor);
  Protected
    Procedure Paint(Canvas: TCanvas; AClip: TRect; TopOffset: Integer); Override;
  Public
    Constructor Create(AOwner: TComponent); Override;
    Property ColorAdded: TColor Read FColorAdded Write SetColorAdded;
    Property ColorRemoved: TColor Read FColorRemoved Write SetColorRemoved;
  End;

Implementation

Uses
  Types, Math;

Procedure TGitMixedDiffHighlighter.SetLanguageBackend(ALang: TLazEditCustomHighlighter);
Begin
  Lang := ALang;
  FContextMode := False;
End;

Procedure TGitMixedDiffHighlighter.InitForScanningLine;
Var
  LineText, Body: String;
Begin
  { Always run Diff init first so fold/range state stays consistent. Skipping this
    left fRange stale and caused access violations on subsequent lines. }
  FContextMode := False;
  FPrefixDone := True;
  FPrefixLen := 0;
  FPrefixStr := '';
  FAtEol := False;
  Inherited;

  If Not Assigned(Lang) Then
    Exit;
  LineText := CurrentLineText;
  If Not LineIsDiffContext(LineText) Then
    Exit;

  Try
    If (Length(LineText) > 0) And (LineText[1] = ' ') Then
      Begin
        FPrefixLen := 1;
        FPrefixStr := ' ';
        FPrefixDone := False;
        Body := Copy(LineText, 2, MaxInt);
      End
    Else
      Body := LineText;
    { Private language instance only: line index 0 => ResetRange, no CurrentRanges. }
    Lang.SetAlternativeLineTextForGetTokens(Body, 0);
    FContextMode := True;
    FAtEol := False;
    If FPrefixDone And Lang.GetEol Then
      FAtEol := True;
  Except
    { Fall back to Diff tokens already set up by Inherited (this line only). }
    FContextMode := False;
  End;
End;

Procedure TGitMixedDiffHighlighter.Next;
Begin
  If Not FContextMode Then
    Begin
      Inherited;
      Exit;
    End;
  If FAtEol Then
    Exit;
  Try
    If Not FPrefixDone Then
      Begin
        FPrefixDone := True;
        If (Not Assigned(Lang)) Or Lang.GetEol Then
          FAtEol := True;
        Exit;
      End;
    If Not Assigned(Lang) Then
      Begin
        FAtEol := True;
        Exit;
      End;
    Lang.Next;
    If Lang.GetEol Then
      FAtEol := True;
  Except
    FAtEol := True;
    FContextMode := False;
  End;
End;

Function TGitMixedDiffHighlighter.GetEol: Boolean;
Begin
  If FContextMode Then
    Result := FAtEol
  Else
    Result := Inherited GetEol;
End;

Function TGitMixedDiffHighlighter.GetToken: String;
Begin
  If Not FContextMode Then
    Exit(Inherited GetToken);
  Try
    If Not FPrefixDone Then
      Result := FPrefixStr
    Else If Assigned(Lang) Then
      Result := Lang.GetToken
    Else
      Result := Inherited GetToken;
  Except
    Result := Inherited GetToken;
  End;
End;

Function TGitMixedDiffHighlighter.GetTokenPos: Integer;
Begin
  If Not FContextMode Then
    Exit(Inherited GetTokenPos);
  Try
    If Not FPrefixDone Then
      Result := 0
    Else If Assigned(Lang) Then
      Result := Lang.GetTokenPos + FPrefixLen
    Else
      Result := Inherited GetTokenPos;
  Except
    Result := Inherited GetTokenPos;
  End;
End;

Function TGitMixedDiffHighlighter.GetTokenKind: Integer;
Begin
  If Not FContextMode Then
    Exit(Inherited GetTokenKind);
  Try
    If Not FPrefixDone Then
      Result := 0
    Else If Assigned(Lang) Then
      Result := Lang.GetTokenKind
    Else
      Result := Inherited GetTokenKind;
  Except
    Result := Inherited GetTokenKind;
  End;
End;

Procedure TGitMixedDiffHighlighter.GetTokenEx(Out TokenStart: PChar; Out TokenLength: Integer);
Begin
  If Not FContextMode Then
    Begin
      Inherited GetTokenEx(TokenStart, TokenLength);
      Exit;
    End;
  Try
    If Not FPrefixDone Then
      Begin
        TokenStart := PChar(FPrefixStr);
        TokenLength := FPrefixLen;
      End
    Else If Assigned(Lang) Then
      Lang.GetTokenEx(TokenStart, TokenLength)
    Else
      Inherited GetTokenEx(TokenStart, TokenLength);
  Except
    Inherited GetTokenEx(TokenStart, TokenLength);
  End;
End;

Function TGitMixedDiffHighlighter.GetTokenAttribute: TLazEditTextAttribute;
Begin
  If Not FContextMode Then
    Exit(Inherited GetTokenAttribute);
  Try
    If Not FPrefixDone Then
      Result := LineContextAttri
    Else If Assigned(Lang) Then
      Begin
        Result := Lang.GetTokenAttribute;
        If Result = Nil Then
          Result := LineContextAttri;
      End
    Else
      Result := Inherited GetTokenAttribute;
  Except
    Result := LineContextAttri;
  End;
End;

Constructor TGitDiffOverviewProvider.Create(AOwner: TComponent);
Begin
  Inherited Create(AOwner);
  ColorAdded := RGBToColor(76, 175, 80);
  ColorRemoved := RGBToColor(229, 57, 53);
  Priority := 10;
End;

Procedure TGitDiffOverviewProvider.SetColorAdded(Const NewColor: TColor);
Begin
  If FColorAdded = NewColor Then
    Exit;
  FColorAdded := NewColor;
  RGBAdded := TColor(ColorToRGB(NewColor));
  DoChange(Self);
End;

Procedure TGitDiffOverviewProvider.SetColorRemoved(Const NewColor: TColor);
Begin
  If FColorRemoved = NewColor Then
    Exit;
  FColorRemoved := NewColor;
  RGBRemoved := TColor(ColorToRGB(NewColor));
  DoChange(Self);
End;

Procedure TGitDiffOverviewProvider.Paint(Canvas: TCanvas; AClip: TRect; TopOffset: Integer);
Var
  LineNo, Y1, Y2, Count, ClipTop, ClipBottom: Integer;
  LineText: String;
  R: TRect;
  IsAdd, IsDel: Boolean;
Begin
  If (SynEdit = Nil) Or (SynEdit.Lines = Nil) Then
    Exit;
  Count := SynEdit.Lines.Count;
  If Count < 1 Then
    Exit;

  ClipTop := AClip.Top - TopOffset;
  ClipBottom := AClip.Bottom - TopOffset;
  R := AClip;
  R.Left := AClip.Left + Max(1, (AClip.Right - AClip.Left) Div 4);
  R.Right := AClip.Right - Max(1, (AClip.Right - AClip.Left) Div 4);

  For LineNo := 1 To Count Do
    Begin
      LineText := SynEdit.Lines[LineNo - 1];
      IsAdd := LineIsDiffAdded(LineText);
      IsDel := LineIsDiffRemoved(LineText);
      If Not (IsAdd Or IsDel) Then
        Continue;

      Y1 := TextLineToPixel(LineNo);
      Y2 := TextLineToPixelEnd(LineNo);
      If Y2 < Y1 Then
        Y2 := Y1;
      If (Y2 < ClipTop) Or (Y1 > ClipBottom) Then
        Continue;

      R.Top := Y1 + TopOffset;
      R.Bottom := Max(Y1 + 1, Y2) + TopOffset + 1;
      If IsAdd Then
        Canvas.Brush.Color := RGBAdded
      Else
        Canvas.Brush.Color := RGBRemoved;
      Canvas.FillRect(R);
    End;
End;

End.
