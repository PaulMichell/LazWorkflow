Unit AssistantMonitorTls;

{ Host certificate minting for the monitor (c) 2026 Michell Computing.

  OpenSSL load is AssistantHttps.EnsureOpenSSLReady. The one-time mint calls
  protected CreateSelfSignedCertificate. CreateCertificateAndKey stores DER
  from i2dX509Bio and i2dPrivatekeyBio. There is no InitContext override, no
  PEM writer, and no ALPN h2 offer. Fingerprint is fpsha256.TSHA256.DigestBytes
  over that DER, then fphashutils.BytesToHexStr in lowercase. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, opensslsockets;

Const
  MonitorCertificateCommonName = 'LazAssistantMonitor';
  { UTCTime years 00-49 mean 2000-2049. 2050 would encode as 50 and mean 1950. }
  MonitorCertificateValidYear = 2049;
  MonitorCertificateMaxBytes = 65536;

Type
  { Exposes one-time host certificate minting from the OpenSSL handler. }
  TMonitorTlsHandler = Class(TOpenSSLSocketHandler)
  Public
    Constructor Create; Override;
    { One-time mint into this handler. Does not write the certificate files. }
    Function MintHostMaterial(Out ErrorText: String): Boolean;
  End;

{ Creates the certificate and key once. A second call keeps the same files. }
Function EnsureMonitorHostCertificate(Out ErrorText: String): Boolean;
{ Lowercase hex of SHA-256 over the certificate DER. Not a PEM hash. }
Function MonitorHostFingerprint(Out Fingerprint, ErrorText: String): Boolean;
{ Groups of two for the options form. The stored fingerprint has no spaces. }
Function MonitorFingerprintText(Const Fingerprint: String): String;
{ Same predicate as H2TLSVersionAdequate: TLS 1.2 or higher. }
Function MonitorTlsVersionAdequate(Const VersionText: String): Boolean;
{ One DER file. The listen thread passes the paths copied at start. }
Function LoadMonitorDerFile(Const Path: String; Out Data: TBytes; Out ErrorText: String): Boolean;

Implementation

Uses
  Classes, fpsha256, fphashutils, AssistantHttps, AssistantMonitorSettings, SafeFileAccess, WorkflowSettings;

Function MonitorTlsVersionAdequate(Const VersionText: String): Boolean;
Begin
  Result := H2TLSVersionAdequate(VersionText);
End;

Function MonitorFingerprintText(Const Fingerprint: String): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 1 To Length(Fingerprint) Do
    Begin
      If (I > 1) And ((I Mod 2) = 1) Then
        Result := Result + ' ';
      Result := Result + Fingerprint[I];
    End;
End;

Function FingerprintOf(Const Der: TBytes): String;
Var
  Digest: TBytes;
  Hex: AnsiString;
Begin
  Result := '';
  Digest := Nil;
  If Length(Der) = 0 Then
    Exit;
  TSHA256.DigestBytes(Der, Digest);
  Hex := BytesToHexStr(Digest);
  Result := LowerCase(String(Hex));
End;

Function CopyBytes(Const Source: TBytes): TBytes;
Begin
  Result := Nil;
  SetLength(Result, Length(Source));
  If Length(Result) > 0 Then
    Move(Source[0], Result[0], Length(Result));
End;

Function ReadDerFile(Const Path: String; Out Data: TBytes; Out ErrorText: String): Boolean;
Var
  Stream: TFileStream;
  Count: Int64;
Begin
  Result := False;
  Data := Nil;
  ErrorText := '';
  If Not IsRegularFile(Path, MonitorCertificateMaxBytes) Then
    Begin
      ErrorText := 'Monitor certificate file is missing.';
      Exit;
    End;
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyWrite);
  Try
    Count := Stream.Size;
    If (Count < 1) Or (Count > MonitorCertificateMaxBytes) Then
      Begin
        ErrorText := 'Monitor certificate file is empty.';
        Exit;
      End;
    SetLength(Data, Count);
    Stream.ReadBuffer(Data[0], Count);
  Finally
    Stream.Free;
  End;
  If Data[0] <> $30 Then
    Begin
      SetLength(Data, 0);
      ErrorText := 'Monitor certificate file is not DER.';
      Exit;
    End;
  Result := True;
End;

