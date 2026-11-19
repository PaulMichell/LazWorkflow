program VerifyFormBinding;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, ExtCtrls, BindingForm;
var
  Form: TBindingForm;
  Handler: TMethod;
begin
  Application.Initialize;
  Form := TBindingForm.Create(nil);
  try
    if (Form.Clock = nil) or (Form.Clock <> Form.FindComponent('Clock')) then
      raise Exception.Create('Streamed timer did not populate the form field');
    Handler := TMethod(Form.Clock.OnTimer);
    if (Handler.Code = nil) or (Handler.Code <> Form.MethodAddress('Tick')) or
      (Handler.Data <> Pointer(Form)) then raise Exception.Create('Incorrect event binding');
    Form.Clock.OnTimer(Form.Clock);
    WriteLn('Streamed timer and invoked TBindingForm.Tick');
  finally
    Form.Free;
  end;
end.
