Unit AssistantCommands;

{ Command catalog: caption, category, slash alias, and prompt-token matching (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  TAssistantCatalogItem = Record
    Caption: String;
    Category: String;
    Slash: String;
    Aliases: String;
    Hint: String;
    Action: TObject;
    UserData: String;
  End;
  TAssistantCatalogItemArray = Array Of TAssistantCatalogItem;
  TCatalogIndexArray = Array Of Integer;

  TAssistantCatalog = Class
  Private
    FItems: TAssistantCatalogItemArray;
  Public
    Destructor Destroy; Override;
    Procedure Clear;
    Procedure Add(Const Caption, Category, Slash, Aliases, Hint: String;
      Action: TObject = Nil; Const UserData: String = '');
    Function Count: Integer;
    Function GetItem(Index: Integer): TAssistantCatalogItem;
    Function HasSlash(Const Slash: String): Boolean;
    Procedure Filter(Const Query: String; Out Hits: TCatalogIndexArray);
  End;

Function NormalizeSlashName(Const Token: String): String;
Function ExtractSlashToken(Const Text: String; Caret: Integer; Out TokenStart: Integer): String;
Function RemoveSlashToken(Var Text: String; Caret: Integer): Integer;
Function CatalogItemMatches(Const Item: TAssistantCatalogItem; Const Query: String): Boolean;
Function CatalogMatchRank(Const Item: TAssistantCatalogItem; Const Query: String): Integer;
Function FormatSlashAlias(Const Slash: String): String;
Function SlashListContains(Const List, Name: String): Boolean;

Implementation

Function IsTokenWhite(C: Char): Boolean;
Begin
  Result := C <= ' ';
End;

Function NormalizeSlashName(Const Token: String): String;
Begin
  Result := LowerCase(Trim(Token));
  While (Result <> '') And (Result[1] = '/') Do
    Delete(Result, 1, 1);
End;

Function SlashListContains(Const List, Name: String): Boolean;
Var
  Wrapped, Needle: String;
Begin
  Needle := NormalizeSlashName(Name);
  If Needle = '' Then
    Begin
      Result := False;
      Exit;
    End;
  Wrapped := ',' + StringReplace(LowerCase(Trim(List)), ' ', '', [rfReplaceAll]) + ',';
  Result := Pos(',' + Needle + ',', Wrapped) > 0;
End;

Function ExtractSlashToken(Const Text: String; Caret: Integer; Out TokenStart: Integer): String;
Var
  N, TokenEnd: Integer;
Begin
  Result := '';
  TokenStart := 0;
  N := Length(Text);
  If Caret < 0 Then
    Caret := 0;
  If Caret > N Then
    Caret := N;
  TokenEnd := Caret;
  While (TokenEnd < N) And (Not IsTokenWhite(Text[TokenEnd + 1])) Do
    Inc(TokenEnd);
  While (Caret > 0) And (Not IsTokenWhite(Text[Caret])) Do
    Dec(Caret);
  If (Caret < TokenEnd) And (Text[Caret + 1] = '/') Then
    Begin
      TokenStart := Caret + 1;
      Result := Copy(Text, TokenStart, TokenEnd - Caret);
    End;
End;

Function RemoveSlashToken(Var Text: String; Caret: Integer): Integer;
Var
  Token: String;
  TokenStart, TokenLen: Integer;
Begin
  Token := ExtractSlashToken(Text, Caret, TokenStart);
  If (Token = '') Or (TokenStart < 1) Then
    Begin
      Result := Caret;
      If Result > Length(Text) Then
        Result := Length(Text);
      Exit;
    End;
  TokenLen := Length(Token);
  Delete(Text, TokenStart, TokenLen);
  If (TokenStart > 1) And (TokenStart <= Length(Text) + 1) And
    (TokenStart - 1 <= Length(Text)) And (Text[TokenStart - 1] = ' ') And
    ((TokenStart > Length(Text)) Or (Text[TokenStart] = ' ') Or (Text[TokenStart] <= ' ')) Then
    Begin
      Delete(Text, TokenStart - 1, 1);
      Dec(TokenStart);
    End;
  Result := TokenStart - 1;
  If Result < 0 Then
    Result := 0;
End;

Function CatalogMatchRank(Const Item: TAssistantCatalogItem; Const Query: String): Integer;
Var
  Q, SlashName, CaptionLow: String;
Begin
  Q := NormalizeSlashName(Query);
  If Q = '' Then
    Begin
      Result := 50;
      Exit;
    End;
  SlashName := NormalizeSlashName(Item.Slash);
  CaptionLow := LowerCase(Item.Caption);
  If (SlashName <> '') And (SlashName = Q) Then
    Result := 0
  Else If SlashListContains(Item.Aliases, Q) Then
    Result := 1
  Else If (SlashName <> '') And (Pos(Q, SlashName) = 1) Then
    Result := 2
  Else If Pos(Q, CaptionLow) = 1 Then
    Result := 3
  Else If (SlashName <> '') And (Pos(Q, SlashName) > 0) Then
    Result := 4
  Else If Pos(Q, CaptionLow) > 0 Then
    Result := 5
  Else If Pos(Q, LowerCase(Item.Hint)) > 0 Then
    Result := 6
  Else If Pos(Q, LowerCase(Item.Aliases)) > 0 Then
    Result := 7
  Else
    Result := 100;
End;

Function CatalogItemMatches(Const Item: TAssistantCatalogItem; Const Query: String): Boolean;
Begin
  Result := CatalogMatchRank(Item, Query) < 100;
End;

Function FormatSlashAlias(Const Slash: String): String;
Var
  Name: String;
Begin
  Name := NormalizeSlashName(Slash);
  If Name = '' Then
    Result := ''
  Else
    Result := '/' + Name;
End;

Destructor TAssistantCatalog.Destroy;
Begin
  Clear;
  Inherited Destroy;
End;

Procedure TAssistantCatalog.Clear;
Begin
  SetLength(FItems, 0);
End;

Procedure TAssistantCatalog.Add(Const Caption, Category, Slash, Aliases, Hint: String;
  Action: TObject; Const UserData: String);
Var
  N: Integer;
  Item: TAssistantCatalogItem;
Begin
  If Trim(Caption) = '' Then
    Exit;
  Item.Caption := Trim(Caption);
  Item.Category := Trim(Category);
  Item.Slash := NormalizeSlashName(Slash);
  Item.Aliases := StringReplace(LowerCase(Trim(Aliases)), ' ', '', [rfReplaceAll]);
  Item.Hint := Trim(Hint);
  Item.Action := Action;
  Item.UserData := UserData;
  N := Length(FItems);
  SetLength(FItems, N + 1);
  FItems[N] := Item;
End;

Function TAssistantCatalog.Count: Integer;
Begin
  Result := Length(FItems);
End;

Function TAssistantCatalog.GetItem(Index: Integer): TAssistantCatalogItem;
Begin
  If (Index < 0) Or (Index > High(FItems)) Then
    Begin
      Result.Caption := '';
      Result.Category := '';
      Result.Slash := '';
      Result.Aliases := '';
      Result.Hint := '';
      Result.Action := Nil;
      Result.UserData := '';
    End
  Else
    Result := FItems[Index];
End;

Function TAssistantCatalog.HasSlash(Const Slash: String): Boolean;
Var
  I: Integer;
  Name: String;
Begin
  Result := False;
  Name := NormalizeSlashName(Slash);
  If Name = '' Then
    Exit;
  For I := 0 To High(FItems) Do
    If (FItems[I].Slash = Name) Or SlashListContains(FItems[I].Aliases, Name) Then
      Begin
        Result := True;
        Exit;
      End;
End;

Procedure TAssistantCatalog.Filter(Const Query: String; Out Hits: TCatalogIndexArray);
Var
  I, J, N, RankI, RankJ, Tmp: Integer;
  Q: String;
Begin
  Hits := Nil;
  Q := NormalizeSlashName(Query);
  SetLength(Hits, Length(FItems));
  N := 0;
  For I := 0 To High(FItems) Do
    If CatalogItemMatches(FItems[I], Q) Then
      Begin
        Hits[N] := I;
        Inc(N);
      End;
  SetLength(Hits, N);
  If (Q = '') Or (N < 2) Then
    Exit;
  For I := 1 To N - 1 Do
    Begin
      J := I;
      While J > 0 Do
        Begin
          RankI := CatalogMatchRank(FItems[Hits[J]], Q);
          RankJ := CatalogMatchRank(FItems[Hits[J - 1]], Q);
          If (RankI < RankJ) Or
            ((RankI = RankJ) And (CompareText(FItems[Hits[J]].Caption, FItems[Hits[J - 1]].Caption) < 0)) Then
            Begin
              Tmp := Hits[J - 1];
              Hits[J - 1] := Hits[J];
              Hits[J] := Tmp;
              Dec(J);
            End
          Else
            Break;
        End;
    End;
End;

End.
