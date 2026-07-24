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
    FLabel: TLabel;
    FFolderEdit: TDirectoryEdit;
    FButtonPanel: TButtonPanel;
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
  Public
    Procedure SetDefaultFolder(Const Folder: String);
    Function SelectedFolder: String;
  End;

Function ShowGitInitForm(Const DefaultFolder: String; Out ChosenFolder: String): Boolean;

Implementation

{$R *.lfm}

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

Procedure TGitInitForm.FormCreate(Sender: TObject);
Begin
  FButtonPanel.OKButton.Caption := 'Initialise';
  FButtonPanel.CancelButton.Caption := 'Cancel';
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
      MessageDlg('Choose a project folder.', mtWarning, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If Not DirectoryExists(Dir) Then
    Begin
      MessageDlg('Folder does not exist:' + LineEnding + Dir, mtWarning, [mbOK], 0);
      CanClose := False;
    End;
End;

End.
