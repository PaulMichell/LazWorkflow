Unit AssistantModelProvider;

{ Native model-provider boundary. Managed agent runtimes own a separate loop.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes;

Type
  TAssistantAuthentication = (aaaUnknown, aaaSubscription, aaaMeteredApiKey);
  IAssistantModelProvider = Interface
    ['{2DDCA865-E771-4FBD-A0B0-DA1E110250EF}']
    Function BackendId: String;
    Function Authentication: TAssistantAuthentication;
    Function IsSignedIn: Boolean;
    { Token is private transport state: never put it into events or history. }
    Function GetAccessToken(PersistRefresh: Boolean; Out Token, ErrorText: String): Boolean;
    Function ListModels(Const ApiBase: String; ModelIds: TStrings;
      PersistRefresh: Boolean; Out ErrorText: String): Boolean;
    Function CompleteOnce(Const ApiBase, Model, SystemPrompt, UserPrompt: String;
      PersistRefresh: Boolean; Out AnswerText, ErrorText: String): Boolean;
  End;

Function RequireSubscriptionProvider(Const Provider: IAssistantModelProvider;
    Out ErrorText: String): Boolean;

Implementation

Function RequireSubscriptionProvider(Const Provider: IAssistantModelProvider;
    Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Result := Assigned(Provider) And (Provider.Authentication = aaaSubscription);
  If Not Result Then
    ErrorText := 'This assistant requires subscription sign-in. Metered API access is disabled.';
End;
End.
