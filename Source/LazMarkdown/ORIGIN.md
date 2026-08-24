# LazMarkdown (vendored)

Local copy of Lazarus `components/markdown` (lazmarkdown) for LazWorkflow.

- Upstream author: Michael Van Canneyt / Lazarus LCL + FPC FCL markdown
- License: Modified LGPL (LCL + Src_3_2)
- Copied from the local Lazarus tree on 2026-07-26 so Project Assistant does not depend on IDE package reinstall for markdown fixes.

## Local fixes (relative to stock Lazarus 4.x)

1. `markdown.canvasrender.pp` — table `GetCellTexts` ChildCount off-by-one; safer entity resolution; skip duplicate HTML entity keys; collapse paragraph space/tab runs; re-apply font Name+Size+Style together on Qt/GTK
2. `Src_3_2/markdown.inlinetext.pas` — bare `&` no longer AVs in `HandleEntityInner`
3. `Src_3_2/markdown.parser.pas` — skip duplicate HTML entity keys (`AElig`, `AMP`, …) so `TMarkDownControl` can construct without “item with key already exists”

Do not add this package to the IDE as a design-time replacement for `lazmarkdown` unless intended; LazAssistantTools links it as a required package for runtime `TMarkDownControl`.
