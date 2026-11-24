Program AssistantNativeEditsTest;

{ Headless native edit gate. No IDE form. The broker test stays AssistantEditorEditsTest. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  SysUtils, Classes, AssistantExactReplace;

Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Function ReadBytes(Const Path: String): String;
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
  Try
    SetLength(Result, Stream.Size);
    If Result <> '' Then
      Stream.ReadBuffer(Result[1], Length(Result));
  Finally
    Stream.Free;
  End;
End;

Procedure WriteBytes(Const Path, Body: String);
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmCreate);
  Try
    If Body <> '' Then
      Stream.WriteBuffer(Body[1], Length(Body));
  Finally
    Stream.Free;
  End;
End;

Procedure TestRevisionGate;
Var
  Path, Original, Changed, Revision, Err, Updated: String;
Begin
  Path := 'unit.pas';
  Original := 'Line one.' + LineEnding + 'Line two.' + LineEnding;
  Changed := 'Line one.' + LineEnding + 'Line changed.' + LineEnding;
  Revision := RememberNativeRead(Path, Original);
  Check('read records a revision', Revision <> '');
  Check('missing revision does not overwrite an open editor',
    Not AcceptNativeWrite(Path, '', Original, True, True, Err) And (Err = EditorOwnsPathMessage));
  Check('missing revision does not overwrite a disk file',
    Not AcceptNativeWrite(Path, '', Original, True, False, Err) And (Err = DestinationExistsMessage));
  Check('empty revision may create a new file',
    AcceptNativeWrite(Path, '', '', False, False, Err) And (Err = ''));
  Check('a supplied revision must match the text last read',
    AcceptNativeWrite(Path, Revision, Original, True, False, Err));
  Check('a wrong revision is the broker stale sentence',
    Not AcceptNativeWrite(Path, 'native:missing', Original, True, False, Err) And (Err = StaleBufferRevisionMessage));
  Check('text changed since the read is stale',
    Not AcceptNativeWrite(Path, Revision, Changed, True, True, Err) And (Err = StaleBufferRevisionMessage));
  Check('replace without a revision is stale and changes nothing',
    Not PrepareNativeReplace(Path, '', Original, 'Line', 'Row', False, Updated, Err) And (Updated = '') And
    (Err = StaleBufferRevisionMessage) And (Original = 'Line one.' + LineEnding + 'Line two.' + LineEnding));
  Check('replace with the read revision is accepted',
    PrepareNativeReplace(Path, Revision, Original, 'Line two.', 'Line changed.', False, Updated, Err) And
    (Updated = Changed));
  Check('a second read retires the previous revision',
    (RememberNativeRead(Path, Original) <> Revision) And
    Not NativeRevisionCurrent(Path, Revision, Original, Err) And (Err = StaleBufferRevisionMessage));
End;

Procedure TestUniqueMatchLeavesDisk;
Var
  Dir, Path, Body, Updated, Err, Revision, Seen: String;
Begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-native-edits';
  ForceDirectories(Dir);
  Path := IncludeTrailingPathDelimiter(Dir) + 'repeat.txt';
  Body := 'same token same token';
  WriteBytes(Path, Body);
  Try
    Revision := RememberNativeRead(Path, Body);
    Updated := 'must not be written';
    Check('repeated old_text is the broker sentence',
      Not PrepareNativeReplace(Path, Revision, Body, 'same', 'other', False, Updated, Err) And
      (Err = 'old_text occurs more than once; set replace_all to replace every match.') And (Updated = ''));
    { The native tool writes only after PrepareNativeReplace succeeds. This is that caller. }
    If PrepareNativeReplace(Path, Revision, Body, 'same', 'other', False, Updated, Err) Then
      WriteBytes(Path, Updated);
    Seen := ReadBytes(Path);
    Check('repeated old_text changes nothing on disk', Seen = Body);
    Check('replace_all still replaces every match',
      PrepareNativeReplace(Path, Revision, Body, 'same', 'other', True, Updated, Err) And
      (Updated = 'other token other token'));
    Check('a unique match replaces once',
      PrepareNativeReplace(Path, Revision, Body, 'same token same token', 'done', False, Updated, Err) And
      (Updated = 'done'));
  Finally
    DeleteFile(Path);
    RemoveDir(Dir);
  End;
End;

Procedure TestRegistrationFailureKeepsFile;
Var
  Dir, Path, Body, Err: String;
Begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-native-edits-reg';
  ForceDirectories(Dir);
  Path := IncludeTrailingPathDelimiter(Dir) + 'KeptUnit.pas';
  Body := 'Unit KeptUnit;' + LineEnding + 'Begin End;' + LineEnding;
  WriteBytes(Path, Body);
  Try
    Check('registration failure is not success',
      Not FailWriteFileProjectRegistration(Path, 'CreateProjectFile returned nil.', Err));
    Check('error says the file was written', Pos('The file was written', Err) = 1);
    Check('error says the project was not updated', Pos('the project was not updated', Err) > 0);
    Check('written unit is not deleted', FileExists(Path) And (ReadBytes(Path) = Body));
  Finally
    DeleteFile(Path);
    RemoveDir(Dir);
  End;
End;

Begin
  ResetNativeReads;
  TestRevisionGate;
  TestUniqueMatchLeavesDisk;
  TestRegistrationFailureKeepsFile;
  WriteLn('AssistantNativeEditsTest passed');
End.
