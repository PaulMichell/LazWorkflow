Unit AssistantMCPListener;

{ Loopback HTTP endpoint for Claude Code's MCP client, one bearer token per run (c) 2026 Michell Computing.

  MCP's streamable HTTP transport with plain JSON answers: a POST to /mcp carries one JSON-RPC message and gets
  200 with the response, or 202 with no body for a notification. GET (the optional event stream) and DELETE (session
  end) get 405, which the transport allows. No session id is issued.

  The socket is bound to 127.0.0.1 on a port the kernel picks. Start makes a new random token, and any request that
  does not carry it as "Authorization: Bearer" gets 401 before its path or body is looked at. Each accepted connection
  is served on its own thread and closed after one response, so a tool call that is still running never holds up
  initialize or tools/list from the same or another session.

  The executor is called on those connection threads, several at once when Claude runs tools in parallel. Stop waits
  for calls already running, so the executor must return when the run is cancelled; on the main thread the wait keeps
  serving TThread.Synchronize and TThread.Queue so an executor that marshals to the IDE thread can finish.

  Start also writes the --mcp-config JSON to an owner-only file in the temporary directory, so the token is never on
  a command line. Stop deletes it. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantMCPProtocol;

Const
  MCPListenHost = '127.0.0.1';
  MCPEndpointPath = '/mcp';

Type
  TMCPListener = Class
  Private
    FPort: Word;
    FToken: String;
    FConfigFileName: String;
    Catalogue: String;
    ToolExecutor: TMCPToolExecutor;
    Lock: TRTLCriticalSection;
    Connections: TList;
    AcceptThread: TThread;
    Ready: PRTLEvent;
    BindError: String;
    Function GetRunning: Boolean;
    Function GetURL: String;
    Procedure AddConnection(Connection: TThread);
    Procedure ReapConnections;
    Procedure CloseConnections;
  Public
    Constructor Create(Const ToolsJSON: String; Executor: TMCPToolExecutor);
    Destructor Destroy; Override;
    /// Binds a free loopback port, makes a new token and writes the --mcp-config file. Stops an earlier run first.
    Function Start(Out ErrorText: String): Boolean;
    /// Stops accepting, closes open connections, waits for running calls and deletes the config file. Safe to repeat.
    Procedure Stop;
    Property Running: Boolean Read GetRunning;
    Property Port: Word Read FPort;
    Property Token: String Read FToken;
    Property URL: String Read GetURL;
    /// The owner-only file to pass as --mcp-config while the listener runs; '' when stopped.
    Property ConfigFileName: String Read FConfigFileName;
  End;

/// The --mcp-config document naming the server lazarus at URL with Token as its bearer header.
Function MCPConfigJSON(Const EndpointURL, BearerToken: String): String;

Implementation

Uses
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  ssockets, sockets, fpjson, fphashutils;

Const
  TokenBytes = 32;
  BindWaitMs = 10000;
  AcceptIdleMs = 100;
  { A stalled client is dropped after this long without a byte. A running tool call is not affected. }
  ReadTimeoutMs = 30000;
  MaxHeadBytes = 65536;
  MaxBodyBytes = 32 * 1024 * 1024;

Type
  TMCPAcceptThread = Class(TThread)
  Private
    Listener: TMCPListener;
    Server: TInetServer;
    Procedure HandleConnect(Sender: TObject; Data: TSocketStream);
    Procedure HandleIdle(Sender: TObject);
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Owner: TMCPListener);
  End;

  TMCPConnectionThread = Class(TThread)
  Private
    Listener: TMCPListener;
    { Guarded by the listener's lock: Stop shuts it down from another thread to end a blocked read. }
    Stream: TSocketStream;
    Function ReadMore(Var Buffer: String): Boolean;
    Procedure Respond(Code: Integer; Const Reason, ExtraHeaders, ContentType, BodyText: String);
    Procedure Serve;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Owner: TMCPListener; Data: TSocketStream);
    Destructor Destroy; Override;
  End;

Function MCPConfigJSON(Const EndpointURL, BearerToken: String): String;
Var
  Config: TJSONObject;
