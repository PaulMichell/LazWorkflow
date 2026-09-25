Program AssistantOnlyInstall;

{ Assistant-only uses clause: Common, StyledText and Assistant units, no Repository units.
  Saving assistant leaves a repository section written through Common. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson,
  AssistantConfig, AssistantConnections, StyledTextTypes, WorkflowEvents, WorkflowSettings;

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

Procedure CheckAssistantSaveLeavesRepository;
Var
  Section: TJSONObject;
  ErrorText: String;
  Chat: TAssistantConfig;
  Connections: TAssistantConnections;
  Guid: TGuid;
  Root: String;
Begin
  Check('styled text linked without repository units', StyledInsets(4).Top = 4);
  Check('suggest stays disabled when assistant settings are linked but not registered',
    Not SuggestCommitMessageAvailable);
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-assistant-only-' + GUIDToString(Guid);
  If Not ForceDirectories(Root) Then
    Raise Exception.Create('Could not create ' + Root);
  SetWorkflowSettingsDirectory(Root);
  Try
    Section := TJSONObject.Create;
    Try
      Section.Add('marker', 'keep-repository');
      Section.Add('interval_sec', 42);
      Check('seed repository section without repository units', WriteWorkflowSection('repository', Section, ErrorText));
      If ErrorText <> '' Then
        WriteLn(ErrorText);
    Finally
      Section.Free;
    End;
    Connections := TAssistantConnections.Create(Root);
    Chat := TAssistantConfig.Create;
    Try
      Chat.IncludeIDEContext := True;
      Connections.EnsureBuiltinGrok;
      Chat.SaveWithConnections(Connections);
    Finally
      Chat.Free;
      Connections.Free;
    End;
    Section := ReadWorkflowSection('repository');
    Try
      Check('assistant save leaves the repository section', Assigned(Section));
      Check('assistant save leaves the repository marker',
        Assigned(Section) And (Section.Get('marker', '') = 'keep-repository'));
      Check('assistant save leaves the repository interval',
        Assigned(Section) And (Section.Get('interval_sec', 0) = 42));
    Finally
      Section.Free;
    End;
    Section := ReadWorkflowSection('assistant');
    Try
      Check('assistant section written by assistant save', Assigned(Section));
      Check('assistant include_ide_context written', Assigned(Section) And Section.Get('include_ide_context', False));
    Finally
      Section.Free;
    End;
  Finally
    DeleteFile(WorkflowSettingsPath);
    DeleteFile(WorkflowSettingsPath + '.tmp');
    SetWorkflowSettingsDirectory('');
    RemoveDir(ExcludeTrailingPathDelimiter(Root));
  End;
End;

Begin
  FailCount := 0;
  Try
    CheckAssistantSaveLeavesRepository;
  Except
    On E: Exception Do
      Begin
        WriteLn('FAIL ', E.ClassName, ': ', E.Message);
        ExitCode := 1;
        Exit;
      End;
  End;
  If FailCount = 0 Then
    WriteLn('PASS assistant-only install leaves the repository section')
  Else
    Begin
      WriteLn('FAIL ', FailCount, ' checks');
      ExitCode := 1;
    End;
End.
