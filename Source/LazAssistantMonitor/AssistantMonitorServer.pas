Unit AssistantMonitorServer;

{ HTTPS listener for the remote monitor (c) 2026 Michell Computing.

  TFPHttpServer, threaded, with the minted DER certificate. Active blocks the
  caller, so the accept loop runs on its own thread. On Unix, SIGPIPE is ignored
  before listen: fphttpserver does not do that, and a dropped phone would
  otherwise kill the IDE. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Function StartMonitorHttps(Const Address: String; Port: Integer; Out ErrorText: String): Boolean;
Procedure StopMonitorHttps;
Function MonitorHttpsRunning: Boolean;
Function MonitorHttpsAddress: String;
Function MonitorHttpsPort: Integer;

Implementation

Uses
  {$IFDEF UNIX}
  BaseUnix, cthreads,
  {$ENDIF}
  Classes, fpjson, fphttpserver, Sockets, AssistantHttps, AssistantMonitorSettings, AssistantMonitorTls, WorkflowLog;

Type
  TMonitorListenThread = Class(TThread)
    Server: TFPHttpServer;
    Procedure Execute; Override;
  End;

  TMonitorHttps = Class
    Server: TFPHttpServer;
    Listen: TMonitorListenThread;
    Address: String;
    Port: Integer;
    Epoch: String;
    Stopping: Boolean;
    Procedure HandleRequest(Sender: TObject; Var ARequest: TFPHTTPConnectionRequest;
      Var AResponse: TFPHTTPConnectionResponse);
  End;

Var
  Live: TMonitorHttps;

Function MonitorHttpsRunning: Boolean;
Begin
  Result := Assigned(Live) And Assigned(Live.Listen) And (Not Live.Listen.Finished);
End;

Function MonitorHttpsAddress: String;
Begin
  If Assigned(Live) Then
    Result := Live.Address
  Else
    Result := '';
End;

Function MonitorHttpsPort: Integer;
Begin
  If Assigned(Live) Then
    Result := Live.Port
  Else
    Result := 0;
End;

Function ErrorJson(Const Reason, MessageText: String): String;
Var
  Obj: TJSONObject;
Begin
  Obj := TJSONObject.Create(['reason', Reason, 'message', MessageText]);
  Try
    Result := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Procedure WriteError(Var AResponse: TFPHTTPConnectionResponse; Status: Integer; Const Reason, MessageText: String);
Begin
  AResponse.Code := Status;
  AResponse.ContentType := 'application/json; charset=utf-8';
  AResponse.Content := ErrorJson(Reason, MessageText);
End;

Function RequestPath(Const Uri: String): String;
Var
  QueryAt: Integer;
Begin
  QueryAt := Pos('?', Uri);
  If QueryAt > 0 Then
    Result := Copy(Uri, 1, QueryAt - 1)
  Else
    Result := Uri;
  If (Result <> '') And (Result[Length(Result)] = '/') And (Result <> '/') Then
    Delete(Result, Length(Result), 1);
End;

Function BearerToken(ARequest: TFPHTTPConnectionRequest): String;
Var
  Header: String;
Begin
  Result := '';
  Header := Trim(ARequest.GetFieldByName('Authorization'));
  If Header = '' Then
    Exit;
  If Not SameText(Copy(Header, 1, 7), 'Bearer ') Then
    Exit;
  Result := Trim(Copy(Header, 8, MaxInt));
End;

Function TokenAccepted(Const Token: String): Boolean;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
  Index: Integer;
Begin
  Result := False;
  If Token = '' Then
    Exit;
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Exit;
  For Index := 0 To High(Settings.Clients) Do
    If Settings.Clients[Index].Token = Token Then
      Exit(True);
End;

Function ReadFileBytes(Const Path: String; Out Data: TBytes; Out ErrorText: String): Boolean;
Var
  Stream: TFileStream;
Begin
  Result := False;
  Data := Nil;
  ErrorText := '';
  If Not FileExists(Path) Then
    Begin
      ErrorText := 'Monitor certificate file is missing.';
      Exit;
    End;
  Try
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyWrite);
    Try
      SetLength(Data, Stream.Size);
      If Length(Data) > 0 Then
        Stream.ReadBuffer(Data[0], Length(Data));
    Finally
      Stream.Free;
    End;
    Result := Length(Data) > 0;
    If Not Result Then
      ErrorText := 'Monitor certificate file is empty.';
  Except
    On E: Exception Do
      ErrorText := E.Message;
  End;
End;

Function NewEpoch: String;
Var
  Guid: TGuid;
Begin
  CreateGUID(Guid);
  Result := LowerCase(GUIDToString(Guid));
  Result := StringReplace(Result, '{', '', []);
  Result := StringReplace(Result, '}', '', []);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
End;

Procedure WakeAccept(Const Address: String; Port: Integer);
Var
  Sock: TSocket;
  Host: String;
  Addr: TInetSockAddr;
