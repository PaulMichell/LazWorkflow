Program WorkflowEventsLifetimeTest;
{$mode objfpc}{$H+}
Uses Classes, SysUtils, WorkflowEvents;
Type
  TListener = Class(TComponent, IMarkdownDocumentChanged)
  Public
    Bus: TWorkflowEventBus;
    Victim: TListener;
    Calls: Integer;
    Fail: Boolean;
    Procedure DocumentChanged(Const FileName, NewContent: String);
    Procedure DocumentSaved(Const FileName: String);
  End;
Procedure TListener.DocumentChanged(Const FileName, NewContent: String);
Begin
  Inc(Calls);
  If Assigned(Victim) Then
    Begin
      Bus.RemoveListener(Victim);
      FreeAndNil(Victim);
    End;
  If Fail Then Raise Exception.Create('Injected listener failure');
End;
Procedure TListener.DocumentSaved(Const FileName: String);
Begin
  DocumentChanged(FileName, '');
End;
Var Bus: TWorkflowEventBus; First, Last: TListener;
Begin
  Bus := TWorkflowEventBus.Create;
  First := TListener.Create(Nil);
  Last := TListener.Create(Nil);
  Try
    First.Bus := Bus;
    First.Victim := TListener.Create(Nil);
    First.Fail := True;
    Bus.AddListener(First);
    Bus.AddListener(First.Victim);
    Bus.AddListener(Last);
    Bus.NotifyDocumentChanged('fixture', '');
    If (First.Calls <> 1) Or (Last.Calls <> 1) Then
      Raise Exception.Create('A failing or removed listener disrupted delivery');
    Bus.NotifyDocumentSaved('fixture');
    If (First.Calls <> 2) Or (Last.Calls <> 2) Then
      Raise Exception.Create('Event bus did not recover');
    Bus.RemoveListener(First);
    First.Free; First := Nil;
    Bus.NotifyDocumentSaved('fixture');
    If Last.Calls <> 3 Then Raise Exception.Create('Surviving listener was lost');
    WriteLn('PASS removed forms are skipped and listener failures are isolated');
  Finally
    If Assigned(First) Then Bus.RemoveListener(First);
    Bus.RemoveListener(Last);
    First.Free; Last.Free; Bus.Free;
  End;
End.
