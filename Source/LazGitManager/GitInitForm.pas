Unit GitInitForm;

{ Initialise repository – choose project folder (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  EditBtn, ButtonPanel;

Type
  TGitInitForm = Class(TForm)
  Private
    FFolderEdit: TDirectoryEdit;
    FLabel: TLabel;
    FHintLabel: TLabel;
    FButtonPanel: TButtonPanel;
    Procedure CreateUI;
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Procedure SetDefaultFolder(Const Folder: String);
    Function SelectedFolder: String;
  End;

{ Returns True if the user confirmed a folder. }
Function ShowGitInitForm(Const DefaultFolder: String; Out ChosenFolder: String): Boolean;

Implementation

Function ShowGitInitForm(Const DefaultFolder: String; Out ChosenFolder: String): Boolean;
Var
  Form: TGitInitForm;
Begin
  Result := False;
  ChosenFolder := '';
  Form := TGitInitForm.Create(Application.MainForm);
  Try
    Form.SetDefaultFolder(DefaultFolder);
    If Form.ShowModal = mrOk Then
      Begin
        ChosenFolder := Form.SelectedFolder;
        Result := ChosenFolder <> '';
      End;
  Finally
    Form.Free;
  End;
End;

Constructor TGitInitForm.Create(TheOwner: TComponent);
Begin
  Inherited CreateNew(TheOwner);
  CreateUI;
End;

Procedure TGitInitForm.CreateUI;
Begin
  Caption := 'Initialise Repository';
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  Width := 520;
  Height := 180;
  OnCloseQuery := @FormCloseQuery;

  FButtonPanel := TButtonPanel.Create(Self);
  With FButtonPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      ShowButtons := [pbOK, pbCancel];
      OKButton.Caption := 'Initialise';
      CancelButton.Caption := 'Cancel';
    End;

  FLabel := TLabel.Create(Self);
  With FLabel Do
    Begin
      Parent := Self;
      Left := 16;
      Top := 16;
      Caption := 'Project folder (Git root):';
    End;

  FFolderEdit := TDirectoryEdit.Create(Self);
  With FFolderEdit Do
    Begin
      Parent := Self;
      Left := 16;
      Top := 40;
      Width := 480;
      DialogTitle := 'Select folder for the new Git repository';
      ShowHidden := False;
    End;

  FHintLabel := TLabel.Create(Self);
  With FHintLabel Do
    Begin
      Parent := Self;
      Left := 16;
      Top := 76;
      Width := 480;
      WordWrap := True;
      Caption := 'Defaults to the folder containing the open project file. ' +
        'Choose the parent folder if that is your usual monorepo root.';
      Font.Color := clGrayText;
    End;
End;

Procedure TGitInitForm.SetDefaultFolder(Const Folder: String);
Begin
  If Folder <> '' Then
    FFolderEdit.Directory := ExcludeTrailingPathDelimiter(ExpandFileName(Folder))
  Else
    FFolderEdit.Directory := GetCurrentDir;
End;

Function TGitInitForm.SelectedFolder: String;
Begin
  Result := Trim(FFolderEdit.Directory);
  If Result <> '' Then
    Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
End;

Procedure TGitInitForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Var
  Dir: String;
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;
  Dir := SelectedFolder;
  If Dir = '' Then
    Begin
      MessageDlg('Choose a project folder.', mtError, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If Not DirectoryExists(Dir) Then
    Begin
      MessageDlg('Folder does not exist:' + LineEnding + Dir, mtError, [mbOK], 0);
      CanClose := False;
    End;
End;

End.
