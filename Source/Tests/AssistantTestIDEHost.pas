Unit AssistantTestIDEHost;
{$mode objfpc}{$H+}
{ Supply the IDE configuration callback before assistant unit initialization.
  Tests must never load or save the user's real IDE configuration/credentials. }
Interface
Implementation
Uses BaseIDEIntf, LazConfigStorage;
Function TestConfig(Const Filename: String; LoadFromDisk: Boolean): TConfigStorage;
Begin Result := TConfigMemStorage.Create('', False); End;
Initialization
  GetIDEConfigStorage := @TestConfig;
End.
