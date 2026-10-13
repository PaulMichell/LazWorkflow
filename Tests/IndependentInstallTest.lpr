Program IndependentInstallTest;

{ Save repository, then assistant, and prove the first section remains.
  Linking Assistant settings does not register Suggest. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, fpjson,
  GitConfig, AssistantConfig, AssistantConnections, WorkflowEvents, WorkflowSettings;

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

Function MakeRoot: String;
Var
  Guid: TGuid;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-independent-' + GUIDToString(Guid);
  If Not ForceDirectories(Result) Then
    Raise Exception.Create('Could not create ' + Result);
  SetWorkflowSettingsDirectory(Result);
End;

Procedure RemoveRoot;
Var
  Path: String;
Begin
  Path := WorkflowSettingsDirectory;
  DeleteFile(Path + 'LazAssistantTools.xml');
  DeleteFile(Path + 'assistant-connections.ini');
  DeleteFile(Path + 'assistant-backend.ini');
  Path := WorkflowSettingsPath;
  If Path <> '' Then
    Begin
      DeleteFile(Path);
      DeleteFile(Path + '.tmp');
    End;
  Path := ExcludeTrailingPathDelimiter(WorkflowSettingsDirectory);
  SetWorkflowSettingsDirectory('');
  If Path <> '' Then
    RemoveDir(Path);
End;

Procedure PlantLegacy(Const FileName, Marker: String);
Var
  Lines: TStringList;
Begin
  Lines := TStringList.Create;
  Try
    Lines.Text := Marker;
    Lines.SaveToFile(WorkflowSettingsDirectory + FileName);
  Finally
    Lines.Free;
  End;
End;

Function FileText(Const FileName: String): String;
Var
  Lines: TStringList;
Begin
  Result := '';
  Lines := TStringList.Create;
  Try
    If FileExists(FileName) Then
      Lines.LoadFromFile(FileName);
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Procedure CheckIdeDocument;
Var
  Foreign: TJSONObject;
  Section: TJSONObject;
  ErrorText: String;
Begin
  Check('legacy assistant xml name is rejected', IsRejectedSettingsFileName('LazAssistantTools.xml'));
  Check('legacy grok xml name is rejected', IsRejectedSettingsFileName('LazGrokChat.xml'));
  Check('legacy repository xml name is rejected', IsRejectedSettingsFileName('LazRepositoryTools.xml'));
  Check('legacy git manager xml name is rejected', IsRejectedSettingsFileName('LazGitManager.xml'));
  Check('legacy spell xml name is rejected', IsRejectedSettingsFileName('LazWorkflowSpell.xml'));
  Check('legacy connections ini name is rejected', IsRejectedSettingsFileName('assistant-connections.ini'));
  Check('legacy backend ini name is rejected', IsRejectedSettingsFileName('assistant-backend.ini'));
  Check('current IDE document name is accepted', Not IsRejectedSettingsFileName(WorkflowSettingsFileName));
  PlantLegacy('LazAssistantTools.xml', 'legacy-marker-must-not-load');
  PlantLegacy('assistant-connections.ini', 'legacy-marker-must-not-load');
  PlantLegacy('assistant-backend.ini', 'legacy-marker-must-not-load');
  Section := ReadWorkflowSection('assistant');
  Check('legacy filenames are not read as the IDE document', Not Assigned(Section));
  Section.Free;
  Foreign := TJSONObject.Create;
  Try
    Foreign.Add('marker', 'keep-foreign');
    Check('foreign section can be written', WriteWorkflowSection('foreign', Foreign, ErrorText));
    If ErrorText <> '' Then
      WriteLn(ErrorText);
  Finally
    Foreign.Free;
  End;
End;

Procedure CheckRoundTrip;
Var
  Config: TGitConfig;
  Chat: TAssistantConfig;
  Connections: TAssistantConnections;
  Section: TJSONObject;
Begin
  Check('suggest starts disabled', Not SuggestCommitMessageAvailable);
  CheckIdeDocument;
  Config := TGitConfig.Create;
  Try
    Config.AutoRefresh := False;
    Config.AutoRefreshSeconds := 17;
    Config.GraphFontName := 'RoundTripFont';
    Config.GraphFontSize := 14;
    Config.Save;
  Finally
    Config.Free;
  End;

  Connections := TAssistantConnections.Create(WorkflowSettingsDirectory);
  Chat := TAssistantConfig.Create;
  Try
    Chat.IncludeIDEContext := True;
    Chat.AutoNewChatAtContextLimit := True;
    Chat.ShowThinking := False;
    Chat.ShowToolCalls := False;
    Chat.SearchMode := 'auto';
    Chat.SearchCitations := True;
    Chat.AnswerVerbosity := 'low';
    Chat.MaxOutputTokens := 4096;
    Connections.EnsureBuiltinGrok;
    Chat.SaveWithConnections(Connections);
  Finally
    Chat.Free;
    Connections.Free;
  End;

  Section := ReadWorkflowSection('repository');
  Try
    Check('repository section still present after assistant save', Assigned(Section));
    Check('repository auto_refresh kept', Assigned(Section) And (Not Section.Get('auto_refresh', True)));
    Check('repository interval kept', Assigned(Section) And (Section.Get('interval_sec', 0) = 17));
    Check('repository font kept', Assigned(Section) And (Section.Get('graph_font_name', '') = 'RoundTripFont'));
    Check('repository font size kept', Assigned(Section) And (Section.Get('graph_font_size', 0) = 14));
  Finally
    Section.Free;
  End;
  Section := ReadWorkflowSection('assistant');
  Try
    Check('assistant section present', Assigned(Section));
    Check('assistant include_ide_context written', Assigned(Section) And Section.Get('include_ide_context', False));
    Check('assistant auto_new_chat_at_limit written',
      Assigned(Section) And Section.Get('auto_new_chat_at_limit', False));
    Check('assistant show_thinking written', Assigned(Section) And (Not Section.Get('show_thinking', True)));
    Check('assistant show_tool_calls written', Assigned(Section) And (Not Section.Get('show_tool_calls', True)));
    Check('assistant search_mode written', Assigned(Section) And (Section.Get('search_mode', '') = 'auto'));
    Check('assistant search_citations written', Assigned(Section) And Section.Get('search_citations', False));
    Check('assistant answer_verbosity written', Assigned(Section) And (Section.Get('answer_verbosity', '') = 'low'));
    Check('assistant max_output_tokens written', Assigned(Section) And (Section.Get('max_output_tokens', 0) = 4096));
  Finally
    Section.Free;
  End;

  Config := TGitConfig.Create;
  Try
    Config.Load;
    Check('repository reload sees the saved interval', Config.AutoRefreshSeconds = 17);
    Config.AutoRefreshSeconds := 19;
    Config.Save;
  Finally
    Config.Free;
  End;
  Section := ReadWorkflowSection('assistant');
  Try
    Check('assistant section still present after repository save', Assigned(Section));
    Check('assistant include_ide_context kept', Assigned(Section) And Section.Get('include_ide_context', False));
  Finally
    Section.Free;
  End;
  Section := ReadWorkflowSection('repository');
  Try
    Check('second repository save wrote the new interval', Assigned(Section) And (Section.Get('interval_sec', 0) = 19));
  Finally
    Section.Free;
  End;
  Section := ReadWorkflowSection('foreign');
  Try
    Check('foreign section still present', Assigned(Section) And (Section.Get('marker', '') = 'keep-foreign'));
  Finally
    Section.Free;
  End;
  Check('legacy xml was not used as the IDE document',
    Pos('legacy-marker-must-not-load', FileText(WorkflowSettingsDirectory + 'LazAssistantTools.xml')) > 0);
  Check('legacy connection ini was not used as the IDE document',
    Pos('legacy-marker-must-not-load', FileText(WorkflowSettingsDirectory + 'assistant-connections.ini')) > 0);
  Check('suggest remains disabled without assistant registration', Not SuggestCommitMessageAvailable);
End;

Begin
  FailCount := 0;
  Try
    MakeRoot;
    Try
      CheckRoundTrip;
    Finally
      RemoveRoot;
    End;
  Except
    On E: Exception Do
      Begin
        WriteLn('FAIL ', E.ClassName, ': ', E.Message);
        ExitCode := 1;
        Exit;
      End;
  End;
  If FailCount = 0 Then
    WriteLn('PASS repository then assistant leaves the first section')
  Else
    Begin
      WriteLn('FAIL ', FailCount, ' checks');
      ExitCode := 1;
    End;
End.
