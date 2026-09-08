Program AssistantProviderTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Classes, SysUtils,
  AssistantTestIDEHost, AssistantModelProvider, AssistantService, AssistantProtocol,
  AssistantSampler, AssistantHttps, fpjson, jsonparser;
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
Procedure TestResponsesContinuation;
Const
  OutputJson = '[' +
    '{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"encrypted_first"},' +
    '{"type":"message","id":"msg_1","role":"assistant","content":[{"type":"output_text","text":"Inventory"}]},' +
    '{"type":"function_call","id":"fc_1","call_id":"call_1","name":"get_project_info","arguments":"{}"},' +
    '{"type":"reasoning","id":"rs_2","summary":[],"encrypted_content":"encrypted_second"},' +
    '{"type":"function_call","id":"fc_2","call_id":"call_2","name":"list_directory","arguments":"{}"},' +
    '{"type":"function_call","id":"fc_3","call_id":"call_3","name":"read_skill","arguments":"{}"}]';
  DisplayCalls = '[' +
    '{"id":"call_1","function":{"name":"get_project_info","arguments":"{}"}},' +
    '{"id":"call_2","function":{"name":"list_directory","arguments":"{}"}},' +
    '{"id":"call_3","function":{"name":"read_skill","arguments":"{}"}}]';
Var Svc: TAssistantService; Parser: TAssistantSseParser;
  Items: TSamplerInputItemArray; Options: TSamplerRequestOptions;
  Request, Expected: TJSONData; Input: TJSONArray; I: Integer; Calls: String;
Begin
  Svc := TAssistantService.Create;
  Parser := TAssistantSseParser.Create;
  Try
    Svc.AddMessage(amrUser, 'list units and dependencies');
    Parser.Feed('data: {"type":"response.completed","response":{"output":' + OutputJson + '}}' + #10);
    Check('tool response parsed', Parser.Completed And Not Parser.Failed);
    Svc.AddAssistantToolCalls('Inventory', DisplayCalls, Parser.OutputJson);
    For I := 1 To 3 Do Svc.AddToolResult('call_' + IntToStr(I), 'fixture result');
    Options := DefaultSamplerRequestOptions;
    Items := Svc.ExportSamplerItems(True);
    Request := GetJSON(BuildResponsesRequestJson(Items, Options));
    Expected := GetJSON(OutputJson);
    Try
      Input := Request.FindPath('input') As TJSONArray;
      Check('follow-up contains complete output and all results', Input.Count = 11);
      For I := 0 To Expected.Count - 1 Do
        Check('response output item order and fields ' + IntToStr(I), Input.Items[I + 2].AsJSON = Expected.Items[I].AsJSON);
      For I := 0 To 2 Do
        Check('result follows its original call ' + IntToStr(I),
          (Input.Items[I + 8].FindPath('type').AsString = 'function_call_output') And
          (Input.Items[I + 8].FindPath('call_id').AsString = 'call_' + IntToStr(I + 1)));
    Finally Request.Free; Expected.Free; End;
    Svc.AddAssistantToolCalls('', '[{"id":"call_4","function":{"name":"read_file","arguments":"{}"}}]',
      '[{"type":"reasoning","id":"rs_3","summary":[],"encrypted_content":"encrypted_third"},' +
      '{"type":"function_call","id":"fc_4","call_id":"call_4","name":"read_file","arguments":"{}"}]');
    Svc.AddToolResult('call_4', 'unit Fixture;');
    Items := Svc.ExportSamplerItems(True);
    Request := GetJSON(BuildResponsesRequestJson(Items, Options));
    Try
      Input := Request.FindPath('input') As TJSONArray;
      Check('third request preserves both previous tool rounds', Input.Count = 14);
      Check('new reasoning stays ahead of new call', Input.Items[11].FindPath('id').AsString = 'rs_3');
      Check('no reasoning appended after tool output', Input.Items[13].FindPath('type').AsString = 'function_call_output');
    Finally Request.Free; End;
    Items := Svc.ExportSamplerItems(False);
    Check('chat fallback does not send opaque Responses state',
      Pos('encrypted_', BuildChatCompletionsRequestJson(Items, Options)) = 0);
    Svc.ClearHistory;
    Calls := '[{"id":"call_large","function":{"name":"write_file","arguments":"' +
      JsonEscapeText('{"content":"' + StringOfChar('x', 100100) + '"}') + '"}}]';
    Svc.AddAssistantToolCalls('', Calls);
    Svc.AddToolResult('call_large', 'saved');
    Items := Svc.ExportSamplerItems(True);
    Check('large arguments retain the real call ID', Items[1].CallId = 'call_large');
    Check('large call still matches its result', Items[2].CallId = Items[1].CallId);
    Check('structured provider error is visible',
      HttpsResponseErrorMessage('{"error":{"message":"Invalid reasoning item","code":"invalid_request"}}') = 'Invalid reasoning item');
    Check('flat provider error is visible', HttpsResponseErrorMessage('{"error":"Invalid input"}') = 'Invalid input');
    Check('raw HTML error is not dumped', HttpsResponseErrorMessage('<html>proxy</html>') = '');
    Check('provider error length is bounded', Length(HttpsResponseErrorMessage('{"message":"' + StringOfChar('x', 1200) + '"}')) = 1000);
  Finally Parser.Free; Svc.Free; End;
End;

Var Svc: TAssistantService; Fake: TFakeProvider; Provider: IAssistantModelProvider;
  Models: TStringList; Answer, Err: String; Rejected: Boolean;
Begin
  Application.Initialize;
  TestResponsesContinuation;
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
