Unit AssistantPlanDocument;

{ Reads the active plan file for the phone cache (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  { Same ceiling as the monitor item cap, so a connected phone can keep the whole file. }
  AssistantPlanDocumentMaxBytes = 4 * 1024 * 1024;

/// Whole plan Markdown for the phone cache. An empty path does not fall back to the default plan.
Function ReadAssistantPlanDocument(Const RelativeOrAbsolute: String; Out Truncated: Boolean): String;
{ Hash and length of that document. Empty when the path is empty or the file is missing. }
Function AssistantPlanDocumentRevision(Const RelativeOrAbsolute: String): String;
{ Age and size for the desktop save timer. False when the file is missing. }
Function AssistantPlanFileStamp(Const RelativeOrAbsolute: String; Out Age: LongInt; Out Bytes: Int64): Boolean;

Implementation

Uses
  Classes, LazFileUtils, AssistantPlan;

Function TrimPartialUtf8(Const Text: String): String;
Var
  Last: Integer;
Begin
  Result := Text;
  While Result <> '' Do
    Begin
      Last := Ord(Result[Length(Result)]);
      If (Last And $C0) = $80 Then
        Delete(Result, Length(Result), 1)
      Else
        Break;
    End;
  If (Result <> '') And ((Ord(Result[Length(Result)]) And $C0) = $C0) Then
    Delete(Result, Length(Result), 1);
End;

Function ReadCappedUtf8File(Const FileName: String; MaxBytes: Integer; Out Truncated: Boolean): String;
Var
  Stream: TFileStream;
  Count, Size: Integer;
Begin
  Result := '';
  Truncated := False;
  If MaxBytes < 1 Then
    Exit;
  Try
    Stream := TFileStream.Create(FileName, fmOpenRead Or fmShareDenyNone);
  Except
    Exit;
  End;
  Try
    Size := Stream.Size;
    If Size < 1 Then
      Exit;
    Truncated := Size > MaxBytes;
    Count := Size;
    If Count > MaxBytes Then
      Count := MaxBytes;
    SetLength(Result, Count);
    Count := Stream.Read(Result[1], Count);
    If Count < 0 Then
      Count := 0;
    SetLength(Result, Count);
    If (Length(Result) >= 3) And (Result[1] = #$EF) And (Result[2] = #$BB) And (Result[3] = #$BF) Then
      Delete(Result, 1, 3);
    If Truncated Then
      Result := TrimPartialUtf8(Result);
  Finally
    Stream.Free;
  End;
End;

Function PlanFileRevision(Const Text: String): String;
Var
  Hash: UInt64;
  Index: Integer;
Begin
  {$PUSH}{$Q-}{$R-}
  Hash := UInt64(14695981039346656037);
  For Index := 1 To Length(Text) Do
    Begin
      Hash := Hash Xor Ord(Text[Index]);
      Hash := Hash * UInt64(1099511628211);
    End;
  {$POP}
  Result := LowerCase(IntToHex(Hash, 16));
End;

Function PlanTextFingerprint(Const Text: String): String;
Var
  Index: Integer;
  Hash: Cardinal;
Begin
  Hash := 2166136261;
  For Index := 1 To Length(Text) Do
    Hash := Cardinal((QWord(Hash) Xor Byte(Text[Index])) * 16777619);
  Result := IntToHex(Hash, 8) + ':' + IntToStr(Length(Text));
End;

Function ReadAssistantPlanDocument(Const RelativeOrAbsolute: String; Out Truncated: Boolean): String;
Var
  Resolved, ErrorText: String;
Begin
  Result := '';
  Truncated := False;
  If Trim(RelativeOrAbsolute) = '' Then
    Exit;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  Result := ReadCappedUtf8File(Resolved, AssistantPlanDocumentMaxBytes, Truncated);
End;

Function AssistantPlanDocumentRevision(Const RelativeOrAbsolute: String): String;
Var
  Resolved, ErrorText, Body: String;
  Truncated: Boolean;
Begin
  Result := '';
  If Trim(RelativeOrAbsolute) = '' Then
    Exit;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Exit;
  Body := ReadCappedUtf8File(Resolved, AssistantPlanDocumentMaxBytes, Truncated);
  Result := PlanFileRevision(Body);
End;

Function AssistantPlanFileStamp(Const RelativeOrAbsolute: String; Out Age: LongInt; Out Bytes: Int64): Boolean;
Var
  Resolved, ErrorText: String;
  Stream: TFileStream;
Begin
  Result := False;
  Age := -1;
  Bytes := -1;
  If Trim(RelativeOrAbsolute) = '' Then
    Exit;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Exit;
  Age := FileAge(Resolved);
  Try
    Stream := TFileStream.Create(Resolved, fmOpenRead Or fmShareDenyNone);
  Except
    Exit;
  End;
  Try
    Bytes := Stream.Size;
    Result := True;
  Finally
    Stream.Free;
  End;
End;

End.
