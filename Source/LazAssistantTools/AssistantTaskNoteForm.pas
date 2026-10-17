Unit AssistantTaskNoteForm;

{ Note dialog for a task run. Cancel aborts the run (c) 2026 Michell Computing.

  Not placed on the settings form. Used when scope is user_note or the prompt
  contains the user_note placeholder. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ButtonPanel, AssistantTasks;

Type
  TAssistantTaskNoteForm = Class(TForm)
    NoteMemo: TMemo;
    ButtonPanel: TButtonPanel;
    Procedure FormCreate(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
  End;

/// True when a run must ask for a note: scope user_note, or the prompt contains the user_note placeholder.
Function AssistantTaskNeedsUserNote(Const Task: TAssistantTask): Boolean;
/// Modal note. Caption is the task title. Cancel returns false and leaves NoteText empty.
/// OK returns true and the trimmed memo, which may be empty.
Function ShowAssistantTaskNote(Const TaskTitle: String; Out NoteText: String): Boolean;

Implementation

{$R *.lfm}

Uses
  LCLType;

Function AssistantTaskNeedsUserNote(Const Task: TAssistantTask): Boolean;
Begin
  Result := (Task.Scope = tsUserNote) Or (Pos('{user_note}', Task.Prompt) > 0);
End;

Function ShowAssistantTaskNote(Const TaskTitle: String; Out NoteText: String): Boolean;
Var
  Form: TAssistantTaskNoteForm;
Begin
  NoteText := '';
  Result := False;
  Form := TAssistantTaskNoteForm.Create(Nil);
  Try
    If Trim(TaskTitle) = '' Then
      Form.Caption := 'Note'
    Else
      Form.Caption := TaskTitle;
    If Form.ShowModal <> mrOk Then
      Exit;
    NoteText := Trim(Form.NoteMemo.Text);
    Result := True;
  Finally
    Form.Free;
  End;
End;

Procedure TAssistantTaskNoteForm.FormCreate(Sender: TObject);
Begin
  ButtonPanel.OKButton.Caption := 'OK';
  ButtonPanel.OKButton.Default := True;
  ButtonPanel.OKButton.ModalResult := mrOk;
  ButtonPanel.CancelButton.Caption := 'Cancel';
  ButtonPanel.CancelButton.Cancel := True;
  ButtonPanel.CancelButton.ModalResult := mrCancel;
End;

Procedure TAssistantTaskNoteForm.FormShow(Sender: TObject);
Begin
  NoteMemo.SetFocus;
End;

Procedure TAssistantTaskNoteForm.FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  If (Key <> VK_ESCAPE) Or (Shift <> []) Then
    Exit;
  Key := 0;
  ModalResult := mrCancel;
End;

Initialization

RegisterClass(TAssistantTaskNoteForm);

End.
