Unit AssistantTestReport;
{ FPCUnit XML written to this job's stdout, never a pre-existing report file. }
{$mode objfpc}{$H+}
Interface
Function ParseFPCUnitReport(Const Text: String; Truncated: Boolean; MinimumTests: Integer): String;
Implementation
Uses Classes, SysUtils, DOM, XMLRead, fpjson;
Function ParseFPCUnitReport(Const Text: String; Truncated: Boolean; MinimumTests: Integer): String;
Var Doc: TXMLDocument; Stream: TStringStream; Root: TJSONObject; Runs, Errors, Failures, Ignored: Integer;
  Function Count(Const Name: String): Integer;
  Var Node: TDOMNode; Found: Boolean;
  Begin
    Found := False; Result := 0; Node := Doc.DocumentElement.FirstChild;
    While Assigned(Node) Do
      Begin
        If (Node.NodeType = ELEMENT_NODE) And (Node.NodeName = UnicodeString(Name)) Then
          Begin
            If Found Or Not TryStrToInt(Trim(UTF8Encode(Node.TextContent)), Result) Or (Result < 0) Then
              Raise Exception.Create('Invalid or duplicate report count: ' + Name);
            Found := True;
          End;
        Node := Node.NextSibling;
      End;
    If Not Found Then Raise Exception.Create('Missing report count: ' + Name);
  End;
Begin
  Root := TJSONObject.Create; Doc := Nil; Stream := Nil;
  Try
    Root.Add('format', 'fpcunit-xml'); Root.Add('minimumTests', MinimumTests);
    Try
      If Truncated Or (Length(Text) > 1048576) Then Raise Exception.Create('Test output is truncated; report cannot be verified.');
      If Pos(#0, Text) > 0 Then Raise Exception.Create('Report must use UTF-8 text.');
      If (Pos('<!DOCTYPE', UpperCase(Text)) > 0) Or (Pos('<!ENTITY', UpperCase(Text)) > 0) Then
        Raise Exception.Create('Report document types and entities are unsupported.');
      Stream := TStringStream.Create(Text); ReadXMLFile(Doc, Stream);
      If Not Assigned(Doc.DocumentElement) Or (Doc.DocumentElement.NodeName <> 'TestResults') Then
        Raise Exception.Create('Expected an FPCUnit TestResults document on stdout.');
      Runs := Count('NumberOfRunTests'); Errors := Count('NumberOfErrors');
      Failures := Count('NumberOfFailures'); Ignored := Count('NumberOfIgnoredTests');
      If (MinimumTests < 1) Or (Int64(Errors) + Failures + Ignored > Runs) Then
        Raise Exception.Create('Inconsistent test counts.');
      Root.Add('valid', True); Root.Add('run', Runs); Root.Add('errors', Errors);
      Root.Add('failures', Failures); Root.Add('ignored', Ignored); Root.Add('executed', Runs - Ignored);
      Root.Add('passed', (Errors = 0) And (Failures = 0) And (Runs - Ignored >= MinimumTests));
      Root.Add('error', '');
    Except On E: Exception Do Begin Root.Add('valid', False); Root.Add('passed', False); Root.Add('error', Copy(E.Message, 1, 2000)); End; End;
    Result := Root.AsJSON;
  Finally Root.Free; Doc.Free; Stream.Free; End;
End;
End.
