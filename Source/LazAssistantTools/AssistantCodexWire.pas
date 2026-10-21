Unit AssistantCodexWire;

{ Named-permission app-server adapter. Qualification and live requests use the
  same serializers. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Function CodexNativeApprovalReply(Const Method, RequestId: String): String;
Function CodexThreadStartParams(Const WorkingDirectory, Model, DynamicToolsJson, DeveloperInstructions: String;
    TaggedTools: Boolean = True): String;
Function CodexTurnBody(Const ThreadId, TurnId, InputJson, Effort: String; Start: Boolean; Summary: Boolean = True): String;

Implementation

Uses
  SysUtils, fpjson, jsonparser, AssistantProtocol;

Function Quote(Const Value: String): String;
Begin
  Result := '"' + JsonEscapeText(Value) + '"';
End;

Function CodexNativeApprovalReply(Const Method, RequestId: String): String;
Begin
  { Permissions escalation is not a decision object. Grant nothing so the turn continues. }
  If Method = 'item/permissions/requestApproval' Then
    Result := '{"id":' + RequestId + ',"result":{"permissions":{},"scope":"turn"}}'
  Else If (Method = 'item/commandExecution/requestApproval') Or
    (Method = 'item/fileChange/requestApproval') Then
      Result := '{"id":' + RequestId + ',"result":{"decision":"decline"}}'
  Else
    Result := '{"id":' + RequestId + ',"error":{"code":-32601,"message":"Unsupported approval request"}}';
End;

Function CodexThreadStartParams(Const WorkingDirectory, Model, DynamicToolsJson, DeveloperInstructions: String;
    TaggedTools: Boolean): String;
Var
  Tools: String;
  Data: TJSONData;
  I: Integer;
Begin
  Tools := Trim(DynamicToolsJson);
  If Tools = '' Then Tools := '[]';
  If TaggedTools And (Tools <> '[]') Then
    Begin
      Data := GetJSON(Tools);
      Try
        If Not (Data Is TJSONArray) Then Raise Exception.Create('Expected dynamic tools');
        For I := 0 To Data.Count - 1 Do
          If Data.Items[I] Is TJSONObject Then
            If TJSONObject(Data.Items[I]).Find('type') = Nil Then
              TJSONObject(Data.Items[I]).Add('type', 'function');
            Tools := Data.AsJSON;
      Finally
        Data.Free;
      End;
    End;
  Result := '{"cwd":' + Quote(WorkingDirectory) +
    ',"model":' + Quote(Model) + ',"modelProvider":"openai",' +
    '"approvalPolicy":"on-request","permissions":"lazarus_ide","ephemeral":true,' +
    '"environments":[],"dynamicTools":' + Tools +
    ',"developerInstructions":' + Quote(DeveloperInstructions) +
    ',"config":{"forced_login_method":"chatgpt","model_provider":"openai"}}';
End;

Function CodexTurnBody(Const ThreadId, TurnId, InputJson, Effort: String; Start: Boolean; Summary: Boolean): String;
Begin
  If Start Then
    Begin
      Result := '{"threadId":' + Quote(ThreadId) + ',"input":' + InputJson +
        ',"approvalPolicy":"on-request","permissions":"lazarus_ide"';
      If Summary Then Result := Result + ',"summary":"auto"';
      If Effort <> '' Then Result := Result + ',"effort":' + Quote(Effort);
      Result := Result + '}';
    End
      Else
        Result := '{"threadId":' + Quote(ThreadId) + ',"expectedTurnId":' + Quote(TurnId) +
          ',"input":' + InputJson + '}';
End;

End.
