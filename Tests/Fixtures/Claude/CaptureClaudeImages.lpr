Program CaptureClaudeImages;

{ Captures how Claude Code takes images (c) 2026 Michell Computing.

  Sends a synthetic PNG as a stream-json image block, resumes that session with text only, and offers the picture as
  an MCP tool result, then probes stdin closing and the size and format limits. Runs on the signed-in Claude
  subscription; never reads Claude sign-in files and never passes --bare, --max-budget-usd or --betas. Build and run
  from the repository root, as Tests/Fixtures/Claude/README.md shows:
    fpc -MObjFPC -FUTemporary/ClaudeCapture -FETemporary/ClaudeCapture -FuTests -FuSource/LazAssistantTools
      -FuSource/LazWorkflowCommon -Fu<Lazarus>/components/lazutils/lib/<cpu-os> Tests/Fixtures/Claude/CaptureClaudeImages.lpr
    Temporary/ClaudeCapture/CaptureClaudeImages --output-dir Temporary/ClaudeCapture/Run
  The work is in Tests/ClaudeCaptureProgram.pas and Tests/ClaudeCaptureSupport.pas, which ClaudeCaptureTest builds. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  ClaudeCaptureProgram;

Begin
  ExitCode := RunCaptureProgram;
End.
