Unit AssistantMonitorCarrier;

{ Transport seam for monitor frames. The LAN carrier is the v1 implementation.
  No relay class is compiled. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorFrames;

Type
  TMonitorCarrierState = (
    mcsIdle,
    mcsConnecting,
    mcsListening,
    mcsConnected,
    mcsClosed
  );

  TMonitorFrameHandler = Procedure(Const Frame: TMonitorFrame) Of Object;

  IMonitorCarrier = Interface
    ['{7C1A6E2B-4F0D-4C1A-9B3E-2A6D8F0C1E44}']
    Function Start(Out ErrorText: String): Boolean;
    Procedure Stop;
    Function Send(Const Frame: TMonitorFrame; Out ErrorText: String): Boolean;
    Function State: TMonitorCarrierState;
    Procedure SetFrameHandler(Handler: TMonitorFrameHandler);
    { Drops frames accepted by Send and not yet written. A new conversation must not wait behind them. }
    Procedure DiscardUnsent;
  End;

Implementation

End.
