Program AssistantCommandsTest;

{ Console checks for slash-token parse and command-catalog matching (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, AssistantCommands;

Var
  FailCount: Integer;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure TestNormalize;
Begin
  Check('strip slash', NormalizeSlashName('/Compact') = 'compact');
  Check('trim', NormalizeSlashName('  /New  ') = 'new');
  Check('bare', NormalizeSlashName('context') = 'context');
  Check('empty', NormalizeSlashName('///') = '');
End;

Procedure TestExtract;
Var
  Token: String;
  StartAt: Integer;
Begin
  Token := ExtractSlashToken('/compact', 8, StartAt);
  Check('whole token', Token = '/compact');
  Check('whole start', StartAt = 1);

  Token := ExtractSlashToken('/co', 3, StartAt);
  Check('partial', Token = '/co');

  Token := ExtractSlashToken('hello /rev', 10, StartAt);
  Check('after words', Token = '/rev');
  Check('after words start', StartAt = 7);

  Token := ExtractSlashToken('hello', 5, StartAt);
  Check('no slash', Token = '');

  Token := ExtractSlashToken('foo /bar baz', 8, StartAt);
  Check('caret in token', Token = '/bar');

  Token := ExtractSlashToken('/', 1, StartAt);
  Check('bare slash', Token = '/');
End;

Procedure TestRemove;
Var
  Text: String;
  Caret: Integer;
Begin
  Text := '/compact';
  Caret := RemoveSlashToken(Text, 8);
  Check('remove only token', Text = '');
  Check('remove caret home', Caret = 0);

  Text := 'hello /rev';
  Caret := RemoveSlashToken(Text, 10);
  Check('remove keeps prefix', Text = 'hello');
  Check('remove caret after prefix', Caret = 5);
End;

Procedure TestMatch;
Var
  Item: TAssistantCatalogItem;
  Catalog: TAssistantCatalog;
  Hits: TCatalogIndexArray;
Begin
  Item := Default(TAssistantCatalogItem);
  Item.Caption := 'New Chat';
  Item.Slash := 'new';
  Item.Aliases := 'clear';
  Item.Hint := 'Start a new conversation';
  Check('exact slash', CatalogMatchRank(Item, 'new') = 0);
  Check('alias', SlashListContains(Item.Aliases, 'clear'));
  Check('alias matches', CatalogItemMatches(Item, 'clear'));
  Check('caption sub', CatalogItemMatches(Item, 'chat'));
  Check('no match', Not CatalogItemMatches(Item, 'rewind'));
  Check('format', FormatSlashAlias('New') = '/new');

  Catalog := TAssistantCatalog.Create;
  Try
    Catalog.Add('New Chat', 'Session', 'new', 'clear', 'Start a new conversation');
    Catalog.Add('Compact context', 'Session', 'compact', '', 'Shrink older turns');
    Catalog.Add('Review Changes', 'Review', 'review', '', 'Pascal lenses');
    Check('has new', Catalog.HasSlash('/new'));
    Check('has clear alias', Catalog.HasSlash('clear'));
    Check('no missing', Not Catalog.HasSlash('rewind'));
    Catalog.Filter('comp', Hits);
    Check('filter one', Length(Hits) = 1);
    Check('filter compact', Catalog.GetItem(Hits[0]).Slash = 'compact');
    Catalog.Filter('', Hits);
    Check('empty filter all', Length(Hits) = 3);
    Catalog.Filter('new', Hits);
    Check('exact first', (Length(Hits) >= 1) And (Catalog.GetItem(Hits[0]).Slash = 'new'));
  Finally
    Catalog.Free;
  End;
End;

Begin
  FailCount := 0;
  TestNormalize;
  TestExtract;
  TestRemove;
  TestMatch;
  WriteLn;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantCommands tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' test(s) failed.');
      Halt(1);
    End;
End.
