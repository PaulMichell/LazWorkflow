Unit AssistantRecap;

{ One bounded recap for a backend that does not keep a message array (c) 2026 Michell Computing.

  The 24000 / 4000 / 8000 limits live in this unit. A caller that copies the loop will drift.
  Image re-attachment is the recap-only rule: an ephemeral thread has no message array, so a stored
  ref is sent again when its upload file still exists. A missing file is skipped, not described.
  A runtime session does not use that rule. Message history does not use this unit at all. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  AssistantConversation, AssistantImages;

Const
  { Stop adding turns once the recap reaches this length. }
  AssistantRecapMaxChars = 24000;
  { Each included user prompt. }
  AssistantRecapUserChars = 4000;
  { Each included assistant answer. }
  AssistantRecapAnswerChars = 8000;

/// Newest matching turns first, until AssistantRecapMaxChars. Empty when the store has none.
Function AssistantBoundedRecap(Store: TAssistantConversationStore; Const ModelName: String): String;
/// SubmitText unchanged when Recap is empty. The heading is transport history, not an instruction.
Function AssistantRecapPrompt(Const Recap, SubmitText: String): String;
/// One walk. Recap is the bounded text. Refs starts as Current. When Reattach is true, refs from the
/// same turns are added while the upload file still exists, up to MaxCount. A duplicate id is skipped.
/// A missing file is skipped. MaxCount below 1 uses AssistantImageMaxAttachments.
Procedure AssistantBuildRecap(Store: TAssistantConversationStore; Const ProjectRoot, ModelName: String;
  Const Current: TAssistantImageRefArray; Reattach: Boolean; MaxCount: Integer;
  Out Recap: String; Out Refs: TAssistantImageRefArray);

Implementation

Uses
  SysUtils;

Function RecapTurnText(Const Turn: TConversationTurn): String;
Begin
  Result := 'User: ' + Copy(Turn.Prompt, 1, AssistantRecapUserChars) + LineEnding +
    'Assistant: ' + Copy(Turn.Response, 1, AssistantRecapAnswerChars) + LineEnding;
End;

Function RefAlreadyIncluded(Const Refs: TAssistantImageRefArray; Count: Integer; Const ImageId: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 0 To Count - 1 Do
    If Refs[I].Id = ImageId Then
      Exit(True);
End;

Procedure AssistantBuildRecap(Store: TAssistantConversationStore; Const ProjectRoot, ModelName: String;
  Const Current: TAssistantImageRefArray; Reattach: Boolean; MaxCount: Integer;
  Out Recap: String; Out Refs: TAssistantImageRefArray);
Var
  I, J, N: Integer;
  Turn: TConversationTurn;
  Prior: TAssistantImageRefArray;
  Path, ErrorText: String;
Begin
  Recap := '';
  Refs := Nil;
  If MaxCount < 1 Then
    MaxCount := AssistantImageMaxAttachments;
  N := Length(Current);
  If N > MaxCount Then
    N := MaxCount;
  SetLength(Refs, N);
  For I := 0 To N - 1 Do
    Refs[I] := Current[I];
  If Not Assigned(Store) Then
    Exit;
  For I := Store.TurnCount - 1 DownTo 0 Do
    Begin
      If Length(Recap) >= AssistantRecapMaxChars Then
        Break;
      If (Not Store.GetTurn(I, Turn)) Or (Turn.Model <> ModelName) Then
        Continue;
      Recap := RecapTurnText(Turn) + Recap;
      If (Not Reattach) Or (N >= MaxCount) Then
        Continue;
      ParseAssistantImageRefs(Turn.AttachmentsJson, Prior);
      For J := 0 To High(Prior) Do
        Begin
          If N >= MaxCount Then
            Break;
          If RefAlreadyIncluded(Refs, N, Prior[J].Id) Then
            Continue;
          If Not AssistantImageUploadFile(ProjectRoot, Prior[J], Path, ErrorText) Then
            Continue;
          SetLength(Refs, N + 1);
          Refs[N] := Prior[J];
          Inc(N);
        End;
    End;
End;

Function AssistantBoundedRecap(Store: TAssistantConversationStore; Const ModelName: String): String;
Var
  Refs: TAssistantImageRefArray;
Begin
  Refs := Nil;
  AssistantBuildRecap(Store, '', ModelName, Refs, False, 0, Result, Refs);
End;

Function AssistantRecapPrompt(Const Recap, SubmitText: String): String;
Begin
  Result := SubmitText;
  If Recap <> '' Then
    Result := 'Previous conversation (bounded recap):' + LineEnding + Recap + LineEnding + LineEnding + SubmitText;
End;

End.
