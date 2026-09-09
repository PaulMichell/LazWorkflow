Program AssistantFileCreationTest;
{$mode objfpc}{$H+}
Uses SysUtils, Classes, BaseUnix, AssistantFileCreation;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok   ', Name); End;
Function ReadText(Const Path: String): String;
Var Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmOpenRead);
  Try SetLength(Result, Stream.Size); If Result <> '' Then Stream.ReadBuffer(Result[1], Length(Result)); Finally Stream.Free; End;
End;
Var Root, Outside, Err, Body: String; Id: TGuid; Search: TSearchRec;
Begin
  CreateGUID(Id); Root := GetTempDir + 'laz-create-' + GUIDToString(Id); Outside := Root + '-outside';
  ForceDirectories(Root); ForceDirectories(Outside);
  Body := '# Review' + LineEnding + '**UTF-8:** café' + LineEnding;
  Try
    Check('nested report creates complete exact text', CreateNewProjectText(Root, 'Documents/Review.md', Body, Err)
      And (ReadText(Root + '/Documents/Review.md') = Body));
    Check('existing report never overwritten', Not CreateNewProjectText(Root, 'Documents/Review.md', 'replacement', Err)
      And (ReadText(Root + '/Documents/Review.md') = Body));
    Check('temporary files removed after success and collision', FindFirst(Root + '/Documents/.laz-assistant-*', faAnyFile, Search) <> 0);
    FindClose(Search);
    Check('empty file supported', CreateNewProjectText(Root, 'empty.txt', '', Err) And (ReadText(Root + '/empty.txt') = ''));
    Check('traversal rejected', Not CreateNewProjectText(Root, '../outside.txt', Body, Err));
    Check('absolute path rejected', Not CreateNewProjectText(Root, Outside + '/bad.txt', Body, Err));
    Check('NUL path rejected', Not CreateNewProjectText(Root, 'bad' + #0 + '.txt', Body, Err));
    Check('binary content rejected', Not CreateNewProjectText(Root, 'binary.txt', #0, Err));
    Check('oversized content rejected', Not CreateNewProjectText(Root, 'large.txt', StringOfChar('x', 1048577), Err));
    fpSymlink(PChar(Outside), PChar(Root + '/escape'));
    Check('symlink parent not followed', Not CreateNewProjectText(Root, 'escape/bad.txt', Body, Err) And Not FileExists(Outside + '/bad.txt'));
    fpSymlink(PChar(Outside + '/missing.txt'), PChar(Root + '/dangling'));
    Check('dangling destination symlink never overwritten', Not CreateNewProjectText(Root, 'dangling', Body, Err) And Not FileExists(Outside + '/missing.txt'));
    Check('file cannot become a directory', Not CreateNewProjectText(Root, 'empty.txt/child.txt', Body, Err));
    Check('quoted names preserved', CreateNewProjectText(Root, 'Documents/"Review".md', Body, Err) And FileExists(Root + '/Documents/"Review".md'));
  Finally
    DeleteFile(Root + '/Documents/"Review".md'); DeleteFile(Root + '/Documents/Review.md'); RemoveDir(Root + '/Documents');
    DeleteFile(Root + '/empty.txt'); DeleteFile(Root + '/escape'); DeleteFile(Root + '/dangling');
    RemoveDir(Root); RemoveDir(Outside);
  End;
End.
