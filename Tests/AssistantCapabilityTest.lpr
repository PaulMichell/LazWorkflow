Program AssistantCapabilityTest;

{ Checks the turn-backend capability registry against today's matrix (c) 2026 Michell Computing.

  Lookup by grok, codex, and claude returns a set. openai-compatible is not a turn backend.
  No send path is called. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, AssistantCapabilities, AssistantGrokBackend, AssistantChatGPTBackend, AssistantClaudeBackend;

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

Function ExpectSet(Const BackendId: String): TAssistantCapabilitySet;
Begin
  Result := AbsentCapabilitySet;
  If BackendId = 'grok' Then
    Begin
      Result[acHarnessPrompt] := asNative;
      Result[acSkillsAndAgents] := asNative;
      Result[acSubagents] := asNative;
      Result[acTodoWrite] := asNative;
      Result[acImageInput] := asNative;
      Result[acImageOutput] := asNative;
      Result[acWebSearch] := asNative;
      Result[acSteer] := asNative;
      Result[acPhoneApproval] := asNative;
      Result[acContextCompaction] := asNative;
      Result[acEventsJSONL] := asNative;
      Result[acAccountUsage] := asNative;
      Result[acEffortControl] := asNative;
    End
  Else If BackendId = 'codex' Then
    Begin
      Result[acHarnessPrompt] := asNative;
      Result[acSkillsAndAgents] := asNative;
      Result[acTodoWrite] := asNative;
      Result[acImageInput] := asNative;
      Result[acSteer] := asNative;
      Result[acAccountUsage] := asNative;
      Result[acEffortControl] := asNative;
    End
  Else If BackendId = 'claude' Then
    Begin
      Result[acTodoWrite] := asNative;
      Result[acImageInput] := asNative;
      Result[acRevisionEdits] := asNative;
      Result[acAsyncWork] := asNative;
      Result[acEffortControl] := asNative;
    End;
End;

Procedure CheckBackend(Const BackendId, DisplayName: String);
Var
  Info: TAssistantBackendInfo;
  Support: TAssistantSupport;
  Capability: TAssistantCapability;
  Expected: TAssistantCapabilitySet;
Begin
  Check(BackendId + ' is registered', FindAssistantBackend(BackendId, Info));
  Check(BackendId + ' display name', Info.DisplayName = DisplayName);
  Check(BackendId + ' id', Info.Id = BackendId);
  Expected := ExpectSet(BackendId);
  For Capability := Low(TAssistantCapability) To High(TAssistantCapability) Do
    Begin
      Check(BackendId + ' ' + AssistantCapabilityName(Capability),
        AssistantCapabilitySupport(BackendId, Capability, Support) And (Support = Expected[Capability]));
      Check(BackendId + ' set ' + AssistantCapabilityName(Capability), Info.Support[Capability] = Expected[Capability]);
    End;
End;

Procedure CheckMissing(Const BackendId: String);
Var
  Info: TAssistantBackendInfo;
  Support: TAssistantSupport;
Begin
  Support := asNative;
  Check(BackendId + ' is not a turn backend', Not FindAssistantBackend(BackendId, Info));
  Check(BackendId + ' lookup leaves the id empty', Info.Id = '');
  Check(BackendId + ' support is unknown', Not AssistantCapabilitySupport(BackendId, acContextCompaction, Support));
  Check(BackendId + ' support is not invented', Support = asNative);
End;

Begin
  FailCount := 0;
  CheckBackend('grok', 'Grok');
  CheckBackend('codex', 'ChatGPT');
  CheckBackend('claude', 'Claude');
  CheckMissing('openai-compatible');
  CheckMissing('');
  CheckMissing('Grok');
  Check('unsupported sentence names the connection',
    AssistantUnsupportedSentence(acImageOutput, 'Claude') = 'Not available with this connection (Claude).');
  Check('unsupported sentence without a name',
    AssistantUnsupportedSentence(acSteer, '') = 'Not available with this connection.');
  If FailCount = 0 Then
    WriteLn('All capability lookups matched.')
  Else
    Begin
      WriteLn(FailCount, ' capability check(s) failed.');
      Halt(1);
    End;
End.
