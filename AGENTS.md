# Apple On-Device OpenAI API - Information for Coding Agents

A macOS SwiftUI app that serves Apple's on-device Foundation Models through an OpenAI-compatible HTTP API. Fork of `gety-ai/apple-on-device-openai` (`upstream` remote); `origin` is `secondtruth/apple-on-device-openai`. User-facing behaviour, the supported parameters and the limits of tool calling are documented in `README.md` — keep it in step with the code.

It is a GUI app on purpose: Apple rate-limits Foundation Models for processes without UI.

## Requirements

macOS 27 and Xcode 27. The code uses macOS 27-only API (`GenerationOptions.toolCallingMode`, `transcriptErrorHandlingPolicy`, `LanguageModelSession.usage`, `LanguageModelError`); there is no macOS 26 fallback.

## Commands

Build artefacts stay out of the repository:

```bash
C=~/Entwicklung/Caches/apple-on-device-openai

# Unit tests (no app, no model needed)
cd OnDeviceServer && swift test --scratch-path $C/spm

# App
xcodebuild -project AppleOnDeviceOpenAI.xcodeproj -scheme AppleOnDeviceOpenAI -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath $C/DerivedData \
  -clonedSourcePackagesDirPath $C/SourcePackages build

# Run with the server started, then smoke-test it
open -n $C/DerivedData/Build/Products/Debug/AppleOnDeviceOpenAI.app --args -port 11535 -autoStart YES
python3 test_server.py        # needs: pip install openai requests
```

`xcodebuild` prints a `DVTCoreDeviceCore` plug-in error and a CoreSimulator version warning on this machine. Both are noise for macOS builds.

Launch the app with `open`, not by running the binary: the rate limit applies to processes that are not foreground GUI apps. Before relaunching, make sure the old instance is gone (`pgrep -f AppleOnDeviceOpenAI.app`); a second instance cannot bind the port, and requests silently keep hitting the old binary. A throttled instance ignores SIGTERM for minutes — use `pkill -9`.

## Layout

```
AppleOnDeviceOpenAI/       App target: window, settings, server lifecycle
  ServerViewModel.swift    Observable state; owns the OnDeviceServer actor
  ServerSettings.swift     UserDefaults-backed settings, which double as launch arguments
  Sections/, Components/   SwiftUI views
OnDeviceServer/            Local Swift package, Swift 6 language mode
  Sources/OnDeviceServer/
    OnDeviceServer.swift   Public facade: start/stop (actor)
    OpenAI/                Wire types; APIError is the OpenAI error envelope
    Generation/            Conversation (messages -> Transcript), ChatGeneration (the session),
                           ClientExecutedTool, JSONSchemaConverter, OnDeviceModel, error mapping
    HTTP/                  Routes, ChatCompletionsHandler, SSE writer, APIErrorMiddleware
  Tests/OnDeviceServerTests/
```

The Xcode project uses file-system-synchronized groups: new files under `AppleOnDeviceOpenAI/` need no project-file edit. The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and member-import visibility, so it must `import OnDeviceServer` in every file that touches the package's types, and it cannot use swift-log types — the package exposes its own `ServerConfiguration.LogLevel`.

## How a completion runs

1. `ChatCompletionsHandler` decodes the request and builds a `ChatGeneration`, whose initializer validates everything and throws `APIError` — before the model is involved.
2. `Conversation` turns the messages into a `Transcript` plus the final prompt. System and developer messages are joined into one leading instructions entry, which also carries the tool definitions.
3. `ChatGeneration.events()` runs one `LanguageModelSession` and yields text deltas, then one `Completion`. Streaming and non-streaming consume the same sequence.
4. For streaming, the handler awaits the first event before it sends the status line, so failures before the first token become HTTP errors rather than a 200 stream.

### Tool calling

Foundation Models executes tools inside a session turn; OpenAI clients execute them between two requests. `ClientExecutedTool.call` therefore throws `Handoff`. The session runs with `transcriptErrorHandlingPolicy = .preserveTranscript`, so the `.toolCalls` entry survives the failed turn and `ChatGeneration` reads the calls from `session.transcript`. The follow-up request is rebuilt as a transcript ending in `.toolOutput` entries and continued with an empty prompt, because the framework has no way to generate without one. The server is stateless.

These mechanics were established by probing the SDK, not from documentation: `GenerationSchema`'s `Codable` conformance only reads the framework's own dialect (it requires `x-order`), which is why `JSONSchemaConverter` goes through `DynamicGenerationSchema`. The executor-level API (`LanguageModelExecutorGenerationChannel`) would deliver raw tool-call events, but its `Event` type has no public accessors, so a consumer cannot read them.

## Conventions

- Code style follows the `code-craftsmanship` skill. Comments carry a *why*.
- Every client-visible error is an `APIError`; add new cases there, with an OpenAI `type` and a `code`.
- Do not approximate what the model cannot do. Reject with `unsupported_parameter` / `unsupported_schema`, and document the limit in `README.md`.
- Log lines never contain prompts or model output.
- Conventional commits, one logical change per commit.
