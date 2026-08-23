Unit AssistantSession;

{ Per-project Project Chat session persistence (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantService;

Const
  AssistantSessionFileName = '.lazgrokchat-session';
  AssistantSessionFormatVersion = 2;

Function ActiveProjectSessionPath: String;
Function SaveProjectChatSession(Transcript: TStrings; ContextUsed: Integer): Boolean;
Function LoadProjectChatSession(Transcript: TStrings; Out ContextUsed: Integer): Boolean;
Procedure ClearProjectChatSession;

Implementation

Uses
  LazFileUtils, LazIDEIntf, ProjectIntf, WorkflowLog, fpjson, jsonparser;

Function ActiveProjectSessionPath: String;
Var
  Proj: TLazProject;
  Dir: String;
Begin
  Result := '';
  If Not Assigned(LazarusIDE) Then
    Exit;
  Proj := LazarusIDE.ActiveProject;
  If Not Assigned(Proj) Then
    Exit;
  Dir := '';
  If Assigned(Proj.MainFile) And (Proj.MainFile.Filename <> '') Then
    Dir := ExtractFilePath(ExpandFileName(Proj.MainFile.Filename));
  If Dir = '' Then
    Dir := ExtractFilePath(ExpandFileName(Proj.ProjectInfoFile));
  If Dir = '' Then
    Exit;
  Result := IncludeTrailingPathDelimiter(Dir) + AssistantSessionFileName;
End;

Function RoleToTag(Role: TAssistantMessageRole): String;
Begin
  Case Role Of
    amrSystem: Result := 'system';
    amrUser: Result := 'user';
    amrAssistant: Result := 'assistant';
    amrTool: Result := 'tool';
  Else
    Result := 'user';
  End;
End;

Function TagToRole(Const Tag: String): TAssistantMessageRole;
Var
  T: String;
Begin
  T := LowerCase(Trim(Tag));
  If T = 'system' Then
    Result := amrSystem
  Else If T = 'assistant' Then
    Result := amrAssistant
  Else If T = 'tool' Then
    Result := amrTool
  Else
    Result := amrUser;
End;

Function SaveProjectChatSession(Transcript: TStrings; ContextUsed: Integer): Boolean;
Var
  Path: String;
  Root: TJSONObject;
  TranscriptArr, MessagesArr: TJSONArray;
  MsgObj: TJSONObject;
  OutList: TStringList;
  I: Integer;
  Role: TAssistantMessageRole;
  Content, ToolCallId, ToolCallsJson: String;
Begin
  Result := False;
  Path := ActiveProjectSessionPath;
  If Path = '' Then
    Exit;
  Root := TJSONObject.Create;
  Try
    Root.Add('format', 'LazAssistantTools-Session');
    Root.Add('version', AssistantSessionFormatVersion);
    Root.Add('contextUsed', ContextUsed);
    TranscriptArr := TJSONArray.Create;
    Root.Add('transcript', TranscriptArr);
    If Assigned(Transcript) Then
      For I := 0 To Transcript.Count - 1 Do
        TranscriptArr.Add(Transcript[I]);
    MessagesArr := TJSONArray.Create;
    Root.Add('messages', MessagesArr);
    If Assigned(AssistantClient) Then
      For I := 0 To AssistantClient.MessageCount - 1 Do
        If AssistantClient.GetMessage(I, Role, Content, ToolCallId, ToolCallsJson) Then
          Begin
            MsgObj := TJSONObject.Create;
            MsgObj.Add('role', RoleToTag(Role));
            MsgObj.Add('content', Content);
            If ToolCallId <> '' Then
              MsgObj.Add('toolCallId', ToolCallId);
            If ToolCallsJson <> '' Then
              MsgObj.Add('toolCallsJson', ToolCallsJson);
            MessagesArr.Add(MsgObj);
          End;
    Try
      OutList := TStringList.Create;
      Try
        OutList.Text := Root.FormatJSON;
        OutList.SaveToFile(Path);
      Finally
        OutList.Free;
      End;
      Result := True;
      WorkflowLogger.Info('AssistantSession', 'Saved session to ' + Path);
    Except
      On E: Exception Do
        WorkflowLogger.Warning('AssistantSession', 'Save failed: ' + E.Message);
    End;
  Finally
    Root.Free;
  End;
End;

Function LoadProjectChatSession(Transcript: TStrings; Out ContextUsed: Integer): Boolean;
Var
  Path: String;
  Lines: TStringList;
  I: Integer;
  Line, RoleTag, Content, ToolCallId, ToolCallsJson: String;
  Section: String;
  Data: TJSONData;
  Root, MsgObj: TJSONObject;
  Arr: TJSONArray;
Begin
  Result := False;
  ContextUsed := 0;
  Path := ActiveProjectSessionPath;
  If (Path = '') Or (Not FileExistsUTF8(Path)) Then
    Exit;
  If Not Assigned(Transcript) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Try
      Lines.LoadFromFile(Path);
    Except
      On E: Exception Do
        Begin
          WorkflowLogger.Warning('AssistantSession', 'Load failed: ' + E.Message);
          Exit;
        End;
    End;
    If Lines.Count < 1 Then
      Exit;
    If (Trim(Lines[0]) <> '') And (Trim(Lines[0])[1] = '{') Then
      Begin
        Data := Nil;
        Try
          Try
            Data := GetJSON(Lines.Text);
          Except
            On E: Exception Do
              Begin
                WorkflowLogger.Warning('AssistantSession', 'JSON parse failed: ' + E.Message);
                Exit;
              End;
          End;
          If Not (Data Is TJSONObject) Then
            Exit;
          Root := TJSONObject(Data);
          Transcript.Clear;
          If Assigned(AssistantClient) Then
            AssistantClient.ClearHistory;
          ContextUsed := Root.Get('contextUsed', 0);
          Arr := Root.FindPath('transcript') As TJSONArray;
          If Assigned(Arr) Then
            For I := 0 To Arr.Count - 1 Do
              Transcript.Add(Arr.Items[I].AsString);
          Arr := Root.FindPath('messages') As TJSONArray;
          If Assigned(Arr) And Assigned(AssistantClient) Then
            For I := 0 To Arr.Count - 1 Do
              If Arr.Items[I] Is TJSONObject Then
                Begin
                  MsgObj := TJSONObject(Arr.Items[I]);
                  RoleTag := MsgObj.Get('role', 'user');
                  Content := MsgObj.Get('content', '');
                  ToolCallId := MsgObj.Get('toolCallId', '');
                  ToolCallsJson := MsgObj.Get('toolCallsJson', '');
                  AssistantClient.RestoreMessage(TagToRole(RoleTag), Content, ToolCallId, ToolCallsJson);
                End;
          Result := True;
          I := 0;
          If Assigned(AssistantClient) Then
            I := AssistantClient.MessageCount;
          WorkflowLogger.Info('AssistantSession',
            Format('Loaded session from %s (transcript lines=%d messages=%d)',
              [Path, Transcript.Count, I]));
        Finally
          Data.Free;
        End;
        Exit;
      End;
    If (Pos('LazAssistantTools-Session', Lines[0]) <> 1) And
      (Pos('LazGrokChat-Session', Lines[0]) <> 1) Then
      Exit;

    Transcript.Clear;
    If Assigned(AssistantClient) Then
      AssistantClient.ClearHistory;

    Section := 'header';
    RoleTag := '';
    Content := '';
    For I := 1 To Lines.Count - 1 Do
      Begin
        Line := Lines[I];
        If Line = '---TRANSCRIPT---' Then
          Begin
            Section := 'transcript';
            Continue;
          End;
        If Line = '---MESSAGES---' Then
          Begin
            Section := 'messages';
            Continue;
          End;
        If Line = '---END---' Then
          Break;
        If (Copy(Line, 1, 7) = '---MSG ') And
          ((Pos('---MSG user---', Line) = 1) Or (Pos('---MSG assistant---', Line) = 1) Or
           (Pos('---MSG system---', Line) = 1) Or (Pos('---MSG tool---', Line) = 1)) Then
          Begin
            If (Section = 'msgbody') And (RoleTag <> '') And Assigned(AssistantClient) Then
              AssistantClient.AddMessage(TagToRole(RoleTag), Content);
            Section := 'msgbody';
            { Line format: ---MSG user--- }
            RoleTag := Copy(Line, 8, MaxInt);
            If (Length(RoleTag) >= 3) And (Copy(RoleTag, Length(RoleTag) - 2, 3) = '---') Then
              RoleTag := Copy(RoleTag, 1, Length(RoleTag) - 3);
            RoleTag := Trim(RoleTag);
            Content := '';
            Continue;
          End;
        If Section = 'header' Then
          Begin
            If Copy(Line, 1, 12) = 'ContextUsed=' Then
              ContextUsed := StrToIntDef(Copy(Line, 13, MaxInt), 0);
          End
        Else If Section = 'transcript' Then
          Transcript.Add(Line)
        Else If Section = 'msgbody' Then
          Begin
            If Content <> '' Then
              Content := Content + LineEnding;
            Content := Content + Line;
          End;
      End;
    If (Section = 'msgbody') And (RoleTag <> '') And Assigned(AssistantClient) Then
      AssistantClient.AddMessage(TagToRole(RoleTag), Content);

    Result := True;
    WorkflowLogger.Info('AssistantSession',
      Format('Loaded session from %s (transcript lines=%d messages=%d)',
        [Path, Transcript.Count, AssistantClient.MessageCount]));
  Finally
    Lines.Free;
  End;
End;

Procedure ClearProjectChatSession;
Var
  Path: String;
Begin
  Path := ActiveProjectSessionPath;
  If (Path <> '') And FileExistsUTF8(Path) Then
    Begin
      Try
        DeleteFileUTF8(Path);
        WorkflowLogger.Info('AssistantSession', 'Cleared session file ' + Path);
      Except
        On E: Exception Do
          WorkflowLogger.Warning('AssistantSession', 'Clear failed: ' + E.Message);
      End;
    End;
End;

End.
