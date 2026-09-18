Unit AssistantBuildDependencies;

{ Saved Pascal source closure under the IDE's CodeTools configuration. This
  deliberately does not claim compiler, linker, package or runtime closure. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  AssistantBuildJob;
Procedure CaptureAssistantDependencies(Var Inputs: TBuildInputs; Out Evidence: String; Out DefineStep: Integer);

Implementation

Uses
  Classes, SysUtils, LazFileUtils, LazIDEIntf, CodeToolManager, CodeCache,
  AssistantCodeToolsGuard, fpjson;

Procedure CaptureAssistantDependencies(Var Inputs: TBuildInputs; Out Evidence: String; Out DefineStep: Integer);
Var
  Queue, Captured: TStringList;
  Gaps: TJSONArray;
  Root: TJSONObject;
  I, J, InitialCount: Integer;
  Path, Note: String;
  Code, Included, SystemCode: TCodeBuffer;
  Tool: TCodeTool;
  MainUses, ImplUses: TStrings;
  Deadline: QWord;
  Entered: Boolean;
  Procedure Gap(Const Text: String);
  Begin
    If Gaps.Count < 20 Then Gaps.Add(Copy(Text, 1, 1000));
  End;
  Procedure Enqueue(Const Name: String);
  Var
    Ext: String;
  Begin
    Ext := LowerCase(ExtractFileExt(Name));
    If (Ext <> '.pas') And (Ext <> '.pp') And (Ext <> '.lpr') And (Ext <> '.dpr') And (Ext <> '.p') Then Exit;
    If Queue.IndexOf(Name) >= 0 Then Exit;
    If Queue.Count >= 512 Then
      Begin
        Gap('Source dependency limit reached.');
        Exit;
      End;
    Queue.Add(Name);
  End;
  Procedure Capture(CodeBuffer: TCodeBuffer);
  Var
    Index: Integer;
    Resource: String;
  Begin
    If Not Assigned(CodeBuffer) Then
      Begin
        Gap('CodeTools source is unavailable.');
        Exit;
      End;
    If Captured.IndexOf(CodeBuffer.Filename) >= 0 Then Exit;
    Captured.Add(CodeBuffer.Filename);
    If Not AddBuildInput(Inputs, CodeBuffer.Filename, Note) Then
      Begin
        Gap(Note);
        Exit;
      End;
    For Index := 0 To High(Inputs) Do
      If Inputs[Index].Path = ExpandFileName(CodeBuffer.Filename) Then
        If Inputs[Index].Text <> CodeBuffer.Source Then Gap('CodeTools text differs from saved source: ' + CodeBuffer.Filename);
      Resource := ChangeFileExt(CodeBuffer.Filename, '.lfm');
    If FileExistsUTF8(Resource) And Not AddBuildInput(Inputs, Resource, Note) Then Gap(Note);
    Resource := ChangeFileExt(CodeBuffer.Filename, '.lrs');
    If FileExistsUTF8(Resource) And Not AddBuildInput(Inputs, Resource, Note) Then Gap(Note);
  End;
  Procedure UsesFiles(Files: TStrings);
  Var
    Index: Integer;
  Begin
    If Not Assigned(Files) Then Exit;
    For Index := 0 To Files.Count - 1 Do
      If FilenameIsAbsolute(Files[Index]) And FileExistsUTF8(Files[Index]) Then Enqueue(Files[Index])
      Else Gap('Unresolved source dependency in ' + Path + ': ' + Files[Index]);
  End;
Begin
  DefineStep := -1;
  Entered := False;
  InitialCount := Length(Inputs);
  Queue := TStringList.Create;
  Queue.CaseSensitive := True;
  Captured := TStringList.Create;
  Captured.CaseSensitive := True;
  Root := TJSONObject.Create;
  Gaps := TJSONArray.Create;
  Root.Add('gaps', Gaps);
  Try
    Try
      If Not Assigned(LazarusIDE) Or Not Assigned(CodeToolBoss) Then Gap('IDE CodeTools is unavailable.')
      Else
        Begin
          Entered := EnterAssistantCodeTools;
          If Not Entered Then Gap('IDE CodeTools is busy.')
          Else If Not LazarusIDE.BeginCodeTools Then Gap('IDE could not prepare CodeTools.')
          Else
            Begin
              CodeToolBoss.DirectoryCachePool.IncreaseFileTimeStamp;
              DefineStep := CodeToolBoss.DefineTree.ChangeStep;
              For I := 0 To High(Inputs) Do Enqueue(Inputs[I].Path);
              If Queue.Count = 0 Then Gap('No Pascal source roots were available.');
              Deadline := GetTickCount64 + 2000;
              I := 0;
              While I < Queue.Count Do
                Begin
                  If GetTickCount64 >= Deadline Then
                    Begin
                      Gap('Source dependency scan time limit reached.');
                      Break;
                    End;
                  Path := Queue[I];
                  Inc(I);
                  { Check bounds before asking CodeTools to load the file. }
                  If Not AddBuildInput(Inputs, Path, Note) Then
                    Begin
                      Gap(Note);
                      Continue;
                    End;
                  Code := CodeToolBoss.LoadFile(Path, True, False);
                  Capture(Code);
                  If Not Assigned(Code) Then Continue;
                  MainUses := Nil;
                  ImplUses := Nil;
                  Try
                    If CodeToolBoss.FindUsedUnitFiles(Code, MainUses, ImplUses) Then
                      Begin
                        UsesFiles(MainUses);
                        UsesFiles(ImplUses);
                      End
                    Else Gap('Cannot resolve uses in ' + Path + ': ' + CodeToolBoss.ErrorMessage);
                  Finally
                    MainUses.Free;
                    ImplUses.Free;
                  End;
                  If Not SameText(ChangeFileExt(ExtractFileName(Path), ''), 'system') Then
                    Begin
                      SystemCode := CodeToolBoss.FindUnitSource(Code, 'System', '');
                      If Assigned(SystemCode) Then Enqueue(SystemCode.Filename)
                      Else Gap('Implicit System source is unavailable for ' + Path);
                    End;
                  { Full exploration includes implementation-body include directives. }
                  If Not CodeToolBoss.Explore(Code, Tool, False) Then
                    Begin
                      Gap('Cannot scan all includes in ' + Path + ': ' + CodeToolBoss.ErrorMessage);
                      Continue;
                    End;
                  If Tool.Scanner.IncludeFileIsMissing Then Gap('Missing include in ' + Path);
                  For J := 0 To Tool.Scanner.LinkCount - 1 Do
                    Begin
                      Included := TCodeBuffer(Tool.Scanner.Links[J].Code);
                      Capture(Included);
                    End;
                End;
              If CodeToolBoss.DefineTree.ChangeStep <> DefineStep Then Gap('CodeTools defines changed during discovery.');
            End;
        End;
    Except On E: Exception Do Gap('Source dependency scan failed: ' + E.Message);
    End;
    Root.Add('sourceClosureComplete', Gaps.Count = 0);
    Root.Add('compilerEnvironmentComplete', False);
    Root.Add('scope', 'CodeTools uses, implicit System, active includes and paired lfm/lrs files; compiler/linker configuration and other resources are not frozen');
    Root.Add('addedInputs', Length(Inputs) - InitialCount);
    Root.Add('defineStep', DefineStep);
    Evidence := Root.AsJSON;
  Finally
    If Entered Then LeaveAssistantCodeTools;
    Root.Free;
    Queue.Free;
    Captured.Free;
  End;
End;
End.
