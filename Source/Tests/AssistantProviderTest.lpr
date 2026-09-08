Program AssistantProviderTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Classes, SysUtils,
  AssistantTestIDEHost, AssistantModelProvider, AssistantService;
Type
  TFakeProvider = Class(TInterfacedObject, IAssistantModelProvider)
    Auth: TAssistantAuthentication;
    OnceCount, ModelCount: Integer;
    Function BackendId: String;
    Function Authentication: TAssistantAuthentication;
    Function IsSignedIn: Boolean;
    Function GetAccessToken(PersistRefresh: Boolean; Out Token, ErrorText: String): Boolean;
    Function ListModels(Const ApiBase: String; ModelIds: TStrings;
      PersistRefresh: Boolean; Out ErrorText: String): Boolean;
    Function CompleteOnce(Const ApiBase, Model, SystemPrompt, UserPrompt: String;
      PersistRefresh: Boolean; Out AnswerText, ErrorText: String): Boolean;
  End;
Function TFakeProvider.BackendId: String;
Begin Result := 'test-subscription'; End;
Function TFakeProvider.Authentication: TAssistantAuthentication;
Begin Result := Auth; End;
Function TFakeProvider.IsSignedIn: Boolean;
Begin Result := True; End;
Function TFakeProvider.GetAccessToken(PersistRefresh: Boolean; Out Token, ErrorText: String): Boolean;
Begin Token := ''; ErrorText := 'No live transport in tests'; Result := False; End;
Function TFakeProvider.ListModels(Const ApiBase: String; ModelIds: TStrings;
  PersistRefresh: Boolean; Out ErrorText: String): Boolean;
Begin Inc(ModelCount); ModelIds.Add('fixture-model'); ErrorText := ''; Result := True; End;
Function TFakeProvider.CompleteOnce(Const ApiBase, Model, SystemPrompt, UserPrompt: String;
  PersistRefresh: Boolean; Out AnswerText, ErrorText: String): Boolean;
Begin Inc(OnceCount); AnswerText := 'fixture answer'; ErrorText := ''; Result := True; End;
Procedure Check(Const Title: String; Value: Boolean);
Begin If Not Value Then Begin WriteLn(StdErr, 'FAIL ', Title); Halt(1); End; WriteLn('ok ', Title); End;
Var Svc: TAssistantService; Fake: TFakeProvider; Provider: IAssistantModelProvider;
  Models: TStringList; Answer, Err: String; Rejected: Boolean;
Begin
  Application.Initialize;
  Fake := TFakeProvider.Create;
  Provider := Fake;
  Svc := TAssistantService.Create;
  Models := TStringList.Create;
  Try
    Check('nil provider denied', Not RequireSubscriptionProvider(Nil, Err));
    Check('unknown authentication denied', Not RequireSubscriptionProvider(Provider, Err));
    Fake.Auth := aaaMeteredApiKey;
    Rejected := False;
    Try Svc.SetModelProvider(Provider); Except On E: Exception Do Rejected := True; End;
    Check('metered provider cannot be installed', Rejected);
    Fake.Auth := aaaSubscription;
    Svc.AddMessage(amrUser, 'old provider history');
    Svc.SetModelProvider(Provider);
    Check('provider change clears foreign history', Svc.MessageCount = 0);
    Check('sign-in delegates', Svc.IsSignedIn);
    Check('models delegate', Svc.ListAvailableModels(Models, Err) And (Fake.ModelCount = 1));
    Check('one-shot delegates', Svc.CompleteOnce('system', 'user', Answer, Err) And
      (Answer = 'fixture answer') And (Fake.OnceCount = 1));
    Fake.Auth := aaaMeteredApiKey;
    Check('changed auth cannot send one-shot', Not Svc.CompleteOnce('', '', Answer, Err));
    Check('denied one-shot not dispatched', Fake.OnceCount = 1);
    Check('changed auth cannot list models', Not Svc.ListAvailableModels(Models, Err));
    Check('denied model listing not dispatched', Fake.ModelCount = 1);
    Fake.Auth := aaaUnknown;
    Check('unknown auth cannot stream', Not Svc.StartStream(Nil));
  Finally
    Svc.Free; Models.Free; Provider := Nil;
  End;
End.
