#!/usr/bin/env instantfpc
Program CodexEventFixture;

{ Offline App Server fixture for live IDE acceptance. Never contacts a provider.
  (c) 2026 Michell Computing.

  The Linux Codex transport executes this file. InstantFPC is the interpreter.
  AssistantCodexEventsTest marks it executable before launch. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
  {$CODEPAGE UTF8}
{$ENDIF}

Uses
  Classes, SysUtils, fpjson, jsonparser;

Procedure Send(Data: TJSONData);
Begin
  WriteLn(Data.AsJSON);
  Flush(Output);
  Data.Free;
End;

Function EventRoot(Const Method: String): TJSONObject;
Var
  Params: TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('method', Method);
  Params := TJSONObject.Create;
  Params.Add('threadId', 'fixture-thread');
  Params.Add('turnId', 'fixture-turn');
  Result.Add('params', Params);
End;

Procedure SummaryDelta(Const ItemId: String; SummaryIndex: Integer; Const Delta: String);
Var
  Root, Params: TJSONObject;
Begin
  Root := EventRoot('item/reasoning/summaryTextDelta');
  Params := TJSONObject(Root.Find('params'));
  Params.Add('itemId', ItemId);
  Params.Add('summaryIndex', SummaryIndex);
  Params.Add('delta', Delta);
  Send(Root);
End;

Procedure MessageDelta(Const ItemId, Text: String);
Var
  Root, Params: TJSONObject;
Begin
  Root := EventRoot('item/agentMessage/delta');
  Params := TJSONObject(Root.Find('params'));
  Params.Add('itemId', ItemId);
  Params.Add('delta', Text);
  Send(Root);
End;

Procedure MessageComplete(Const ItemId, Text: String);
Var
  Root, Item: TJSONObject;
Begin
  Root := EventRoot('item/completed');
  Item := TJSONObject.Create;
  Item.Add('id', ItemId);
  Item.Add('type', 'agentMessage');
  Item.Add('text', Text);
  TJSONObject(Root.Find('params')).Add('item', Item);
  Send(Root);
End;

Procedure FinishTurn(Const Status: String; Const ErrorMessage: String);
Var
  Root, Turn, ErrorObj: TJSONObject;
Begin
  Root := EventRoot('turn/completed');
  Turn := TJSONObject.Create;
  Turn.Add('id', 'fixture-turn');
  Turn.Add('status', Status);
  If ErrorMessage <> '' Then
    Begin
      ErrorObj := TJSONObject.Create;
      ErrorObj.Add('message', ErrorMessage);
      Turn.Add('error', ErrorObj);
    End;
  TJSONObject(Root.Find('params')).Add('turn', Turn);
  Send(Root);
End;

Procedure Reply(IdNode: TJSONData; ResultObj: TJSONObject);
Var
  Root: TJSONObject;
Begin
  Root := TJSONObject.Create;
  If IdNode.JSONType = jtNumber Then
    Root.Add('id', IdNode.AsInteger)
  Else
    Root.Add('id', IdNode.AsString);
  Root.Add('result', ResultObj);
  Send(Root);
End;

Function PromptText(Request: TJSONObject): String;
Var
  Params, Input: TJSONData;
Begin
  Result := '';
  Params := Request.Find('params');
  If Not (Params Is TJSONObject) Then
    Exit;
  Input := TJSONObject(Params).Find('input');
  If Not (Input Is TJSONArray) Or (TJSONArray(Input).Count = 0) Then
    Exit;
  If Not (TJSONArray(Input).Items[0] Is TJSONObject) Then
    Exit;
  Result := LowerCase(TJSONObject(TJSONArray(Input).Items[0]).Get('text', ''));
End;

Function CaseName(Const Prompt: String): String;
Const
  Names: Array[0..4] Of String = ('thinking', 'failure', 'disconnect', 'cancel', 'final');
Var
  I: Integer;
Begin
  Result := 'thinking';
  For I := 0 To High(Names) Do
    If Pos('case: ' + Names[I], Prompt) > 0 Then
      Exit(Names[I]);
End;

Procedure EmptyReasoning;
Var
  Root, Item: TJSONObject;
Begin
  Root := EventRoot('item/completed');
  Item := TJSONObject.Create;
  Item.Add('id', 'empty-reasoning');
  Item.Add('type', 'reasoning');
  Item.Add('summary', TJSONArray.Create);
  Item.Add('content', TJSONArray.Create);
  TJSONObject(Root.Find('params')).Add('item', Item);
  Send(Root);
End;

Procedure ToolCall;
Var
  Root, Params, Args: TJSONObject;
Begin
  Root := TJSONObject.Create;
  Root.Add('id', 'fixture-tool-request');
  Root.Add('method', 'item/tool/call');
  Params := TJSONObject.Create;
  Params.Add('threadId', 'fixture-thread');
  Params.Add('turnId', 'fixture-turn');
  Params.Add('callId', 'fixture-tool');
  Params.Add('tool', 'lazarus_read_file');
  Args := TJSONObject.Create;
  Args.Add('path', 'missing-acceptance-fixture.pas');
  Params.Add('arguments', Args);
  Root.Add('params', Params);
  Send(Root);
End;

Function IdText(Node: TJSONData): String;
Begin
  If Node = Nil Then
    Result := ''
  Else If Node.JSONType = jtString Then
    Result := Node.AsString
  Else
    Result := Node.AsJSON;
End;

Var
  Line, Chosen: String;
  Request: TJSONData;
  Obj, Account, ResultObj: TJSONObject;
  IdNode: TJSONData;
  Method: String;
  I: Integer;
Begin
  For I := 1 To ParamCount Do
    If ParamStr(I) = '--version' Then
      Begin
        WriteLn('codex-cli 0.153.4');
        Flush(Output);
        Sleep(100);
        Halt(0);
      End;
  Chosen := '';
  While Not Eof Do
    Begin
      ReadLn(Line);
      If Trim(Line) = '' Then
        Continue;
      Request := GetJSON(Line);
      Try
        If Not (Request Is TJSONObject) Then
          Continue;
        Obj := TJSONObject(Request);
        IdNode := Obj.Find('id');
        If (IdNode = Nil) Or (IdNode.JSONType = jtNull) Then
          Continue;
        Method := Obj.Get('method', '');
        If Method = 'initialize' Then
          Begin
            ResultObj := TJSONObject.Create;
            ResultObj.Add('userAgent', 'codex/0.153.4');
            Reply(IdNode, ResultObj);
          End
        Else If Method = 'account/read' Then
          Begin
            ResultObj := TJSONObject.Create;
            Account := TJSONObject.Create;
            Account.Add('type', 'chatgpt');
            ResultObj.Add('account', Account);
            ResultObj.Add('requiresOpenaiAuth', True);
            Reply(IdNode, ResultObj);
          End
        Else If Method = 'mcpServerStatus/list' Then
          Begin
            ResultObj := TJSONObject.Create;
            ResultObj.Add('data', TJSONArray.Create);
            ResultObj.Add('nextCursor', TJSONNull.Create);
            Reply(IdNode, ResultObj);
          End
        Else If Method = 'model/list' Then
          Begin
            ResultObj := TJSONObject.Create;
            Account := TJSONObject.Create;
            Account.Add('id', 'offline-event-fixture');
            ResultObj.Add('data', TJSONArray.Create);
            TJSONArray(ResultObj.Find('data')).Add(Account);
            ResultObj.Add('nextCursor', TJSONNull.Create);
            Reply(IdNode, ResultObj);
          End
        Else If Method = 'thread/start' Then
          Begin
            ResultObj := TJSONObject.Create;
            ResultObj.Add('modelProvider', 'openai');
            ResultObj.Add('approvalPolicy', 'on-request');
            Account := TJSONObject.Create;
            Account.Add('type', 'readOnly');
            ResultObj.Add('sandbox', Account);
            Account := TJSONObject.Create;
            Account.Add('id', 'fixture-thread');
            ResultObj.Add('thread', Account);
            Reply(IdNode, ResultObj);
          End
        Else If Method = 'turn/start' Then
          Begin
            Chosen := CaseName(PromptText(Obj));
            ResultObj := TJSONObject.Create;
            Account := TJSONObject.Create;
            Account.Add('id', 'fixture-turn');
            Account.Add('status', 'inProgress');
            ResultObj.Add('turn', Account);
            Reply(IdNode, ResultObj);
            If Chosen = 'final' Then
              Begin
                EmptyReasoning;
                MessageComplete('answer', 'FINAL-ONLY **answer** café.');
                MessageComplete('answer', 'FINAL-ONLY **answer** café.');
                FinishTurn('completed', '');
                Continue;
              End;
            SummaryDelta('reasoning-1', 0, '**Checking the fixture**');
            Sleep(600);
            SummaryDelta('reasoning-1', 1, 'Received summary detail: preserve both paragraphs and UTF-8 café.');
            Sleep(600);
            MessageDelta('answer', 'Partial **answer** retained before the next event.');
            Sleep(600);
            If Chosen = 'failure' Then
              FinishTurn('failed', 'FIXTURE BACKEND FAILURE: retryable test error')
            Else If Chosen = 'disconnect' Then
              Halt(0)
            Else If Chosen = 'thinking' Then
              ToolCall;
          End
        Else If Method = 'turn/interrupt' Then
          Begin
            Reply(IdNode, TJSONObject.Create);
            FinishTurn('interrupted', '');
          End
        Else If Method = 'turn/steer' Then
          Reply(IdNode, TJSONObject.Create)
        Else If (Method = '') And (IdText(IdNode) = 'fixture-tool-request') Then
          Begin
            Sleep(600);
            SummaryDelta('reasoning-2', 0, 'The IDE returned the missing-file result; preserve the failed tool detail.');
            Sleep(600);
            MessageComplete('final', 'Completed after tool failure.' + LineEnding + LineEnding +
              '| Check | Result |' + LineEnding + '| --- | --- |' + LineEnding +
              '| Received thinking | Present |' + LineEnding + '| Failed tool | Retained |');
            FinishTurn('completed', '');
          End;
      Finally
        Request.Free;
      End;
    End;
End.