Begin
  Config := TJSONObject.Create(['mcpServers', TJSONObject.Create([MCPServerName, TJSONObject.Create(['type', 'http',
    'url', EndpointURL, 'headers', TJSONObject.Create(['Authorization', 'Bearer ' + BearerToken])])])]);
  Try
    Result := Config.AsJSON;
  Finally
    Config.Free;
  End;
End;

Function NewToken(Out TokenText: String): Boolean;
Var
  Bytes: Array[0..TokenBytes - 1] Of Byte;
  I: Integer;
Begin
  TokenText := '';
  Result := CryptoGetRandomBytes(@Bytes[0], TokenBytes);
  If Not Result Then
    Exit;
  For I := 0 To TokenBytes - 1 Do
    TokenText := TokenText + LowerCase(IntToHex(Bytes[I], 2));
End;

{ Compares every byte whatever the first difference, so the time taken says nothing about the token. }
Function SameToken(Const Offered, Expected: String): Boolean;
Var
  Difference, I: Integer;
Begin
  Result := False;
  If (Expected = '') Or (Length(Offered) <> Length(Expected)) Then
    Exit;
  Difference := 0;
  For I := 1 To Length(Expected) Do
    Difference := Difference Or (Ord(Offered[I]) Xor Ord(Expected[I]));
  Result := Difference = 0;
End;

