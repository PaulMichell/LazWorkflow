Unit AssistantSubagents;

{ Depth-1 subagent kinds, spawn policy, and review-lens prompts (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantConversation;

Const
  MaxLiveSubagents = 3;
  MaxSubagentToolRounds = 8;
  MaxSubagentRuntimeMs = 180000;
  SubagentSummaryMaxChars = 8000;

Type
  TSubagentKind = (
    sakExplore,
    sakPlan,
    sakGeneralPurpose,
    sakPascalNaming,
    sakPascalStructure,
    sakPascalReview
  );

  TSubagentRequest = Record
    Kind: TSubagentKind;
    Title: String;
    Prompt: String;
    Files: String;
  End;

Function SubagentKindName(Kind: TSubagentKind): String;
Function SubagentKindCaption(Kind: TSubagentKind): String;
Function ParseSubagentKind(Const Name: String): TSubagentKind;
Function TryParseSubagentKind(Const Name: String; Out Kind: TSubagentKind): Boolean;
Function SubagentModeForKind(Kind: TSubagentKind; ParentMode: TAssistantMode): TAssistantMode;
Function SubagentPersonaPrompt(Kind: TSubagentKind): String;
Function ParseSpawnSubagentArguments(Const ArgumentsJson: String; Out Request: TSubagentRequest;
  Out ErrorText: String): Boolean;
Function CanSpawnSubagent(IsParentSession: Boolean; LiveCount: Integer; Out ErrorText: String): Boolean;
Function BuildSubagentUserPrompt(Const Request: TSubagentRequest; Const CompileLog: String): String;
Function BuildReviewLensesPrompt(Const ChangedFiles: String): String;
Function SubagentRunningTitle(Const KindCaption, Phase: String): String;
Function SubagentFinishedTitle(Const KindCaption, Title: String): String;
Function FormatSubagentToolResult(Const KindName, Title, Summary: String; Ok: Boolean;
  DurationMs: Integer): String;
Function SubagentRunTimedOut(StartedTick, NowTick: QWord): Boolean;
Function IsReviewLensKind(Kind: TSubagentKind): Boolean;
Function ReviewLensAlreadyListed(Kind: TSubagentKind; Const KindNames: Array Of String;
  LastIndex: Integer): Boolean;
Function SubagentReasoningEffort(Const ParentEffort: String): String;
Function IsSpawnSubagentName(Const ToolName: String): Boolean;

Implementation

Uses
  fpjson, jsonparser, AssistantPlan;

Function IsSpawnSubagentName(Const ToolName: String): Boolean;
Begin
  Result := SameText(Trim(ToolName), 'spawn_subagent');
End;

Function SubagentRunTimedOut(StartedTick, NowTick: QWord): Boolean;
Begin
  Result := (StartedTick > 0) And (NowTick >= StartedTick) And
    ((NowTick - StartedTick) >= MaxSubagentRuntimeMs);
End;

Function IsReviewLensKind(Kind: TSubagentKind): Boolean;
Begin
  Result := Kind In [sakPascalNaming, sakPascalStructure, sakPascalReview];
End;

Function ReviewLensAlreadyListed(Kind: TSubagentKind; Const KindNames: Array Of String;
  LastIndex: Integer): Boolean;
Var
  I, Last: Integer;
  Name: String;
Begin
  Result := False;
  If Not IsReviewLensKind(Kind) Then
    Exit;
  Name := SubagentKindName(Kind);
  Last := LastIndex;
  If Last > High(KindNames) Then
    Last := High(KindNames);
  For I := 0 To Last Do
    If SameText(KindNames[I], Name) Then
      Begin
        Result := True;
        Exit;
      End;
End;

Function SubagentReasoningEffort(Const ParentEffort: String): String;
Var
  Effort: String;
Begin
  Effort := LowerCase(Trim(ParentEffort));
  If (Effort = 'xhigh') Or (Effort = 'x-high') Then
    Result := 'high'
  Else If Effort = '' Then
    Result := 'high'
  Else
    Result := Effort;
End;

Function SubagentKindName(Kind: TSubagentKind): String;
Begin
  Case Kind Of
    sakPlan: Result := 'plan';
    sakGeneralPurpose: Result := 'general-purpose';
    sakPascalNaming: Result := 'pascal-naming';
    sakPascalStructure: Result := 'pascal-structure';
    sakPascalReview: Result := 'pascal-review';
  Else
    Result := 'explore';
  End;
End;

Function SubagentKindCaption(Kind: TSubagentKind): String;
Begin
  Case Kind Of
    sakPlan: Result := 'Plan';
    sakGeneralPurpose: Result := 'General';
    sakPascalNaming: Result := 'Naming';
    sakPascalStructure: Result := 'Structure';
    sakPascalReview: Result := 'Review';
  Else
    Result := 'Explore';
  End;
End;

Function TryParseSubagentKind(Const Name: String; Out Kind: TSubagentKind): Boolean;
Var
  N: String;
Begin
  Result := True;
  N := LowerCase(Trim(Name));
  N := StringReplace(N, '_', '-', [rfReplaceAll]);
  If (N = '') Or (N = 'explore') Then
    Kind := sakExplore
  Else If N = 'plan' Then
    Kind := sakPlan
  Else If (N = 'general-purpose') Or (N = 'generalpurpose') Or (N = 'general') Then
    Kind := sakGeneralPurpose
  Else If (N = 'pascal-naming') Or (N = 'naming') Then
    Kind := sakPascalNaming
  Else If (N = 'pascal-structure') Or (N = 'structure') Then
    Kind := sakPascalStructure
  Else If (N = 'pascal-review') Or (N = 'review') Then
    Kind := sakPascalReview
  Else
    Begin
      Kind := sakExplore;
      Result := False;
    End;
End;

Function ParseSubagentKind(Const Name: String): TSubagentKind;
Begin
  If Not TryParseSubagentKind(Name, Result) Then
    Result := sakExplore;
End;

Function SubagentModeForKind(Kind: TSubagentKind; ParentMode: TAssistantMode): TAssistantMode;
Begin
  Case Kind Of
    sakPlan: Result := amPlan;
    sakGeneralPurpose: Result := ParentMode;
  Else
    Result := amChat;
  End;
End;

Function SubagentPersonaPrompt(Kind: TSubagentKind): String;
Begin
  Result := '<subagent>' + LineEnding;
  Case Kind Of
    sakPlan:
      Result := Result +
        'You are a depth-1 **plan** child of the Lazarus Project Assistant.' + LineEnding +
        AssistantPlanAuthoringRules + LineEnding +
        'Do not edit source (.pas/.lfm). Return a short summary of the plan file and sections you wrote.';
    sakGeneralPurpose:
      Result := Result +
        'You are a depth-1 **general-purpose** child with the parent session''s current mode tools.' + LineEnding +
        'Do the isolated chunk in the user prompt. Return what you changed and how to verify it.' + LineEnding +
        'You cannot spawn further subagents.';
    sakPascalNaming:
      Result := Result +
        'You are a read-only **pascal-naming** review lens.' + LineEnding +
        'Check Michell identifiers: PascalCase reserved words; `F` only on property storage fields; ' +
        'streamed form/frame components have no `F` prefix; no collisions with TControl/TForm members ' +
        '(Caption, Name, Text, Parent, Tag, Enabled, Visible, Color, Font, Width, Height, Edit, Tree).' + LineEnding +
        'Report file:line findings. Do not edit. Do not re-check syntax — that is the compiler.' + LineEnding +
        'Grep with glob `.pas`/`.lfm` and the files list; do not scan the whole tree without a glob.';
    sakPascalStructure:
      Result := Result +
        'You are a read-only **pascal-structure** review lens.' + LineEnding +
        'Check unit size (prefer under ~1000 lines), interface vs implementation Uses, form .pas/.lfm pairing, ' +
        'and foundation/service/bridge layering. Report file:line findings. Do not edit.' + LineEnding +
        'Grep with glob `.pas`/`.pp`/`.lfm` and the files list; do not scan the whole tree without a glob.';
    sakPascalReview:
      Result := Result +
        'You are a read-only **pascal-review** lens.' + LineEnding +
        'Check correctness, threading, memory (Assigned, FreeAndNil, no UI from workers), and whether the ' +
        'change actually fixes the request. If compiler messages are attached, treat them as ground truth ' +
        'for syntax — do not guess what lazbuild already said. Do not edit.';
  Else
    Result := Result +
      'You are a depth-1 **explore** child. Read-only: grep, read_file, list_directory, get_project_info.' + LineEnding +
      'Answer the research question with paths and line numbers. Do not edit files. Do not spawn children.';
  End;
  Result := Result + LineEnding +
    'You cannot call spawn_subagent. Return a structured summary the parent can merge.' + LineEnding +
    'Write in plain English. If you rank issues, use Blocking, Major, or Minor — never "Nit" or other review slang.' + LineEnding +
    '</subagent>';
End;

Function JsonStringOrEmpty(Obj: TJSONObject; Const FieldName: String): String;
Var
  Node: TJSONData;
Begin
  Result := '';
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(FieldName);
  If Not Assigned(Node) Then
    Exit;
  If Node.JSONType = jtNull Then
    Exit;
  If Node.JSONType = jtArray Then
    Result := Trim(TJSONArray(Node).AsJSON)
  Else
    Result := Trim(Node.AsString);
End;

Function ParseSpawnSubagentArguments(Const ArgumentsJson: String; Out Request: TSubagentRequest;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  KindName: String;
Begin
  Result := False;
  ErrorText := '';
  Request.Kind := sakExplore;
  Request.Title := '';
  Request.Prompt := '';
  Request.Files := '';
  If Trim(ArgumentsJson) = '' Then
    Begin
      ErrorText := 'spawn_subagent requires a JSON object with prompt.';
      Exit;
    End;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ArgumentsJson);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'spawn_subagent JSON is invalid: ' + E.Message;
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'spawn_subagent requires a JSON object.';
        Exit;
      End;
    Obj := TJSONObject(Data);
    KindName := JsonStringOrEmpty(Obj, 'kind');
    If KindName = '' Then
      KindName := JsonStringOrEmpty(Obj, 'subagent_type');
    If KindName = '' Then
      Request.Kind := sakExplore
    Else If Not TryParseSubagentKind(KindName, Request.Kind) Then
      Begin
        ErrorText := 'Unknown subagent kind "' + KindName +
          '". Use explore, plan, general-purpose, pascal-naming, pascal-structure, or pascal-review.';
        Exit;
      End;
    Request.Title := JsonStringOrEmpty(Obj, 'title');
    If Request.Title = '' Then
      Request.Title := JsonStringOrEmpty(Obj, 'description');
    If Request.Title = '' Then
      Request.Title := SubagentKindCaption(Request.Kind);
    Request.Prompt := JsonStringOrEmpty(Obj, 'prompt');
    Request.Files := JsonStringOrEmpty(Obj, 'files');
    If Request.Prompt = '' Then
      Begin
        ErrorText := 'spawn_subagent requires prompt.';
        Exit;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function CanSpawnSubagent(IsParentSession: Boolean; LiveCount: Integer; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Not IsParentSession Then
    Begin
      ErrorText := 'spawn_subagent is parent-only (depth 1). This child cannot spawn further agents.';
      Exit;
    End;
  If LiveCount >= MaxLiveSubagents Then
    Begin
      ErrorText := Format('Too many live subagents (%d). Max is %d.', [LiveCount, MaxLiveSubagents]);
      Exit;
    End;
  Result := True;
End;

Function BuildSubagentUserPrompt(Const Request: TSubagentRequest; Const CompileLog: String): String;
Begin
  Result := Trim(Request.Prompt);
  If Trim(Request.Files) <> '' Then
    Result := Result + LineEnding + LineEnding +
      'Focus on these files:' + LineEnding + Trim(Request.Files);
  If (Request.Kind = sakPascalReview) And (Trim(CompileLog) <> '') Then
    Result := Result + LineEnding + LineEnding +
      '----- begin last compile messages -----' + LineEnding +
      Trim(CompileLog) + LineEnding +
      '----- end last compile messages -----';
End;

Function BuildReviewLensesPrompt(Const ChangedFiles: String): String;
Var
  FilesBlock: String;
Begin
  If Trim(ChangedFiles) <> '' Then
    FilesBlock :=
      'Changed files:' + LineEnding + Trim(ChangedFiles)
  Else
    FilesBlock :=
      'No dirty editor buffers or git changes were detected. Review the active editor if present, ' +
      'or use grep / list_directory to choose files, then spawn the three lenses.';
  Result :=
    'Review the following changed files using spawn_subagent. In one tool round, spawn these three ' +
    'read-only lenses in parallel (depth 1, at most 3 live children). Do not edit files. Do not spawn ' +
    'further children. After they return, merge findings (dedupe, rank by severity) and report. ' +
    'Syntax comes from the compiler, not from a lens.' + LineEnding + LineEnding +
    'Lenses:' + LineEnding +
    '- kind pascal-naming — Michell identifiers, F prefix only on property storage, streamed component names, ' +
    'collisions with TControl/TForm members' + LineEnding +
    '- kind pascal-structure — unit size, interface/implementation split, form .lfm pairing, layering' + LineEnding +
    '- kind pascal-review — correctness, threading, memory, and whether the change actually fixes the request' +
    LineEnding + LineEnding +
    FilesBlock + LineEnding + LineEnding +
    'If a lens has nothing to say, it should say so briefly. Rank issues as Blocking, Major, or Minor — not Nit.';
End;

Function SubagentRunningTitle(Const KindCaption, Phase: String): String;
Var
  PhaseText: String;
Begin
  PhaseText := Trim(Phase);
  If PhaseText = '' Then
    PhaseText := 'Starting';
  Result := 'Subagent running: ' + Trim(KindCaption) + ' — ' + PhaseText;
End;

Function SubagentFinishedTitle(Const KindCaption, Title: String): String;
Begin
  Result := 'Subagent · ' + Trim(KindCaption);
  If (Trim(Title) <> '') And (Not SameText(Trim(Title), Trim(KindCaption))) Then
    Result := Result + ' — ' + Trim(Title);
End;

Function FormatSubagentToolResult(Const KindName, Title, Summary: String; Ok: Boolean;
  DurationMs: Integer): String;
Var
  Body: String;
Begin
  Body := Trim(Summary);
  If Length(Body) > SubagentSummaryMaxChars Then
    Body := Copy(Body, 1, SubagentSummaryMaxChars - 80) + LineEnding +
      '[… subagent summary truncated …]';
  If Body = '' Then
    Begin
      If Ok Then
        Body := '(no summary)'
      Else
        Body := '(failed)';
    End;
  Result :=
    Format('Subagent %s (%s) — %d ms', [KindName, BoolToStr(Ok, True), DurationMs]) + LineEnding +
    'Title: ' + Title + LineEnding + LineEnding +
    Body;
End;

End.
