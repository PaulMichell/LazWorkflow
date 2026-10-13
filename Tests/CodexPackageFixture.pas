#!/usr/bin/env instantfpc
Program CodexPackageFixture;

{ Offline, opt-in live IDE package acceptance. Only edits PackageTargetCheck.
  (c) 2026 Michell Computing.

  Requires the disposable fixture from Tests/CreatePackageTargetFixture.pas.
  No network or account access. The Linux Codex transport executes this file. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
  {$CODEPAGE UTF8}
{$ENDIF}

Uses
  Classes, SysUtils, fpjson, jsonparser;

Var
  CallCount, BuildPolls, TestPolls: Integer;
  Step: Integer;
  Failed: Boolean;
  UnitText, Revision, BuildJob, TestJob: String;

Procedure Send(Data: TJSONData);
Begin
  WriteLn(Data.AsJSON);
  Flush(Output);
  Data.Free;
End;

Procedure MessageComplete(Const Text: String);
Var
  Root, Params, Item: TJSONObject;
Begin
  Root := TJSONObject.Create;
  Root.Add('method', 'item/completed');
  Params := TJSONObject.Create;
  Params.Add('threadId', 'fixture-thread');
  Params.Add('turnId', 'fixture-turn');
  Item := TJSONObject.Create;
  Item.Add('id', 'answer');
  Item.Add('type', 'agentMessage');
  Item.Add('text', Text);
  Params.Add('item', Item);
  Root.Add('params', Params);
  Send(Root);
End;

Procedure FinishTurn(Const Status, ErrorMessage: String);
Var
  Root, Params, Turn, ErrorObj: TJSONObject;
Begin
  Root := TJSONObject.Create;
  Root.Add('method', 'turn/completed');
  Params := TJSONObject.Create;
  Params.Add('threadId', 'fixture-thread');
  Params.Add('turnId', 'fixture-turn');
  Turn := TJSONObject.Create;
  Turn.Add('id', 'fixture-turn');
  Turn.Add('status', Status);
  If ErrorMessage <> '' Then
    Begin
      ErrorObj := TJSONObject.Create;
      ErrorObj.Add('message', ErrorMessage);
      Turn.Add('error', ErrorObj);
    End;
  Params.Add('turn', Turn);
  Root.Add('params', Params);
  Send(Root);
End;

Procedure FailAcceptance(Const Reason: String);
Begin
  If Failed Then
    Exit;
  Failed := True;
  MessageComplete('PACKAGE ACCEPTANCE FAILED: ' + Reason);
  FinishTurn('failed', Reason);
End;

Procedure SendCall(Const ToolName: String; Args: TJSONObject);
Var
  Root, Params: TJSONObject;
Begin
  Inc(CallCount);
  Root := TJSONObject.Create;
  Root.Add('id', 'package-' + IntToStr(CallCount));
  Root.Add('method', 'item/tool/call');
  Params := TJSONObject.Create;
  Params.Add('threadId', 'fixture-thread');
  Params.Add('turnId', 'fixture-turn');
  Params.Add('callId', 'call-' + IntToStr(CallCount));
  Params.Add('tool', ToolName);
  If Args = Nil Then
    Args := TJSONObject.Create;
  Params.Add('arguments', Args);
  Root.Add('params', Params);
  Send(Root);
End;

Function HasTarget(Value: TJSONData): Boolean;
Const
  Needle = 'Target: Package — PackageTargetCheck.lpk';
Var
  I: Integer;
Begin
  Result := False;
  If Value = Nil Then
    Exit;
  If Value.JSONType = jtString Then
    Result := Pos(Needle, Value.AsString) > 0
  Else If Value Is TJSONObject Then
    For I := 0 To TJSONObject(Value).Count - 1 Do
      If TJSONObject(Value).Names[I] = Needle Then
        Exit(True);
End;

Procedure Advance(Value: TJSONData);
Var
  Args: TJSONObject;
  Text: String;
Begin
  If Failed Or (Step = 10) Then
    Exit;
  Case Step Of
    0:
      Begin
        Step := 1;
        SendCall('lazarus_project_info', Nil);
      End;
    1:
      Begin
        If Not HasTarget(Value) Then
          Begin
            FailAcceptance('Select the disposable PackageTargetCheck package first.');
            Exit;
          End;
        Step := 2;
        Args := TJSONObject.Create;
        Args.Add('path', 'Source/PackageUnit.pas');
        SendCall('lazarus_open_buffer', Args);
      End;
    2:
      Begin
        If Not (Value Is TJSONObject) Then
          Begin
            FailAcceptance('Expected the untouched disposable unit fixture.');
            Exit;
          End;
        UnitText := TJSONObject(Value).Get('text', '');
        Revision := TJSONObject(Value).Get('revision', '');
        If Pos('Result := 42;', UnitText) = 0 Then
          Begin
            FailAcceptance('Expected the untouched disposable unit fixture.');
            Exit;
          End;
        Step := 3;
        Args := TJSONObject.Create;
        Args.Add('path', 'Source/PackageUnit.pas');
        Args.Add('revision', Revision);
        Args.Add('text', StringReplace(UnitText, 'Result := 42;', 'Result := 43;', [rfReplaceAll]));
        SendCall('lazarus_replace_buffer', Args);
      End;
    3:
      Begin
        Step := 4;
        Args := TJSONObject.Create;
        Args.Add('path', 'Source/PackageUnit.pas');
        SendCall('lazarus_read_buffer', Args);
      End;
    4:
      Begin
        If Not (Value Is TJSONObject) Then
          Begin
            FailAcceptance('Buffer read did not return a revision.');
            Exit;
          End;
        Step := 5;
        Args := TJSONObject.Create;
        Args.Add('path', 'Source/PackageUnit.pas');
        Args.Add('revision', TJSONObject(Value).Get('revision', ''));
        SendCall('lazarus_save_buffer', Args);
      End;
    5:
      Begin
        Step := 6;
        SendCall('lazarus_start_build', Nil);
      End;
    6:
      Begin
        If Not (Value Is TJSONObject) Then
          Begin
            FailAcceptance('Build did not return a job id.');
            Exit;
          End;
        BuildJob := TJSONObject(Value).Get('job_id', '');
        Step := 7;
        BuildPolls := 0;
        Sleep(250);
        Args := TJSONObject.Create;
        Args.Add('job_id', BuildJob);
        SendCall('lazarus_build_status', Args);
      End;
    7:
      Begin
        Inc(BuildPolls);
        If Not (Value Is TJSONObject) Then
          Begin
            FailAcceptance('Package build failed: ' + Value.AsJSON);
            Exit;
          End;
        If TJSONObject(Value).Get('done', False) Then
          Begin
            If TJSONObject(Value).Get('outcome', '') <> 'compile_passed' Then
              Begin
                FailAcceptance('Package build failed: ' + Value.AsJSON);
                Exit;
              End;
            Step := 8;
            Args := TJSONObject.Create;
            Args.Add('build_job_id', BuildJob);
            SendCall('lazarus_start_tests', Args);
            Exit;
          End;
        If BuildPolls >= 240 Then
          Begin
            FailAcceptance('Build did not finish within the fixture poll limit.');
            Exit;
          End;
        Sleep(250);
        Args := TJSONObject.Create;
        Args.Add('job_id', BuildJob);
        SendCall('lazarus_build_status', Args);
      End;
    8:
      Begin
        If Not (Value Is TJSONObject) Then
          Begin
            FailAcceptance('Tests did not return a job id.');
            Exit;
          End;
        TestJob := TJSONObject(Value).Get('job_id', '');
        Step := 9;
        TestPolls := 0;
        Sleep(250);
        Args := TJSONObject.Create;
        Args.Add('job_id', TestJob);
        SendCall('lazarus_test_status', Args);
      End;
    9:
      Begin
        Inc(TestPolls);
        If Not (Value Is TJSONObject) Then
          Begin
            FailAcceptance('Package tests failed: ' + Value.AsJSON);
            Exit;
          End;
        If TJSONObject(Value).Get('done', False) Then
          Begin
            If TJSONObject(Value).Get('outcome', '') <> 'test_command_passed' Then
              Begin
                FailAcceptance('Package tests failed: ' + Value.AsJSON);
                Exit;
              End;
            Step := 10;
            MessageComplete('PACKAGE ACCEPTANCE PASSED: inspected, edited and saved the selected ' +
              'package unit; compiled its .lpk; ran its configured behavioural test.');
            FinishTurn('completed', '');
            Exit;
          End;
        If TestPolls >= 120 Then
          Begin
            FailAcceptance('Tests did not finish within the fixture poll limit.');
            Exit;
          End;
        Sleep(250);
        Args := TJSONObject.Create;
        Args.Add('job_id', TestJob);
        SendCall('lazarus_test_status', Args);
      End;
  Else
    FailAcceptance('Package acceptance ended in an unknown step.');
  End;
End;

Function JoinedText(ResultObj: TJSONObject): String;
Var
  Items: TJSONData;
  I: Integer;
  Piece: String;
Begin
  Result := '';
  Items := ResultObj.Find('contentItems');
  If Not (Items Is TJSONArray) Then
    Exit;
  For I := 0 To TJSONArray(Items).Count - 1 Do
    Begin
      If Not (TJSONArray(Items).Items[I] Is TJSONObject) Then
        Continue;
      Piece := TJSONObject(TJSONArray(Items).Items[I]).Get('text', '');
      If Result <> '' Then
        Result := Result + #10;
      Result := Result + Piece;
    End;
End;

Function ParseValue(Const Text: String): TJSONData;
Begin
  Try
    Result := GetJSON(Text);
  Except
    Result := TJSONString.Create(Text);
  End;
End;

Procedure HandleLine(Const Line: String);
Var
  Request, Value: TJSONData;
  Obj, ResultObj, Account: TJSONObject;
  IdNode: TJSONData;
  Method, Ident, Text: String;
Begin
  Request := GetJSON(Line);
  Try
    If Not (Request Is TJSONObject) Then
      Exit;
    Obj := TJSONObject(Request);
    IdNode := Obj.Find('id');
    If (IdNode = Nil) Or (IdNode.JSONType = jtNull) Then
      Exit;
    If IdNode.JSONType = jtString Then
      Ident := IdNode.AsString
    Else
      Ident := IdNode.AsJSON;
    Method := Obj.Get('method', '');
    ResultObj := TJSONObject.Create;
    If Method = 'initialize' Then
      ResultObj.Add('userAgent', 'codex/0.153.4')
    Else If Method = 'account/read' Then
      Begin
        Account := TJSONObject.Create;
        Account.Add('type', 'chatgpt');
        ResultObj.Add('account', Account);
        ResultObj.Add('requiresOpenaiAuth', True);
      End
    Else If Method = 'mcpServerStatus/list' Then
      Begin
        ResultObj.Add('data', TJSONArray.Create);
        ResultObj.Add('nextCursor', TJSONNull.Create);
      End
    Else If Method = 'model/list' Then
      Begin
        Account := TJSONObject.Create;
        Account.Add('id', 'offline-package-fixture');
        ResultObj.Add('data', TJSONArray.Create);
        TJSONArray(ResultObj.Find('data')).Add(Account);
        ResultObj.Add('nextCursor', TJSONNull.Create);
      End
    Else If Method = 'thread/start' Then
      Begin
        ResultObj.Add('modelProvider', 'openai');
        ResultObj.Add('approvalPolicy', 'on-request');
        Account := TJSONObject.Create;
        Account.Add('type', 'readOnly');
        ResultObj.Add('sandbox', Account);
        Account := TJSONObject.Create;
        Account.Add('id', 'fixture-thread');
        ResultObj.Add('thread', Account);
      End
    Else If Method = 'turn/start' Then
      Begin
        Account := TJSONObject.Create;
        Account.Add('id', 'fixture-turn');
        Account.Add('status', 'inProgress');
        ResultObj.Add('turn', Account);
        Account := TJSONObject.Create;
        If IdNode.JSONType = jtNumber Then
          Account.Add('id', IdNode.AsInteger)
        Else
          Account.Add('id', IdNode.AsString);
        Account.Add('result', ResultObj);
        Send(Account);
        Advance(Nil);
        Exit;
      End
    Else If (Method = '') And (Copy(Ident, 1, 8) = 'package-') Then
      Begin
        ResultObj.Free;
        ResultObj := Nil;
        If Not (Obj.Find('result') Is TJSONObject) Then
          Begin
            FailAcceptance('Tool result was not an object.');
            Exit;
          End;
        ResultObj := TJSONObject(Obj.Find('result'));
        Text := JoinedText(ResultObj);
        If Not ResultObj.Get('success', False) Then
          Begin
            FailAcceptance(Text);
            Exit;
          End;
        Value := ParseValue(Text);
        Try
          Advance(Value);
        Finally
          Value.Free;
        End;
        Exit;
      End
    Else If Method = 'turn/interrupt' Then
      Begin
        Account := TJSONObject.Create;
        If IdNode.JSONType = jtNumber Then
          Account.Add('id', IdNode.AsInteger)
        Else
          Account.Add('id', IdNode.AsString);
        Account.Add('result', ResultObj);
        Send(Account);
        FinishTurn('interrupted', '');
        Exit;
      End;
    Account := TJSONObject.Create;
    If IdNode.JSONType = jtNumber Then
      Account.Add('id', IdNode.AsInteger)
    Else
      Account.Add('id', IdNode.AsString);
    Account.Add('result', ResultObj);
    Send(Account);
  Finally
    Request.Free;
  End;
End;

Var
  Line: String;
  I: Integer;
Begin
  For I := 1 To ParamCount Do
    If ParamStr(I) = '--version' Then
      Begin
        WriteLn('codex-cli 0.153.4');
        Flush(Output);
        Halt(0);
      End;
  CallCount := 0;
  BuildPolls := 0;
  TestPolls := 0;
  Step := 0;
  Failed := False;
  While Not Eof Do
    Begin
      ReadLn(Line);
      If Trim(Line) = '' Then
        Continue;
      HandleLine(Line);
    End;
End.
