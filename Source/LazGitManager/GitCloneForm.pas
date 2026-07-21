Unit GitCloneForm;

{ Clone a remote repository into a local folder (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  EditBtn, ButtonPanel;

Type
  TGitCloneForm = Class(TForm)
  Private
    FUrlEdit: TEdit;
    FFolderEdit: TDirectoryEdit;
    FUrlLabel: TLabel;
    FFolderLabel: TLabel;
    FHintLabel: TLabel;
    FButtonPanel: TButtonPanel;
    Procedure CreateUI;
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Procedure SetDefaultFolder(Const Folder: String);
    Function RemoteUrl: String;
    Function TargetFolder: String;
  End;

Function ShowGitCloneForm(Const DefaultFolder: String; Out RemoteUrl, TargetFolder: String): Boolean;

Implementation

Function ShowGitCloneForm(Const DefaultFolder: String; Out RemoteUrl, TargetFolder: String): Boolean;
Var
  Form: TGitCloneForm;
Begin
  Result := False;
  RemoteUrl := '';
  TargetFolder := '';
  Form := TGitCloneForm.Create(Application.MainForm);
  Try
    Form.SetDefaultFolder(DefaultFolder);
    If Form.ShowModal = mrOk Then
      Begin
        RemoteUrl := Form.RemoteUrl;
        TargetFolder := Form.TargetFolder;
        Result := (RemoteUrl <> '') And (TargetFolder <> '');
      End;
  Finally
    Form.Free;
  End;
End;

Constructor TGitCloneForm.Create(TheOwner: TComponent);
Begin
  Inherited CreateNew(TheOwner);
  CreateUI;
End;

Procedure TGitCloneForm.CreateUI;
Begin
  Caption := 'Clone Repository';
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  Width := 560;
  Height := 220;
  OnCloseQuery := @FormCloseQuery;

  FButtonPanel := TButtonPanel.Create(Self);
  With FButtonPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      ShowButtons := [pbOK, pbCancel];
      OKButton.Caption := 'Clone';
      CancelButton.Caption := 'Cancel';
    End;

  FUrlLabel := TLabel.Create(Self);
  With FUrlLabel Do
    Begin
      Parent := Self;
      Left := 16;
      Top := 16;
      Caption := 'Remote URL:';
    End;

  FUrlEdit := TEdit.Create(Self);
  With FUrlEdit Do
    Begin
      Parent := Self;
      Left := 16;
      Top := 36;
      Width := 520;
      Text := '';
      TextHint := 'https://github.com/org/repo.git';
    End;

  FFolderLabel := TLabel.Create(Self);
  With FFolderLabel Do
    Begin
      Parent := Self;
      Left := 16;
      Top := 76;
      Caption := 'Target folder (will be created by git clone):';
    End;

  FFolderEdit := TDirectoryEdit.Create(Self);
  With FFolderEdit Do
    Begin
      Parent := Self;
      Left := 16;
      Top := 96;
      Width := 520;
      DialogTitle := 'Select parent location / target folder name';
    End;

  FHintLabel := TLabel.Create(Self);
  With FHintLabel Do
    Begin
      Parent := Self;
      Left := 16;
      Top := 132;
      Width := 520;
      WordWrap := True;
      Font.Color := clGrayText;
      Caption := 'Enter the full path for the new repository folder (it must not already exist).';
    End;
End;

Procedure TGitCloneForm.SetDefaultFolder(Const Folder: String);
Var
  Base: String;
Begin
  If Folder <> '' Then
    Base := ExcludeTrailingPathDelimiter(ExpandFileName(Folder))
  Else
    Base := GetCurrentDir;
  { Suggest a sibling path the user can edit to the final clone directory. }
  FFolderEdit.Directory := Base;
End;

Function TGitCloneForm.RemoteUrl: String;
Begin
  Result := Trim(FUrlEdit.Text);
End;

Function TGitCloneForm.TargetFolder: String;
Begin
  Result := Trim(FFolderEdit.Directory);
  If Result <> '' Then
    Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
End;

Procedure TGitCloneForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;
  If RemoteUrl = '' Then
    Begin
      MessageDlg('Enter a remote repository URL.', mtError, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If TargetFolder = '' Then
    Begin
      MessageDlg('Choose a target folder path for the clone.', mtError, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If DirectoryExists(TargetFolder) Then
    Begin
      MessageDlg('Target folder already exists:' + LineEnding + TargetFolder + LineEnding +
        'Choose a new folder path.', mtError, [mbOK], 0);
      CanClose := False;
    End;
End;

End.
