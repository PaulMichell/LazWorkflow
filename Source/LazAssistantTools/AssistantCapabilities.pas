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

  TAssistantBackendInfo = Record
    Id: String;
    DisplayName: String;
    Support: TAssistantCapabilitySet;
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

Initialization

InitCriticalSection(RegistryLock);
RegistryReady := True;

Finalization

RegistryReady := False;
Registry := Nil;
DoneCriticalSection(RegistryLock);

End.
