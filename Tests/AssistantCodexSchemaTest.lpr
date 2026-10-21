Program AssistantCodexSchemaTest;
{$mode objfpc}{$H+}

Uses
cthreads, SysUtils, fpjson, jsonparser, AssistantCodexSchema, AssistantCodexProfile,
AssistantCodexQualification, AssistantCodexDiagnostics;
Procedure Check(Const Name: String; Passed: Boolean);
Begin
  If Not Passed Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Procedure Contract(Const Name, SchemaText, ValueText: String; Outgoing, Expected: Boolean);

Var
Schema, Value: TJSONData;
Reason: String;
Begin
  Schema := GetJSON(SchemaText);
  Value := GetJSON(ValueText);
  Try
    Check(Name, CodexSchemaAccepts(Schema, Schema, Value, Outgoing, Reason) = Expected);
  Finally
    Value.Free;
    Schema.Free;
  End;
End;

Var
Evidence: TCodexCompatibility;
Capability: TCodexCapability;
Begin
  Contract('enum rejects invalid scope', '{"type":"string","enum":["turn","session"]}', '"none"', True, False);
  Contract('enum accepts valid scope', '{"type":"string","enum":["turn","session"]}', '"turn"', True, True);
  Contract('required outgoing field', '{"type":"object","properties":{"x":{"type":"string"}},"required":["x"]}', '{}', True, False);
  Contract('incoming additive requirement', '{"type":"object","properties":{"x":{"type":"string"}},"required":["x"]}', '{}', False, True);
  Contract('typed incoming field', '{"type":"object","properties":{"x":{"type":"string"}}}', '{"x":1}', False, False);
  Contract('undeclared incoming field', '{"type":"object","properties":{}}', '{"x":1}', False, False);
  Contract('empty message schema', '{}', '{}', True, False);
  Contract('unknown constraint', '{"type":"string","futureConstraint":true}', '"x"', True, False);
  Contract('negation cannot hide unknown constraints', '{"not":{"futureConstraint":true}}', '"x"', True, False);
  Contract('local reference', '{"$ref":"#/definitions/x","definitions":{"x":{"type":"string"}}}', '"x"', True, True);
  Contract('remote reference rejected', '{"$ref":"https://example.invalid/schema"}', '"x"', True, False);
  Contract('recursive reference bounded', '{"$ref":"#"}', '"x"', True, False);
  Contract('union branch', '{"oneOf":[{"type":"string"},{"type":"number"}]}', 'true', True, False);
  Check('numeric extension versions', CompareCodexExtensionVersions('openai.chatgpt-26.1007.21434-linux-x64', 'openai.chatgpt-26.930.51102-linux-x64') > 0);
  Check('missing custom executable preserved', ResolveCodexExecutable('/tmp/nonexistent-custom-codex') = '/tmp/nonexistent-custom-codex');
  Check('diagnostics do not expose server secrets', Pos('secret-token', CodexRequestError('account/read', -32603, 'secret-token workspace routing discovery failed')) = 0);
  Evidence := Default(TCodexCompatibility);
  InspectCodexSchema('Tests/Fixtures/CodexSchema', Evidence);
  For Capability := Low(TCodexCapability) To High(TCodexCapability) Do
    Check('installed contract ' + CodexCapabilityNames[Capability] + ': ' + Evidence.Reason[Capability], Evidence.Support[Capability] = csSupported);
  Check('tagged tool adapter selected', Evidence.Adapter = 'named-permissions-tagged-v1');
  WriteLn('All Codex schema tests passed.');
End.
