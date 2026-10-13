Program PluginFormLifetimeTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Classes, SysUtils, Process, FileUtil,
  AssistantTestIDEHost, BaseIDEIntf, LazConfigStorage,
  ManageRepositoryForm, ProjectAssistantForm, WorkflowEvents;
Var FailSave: Boolean; SaveFailures: Integer;
Function TestConfig(Const Filename: String; LoadFromDisk: Boolean): TConfigStorage;
Begin
  If FailSave And Not LoadFromDisk Then
    Begin
      Inc(SaveFailures);
      Raise Exception.Create('Injected settings write failure');
    End;
  Result := TConfigMemStorage.Create('', False);
End;
Var Repo: TManageRepositoryForm; Assistant: TProjectAssistantForm; I, Before: Integer; TempRoot, OutputText: String;
Begin
  Try
    Application.Initialize;
    GetIDEConfigStorage := @TestConfig;
    TempRoot := GetTempFileName(GetTempDir, 'plugin-lifetime-');
    DeleteFile(TempRoot);
    If Not RunCommand('git', ['init', '--quiet', TempRoot], OutputText) Then
      Raise Exception.Create('Cannot create repository fixture: ' + OutputText);
    If Not RunCommand('git', ['-C', TempRoot, '-c', 'user.name=Test',
      '-c', 'user.email=test@example.invalid', '-c', 'commit.gpgsign=false',
      'commit', '--allow-empty', '-qm', 'initial'], OutputText) Then
      Raise Exception.Create('Cannot commit repository fixture: ' + OutputText);
    Before := Screen.CustomFormCount;
    For I := 1 To 10 Do
      Begin
        Repo := TManageRepositoryForm.Create(Nil);
        Try
          Repo.SetRepository(TempRoot);
          Repo.GraphHostResize(Nil);
          Repo.Show;
          Application.ProcessMessages;
          Repo.Hide;
          Repo.Show;
          Application.ProcessMessages;
        Finally Repo.Free; End;
        Assistant := TProjectAssistantForm.Create(Nil);
        FailSave := True;
        Try Assistant.Free; Finally FailSave := False; End;
        CheckSynchronize;
        WorkflowEventBus.NotifyDocumentSaved('closed-view-fixture');
        WorkflowEventBus.NotifyWorkingTreeChanged('closed-view-fixture');
        If Screen.CustomFormCount <> Before Then
          Raise Exception.Create('A disposed plugin form remained registered');
      End;
    If SaveFailures <> 10 Then Raise Exception.Create('Save failure injection did not run');
    DeleteDirectory(TempRoot, False);
    WriteLn('PASS repeated plugin form disposal, including failed settings saves');
  Except
    On E: Exception Do
      Begin
        WriteLn(StdErr, 'FAIL ', E.ClassName, ': ', E.Message);
        DumpExceptionBackTrace(StdErr);
        Halt(1);
      End;
  End;
End.
