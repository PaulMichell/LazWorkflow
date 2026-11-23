Unit AssistantToolWire;

{ Renders one tool table as OpenAI functions, Responses tools, Codex dynamicTools,
  or MCP inputSchema. Callers do not hand-build those shapes. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantToolSpecs;

Type
  TAssistantToolWireKind = (twkOpenAI, twkResponses, twkCodex, twkMCP);

/// One tool. SchemaJson is the parameters object, embedded as-is. ForBroker selects the broker description.
Function RenderAssistantTool(Const Spec: TAssistantToolSpec; Kind: TAssistantToolWireKind; ForBroker: Boolean;
  Const Notes: TAssistantToolRenderNotes): String;
/// Names in order. Missing names are skipped. Empty is [].
Function RenderAssistantToolNames(Names: TStrings; Kind: TAssistantToolWireKind; ForBroker: Boolean;
  Const Notes: TAssistantToolRenderNotes): String;
/// OpenAI function array to Codex dynamicTools. A thin shape change for a caller that already holds that JSON.
Function OpenAIToolsToCodex(Const CatalogueJson: String): String;
/// OpenAI function array to Responses tools. Items that are already flat are kept.
Function OpenAIToolsToResponses(Const CatalogueJson: String): String;

Implementation

Uses
  fpjson, jsonparser, AssistantProtocol;

Function ApplyNotes(Const Text: String; Const Notes: TAssistantToolRenderNotes): String;
Begin
  Result := Text;
  Result := StringReplace(Result, '{SaveNote}', Notes.SaveNote, [rfReplaceAll]);
  Result := StringReplace(Result, '{WriteNote}', Notes.WriteNote, [rfReplaceAll]);
  Result := StringReplace(Result, '{ReadSource}', Notes.ReadSource, [rfReplaceAll]);
  Result := StringReplace(Result, '{SaveTool}', Notes.SaveTool, [rfReplaceAll]);
  Result := StringReplace(Result, '{CommandMax}', IntToStr(Notes.CommandMaxSeconds), [rfReplaceAll]);
End;

Function ToolDescription(Const Spec: TAssistantToolSpec; ForBroker: Boolean; Const Notes: TAssistantToolRenderNotes): String;
Begin
  If ForBroker And (Spec.BrokerDescription <> '') Then
    Result := Spec.BrokerDescription
  Else
    Result := Spec.Description;
  If ForBroker And (Spec.BrokerNote <> '') Then
    Result := Result + Spec.BrokerNote;
  Result := ApplyNotes(Result, Notes);
End;

Function QuoteJson(Const Text: String): String;
Begin
  Result := '"' + JsonEscapeText(Text) + '"';
End;

Function RenderAssistantTool(Const Spec: TAssistantToolSpec; Kind: TAssistantToolWireKind; ForBroker: Boolean;
  Const Notes: TAssistantToolRenderNotes): String;
Var
  Name, Description, Schema: String;
Begin
  Name := QuoteJson(Spec.Name);
  Description := QuoteJson(ToolDescription(Spec, ForBroker, Notes));
  Schema := Spec.Schema;
  If Trim(Schema) = '' Then
    Schema := '{"type":"object","properties":{}}';
  Case Kind Of
    twkOpenAI:
      Result := '{"type":"function","function":{"name":' + Name + ',"description":' + Description +
        ',"parameters":' + Schema + '}}';
    twkResponses:
      Result := '{"type":"function","name":' + Name + ',"description":' + Description + ',"parameters":' + Schema + '}';
    twkCodex:
      Result := '{"type":"function","name":' + Name + ',"description":' + Description + ',"inputSchema":' + Schema + '}';
    twkMCP:
      Result := '{"name":' + Name + ',"description":' + Description + ',"inputSchema":' + Schema + '}';
  End;
End;

Function RenderAssistantToolNames(Names: TStrings; Kind: TAssistantToolWireKind; ForBroker: Boolean;
  Const Notes: TAssistantToolRenderNotes): String;
Var
  I: Integer;
  Spec: TAssistantToolSpec;
  Item: String;
Begin
  Result := '';
  If Not Assigned(Names) Then
    Begin
      Result := '[]';
      Exit;
    End;
  For I := 0 To Names.Count - 1 Do
    Begin
      If Not FindAssistantToolSpec(Names[I], Spec) Then
        Continue;
      Item := RenderAssistantTool(Spec, Kind, ForBroker, Notes);
      If Item = '' Then
        Continue;
      If Result <> '' Then
        Result := Result + ',';
      Result := Result + Item;
    End;
  Result := '[' + Result + ']';
End;

Function CopyJson(Node: TJSONData): TJSONData;
Begin
  Result := Nil;
  If Not Assigned(Node) Then
    Exit;
  Try
    Result := GetJSON(Node.AsJSON);
  Except
    Result := Nil;
  End;
End;

Function OpenAIToolsToCodex(Const CatalogueJson: String): String;
Var
  Data, Fn, Schema: TJSONData;
  Source, Converted: TJSONArray;
  Item, FnObj, Tool: TJSONObject;
  I: Integer;
Begin
  Result := '[]';
  If Trim(CatalogueJson) = '' Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(CatalogueJson);
    Except
      Exit;
    End;
    If Not (Data Is TJSONArray) Then
      Exit;
    Source := TJSONArray(Data);
    Converted := TJSONArray.Create;
    Try
      For I := 0 To Source.Count - 1 Do
        Begin
          If Not (Source[I] Is TJSONObject) Then
            Continue;
          Item := TJSONObject(Source[I]);
          Fn := Item.Find('function');
          If Assigned(Fn) And (Fn Is TJSONObject) Then
            Begin
              FnObj := TJSONObject(Fn);
              Tool := TJSONObject.Create;
              Tool.Add('type', 'function');
              Tool.Add('name', FnObj.Get('name', ''));
              Tool.Add('description', FnObj.Get('description', ''));
              Schema := CopyJson(FnObj.Find('parameters'));
              If Not Assigned(Schema) Then
                Schema := GetJSON('{"type":"object","properties":{}}');
              Tool.Add('inputSchema', Schema);
              Converted.Add(Tool);
            End
          Else If Item.Get('name', '') <> '' Then
            Begin
              Schema := CopyJson(Item);
              If Assigned(Schema) Then
                Converted.Add(Schema);
            End;
        End;
      Result := Converted.AsJSON;
    Finally
      Converted.Free;
    End;
  Finally
    Data.Free;
  End;
End;

Function OpenAIToolsToResponses(Const CatalogueJson: String): String;
Var
  Data: TJSONData;
  Arr, OutArr: TJSONArray;
  Item, Func, Flat: TJSONObject;
  I: Integer;
  Name: String;
Begin
  Result := CatalogueJson;
  If Trim(CatalogueJson) = '' Then
    Exit;
  Data := Nil;
  OutArr := Nil;
  Try
    Try
      Data := GetJSON(CatalogueJson);
      If Not (Data Is TJSONArray) Then
        Exit;
      Arr := TJSONArray(Data);
      OutArr := TJSONArray.Create;
      For I := 0 To Arr.Count - 1 Do
        Begin
          If Not (Arr.Items[I] Is TJSONObject) Then
            Continue;
          Item := TJSONObject(Arr.Items[I]);
          Func := Item.FindPath('function') As TJSONObject;
          If Assigned(Func) Then
            Begin
              Flat := TJSONObject.Create;
              Flat.Add('type', 'function');
              Name := Func.Get('name', '');
              If Name <> '' Then
                Flat.Add('name', Name);
              If Func.Find('description') <> Nil Then
                Flat.Add('description', Func.Get('description', ''));
              If Assigned(Func.Find('parameters')) Then
                Flat.Add('parameters', Func.Find('parameters').Clone);
              OutArr.Add(Flat);
            End
          Else
            OutArr.Add(Item.Clone);
        End;
      Result := OutArr.AsJSON;
    Except
      Result := CatalogueJson;
    End;
  Finally
    OutArr.Free;
    Data.Free;
  End;
End;

End.
