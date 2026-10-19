Unit AssistantFileCreation;

{ Publish complete new text files without replacing existing directory entries.
  SafeFileAccess owns the no-follow publish. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Function CreateNewProjectText(Const Root, RelativePath, Text: String; Out ErrorText: String): Boolean;

Implementation

Uses
  SafeFileAccess;

Function CreateNewProjectText(Const Root, RelativePath, Text: String; Out ErrorText: String): Boolean;
Begin
  Result := CreateNewText(Root, RelativePath, Text, ErrorText);
End;

End.
