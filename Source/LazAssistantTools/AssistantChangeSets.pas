Unit AssistantChangeSets;
{ Bounded, in-memory multi-editor receipts. No disk writes or inferred ownership
  of a failed edit. Callbacks run serially on the broker's IDE thread. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils;
Type
  TChangeRead = Function(Const Path: String; Out CanonicalPath, Text, Stamp, ErrorText: String): Boolean Of Object;
  TChangeWrite = Function(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean Of Object;
  TChangeCurrent = Function: Boolean Of Object;
  TAssistantChange = Record
    Path, BeforeText, AfterText, BeforeStamp, AfterStamp, State, Error: String;
    Owned: Boolean;
  End;
  TAssistantChangeSet = Class
  Public
    Id, Project, State, Error: String;
    Items: Array Of TAssistantChange;
    Function Bytes: Integer;
    Function CheckAll(Read: TChangeRead; Current: TChangeCurrent; Out Note: String): Boolean;
    Function Apply(Read: TChangeRead; Write: TChangeWrite; Current: TChangeCurrent): Boolean;
    Function Revert(Read: TChangeRead; Write: TChangeWrite; Current: TChangeCurrent): Boolean;
    Function Receipt: String;
    Procedure ReviewText(Out BeforeText, AfterText: String);
  End;
Implementation
Uses fpjson;
Function TAssistantChangeSet.Bytes: Integer;
Var I: Integer;
Begin Result := 0; For I := 0 To High(Items) Do Inc(Result, Length(Items[I].BeforeText) + Length(Items[I].AfterText)); End;
Function TAssistantChangeSet.CheckAll(Read: TChangeRead; Current: TChangeCurrent; Out Note: String): Boolean;
Var I: Integer; Path, Text, Stamp, Expected, Version: String;
Begin
  Result := False;
  Try
  For I := 0 To High(Items) Do
    Begin
      If Not Current() Then Begin Note := 'Workspace/run changed or was cancelled.'; Exit; End;
      If Not Read(Items[I].Path, Path, Text, Stamp, Note) Then Exit;
      If Items[I].Owned Then Begin Expected := Items[I].AfterText; Version := Items[I].AfterStamp; End
      Else Begin Expected := Items[I].BeforeText; Version := Items[I].BeforeStamp; End;
      If (Path <> Items[I].Path) Or (Text <> Expected) Or (Stamp <> Version) Then
        Begin Note := 'Editor changed: ' + Items[I].Path; Exit; End;
    End;
  Result := Current();
  If Not Result Then Note := 'Workspace/run changed or was cancelled.';
  Except On E: Exception Do Begin Note := 'Editor validation failed: ' + E.Message; Result := False; End; End;
End;
Function TAssistantChangeSet.Revert(Read: TChangeRead; Write: TChangeWrite; Current: TChangeCurrent): Boolean;
Var I: Integer; Path, Text, Stamp, Note: String; OK: Boolean;
Begin
  Result := True;
  For I := High(Items) Downto 0 Do
    Begin
      If Not Items[I].Owned Then
        Begin If Items[I].State = 'unknown' Then Result := False; Continue; End;
      If Not Current() Then Begin Result := False; Break; End;
      Try
        If Not Read(Items[I].Path, Path, Text, Stamp, Note) Or
          (Path <> Items[I].Path) Or (Text <> Items[I].AfterText) Or (Stamp <> Items[I].AfterStamp) Or Not Current() Then
          Begin Items[I].State := 'conflict'; Items[I].Error := 'Recovery skipped: editor changed, closed, read-only or unavailable.'; Result := False; Continue; End;
        OK := Write(Items[I].Path, Items[I].AfterText, Items[I].BeforeText, Note);
        If Not Current() Then
          Begin Items[I].State := 'unknown'; Items[I].Owned := False; Items[I].Error := 'Recovery interrupted; inspect this editor.'; Result := False; Break; End;
        If OK And Read(Items[I].Path, Path, Text, Stamp, Note) And
          (Path = Items[I].Path) And (Text = Items[I].BeforeText) And Current() Then
          Begin Items[I].Owned := False; Items[I].State := 'restored'; Items[I].Error := ''; End
        Else Begin Items[I].Owned := False; Items[I].State := 'unknown'; Items[I].Error := 'Recovery result is uncertain; inspect this editor. ' + Note; Result := False; End;
      Except
        On E: Exception Do
          Begin Items[I].Owned := False; Items[I].State := 'unknown'; Items[I].Error := 'Recovery failed: ' + E.Message; Result := False; End;
      End;
    End;
  If Result Then State := 'reverted' Else State := 'partial';
End;
Function TAssistantChangeSet.Apply(Read: TChangeRead; Write: TChangeWrite; Current: TChangeCurrent): Boolean;
Var I: Integer; Path, Text, Stamp, Note: String; OK: Boolean;
Begin
  Result := False; State := 'rejected'; Error := '';
  If Not CheckAll(Read, Current, Error) Then Exit;
  State := 'applying';
  For I := 0 To High(Items) Do
    Begin
      If Not CheckAll(Read, Current, Error) Then Break;
      If Items[I].BeforeText = Items[I].AfterText Then Begin Items[I].State := 'unchanged'; Continue; End;
      Items[I].State := 'unknown';
      Try
        OK := Write(Items[I].Path, Items[I].BeforeText, Items[I].AfterText, Note);
        If Not Current() Then Begin Error := 'Editor operation interrupted; inspect the receipt before continuing.'; Break; End;
        If Not Read(Items[I].Path, Path, Text, Stamp, Error) Then
          Begin If Error = '' Then Error := 'Cannot read editor after mutation.'; Break; End;
        If Not Current() Then Begin Error := 'Workspace changed during editor readback.'; Break; End;
        If OK And (Path = Items[I].Path) And (Text = Items[I].AfterText) And (Stamp <> Items[I].BeforeStamp) Then
          Begin Items[I].Owned := True; Items[I].AfterStamp := Stamp; Items[I].State := 'applied'; End
        Else
          Begin
            If (Path = Items[I].Path) And (Text = Items[I].BeforeText) And (Stamp = Items[I].BeforeStamp) Then Items[I].State := 'unchanged';
            Error := 'Editor did not confirm the exact proposed change: ' + Items[I].Path + '. ' + Note; Break;
          End;
      Except On E: Exception Do Begin Error := 'Editor operation failed: ' + E.Message; Break; End; End;
    End;
  For I := 0 To High(Items) Do
    If (Items[I].State <> 'applied') And (Items[I].State <> 'unchanged') And (Error = '') Then
      Error := 'Change set did not finish: ' + Items[I].Path;
  If (Error = '') And CheckAll(Read, Current, Error) Then
    Begin State := 'applied'; Exit(True); End;
  { Only restore confirmed assistant edits, and only while the operation's
    original workspace/run is current. Stop/project changes defer recovery. }
  If Current() Then
    Begin If Revert(Read, Write, Current) Then State := 'rolled_back'; End
  Else State := 'partial';
End;
Function TAssistantChangeSet.Receipt: String;
Var Root, Entry: TJSONObject; Files: TJSONArray; I: Integer;
Begin
  Root := TJSONObject.Create;
  Try
    Root.Add('change_set_id', Id); Root.Add('state', State); Root.Add('error', Error);
    Root.Add('saved', False); Root.Add('durable', False);
    Root.Add('recovery', 'Use lazarus_revert_changes for confirmed unchanged assistant edits; inspect conflicts/unknown outcomes and use editor Undo as needed. Receipt lasts until the assistant panel closes.');
    Files := TJSONArray.Create; Root.Add('files', Files);
    For I := 0 To High(Items) Do
      Begin
        Entry := TJSONObject.Create; Entry.Add('path', Items[I].Path); Entry.Add('state', Items[I].State);
        Entry.Add('error', Items[I].Error); Entry.Add('hasRecoverySnapshot', Items[I].Owned);
        Files.Add(Entry);
      End;
    Result := Root.AsJSON;
  Finally Root.Free; End;
End;
Procedure TAssistantChangeSet.ReviewText(Out BeforeText, AfterText: String);
Var I: Integer; Header: String;
Begin
  BeforeText := ''; AfterText := '';
  For I := 0 To High(Items) Do
    Begin
      Header := LineEnding + 'FILE: ' + Items[I].Path + LineEnding + StringOfChar('=', 60) + LineEnding;
      BeforeText := BeforeText + Header + Items[I].BeforeText + LineEnding;
      AfterText := AfterText + Header + Items[I].AfterText + LineEnding;
    End;
End;
End.
