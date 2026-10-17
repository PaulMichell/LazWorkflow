Program AssistantRecoverySettingsTest;

{ Load and save the four recovery settings. A missing key keeps the default. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, FileUtil, fpjson, jsonparser, Interfaces, WorkflowSettings, AssistantConfig;

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

Function SettingsPath: String;
Begin
  Result := IncludeTrailingPathDelimiter(WorkflowSettingsDirectory) + WorkflowSettingsFileName;
End;

Procedure RemoveRecoveryKeys;
Var
  Raw: String;
  Stream: TFileStream;
  Document, Section: TJSONObject;
Begin
  Stream := TFileStream.Create(SettingsPath, fmOpenRead);
  Try
    SetLength(Raw, Stream.Size);
    If Length(Raw) > 0 Then
      Stream.ReadBuffer(Raw[1], Length(Raw));
  Finally
    Stream.Free;
  End;
  Document := TJSONObject(GetJSON(Raw));
  Try
    Section := TJSONObject(Document.Find('assistant'));
    If Section.IndexOfName('reconnect_interval_seconds') >= 0 Then
      Section.Delete(Section.IndexOfName('reconnect_interval_seconds'));
    If Section.IndexOfName('credit_retry_minutes') >= 0 Then
      Section.Delete(Section.IndexOfName('credit_retry_minutes'));
    If Section.IndexOfName('automatic_continuations') >= 0 Then
      Section.Delete(Section.IndexOfName('automatic_continuations'));
    If Section.IndexOfName('fault_retries') >= 0 Then
      Section.Delete(Section.IndexOfName('fault_retries'));
    If Section.IndexOfName('auto_new_chat_at_limit') >= 0 Then
      Section.Delete(Section.IndexOfName('auto_new_chat_at_limit'));
    If Section.IndexOfName('plan_continue_new_chat') >= 0 Then
      Section.Delete(Section.IndexOfName('plan_continue_new_chat'));
    If Section.IndexOfName('new_chat_context_percent') >= 0 Then
      Section.Delete(Section.IndexOfName('new_chat_context_percent'));
    Raw := Document.AsJSON;
  Finally
    Document.Free;
  End;
  Stream := TFileStream.Create(SettingsPath, fmCreate);
  Try
    If Length(Raw) > 0 Then
      Stream.WriteBuffer(Raw[1], Length(Raw));
  Finally
    Stream.Free;
  End;
End;

Procedure TestRoundTrip(Const Root: String);
Var
  Config: TAssistantConfig;
Begin
  SetWorkflowSettingsDirectory(Root);
  Config := TAssistantConfig.Create;
  Try
    Config.ReconnectIntervalSeconds := 45;
    Config.CreditRetryMinutes := 15;
    Config.AutomaticContinuations := 7;
    Config.FaultRetries := 4;
    Config.AutoNewChatAtContextLimit := False;
    Config.NewChatContextPercent := 80;
    Config.Save;
  Finally
    Config.Free;
  End;
  Config := TAssistantConfig.Create;
  Try
    Config.Load;
    Check('reconnect interval loads', Config.ReconnectIntervalSeconds = 45);
    Check('credit retry loads', Config.CreditRetryMinutes = 15);
    Check('automatic continuations load', Config.AutomaticContinuations = 7);
    Check('fault retries load', Config.FaultRetries = 4);
    Check('new chat continuation loads', Config.AutoNewChatAtContextLimit = False);
    Check('new chat percent loads', Config.NewChatContextPercent = 80);
  Finally
    Config.Free;
  End;
  RemoveRecoveryKeys;
  Config := TAssistantConfig.Create;
  Try
    Config.Load;
    Check('missing reconnect key keeps 30 seconds', Config.ReconnectIntervalSeconds = AssistantReconnectIntervalDefault);
    Check('missing credit key keeps 60 minutes', Config.CreditRetryMinutes = AssistantCreditRetryDefault);
    Check('missing continuation key keeps 3', Config.AutomaticContinuations = AssistantContinuationDefault);
    Check('missing fault-retry key keeps 1', Config.FaultRetries = AssistantFaultRetryDefault);
    Check('missing new-chat key stays on', Config.AutoNewChatAtContextLimit);
    Check('missing context percent keeps 95', Config.NewChatContextPercent = AssistantNewChatContextDefault);
  Finally
    Config.Free;
  End;
End;

Var
  Root: String;
Begin
  FailCount := 0;
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-recovery-settings-' + FormatDateTime('hhnnsszzz', Now);
  ForceDirectories(ExcludeTrailingPathDelimiter(Root));
  Try
    TestRoundTrip(Root);
  Finally
    SetWorkflowSettingsDirectory('');
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False, True);
  End;
  If FailCount = 0 Then
    WriteLn('AssistantRecoverySettingsTest passed')
  Else
    Begin
      WriteLn(FailCount, ' failed');
      Halt(1);
    End;
End.
