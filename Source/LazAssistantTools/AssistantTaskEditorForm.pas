Unit AssistantTaskEditorForm;

{ Task editor dialog. OK validates and does not write settings (c) 2026 Michell Computing.

  Not placed on the settings form. Kind format disables the prompt, locks scope to the
  active editor, and shows the format note. The list form writes on its own save. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ButtonPanel, AssistantTasks;

Type
  TAssistantTaskEditorForm = Class(TForm)
    FieldsPanel: TPanel;
    TitleLabel: TLabel;
    TitleEdit: TEdit;
    SummaryLabel: TLabel;
    SummaryEdit: TEdit;
    EnabledCheck: TCheckBox;
    ModeLabel: TLabel;
    ModeCombo: TComboBox;
    KindLabel: TLabel;
    KindCombo: TComboBox;
    ScopeLabel: TLabel;
    ScopeCombo: TComboBox;
    MessageFilterLabel: TLabel;
    MessageFilterCombo: TComboBox;
    CompileFirstCheck: TCheckBox;
    FreshConversationCheck: TCheckBox;
    DocumentPathLabel: TLabel;
    DocumentPathEdit: TEdit;
    PromptPanel: TPanel;
    PromptMemo: TMemo;
    PromptLabel: TLabel;
    FormatNoteLabel: TLabel;
    ButtonPanel: TButtonPanel;
    Procedure FormCreate(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure KindComboChange(Sender: TObject);
    Procedure ScopeComboChange(Sender: TObject);
    Procedure ModeComboChange(Sender: TObject);
  Private
    SuppressChange: Boolean;
    EditingTask: TAssistantTask;
    HeldScope: TAssistantTaskScope;
    HeldPrompt: String;
    Procedure FillChoices;
    Procedure LoadTask(Const Task: TAssistantTask);
    Procedure ApplyEnabledState;
    Function ComboInRange(Combo: TComboBox; MinOrd, MaxOrd: Integer): Boolean;
    Function FilterFromCombo: TAssistantTaskMessageFilter;
    Function ReadTask(Out Task: TAssistantTask; Out ErrorText: String): Boolean;
    Procedure FocusValidationError(Const ErrorText: String);
  End;

/// Modal editor. OK runs ValidateAssistantTask and does not write the settings file.
/// IsNew only changes the caption. Id, Hidden, and BuiltinId are kept.
Function ShowAssistantTaskEditor(Var Task: TAssistantTask; IsNew: Boolean): Boolean;

Implementation

{$R *.lfm}

Uses
  Dialogs, LCLType, AssistantTools;

Const
  FormatKindNote = 'The active Pascal unit is formatted in the editor, Undoable, not saved, and no model is called.';

Function FallbackTaskId(Const Title: String): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := '';
  For I := 1 To Length(Title) Do
    Begin
      C := Title[I];
      If (C >= 'A') And (C <= 'Z') Then
        C := Chr(Ord(C) + 32);
      If ((C >= 'a') And (C <= 'z')) Or ((C >= '0') And (C <= '9')) Or (C = '.') Or (C = '_') Or (C = '-') Then
        Result := Result + C
      Else If C = ' ' Then
        If (Result <> '') And (Result[Length(Result)] <> '-') Then
          Result := Result + '-';
    End;
  If (Result = '') Or (Result = '.') Or (Result = '..') Then
    Result := 'task';
  If Length(Result) > 64 Then
    Result := Copy(Result, 1, 64);
End;

Function ShowAssistantTaskEditor(Var Task: TAssistantTask; IsNew: Boolean): Boolean;
Var
  Form: TAssistantTaskEditorForm;
Begin
  Result := False;
  Form := TAssistantTaskEditorForm.Create(Nil);
  Try
    If IsNew Then
      Form.Caption := 'New Task'
    Else
      Form.Caption := 'Edit Task';
    Form.LoadTask(Task);
    If Form.ShowModal <> mrOk Then
      Exit;
    Task := Form.EditingTask;
    Result := True;
  Finally
    Form.Free;
  End;
End;

Procedure TAssistantTaskEditorForm.FillChoices;
Begin
  { Item order matches the enum order, except the message filter omits the empty value. }
  ModeCombo.Items.BeginUpdate;
  Try
    ModeCombo.Items.Clear;
    ModeCombo.Items.Add('Inspect');
    ModeCombo.Items.Add('Document');
    ModeCombo.Items.Add('Plan');
    ModeCombo.Items.Add('Build');
    ModeCombo.Items.Add('Chat');
  Finally
    ModeCombo.Items.EndUpdate;
  End;
  KindCombo.Items.BeginUpdate;
  Try
    KindCombo.Items.Clear;
    KindCombo.Items.Add('Prompt');
    KindCombo.Items.Add('Format');
  Finally
    KindCombo.Items.EndUpdate;
  End;
  ScopeCombo.Items.BeginUpdate;
  Try
    ScopeCombo.Items.Clear;
    ScopeCombo.Items.Add('None');
    ScopeCombo.Items.Add('Active editor');
    ScopeCombo.Items.Add('Selection');
    ScopeCombo.Items.Add('Changed files');
    ScopeCombo.Items.Add('Messages');
    ScopeCombo.Items.Add('User note');
  Finally
    ScopeCombo.Items.EndUpdate;
  End;
  MessageFilterCombo.Items.BeginUpdate;
  Try
    MessageFilterCombo.Items.Clear;
    MessageFilterCombo.Items.Add('Errors');
    MessageFilterCombo.Items.Add('Warnings');
    MessageFilterCombo.Items.Add('Hints');
    MessageFilterCombo.Items.Add('All');
  Finally
    MessageFilterCombo.Items.EndUpdate;
  End;
End;

Procedure TAssistantTaskEditorForm.LoadTask(Const Task: TAssistantTask);
Begin
  EditingTask := Task;
  SuppressChange := True;
  Try
    TitleEdit.Text := Task.Title;
    SummaryEdit.Text := Task.Summary;
    EnabledCheck.Checked := Task.Enabled;
    If (Ord(Task.Mode) >= 0) And (Ord(Task.Mode) < ModeCombo.Items.Count) Then
      ModeCombo.ItemIndex := Ord(Task.Mode)
    Else
      ModeCombo.ItemIndex := Ord(tmInspect);
    If Task.Kind = tkFormat Then
      KindCombo.ItemIndex := Ord(tkFormat)
    Else
      KindCombo.ItemIndex := Ord(tkPrompt);
    HeldScope := Task.Scope;
    HeldPrompt := Task.Prompt;
    If Task.Kind = tkFormat Then
      ScopeCombo.ItemIndex := Ord(tsActiveEditor)
    Else If (Ord(Task.Scope) >= 0) And (Ord(Task.Scope) < ScopeCombo.Items.Count) Then
      ScopeCombo.ItemIndex := Ord(Task.Scope)
    Else
      ScopeCombo.ItemIndex := Ord(tsNone);
    Case Task.MessageFilter Of
      mfErrors: MessageFilterCombo.ItemIndex := 0;
      mfWarnings: MessageFilterCombo.ItemIndex := 1;
      mfHints: MessageFilterCombo.ItemIndex := 2;
      mfAll: MessageFilterCombo.ItemIndex := 3;
    Else
      MessageFilterCombo.ItemIndex := -1;
    End;
    CompileFirstCheck.Checked := Task.CompileFirst;
    FreshConversationCheck.Checked := Task.FreshConversation;
    DocumentPathEdit.Text := Task.DocumentPath;
    If Task.Kind = tkFormat Then
      PromptMemo.Text := ''
    Else
      PromptMemo.Text := Task.Prompt;
  Finally
    SuppressChange := False;
  End;
  ApplyEnabledState;
End;

Procedure TAssistantTaskEditorForm.ApplyEnabledState;
Var
  FormatKind, MessagesScope, DocumentMode: Boolean;
Begin
  FormatKind := KindCombo.ItemIndex = Ord(tkFormat);
  MessagesScope := (Not FormatKind) And (ScopeCombo.ItemIndex = Ord(tsMessages));
  DocumentMode := ModeCombo.ItemIndex = Ord(tmDocument);
  ScopeLabel.Enabled := Not FormatKind;
  ScopeCombo.Enabled := Not FormatKind;
  PromptLabel.Enabled := Not FormatKind;
  PromptMemo.Enabled := Not FormatKind;
  FormatNoteLabel.Visible := FormatKind;
  MessageFilterLabel.Enabled := MessagesScope;
  MessageFilterCombo.Enabled := MessagesScope;
  CompileFirstCheck.Enabled := MessagesScope;
  DocumentPathLabel.Enabled := DocumentMode;
  DocumentPathEdit.Enabled := DocumentMode;
End;

Function TAssistantTaskEditorForm.ComboInRange(Combo: TComboBox; MinOrd, MaxOrd: Integer): Boolean;
Begin
  Result := Assigned(Combo) And (Combo.ItemIndex >= MinOrd) And (Combo.ItemIndex <= MaxOrd);
End;

Function TAssistantTaskEditorForm.FilterFromCombo: TAssistantTaskMessageFilter;
Begin
  Case MessageFilterCombo.ItemIndex Of
    0: Result := mfErrors;
    1: Result := mfWarnings;
    2: Result := mfHints;
    3: Result := mfAll;
  Else
    Result := mfNone;
  End;
End;

Function TAssistantTaskEditorForm.ReadTask(Out Task: TAssistantTask; Out ErrorText: String): Boolean;
Begin
  Task := EditingTask;
  Task.Title := Trim(TitleEdit.Text);
  Task.Summary := Trim(SummaryEdit.Text);
  Task.Enabled := EnabledCheck.Checked;
  Task.FreshConversation := FreshConversationCheck.Checked;
  If ComboInRange(ModeCombo, Ord(tmInspect), Ord(tmChat)) Then
    Task.Mode := TAssistantTaskMode(ModeCombo.ItemIndex)
  Else
    Task.Mode := tmInspect;
  If KindCombo.ItemIndex = Ord(tkFormat) Then
    Task.Kind := tkFormat
  Else
    Task.Kind := tkPrompt;
  If Task.Kind = tkFormat Then
    Begin
      Task.Scope := tsActiveEditor;
      Task.Prompt := '';
    End
  Else
    Begin
      If ComboInRange(ScopeCombo, Ord(tsNone), Ord(tsUserNote)) Then
        Task.Scope := TAssistantTaskScope(ScopeCombo.ItemIndex)
      Else
        Task.Scope := tsNone;
      Task.Prompt := PromptMemo.Text;
    End;
  If Task.Scope = tsMessages Then
    Begin
      Task.MessageFilter := FilterFromCombo;
      Task.CompileFirst := CompileFirstCheck.Checked;
    End
  Else
    Begin
      Task.MessageFilter := mfNone;
      Task.CompileFirst := False;
    End;
  If Task.Mode = tmDocument Then
    Task.DocumentPath := StringReplace(Trim(DocumentPathEdit.Text), '\', '/', [rfReplaceAll])
  Else
    Task.DocumentPath := '';
  If Not TaskIdIsSafe(Task.Id) Then
    Task.Id := FallbackTaskId(Task.Title);
  Result := ValidateAssistantTask(Task, GetActivePlanRelativePath, ErrorText);
End;

Procedure TAssistantTaskEditorForm.FocusValidationError(Const ErrorText: String);
Var
  Lower: String;
Begin
  Lower := LowerCase(ErrorText);
  If Pos('title', Lower) > 0 Then
    TitleEdit.SetFocus
  Else If (Pos('prompt', Lower) > 0) And PromptMemo.Enabled Then
    PromptMemo.SetFocus
  Else If (Pos('document path', Lower) > 0) And DocumentPathEdit.Enabled Then
    DocumentPathEdit.SetFocus
  Else If (Pos('filter', Lower) > 0) And MessageFilterCombo.Enabled Then
    MessageFilterCombo.SetFocus;
End;

Procedure TAssistantTaskEditorForm.FormCreate(Sender: TObject);
Begin
  SuppressChange := False;
  HeldScope := tsNone;
  HeldPrompt := '';
  Caption := 'Edit Task';
  FormatNoteLabel.Caption := FormatKindNote;
  DocumentPathEdit.TextHint := 'Documents/Name.md';
  ButtonPanel.OKButton.Caption := 'OK';
  ButtonPanel.OKButton.Default := True;
  ButtonPanel.OKButton.ModalResult := mrOk;
  ButtonPanel.CancelButton.Caption := 'Cancel';
  ButtonPanel.CancelButton.Cancel := True;
  ButtonPanel.CancelButton.ModalResult := mrCancel;
  FillChoices;
  ApplyEnabledState;
End;

Procedure TAssistantTaskEditorForm.FormShow(Sender: TObject);
Begin
  TitleEdit.SetFocus;
  TitleEdit.SelectAll;
End;

Procedure TAssistantTaskEditorForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Var
  ErrorText: String;
  Task: TAssistantTask;
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;
  If ReadTask(Task, ErrorText) Then
    EditingTask := Task
  Else
    Begin
      CanClose := False;
      ModalResult := mrNone;
      If ErrorText = '' Then
        ErrorText := 'This task is not valid.';
      MessageDlg(ErrorText, mtError, [mbOK], 0);
      ModalResult := mrNone;
      FocusValidationError(ErrorText);
    End;
End;

Procedure TAssistantTaskEditorForm.FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  If (Key <> VK_ESCAPE) Or (Shift <> []) Then
    Exit;
  Key := 0;
  ModalResult := mrCancel;
End;

Procedure TAssistantTaskEditorForm.KindComboChange(Sender: TObject);
Begin
  If SuppressChange Then
    Exit;
  SuppressChange := True;
  Try
    If KindCombo.ItemIndex = Ord(tkFormat) Then
      Begin
        If ScopeCombo.Enabled And ComboInRange(ScopeCombo, Ord(tsNone), Ord(tsUserNote)) Then
          HeldScope := TAssistantTaskScope(ScopeCombo.ItemIndex);
        If PromptMemo.Enabled Then
          HeldPrompt := PromptMemo.Text;
        ScopeCombo.ItemIndex := Ord(tsActiveEditor);
        PromptMemo.Text := '';
      End
    Else
      Begin
        ScopeCombo.ItemIndex := Ord(HeldScope);
        PromptMemo.Text := HeldPrompt;
      End;
  Finally
    SuppressChange := False;
  End;
  ApplyEnabledState;
End;

Procedure TAssistantTaskEditorForm.ScopeComboChange(Sender: TObject);
Begin
  If Not SuppressChange Then
    ApplyEnabledState;
End;

Procedure TAssistantTaskEditorForm.ModeComboChange(Sender: TObject);
Begin
  If Not SuppressChange Then
    ApplyEnabledState;
End;

Initialization

RegisterClass(TAssistantTaskEditorForm);

End.
