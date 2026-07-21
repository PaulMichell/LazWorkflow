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
    FUrlEdit: TEdit;
    FFolderEdit: TDirectoryEdit;
    FUrlLabel: TLabel;
    FFolderLabel: TLabel;
    FButtonPanel: TButtonPanel;
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
  Public
    Procedure SetDefaultFolder(Const Folder: String);
    Function RemoteUrl: String;
    Function TargetFolder: String;
  End;

Function ShowGitCloneForm(Const DefaultFolder: String; Out RemoteUrl, TargetFolder: String): Boolean;

Implementation

{$R *.lfm}

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

Procedure TGitCloneForm.FormCreate(Sender: TObject);
Begin
  FButtonPanel.OKButton.Caption := 'Clone';
  FButtonPanel.CancelButton.Caption := 'Cancel';
End;

Procedure TGitCloneForm.SetDefaultFolder(Const Folder: String);
Var
  Base: String;
Begin
  If Folder <> '' Then
    Base := ExcludeTrailingPathDelimiter(ExpandFileName(Folder))
  Else
    Base := GetCurrentDir;
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
      MessageDlg('Enter a remote repository URL.', mtWarning, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If TargetFolder = '' Then
    Begin
      MessageDlg('Choose a target folder path for the clone.', mtWarning, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If DirectoryExists(TargetFolder) Then
    Begin
      MessageDlg('Target folder already exists:' + LineEnding + TargetFolder + LineEnding +
        'Choose a new folder path.', mtWarning, [mbOK], 0);
      CanClose := False;
    End;
End;

End.
