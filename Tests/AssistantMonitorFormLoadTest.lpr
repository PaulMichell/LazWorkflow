Program AssistantMonitorFormLoadTest;

{ Streams the Remote Monitor form and checks Pascal fields against LFM objects.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, Classes, SysUtils, FileUtil, AssistantTestIDEHost, WorkflowSettings, AssistantMonitorForm;

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

Function RepositoryRoot: String;
Var
  I: Integer;
  Dir, Probe: String;
Begin
  Result := '';
  Dir := GetCurrentDir;
  For I := 1 To 8 Do
    Begin
      If FileExists(IncludeTrailingPathDelimiter(Dir) + 'Tests' + PathDelim + 'RunAssistantTests.pas') And
        DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'Source') Then
        Exit(ExcludeTrailingPathDelimiter(Dir));
      Probe := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + '..');
      If Probe = Dir Then
        Break;
      Dir := Probe;
    End;
End;

Function FormPath(Const Root, Extension: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(Root) + 'Source' + PathDelim + 'LazAssistantMonitor' + PathDelim +
    'AssistantMonitorForm.' + Extension;
End;

Procedure AddMember(List: TStringList; Const Name, ClassName: String);
Begin
  If (Name = '') Or (ClassName = '') Then
    Exit;
  List.Values[Name] := ClassName;
End;

{ Component fields in the unnamed section. Methods and the Private section are not fields. }
Procedure ReadPascalFields(Const Path: String; Fields: TStringList);
Var
  Lines: TStringList;
  I, Colon, Semi: Integer;
  Line, Name, ClassName: String;
  InClass: Boolean;
Begin
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    InClass := False;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[I]);
        If Not InClass Then
          Begin
            InClass := Pos('TAssistantMonitorForm = Class(TForm)', Line) = 1;
            Continue;
          End;
        If (Line = 'Private') Or (Line = 'Protected') Or (Line = 'Public') Or (Line = 'Published') Or (Line = 'End;') Then
          Break;
        If (Pos('Procedure ', Line) = 1) Or (Pos('Function ', Line) = 1) Or (Pos('Constructor ', Line) = 1) Or
          (Pos('Destructor ', Line) = 1) Then
          Continue;
        Colon := Pos(':', Line);
        Semi := Pos(';', Line);
        If (Colon < 2) Or (Semi < Colon) Then
          Continue;
        Name := Trim(Copy(Line, 1, Colon - 1));
        ClassName := Trim(Copy(Line, Colon + 1, Semi - Colon - 1));
        If (Pos(' ', Name) > 0) Or (ClassName = '') Or (ClassName[1] <> 'T') Then
          Continue;
        AddMember(Fields, Name, ClassName);
      End;
  Finally
    Lines.Free;
  End;
End;

{ Nested LFM objects, excluding the form root. }
Procedure ReadLfmObjects(Const Path: String; Objects: TStringList);
Var
  Lines: TStringList;
  I, Colon, NameAt: Integer;
  Line, Name, ClassName: String;
Begin
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[I]);
        If Pos('object ', Line) <> 1 Then
          Continue;
        Colon := Pos(':', Line);
        NameAt := 8;
        If (Colon < NameAt) Or (Copy(Line, 1, 7) <> 'object ') Then
          Continue;
        Name := Trim(Copy(Line, NameAt, Colon - NameAt));
        ClassName := Trim(Copy(Line, Colon + 1, MaxInt));
        If ClassName = 'TAssistantMonitorForm' Then
          Continue;
        AddMember(Objects, Name, ClassName);
      End;
  Finally
    Lines.Free;
  End;
End;

Procedure CollectComponents(Owner: TComponent; Found: TStringList);
Var
  I: Integer;
  Child: TComponent;
Begin
  For I := 0 To Owner.ComponentCount - 1 Do
    Begin
      Child := Owner.Components[I];
      If Child.Name <> '' Then
        AddMember(Found, Child.Name, Child.ClassName);
      CollectComponents(Child, Found);
    End;
End;

Procedure CompareLists(Const Title: String; Left, Right: TStringList);
Var
  I: Integer;
  Name: String;
Begin
  Check(Title + ' count', Left.Count = Right.Count);
  For I := 0 To Left.Count - 1 Do
    Begin
      Name := Left.Names[I];
      Check(Title + ' ' + Name, Right.Values[Name] = Left.Values[Name]);
    End;
End;

Procedure TestStreamedFields;
Const
  Kept: Array[0..9] Of String = (
    'AddressEdit', 'PortEdit', 'PairCodeEdit', 'RequirePairCodeCheck', 'RemoteApprovalCheck', 'ClientList',
    'RevokeButton', 'RevokeAllButton', 'EndpointLabel', 'FingerprintLabel');
Var
  Root, TempRoot: String;
  Fields, Objects, Streamed: TStringList;
  Form: TAssistantMonitorForm;
  I: Integer;
Begin
  Root := RepositoryRoot;
  Check('repository root', Root <> '');
  If Root = '' Then
    Exit;
  Fields := TStringList.Create;
  Objects := TStringList.Create;
  Streamed := TStringList.Create;
  Form := Nil;
  TempRoot := '';
  Try
    TempRoot := GetTempFileName(GetTempDir, 'monitor-form-');
    DeleteFile(TempRoot);
    If Not CreateDir(TempRoot) Then
      Raise Exception.Create('Could not create the settings directory.');
    ReadPascalFields(FormPath(Root, 'pas'), Fields);
    ReadLfmObjects(FormPath(Root, 'lfm'), Objects);
    Check('fields were read', Fields.Count > 0);
    CompareLists('pas field matches lfm object', Fields, Objects);
    CompareLists('lfm object matches pas field', Objects, Fields);
    For I := 0 To High(Kept) Do
      Check('kept ' + Kept[I], (Fields.Values[Kept[I]] <> '') And (Objects.Values[Kept[I]] = Fields.Values[Kept[I]]));
    SetWorkflowSettingsDirectory(TempRoot);
    Application.Initialize;
    Form := TAssistantMonitorForm.Create(Nil);
    CollectComponents(Form, Streamed);
    CompareLists('streamed component matches lfm object', Streamed, Objects);
    CompareLists('lfm object matches streamed component', Objects, Streamed);
    Check('endpoint is shown', Form.EndpointLabel.Caption <> '');
    Check('fingerprint is shown', Pos('Fingerprint', Form.FingerprintLabel.Caption) = 1);
    Check('listener status is the server, not a frame counter',
      (Pos('Listener ', Form.StatusMemo.Text) = 1) And (Pos('Frames sent', Form.StatusMemo.Text) = 0) And
      (Pos('Seconds since frame', Form.StatusMemo.Text) = 0));
    Check('pairing code control is present', Form.PairCodeEdit.Text <> '');
    Check('client list is present', Assigned(Form.ClientList));
    Check('revoke is present', Assigned(Form.RevokeAction) And Assigned(Form.RevokeAllAction));
  Finally
    Form.Free;
    SetWorkflowSettingsDirectory('');
    If TempRoot <> '' Then
      DeleteDirectory(TempRoot, False, True);
    Streamed.Free;
    Objects.Free;
    Fields.Free;
  End;
End;

Begin
  FailCount := 0;
  Try
    TestStreamedFields;
  Except
    On E: Exception Do
      Begin
        WriteLn('FAIL exception ', E.ClassName, ': ', E.Message);
        Inc(FailCount);
      End;
  End;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorFormLoadTest passed')
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
End.
