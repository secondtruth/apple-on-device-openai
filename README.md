# Apple On-Device OpenAI API

A macOS app that serves Apple's on-device Foundation Models through an OpenAI-compatible HTTP API. Anything that speaks to OpenAI with a configurable base URL can use the local Apple Intelligence model instead: chat completions, streaming, tool calling and structured output.

This is a fork of [gety-ai/apple-on-device-openai](https://github.com/gety-ai/apple-on-device-openai), updated for macOS 27 and extended with tool calling, structured output and OpenAI-shaped errors.

## Requirements

- macOS 27 on a Mac with Apple silicon
- Apple Intelligence turned on in System Settings › Apple Intelligence & Siri
- Xcode 27 to build

macOS 27 is a hard requirement: tool calling relies on `GenerationOptions.toolCallingMode`, `transcriptErrorHandlingPolicy` and `LanguageModelSession.usage`, which the macOS 26 SDK does not have.

## Build and run

```bash
git clone https://github.com/secondtruth/apple-on-device-openai.git
cd apple-on-device-openai
open AppleOnDeviceOpenAI.xcodeproj
```

Build and run in Xcode, then click **Start Server**. The project signs to run locally, so no developer team is needed.

From the command line:

```bash
xcodebuild -project AppleOnDeviceOpenAI.xcodeproj -scheme AppleOnDeviceOpenAI \
  -configuration Release -derivedDataPath build build
open build/Build/Products/Release/AppleOnDeviceOpenAI.app
```

## Configuration

Bind address, port and "start the server when the app launches" are set in the window and kept between launches.

The same settings are launch arguments, because they are stored in `UserDefaults`. An argument overrides the stored value for that launch only:

```bash
open -a AppleOnDeviceOpenAI --args -port 11600 -autoStart YES -logLevel debug
```

| Key | Default | Meaning |
| --- | --- | --- |
| `host` | `127.0.0.1` | Address to bind. `0.0.0.0` listens on all interfaces. |
| `port` | `11535` | TCP port. |
| `autoStart` | `NO` | Start the server when the app launches. |
| `logLevel` | `info` | `trace`, `debug`, `info`, `notice`, `warning`, `error` or `critical`. |

Clients need three values:

| | |
| --- | --- |
| Base URL | `http://127.0.0.1:11535/v1` |
| Model | `apple-on-device` |
| API key | any value, unless you set one (below) |

### API key

Binding to anything but `127.0.0.1` makes the server reachable from the network. Set an API key in the window (**Generate** creates one) and every endpoint except `/health` requires it as `Authorization: Bearer <key>`, which is where OpenAI clients put their key. A missing or wrong key answers `401` in OpenAI's error envelope. With no key set, any client is accepted.

The key is stored in the login keychain, not with the other settings, and it is deliberately not a launch argument: those show up in `ps`. While the server runs, copy it from the **OpenAI API Integration** section.

Two limits:

- The server speaks plain HTTP, so the key crosses the network unencrypted. It keeps casual clients out; it does not protect against someone who can read the traffic. For that, put a TLS-terminating reverse proxy in front.
- A locally built app is signed ad hoc, and macOS ties keychain access to the code signature. After every rebuild it asks once for permission to read the key. Until that is answered the server does not start, rather than starting without the key. Builds signed with a development team do not ask again.

## Endpoints

| Endpoint | |
| --- | --- |
| `GET /health` | `200` while the server runs. |
| `GET /status` | State of the default model: availability, reason, supported languages, context window, server version. |
| `GET /v1/models` | The models, each with availability and capabilities. |
| `GET /v1/models/{id}` | One model. |
| `POST /v1/chat/completions` | Chat completions, streaming and non-streaming. |

### Models

| Model id | |
| --- | --- |
| `apple-on-device` | The general-purpose system model. Used when a request names no model. |
| `apple-on-device-content-tagging` | The system model adapted for tagging and extraction. |

`/v1/models` always lists both and says whether each can be used right now. The fields beyond OpenAI's are `available`, `unavailable_reason`, `context_window` and `capabilities`:

```json
{
  "id": "apple-on-device",
  "object": "model",
  "created": 1757894400,
  "owned_by": "apple",
  "available": false,
  "unavailable_reason": "model_downloading",
  "context_window": 8192,
  "capabilities": ["tool_calling", "structured_output", "vision"]
}
```

`unavailable_reason` is one of `apple_intelligence_disabled`, `model_downloading`, `device_not_eligible` or `model_unavailable`. A completion request against an unavailable model answers `503` with the same code and a message that says what to do. The server starts regardless, so a client sees that message rather than a refused connection, and requests succeed by themselves once a download finishes.

## Chat completions

```bash
curl http://127.0.0.1:11535/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-on-device",
    "messages": [{"role": "user", "content": "Hello, how are you?"}]
  }'
```

| Parameter | Support |
| --- | --- |
| `model` | One of the ids above. Unknown ids are rejected with `404 model_not_found`. |
| `messages` | Roles `system`, `developer`, `user`, `assistant`, `tool`. Text content only, as a string or as `text` parts. |
| `stream`, `stream_options.include_usage` | Supported. |
| `temperature` | `0`–`2`. `0` selects greedy sampling. |
| `top_p`, `seed` | Mapped to nucleus sampling. The same seed repeats the same output for an identical request; expect that to break across OS updates, which replace the model. |
| `max_tokens`, `max_completion_tokens` | Mapped. `finish_reason` is `length` when the limit was reached. |
| `tools`, `tool_choice`, `parallel_tool_calls` | Supported; see below. |
| `response_format` | `text` and `json_schema`; see below. |
| `n` > 1, `stop` | Rejected with `400 unsupported_parameter`. The model cannot honour them, and ignoring them would change what the client gets without telling it. |
| `presence_penalty`, `frequency_penalty`, `logit_bias`, `user` | Accepted and ignored. |

System and developer messages from anywhere in the list are joined into the single instructions entry the model reads. The last message must come from the `user` or a `tool`; a prefilled assistant message cannot be continued. Image parts are rejected rather than dropped.

Responses carry real token counts in `usage`.

### Tool calling

`tools` and `tool_choice` work as in the OpenAI API, in both response modes. The model returns `tool_calls` with `finish_reason: "tool_calls"`, the client runs the tools, appends the assistant message and one `tool` message per call, and sends the conversation back:

```python
first = client.chat.completions.create(model="apple-on-device", messages=messages, tools=tools)
messages.append(first.choices[0].message)
for call in first.choices[0].message.tool_calls:
    messages.append({"role": "tool", "tool_call_id": call.id, "content": run(call)})
final = client.chat.completions.create(model="apple-on-device", messages=messages, tools=tools)
```

The server keeps no state between the two requests.

| `tool_choice` | Behaviour |
| --- | --- |
| `auto` or absent | The model decides. |
| `none` | Tool calling is disallowed for this turn. |
| `required` | The model must call a tool. |
| `{"type": "function", "function": {"name": …}}` | Only that tool is offered, and a call is required. |

What differs from OpenAI:

- **Tool calls are not streamed in fragments.** The framework exposes a call only once it is complete, so a streaming response carries each call whole, in one chunk.
- **`parallel_tool_calls: false` returns the first call only.** The model cannot be told to emit a single call; it decides on the next one when it sees the first result.
- **The continuation is an empty turn.** Foundation Models only generates in answer to a prompt, so a request that ends in tool results is continued with an empty prompt. The model answers from the tool output; nothing is added to what it reads.
- **Small model, small context.** The context window is 8192 tokens, and tool definitions count against it. A handful of tools with short descriptions works well; large tool catalogues do not fit. With `tool_choice: "required"` the model calls a tool even when none applies and invents arguments.

#### Parameter schemas

Foundation Models constrains the model's output to a schema while decoding, so arguments always match the shape you declare. The JSON Schema in `parameters` is converted into the framework's schema type, which covers a subset:

| | |
| --- | --- |
| Supported | `object` with `properties` and `required`, `array` with `items`, `minItems`, `maxItems`, `string`, `integer`, `number`, `boolean`, `null`, string `enum`, string `const`, `pattern`, `minimum`, `maximum`, `anyOf`, `oneOf` (treated as `anyOf`), nullable types (`["string", "null"]`), `$ref` into `$defs` or `definitions`. |
| Passed on as a hint | `format`, `minLength`, `maxLength`, `multipleOf`, `exclusiveMinimum`, `exclusiveMaximum`, `uniqueItems`, `default`. They cannot be enforced, so they are appended to the property's description, where the model still reads them. |
| Rejected | `allOf`, `not`, `if`/`then`/`else`, `patternProperties`, `propertyNames`, `prefixItems`, `contains`, `dependentSchemas`, `dependentRequired`, `unevaluatedProperties`, free-form maps (`additionalProperties` with a schema), non-string enums and constants, values without a `type`, arrays without `items`, external `$ref`. |

A rejected schema answers `400 unsupported_schema` with the JSON path of the keyword, for example `Unsupported JSON Schema at $.properties.meta.additionalProperties`. Properties are presented to the model with the required ones first, then alphabetically.

### Structured output

`response_format` of type `json_schema` constrains the answer to a schema, with the same subset as above:

```json
"response_format": {
  "type": "json_schema",
  "json_schema": {
    "name": "person",
    "schema": {
      "type": "object",
      "properties": {"name": {"type": "string"}, "age": {"type": "integer"}},
      "required": ["name", "age"]
    }
  }
}
```

In streaming mode the document arrives as one content chunk: partially generated structured output is not valid JSON. `json_object` is rejected, because the framework can only constrain output to a schema.

### Errors

Errors use OpenAI's envelope and matching HTTP statuses, so client libraries raise their usual exceptions:

```json
{"error": {"message": "…", "type": "invalid_request_error", "param": "messages", "code": "context_length_exceeded"}}
```

| Status | `code` | |
| --- | --- | --- |
| 400 | — | Malformed request; `param` names the field, e.g. `messages[1].role`. |
| 400 | `unsupported_parameter`, `unsupported_schema`, `unsupported_content_type` | The model cannot do what was asked. |
| 400 | `context_length_exceeded` | The conversation does not fit the context window; the message states both token counts. |
| 400 | `content_policy_violation` | Blocked by the model's guardrails, or refused. |
| 401 | `invalid_api_key`, or none when the key is missing | An API key is set and the request does not carry it. |
| 404 | `model_not_found`, `unknown_url` | |
| 429 | `rate_limit_exceeded` | With `Retry-After` when the system reports a reset time. |
| 503 | `apple_intelligence_disabled`, `model_downloading`, `device_not_eligible` | The model is unavailable. |

In a stream, failures that occur before the first token still answer with an HTTP error. A failure after that arrives as a `data: {"error": …}` event.

When a streaming client disconnects, the generation is cancelled. A non-streaming request runs to the end: Vapor does not report the disconnect to the handler.

## Logging

One line per completion, with model, token counts, finish reason and duration; never prompts or output. Logs go to stderr and to the unified log:

```bash
log stream --info --predicate 'subsystem == "apple-on-device-openai"'
```

## Why a GUI app

Apple rate-limits Foundation Models for processes without a user interface: according to an Apple DTS engineer, an app with UI running in the foreground is not rate limited, while a command-line tool is ([forum thread](https://developer.apple.com/forums/thread/787737)). That is why this is an app and not a daemon.

### Running in the background

macOS naps a GUI app nobody is using. Without countermeasures, after a few idle minutes in the background the app's threads fall to the scheduler's lowest priority and the server stalls: in a side-by-side test after eleven idle minutes, a one-word completion timed out at 90 s and `/health` stopped answering.

The server therefore holds an activity assertion while it runs, which exempts the app from App Nap. In the same test it answered in 0.6 s. The window does not have to be in front.

The assertion does not keep the Mac awake. When the Mac sleeps, the server is unreachable; to serve around the clock, prevent system sleep in System Settings or with `caffeinate -s`.

If Apple's rate limit applies anyway, requests answer `429 rate_limit_exceeded`. Going by Apple's statement above, the limit does not apply while the app is in the foreground; it was not hit while testing this server.

### One generation at a time

The on-device model runs one generation at a time. Concurrent requests are accepted and queue behind each other: a one-word completion sent while a 1500-token essay was generating waited 33 s for it. Cancelling matters for the same reason — when a streaming client disconnects, the generation stops and the next request starts immediately.

## Development

```
AppleOnDeviceOpenAI/     The app: window, settings, server lifecycle
OnDeviceServer/          Swift package: everything reachable over HTTP
  Sources/OnDeviceServer/
    OpenAI/              Wire types of the OpenAI API
    Generation/          Transcript building, tools, schema conversion, the session
    HTTP/                Routes, handlers, SSE, error middleware
  Tests/
```

The package has unit tests that need neither the app nor the model:

```bash
cd OnDeviceServer
swift test
```

`test_server.py` is a smoke test against a running server, using the official OpenAI Python SDK:

```bash
pip install openai requests
python3 test_server.py
```

## License

Upstream's README states the MIT License; neither repository contains a license file.

## References

- [Apple Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels)
- [OpenAI API reference](https://platform.openai.com/docs/api-reference)
