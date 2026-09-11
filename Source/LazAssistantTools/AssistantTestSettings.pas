Unit AssistantTestSettings;
{ User-owned per-project test commands, stored in the IDE configuration tree. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils;
Type
  TAssistantTestSettings = Class
  Private
    FRoot, FProject: String;
  Public
    Enabled: Boolean;
    Executable: String;
    Arguments: TStringList;
    TimeoutSeconds: Integer;
    Constructor Create(Const ConfigRoot, ProjectFile: String);
    Destructor Destroy; Override;
    Procedure Load;
    Procedure Save;
    Function Validate(Out ErrorText: String): Boolean;
    Function CommandJSON: String;
    Function ResolvedExecutable: String;
    Function WorkingDirectory: String;
    Function StorageFilename: String;
  End;
Implementation
Uses IniFiles, sha1, fpjson, jsonparser;
Constructor TAssistantTestSettings.Create(Const ConfigRoot, ProjectFile: String);
Begin
  Inherited Create; FRoot := ConfigRoot; FProject := ProjectFile;
  If FProject <> '' Then FProject := ExpandFileName(FProject);
  Arguments := TStringList.Create; TimeoutSeconds := 600;
End;
Destructor TAssistantTestSettings.Destroy;
Begin Arguments.Free; Inherited Destroy; End;
Function TAssistantTestSettings.StorageFilename: String;
Begin Result := IncludeTrailingPathDelimiter(FRoot) + 'assistant-tests/' + SHA1Print(SHA1String(FProject)) + '.ini'; End;
Function TAssistantTestSettings.WorkingDirectory: String;
Begin Result := ExtractFilePath(FProject); End;
Function TAssistantTestSettings.ResolvedExecutable: String;
Begin
  Result := Executable;
  If (Result <> '') And Not (Result[1] = PathDelim) Then Result := WorkingDirectory + Result;
  If Result <> '' Then Result := ExpandFileName(Result);
End;
Procedure TAssistantTestSettings.Load;
Var Ini: TIniFile; I: Integer; Data: TJSONData;
Begin
  Enabled := False; Executable := ''; TimeoutSeconds := 600; Arguments.Clear;
  If (FProject = '') Or Not FileExists(StorageFilename) Then Exit;
  Ini := TIniFile.Create(StorageFilename);
  Try
    If (Ini.ReadInteger('test', 'version', 0) <> 1) Or (Ini.ReadString('test', 'project', '') <> FProject) Then Exit;
    Executable := Ini.ReadString('test', 'executable', '');
    TimeoutSeconds := Ini.ReadInteger('test', 'timeout', 600);
    Try Data := GetJSON(Ini.ReadString('test', 'arguments', '[]'));
    Except On E: Exception Do Exit; End;
    Try
      If Not (Data Is TJSONArray) Or (Data.Count > 128) Then Exit;
      For I := 0 To Data.Count - 1 Do
        Begin If Data.Items[I].JSONType <> jtString Then Exit; Arguments.Add(Data.Items[I].AsString); End;
    Finally Data.Free; End;
    Enabled := Ini.ReadBool('test', 'enabled', False);
  Finally Ini.Free; End;
End;
Function TAssistantTestSettings.Validate(Out ErrorText: String): Boolean;
Var I, Bytes: Integer;
Begin
  Result := False; ErrorText := '';
  If FProject = '' Then Begin ErrorText := 'Open a saved project before configuring tests.'; Exit; End;
  If Not Enabled Then Exit(True);
  If (Trim(Executable) = '') Or (Length(Executable) > 4096) Or (Pos(#0, Executable) > 0) Or
    (Pos(#10, Executable) > 0) Or (Pos(#13, Executable) > 0) Then
    Begin ErrorText := 'Choose a test executable path without control characters.'; Exit; End;
  If (TimeoutSeconds < 1) Or (TimeoutSeconds > 3600) Then Begin ErrorText := 'Test timeout must be 1–3600 seconds.'; Exit; End;
  If Arguments.Count > 128 Then Begin ErrorText := 'At most 128 test arguments are supported.'; Exit; End;
  Bytes := 0;
  For I := 0 To Arguments.Count - 1 Do
    Begin
      If Arguments[I] = '' Then Begin ErrorText := 'Remove blank argument lines; this process launcher cannot preserve empty arguments.'; Exit; End;
      Inc(Bytes, Length(Arguments[I]));
      If (Pos(#0, Arguments[I]) > 0) Or (Pos(#10, Arguments[I]) > 0) Or (Pos(#13, Arguments[I]) > 0) Or (Bytes > 32768) Then
        Begin ErrorText := 'Test arguments must fit 32 KiB and contain no line breaks or NUL bytes.'; Exit; End;
    End;
  Result := True;
End;
Procedure TAssistantTestSettings.Save;
Var Ini: TMemIniFile; I: Integer; Note, Temp: String; Data: TJSONArray;
Begin
  If Not Validate(Note) Then Raise Exception.Create(Note);
  ForceDirectories(ExtractFilePath(StorageFilename)); Temp := StorageFilename + '.tmp';
  Ini := TMemIniFile.Create(Temp);
  Try
    Ini.Clear; Ini.WriteInteger('test', 'version', 1); Ini.WriteString('test', 'project', FProject);
    Ini.WriteBool('test', 'enabled', Enabled); Ini.WriteString('test', 'executable', Executable);
    Ini.WriteInteger('test', 'timeout', TimeoutSeconds);
    Data := TJSONArray.Create;
    Try For I := 0 To Arguments.Count - 1 Do Data.Add(Arguments[I]); Ini.WriteString('test', 'arguments', Data.AsJSON);
    Finally Data.Free; End;
    Ini.UpdateFile;
  Finally Ini.Free; End;
  If Not RenameFile(Temp, StorageFilename) Then Begin DeleteFile(Temp); Raise Exception.Create('Cannot save test settings.'); End;
End;
Function TAssistantTestSettings.CommandJSON: String;
Var Root: TJSONObject; Args: TJSONArray; I: Integer;
Begin
  Root := TJSONObject.Create;
  Try
    Root.Add('enabled', Enabled); Root.Add('executable', ResolvedExecutable); Root.Add('workingDirectory', WorkingDirectory);
    Root.Add('timeoutSeconds', TimeoutSeconds); Args := TJSONArray.Create; Root.Add('arguments', Args);
    For I := 0 To Arguments.Count - 1 Do Args.Add(Arguments[I]);
    Result := Root.AsJSON;
  Finally Root.Free; End;
End;
End.
