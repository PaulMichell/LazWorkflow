Unit AssistantSession;

{ Legacy session path only. Model messages live on conversation.jsonl turns.
  This unit does not read or write .lazgrokchat-session. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  AssistantSessionFileName = '.lazgrokchat-session';
  AssistantSessionFormatVersion = 2;

Function ActiveProjectSessionPath: String;
Function SaveProjectChatSession(Transcript: TStrings; ContextUsed: Integer): Boolean;
Function LoadProjectChatSession(Transcript: TStrings; Out ContextUsed: Integer): Boolean;
Procedure ClearProjectChatSession;

Implementation

Uses
  LazFileUtils, LazIDEIntf, ProjectIntf, AssistantProjectPaths, AssistantWorkTarget;

Function ActiveProjectSessionPath: String;
Var
  Proj: TLazProject;
  Dir, Root, Preferred, Legacy, MainName: String;
Begin
  Result := '';
  If AssistantTarget.Kind <> atkProject Then
    Begin
      If AssistantTarget.Available Then Result := AssistantTarget.StoreDirectory + AssistantSessionFileName;
      Exit;
    End;
  Root := '';
  Preferred := '';
  Legacy := '';
  If Not Assigned(LazarusIDE) Then
    Exit;
  Proj := LazarusIDE.ActiveProject;
  If Not Assigned(Proj) Then
    Exit;
  MainName := '';
  If Assigned(Proj.MainFile) Then
    MainName := Proj.MainFile.Filename;
  Root := ResolveAssistantProjectRoot(Proj.ProjectInfoFile, MainName);
  If Root <> '' Then
    Preferred := IncludeTrailingPathDelimiter(Root) + AssistantStoreFolderName + PathDelim + AssistantSessionFileName;
  If (Preferred <> '') And FileExistsUTF8(Preferred) Then
    Begin
      Result := Preferred;
      Exit;
    End;
  If Root <> '' Then
    Begin
      Legacy := IncludeTrailingPathDelimiter(Root) + 'Source' + PathDelim + AssistantSessionFileName;
      If FileExistsUTF8(Legacy) Then
        Begin
          Result := Legacy;
          Exit;
        End;
    End;
  Dir := '';
  If MainName <> '' Then
    Dir := ExtractFilePath(ExpandFileName(MainName));
  If Dir = '' Then
    Dir := ExtractFilePath(ExpandFileName(Proj.ProjectInfoFile));
  If Dir <> '' Then
    Legacy := IncludeTrailingPathDelimiter(Dir) + AssistantSessionFileName;
  If (Legacy <> '') And FileExistsUTF8(Legacy) Then
    Begin
      Result := Legacy;
      Exit;
    End;
  If Preferred <> '' Then
    Result := Preferred
  Else
    Result := Legacy;
End;

Function SaveProjectChatSession(Transcript: TStrings; ContextUsed: Integer): Boolean;
Begin
  { Conversation turns own the model message list. Do not create the session file. }
  Result := True;
  If Assigned(Transcript) Or (ContextUsed >= 0) Then
    Result := True;
End;

Function LoadProjectChatSession(Transcript: TStrings; Out ContextUsed: Integer): Boolean;
Begin
  Result := False;
  ContextUsed := 0;
  If Assigned(Transcript) Then
    Result := False;
End;

Procedure ClearProjectChatSession;
Begin
  { Nothing to clear: the session file is not a history store. }
End;

End.
