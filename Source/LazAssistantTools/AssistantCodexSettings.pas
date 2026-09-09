Unit AssistantCodexSettings;
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, AssistantCodexAccount;
Type
  TCodexConnectionFrame = Class(TFrame)
  Private

    Status: TLabel;
    SignIn, CheckButton: TButton;
    Timer: TTimer;
    Job: TAssistantCodexAccount;
    OpenedUrl, ModelsJson: String;
    Procedure ModelChanged(Sender: TObject);
    Procedure StartCheck(Sender: TObject);
    Procedure Tick(Sender: TObject);
  Public
    RuntimeEdit: TEdit;
    ModelCombo, EffortCombo, ApprovalCombo: TComboBox;
    Profile: String;
    Procedure LoadConnection(Const ProfileDir, Runtime, Model: String; Const Effort: String = ''; Const Approval: String = 'ask');
    Procedure LoadModels(Const Value: String);
    Function ReasoningEffort: String;
    Function ApprovalMode: String;
    Function Busy: Boolean;
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
  End;

{ Move a cancelled worker's join/destruction off the IDE thread. No IDE callbacks. }
Procedure ReapCodexWorker(Worker: TThread);
Implementation
{$R *.lfm}
Uses Dialogs, LCLIntf, fpjson, jsonparser, AssistantCodexHandshake, AssistantCodexProfile;
Type
  TWorkerReaper = Class(TThread)
    Worker: TThread;
    Procedure Execute; Override;
  End;
Procedure TWorkerReaper.Execute;
Begin Worker.WaitFor; Worker.Free; End;
Procedure ReapCodexWorker(Worker: TThread);
Var Reaper: TWorkerReaper;
Begin
  If Not Assigned(Worker) Then Exit;
  Reaper := TWorkerReaper.Create(True);
  Reaper.FreeOnTerminate := True;
  Reaper.Worker := Worker;
  Reaper.Start;
End;
Constructor TCodexConnectionFrame.Create(TheOwner: TComponent);
Var LabelControl: TLabel;
Begin
  Inherited Create(TheOwner);
  SetBounds(0, 0, 660, 310);
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self;
  LabelControl.SetBounds(16, 16, 620, 20); LabelControl.Caption := 'Codex executable (preview requires version 0.153.0)';
  RuntimeEdit := TEdit.Create(Self); RuntimeEdit.Parent := Self; RuntimeEdit.SetBounds(16, 42, 625, 28);
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self;
  LabelControl.SetBounds(16, 85, 600, 20); LabelControl.Caption := 'Model';
  ModelCombo := TComboBox.Create(Self); ModelCombo.Style := csDropDownList; ModelCombo.Parent := Self; ModelCombo.SetBounds(16, 110, 625, 28);
  ModelCombo.OnChange := @ModelChanged;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self;
  LabelControl.SetBounds(16, 150, 300, 20); LabelControl.Caption := 'Reasoning level';
  EffortCombo := TComboBox.Create(Self); EffortCombo.Parent := Self; EffortCombo.Style := csDropDownList;
  EffortCombo.SetBounds(16, 175, 300, 28); EffortCombo.Items.Add('Model default'); EffortCombo.ItemIndex := 0;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self;
  LabelControl.SetBounds(338, 150, 300, 20); LabelControl.Caption := 'Tool usage permissions';
  ApprovalCombo := TComboBox.Create(Self); ApprovalCombo.Parent := Self; ApprovalCombo.Style := csDropDownList;
  ApprovalCombo.SetBounds(338, 175, 303, 28);
  ApprovalCombo.Items.Add('Ask before file changes and builds');
  ApprovalCombo.Items.Add('Auto: allow project tools');
  ApprovalCombo.Items.Add('Always: allow registered tools'); ApprovalCombo.ItemIndex := 0;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self; LabelControl.AutoSize := False;
  LabelControl.SetBounds(16, 215, 625, 54); LabelControl.WordWrap := True;
  LabelControl.Caption := 'Refresh models to discover supported reasoning levels. Ask and Plan stay read-only. Auto and Always currently allow the same bounded Lazarus tools.';
  SignIn := TButton.Create(Self); SignIn.Parent := Self; SignIn.SetBounds(16, 285, 180, 32);
  SignIn.Caption := 'Sign in with ChatGPT'; SignIn.OnClick := @StartCheck;
  CheckButton := TButton.Create(Self); CheckButton.Parent := Self; CheckButton.SetBounds(210, 285, 180, 32);
  CheckButton.Caption := 'Check / refresh models'; CheckButton.OnClick := @StartCheck;
  Status := TLabel.Create(Self); Status.Parent := Self; Status.AutoSize := False;
  Status.SetBounds(16, 332, 625, 70); Status.WordWrap := True;
  Status.Caption := 'Uses ChatGPT subscription access. API-key billing is disabled.';
  Timer := TTimer.Create(Self); Timer.Interval := 100; Timer.Enabled := False; Timer.OnTimer := @Tick;
End;
Destructor TCodexConnectionFrame.Destroy;
Begin
  Timer.Enabled := False;
  If Assigned(Job) Then Begin Job.Cancel; ReapCodexWorker(Job); Job := Nil; End;
  Inherited Destroy;
End;
Procedure TCodexConnectionFrame.StartCheck(Sender: TObject);
Begin
  If Assigned(Job) Then Exit;
  If Not FileExists(RuntimeEdit.Text) Then
    Begin Status.Caption := 'Select the installed Codex executable first.'; Exit; End;
  Job := TAssistantCodexAccount.Create(RuntimeEdit.Text, Profile, Sender = SignIn);
  OpenedUrl := ''; SignIn.Enabled := False; CheckButton.Enabled := False;
  RuntimeEdit.Enabled := False;
  Status.Caption := 'Connecting to Codex…'; Job.Start; Timer.Enabled := True;
End;
Function TCodexConnectionFrame.ReasoningEffort: String;
Begin If EffortCombo.ItemIndex <= 0 Then Result := '' Else Result := EffortCombo.Text; End;
Function TCodexConnectionFrame.ApprovalMode: String;
Begin Case ApprovalCombo.ItemIndex Of 1: Result := 'auto'; 2: Result := 'always'; Else Result := 'ask'; End; End;
Procedure TCodexConnectionFrame.ModelChanged(Sender: TObject);
Var Data, Items, ModelData, Levels, Level: TJSONData; I, J: Integer; Previous, Value: String;
Begin
  Previous := ReasoningEffort;
  EffortCombo.Items.Clear; EffortCombo.Items.Add('Model default'); EffortCombo.ItemIndex := 0;
  If ModelsJson = '' Then Exit;
  Data := GetJSON(ModelsJson);
  Try
    Items := Data.FindPath('data'); If Not (Items Is TJSONArray) Then Exit;
    For I := 0 To Items.Count - 1 Do
      Begin
        ModelData := Items.Items[I]; If Not (ModelData Is TJSONObject) Then Continue;
        If TJSONObject(ModelData).Get('model', TJSONObject(ModelData).Get('id', '')) <> ModelCombo.Text Then Continue;
        Levels := ModelData.FindPath('supportedReasoningEfforts'); If Not (Levels Is TJSONArray) Then Exit;
        For J := 0 To Levels.Count - 1 Do
          Begin
            Level := Levels.Items[J]; If Not (Level Is TJSONObject) Then Continue;
            Value := TJSONObject(Level).Get('reasoningEffort', '');
            If (Value <> '') And (EffortCombo.Items.IndexOf(Value) < 0) Then EffortCombo.Items.Add(Value);
          End;
        EffortCombo.ItemIndex := EffortCombo.Items.IndexOf(Previous);
        If EffortCombo.ItemIndex < 0 Then EffortCombo.ItemIndex := 0;
        Exit;
      End;
  Finally Data.Free; End;
End;
Procedure TCodexConnectionFrame.LoadModels(Const Value: String);
Var Data, Items, Item: TJSONData; I: Integer; Previous, Id: String;
Begin
  Data := GetJSON(Value);
  Try
    Items := Data.FindPath('data');
    If Not (Items Is TJSONArray) Then Raise Exception.Create('Invalid model list');
    Previous := ModelCombo.Text; ModelCombo.Items.Clear;
    For I := 0 To Items.Count - 1 Do
      Begin
        Item := Items.Items[I]; If Not (Item Is TJSONObject) Then Continue;
        Id := TJSONObject(Item).Get('model', TJSONObject(Item).Get('id', ''));
        If Id <> '' Then ModelCombo.Items.Add(Id);
      End;
    ModelCombo.ItemIndex := ModelCombo.Items.IndexOf(Previous);
    If (ModelCombo.ItemIndex < 0) And (ModelCombo.Items.Count > 0) Then ModelCombo.ItemIndex := 0;
    ModelsJson := Value; ModelChanged(Nil);
  Finally Data.Free; End;
End;
Procedure TCodexConnectionFrame.Tick(Sender: TObject);
Var Value: TCodexAccountSnapshot;
Begin
  If Not Assigned(Job) Then Exit;
  Value := Job.Snapshot;
  If (Value.LoginUrl <> '') And (Value.LoginUrl <> OpenedUrl) Then
    Begin
      OpenedUrl := Value.LoginUrl;
      If Not OpenURL(OpenedUrl) Then
        Status.Caption := 'Could not open the sign-in browser. Check your default browser configuration.'
      Else Status.Caption := 'Complete ChatGPT sign-in in your browser…';
    End;
  If Not Value.Done Then Exit;
  Timer.Enabled := False; ReapCodexWorker(Job); Job := Nil;
  RuntimeEdit.Enabled := True; SignIn.Enabled := True; CheckButton.Enabled := True;
  If Value.ErrorText <> '' Then Begin Status.Caption := Value.ErrorText; Exit; End;
  If Value.State <> ccsSubscriptionAuthenticated Then
    Begin Status.Caption := 'ChatGPT sign-in is required for this assistant profile.'; Exit; End;
  Try LoadModels(Value.ModelsJson);
  Except Status.Caption := 'Signed in, but model discovery returned an invalid response.'; Exit; End;
  If ModelCombo.Items.Count > 0 Then Status.Caption := 'Signed in with ChatGPT. Available allowance is checked when you send a request.'
  Else Status.Caption := 'Signed in, but no available models were discovered.';
End;
Procedure TCodexConnectionFrame.LoadConnection(Const ProfileDir, Runtime, Model: String; Const Effort, Approval: String);
Begin
  If Assigned(Job) Then Begin Job.Cancel; ReapCodexWorker(Job); Job := Nil; End;
  Timer.Enabled := False; Profile := ProfileDir; ModelsJson := '';
  EffortCombo.Items.Clear; EffortCombo.Items.Add('Model default'); EffortCombo.ItemIndex := 0;
  If Effort <> '' Then Begin EffortCombo.Items.Add(Effort); EffortCombo.ItemIndex := 1; End;
  ApprovalCombo.ItemIndex := 0;
  If Approval = 'auto' Then ApprovalCombo.ItemIndex := 1 Else If Approval = 'always' Then ApprovalCombo.ItemIndex := 2;
  RuntimeEdit.Enabled := True; SignIn.Enabled := True; CheckButton.Enabled := True;
  RuntimeEdit.Text := Runtime;
  If RuntimeEdit.Text = '' Then RuntimeEdit.Text := FindCodexExecutable;
  ModelCombo.Items.Clear;
  If Model <> '' Then Begin ModelCombo.Items.Add(Model); ModelCombo.ItemIndex := 0; End;
  Status.Caption := 'Sign in or check this connection. Other connections stay signed in.';
End;
Function TCodexConnectionFrame.Busy: Boolean;
Begin Result := Assigned(Job); End;
End.
