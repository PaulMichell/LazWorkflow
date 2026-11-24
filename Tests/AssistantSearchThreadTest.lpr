Program AssistantSearchThreadTest;

{ Worker dispatch for grep. No IDE form. The disk walk is not IdeThread; the editor
  overlay refuses to touch the editor manager off the IDE thread.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, AssistantToolSpecs, AssistantTools;

Type
  TSearchWorker = Class(TThread)
    DispatchGrep, DispatchSearch, CaptureAllowed: Boolean;
    Reads: Integer;
    Procedure Execute; Override;
  End;

Procedure TSearchWorker.Execute;
Var
  Paths, Texts: TStringList;
Begin
  DispatchGrep := AssistantToolNeedsIdeThread('grep');
  DispatchSearch := AssistantToolNeedsIdeThread('search_in_project');
  Paths := TStringList.Create;
  Texts := TStringList.Create;
  Try
    CaptureAllowed := AssistantCaptureSearchEditors(GetTempDir, '', Paths, Texts, Nil);
  Finally
    Texts.Free;
    Paths.Free;
  End;
  Reads := AssistantSearchEditorManagerReads;
End;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Not Condition Then
    Begin
      WriteLn('FAIL ', Title);
      Halt(1);
    End;
  WriteLn('ok   ', Title);
End;

Var
  Worker: TSearchWorker;
Begin
  AssistantResetSearchEditorManagerReads;
  Worker := TSearchWorker.Create(False);
  Try
    Worker.WaitFor;
    Check('worker grep is not dispatched to the IDE thread', Not Worker.DispatchGrep);
    Check('worker search_in_project is not dispatched to the IDE thread', Not Worker.DispatchSearch);
    Check('worker capture does not read the editor manager', (Not Worker.CaptureAllowed) And (Worker.Reads = 0));
  Finally
    Worker.Free;
  End;
  Check('read_file stays on the IDE thread', AssistantToolNeedsIdeThread('read_file'));
  Check('list_directory stays on the worker', Not AssistantToolNeedsIdeThread('list_directory'));
  Check('read_image stays on the worker', Not AssistantToolNeedsIdeThread('read_image'));
  WriteLn('AssistantSearchThreadTest passed');
End.
