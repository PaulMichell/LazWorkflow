Unit StatusFooterFrame;

{ Reusable status footer frame for chat and tool windows (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls;

Type
  TStatusFooterFrame = Class(TFrame)
    Panel: TPanel;
    LeftLabel: TLabel;
    CentreLabel: TLabel;
    RightLabel: TLabel;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Procedure SetLeftText(Const Value: String);
    Procedure SetCentreText(Const Value: String);
    Procedure SetRightText(Const Value: String);
    Procedure SetAll(Const NewLeftText, NewCentreText, NewRightText: String);
    Property LeftText: String Write SetLeftText;
    Property CentreText: String Write SetCentreText;
    Property RightText: String Write SetRightText;
  End;

Implementation

{$R *.lfm}

Constructor TStatusFooterFrame.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  Align := alBottom;
  Height := 22;
End;

Procedure TStatusFooterFrame.SetLeftText(Const Value: String);
Begin
  If Assigned(LeftLabel) Then
    LeftLabel.Caption := Value;
End;

Procedure TStatusFooterFrame.SetCentreText(Const Value: String);
Begin
  If Assigned(CentreLabel) Then
    CentreLabel.Caption := Value;
End;

Procedure TStatusFooterFrame.SetRightText(Const Value: String);
Begin
  If Assigned(RightLabel) Then
    RightLabel.Caption := Value;
End;

Procedure TStatusFooterFrame.SetAll(Const NewLeftText, NewCentreText, NewRightText: String);
Begin
  If Assigned(LeftLabel) Then
    LeftLabel.Caption := NewLeftText;
  If Assigned(CentreLabel) Then
    CentreLabel.Caption := NewCentreText;
  If Assigned(RightLabel) Then
    RightLabel.Caption := NewRightText;
End;

Initialization

RegisterClass(TStatusFooterFrame);

End.
