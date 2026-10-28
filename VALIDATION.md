# Equal Agents 0.1 — validation

Validated on this Apple Silicon Mac on 2026-10-28. Windows has not been implemented or tested.

## Automated behavior checks

14 Node tests pass, including:

- Host only opens and reports; no source tools in opening, closing, or report phases.
- Proposals genuinely overlap and cannot see peer proposals.
- Discussion and final statements follow the configured order; history is complete beyond a recent-message window.
- Failed proposals block progression. Retry preserves completed turns and avoids duplicate public statements.
- Pause cancels concurrent work. Restart preserves state and never automatically replays paid calls.
- Skipped turns remain explicit in later context and reports.
- All search results are registered before delivery; proposal source visibility is enforced.
- Disabled sharing does not persist retrieved material into the shared library.
- Private network and metadata addresses are rejected by source fetching.
- Unlimited time/length settings persist and remain cancellable.
- Changing a paused model preserves completed-turn provenance.
- Delete hides discussions from the active list, preserves transcripts and evidence across restart, and restores without replaying model calls.
- Deleting a running discussion cancels active proposals, prevents racing starts/restores, and restores to a paused state.

## Real framework checks

- Installed Codex 0.163.0: model catalog retrieved successfully.
- Installed pi 0.87.1: model/provider catalog retrieved successfully.
- A real mixed meeting completed all 8 statements: pi / OpenCode Go / minimax-m3 as host and one participant; Codex / gpt-6-luna as another participant. One discussion round, independent proposals, individual closing statements, and host report all completed.
- Shared attachment delivered through both frameworks; four recorded source-read deliveries. No errors in that completed meeting.
- After adding explicit Codex MCP disabling and compaction detection, a separate real Codex response returned exactly `Equal Agents ready.`
- Live Bing RSS search returned 10 results. Fetching example.com encountered a TLS/network error in an earlier test; the app reported the failure, and did not invent page content.
- Error handling was also exercised with an OpenCode Go model returning `ModelDeprecated` and the configured Xiaomi channel returning `Invalid API Key`. These are provider/account availability failures, not silently substituted models. Catalog membership does not guarantee current account access.

## Native app and package

- SwiftUI debug and release builds succeeded using Xcode.
- Native launch connected to the bundled local engine. English navigation and controls were inspected in a separate preview, without replacing the user's open draft.
- Model-prefix suggestions were exercised by typing `gpt-6` and selecting `gpt-6.1-sol`.
- Final framework buttons were exercised: switching to pi revealed a separate provider field, `opencode` suggested `opencode-go`, and `minimax` suggested only matching models from that provider.
- A draft was created through the native UI with directly typed participant model IDs. The persisted record was read back and confirmed the exact host framework/provider/model and null time/length limits.
- No time limit / No length limit controls were inspected. Both are off by default (limits disabled).
- The real completed meeting and its shared attachment metadata were displayed in the native UI.
- The shared attachment was opened in the native reader; its full text and four passage-delivery receipts were verified.
- The app and bundled Node executable pass ad-hoc code-signature verification. Runtime dependency inspection shows only system frameworks/libraries.
- Node v24.19.0 license was taken from its official distribution archive after SHA-256 verification: `8294b7aa9b03997481c06babf1e8b270c859358f27da57a11509afe537ac381d`.

## Limits

Not notarized. Requires working local Codex / pi installations and provider access. No Windows app, built-in login flow, OCR, browser automation, script execution, or cloud sync. URL-based PDFs need importing through the native PDF reader. Search uses a public RSS endpoint and may be unavailable in some networks. Turn length is a model instruction, not enforced truncation. Large contexts pause instead of being silently shortened. The app can provide rebuttals and evidence to a model; it cannot guarantee the quality of the response.

### Searchable model picker (2026-10-28)
- Swift search tests: 3 passed (framework/provider scope, compact/token search and ranking, recent deduplication/order).
- Release build and strict bundle signature verification passed.
- Native preview UI verified: `gpt6` search, Down + Enter selection, pi provider selection, provider-scoped catalog, custom model ID, switching frameworks restores model/provider, and recently selected model appears first. No meeting/model generation was started for these checks.

### Private roles, initial materials, and reading controls (2026-10-29)
- 16 Node tests passed, including every-stage persona isolation (host included), initial file/link context with sharing disabled, persistence/export, and input limits.
- 3 Swift tests passed; release build and signature verification passed.
- Native preview verified multiline personality text entry, link addition/removal control, and wheel scrolling switches Following latest to Jump to latest. Initial-material file extraction uses PDFKit/UTF-8; no OCR.
- No live model generation was invoked in this iteration; stream updates remain gated by the same follow state tested through native scrolling.

### Layout regression correction (2026-10-29)
The previous top-alignment change was insufficient: the detail's intrinsic size expanded the split view beyond the window and clipped both the heading and sidebar. Reproduced in the preview app, including its empty draft state. A GeometryReader now bounds the detail to the actual viewport. Native screenshots verified the long heading, sidebar, completed transcript opening, and empty Sources tab remain visible below the toolbar. Opening a room defaults to the first statement with following disabled. This replaces the prior unverified layout claim; build/signature checks alone were not adequate visual acceptance.

### Multiline input scrollers (2026-10-29)
Replaced both SwiftUI TextEditors with a shared plain NSTextView/NSScrollView wrapper using overlay, autohiding vertical scrollers and no horizontal scroller. Native screenshots verified empty topic input has no reserved track, 14-line input scrolls with a narrow thumb, and multiline personality input has no track when its content fits. Release build/signature verification passed.
