Unit AssistantAcceptance;

{ Explicit machine-checkable validation; prose acceptance remains a human decision. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Const
  AssistantAcceptanceHumanReviewReason =
    'No explicit Validation: build or Validation: tests criterion; use Done after review.';

Function CheckAssistantAcceptance(Const Section, BuildJSON, TestJSON: String; Out Reason: String): Boolean;
{ True when Reason is the missing machine-validation result. Work on Plan keeps running. }
Function AssistantAcceptanceIsHumanReview(Const Reason: String): Boolean;

Implementation

Uses
  Classes, SysUtils, fpjson, jsonparser;

Function CheckAssistantAcceptance(Const Section, BuildJSON, TestJSON: String; Out Reason: String): Boolean;
Var
  Lines: TStringList;
  Build, Tests, Report: TJSONObject;
  I, Rules, FenceLength, N: Integer;
  Line, Rule: String;
  Fence: Char;
  Function ObjectJSON(Const Text: String): TJSONObject;
  Var
    Data: TJSONData;
  Begin
    Data := GetJSON(Text);
    If Not (Data Is TJSONObject) Then
      Begin
        Data.Free;
        Raise Exception.Create('Expected evidence object.');
      End;
    Result := TJSONObject(Data);
  End;
Begin
  Result := False;
  Reason := AssistantAcceptanceHumanReviewReason;
  Lines := TStringList.Create;
  Build := Nil;
  Tests := Nil;
  Try
    Lines.Text := Section;
    Rules := 0;
    Rule := '';
    Fence := #0;
    FenceLength := 0;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[I]);
        If (Copy(Line, 1, 3) = '```') Or (Copy(Line, 1, 3) = '~~~') Then
          Begin
            N := 1;
            While (N <= Length(Line)) And (Line[N] = Line[1]) Do Inc(N);
            Dec(N);
            If Fence = #0 Then
              Begin
                Fence := Line[1];
                FenceLength := N;
              End
            Else If (Line[1] = Fence) And (N >= FenceLength) And (Trim(Copy(Line, N + 1, MaxInt)) = '') Then Fence := #0;
            Continue;
          End;
        If Fence <> #0 Then Continue;
        If Pos('[ ]', Line) > 0 Then
          Begin
            Reason := 'Unchecked acceptance items require review; package stays in progress.';
            Exit;
          End;
        If SameText(Copy(Line, 1, 11), 'Validation:') Then
          Begin
            Inc(Rules);
            Rule := LowerCase(Trim(Copy(Line, 12, MaxInt)));
          End;
      End;
    If Rules = 0 Then
      Exit;
    If Rules <> 1 Then
      Begin
        Reason := 'More than one Validation line; the item stays in progress.';
        Exit;
      End;
    If (Rule <> 'build') And (Rule <> 'tests') Then
      Exit;
    Try
      Reason := 'A current successful build with complete CodeTools source coverage is required.';
      If BuildJSON = '' Then Exit;
      Build := ObjectJSON(BuildJSON);
      If (Build.Get('kind', '') <> 'build') Or Not Build.Get('done', False) Or Build.Get('stale', True) Or
        (Build.Get('outcome', '') <> 'compile_passed') Or (Build.Get('job_id', '') = '') Then Exit;
      If Not (Build.Find('dependencies') Is TJSONObject) Then Exit;
      If Not TJSONObject(Build.Find('dependencies')).Get('sourceClosureComplete', False) Then Exit;
      If Rule = 'tests' Then
        Begin
          Reason := 'Matching current tests with a passing FPCUnit report and sufficient executed tests are required.';
          If TestJSON = '' Then Exit;
          Tests := ObjectJSON(TestJSON);
          If (Tests.Get('kind', '') <> 'test') Or Not Tests.Get('done', False) Or Tests.Get('stale', True) Or
            (Tests.Get('outcome', '') <> 'test_command_passed') Or Not Tests.Get('testsRun', False) Or
            (Tests.Get('build_job_id', '') <> Build.Get('job_id', '')) Or (Tests.Get('job_id', '') = '') Then Exit;
          If Not (Tests.Find('testReport') Is TJSONObject) Then Exit;
          Report := TJSONObject(Tests.Find('testReport'));
          If (Report.Get('format', '') <> 'fpcunit-xml') Or Not Report.Get('valid', False) Or Not Report.Get('passed', False) Or
            (Report.Get('minimumTests', 0) < 1) Or (Report.Get('executed', 0) < Report.Get('minimumTests', 1)) Then Exit;
        End;
      Result := True;
      Reason := 'Validation: ' + Rule + ' satisfied by build ' + Build.Get('job_id', '');
      If Assigned(Tests) Then Reason := Reason + ' and test ' + Tests.Get('job_id', '');
      Reason := Reason + '. Source coverage uses CodeTools; compiler/runtime environment and prose requirements still need review.';
    Except On E: Exception Do
      Begin
        Result := False;
        Reason := 'Validation evidence is unavailable or malformed; use Done after review.';
      End;
    End;
  Finally
    Lines.Free;
    Build.Free;
    Tests.Free;
  End;
End;

Function AssistantAcceptanceIsHumanReview(Const Reason: String): Boolean;
Begin
  Result := Reason = AssistantAcceptanceHumanReviewReason;
End;

End.