Function WriteProtectedDer(Const Path: String; Const Data: TBytes; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Length(Data) < 1 Then
    Begin
      ErrorText := 'Monitor certificate data is empty.';
      Exit;
    End;
  If Not CreateExclusiveNoFollow(Path, Data, ErrorText) Then
    Exit;
  If Not ProtectOwnerOnlyFile(Path) Then
    Begin
      DeleteFile(Path);
      ErrorText := 'Could not protect the monitor certificate file.';
      Exit;
    End;
  Result := True;
End;

Function HostFilesPresent: Boolean;
Begin
  Result := PathEntryExists(MonitorCertificateFile) Or PathEntryExists(MonitorKeyFile);
End;

Function HostFilesReady(Out CertificateDer, KeyDer: TBytes; Out ErrorText: String): Boolean;
Begin
  Result := False;
  CertificateDer := Nil;
  KeyDer := Nil;
  ErrorText := '';
  If Not IsRegularFile(MonitorCertificateFile, MonitorCertificateMaxBytes) Or
    Not IsRegularFile(MonitorKeyFile, MonitorCertificateMaxBytes) Then
    Exit;
  Result := ReadDerFile(MonitorCertificateFile, CertificateDer, ErrorText) And
    ReadDerFile(MonitorKeyFile, KeyDer, ErrorText);
End;

Constructor TMonitorTlsHandler.Create;
Begin
  Inherited Create;
  VerifyPeerCert := False;
  If Assigned(CertificateData) Then
    CertificateData.ALPNProtocols := '';
End;

Function TMonitorTlsHandler.MintHostMaterial(Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Result := False;
  CertGenerator.CommonName := MonitorCertificateCommonName;
  { SetNameData writes HostName into the subject CN. CommonName alone would leave CN as localhost. }
  CertGenerator.HostName := MonitorCertificateCommonName;
  CertGenerator.ValidFrom := Date - 1;
  CertGenerator.ValidTo := EncodeDate(MonitorCertificateValidYear, 12, 31);
  CertificateData.ALPNProtocols := '';
  VerifyPeerCert := False;
  If Not CreateSelfSignedCertificate Then
    Begin
      ErrorText := 'Could not create the monitor certificate.';
      Exit;
    End;
  If (Length(CertificateData.Certificate.Value) = 0) Or (Length(CertificateData.PrivateKey.Value) = 0) Or
    (CertificateData.Certificate.Value[0] <> $30) Or (CertificateData.PrivateKey.Value[0] <> $30) Then
    Begin
      ErrorText := 'Could not create the monitor certificate.';
      Exit;
    End;
  Result := True;
End;

Function EnsureMonitorHostCertificate(Out ErrorText: String): Boolean;
Var
  Directory, CertPath, KeyPath: String;
  Handler: TMonitorTlsHandler;
  CertificateDer, KeyDer: TBytes;
Begin
  Result := False;
  ErrorText := '';
  CertificateDer := Nil;
  KeyDer := Nil;
  Handler := Nil;
  If WorkflowSettingsDirectory = '' Then
    Begin
      ErrorText := 'Monitor certificate directory is not set.';
      Exit;
    End;
  If Not EnsureOpenSSLReady(ErrorText) Then
    Exit;
  If HostFilesReady(CertificateDer, KeyDer, ErrorText) Then
    Begin
      Result := ProtectOwnerOnlyFile(MonitorCertificateFile) And ProtectOwnerOnlyFile(MonitorKeyFile);
      If Not Result Then
        ErrorText := 'Could not protect the monitor certificate files.';
      Exit;
    End;
  If HostFilesPresent Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'Monitor certificate files are incomplete.';
      Exit;
    End;
  Directory := ExcludeTrailingPathDelimiter(ExtractFilePath(MonitorCertificateFile));
  If Not ForceDirectories(Directory) Then
    Begin
      ErrorText := 'Could not create the monitor certificate directory.';
      Exit;
    End;
  If Not ProtectOwnerOnlyDirectory(Directory) Then
    Begin
      ErrorText := 'Could not protect the monitor certificate directory.';
      Exit;
    End;
  CertPath := MonitorCertificateFile;
  KeyPath := MonitorKeyFile;
  Handler := TMonitorTlsHandler.Create;
  Try
    If Not Handler.MintHostMaterial(ErrorText) Then
      Exit;
    CertificateDer := CopyBytes(Handler.CertificateData.Certificate.Value);
    KeyDer := CopyBytes(Handler.CertificateData.PrivateKey.Value);
  Finally
    Handler.Free;
  End;
  If Not WriteProtectedDer(CertPath, CertificateDer, ErrorText) Then
    Exit;
  If Not WriteProtectedDer(KeyPath, KeyDer, ErrorText) Then
    Begin
      DeleteFile(CertPath);
      Exit;
    End;
  Result := True;
End;

Function MonitorHostFingerprint(Out Fingerprint, ErrorText: String): Boolean;
Var
  CertificateDer: TBytes;
Begin
  Fingerprint := '';
  CertificateDer := Nil;
  Result := False;
  If Not EnsureMonitorHostCertificate(ErrorText) Then
    Exit;
  If Not ReadDerFile(MonitorCertificateFile, CertificateDer, ErrorText) Then
    Exit;
  Fingerprint := FingerprintOf(CertificateDer);
  Result := Fingerprint <> '';
  If Not Result Then
    ErrorText := 'Could not fingerprint the monitor certificate.';
End;

Function LoadMonitorDerFile(Const Path: String; Out Data: TBytes; Out ErrorText: String): Boolean;
Begin
  Result := ReadDerFile(Path, Data, ErrorText);
End;

End.
