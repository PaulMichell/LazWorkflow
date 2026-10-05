Program AssistantCodexHandshakeTest;
{$mode objfpc}{$H+}
Uses Classes, SysUtils, fpjson, jsonparser, AssistantCodexHandshake;
Procedure Check(Const Title: String; Value: Boolean);
Begin If Not Value Then Raise Exception.Create(Title); WriteLn('ok ', Title); End;
Function Take(Session: TAssistantCodexHandshake; Const Method: String): Int64;
Var Frame: String; Data: TJSONData;
Begin
  Check('outgoing ' + Method, Session.TakeOutgoing(Frame));
  Data := GetJSON(Frame);
  Try
    Check('method ' + Method, TJSONObject(Data).Get('method', '') = Method);
    Check('App Server omits jsonrpc header', Data.FindPath('jsonrpc') = Nil);
    Result := TJSONObject(Data).Get('id', Int64(0));
    If Method = 'account/login/start' Then
      Check('only managed ChatGPT login', (Data.FindPath('params.type').AsString = 'chatgptDeviceCode') Or
        (Data.FindPath('params.type').AsString = 'chatgpt'));
  Finally Data.Free; End;
End;
Procedure Reply(Session: TAssistantCodexHandshake; Id: Int64; Const Body: String);
Begin Session.Feed('{"id":' + IntToStr(Id) + ',"result":' + Body + '}' + #10); End;
Function TakeLogin(Session: TAssistantCodexHandshake; Out Id: Int64): String;
Var
  RequestFrame: String;
  Data: TJSONData;
Begin
  Check('outgoing login', Session.TakeOutgoing(RequestFrame));
  Data := GetJSON(RequestFrame);
  Try
    Check('login method', TJSONObject(Data).Get('method', '') = 'account/login/start');
    Result := Data.FindPath('params.type').AsString;
    Id := TJSONObject(Data).Get('id', Int64(0));
  Finally
    Data.Free;
  End;
End;
Function Initialize(Session: TAssistantCodexHandshake): Int64;
Var Id: Int64; Frame: String; I: Integer;
Begin
  Session.Close;
  Session.Start;
  Id := Take(Session, 'initialize');
  Frame := '{"id":' + IntToStr(Id) + ',"result":{"userAgent":"fixture"}}' + #13#10;
  For I := 1 To Length(Frame) Do Session.Feed(Frame[I]);
  Take(Session, 'initialized');
  Result := Take(Session, 'account/read');
End;
Var Session: TAssistantCodexHandshake; Id, OldId: Int64; Frame: String; Args: TStringList;
Begin
  Session := TAssistantCodexHandshake.Create;
  Args := TStringList.Create;
  Try
    CodexSubscriptionArguments(Args);
    Check('runtime forced to ChatGPT login', Args.IndexOf('forced_login_method="chatgpt"') >= 0);
    Check('runtime forced to OpenAI provider', Args.IndexOf('model_provider="openai"') >= 0);
    Check('automatic ChatGPT app connectors disabled', Args.IndexOf('features.apps=false') >= 0);
    Check('minimal filesystem profile defined', Args.IndexOf('permissions.lazarus_ide.filesystem={":minimal"="read"}') >= 0);
    Check('profile command network disabled', Args.IndexOf('permissions.lazarus_ide.network.enabled=false') >= 0);
    Check('private stdio transport', Args.IndexOf('stdio://') >= 0);
    Id := Initialize(Session);
    Check('handshake checks account', Session.State = ccsCheckingAccount);
    Reply(Session, Id + 1000, '{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}');
    Check('uncorrelated response ignored', Session.State = ccsCheckingAccount);
    Reply(Session, Id, '{"account":{"type":"apiKey"},"requiresOpenaiAuth":true}');
    Check('API-key authentication rejected', Session.State = ccsNeedsSignIn);
    Check('no automatic fallback or login', Not Session.TakeOutgoing(Frame));
    Session.StartChatGPTLogin;
    Id := Take(Session, 'account/login/start');
    Reply(Session, Id, '{"type":"chatgpt","loginId":"login1","authUrl":"https://auth.openai.com/authorize?fixture=1"}');
    Check('managed login URL exposed', Pos('https://auth.openai.com/', Session.LoginUrl) = 1);
    Session.Feed('{"method":"account/login/completed","params":{"loginId":"other","success":true}}' + #10);
    Check('unrelated login notification ignored', Session.State = ccsSigningIn);
    Session.Feed('{"method":"account/login/completed","params":{"loginId":"login1","success":true}}' + #10);
    Id := Take(Session, 'account/read');
    Reply(Session, Id, '{"account":{"type":"chatgpt","planType":"plus"},"requiresOpenaiAuth":true}');
    Check('ChatGPT account accepted', Session.State = ccsSubscriptionAuthenticated);
    Check('login URL cleared after completion', Session.LoginUrl = '');
    Session.Feed('{"method":"account/updated","params":{"authMode":"apikey"}}' + #10);
    Check('auth change revokes readiness', Session.State = ccsNeedsSignIn);
    Id := Initialize(Session);
    Session.Feed('{"method":"account/updated","params":{"authMode":"chatgpt"}}' + #10);
    OldId := Id;
    Id := Take(Session, 'account/read');
    Reply(Session, OldId, '{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}');
    Check('stale account reply ignored', Session.State = ccsCheckingAccount);
    Reply(Session, Id, '{"account":{"type":"chatgpt"},"requiresOpenaiAuth":false}');
    Check('external provider configuration rejected', Session.State = ccsNeedsSignIn);
    Id := Initialize(Session);
    Reply(Session, Id, '{"account":null,"requiresOpenaiAuth":true}');
    Check('signed-out state handled', Session.State = ccsNeedsSignIn);
    Session.StartChatGPTLogin;
    Id := Take(Session, 'account/login/start');
    Reply(Session, Id, '{"type":"chatgpt","loginId":"login2","authUrl":"https://auth.openai.com.evil.example/login"}');
    Check('unexpected sign-in host rejected', Session.State = ccsFailed);
    Id := Initialize(Session);
    Session.Feed('{"id":"server-tool","method":"item/tool/call","params":{}}' + #10);
    Check('unsupported server tool gets rejection', Session.TakeOutgoing(Frame) And (Pos('"code":-32601', Frame) > 0));
    Session.Close;
    Reply(Session, Id, '{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}');
    Check('closed connection ignores late replies', Session.State = ccsClosed);
    Session.Start;
    Take(Session, 'initialize');
    Session.Feed('not-json' + #10);
    Check('malformed frame fails closed', Session.State = ccsFailed);
    Initialize(Session);
    Session.Feed(StringOfChar('x', 1048577));
    Check('oversized frame fails closed', Session.State = ccsFailed);
    Id := Initialize(Session);
    Reply(Session, Id, '{"account":null,"requiresOpenaiAuth":true}');
    Session.StartChatGPTLogin;
    Check('browser login is started first', TakeLogin(Session, Id) = 'chatgpt');
    Session.Feed('{"id":' + IntToStr(Id) + ',"error":{"code":-32602,"message":"unsupported"}}' + #10);
    Check('device code is only the fallback', TakeLogin(Session, Id) = 'chatgptDeviceCode');
    Reply(Session, Id, '{"type":"chatgptDeviceCode","loginId":"login3","verificationUrl":"https://auth.openai.com/codex/device","userCode":"FJA4-C6AMZ"}');
    Check('fallback code is kept', (Session.UserCode = 'FJA4-C6AMZ') And (Session.State = ccsSigningIn));
  Finally Args.Free; Session.Free; End;
End.
