# Codex image generation qualification

On 2026-11-24 the installed Windows desktop CLI reported `0.167.0-alpha.3.2`. Its feature list reported `image_generation` stable and enabled. Its generated v2 ItemCompletedNotification schema includes an `imageGeneration` item with inline `result` or attachment-store `fileId` and optional absolute `savedPath`. AssistantCodexQualification checks local image input and tool-returned input images under ccImages. Neither check exercises native generation.

An IDE-brokered stdio client launched the server with AssistantCodexHandshake’s subscription flags and the IDE-managed profile. Account discovery returned `chatgpt`. The ephemeral thread used the OpenAI provider, Lazarus permissions and no dynamic tools. Two independent requests to draw a blue circle returned PNG bytes.

| Event | Thread | Turn | Item | Observation |
| --- | --- | --- | --- | --- |
| turn/started | H1 | T1 | | Generation requested |
| item/started | H1 | T1 | I1 | imageGeneration, in_progress |
| item/completed | H1 | T1 | I1 | imageGeneration, completed |
| turn/completed | H1 | T1 | | completed |
| turn/started | H1 | T2 | | Immediately sent turn/interrupt with threadId H1 and turnId T2 |
| turn/completed | H1 | T2 | | interrupted, no completed image observed |

The identifiers above are aliases from the second run. The image notifications matched the active threadId and turnId and shared the same item.id. The completed item carried type, id, status, revisedPrompt, result, transparentBackground, failure, savedPath, generationId, startedAtMs and completedAtMs. Base64 decoding result yielded 968,373 bytes with the PNG signature. The broker process read identical bytes from savedPath. Retrieval by fileId and interruption after an image item starts remain untested.

The captured completion line measured 1,292,138 bytes before the newline. The production transport now accepts inbound frames up to its 4 MiB queue budget. In a repeat signed-in turn, `AssistantCodexProbe --auto <IDE-managed-profile> --image` used the production client to receive the completed item and open its `savedPath`. The artifact measured 1,007,867 bytes and had the eight-byte PNG signature. The probe reports the size without logging the path or image payload.

## Win64 IDE verification

The qualified configuration uses Codex `0.167.0-alpha.3.2`, a signed-in ChatGPT account in the IDE-managed profile, and image output enabled for that connection. Start the request from a parent turn in Plan, Document or Build.

All five Win64 packages compiled with zero errors and warnings. The nested verification folder contained one file, `Temporary/SignedInIDE32/kingfisher.png` (2,151,859 bytes). The IDE image reader decoded it at 1254 × 1254. Requesting that same destination with overwrite disabled returned “File already exists” before generation. Its SHA-256 digest matched before and after the refusal.

The connection and writer regressions passed with image output disabled. Interactive checks still awaiting confirmation include the original generation count, opening the separate viewer, the generated attachment count after reopening the conversation, the phone preview if connected, a turn with image output disabled, and declining the IDE overwrite prompt.
