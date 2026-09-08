Unit AssistantCodexSettings;
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, AssistantCodexAccount;
Function ConfigureCodex(Const ProfileDir: String; Var Runtime, Model: String): Boolean;
{ Move a cancelled worker's join/destruction off the IDE thread. No IDE callbacks. }
Procedure ReapCodexWorker(Worker: TThread);
Implementation
Uses Dialogs, LCLIntf, fpjson, jsonparser, AssistantCodexHandshake, AssistantCodexProfile;
Type
  TWorkerReaper = Class(TThread)
    Worker: TThread;
    Procedure Execute; Override;
  End;
  TCodexSettingsForm = Class(TForm)
  Private
    RuntimeEdit: TEdit;
    ModelCombo: TComboBox;
    Status: TLabel;
    SignIn, CheckButton, UseButton: TButton;
    Timer: TTimer;
    Job: TAssistantCodexAccount;
    Profile, OpenedUrl: String;
    Procedure StartCheck(Sender: TObject);
    Procedure Tick(Sender: TObject);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
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
Constructor TCodexSettingsForm.Create(TheOwner: TComponent);
Var LabelControl: TLabel; CloseButton: TButton;
Begin
  Inherited CreateNew(TheOwner);
  Caption := 'ChatGPT connection'; Position := poScreenCenter;
  SetBounds(0, 0, 660, 310); BorderStyle := bsDialog;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self;
  LabelControl.SetBounds(16, 16, 620, 20); LabelControl.Caption := 'Codex executable (preview requires version 0.153.0)';
  RuntimeEdit := TEdit.Create(Self); RuntimeEdit.Parent := Self; RuntimeEdit.SetBounds(16, 42, 625, 28);
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self;
  LabelControl.SetBounds(16, 85, 600, 20); LabelControl.Caption := 'Model';
  ModelCombo := TComboBox.Create(Self); ModelCombo.Style := csDropDownList; ModelCombo.Parent := Self; ModelCombo.SetBounds(16, 110, 625, 28);
  SignIn := TButton.Create(Self); SignIn.Parent := Self; SignIn.SetBounds(16, 153, 180, 32);
  SignIn.Caption := 'Sign in with ChatGPT'; SignIn.OnClick := @StartCheck;
  CheckButton := TButton.Create(Self); CheckButton.Parent := Self; CheckButton.SetBounds(210, 153, 180, 32);
  CheckButton.Caption := 'Check / refresh models'; CheckButton.OnClick := @StartCheck;
  Status := TLabel.Create(Self); Status.Parent := Self; Status.AutoSize := False;
  Status.SetBounds(16, 198, 625, 54); Status.WordWrap := True;
  Status.Caption := 'Uses ChatGPT subscription access. API-key billing is disabled.';
  UseButton := TButton.Create(Self); UseButton.Parent := Self; UseButton.SetBounds(410, 263, 110, 32);
  UseButton.Caption := 'Use ChatGPT'; UseButton.ModalResult := mrOK; UseButton.Enabled := False;
  CloseButton := TButton.Create(Self); CloseButton.Parent := Self; CloseButton.SetBounds(530, 263, 110, 32);
  CloseButton.Caption := 'Cancel'; CloseButton.ModalResult := mrCancel;
  Timer := TTimer.Create(Self); Timer.Interval := 100; Timer.Enabled := False; Timer.OnTimer := @Tick;
End;
Destructor TCodexSettingsForm.Destroy;
Begin
  Timer.Enabled := False;
  If Assigned(Job) Then Begin Job.Cancel; ReapCodexWorker(Job); Job := Nil; End;
  Inherited Destroy;
End;
Procedure TCodexSettingsForm.StartCheck(Sender: TObject);
Begin
  If Assigned(Job) Then Exit;
  If Not FileExists(RuntimeEdit.Text) Then
    Begin Status.Caption := 'Select the installed Codex executable first.'; Exit; End;
  Job := TAssistantCodexAccount.Create(RuntimeEdit.Text, Profile, Sender = SignIn);
  OpenedUrl := ''; UseButton.Enabled := False; SignIn.Enabled := False; CheckButton.Enabled := False;
  RuntimeEdit.Enabled := False;
  Status.Caption := 'Connecting to Codex…'; Job.Start; Timer.Enabled := True;
End;
Procedure TCodexSettingsForm.Tick(Sender: TObject);
Var Value: TCodexAccountSnapshot; Data: TJSONData; Items: TJSONArray; I: Integer;
  PreviousModel, ModelId: String; Valid: Boolean;
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
  Timer.Enabled := False;
  ReapCodexWorker(Job); Job := Nil;
  RuntimeEdit.Enabled := True; SignIn.Enabled := True; CheckButton.Enabled := True;
  If Value.ErrorText <> '' Then Begin Status.Caption := Value.ErrorText; Exit; End;
  If Value.State <> ccsSubscriptionAuthenticated Then
    Begin Status.Caption := 'ChatGPT sign-in is required for this assistant profile.'; Exit; End;
  PreviousModel := ModelCombo.Text;
  Data := Nil; Valid := False;
  Try
    Data := GetJSON(Value.ModelsJson);
    Items := Data.FindPath('data') As TJSONArray;
    ModelCombo.Items.Clear;
    If Assigned(Items) Then
      For I := 0 To Items.Count-1 Do
        If Items[I] Is TJSONObject Then
          Begin
            ModelId := TJSONObject(Items[I]).Get('model', TJSONObject(Items[I]).Get('id', ''));
            If ModelId <> '' Then ModelCombo.Items.Add(ModelId);
          End;
    ModelCombo.ItemIndex := ModelCombo.Items.IndexOf(PreviousModel);
    If (ModelCombo.ItemIndex < 0) And (ModelCombo.Items.Count > 0) Then ModelCombo.ItemIndex := 0;
    Valid := ModelCombo.Items.Count > 0;
  Except
    Status.Caption := 'Signed in, but model discovery returned an invalid response.';
  End;
  Data.Free;
  UseButton.Enabled := Valid;
  If Valid Then Status.Caption := 'Signed in with ChatGPT. Available allowance is checked when you send a request.'
  Else Status.Caption := 'Signed in, but no available models were discovered.';
End;
Function ConfigureCodex(Const ProfileDir: String; Var Runtime, Model: String): Boolean;
Var Dialog: TCodexSettingsForm;
Begin
  Dialog := TCodexSettingsForm.Create(Nil);
  Try
    Dialog.Profile := ProfileDir;
    If Runtime = '' Then Runtime := FindCodexExecutable;
    Dialog.RuntimeEdit.Text := Runtime; Dialog.ModelCombo.Text := Model;
    Result := (Dialog.ShowModal = mrOK) And (Trim(Dialog.ModelCombo.Text) <> '');
    If Result Then Begin Runtime := Dialog.RuntimeEdit.Text; Model := Dialog.ModelCombo.Text; End;
  Finally Dialog.Free; End;
End;
End.
