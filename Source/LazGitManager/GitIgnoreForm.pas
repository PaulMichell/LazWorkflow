Unit GitIgnoreForm;

{ Simple .gitignore editor for the repository root (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ButtonPanel;

Type
  TGitIgnoreForm = Class(TForm)
    FHintLabel: TLabel;
    FMemo: TMemo;
    FButtonPanel: TButtonPanel;
    Procedure FormCreate(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
  Private
    FIgnorePath: String;
  Public
    Procedure LoadFromRepository(Const RepoPath: String);
  End;

Function ShowGitIgnoreForm(Const RepoPath: String): Boolean;

Implementation

{$R *.lfm}

Function ShowGitIgnoreForm(Const RepoPath: String): Boolean;
Var
  Form: TGitIgnoreForm;
Begin
  Result := False;
  If (RepoPath = '') Or Not DirectoryExists(RepoPath) Then
    Begin
      MessageDlg('No repository path is available.', mtWarning, [mbOK], 0);
      Exit;
    End;
  Form := TGitIgnoreForm.Create(Application.MainForm);
  Try
    Form.LoadFromRepository(RepoPath);
    Result := Form.ShowModal = mrOk;
  Finally
    Form.Free;
  End;
End;

Procedure TGitIgnoreForm.FormCreate(Sender: TObject);
Begin
  FButtonPanel.OKButton.Caption := 'Save';
  FButtonPanel.CancelButton.Caption := 'Cancel';
End;

Procedure TGitIgnoreForm.LoadFromRepository(Const RepoPath: String);
Begin
  FIgnorePath := IncludeTrailingPathDelimiter(ExpandFileName(RepoPath)) + '.gitignore';
  Caption := 'Ignore Files – ' + FIgnorePath;
  If FileExists(FIgnorePath) Then
    FMemo.Lines.LoadFromFile(FIgnorePath)
  Else
    FMemo.Clear;
End;

Procedure TGitIgnoreForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;
  Try
    FMemo.Lines.SaveToFile(FIgnorePath);
  Except
    On E: Exception Do
      Begin
        MessageDlg('Could not save .gitignore:' + LineEnding + E.Message, mtError, [mbOK], 0);
        CanClose := False;
      End;
  End;
End;

End.
