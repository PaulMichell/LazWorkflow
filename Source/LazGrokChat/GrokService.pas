Unit GrokService;

{ Grok / OpenAI-compatible LLM service with streaming support (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, WorkflowLog, WorkflowEvents;

Type
  TGrokMessageRole = (gmrSystem, gmrUser, gmrAssistant, gmrTool);

  TGrokMessage = Record
    Role: TGrokMessageRole;
    Content: String;
    ToolCallId: String;
  End;

  TGrokStreamEvent = Procedure(Const Token: String; IsFinished: Boolean) Of Object;

  TGrokService = Class
  Private
    FApiBase: String;
    FApiKey: String;
    FModel: String;
    FSystemPrompt: String;
    FMessages: Array Of TGrokMessage;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure SetCredentials(Const ApiBase, ApiKey, Model: String);
    Procedure ClearHistory;
    Procedure AddMessage(Role: TGrokMessageRole; Const Content: String);
    Function SendAndStream(OnToken: TGrokStreamEvent): Boolean; { async in Phase 2 }
    Property Model: String Read FModel;
    Property SystemPrompt: String Read FSystemPrompt Write FSystemPrompt;
  End;

Var
  GrokService: TGrokService;

Implementation

Constructor TGrokService.Create;
Begin
  Inherited Create;
  FApiBase := 'https://api.x.ai/v1';
  FApiKey := '';
  FModel := 'grok-4';
  FSystemPrompt := 'You are a helpful Free Pascal / Lazarus expert working inside the IDE.';
  SetLength(FMessages, 0);
End;

Destructor TGrokService.Destroy;
Begin
  SetLength(FMessages, 0);
  Inherited Destroy;
End;

Procedure TGrokService.SetCredentials(Const ApiBase, ApiKey, Model: String);
Begin
  If ApiBase <> '' Then
    FApiBase := ApiBase;
  FApiKey := ApiKey;
  If Model <> '' Then
    FModel := Model;
  WorkflowLogger.Info('GrokService', 'Credentials updated – model=' + FModel);
End;

Procedure TGrokService.ClearHistory;
Begin
  SetLength(FMessages, 0);
End;

Procedure TGrokService.AddMessage(Role: TGrokMessageRole; Const Content: String);
Var
  Idx: Integer;
Begin
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := Role;
  FMessages[Idx].Content := Content;
  FMessages[Idx].ToolCallId := '';
End;

Function TGrokService.SendAndStream(OnToken: TGrokStreamEvent): Boolean;
Begin
  { Placeholder – Phase 2 will implement HTTP SSE streaming with fphttpclient. }
  Result := False;
  WorkflowLogger.Warning('GrokService', 'SendAndStream not yet implemented');
  If Assigned(OnToken) Then
    Begin
      OnToken('(GrokService streaming not yet implemented – Phase 2)', False);
      OnToken('', True);
    End;
End;

Initialization

GrokService := TGrokService.Create;

Finalization

FreeAndNil(GrokService);

End.