Begin
  Host := Address;
  If (Host = '') Or (Host = MonitorBindAllAddress) Then
    Host := '127.0.0.1';
  Sock := fpSocket(AF_INET, SOCK_STREAM, 0);
  If Sock = TSocket(INVALID_SOCKET) Then
    Exit;
  Try
    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := HToNS(Port);
    Addr.sin_addr := StrToNetAddr(Host);
    fpConnect(Sock, @Addr, SizeOf(Addr));
  Finally
    CloseSocket(Sock);
  End;
End;

Procedure TMonitorListenThread.Execute;
Begin
  Try
    Server.Active := True;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('AssistantMonitor', 'listener accept ended: ' + E.Message);
  End;
End;

Procedure TMonitorHttps.HandleRequest(Sender: TObject; Var ARequest: TFPHTTPConnectionRequest;
  Var AResponse: TFPHTTPConnectionResponse);
Var
  Path, Method: String;
  Hello: TJSONObject;
Begin
  Path := RequestPath(ARequest.URI);
  Method := UpperCase(ARequest.Method);
  If Stopping Then
    Begin
      WriteError(AResponse, 503, 'no_session', 'The listener is stopping.');
      Exit;
    End;
  If (Path <> '/v4/pair') And (Not TokenAccepted(BearerToken(ARequest))) Then
    Begin
      WriteError(AResponse, 401, 'auth', 'The token was not accepted.');
      Exit;
    End;
  If (Path = '/v4/pair') And (Method = 'POST') Then
    Begin
      WriteError(AResponse, 400, 'protocol', 'Pairing is not available yet.');
      Exit;
    End;
  If (Path = '/v4/hello') And (Method = 'GET') Then
    Begin
      Hello := TJSONObject.Create;
      Try
        Hello.Add('epoch', Epoch);
        Hello.Add('rev', 0);
        Hello.Add('capabilities', TJSONArray.Create);
        AResponse.Code := 200;
        AResponse.ContentType := 'application/json; charset=utf-8';
        AResponse.Content := Hello.AsJSON;
      Finally
        Hello.Free;
      End;
      Exit;
    End;
  WriteError(AResponse, 404, 'not_found', 'That monitor path is not available.');
End;

Function StartMonitorHttps(Const Address: String; Port: Integer; Out ErrorText: String): Boolean;
Var
  CertificateDer, KeyDer: TBytes;
  Host: TMonitorHttps;
Begin
  Result := False;
  ErrorText := '';
  CertificateDer := Nil;
  KeyDer := Nil;
  If MonitorHttpsRunning Then
    Begin
      Result := True;
      Exit;
    End;
  If (Address = '') Or (Port <= 0) Or (Port > 65535) Then
    Begin
      ErrorText := 'The monitor bind address or port is not valid.';
      Exit;
    End;
  {$IFDEF UNIX}
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  {$ENDIF}
  If Not EnsureOpenSSLReady(ErrorText) Then
    Exit;
  If Not EnsureMonitorHostCertificate(ErrorText) Then
    Exit;
  If Not ReadFileBytes(MonitorCertificateFile, CertificateDer, ErrorText) Then
    Exit;
  If Not ReadFileBytes(MonitorKeyFile, KeyDer, ErrorText) Then
    Exit;
  If (CertificateDer[0] <> $30) Or (KeyDer[0] <> $30) Then
    Begin
      ErrorText := 'The monitor certificate is not DER.';
      Exit;
    End;
  Host := TMonitorHttps.Create;
  Host.Address := Address;
  Host.Port := Port;
  Host.Epoch := NewEpoch;
  Host.Server := TFPHttpServer.Create(Nil);
  Host.Server.Threaded := True;
  Host.Server.UseSSL := True;
  Host.Server.Address := Address;
  Host.Server.Port := Port;
  Host.Server.CertificateData.Certificate.Value := Copy(CertificateDer);
  Host.Server.CertificateData.PrivateKey.Value := Copy(KeyDer);
  Host.Server.OnRequest := @Host.HandleRequest;
  Host.Listen := TMonitorListenThread.Create(True);
  Host.Listen.FreeOnTerminate := False;
  Host.Listen.Server := Host.Server;
  Live := Host;
  Host.Listen.Start;
  Sleep(300);
  If Host.Listen.Finished Then
    Begin
      ErrorText := 'The monitor listener did not stay open.';
      StopMonitorHttps;
      Exit;
    End;
  Result := True;
  WorkflowLogger.Info('AssistantMonitor', 'listen start bind=' + Address + ' port=' + IntToStr(Port));
End;

Procedure StopMonitorHttps;
Var
  Host: TMonitorHttps;
Begin
  Host := Live;
  If Not Assigned(Host) Then
    Exit;
  If Host.Stopping Then
    Exit;
  Host.Stopping := True;
  Try
    If Assigned(Host.Server) Then
      Host.Server.Active := False;
    WakeAccept(Host.Address, Host.Port);
    If Assigned(Host.Listen) Then
      Begin
        Host.Listen.WaitFor;
        FreeAndNil(Host.Listen);
      End;
    FreeAndNil(Host.Server);
  Finally
    Live := Nil;
    Host.Free;
  End;
  WorkflowLogger.Info('AssistantMonitor', 'listen stop');
End;

End.
