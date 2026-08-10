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
  Published
    { Must be published for inline streaming in host forms (ObjFPC defaults to public). }
    FPanel: TPanel;
    FLeftLabel: TLabel;
    FCentreLabel: TLabel;
    FRightLabel: TLabel;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Procedure SetLeftText(Const Value: String);
    Procedure SetCentreText(Const Value: String);
    Procedure SetRightText(Const Value: String);
    Procedure SetAll(Const LeftText, CentreText, RightText: String);
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
  FLeftLabel.Caption := Value;
End;

Procedure TStatusFooterFrame.SetCentreText(Const Value: String);
Begin
  FCentreLabel.Caption := Value;
End;

Procedure TStatusFooterFrame.SetRightText(Const Value: String);
Begin
  FRightLabel.Caption := Value;
End;

Procedure TStatusFooterFrame.SetAll(Const LeftText, CentreText, RightText: String);
Begin
  FLeftLabel.Caption := LeftText;
  FCentreLabel.Caption := CentreText;
  FRightLabel.Caption := RightText;
End;

Initialization

RegisterClass(TStatusFooterFrame);

End.
