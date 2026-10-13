Program AssistantAcceptanceTest;
{$mode objfpc}{$H+}
Uses SysUtils, AssistantAcceptance;
Const
  Build = '{"kind":"build","done":true,"stale":false,"outcome":"compile_passed","job_id":"build1","dependencies":{"sourceClosureComplete":true}}';
  Tests = '{"kind":"test","done":true,"stale":false,"outcome":"test_command_passed","testsRun":true,"job_id":"test1","build_job_id":"build1","testReport":{"format":"fpcunit-xml","valid":true,"passed":true,"minimumTests":2,"executed":2}}';
Var Reason: String;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name, ': ', Reason); Halt(1); End; WriteLn('ok ', Name); End;
Begin
  Check('missing criteria require human completion', Not CheckAssistantAcceptance('## Task', Build, Tests, Reason));
  Check('missing criteria are manual review and must not be repeated', AssistantAcceptanceIsHumanReview(Reason));
  Check('current build satisfies explicit build criterion', CheckAssistantAcceptance('Validation: build', Build, '', Reason));
  Check('current linked report satisfies tests criterion', CheckAssistantAcceptance('Validation: tests', Build, Tests, Reason));
  Check('build alone does not satisfy tests', Not CheckAssistantAcceptance('Validation: tests', Build, '', Reason));
  Check('unchecked acceptance items block completion', Not CheckAssistantAcceptance('Validation: build' + LineEnding + '- [ ] Inspect UI', Build, Tests, Reason));
  Check('unchecked items stop the plan agent', Not AssistantAcceptanceIsHumanReview(Reason));
  Check('example inside fenced block does not enable completion', Not CheckAssistantAcceptance('```' + LineEnding + 'Validation: build' + LineEnding + '```', Build, Tests, Reason));
  Check('shorter fence cannot end example', Not CheckAssistantAcceptance('````' + LineEnding + '```' + LineEnding + 'Validation: build', Build, Tests, Reason));
  Check('duplicate criteria rejected', Not CheckAssistantAcceptance('Validation: build' + LineEnding + 'Validation: tests', Build, Tests, Reason));
  Check('duplicate criteria stop the plan agent', Not AssistantAcceptanceIsHumanReview(Reason));
  Check('manual criteria require human completion', Not CheckAssistantAcceptance('Validation: manual', Build, Tests, Reason));
  Check('manual criteria are manual review and must not be repeated', AssistantAcceptanceIsHumanReview(Reason));
  Check('incomplete dependency coverage blocks completion', Not CheckAssistantAcceptance('Validation: build', StringReplace(Build, 'Complete":true', 'Complete":false', []), Tests, Reason));
  Check('stale build cannot complete', Not CheckAssistantAcceptance('Validation: build', StringReplace(Build, 'stale":false', 'stale":true', []), Tests, Reason));
  Check('running build cannot complete', Not CheckAssistantAcceptance('Validation: build', StringReplace(Build, 'done":true', 'done":false', []), Tests, Reason));
  Check('failed build cannot complete', Not CheckAssistantAcceptance('Validation: build', StringReplace(Build, 'compile_passed', 'compile_failed', []), Tests, Reason));
  Check('failed validation stops the plan agent', Not AssistantAcceptanceIsHumanReview(Reason));
  Check('unrelated tests cannot complete', Not CheckAssistantAcceptance('Validation: tests', Build, StringReplace(Tests, 'build1', 'build2', []), Reason));
  Check('stale tests cannot complete', Not CheckAssistantAcceptance('Validation: tests', Build, StringReplace(Tests, 'stale":false', 'stale":true', []), Reason));
  Check('insufficient executed tests cannot complete', Not CheckAssistantAcceptance('Validation: tests', Build, StringReplace(Tests, 'executed":2', 'executed":0', []), Reason));
  Check('exit-only tests cannot complete', Not CheckAssistantAcceptance('Validation: tests', Build, StringReplace(Tests, 'testReport', 'ignoredReport', []), Reason));
  Check('malformed evidence cannot complete', Not CheckAssistantAcceptance('Validation: build', '[]', Tests, Reason));
End.