{ Creates the file for this user alone; fails rather than open a file that is already there. }
Function WriteOwnerOnlyFile(Const FileName, Contents: String; Out ErrorText: String): Boolean;
{$IFDEF UNIX}
Var
  Handle: cint;
  Written: TSsize;
{$ENDIF}
{$IFNDEF UNIX}
Var
  FileStream: TFileStream;
{$ENDIF}
Begin
  ErrorText := '';
  Result := False;
{$IFDEF UNIX}
  Handle := FpOpen(PChar(FileName), O_WRONLY Or O_CREAT Or O_EXCL, &600);
  If Handle < 0 Then
    Begin
      ErrorText := 'Could not create ' + FileName + ' (error ' + IntToStr(fpgeterrno) + ').';
      Exit;
    End;
  Try
    Written := 0;
    If Length(Contents) > 0 Then
      Written := FpWrite(Handle, Contents[1], Length(Contents));
    Result := Written = Length(Contents);
  Finally
    FpClose(Handle);
  End;
  If Not Result Then
    Begin
      ErrorText := 'Could not write ' + FileName + '.';
      DeleteFile(FileName);
    End;
{$ELSE}
  { The temporary directory on Windows is inside the user's profile, which only that user can read. }
  If FileExists(FileName) Then
    Begin
      ErrorText := FileName + ' already exists.';
      Exit;
    End;
  Try
    FileStream := TFileStream.Create(FileName, fmCreate Or fmShareExclusive);
    Try
      If Length(Contents) > 0 Then
        FileStream.WriteBuffer(Contents[1], Length(Contents));
    Finally
      FileStream.Free;
    End;
    Result := True;
  Except
    On E: Exception Do
      Begin
        ErrorText := 'Could not write ' + FileName + ': ' + E.Message;
        DeleteFile(FileName);
      End;
  End;
{$ENDIF}
End;

Function BoundPort(Server: TInetServer): Word;
Var
  Address: TSockAddr;
  AddressLength: TSockLen;
Begin
  Result := 0;
  Address := Default(TSockAddr);
  AddressLength := SizeOf(Address);
  { TInetServer.Port keeps the requested 0; the kernel's choice is only in the socket. }
  If fpGetSockName(Server.FPSocket.FD, @Address, @AddressLength) = 0 Then
    Result := NToHs(Address.sin_port);
End;

{ Waits for a thread the caller owns. On the main thread it keeps serving Synchronize, which the thread may be in. }
Procedure WaitForThread(Thread: TThread);
Begin
  If GetCurrentThreadId = MainThreadID Then
    While Not Thread.Finished Do
      CheckSynchronize(10);
  Thread.WaitFor;
End;

Function HeaderValue(Headers: TStrings; Const HeaderName: String): String;
Var
  I, Colon: Integer;
Begin
  Result := '';
  For I := 1 To Headers.Count - 1 Do
    Begin
      Colon := Pos(':', Headers[I]);
      If (Colon > 1) And SameText(Trim(Copy(Headers[I], 1, Colon - 1)), HeaderName) Then
        Begin
          Result := Trim(Copy(Headers[I], Colon + 1, MaxInt));
          Exit;
        End;
    End;
End;

Function BearerToken(Const Authorization: String): String;
Begin
  Result := '';
  If SameText(Copy(Authorization, 1, 7), 'Bearer ') Then
    Result := Trim(Copy(Authorization, 8, MaxInt));
End;

{ TMCPAcceptThread }

Constructor TMCPAcceptThread.Create(Owner: TMCPListener);
Begin
  Listener := Owner;
  Server := Nil;
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Procedure TMCPAcceptThread.HandleConnect(Sender: TObject; Data: TSocketStream);
Var
  Connection: TMCPConnectionThread;
Begin
  If Terminated Then
    Begin
      Data.Free;
      Exit;
    End;
  Listener.ReapConnections;
  Try
    Connection := TMCPConnectionThread.Create(Listener, Data);
  Except
    Data.Free;
    Exit;
  End;
  Listener.AddConnection(Connection);
End;

Procedure TMCPAcceptThread.HandleIdle(Sender: TObject);
Begin
  If Terminated And Assigned(Server) Then
    Server.StopAccepting(True);
End;

Procedure TMCPAcceptThread.Execute;
Begin
  Try
    Try
      Server := TInetServer.Create(MCPListenHost, 0);
      Server.ReuseAddress := False;
      Server.AcceptIdleTimeOut := AcceptIdleMs;
      { Lifetime accept count. -1 keeps accepting. }
      Server.MaxConnections := -1;
      Server.OnConnect := @HandleConnect;
      Server.OnIdle := @HandleIdle;
      Server.Bind;
      Listener.FPort := BoundPort(Server);
      If Listener.FPort = 0 Then
        Begin
          Listener.BindError := 'Could not read the MCP listener port.';
          Exit;
        End;
      Server.Listen;
      RTLEventSetEvent(Listener.Ready);
      Server.StartAccepting;
    Except
      On Error: Exception Do
        If Listener.FPort = 0 Then
          Listener.BindError := 'The MCP listener could not start: ' + Error.Message
        Else
          Listener.BindError := Error.Message;
    End;
  Finally
    If Assigned(Server) Then
      Begin
        Server.OnConnect := Nil;
        Server.OnIdle := Nil;
        FreeAndNil(Server);
      End;
    RTLEventSetEvent(Listener.Ready);
  End;
End;

{ TMCPConnectionThread }

Constructor TMCPConnectionThread.Create(Owner: TMCPListener; Data: TSocketStream);
Begin
  Listener := Owner;
  Stream := Data;
  Stream.IOTimeout := ReadTimeoutMs;
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Destructor TMCPConnectionThread.Destroy;
Begin
  FreeAndNil(Stream);
  Inherited Destroy;
End;

Function TMCPConnectionThread.ReadMore(Var Buffer: String): Boolean;
Var
  Chunk: Array[0..16383] Of Byte;
  Count, Filled: Integer;
Begin
  Count := Stream.Read(Chunk[0], SizeOf(Chunk));
  Result := Count > 0;
  If Not Result Then
    Exit;
  Filled := Length(Buffer);
  SetLength(Buffer, Filled + Count);
  Move(Chunk[0], Buffer[Filled + 1], Count);
End;

Procedure TMCPConnectionThread.Respond(Code: Integer; Const Reason, ExtraHeaders, ContentType, BodyText: String);
Var
  Response: String;
Begin
  Response := 'HTTP/1.1 ' + IntToStr(Code) + ' ' + Reason + #13#10 + ExtraHeaders;
  If BodyText <> '' Then
    Response := Response + 'Content-Type: ' + ContentType + #13#10;
  Response := Response + 'Content-Length: ' + IntToStr(Length(BodyText)) + #13#10 + 'Connection: close'#13#10#13#10 + BodyText;
  Stream.WriteBuffer(Response[1], Length(Response));
End;

Procedure TMCPConnectionThread.Serve;
Var
  Buffer, Body, Method, Target, LengthText, ResponseText: String;
  Headers: TStringList;
  HeadEnd, Space, BodyLength: Integer;
Begin
  Buffer := '';
  Repeat
    If Not ReadMore(Buffer) Then
      Exit;
    HeadEnd := Pos(#13#10#13#10, Buffer);
    If (HeadEnd = 0) And (Length(Buffer) > MaxHeadBytes) Then
      Begin
        Respond(431, 'Request Header Fields Too Large', '', 'text/plain', 'Request head too large.');
        Exit;
      End;
  Until HeadEnd > 0;
  Headers := TStringList.Create;
  Try
    Headers.Text := Copy(Buffer, 1, HeadEnd - 1);
    Delete(Buffer, 1, HeadEnd + 3);
    If Headers.Count = 0 Then
      Begin
        Respond(400, 'Bad Request', '', 'text/plain', 'No request line.');
        Exit;
      End;
    Space := Pos(' ', Headers[0]);
    Method := Copy(Headers[0], 1, Space - 1);
    Target := Trim(Copy(Headers[0], Space + 1, MaxInt));
    Space := Pos(' ', Target);
    If (Method = '') Or (Space = 0) Then
      Begin
        Respond(400, 'Bad Request', '', 'text/plain', 'Malformed request line.');
        Exit;
      End;
    Target := Copy(Target, 1, Space - 1);
    If Pos('?', Target) > 0 Then
      Target := Copy(Target, 1, Pos('?', Target) - 1);
    { The token is checked before anything else, so a caller without it learns nothing about the server. }
    If Not SameToken(BearerToken(HeaderValue(Headers, 'Authorization')), Listener.Token) Then
      Begin
        Respond(401, 'Unauthorized', 'WWW-Authenticate: Bearer'#13#10, 'text/plain', 'Unauthorized.');
        Exit;
      End;
    If Target <> MCPEndpointPath Then
      Begin
        Respond(404, 'Not Found', '', 'text/plain', 'Not found.');
        Exit;
      End;
    If Method <> 'POST' Then
      Begin
        Respond(405, 'Method Not Allowed', 'Allow: POST'#13#10, 'text/plain', 'This server sends no event stream.');
        Exit;
      End;
    If HeaderValue(Headers, 'Transfer-Encoding') <> '' Then
      Begin
        Respond(411, 'Length Required', '', 'text/plain', 'Send the body with a Content-Length.');
        Exit;
      End;
    LengthText := HeaderValue(Headers, 'Content-Length');
    If LengthText = '' Then
      Begin
        Respond(411, 'Length Required', '', 'text/plain', 'Send the body with a Content-Length.');
        Exit;
      End;
    BodyLength := StrToIntDef(LengthText, -1);
    If (BodyLength < 0) Or (BodyLength > MaxBodyBytes) Then
      Begin
        Respond(413, 'Content Too Large', '', 'text/plain', 'The body is too large.');
        Exit;
      End;
  Finally
    Headers.Free;
  End;
  While Length(Buffer) < BodyLength Do
    If Not ReadMore(Buffer) Then
      Exit;
  Body := Copy(Buffer, 1, BodyLength);
  If MCPHandleMessage(Body, Listener.Catalogue, Listener.ToolExecutor, ResponseText) Then
    Respond(200, 'OK', '', 'application/json', ResponseText)
  Else
    Respond(202, 'Accepted', '', '', '');
End;

Procedure TMCPConnectionThread.Execute;
Begin
  Try
    Serve;
  Except
    { The client went away or the run stopped; there is no one left to answer. }
    On Error: Exception Do
      ;
  End;
  { Closed here rather than when the thread is reaped, so the client sees the end of the response at once. }
  EnterCriticalSection(Listener.Lock);
  Try
    FreeAndNil(Stream);
  Finally
    LeaveCriticalSection(Listener.Lock);
  End;
End;

{ TMCPListener }

Constructor TMCPListener.Create(Const ToolsJSON: String; Executor: TMCPToolExecutor);
Begin
  Inherited Create;
  InitCriticalSection(Lock);
  Connections := TList.Create;
  Ready := RTLEventCreate;
  Catalogue := ToolsJSON;
  ToolExecutor := Executor;
  AcceptThread := Nil;
  FPort := 0;
  FToken := '';
  FConfigFileName := '';
End;

Destructor TMCPListener.Destroy;
Begin
  Stop;
  FreeAndNil(Connections);
  RTLEventDestroy(Ready);
  DoneCriticalSection(Lock);
  Inherited Destroy;
End;

Function TMCPListener.GetRunning: Boolean;
Begin
  Result := Assigned(AcceptThread);
End;

Function TMCPListener.GetURL: String;
Begin
  Result := '';
  If FPort <> 0 Then
    Result := 'http://' + MCPListenHost + ':' + IntToStr(FPort) + MCPEndpointPath;
End;

Procedure TMCPListener.AddConnection(Connection: TThread);
Begin
  EnterCriticalSection(Lock);
  Try
    Connections.Add(Connection);
  Finally
    LeaveCriticalSection(Lock);
  End;
End;

{ Frees connection threads that have finished. Called on the accept thread, which Stop has joined before it frees the rest. }
Procedure TMCPListener.ReapConnections;
Var
  Done: TList;
  I: Integer;
Begin
  Done := TList.Create;
  Try
    EnterCriticalSection(Lock);
    Try
      For I := Connections.Count - 1 DownTo 0 Do
        If TThread(Connections[I]).Finished Then
          Begin
            Done.Add(Connections[I]);
            Connections.Delete(I);
          End;
    Finally
      LeaveCriticalSection(Lock);
    End;
    For I := 0 To Done.Count - 1 Do
      Begin
        TThread(Done[I]).WaitFor;
        TThread(Done[I]).Free;
      End;
  Finally
    Done.Free;
  End;
End;

Procedure TMCPListener.CloseConnections;
Var
  Pending: TList;
  Connection: TMCPConnectionThread;
  I: Integer;
Begin
  Pending := TList.Create;
  Try
    EnterCriticalSection(Lock);
    Try
      For I := 0 To Connections.Count - 1 Do
        Begin
          Connection := TMCPConnectionThread(Connections[I]);
          Connection.Terminate;
          { Ends a read that is waiting for the client. A call already in the executor finishes and its write fails. }
          If Assigned(Connection.Stream) Then
            fpShutdown(Connection.Stream.Handle, 2);
          Pending.Add(Connection);
        End;
      Connections.Clear;
    Finally
      LeaveCriticalSection(Lock);
    End;
    For I := 0 To Pending.Count - 1 Do
      Begin
        WaitForThread(TThread(Pending[I]));
        TThread(Pending[I]).Free;
      End;
  Finally
    Pending.Free;
  End;
End;

Function TMCPListener.Start(Out ErrorText: String): Boolean;
Var
  RunToken, FileName: String;
Begin
  ErrorText := '';
  Result := False;
  Stop;
  If Not NewToken(RunToken) Then
    Begin
      ErrorText := 'Could not make a token for the MCP listener: no system random source.';
      Exit;
    End;
  FToken := RunToken;
  BindError := '';
  FPort := 0;
  RTLEventResetEvent(Ready);
  AcceptThread := TMCPAcceptThread.Create(Self);
  RTLEventWaitFor(Ready, BindWaitMs);
  If (FPort = 0) Or (BindError <> '') Then
    Begin
      ErrorText := BindError;
      If ErrorText = '' Then
        ErrorText := 'The MCP listener did not start within ' + IntToStr(BindWaitMs Div 1000) + ' s.';
      Stop;
      Exit;
    End;
  If Not NewToken(FileName) Then
    Begin
      ErrorText := 'Could not name the MCP config file: no system random source.';
      Stop;
      Exit;
    End;
  FileName := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'lazarus-mcp-' + Copy(FileName, 1, 16) + '.json';
  If Not WriteOwnerOnlyFile(FileName, MCPConfigJSON(URL, FToken), ErrorText) Then
    Begin
      Stop;
      Exit;
    End;
  FConfigFileName := FileName;
  Result := True;
End;

Procedure TMCPListener.Stop;
Begin
  If Assigned(AcceptThread) Then
    Begin
      AcceptThread.Terminate;
      AcceptThread.WaitFor;
      FreeAndNil(AcceptThread);
    End;
  CloseConnections;
  If FConfigFileName <> '' Then
    DeleteFile(FConfigFileName);
  FConfigFileName := '';
  FToken := '';
  FPort := 0;
End;

End.
