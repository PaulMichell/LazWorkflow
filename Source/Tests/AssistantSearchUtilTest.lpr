Program AssistantSearchUtilTest;

{ Console checks for grep glob / regex detection and read_file ranges (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  SysUtils, AssistantSearchUtil;

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

Procedure TestRegexDetect;
Begin
  Check('plain text is not regex', Not PatternLooksLikeRegex('SurveyTitle'));
  Check('pipe is regex', PatternLooksLikeRegex('SurveyTitle|TitleEdit'));
  Check('escaped-dot pipe is regex', PatternLooksLikeRegex('ProjectSurvey\.SurveyTitle|dbo\.Project'));
End;

Procedure TestGlob;
Begin
  Check('empty matches all', FileMatchesSearchGlob('Main.pas', ''));
  Check('star matches all', FileMatchesSearchGlob('Main.pas', '*'));
  Check('dot-ext', FileMatchesSearchGlob('Main.pas', '.pas'));
  Check('bare ext', FileMatchesSearchGlob('Main.pas', 'pas'));
  Check('star-ext', FileMatchesSearchGlob('Main.pas', '*.pas'));
  Check('star-ext rejects other', Not FileMatchesSearchGlob('Main.lfm', '*.pas'));
  Check('brace pas', FileMatchesSearchGlob('Main.pas', '*.{pas,lfm,sql}'));
  Check('brace lfm', FileMatchesSearchGlob('ProjectManager.lfm', '*.{pas,lfm,sql}'));
  Check('brace sql', FileMatchesSearchGlob('TransferData.sql', '*.{pas,lfm,sql,inc,lrs}'));
  Check('brace rejects md', Not FileMatchesSearchGlob('Plan.md', '*.{pas,lfm}'));
  Check('basename', FileMatchesSearchGlob('/tmp/ProjectManager.pas', 'ProjectManager.pas'));
End;

Procedure TestReadRange;
Var
  StartLine, EndLine: Integer;
Begin
  StartLine := 470;
  EndLine := 180;
  ResolveReadLineRange(StartLine, EndLine, 0);
  Check('end_line as count start', StartLine = 470);
  Check('end_line as count last', EndLine = 649);

  StartLine := 580;
  EndLine := 630;
  ResolveReadLineRange(StartLine, EndLine, 0);
  Check('absolute end_line kept', EndLine = 630);

  StartLine := 1;
  EndLine := 0;
  ResolveReadLineRange(StartLine, EndLine, 80);
  Check('limit from start', EndLine = 80);

  StartLine := 100;
  EndLine := 9999;
  ResolveReadLineRange(StartLine, EndLine, 50);
  Check('limit wins over end_line', EndLine = 149);

  StartLine := 0;
  EndLine := 10;
  ResolveReadLineRange(StartLine, EndLine, 0);
  Check('zero start becomes 1', StartLine = 1);
End;

Begin
  FailCount := 0;
  TestRegexDetect;
  TestGlob;
  TestReadRange;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantSearchUtil tests passed.');
      Halt(0);
    End;
  WriteLn(FailCount, ' AssistantSearchUtil test(s) failed.');
  Halt(1);
End.
