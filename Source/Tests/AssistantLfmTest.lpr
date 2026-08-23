Program AssistantLfmTest;

{ Console checks for LFM quoting and component upsert (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  Classes, SysUtils, AssistantLfm;

Var
  FailCount: Integer;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Function RPos(Const Needle, Hay: String): Integer;
Var
  I: Integer;
Begin
  Result := 0;
  For I := Length(Hay) - Length(Needle) + 1 DownTo 1 Do
    If Copy(Hay, I, Length(Needle)) = Needle Then
      Begin
        Result := I;
        Exit;
      End;
End;

Procedure TestQuoteCaptionGo;
Var
  Lines, EventMethod: String;
Begin
  Check('caption json', BuildLfmPropertyLines('{"Caption":"Go","Align":"alClient"}', Lines, EventMethod));
  Check('caption quoted', Pos('Caption = ''Go''', Lines) > 0);
  Check('align unquoted', Pos('Align = alClient', Lines) > 0);
  Check('no bare Go', Pos('Caption = Go', Lines) < 1);
End;

Procedure TestEventUnquoted;
Var
  Lines, EventMethod: String;
Begin
  Check('event json', BuildLfmPropertyLines('{"OnClick":"Button1Click","Enabled":true}', Lines, EventMethod));
  Check('event method', EventMethod = 'Button1Click');
  Check('event unquoted', Pos('OnClick = Button1Click', Lines) > 0);
  Check('bool true', Pos('Enabled = True', Lines) > 0);
End;

Procedure TestIndentedUpsertDoesNotDuplicate;
Var
  Body, Original: String;
Begin
  Body :=
    'object Form1: TForm1' + LineEnding +
    '  Caption = ''Form1''' + LineEnding +
    '  object Button1: TButton' + LineEnding +
    '    Left = 8' + LineEnding +
    '    Caption = ''Old''' + LineEnding +
    '    object Nested: TPanel' + LineEnding +
    '      Caption = ''child''' + LineEnding +
    '    end' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
  Original := Body;
  Check('upsert found', UpsertLfmComponent(Body, 'Button1', 'TButton', '    Caption = ''Go''' + LineEnding));
  Check('caption updated', Pos('Caption = ''Go''', Body) > 0);
  Check('old caption gone', Pos('Caption = ''Old''', Body) < 1);
  Check('nested kept', Pos('object Nested: TPanel', Body) > 0);
  Check('child caption kept', Pos('Caption = ''child''', Body) > 0);
  Check('left kept', Pos('Left = 8', Body) > 0);
  Check('one button', (Pos('object Button1: TButton', Body) > 0) And
    (Pos('object Button1: TButton', Copy(Body, Pos('object Button1: TButton', Body) + 10, MaxInt)) < 1));
  Check('changed', Body <> Original);
End;

Procedure TestInsertNewComponent;
Var
  Body: String;
Begin
  Body :=
    'object Form1: TForm1' + LineEnding +
    '  Caption = ''Form1''' + LineEnding +
    'end' + LineEnding;
  Check('insert', UpsertLfmComponent(Body, 'ColorTimer', 'TTimer', '    Interval = 1000' + LineEnding + '    Enabled = True' + LineEnding));
  Check('timer object', Pos('object ColorTimer: TTimer', Body) > 0);
  Check('interval', Pos('Interval = 1000', Body) > 0);
  Check('before root end', Pos('object ColorTimer: TTimer', Body) < RPos('end', Body));
End;

Begin
  FailCount := 0;
  TestQuoteCaptionGo;
  TestEventUnquoted;
  TestIndentedUpsertDoesNotDuplicate;
  TestInsertNewComponent;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantLfm tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantLfm test(s) failed.');
      Halt(1);
    End;
End.
