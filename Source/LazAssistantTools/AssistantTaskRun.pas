Unit AssistantTaskRun;

{ Prepare a task run: collect evidence, or refuse before anything is sent (c) 2026 Michell Computing.

  Does not use ProjectAssistantForm and does not start build-work tracking.
  A format task is not sent. It formats the editor buffer and does not save. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantTasks;

Type
  TAssistantTaskPreparation = (tpMissing, tpReady, tpFormatted);
  TQueryAssistantTaskHostBusy = Function(Out Reason: String): Boolean;
  TPostAssistantTaskSystemNote = Procedure(Const NoteText: String);

/// True when a turn or plan run is active. An empty reason becomes the wait sentence.
Function HostIsBusy(Out ErrorText: String): Boolean;
/// Ready fills Request. Missing sets ErrorText and does not send. Formatted means the host
/// already applied a format task and nothing should be sent.
Function PrepareAssistantTaskRun(Const Task: TAssistantTask; Kind: TAssistantTaskRequestKind;
  Out Request: TAssistantTaskRequest; Out ErrorText: String): TAssistantTaskPreparation;
/// Dialog-free preparation. Does not call AskForNote, TryApplyFormat, or CompileLikeReview.
Function PrepareAssistantTaskRunWithNote(Const Task: TAssistantTask; Kind: TAssistantTaskRequestKind;
  Const Note: String; Out Request: TAssistantTaskRequest; Out ErrorText: String): TAssistantTaskPreparation;

Var
  { The assistant form assigns these. Nil means the runner cannot see a turn or post a note. }
  QueryAssistantTaskHostBusy: TQueryAssistantTaskHostBusy;
  PostAssistantTaskSystemNote: TPostAssistantTaskSystemNote;

Implementation

Uses
  Types, Controls, Forms, Dialogs, LazIDEIntf, SrcEditorIntf, IDEMsgIntf, IDEExternToolIntf, PackageIntf,
  CompOptsIntf,
  LazFileUtils, fpjson, jsonparser, AssistantGit, AssistantWorkTarget, AssistantTaskNoteForm,
  AssistantEditorEdits, PascalStyleFormat;

Const
  UnsavedDiffNote = 'Unsaved editor text is not in the diff.';
  ErrorsTaskTitle = 'Fix compiler errors';

Function HostIsBusy(Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(QueryAssistantTaskHostBusy) Then
    Exit;
  Result := QueryAssistantTaskHostBusy(ErrorText);
  If Result And (ErrorText = '') Then
    ErrorText := 'Wait for the current reply to finish.';
End;

Function ShortPath(Const FileName: String): String;
Var
  Root, Full, Base: String;
Begin
  Result := StringReplace(FileName, '\', '/', [rfReplaceAll]);
  Root := ExcludeTrailingPathDelimiter(AssistantTarget.Root);
  If (Root = '') Or (FileName = '') Then
    Exit;
  Full := ExpandFileName(FileName);
  Base := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  If CompareFilenames(Copy(Full, 1, Length(Base)), Base) = 0 Then
    Result := StringReplace(Copy(Full, Length(Base) + 1, MaxInt), '\', '/', [rfReplaceAll]);
End;

Function ActiveEditor: TSourceEditorInterface;
Begin
  Result := Nil;
  If Assigned(SourceEditorManagerIntf) Then
    Result := SourceEditorManagerIntf.ActiveEditor;
End;

Function EditorInsideTarget(Editor: TSourceEditorInterface): Boolean;
Begin
  Result := Assigned(Editor) And (Editor.FileName <> '') And AssistantTarget.ContainsFile(Editor.FileName);
End;

Function EditorRefusal(Out ErrorText: String): Boolean;
Var
  Editor: TSourceEditorInterface;
Begin
  Result := True;
  ErrorText := '';
  Editor := ActiveEditor;
  If Not Assigned(Editor) Then
    Begin
      ErrorText := 'There is no active editor.';
      Exit;
    End;
  If Editor.FileName = '' Then
    Begin
      ErrorText := 'The active editor has no file name.';
      Exit;
    End;
  If Not EditorInsideTarget(Editor) Then
    Begin
      ErrorText := 'The active editor is outside the selected package.';
      Exit;
    End;
  Result := False;
End;

Procedure ClearEvidence(Out Evidence: TAssistantTaskEvidence);
Begin
  Evidence.ProjectName := '';
  Evidence.ActiveFile := '';
  Evidence.Cursor := '';
  Evidence.Selection := '';
  Evidence.Messages := '';
  Evidence.GitStatus := '';
  Evidence.GitDiff := '';
  Evidence.UserNote := '';
End;

Procedure FillEditorEvidence(Var Evidence: TAssistantTaskEvidence);
Var
  Editor: TSourceEditorInterface;
  Cursor: TPoint;
Begin
  Evidence.ProjectName := AssistantTarget.DisplayName;
  Evidence.ActiveFile := '';
  Evidence.Cursor := '';
  Evidence.Selection := '';
  Editor := ActiveEditor;
  If Not Assigned(Editor) Then
    Exit;
  Evidence.Selection := Editor.Selection;
  If Editor.FileName = '' Then
    Exit;
  Cursor := Editor.CursorTextXY;
  Evidence.Cursor := 'line ' + IntToStr(Cursor.Y) + ', column ' + IntToStr(Cursor.X);
  Evidence.ActiveFile := ShortPath(Editor.FileName);
End;

Function FormatMessageLine(Line: TMessageLine): String;
Var
  Loc: String;
Begin
  Result := '';
  If Not Assigned(Line) Then
    Exit;
  If Trim(Line.OriginalLine) <> '' Then
    Begin
      Result := Line.OriginalLine;
      Exit;
    End;
  Loc := '';
  If Line.Filename <> '' Then
    Begin
      Loc := Line.GetFullFilename;
      If Line.Line > 0 Then
        Begin
          Loc := Loc + '(' + IntToStr(Line.Line);
          If Line.Column > 0 Then
            Loc := Loc + ',' + IntToStr(Line.Column);
          Loc := Loc + ')';
        End;
    End;
  If Loc <> '' Then
    Result := Loc + ' '
  Else
    Result := '';
  If Line.Urgency In [mluHint..mluPanic] Then
    Result := Result + MessageLineUrgencyNames[Line.Urgency] + ': ';
  If Line.TranslatedMsg <> '' Then
    Result := Result + Line.TranslatedMsg
  Else
    Result := Result + Line.Msg;
  Result := Trim(Result);
End;

Function LineMatches(Filter: TAssistantTaskMessageFilter; Urgency: TMessageLineUrgency): Boolean;
Begin
  Case Filter Of
    mfErrors: Result := Urgency In [mluError, mluFatal, mluPanic];
    mfWarnings: Result := Urgency = mluWarning;
    mfHints: Result := Urgency In [mluHint, mluNote];
    mfAll: Result := Urgency In [mluHint, mluNote, mluWarning, mluImportant, mluError, mluFatal, mluPanic];
  Else
    Result := False;
  End;
End;

Procedure ReadMessages(Filter: TAssistantTaskMessageFilter; Out Text: String; Out ErrorCount, MatchCount: Integer);
Var
  ViewIndex, LineIndex: Integer;
  View: TExtToolView;
  Line: TMessageLine;
  Parts: TStringList;
  Formatted: String;
Begin
  Text := '';
  ErrorCount := 0;
  MatchCount := 0;
  If Not Assigned(IDEMessagesWindow) Then
    Exit;
  Parts := TStringList.Create;
  Try
    For ViewIndex := 0 To IDEMessagesWindow.ViewCount - 1 Do
      Begin
        View := IDEMessagesWindow.Views[ViewIndex];
        If Not Assigned(View) Then
          Continue;
        View.Lines.EnterCriticalSection;
        Try
          For LineIndex := 0 To View.Lines.Count - 1 Do
            Begin
              Line := View.Lines.Items[LineIndex];
              If Not Assigned(Line) Then
                Continue;
              If Line.Urgency In [mluError, mluFatal, mluPanic] Then
                Inc(ErrorCount);
              If Not LineMatches(Filter, Line.Urgency) Then
                Continue;
              Formatted := FormatMessageLine(Line);
              If Formatted = '' Then
                Continue;
              Parts.Add(Formatted);
              Inc(MatchCount);
            End;
        Finally
          View.Lines.LeaveCriticalSection;
        End;
      End;
    Text := TrimRight(Parts.Text);
  Finally
    Parts.Free;
  End;
End;

Function CompileLikeReview(Out ErrorText: String): Boolean;
Var
  BuildResult: TModalResult;
Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(LazarusIDE) Then
    Begin
      ErrorText := 'Lazarus is not available to compile.';
      Exit;
    End;
  If Not AssistantTarget.Available Then
    Begin
      ErrorText := 'Select a project or package before compiling.';
      Exit;
    End;
  Try
    If AssistantTarget.Kind = atkPackage Then
      Begin
        If Not Assigned(PackageEditingInterface) Or Not Assigned(AssistantTarget.Package) Then
          Begin
            ErrorText := 'The selected package cannot be compiled.';
            Exit;
          End;
        BuildResult := PackageEditingInterface.DoCompilePackage(AssistantTarget.Package, [pcfDoNotSaveEditorFiles], False);
      End
    Else
      BuildResult := LazarusIDE.DoBuildProject(crCompile, []);
  Except
    On E: Exception Do
      Begin
        ErrorText := 'Compile failed to start: ' + E.Message;
        Exit;
      End;
  End;
  If BuildResult <> mrOk Then
    Begin
      ErrorText := 'Compile did not finish.';
      Exit;
    End;
  Result := True;
End;

Function GitArguments(Const Args: Array Of String): String;
Var
  I: Integer;
Begin
  Result := '{"arguments":[';
  For I := 0 To High(Args) Do
    Begin
      If I > 0 Then
        Result := Result + ',';
      Result := Result + '"' + Args[I] + '"';
    End;
  Result := Result + ']}';
End;

Function GitOutput(Const Root, Arguments: String; Out Output, ErrorText: String): Boolean;
Var
  Reply, Err: String;
  Data: TJSONData;
  ExitCode: Integer;
Begin
  Result := False;
  Output := '';
  ErrorText := '';
  Reply := '';
  Err := '';
  RunAssistantGit(Root, Arguments, Reply, Err);
  If Trim(Reply) = '' Then
    Begin
      ErrorText := Err;
      If ErrorText = '' Then
        ErrorText := 'Git did not return a result.';
      Exit;
    End;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Reply);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Git returned an unexpected result.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Git returned an unexpected result.';
        Exit;
      End;
    Output := TJSONObject(Data).Get('output', '');
    ExitCode := TJSONObject(Data).Get('exit_code', -1);
    If TJSONObject(Data).Get('timed_out', False) Then
      Begin
        ErrorText := 'Git timed out.';
        Exit;
      End;
    { diff exits 1 when saved changes exist. That is still a usable diff. }
    If (ExitCode = 0) Or (ExitCode = 1) Then
      Result := True
    Else
      Begin
        ErrorText := Err;
        If ErrorText = '' Then
          ErrorText := 'Git failed with exit code ' + IntToStr(ExitCode) + '.';
      End;
  Finally
    Data.Free;
  End;
End;

Function ChangedFileCount(Const Status: String): Integer;
Var
  Lines: TStringList;
  I: Integer;
Begin
  Result := 0;
  Lines := TStringList.Create;
  Try
    Lines.Text := Status;
    For I := 0 To Lines.Count - 1 Do
      If Trim(Lines[I]) <> '' Then
        Inc(Result);
  Finally
    Lines.Free;
  End;
End;

Function CollectSavedDiff(Out Status, Diff, ErrorText: String): Boolean;
Var
  Root: String;
Begin
  Result := False;
  Status := '';
  Diff := '';
  ErrorText := '';
  Root := ExcludeTrailingPathDelimiter(AssistantTarget.Root);
  If Root = '' Then
    Begin
      ErrorText := 'There is no working root.';
      Exit;
    End;
  If Not WorkingRootHasGitRepository(Root) Then
    Begin
      ErrorText := 'This working root has no Git repository.';
      Exit;
    End;
  If Not GitOutput(Root, GitArguments(['status', '--porcelain']), Status, ErrorText) Then
    Exit;
  If Not GitOutput(Root, GitArguments(['diff', 'HEAD']), Diff, ErrorText) Then
    Begin
      ErrorText := '';
      If Not GitOutput(Root, GitArguments(['diff']), Diff, ErrorText) Then
        Exit;
    End;
  If (Trim(Status) = '') And (Trim(Diff) = '') Then
    Begin
      ErrorText := 'There are no saved changes to review.';
      Exit;
    End;
  If Trim(Diff) = '' Then
    Diff := UnsavedDiffNote
  Else
    Diff := TrimRight(Diff) + LineEnding + UnsavedDiffNote;
  Result := True;
End;

Function TaskLabel(Const Title, Detail: String): String;
Begin
  If Detail = '' Then
    Result := 'Task: ' + Title
  Else
    Result := 'Task: ' + Title + ' — ' + Detail;
End;

Function MessageDetail(Filter: TAssistantTaskMessageFilter; Count: Integer): String;
Begin
  Case Filter Of
    mfErrors: Result := IntToStr(Count) + ' error(s)';
    mfWarnings: Result := IntToStr(Count) + ' warning(s)';
    mfHints: Result := IntToStr(Count) + ' hint(s)';
    mfAll: Result := IntToStr(Count) + ' message(s)';
  Else
    Result := '';
  End;
End;

Function ChangedDetail(Count: Integer): String;
Begin
  If Count = 1 Then
    Result := '1 changed file'
  Else
    Result := IntToStr(Count) + ' changed files';
End;

Function MessagesRefusal(Filter: TAssistantTaskMessageFilter; ErrorCount, MatchCount: Integer;
  Out ErrorText: String): Boolean;
Begin
  Result := True;
  ErrorText := '';
  If (Filter = mfHints) And (ErrorCount > 0) Then
    Begin
      ErrorText := 'Compiler errors remain. Run ' + ErrorsTaskTitle + ' first.';
      Exit;
    End;
  If (Filter = mfErrors) And (MatchCount = 0) Then
    Begin
      ErrorText := 'There is nothing to fix.';
      Exit;
    End;
  If MatchCount = 0 Then
    Begin
      If Not Assigned(IDEMessagesWindow) Then
        ErrorText := 'The IDE Messages window is not available.'
      Else
        ErrorText := 'No matching compiler messages.';
      Exit;
    End;
  Result := False;
End;

Function AskForNote(Const Task: TAssistantTask; Out Note, ErrorText: String): Boolean;
Begin
  Result := True;
  Note := '';
  ErrorText := '';
  If Not AssistantTaskNeedsUserNote(Task) Then
    Exit;
  If Not ShowAssistantTaskNote(Task.Title, Note) Then
    Begin
      ErrorText := 'The note was cancelled.';
      Result := False;
      Exit;
    End;
  If Trim(Note) = '' Then
    Begin
      ErrorText := 'A note is required.';
      Result := False;
    End;
End;

Function PascalStyleName(Const FileName: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.lpr') Or (Ext = '.dpr');
End;

Procedure PostFormatNote(Const RelativePath: String; Changed: Boolean);
Var
  Note: String;
Begin
  If Changed Then
    Note := 'Format unit: `' + RelativePath + '` — changed, not saved.'
  Else
    Note := 'Format unit: `' + RelativePath + '` — unchanged, not saved.';
  If Assigned(PostAssistantTaskSystemNote) Then
    PostAssistantTaskSystemNote(Note);
End;

Function TryApplyFormat(Out ErrorText: String): Boolean;
Var
  Editor: TSourceEditorInterface;
  Expected, Formatted, Ext: String;
Begin
  Result := False;
  ErrorText := '';
  Editor := ActiveEditor;
  If Not Assigned(Editor) Then
    Begin
      ErrorText := 'There is no active editor.';
      Exit;
    End;
  If Editor.FileName = '' Then
    Begin
      ErrorText := 'The active editor has no file name.';
      Exit;
    End;
  If Not EditorInsideTarget(Editor) Then
    Begin
      ErrorText := 'The active editor is outside the selected package.';
      Exit;
    End;
  Ext := LowerCase(ExtractFileExt(Editor.FileName));
  If Ext = '.lfm' Then
    Begin
      ErrorText := 'Format unit does not format a form file.';
      Exit;
    End;
  If Ext = '.inc' Then
    Begin
      ErrorText := 'Format unit does not format an include file.';
      Exit;
    End;
  If Not PascalStyleName(Editor.FileName) Then
    Begin
      ErrorText := 'Format unit accepts .pas, .pp, .lpr, and .dpr only.';
      Exit;
    End;
  { The open buffer, not the file on disk. }
  Expected := Editor.SourceText;
  Formatted := FormatPascalSource(Expected);
  If Not TokenFingerprintsEqual(Expected, Formatted) Then
    Begin
      ErrorText := 'The formatter would change tokens. The buffer was not changed.';
      Exit;
    End;
  If Formatted = Expected Then
    Begin
      PostFormatNote(ShortPath(Editor.FileName), False);
      Result := True;
      Exit;
    End;
  If Not ApplyAssistantEditorText(Editor, Expected, Formatted, ErrorText) Then
    Exit;
  PostFormatNote(ShortPath(Editor.FileName), True);
  Result := True;
End;

Function FillReady(Const Task: TAssistantTask; Kind: TAssistantTaskRequestKind; Const Expanded, Detail: String;
  Out Request: TAssistantTaskRequest): TAssistantTaskPreparation;
Begin
  ClearAssistantTaskRequest(Request);
  Request.Kind := Kind;
  Request.Task := Task;
  Request.Mode := Task.Mode;
  Request.DisplayLabel := TaskLabel(Task.Title, Detail);
  Request.ApiText := Expanded;
  Request.FreshConversation := Task.FreshConversation;
  Request.DocumentPath := Task.DocumentPath;
  Result := tpReady;
End;

Function FinishTaskRequest(Const Task: TAssistantTask; Kind: TAssistantTaskRequestKind;
  Const Evidence: TAssistantTaskEvidence; MatchCount: Integer; Out Request: TAssistantTaskRequest;
  Out ErrorText: String): TAssistantTaskPreparation;
Var
  Expanded, Detail: String;
  Files: Integer;
Begin
  Result := tpMissing;
  If Not ExpandAssistantTaskPrompt(Task, Evidence, Expanded, ErrorText) Then
    Exit;
  Detail := '';
  Case Task.Scope Of
    tsActiveEditor: Detail := ExtractFileName(Evidence.ActiveFile);
    tsChangedFiles:
      Begin
        Files := ChangedFileCount(Evidence.GitStatus);
        Detail := ChangedDetail(Files);
      End;
    tsMessages: Detail := MessageDetail(Task.MessageFilter, MatchCount);
    tsSelection: Detail := 'selection';
  Else
    Detail := '';
  End;
  Result := FillReady(Task, Kind, Expanded, Detail, Request);
End;

Function CollectTaskEvidence(Const Task: TAssistantTask; Var Evidence: TAssistantTaskEvidence; Out MatchCount: Integer;
  Out ErrorText: String): Boolean;
Var
  ErrorCount: Integer;
Begin
  Result := False;
  MatchCount := 0;
  ErrorCount := 0;
  FillEditorEvidence(Evidence);
  If (Task.Scope = tsActiveEditor) And EditorRefusal(ErrorText) Then
    Exit;
  If Task.Scope = tsSelection Then
    Begin
      If Not Assigned(ActiveEditor) Then
        Begin
          ErrorText := 'There is no active editor.';
          Exit;
        End;
      If Trim(Evidence.Selection) = '' Then
        Begin
          ErrorText := 'The selection is empty.';
          Exit;
        End;
    End;
  If Task.Scope = tsChangedFiles Then
    Begin
      If Not CollectSavedDiff(Evidence.GitStatus, Evidence.GitDiff, ErrorText) Then
        Exit;
    End;
  If (Task.Scope = tsMessages) Or Task.CompileFirst Then
    ReadMessages(Task.MessageFilter, Evidence.Messages, ErrorCount, MatchCount)
  Else
    Begin
      ErrorCount := 0;
      MatchCount := 0;
    End;
  If Task.Scope = tsMessages Then
    Begin
      If MessagesRefusal(Task.MessageFilter, ErrorCount, MatchCount, ErrorText) Then
        Exit;
    End;
  Result := True;
End;

Function PrepareAssistantTaskRunWithNote(Const Task: TAssistantTask; Kind: TAssistantTaskRequestKind;
  Const Note: String; Out Request: TAssistantTaskRequest; Out ErrorText: String): TAssistantTaskPreparation;
Var
  Evidence: TAssistantTaskEvidence;
  MatchCount: Integer;
Begin
  Result := tpMissing;
  ClearAssistantTaskRequest(Request);
  ClearEvidence(Evidence);
  ErrorText := '';
  If Task.Hidden Then
    Begin
      ErrorText := 'This task is hidden.';
      Exit;
    End;
  If Not Task.Enabled Then
    Begin
      ErrorText := 'This task is disabled.';
      Exit;
    End;
  If HostIsBusy(ErrorText) Then
    Exit;
  If Task.Kind = tkFormat Then
    Begin
      ErrorText := 'Format tasks run on the desktop editor.';
      Exit;
    End;
  If Task.CompileFirst Then
    Begin
      ErrorText := 'Tasks that compile first run on the desktop.';
      Exit;
    End;
  If Not CollectTaskEvidence(Task, Evidence, MatchCount, ErrorText) Then
    Exit;
  If AssistantTaskNeedsUserNote(Task) And (Trim(Note) = '') Then
    Begin
      ErrorText := 'A note is required.';
      Exit;
    End;
  Evidence.UserNote := Trim(Note);
  Result := FinishTaskRequest(Task, Kind, Evidence, MatchCount, Request, ErrorText);
End;

Function PrepareAssistantTaskRun(Const Task: TAssistantTask; Kind: TAssistantTaskRequestKind;
  Out Request: TAssistantTaskRequest; Out ErrorText: String): TAssistantTaskPreparation;
Var
  Evidence: TAssistantTaskEvidence;
  CompileNote: String;
  MatchCount: Integer;
Begin
  Result := tpMissing;
  ClearAssistantTaskRequest(Request);
  ClearEvidence(Evidence);
  ErrorText := '';
  CompileNote := '';
  If Task.Hidden Then
    Begin
      ErrorText := 'This task is hidden.';
      Exit;
    End;
  If Not Task.Enabled Then
    Begin
      ErrorText := 'This task is disabled.';
      Exit;
    End;
  If (Kind = trkRun) And HostIsBusy(ErrorText) Then
    Exit;
  If Task.Kind = tkFormat Then
    Begin
      If Kind <> trkRun Then
        Begin
          ErrorText := 'Format unit does not insert a prompt.';
          Exit;
        End;
      If EditorRefusal(ErrorText) Then
        Exit;
      If TryApplyFormat(ErrorText) Then
        Begin
          ErrorText := '';
          Result := tpFormatted;
        End;
      Exit;
    End;
  If Task.CompileFirst Then
    Begin
      If Not CompileLikeReview(CompileNote) Then
        Begin
          ErrorText := CompileNote;
          Exit;
        End;
    End;
  If Not CollectTaskEvidence(Task, Evidence, MatchCount, ErrorText) Then
    Exit;
  If Not AskForNote(Task, Evidence.UserNote, ErrorText) Then
    Exit;
  Result := FinishTaskRequest(Task, Kind, Evidence, MatchCount, Request, ErrorText);
End;

Function PrepareRequestForList(Const Task: TAssistantTask; Kind: TAssistantTaskRequestKind;
  Out Request: TAssistantTaskRequest; Out ErrorText: String): Boolean;
Var
  Outcome: TAssistantTaskPreparation;
Begin
  Outcome := PrepareAssistantTaskRun(Task, Kind, Request, ErrorText);
  If Outcome = tpFormatted Then
    Begin
      ClearAssistantTaskRequest(Request);
      ErrorText := '';
      Result := True;
      Exit;
    End;
  Result := Outcome = tpReady;
End;

Initialization

PrepareAssistantTaskRequest := @PrepareRequestForList;

End.
