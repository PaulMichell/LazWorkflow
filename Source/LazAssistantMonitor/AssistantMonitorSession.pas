Unit AssistantMonitorSession;

{ Monitor session state machine. The LAN carrier owns the socket.
  This unit does not use TInetServer. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorFrames, AssistantMonitorCarrier;

Type
  { Stopped, Listening, Accepted, Live, Busy, and Revoked are the design edges.
    Listening to Accepted is the handshake, not hello. }
  TMonitorSessionState = (
    mssStopped,
    mssListening,
    mssAccepted,
    mssLive,
    mssBusy,
    mssRevoked
  );

  TMonitorSession = Class
  Private
    FState: TMonitorSessionState;
    FCarrier: IMonitorCarrier;
    Procedure InboundFrame(Const Frame: TMonitorFrame);
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure AttachCarrier(Const Carrier: IMonitorCarrier);
    Property State: TMonitorSessionState Read FState;
    Property Carrier: IMonitorCarrier Read FCarrier;
  End;

Implementation

Uses
  AssistantMonitorCodec;

Constructor TMonitorSession.Create;
Begin
  Inherited Create;
  FState := mssStopped;
  FCarrier := Nil;
End;

Destructor TMonitorSession.Destroy;
Begin
  AttachCarrier(Nil);
  Inherited Destroy;
End;

Procedure TMonitorSession.AttachCarrier(Const Carrier: IMonitorCarrier);
Begin
  If Assigned(FCarrier) Then
    FCarrier.SetFrameHandler(Nil);
  FCarrier := Carrier;
  If Assigned(FCarrier) Then
    FCarrier.SetFrameHandler(@InboundFrame);
End;

Procedure TMonitorSession.InboundFrame(Const Frame: TMonitorFrame);
Var
  Message: TMonitorMessage;
  Reply: TMonitorFrame;
  ErrorText: String;
Begin
  If Not TryDecodeMonitorEnvelope(Frame.Json, Message, ErrorText) Then
    Exit;
  { An unknown type is already an error. It must not move the state machine. }
  If Not Message.ChangesState Then
    Begin
      If (Message.Kind = mmkError) And Assigned(FCarrier) And (Message.WireJson <> '') Then
        Begin
          Reply.Version := MonitorFrameVersion;
          Reply.Flags := 0;
          Reply.Json := Message.WireJson;
          FCarrier.Send(Reply, ErrorText);
        End;
      Exit;
    End;
End;

End.
