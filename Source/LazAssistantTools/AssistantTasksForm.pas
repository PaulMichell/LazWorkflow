Unit AssistantTasksForm;

{ Tasks list dialog. Does not send, format, or switch mode (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ActnList, AssistantTasks;

Type
  TAssistantTasksForm = Class(TForm)
    ActionList: TActionList;
    RunAction: TAction;
    InsertAction: TAction;
    EditAction: TAction;
    NewAction: TAction;
    DuplicateAction: TAction;
    RemoveAction: TAction;
    CloseAction: TAction;
    MoveUpAction: TAction;
    MoveDownAction: TAction;
    ButtonStrip: TPanel;
    RunButton: TButton;
    InsertButton: TButton;
    EditButton: TButton;
    NewButton: TButton;
    DuplicateButton: TButton;
    RemoveButton: TButton;
    CloseButton: TButton;
    BodyPanel: TPanel;
    ListPanel: TPanel;
    ShowHiddenCheck: TCheckBox;
    TaskList: TListBox;
    MoveStrip: TPanel;
    UpButton: TButton;
    DownButton: TButton;
    PreviewPanel: TPanel;
    TitleValue: TLabel;
    ModeValue: TLabel;
    ScopeValue: TLabel;
    SummaryValue: TLabel;
    PromptLabel: TLabel;
    PromptMemo: TMemo;
    Procedure FormCreate(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure ShowHiddenCheckChange(Sender: TObject);
    Procedure TaskListClick(Sender: TObject);
    Procedure TaskListDblClick(Sender: TObject);
    Procedure TaskListKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure RunActionExecute(Sender: TObject);
    Procedure InsertActionExecute(Sender: TObject);
    Procedure EditActionExecute(Sender: TObject);
    Procedure NewActionExecute(Sender: TObject);
    Procedure DuplicateActionExecute(Sender: TObject);
    Procedure RemoveActionExecute(Sender: TObject);
    Procedure CloseActionExecute(Sender: TObject);
    Procedure MoveUpActionExecute(Sender: TObject);
    Procedure MoveDownActionExecute(Sender: TObject);
  Private
    StoredTasks: TAssistantTaskArray;
    VisibleIndexes: Array Of Integer;
    ListDirty: Boolean;
    FillingList: Boolean;
    AllowRun: Boolean;
    LoadNote: String;
    ChosenRequest: TAssistantTaskRequest;
    Procedure LoadStoredTasks;
    Procedure FillList;
    Procedure SelectTaskId(Const TaskId: String);
    Function SelectedStoredIndex: Integer;
    Procedure UpdatePreview;
    Procedure RefreshTaskActions;
    Procedure MarkDirty;
    Function SaveIfDirty: Boolean;
    Function CopyId(Const Title: String): String;
    Procedure FinishPrepared(Kind: TAssistantTaskRequestKind);
  End;

/// Modal list. True when Run or Insert prepared a request. Does not send or change mode.
Function ShowAssistantTasksForm(CanRun: Boolean; Out Request: TAssistantTaskRequest): Boolean;

Implementation

{$R *.lfm}

Uses
  Dialogs, LCLType, AssistantTaskEditorForm;

Function ShowAssistantTasksForm(CanRun: Boolean; Out Request: TAssistantTaskRequest): Boolean;
Var
  Form: TAssistantTasksForm;
Begin
  ClearAssistantTaskRequest(Request);
  Result := False;
  Form := TAssistantTasksForm.Create(Nil);
  Try
    Form.AllowRun := CanRun;
    If Form.ShowModal = mrOk Then
      Begin
        Request := Form.ChosenRequest;
        Result := Request.Kind <> trkNone;
      End;
  Finally
    Form.Free;
  End;
End;

Function ModeCaption(Mode: TAssistantTaskMode): String;
Begin
  Case Mode Of
    tmInspect: Result := 'Inspect';
    tmDocument: Result := 'Document';
    tmPlan: Result := 'Plan';
    tmBuild: Result := 'Build';
    tmChat: Result := 'Chat';
  Else
    Result := 'Inspect';
  End;
End;

Function ScopeCaption(Scope: TAssistantTaskScope): String;
Begin
  Case Scope Of
    tsNone: Result := 'None';
    tsActiveEditor: Result := 'Active editor';
    tsSelection: Result := 'Selection';
    tsChangedFiles: Result := 'Changed files';
    tsMessages: Result := 'Messages';
    tsUserNote: Result := 'User note';
  Else
    Result := 'None';
  End;
End;

Function PrepareListedTask(Const Task: TAssistantTask; Kind: TAssistantTaskRequestKind;
  Out Request: TAssistantTaskRequest; Out ErrorText: String): Boolean;
Var
  Evidence: TAssistantTaskEvidence;
  Expanded: String;
Begin
  Result := False;
  ClearAssistantTaskRequest(Request);
  ErrorText := '';
  If Task.Hidden Then
    Begin
      ErrorText := 'This task is hidden.';
      Exit;
    End;
  If (Kind = trkRun) And (Not Task.Enabled) Then
    Begin
      ErrorText := 'This task is disabled.';
      Exit;
    End;
  If Assigned(PrepareAssistantTaskRequest) Then
    Begin
      Result := PrepareAssistantTaskRequest(Task, Kind, Request, ErrorText);
      Exit;
    End;
  { No IDE evidence yet. Required scopes fail here and the list stays open. }
  If Task.Kind = tkFormat Then
    Begin
      ErrorText := 'Active editor is required.';
      Exit;
    End;
  Evidence.ProjectName := '';
  Evidence.ActiveFile := '';
  Evidence.Cursor := '';
  Evidence.Selection := '';
  Evidence.Messages := '';
  Evidence.GitStatus := '';
  Evidence.GitDiff := '';
  Evidence.UserNote := '';
  If Not ExpandAssistantTaskPrompt(Task, Evidence, Expanded, ErrorText) Then
    Exit;
  Request.Kind := Kind;
  Request.Task := Task;
  Request.Mode := Task.Mode;
  Request.DisplayLabel := 'Task: ' + Task.Title;
  Request.ApiText := Expanded;
  Request.FreshConversation := Task.FreshConversation;
  Request.DocumentPath := Task.DocumentPath;
  Result := True;
End;

Procedure TAssistantTasksForm.LoadStoredTasks;
Var
  FromCatalog: Boolean;
Begin
  LoadNote := '';
  If Not LoadAssistantTasks(StoredTasks, FromCatalog, LoadNote) Then
    Exit;
  LoadNote := '';
End;

Procedure TAssistantTasksForm.SelectTaskId(Const TaskId: String);
Var
  I: Integer;
Begin
  For I := 0 To High(VisibleIndexes) Do
    If SameText(StoredTasks[VisibleIndexes[I]].Id, TaskId) Then
      Begin
        TaskList.ItemIndex := I;
        Exit;
      End;
  If TaskList.Items.Count > 0 Then
    TaskList.ItemIndex := 0;
End;

Procedure TAssistantTasksForm.FillList;
Var
  I, Selected: Integer;
  KeepId, RowText: String;
Begin
  KeepId := '';
  Selected := SelectedStoredIndex;
  If Selected >= 0 Then
    KeepId := StoredTasks[Selected].Id;
  FillingList := True;
  Try
    TaskList.Items.BeginUpdate;
    Try
      TaskList.Clear;
      SetLength(VisibleIndexes, 0);
      For I := 0 To High(StoredTasks) Do
        Begin
          If StoredTasks[I].Hidden And (Not ShowHiddenCheck.Checked) Then
            Continue;
          SetLength(VisibleIndexes, Length(VisibleIndexes) + 1);
          VisibleIndexes[High(VisibleIndexes)] := I;
          RowText := StoredTasks[I].Title;
          If Not StoredTasks[I].Enabled Then
            RowText := RowText + ' (disabled)';
          TaskList.Items.Add(RowText);
        End;
    Finally
      TaskList.Items.EndUpdate;
    End;
  Finally
    FillingList := False;
  End;
  If KeepId <> '' Then
    SelectTaskId(KeepId)
  Else If TaskList.Items.Count > 0 Then
    TaskList.ItemIndex := 0;
  UpdatePreview;
  RefreshTaskActions;
End;

Function TAssistantTasksForm.SelectedStoredIndex: Integer;
Begin
  Result := -1;
  If FillingList Then
    Exit;
  If (TaskList.ItemIndex < 0) Or (TaskList.ItemIndex > High(VisibleIndexes)) Then
    Exit;
  Result := VisibleIndexes[TaskList.ItemIndex];
End;

Procedure TAssistantTasksForm.UpdatePreview;
Var
  Index: Integer;
Begin
  If FillingList Then
    Exit;
  Index := SelectedStoredIndex;
  If Index < 0 Then
    Begin
      TitleValue.Caption := '';
      ModeValue.Caption := 'Mode:';
      ScopeValue.Caption := 'Scope:';
      SummaryValue.Caption := '';
      PromptMemo.Text := '';
      Exit;
    End;
  TitleValue.Caption := StoredTasks[Index].Title;
  ModeValue.Caption := 'Mode: ' + ModeCaption(StoredTasks[Index].Mode);
  ScopeValue.Caption := 'Scope: ' + ScopeCaption(StoredTasks[Index].Scope);
  SummaryValue.Caption := StoredTasks[Index].Summary;
  PromptMemo.Text := StoredTasks[Index].Prompt;
End;

Procedure TAssistantTasksForm.RefreshTaskActions;
Var
  Index, ListIndex: Integer;
  Task: TAssistantTask;
Begin
  Index := SelectedStoredIndex;
  ListIndex := TaskList.ItemIndex;
  NewAction.Enabled := True;
  EditAction.Enabled := Index >= 0;
  DuplicateAction.Enabled := Index >= 0;
  RemoveAction.Enabled := Index >= 0;
  MoveUpAction.Enabled := ListIndex > 0;
  MoveDownAction.Enabled := (ListIndex >= 0) And (ListIndex < TaskList.Items.Count - 1);
  InsertAction.Enabled := False;
  RunAction.Enabled := False;
  RunAction.Hint := 'Run the selected task';
  If Index < 0 Then
    Exit;
  Task := StoredTasks[Index];
  InsertAction.Enabled := Not Task.Hidden;
  If Task.Hidden Then
    RunAction.Hint := 'This task is hidden.'
  Else If Not Task.Enabled Then
    RunAction.Hint := 'This task is disabled.'
  Else If Not AllowRun Then
    RunAction.Hint := 'Wait for the current reply to finish.'
  Else
    RunAction.Enabled := True;
End;

Procedure TAssistantTasksForm.MarkDirty;
Begin
  ListDirty := True;
End;

Function TAssistantTasksForm.SaveIfDirty: Boolean;
Var
  ErrorText: String;
Begin
  Result := True;
  If Not ListDirty Then
    Exit;
  If SaveAssistantTasks(StoredTasks, ErrorText) Then
    ListDirty := False
  Else
    Begin
      MessageDlg(ErrorText, mtError, [mbOK], 0);
      Result := False;
    End;
End;

Function TAssistantTasksForm.CopyId(Const Title: String): String;
Var
  Base, Suffix: String;
  I, Number: Integer;
  C: Char;
Begin
  Base := '';
  For I := 1 To Length(Title) Do
    Begin
      C := Title[I];
      If (C >= 'A') And (C <= 'Z') Then
        C := Chr(Ord(C) + 32);
      If ((C >= 'a') And (C <= 'z')) Or ((C >= '0') And (C <= '9')) Then
        Base := Base + C
      Else If (C = ' ') Or (C = '-') Or (C = '_') Then
        If (Base <> '') And (Base[Length(Base)] <> '-') Then
          Base := Base + '-';
    End;
  If Base = '' Then
    Base := 'task';
  If Length(Base) > 50 Then
    Base := Copy(Base, 1, 50);
  Result := Base;
  Number := 2;
  While FindAssistantTask(StoredTasks, Result) >= 0 Do
    Begin
      Suffix := '-' + IntToStr(Number);
      Result := Copy(Base, 1, 64 - Length(Suffix)) + Suffix;
      Inc(Number);
    End;
End;

Procedure TAssistantTasksForm.FinishPrepared(Kind: TAssistantTaskRequestKind);
Var
  Index: Integer;
  Request: TAssistantTaskRequest;
  ErrorText: String;
Begin
  Index := SelectedStoredIndex;
  If Index < 0 Then
    Exit;
  If Not SaveIfDirty Then
    Exit;
  If Not PrepareListedTask(StoredTasks[Index], Kind, Request, ErrorText) Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'This task cannot be prepared.';
      MessageDlg(ErrorText, mtInformation, [mbOK], 0);
      Exit;
    End;
  ChosenRequest := Request;
  ModalResult := mrOk;
End;

Procedure TAssistantTasksForm.FormCreate(Sender: TObject);
Begin
  AllowRun := True;
  ListDirty := False;
  FillingList := False;
  LoadNote := '';
  SetLength(VisibleIndexes, 0);
  SetLength(StoredTasks, 0);
  ClearAssistantTaskRequest(ChosenRequest);
  LoadStoredTasks;
  FillList;
End;

Procedure TAssistantTasksForm.FormShow(Sender: TObject);
Begin
  RefreshTaskActions;
  If LoadNote = '' Then
    Exit;
  MessageDlg(LoadNote, mtWarning, [mbOK], 0);
  LoadNote := '';
End;

Procedure TAssistantTasksForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Begin
  CanClose := SaveIfDirty;
End;

Procedure TAssistantTasksForm.FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  If Key <> VK_ESCAPE Then
    Exit;
  Key := 0;
  CloseAction.Execute;
End;

Procedure TAssistantTasksForm.ShowHiddenCheckChange(Sender: TObject);
Begin
  If Not FillingList Then
    FillList;
End;

Procedure TAssistantTasksForm.TaskListClick(Sender: TObject);
Begin
  UpdatePreview;
  RefreshTaskActions;
End;

Procedure TAssistantTasksForm.TaskListDblClick(Sender: TObject);
Begin
  If RunAction.Enabled Then
    RunAction.Execute;
End;

Procedure TAssistantTasksForm.TaskListKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  If (Key <> VK_RETURN) Or (Not RunAction.Enabled) Then
    Exit;
  Key := 0;
  RunAction.Execute;
End;

Procedure TAssistantTasksForm.RunActionExecute(Sender: TObject);
Begin
  If RunAction.Enabled Then
    FinishPrepared(trkRun);
End;

Procedure TAssistantTasksForm.InsertActionExecute(Sender: TObject);
Begin
  If InsertAction.Enabled Then
    FinishPrepared(trkInsert);
End;

Procedure TAssistantTasksForm.EditActionExecute(Sender: TObject);
Var
  Index: Integer;
  Task: TAssistantTask;
Begin
  Index := SelectedStoredIndex;
  If Index < 0 Then
    Exit;
  Task := StoredTasks[Index];
  If Not ShowAssistantTaskEditor(Task, False) Then
    Exit;
  StoredTasks[Index] := Task;
  MarkDirty;
  FillList;
  SelectTaskId(Task.Id);
  UpdatePreview;
  RefreshTaskActions;
End;

Procedure TAssistantTasksForm.NewActionExecute(Sender: TObject);
Var
  Task: TAssistantTask;
Begin
  Task.Id := CopyId('task');
  Task.Title := '';
  Task.Summary := '';
  Task.Mode := tmInspect;
  Task.Kind := tkPrompt;
  Task.Scope := tsNone;
  Task.MessageFilter := mfNone;
  Task.CompileFirst := False;
  Task.FreshConversation := False;
  Task.Enabled := True;
  Task.Hidden := False;
  Task.DocumentPath := '';
  Task.BuiltinId := '';
  Task.Prompt := '';
  If Not ShowAssistantTaskEditor(Task, True) Then
    Exit;
  If FindAssistantTask(StoredTasks, Task.Id) >= 0 Then
    Task.Id := CopyId(Task.Title);
  SetLength(StoredTasks, Length(StoredTasks) + 1);
  StoredTasks[High(StoredTasks)] := Task;
  MarkDirty;
  FillList;
  SelectTaskId(Task.Id);
  UpdatePreview;
  RefreshTaskActions;
End;

Procedure TAssistantTasksForm.DuplicateActionExecute(Sender: TObject);
Var
  Index, I: Integer;
  CopyTask: TAssistantTask;
Begin
  Index := SelectedStoredIndex;
  If Index < 0 Then
    Exit;
  CopyTask := StoredTasks[Index];
  CopyTask.Title := StoredTasks[Index].Title + ' copy';
  CopyTask.Id := CopyId(CopyTask.Title);
  CopyTask.BuiltinId := '';
  CopyTask.Hidden := False;
  SetLength(StoredTasks, Length(StoredTasks) + 1);
  For I := High(StoredTasks) DownTo Index + 2 Do
    StoredTasks[I] := StoredTasks[I - 1];
  StoredTasks[Index + 1] := CopyTask;
  MarkDirty;
  FillList;
  SelectTaskId(CopyTask.Id);
  UpdatePreview;
  RefreshTaskActions;
End;

Procedure TAssistantTasksForm.RemoveActionExecute(Sender: TObject);
Var
  Index, I: Integer;
  PromptText: String;
Begin
  Index := SelectedStoredIndex;
  If Index < 0 Then
    Exit;
  If StoredTasks[Index].BuiltinId <> '' Then
    PromptText := 'Hide "' + StoredTasks[Index].Title + '"? It can be restored with Show hidden.'
  Else
    PromptText := 'Delete "' + StoredTasks[Index].Title + '"? This cannot be undone.';
  If MessageDlg(PromptText, mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  If StoredTasks[Index].BuiltinId <> '' Then
    StoredTasks[Index].Hidden := True
  Else
    Begin
      For I := Index To High(StoredTasks) - 1 Do
        StoredTasks[I] := StoredTasks[I + 1];
      SetLength(StoredTasks, Length(StoredTasks) - 1);
    End;
  MarkDirty;
  FillList;
End;

Procedure TAssistantTasksForm.CloseActionExecute(Sender: TObject);
Begin
  ModalResult := mrCancel;
End;

Procedure TAssistantTasksForm.MoveUpActionExecute(Sender: TObject);
Var
  ListIndex, StoredIndex, Other: Integer;
  Moved: TAssistantTask;
Begin
  ListIndex := TaskList.ItemIndex;
  If ListIndex < 1 Then
    Exit;
  StoredIndex := VisibleIndexes[ListIndex];
  Other := VisibleIndexes[ListIndex - 1];
  Moved := StoredTasks[StoredIndex];
  StoredTasks[StoredIndex] := StoredTasks[Other];
  StoredTasks[Other] := Moved;
  MarkDirty;
  FillList;
  SelectTaskId(Moved.Id);
End;

Procedure TAssistantTasksForm.MoveDownActionExecute(Sender: TObject);
Var
  ListIndex, StoredIndex, Other: Integer;
  Moved: TAssistantTask;
Begin
  ListIndex := TaskList.ItemIndex;
  If (ListIndex < 0) Or (ListIndex >= TaskList.Items.Count - 1) Then
    Exit;
  StoredIndex := VisibleIndexes[ListIndex];
  Other := VisibleIndexes[ListIndex + 1];
  Moved := StoredTasks[StoredIndex];
  StoredTasks[StoredIndex] := StoredTasks[Other];
  StoredTasks[Other] := Moved;
  MarkDirty;
  FillList;
  SelectTaskId(Moved.Id);
End;

Initialization

RegisterClass(TAssistantTasksForm);

End.
