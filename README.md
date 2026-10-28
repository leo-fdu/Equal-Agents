# Equal Agents

A native SwiftUI app for multi-agent discussions, powered by Codex and pi. One host guides the meeting, while independent participants propose ideas, debate them, and summarize their conclusions.

Requires macOS 14 or later. The current app build targets Apple Silicon. The interface is in English; agents respond in the language of your discussion topic.

## Getting started

1. Open `Equal Agents.app`. Packaged builds include Node.js, so no separate Node installation is needed to run the app's backend.
2. Install and authenticate Codex or pi on your Mac. Equal Agents uses each framework's existing authentication and provider configuration; it does not store credentials itself.
3. Create a discussion with a topic, one host, and 2–8 participants. Optionally add files, links, and a private personality or role prompt for each participant.
4. Choose 1–12 discussion rounds for stage 2 and whether to enable shared sources. Time and response-length limits are optional and disabled by default. Model context and service limits still apply.
5. Start the meeting. If a turn fails, the meeting pauses. Resume retries unfinished turns without repeating completed statements. Failed participant turns can be explicitly skipped; host turns cannot.
6. Export the full transcript or final report as Markdown.

Use **Participants** to change models for future turns in a draft or paused meeting. Completed statements retain their original model details.

To delete a discussion, right-click it and choose **Delete discussion**, or use the toolbar's trash button. Running agents are stopped, and the discussion moves to **Recently Deleted**. Transcripts and shared sources remain recoverable; they are not automatically purged.

## Choosing models

Choose **Codex** or **pi** first. For pi, select a provider separately. Click the model field to open a searchable picker, then type a name or model ID to filter suggestions, including compact queries such as `gpt6`.

- Use the arrow keys to navigate, Enter to select, and Escape to close.
- Enter an exact model ID to use a model absent from the catalog.
- Recent selections are saved locally and scoped to their framework and provider.
- Switching frameworks or providers within the same editor preserves each configuration's model and reasoning effort.

Catalog entries do not guarantee that a model is currently accessible through your account. Connection failures are reported rather than silently substituting a different model.

## Meeting protocol

| Stage | Behavior |
| --- | --- |
| Opening | The host introduces the topic and agenda without proposing an answer. No tools. |
| Proposals | Participants work in parallel and speak once each. Peer proposals and newly gathered peer sources are hidden. |
| Discussion | Participants speak sequentially in seat order for the configured number of rounds. Each receives all completed earlier statements, including earlier turns in the current round. |
| Closing | Each participant gives one final statement in seat order, addressing remaining challenges. No further research or new attacks. |
| Report | The host summarizes the complete transcript, including consensus and unresolved disagreement. No tools. |

The host does not join the participant stages. Missing or skipped statements must not be interpreted as agreement.

For `N` participants and `R` discussion rounds, the meeting schedules `2 + N × (R + 2)` public statements. Tool calls do not count as public statements; framework-internal model calls may exceed this number.

A turn can make up to 24 source-tool calls, each subject to network and size limits. If the full prompt exceeds 220,000 characters, the meeting pauses instead of silently truncating history. This guard is not a precise estimate of every model's context capacity; model-specific limits may also cause a pause.

The scheduler controls turn order and context visibility. The quality of reasoning, responses to criticism, and interpretation of evidence still depends on model output. Personality prompts do not override the meeting protocol.

## Initial materials and private personalities

When creating a discussion, attach PDFs, UTF-8 text files, or HTTP/HTTPS links. Extracted file text and link references are included in the initial materials for the host and all participants, even when shared sources are disabled.

Initial materials are limited to 20 items and 100,000 characters in total. Larger files can be added to shared sources after creating the meeting and before starting it. PDF text extraction uses PDFKit; scanned PDFs requiring OCR are not supported.

A supplied link is a reference, not already-read webpage content. Participants are instructed to retrieve relevant links during their research stages.

Personality and role prompts use multiline editors with automatic wrapping and overlay scrollbars. Only the participant's own prompt is included in its model context. Other participant entries contain only IDs and names; the host does not receive private personality prompts either. Public statements still become part of the subsequent discussion history.

## Shared sources

When enabled, all returned search results and retrieved text are archived before delivery to the model. During proposals, each participant can access user-provided sources and its own newly collected sources. During discussion, all archived sources become available.

Source records preserve provenance, snippet versus full-content type, discoverers, and content hashes. Read receipts record delivered passages, not proof that a model understood them.

Search uses Bing's public RSS search endpoint. Availability and result quality depend on the service and network; failures are reported explicitly. The retrieval tools are not a full browser and cannot handle login pages, CAPTCHAs, or content that requires JavaScript rendering. Linked PDFs currently need to be downloaded and imported manually.

When shared sources are disabled, retrieved materials remain in the current turn's temporary memory and are not written to the shared library. References included in public statements remain in the transcript.

## Reading discussions

Opening a discussion starts at its first statement. Click **Jump to latest** to move to the newest statement and enable automatic following. Scrolling manually or dragging the scrollbar pauses following so streaming output does not pull you away from what you are reading.

## Local data and tools

Agents have no individual workspaces and no shell or script-execution tools. The internal `runtime` directory is used to launch frameworks and is not exposed to models.

Meeting data is stored by default in:

```text
~/Library/Application Support/Equal Agents
```

Each meeting uses an atomic JSON snapshot. Discussions and attachments are not written to a Research OS database. Model requests and searches access the corresponding network services.

## Building and testing

Building requires Xcode with Swift 5.9 or later and a standalone Node.js 22+ runtime.

```sh
# Backend tests
node --test tests/*.test.mjs

# Swift tests
swift test

# Build and ad-hoc sign the macOS app
./build_app.sh
```

By default, the build script uses Node from the Codex desktop runtime. Set `EQUAL_AGENTS_BUNDLE_NODE` to use another standalone Node binary. The script bundles Node and `Resources/Node-LICENSE.txt` into the app; if changing the Node distribution, supply its corresponding license file.

The default app output is `../Equal Agents.app`. Set `EQUAL_AGENTS_APP_OUTPUT` to change it, or `EQUAL_AGENTS_BUILD_ROOT` to change the build/cache directory.

Runtime overrides:

| Variable | Purpose |
| --- | --- |
| `EQUAL_AGENTS_CODEX` | Codex CLI path |
| `EQUAL_AGENTS_PI` | pi CLI path |
| `EQUAL_AGENTS_DATA` | Alternative or isolated data directory |
| `EQUAL_AGENTS_ENGINE` | Backend entry point for development |
| `EQUAL_AGENTS_NODE` | Backend Node executable for development |

## Source layout

| Path | Purpose |
| --- | --- |
| `Sources/EqualAgents/` | Native macOS interface |
| `engine/core.mjs` | Scheduling, context construction, and persistence |
| `engine/runtime.mjs` | Codex app-server and pi RPC integration |
| `engine/sources.mjs` | Source search, retrieval, and archiving |
| `engine/server.mjs` | UI communication and tool bridge |
| `tests/` | Backend and Swift tests |

The backend uses standard ECMAScript modules without third-party npm dependencies and can be reused by a future Windows interface.

## Current limitations

Builds are locally ad-hoc signed and are not notarized. Framework compatibility depends on the installed Codex and pi versions.

This version does not include a Windows interface, cloud sync, an account sign-in interface, automatic updates, OCR, script execution, or a research project system. See [VALIDATION.md](VALIDATION.md) for verification notes and known boundaries.

## License

[MIT](LICENSE). The bundled Node.js runtime has separate third-party notices in [Resources/Node-LICENSE.txt](Resources/Node-LICENSE.txt).
