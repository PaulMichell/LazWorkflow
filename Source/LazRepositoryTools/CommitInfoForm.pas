Unit CommitInfoForm;

{ Commit information dialog for the History graph (c) 2026 Michell Computing.

  Date and time are the author timestamp. Committer rows appear only when that
  identity or that time differs. The History row date is the committer time.
  Fields are anchored on the form with a 4px border. The first edit on each row
  shares one left edge. The message memo fills the space above the button panel. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ButtonPanel,
  GitService;

Type
  TCommitInfoForm = Class(TForm)
    IdLabel: TLabel;
    IdEdit: TEdit;
    DateLabel: TLabel;
    DateEdit: TEdit;
    TimeLabel: TLabel;
    TimeEdit: TEdit;
    AuthorLabel: TLabel;
    AuthorEdit: TEdit;
    CommitterLabel: TLabel;
    CommitterEdit: TEdit;
    CommitterDateLabel: TLabel;
    CommitterDateEdit: TEdit;
    CommitterTimeLabel: TLabel;
    CommitterTimeEdit: TEdit;
    ParentsLabel: TLabel;
    ParentsMemo: TMemo;
    RefsLabel: TLabel;
    RefsMemo: TMemo;
    MessageLabel: TLabel;
    MessageMemo: TMemo;
    ButtonPanel: TButtonPanel;
    Procedure FormCreate(Sender: TObject);
    Procedure FormShow(Sender: TObject);
  Private
    Procedure FitFields;
  Public
    Procedure ApplyInfo(Const Info: TGitCommitAttributes);
  End;

Procedure ShowCommitInfo(Owner: TComponent; Const Info: TGitCommitAttributes);

Implementation

{$R *.lfm}

Uses
  DateUtils;

Const
  UnknownValue = '(unknown)';
  NoneValue = '(none)';
  NoMessage = '(no message)';
  FieldBorder = 4;

Function PersonText(Const PersonName, Email: String): String;
Begin
  Result := Trim(PersonName);
  If Trim(Email) <> '' Then
    Begin
      If Result <> '' Then
        Result := Result + ' <' + Trim(Email) + '>'
      Else
        Result := Trim(Email);
    End;
  If Result = '' Then
    Result := UnknownValue;
End;

Function DateText(UnixTime: Int64): String;
Begin
  If UnixTime <= 0 Then
    Result := UnknownValue
  Else
    Result := FormatDateTime('yyyy-mm-dd', UnixToDateTime(UnixTime));
End;

Function TimeText(UnixTime: Int64): String;
Begin
  If UnixTime <= 0 Then
    Result := UnknownValue
  Else
    Result := FormatDateTime('hh:nn:ss', UnixToDateTime(UnixTime));
End;

Function SplitDisplay(Const Value, Separator, EmptyText: String): String;
Var
  Rest, Token: String;
  At: Integer;
Begin
  Result := '';
  Rest := Value;
  While Rest <> '' Do
    Begin
      At := Pos(Separator, Rest);
      If At = 0 Then
        Begin
          Token := Trim(Rest);
          Rest := '';
        End
      Else
        Begin
          Token := Trim(Copy(Rest, 1, At - 1));
          Rest := Copy(Rest, At + Length(Separator), MaxInt);
        End;
      If Token = '' Then
        Continue;
      If Result <> '' Then
        Result := Result + LineEnding;
      Result := Result + Token;
    End;
  If Result = '' Then
    Result := EmptyText;
End;

Function DisplayMessage(Const Raw: String): String;
Begin
  Result := StringReplace(Raw, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  Result := TrimRight(Result);
  Result := StringReplace(Result, #10, LineEnding, [rfReplaceAll]);
  If Result = '' Then
    Result := NoMessage;
End;

Procedure ShowCommitInfo(Owner: TComponent; Const Info: TGitCommitAttributes);
Var
  Form: TCommitInfoForm;
Begin
  Form := TCommitInfoForm.Create(Owner);
  Try
    Form.ApplyInfo(Info);
    Form.ShowModal;
  Finally
    Form.Free;
  End;
End;

Procedure TCommitInfoForm.FormCreate(Sender: TObject);
Begin
  If Assigned(ButtonPanel) And Assigned(ButtonPanel.CloseButton) Then
    Begin
      ButtonPanel.CloseButton.Cancel := True;
      ButtonPanel.CloseButton.Default := True;
    End;
End;

Procedure TCommitInfoForm.FitFields;
Var
  Above: TControl;

  Procedure BindBelow(Control: TControl);
  Begin
    Control.AnchorSide[akTop].Control := Above;
    Control.AnchorSide[akTop].Side := asrBottom;
    Control.BorderSpacing.Top := FieldBorder;
    Above := Control;
  End;

Begin
  { Optional committer rows are hidden when they match the author. Point the next
    visible field at the last visible one so the anchor chain closes the gap. }
  DisableAlign;
  Try
    CommitterLabel.Visible := CommitterEdit.Visible;
    CommitterDateLabel.Visible := CommitterDateEdit.Visible;
    CommitterTimeLabel.Visible := CommitterDateEdit.Visible;
    CommitterTimeEdit.Visible := CommitterDateEdit.Visible;
    Above := AuthorEdit;
    If CommitterEdit.Visible Then
      BindBelow(CommitterEdit);
    If CommitterDateEdit.Visible Then
      BindBelow(CommitterDateEdit);
    BindBelow(ParentsMemo);
  Finally
    EnableAlign;
  End;
End;

Procedure TCommitInfoForm.ApplyInfo(Const Info: TGitCommitAttributes);
Begin
  If Info.Sha <> '' Then
    Begin
      Caption := 'Commit ' + Copy(Info.Sha, 1, 12);
      IdEdit.Text := Info.Sha;
    End
  Else
    Begin
      Caption := 'Commit';
      IdEdit.Text := UnknownValue;
    End;
  DateEdit.Text := DateText(Info.AuthorTime);
  TimeEdit.Text := TimeText(Info.AuthorTime);
  AuthorEdit.Text := PersonText(Info.AuthorName, Info.AuthorEmail);
  CommitterEdit.Text := PersonText(Info.CommitterName, Info.CommitterEmail);
  CommitterDateEdit.Text := DateText(Info.CommitterTime);
  CommitterTimeEdit.Text := TimeText(Info.CommitterTime);
  CommitterEdit.Visible := (Trim(Info.AuthorName) <> Trim(Info.CommitterName)) Or
    (Trim(Info.AuthorEmail) <> Trim(Info.CommitterEmail));
  CommitterDateEdit.Visible := Info.AuthorTime <> Info.CommitterTime;
  ParentsMemo.Text := SplitDisplay(Info.Parents, ' ', NoneValue);
  RefsMemo.Text := SplitDisplay(Info.Refs, ',', NoneValue);
  MessageMemo.Text := DisplayMessage(Info.Message);
  MessageMemo.SelStart := 0;
  FitFields;
End;

Procedure TCommitInfoForm.FormShow(Sender: TObject);
Begin
  FitFields;
  If IdEdit.CanFocus Then
    Begin
      IdEdit.SetFocus;
      IdEdit.SelectAll;
    End;
End;

End.
