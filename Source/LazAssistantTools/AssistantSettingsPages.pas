Unit AssistantSettingsPages;

{ Registry of connection settings frames. The settings form asks this list.
  It does not switch panels by backend name. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantConnections;

Type
  { One backend's settings page. The form does not name the backend. }
  TAssistantSettingsPage = Class
    Function BackendId: String; virtual; abstract;
    Function KindCaption: String; virtual; abstract;
    { Component name of the host panel already on the settings form. }
    Function PanelName: String; virtual; abstract;
    Procedure Load(Host: TComponent; Item: TAssistantConnection); virtual;
    Procedure Store(Host: TComponent; Item: TAssistantConnection); virtual;
    Procedure ApplyNew(Host: TComponent; Item: TAssistantConnection); virtual;
    Function ModelText(Host: TComponent): String; virtual;
    Procedure RestoreModelText(Host: TComponent; Const Text: String; Index: Integer); virtual;
    Function Busy(Host: TComponent): Boolean; virtual;
  End;

Procedure RegisterAssistantSettingsPage(Page: TAssistantSettingsPage);
Function FindAssistantSettingsPage(Const BackendId: String): TAssistantSettingsPage;
Function AssistantSettingsKindCaption(Const BackendId: String): String;
Function AssistantSettingsPageCount: Integer;
Function AssistantSettingsPageAt(Index: Integer): TAssistantSettingsPage;
Function AssistantSettingsBusy(Host: TComponent): Boolean;

Implementation

Var
  Pages: Array Of TAssistantSettingsPage;

Procedure RegisterAssistantSettingsPage(Page: TAssistantSettingsPage);
Var
  N: Integer;
Begin
  If Not Assigned(Page) Then
    Exit;
  N := Length(Pages);
  SetLength(Pages, N + 1);
  Pages[N] := Page;
End;

Function FindAssistantSettingsPage(Const BackendId: String): TAssistantSettingsPage;
Var
  I: Integer;
Begin
  Result := Nil;
  For I := 0 To High(Pages) Do
    If Pages[I].BackendId = BackendId Then
      Exit(Pages[I]);
End;

Function AssistantSettingsKindCaption(Const BackendId: String): String;
Var
  Page: TAssistantSettingsPage;
Begin
  Page := FindAssistantSettingsPage(BackendId);
  If Assigned(Page) Then
    Result := Page.KindCaption
  Else
    Result := '';
End;

Function AssistantSettingsPageCount: Integer;
Begin
  Result := Length(Pages);
End;

Function AssistantSettingsPageAt(Index: Integer): TAssistantSettingsPage;
Begin
  If (Index < 0) Or (Index > High(Pages)) Then
    Result := Nil
  Else
    Result := Pages[Index];
End;

Function AssistantSettingsBusy(Host: TComponent): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 0 To High(Pages) Do
    If Pages[I].Busy(Host) Then
      Exit(True);
End;

Procedure TAssistantSettingsPage.Load(Host: TComponent; Item: TAssistantConnection);
Begin
End;

Procedure TAssistantSettingsPage.Store(Host: TComponent; Item: TAssistantConnection);
Begin
End;

Procedure TAssistantSettingsPage.ApplyNew(Host: TComponent; Item: TAssistantConnection);
Begin
End;

Function TAssistantSettingsPage.ModelText(Host: TComponent): String;
Begin
  Result := '';
End;

Procedure TAssistantSettingsPage.RestoreModelText(Host: TComponent; Const Text: String; Index: Integer);
Begin
End;

Function TAssistantSettingsPage.Busy(Host: TComponent): Boolean;
Begin
  Result := False;
End;

End.
