Unit AssistantBuildDiagnostics;
{ Parse only explicit FPC location/severity lines; retain the raw log separately. }
{$mode objfpc}{$H+}
Interface
Uses fpjson;
Function ParseBuildDiagnostics(Const Log, JobId: String; Out Truncated: Boolean): TJSONArray;
Implementation
Uses Classes, SysUtils;
Function ParseBuildDiagnostics(Const Log, JobId: String; Out Truncated: Boolean): TJSONArray;
Var Lines: TStringList; I, P, Q, Comma, Row, Col, J, Bytes: Integer;
  S, Position, Severity, MessageText, Path: String; Entry: TJSONObject;
Begin
  Result := TJSONArray.Create; Lines := TStringList.Create; Truncated := False; Bytes := 0;
  Try
    Lines.Text := Log;
    For I := 0 To Lines.Count - 1 Do
      Begin
        S := Lines[I]; Q := Pos(') ', S);
        If Q = 0 Then Continue;
        P := Q - 1; While (P > 0) And (S[P] <> '(') Do Dec(P);
        If P <= 1 Then Continue;
        Position := Copy(S, P + 1, Q - P - 1); Comma := Pos(',', Position); Col := 0;
        If Comma > 0 Then
          Begin
            If Not TryStrToInt(Copy(Position, Comma + 1, MaxInt), Col) Or (Col < 1) Then Continue;
            Position := Copy(Position, 1, Comma - 1);
          End;
        If Not TryStrToInt(Position, Row) Or (Row < 1) Then Continue;
        MessageText := TrimLeft(Copy(S, Q + 2, MaxInt)); J := Pos(':', MessageText);
        If J = 0 Then Continue;
        Severity := LowerCase(Copy(MessageText, 1, J - 1));
        If (Severity <> 'fatal') And (Severity <> 'error') And (Severity <> 'warning') And
          (Severity <> 'hint') And (Severity <> 'note') Then Continue;
        If Result.Count >= 200 Then Begin Truncated := True; Break; End;
        Path := Copy(S, 1, P - 1);
        Entry := TJSONObject.Create; Entry.Add('job_id', JobId); Entry.Add('path', Path);
        Entry.Add('line', Row); Entry.Add('column', Col);
        Entry.Add('severity', Severity); Entry.Add('message', TrimLeft(Copy(MessageText, J + 1, MaxInt)));
        Entry.Add('raw', S); Inc(Bytes, Length(Entry.AsJSON));
        If Bytes > 65536 Then Begin Entry.Free; Truncated := True; Break; End;
        Result.Add(Entry);
      End;
  Finally Lines.Free; End;
End;
End.
