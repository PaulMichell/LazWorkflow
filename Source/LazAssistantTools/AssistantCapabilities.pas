Unit AssistantCapabilities;

{ Capability support and the turn-backend registry (c) 2026 Michell Computing.

  Foundation only: no IDE units and no process. A backend registers itself.
  A missing id is unknown, not an error, and is not treated as Absent.
  IAssistantModelProvider remains the HTTP sign-in helper; it is not this registry. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Type
  { What the IDE path delivers. Native is that backend's own wire. Emulated is shared code standing in for a
    missing wire. Absent is not offered: the prompt section and the control stay out. }
  TAssistantSupport = (asNative, asEmulated, asAbsent);

  { Rows of the harness matrix. Mode gates stay with the catalogue; a Native row can still be limited to Plan
    and Build. }
  TAssistantCapability = (
    acHarnessPrompt,
    acSkillsAndAgents,
    acSubagents,
    acTodoWrite,
    acImageInput,
    acImageOutput,
    acWebSearch,
    acSteer,
    acPhoneApproval,
    acContextCompaction,
    acEventsJSONL,
    acRevisionEdits,
    acAsyncWork,
    acAccountUsage,
    acEffortControl);

  TAssistantCapabilitySet = Array[TAssistantCapability] Of TAssistantSupport;

  { How a registered engine becomes connected. erNone is not a turn engine. }
  TAssistantEngineReady = (erNone, erSignedIn, erRuntimeAndModel);

  TAssistantBackendInfo = Record
    Id: String;
    DisplayName: String;
    Support: TAssistantCapabilitySet;
    { Footer half of the effort row. Claude sends effort and does not show it. }
    ShowsEffort: Boolean;
    ReadyKind: TAssistantEngineReady;
  End;

/// Every capability Absent. A backend then sets the rows its path delivers.
Function AbsentCapabilitySet: TAssistantCapabilitySet;
/// A readable name for logs and tests. Not the user sentence.
Function AssistantCapabilityName(Capability: TAssistantCapability): String;
/// The one sentence for a missing capability. DisplayName is the connection name, such as Claude.
Function AssistantUnsupportedSentence(Capability: TAssistantCapability; Const DisplayName: String): String;
/// Replaces an existing id. An empty id is ignored.
Procedure RegisterAssistantBackend(Const Info: TAssistantBackendInfo);
/// False when the id is not registered. Info is cleared. Ids are the lowercase connection ids.
Function FindAssistantBackend(Const BackendId: String; Out Info: TAssistantBackendInfo): Boolean;
/// False when the backend is not registered. Support is not set in that case.
Function AssistantCapabilitySupport(Const BackendId: String; Capability: TAssistantCapability;
  Out Support: TAssistantSupport): Boolean;
/// True when the backend is registered and the row is not Absent. An unknown id is false, not Absent.
Function AssistantCapabilityDelivered(Const BackendId: String; Capability: TAssistantCapability): Boolean;
/// The effort footer. False for Claude, which sends effort and does not show it.
Function AssistantShowsEffort(Const BackendId: String): Boolean;
/// Steer during a turn. False when the row is Absent or the id is not registered.
Function AssistantCanSteer(Const BackendId: String): Boolean;
/// True when this id has a turn engine and that engine is signed in, or has a runtime and a model.
Function AssistantTurnEngineReady(Const BackendId, RuntimePath, Model: String; SignedIn: Boolean): Boolean;
/// The shared refusal for one capability. A known row is named. An empty id has no parentheses.
Function AssistantCapabilitySentence(Const BackendId: String; Capability: TAssistantCapability): String;
/// The shared refusal when no turn can start. A known row is named. An empty id has no parentheses.
Function AssistantTurnUnavailableSentence(Const BackendId: String): String;

Implementation

Uses
  SysUtils;

Var
  RegistryLock: TRTLCriticalSection;
  RegistryReady: Boolean;
  Registry: Array Of TAssistantBackendInfo;

Function AbsentCapabilitySet: TAssistantCapabilitySet;
Var
  Capability: TAssistantCapability;
Begin
  For Capability := Low(TAssistantCapability) To High(TAssistantCapability) Do
    Result[Capability] := asAbsent;
End;

Const
  CapabilityNames: Array[TAssistantCapability] Of String = (
    'harness system prompt',
    'skills and AGENTS.md',
    'subagents',
    'todo_write',
    'image input',
    'image output',
    'web search',
    'steer',
    'phone approval',
    'context compaction',
    'events JSONL',
    'revision-token edits',
    'async build, test, and command',
    'account usage query',
    'effort control');

Function AssistantCapabilityName(Capability: TAssistantCapability): String;
Begin
  Result := CapabilityNames[Capability];
End;

Function AssistantUnsupportedSentence(Capability: TAssistantCapability; Const DisplayName: String): String;
Var
  Name: String;
Begin
  { The row is the same sentence for every capability. The caller already knows which control was refused. }
  Name := Trim(DisplayName);
  If (Name = '') Or (AssistantCapabilityName(Capability) = '') Then
    Result := 'Not available with this connection.'
  Else
    Result := 'Not available with this connection (' + Name + ').';
End;

Procedure ClearBackendInfo(Out Info: TAssistantBackendInfo);
Begin
  Info.Id := '';
  Info.DisplayName := '';
  Info.Support := AbsentCapabilitySet;
  Info.ShowsEffort := False;
  Info.ReadyKind := erNone;
End;

Procedure RegisterAssistantBackend(Const Info: TAssistantBackendInfo);
Var
  I, Count: Integer;
Begin
  If (Trim(Info.Id) = '') Or (Not RegistryReady) Then
    Exit;
  EnterCriticalSection(RegistryLock);
  Try
    For I := 0 To High(Registry) Do
      If Registry[I].Id = Info.Id Then
        Begin
          Registry[I] := Info;
          Exit;
        End;
    Count := Length(Registry);
    SetLength(Registry, Count + 1);
    Registry[Count] := Info;
  Finally
    LeaveCriticalSection(RegistryLock);
  End;
End;

Function FindAssistantBackend(Const BackendId: String; Out Info: TAssistantBackendInfo): Boolean;
Var
  I: Integer;
Begin
  ClearBackendInfo(Info);
  Result := False;
  If (BackendId = '') Or (Not RegistryReady) Then
    Exit;
  EnterCriticalSection(RegistryLock);
  Try
    For I := 0 To High(Registry) Do
      If Registry[I].Id = BackendId Then
        Begin
          Info := Registry[I];
          Result := True;
          Exit;
        End;
  Finally
    LeaveCriticalSection(RegistryLock);
  End;
End;

Function AssistantCapabilitySupport(Const BackendId: String; Capability: TAssistantCapability;
  Out Support: TAssistantSupport): Boolean;
Var
  Info: TAssistantBackendInfo;
Begin
  Result := FindAssistantBackend(BackendId, Info);
  If Result Then
    Support := Info.Support[Capability];
End;

Function AssistantCapabilityDelivered(Const BackendId: String; Capability: TAssistantCapability): Boolean;
Var
  Support: TAssistantSupport;
Begin
  Result := AssistantCapabilitySupport(BackendId, Capability, Support) And (Support <> asAbsent);
End;

Function AssistantShowsEffort(Const BackendId: String): Boolean;
Var
  Info: TAssistantBackendInfo;
Begin
  Result := FindAssistantBackend(BackendId, Info) And Info.ShowsEffort;
End;

Function AssistantCanSteer(Const BackendId: String): Boolean;
Begin
  Result := AssistantCapabilityDelivered(BackendId, acSteer);
End;

Function AssistantTurnEngineReady(Const BackendId, RuntimePath, Model: String; SignedIn: Boolean): Boolean;
Var
  Info: TAssistantBackendInfo;
Begin
  Result := False;
  If Not FindAssistantBackend(BackendId, Info) Then
    Exit;
  Case Info.ReadyKind Of
    erSignedIn: Result := SignedIn;
    erRuntimeAndModel: Result := (Trim(RuntimePath) <> '') And (Trim(Model) <> '');
  Else
    Result := False;
  End;
End;

Function AssistantCapabilitySentence(Const BackendId: String; Capability: TAssistantCapability): String;
Var
  Info: TAssistantBackendInfo;
  Name: String;
Begin
  Name := '';
  If FindAssistantBackend(BackendId, Info) Then
    Name := Info.DisplayName;
  Result := AssistantUnsupportedSentence(Capability, Name);
End;

Function AssistantTurnUnavailableSentence(Const BackendId: String): String;
Begin
  Result := AssistantCapabilitySentence(BackendId, acHarnessPrompt);
End;

Initialization

InitCriticalSection(RegistryLock);
RegistryReady := True;

Finalization

RegistryReady := False;
Registry := Nil;
DoneCriticalSection(RegistryLock);

End.
