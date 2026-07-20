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
  Private
    FPanel: TPanel;
    FLeftLabel: TLabel;
    FCentreLabel: TLabel;
    FRightLabel: TLabel;
    Procedure CreateControls;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
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
  CreateControls;
End;

Destructor TStatusFooterFrame.Destroy;
Begin
  { Controls are owned by Self. }
  Inherited Destroy;
End;

Procedure TStatusFooterFrame.CreateControls;
Begin
  FPanel := TPanel.Create(Self);
  With FPanel Do
    Begin
      Parent := Self;
      Align := alClient;
      BevelOuter := bvNone;
      BorderSpacing.Around := 0;
      Color := clForm;
    End;

  FLeftLabel := TLabel.Create(Self);
  With FLeftLabel Do
    Begin
      Parent := FPanel;
      Align := alLeft;
      AutoSize := True;
      BorderSpacing.Left := 6;
      BorderSpacing.Right := 12;
      Caption := '';
      Layout := tlCenter;
    End;

  FRightLabel := TLabel.Create(Self);
  With FRightLabel Do
    Begin
      Parent := FPanel;
      Align := alRight;
      AutoSize := True;
      BorderSpacing.Right := 6;
      BorderSpacing.Left := 12;
      Caption := '';
      Layout := tlCenter;
    End;

  FCentreLabel := TLabel.Create(Self);
  With FCentreLabel Do
    Begin
      Parent := FPanel;
      Align := alClient;
      Alignment := taCenter;
      Layout := tlCenter;
      Caption := '';
    End;
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

End.
