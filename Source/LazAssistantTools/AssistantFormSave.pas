Unit AssistantFormSave;

{$mode objfpc}{$H+}

Interface

Uses Classes, SysUtils, Types, SrcEditorIntf;

Type
  TFormEditors = Array Of TSourceEditorInterface;
  TFormSaveFile = Function(Const Path, Content: String; OpenAfter: Boolean;
    Out Note, ErrorText: String): Boolean;

Function SaveFormPair(Const PasPath, LfmPath, PasBody, LfmBody: String;
  ChangedPas, ChangedLfm: Boolean; Const PasEditors, LfmEditors: TFormEditors;
  Save: TFormSaveFile; Out ErrorText: String): Boolean;

Implementation

Uses SynEdit, AssistantEditorEdits;

Type
  TEditorState = Record
    Editor: TSourceEditorInterface;
    Body: String;
    Modified: Boolean;
    Caret, BlockStart, BlockEnd: TPoint;
    TopLine, LeftChar: Integer;
  End;
  TFileState = Record
    Path, Bytes: String;
    Editors: Array Of TEditorState;
  End;

Function DiskBytes(Const Path: String): String;
Var Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
  Try
    SetLength(Result, Stream.Size);
    If Result <> '' Then Stream.ReadBuffer(Result[1], Length(Result));
  Finally
    Stream.Free;
  End;
End;

Procedure Capture(Const Path: String; Const Editors: TFormEditors; Out State: TFileState);
Var I: Integer; Syn: TCustomSynEdit;
Begin
  State.Path := Path;
  State.Bytes := DiskBytes(Path);
  SetLength(State.Editors, Length(Editors));
  For I := 0 To High(Editors) Do
    With State.Editors[I] Do
      Begin
        Editor := Editors[I];
        Body := Editor.SourceText;
        Modified := Editor.Modified;
        If Editor.EditorControl Is TCustomSynEdit Then
          Begin
            Syn := TCustomSynEdit(Editor.EditorControl);
            Caret := Syn.LogicalCaretXY;
            BlockStart := Syn.BlockBegin;
            BlockEnd := Syn.BlockEnd;
            TopLine := Syn.TopLine;
            LeftChar := Syn.LeftChar;
          End;
      End;
End;

Procedure Restore(Const State: TFileState; Var ErrorText: String);
Var I: Integer; Stream: TFileStream; Problem: String; Syn: TCustomSynEdit;
Begin
  Try
    If (Not FileExists(State.Path)) Or (DiskBytes(State.Path) <> State.Bytes) Then
      Begin
        Stream := TFileStream.Create(State.Path, fmCreate);
        Try
          If State.Bytes <> '' Then Stream.WriteBuffer(State.Bytes[1], Length(State.Bytes));
        Finally
          Stream.Free;
        End;
      End;
  Except
    On E: Exception Do ErrorText := ErrorText + LineEnding + 'Disk restoration failed for ' + State.Path + ': ' + E.Message;
  End;
  For I := 0 To High(State.Editors) Do
    With State.Editors[I] Do
      Try
        If (Editor.SourceText <> Body) And
          Not ApplyAssistantEditorText(Editor, Editor.SourceText, Body, Problem) Then
          Raise Exception.Create(Problem);
        Editor.Modified := Modified;
        If Editor.EditorControl Is TCustomSynEdit Then
          Begin
            Syn := TCustomSynEdit(Editor.EditorControl);
            Syn.LogicalCaretXY := Caret;
            Syn.BlockBegin := BlockStart;
            Syn.BlockEnd := BlockEnd;
            Syn.TopLine := TopLine;
            Syn.LeftChar := LeftChar;
          End;
      Except
        On E: Exception Do ErrorText := ErrorText + LineEnding + 'Editor restoration failed for ' + State.Path + ': ' + E.Message;
      End;
End;

Function SaveFormPair(Const PasPath, LfmPath, PasBody, LfmBody: String;
  ChangedPas, ChangedLfm: Boolean; Const PasEditors, LfmEditors: TFormEditors;
  Save: TFormSaveFile; Out ErrorText: String): Boolean;
Var PasState, LfmState: TFileState; AttemptedPas, AttemptedLfm: Boolean; Note, RestoreErrors: String;
Begin
  Result := False;
  AttemptedPas := False;
  AttemptedLfm := False;
  Try
    Try
      If ChangedPas Then Capture(PasPath, PasEditors, PasState);
      If ChangedLfm Then Capture(LfmPath, LfmEditors, LfmState);
      If ChangedPas Then
        Begin
          AttemptedPas := True;
          If Not Save(PasPath, PasBody, False, Note, ErrorText) Then Exit;
        End;
      If ChangedLfm Then
        Begin
          AttemptedLfm := True;
          If Not Save(LfmPath, LfmBody, False, Note, ErrorText) Then Exit;
        End;
      Result := True;
    Except
      On E: Exception Do ErrorText := E.Message;
    End;
  Finally
    If Not Result Then
      Begin
        RestoreErrors := '';
        If AttemptedLfm Then Restore(LfmState, RestoreErrors);
        If AttemptedPas Then Restore(PasState, RestoreErrors);
        If RestoreErrors <> '' Then ErrorText := ErrorText + RestoreErrors
        Else If AttemptedPas Or AttemptedLfm Then
          ErrorText := ErrorText + LineEnding + 'Rollback restored the original files and buffers.';
      End;
  End;
End;

End.
