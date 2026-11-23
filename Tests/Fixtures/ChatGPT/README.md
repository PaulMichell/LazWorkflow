# ChatGPT offer snapshots

`inspect.txt`, `document.txt`, `plan.txt`, `build.txt` and `chat.txt` are the tool names a ChatGPT turn is offered and the developer text actually attached, for each conversation mode. `Tests/AssistantOfferSnapshotTest.lpr` compares them. A catalogue or prompt change fails until the file is updated on purpose.

The names are the Codex dynamic-tool names, after `CodexDynamicToolsFromCatalogue`. The fixture has no saved profile, so image output is off. OS, project root, active file and compiler lines are placeholders. OpenAI-compatible has no snapshot.
