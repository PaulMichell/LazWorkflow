Program AssistantCodexEventsTest;
{$mode objfpc}{$H+}{$codepage utf8}
{ Offline, paced process events through the production worker and broker. }
Uses cthreads, SysUtils, AssistantCodexRun, AssistantCodexClient, AssistantToolBroker;
Type
  TFixtureWorkspace=Class(TAssistantWorkspaceAdapter)
    Function Identity:String; Override;
    Function Describe:String; Override;
    Function ReadBuffer(Const Path:String; Out CanonicalPath,Text,ErrorText:String):Boolean; Override;
    Function ReplaceBuffer(Const Path,ExpectedText,NewText:String; Out ErrorText:String):Boolean; Override;
    Function SaveBuffer(Const Path,ExpectedText:String; Out ErrorText:String):Boolean; Override;
    Function CanInspectFiles:Boolean; Override;
    Function ReadFile(Const Arguments:String; Out ResultText,ErrorText:String):Boolean; Override;
  End;
Function TFixtureWorkspace.Identity:String; Begin Result:='offline-events'; End;
Function TFixtureWorkspace.Describe:String; Begin Result:='{}'; End;
Function TFixtureWorkspace.ReadBuffer(Const Path:String; Out CanonicalPath,Text,ErrorText:String):Boolean;
Begin CanonicalPath:=''; Text:=''; ErrorText:='fixture file absent'; Result:=False; End;
Function TFixtureWorkspace.ReplaceBuffer(Const Path,ExpectedText,NewText:String; Out ErrorText:String):Boolean;
Begin ErrorText:='read only'; Result:=False; End;
Function TFixtureWorkspace.SaveBuffer(Const Path,ExpectedText:String; Out ErrorText:String):Boolean;
Begin ErrorText:='read only'; Result:=False; End;
Function TFixtureWorkspace.CanInspectFiles:Boolean; Begin Result:=True; End;
Function TFixtureWorkspace.ReadFile(Const Arguments:String; Out ResultText,ErrorText:String):Boolean;
Begin ResultText:=''; ErrorText:='fixture file absent'; Result:=False; End;
Procedure Check(Const Name:String; OK:Boolean);
Begin If Not OK Then Raise Exception.Create(Name); WriteLn('ok ',Name); End;
Procedure RunCase(Const Name:String);
Var Workspace:TFixtureWorkspace; Broker:TAssistantToolBroker; Run:TAssistantCodexRun;
  S:TCodexRunSnapshot; Deadline:QWord; Tool:TCodexToolRequest;
  Text,Profile:String; OK,FailedTool,Cancelled:Boolean;
Begin
  Workspace:=TFixtureWorkspace.Create; Broker:=TAssistantToolBroker.Create(Workspace);
  Profile:=GetTempFileName; DeleteFile(Profile);
  Run:=TAssistantCodexRun.Create(ExpandFileName(ParamStr(1)),GetTempDir,'offline-event-fixture',
    'CASE: '+Name,Broker.ToolsJson,Broker.BeginRun(awsReadOnly),10000,Profile,'high');
  Try
    Run.Start; Deadline:=GetTickCount64+12000; FailedTool:=False; Cancelled:=False;
    Repeat
      If Run.ServiceOneTool(Broker,Tool,Text,OK) Then
        FailedTool:=Not OK And (Text='fixture file absent');
      S:=Run.Snapshot;
      If (Name='cancel') And Not Cancelled And (S.Content<>'') Then
        Begin Run.Cancel; Cancelled:=True; End;
      Sleep(2);
    Until S.Done Or (GetTickCount64>=Deadline);
    Check(Name+' finishes',S.Done);
    If Name='final' Then
      Begin
        Check('final-only message deduplicated',S.Content='FINAL-ONLY **answer** café.');
        Check('empty reasoning stays absent',S.Thinking='');
      End
    Else
      Begin
        Check(Name+' retains partial answer',Pos('Partial **answer** retained',S.Content)>0);
        Check(Name+' retains populated thinking',Pos('Received summary detail:',S.Thinking)>0);
        If Name='thinking' Then
          Begin
            Check('failed tool serviced by broker',FailedTool);
            Check('recovery answer after failed tool',Pos('Completed after tool failure.',S.Content)>0);
          End;
      End;
    If Name='failure' Then Check('backend failure reported',Pos('FIXTURE BACKEND FAILURE',S.ErrorText)>0)
    Else If Name='disconnect' Then Check('disconnect reported',S.ErrorText<>'')
    Else If Name='cancel' Then Check('cancellation reported',S.ErrorText<>'')
    Else Check(Name+' completes without error',S.State=crsCompleted);
  Finally
    Run.Cancel; Run.WaitFor; Run.Free; Broker.Free; Workspace.Free;
    DeleteFile(Profile+'/config.toml'); RemoveDir(Profile);
  End;
End;
Begin
  If Not FileExists(ParamStr(1)) Then
    Begin WriteLn('Usage: AssistantCodexEventsTest Source/Tests/codex_event_fixture.py'); Halt(2); End;
  RunCase('thinking'); RunCase('failure'); RunCase('disconnect'); RunCase('cancel'); RunCase('final');
  WriteLn('All offline Codex event tests passed.');
End.
