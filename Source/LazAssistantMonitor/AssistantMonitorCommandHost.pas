Unit AssistantMonitorCommandHost;

{ Form adapter for monitor commands. Calls run on the IDE thread. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  AssistantMonitorCommands;

Procedure RegisterMonitorFormCommands;
Procedure UnregisterMonitorFormCommands;

Implementation

Uses
  SysUtils, ProjectAssistantForm, AssistantConversation, AssistantSaveBeforeTurn;

Type
  TFormCommandHost = Class(TMonitorCommandHost)
  Public
    Function KnownTurn(Const CommandId: String; Out TurnId: String): Boolean; Override;
    Function Send(Const Text: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer; Override;
    Function Steer(Const Text: String): TMonitorHostAnswer; Override;
    Function Stop: TMonitorHostAnswer; Override;
    Function StopPlan: TMonitorHostAnswer; Override;
    Function SetMode(Const ModeText: String): TMonitorHostAnswer; Override;
    Function NewConversation: TMonitorHostAnswer; Override;
    Function SelectConversation(Const ConversationId: String): TMonitorHostAnswer; Override;
    Function SelectPlan(Const Path: String): TMonitorHostAnswer; Override;
    Function NewPlan(Const Title: String): TMonitorHostAnswer; Override;
    Function ClosePlan: TMonitorHostAnswer; Override;
    Function RunPlan(SaveFirst: Boolean): TMonitorHostAnswer; Override;
    Function WorkOnPlan(SectionIndex: Integer): TMonitorHostAnswer; Override;
    Function RunTask(Const TaskId, Note: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer; Override;
    Function InsertTask(Const TaskId, Note: String): TMonitorHostAnswer; Override;
  End;

Var
  FormHost: TFormCommandHost;

Function MapFormAnswer(Ok: Boolean; Const ErrorText, TurnId: String): TMonitorHostAnswer;
Begin
  Result.Ok := Ok;
  Result.Message := ErrorText;
  Result.TurnId := TurnId;
  If Ok Then
    Result.Reason := ''
  Else If ErrorText = AssistantUnsavedEditsReason Then
    Result.Reason := 'unsaved_edits'
  Else
    Result.Reason := 'busy';
End;

Function TFormCommandHost.KnownTurn(Const CommandId: String; Out TurnId: String): Boolean;
Var
  Form: TProjectAssistantForm;
  Turn: TConversationTurn;
Begin
  TurnId := '';
  Form := OpenProjectAssistantForm;
  Result := Assigned(Form) And Form.TurnForClientCommand(CommandId, Turn);
  If Result Then
    TurnId := Turn.Id;
End;

Function TFormCommandHost.Send(Const Text: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText, TurnId: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteSubmit(Text, SaveFirst, ErrorText, CommandId), ErrorText, '');
  If Result.Ok And KnownTurn(CommandId, TurnId) Then
    Result.TurnId := TurnId;
End;

Function TFormCommandHost.Steer(Const Text: String): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteSteer(Text, ErrorText), ErrorText, '');
End;

Function TFormCommandHost.Stop: TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteStop(ErrorText), ErrorText, '');
End;

Function TFormCommandHost.StopPlan: TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteStopPlan(ErrorText), ErrorText, '');
End;

Function TFormCommandHost.SetMode(Const ModeText: String): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteSelectMode(ModeText, ErrorText), ErrorText, '');
End;

Function TFormCommandHost.NewConversation: TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteNewConversation(ErrorText), ErrorText, '');
End;

Function TFormCommandHost.SelectConversation(Const ConversationId: String): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteSelectConversation(ConversationId, ErrorText), ErrorText, '');
End;

Function TFormCommandHost.SelectPlan(Const Path: String): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteSelectPlan(Path, ErrorText), ErrorText, '');
End;

Function TFormCommandHost.NewPlan(Const Title: String): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteNewPlan(Title, ErrorText), ErrorText, '');
End;

Function TFormCommandHost.ClosePlan: TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteClosePlan(ErrorText), ErrorText, '');
End;

Function TFormCommandHost.RunPlan(SaveFirst: Boolean): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteRunPlan(SaveFirst, ErrorText), ErrorText, '');
End;

Function TFormCommandHost.WorkOnPlan(SectionIndex: Integer): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteWorkOnPlan(SectionIndex, ErrorText), ErrorText, '');
End;

Function TFormCommandHost.RunTask(Const TaskId, Note: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText, TurnId: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteRunTask(TaskId, Note, SaveFirst, ErrorText, CommandId), ErrorText, '');
  If Result.Ok And KnownTurn(CommandId, TurnId) Then
    Result.TurnId := TurnId;
End;

Function TFormCommandHost.InsertTask(Const TaskId, Note: String): TMonitorHostAnswer;
Var
  Form: TProjectAssistantForm;
  ErrorText, ApiText: String;
Begin
  Form := OpenProjectAssistantForm;
  If Not Assigned(Form) Then
    Exit(MapFormAnswer(False, 'The assistant window is closed.', ''));
  Result := MapFormAnswer(Form.RemoteInsertTask(TaskId, Note, ApiText, ErrorText), ErrorText, '');
  If Result.Ok Then
    Result.Message := ApiText;
End;

Procedure RegisterMonitorFormCommands;
Begin
  If Not Assigned(FormHost) Then
    FormHost := TFormCommandHost.Create;
  SetMonitorCommandHost(FormHost);
End;

Procedure UnregisterMonitorFormCommands;
Begin
  SetMonitorCommandHost(Nil);
  FreeAndNil(FormHost);
End;

End.
