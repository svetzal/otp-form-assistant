# OTP form assistant

A form assistant for Phoenix LiveView. People can type or speak, review
suggested changes, undo edits, and save through the host application's rules.

The Hex package and OTP application are `otp_form_assistant`. Elixir modules
use the `FormAssistant` namespace.

## Documentation

[Read the published documentation](https://vetzal.ca/otp-form-assistant/).

- [Functional guide](guides/functional.md): behavior, draft lifecycle, and limits.
- [Integration guide](guides/integration.md): host contracts and LiveView wiring.
- [Deployment guide](guides/deployment.md): releases, operation, and recovery.

GitHub Actions publishes the guides and API reference after the checks pass
on `main`. Run `mix docs --warnings-as-errors` to build them locally.

## Scope

The package owns form descriptions, drafts, history, review, assistant tools,
LiveView components, and optional voice sessions. The host owns authorization,
persistence, model requests, credentials, and voice connections.

No process starts automatically. Text-only hosts need no supervisor child.
This first extraction keeps the existing behavior of the phone assistant.
It does not migrate or deploy the original application.

## Requirements

- Elixir 1.20 and Erlang/OTP 29.
- Phoenix LiveView 1.2 and Armature 0.4.
- A host function that sends Responses API request maps.
- For voice, a host implementation of `FormAssistant.Voice.Transport`.

Voice uses GPT-Live message shapes copied from the original implementation.
See `FormAssistant.Voice.Protocol` for verified shapes and remaining assumptions.
The package does not provide a network client or guarantee provider access.

## Installation

After the maintainers publish a version to Hex, add its dependency:

```elixir
{:otp_form_assistant, "~> 0.1.0"}
```

For a local trial before publication, use a checkout:

```elixir
{:otp_form_assistant, path: "../otp-form-assistant"}
```

Use released Hex versions in committed consumer dependencies. A path override
is for local development only.

Run `mix deps.get`.

## Describe the form

Implement `FormAssistant.Form` in the host application:

- `fields/0` returns `FormAssistant.Field` structs, including dependencies.
- `load/1` reads saved values for the supplied scope.
- `validate/1` checks and normalizes the complete map of values.
- `save/3` checks authorization and saves the values. The third argument
  lists changed field IDs.
- `context/1` describes the form to the assistant.
- Optional `review/1` returns domain-specific findings.

Field IDs are strings. Scope is opaque to this package. Enforce authorization
inside `load/1` and `save/3`, even when the page also checks it.

## Configure the assistant

Build one configuration for the current user and form:

```elixir
config = %FormAssistant.Config{
  form: MyApp.SettingsForm,
  scope: scope,
  respond: &MyApp.ModelClient.respond/1,
  record: &MyApp.Conversations.record_event(conversation, &1),
  text_model: model
}
```

`respond` receives a request map and returns `{:ok, response}` or an error.
`record` receives utterances, tool calls, tool results, and notices. The host
chooses their storage and access rules. Credentials stay in the host.

## Connect a LiveView

1. Call `FormAssistant.Live.init/1` in `mount/3`.
2. Handle `fa_open` in the host page.
3. Call `FormAssistant.Live.open/4` with the configuration and saved values.
4. Supply an `on_change` callback that refreshes the page from the draft.
5. Delegate other `fa_` events to `FormAssistant.Live.handle_event/3`.
6. Delegate `:form_assistant_turn` results to `FormAssistant.Live.handle_async/3`.
7. Delegate voice messages to `FormAssistant.Live.handle_info/2`.
8. Send manual edits through `owner_edit/2` or `owner_set/3` while a draft exists.

Render `FormAssistant.Components.assistant/1` with the
`:form_assistant_turns` stream and an `:intro` slot. Use `draft_bar/1` for
save controls and `change_notes/1` beside each form section.

The assistant and the person share one draft history. Closing the panel keeps
the draft. Discarding drops it. Saving always calls the host's form callback.

## Include browser assets

Import the packaged CSS after Armature in the host's stylesheet:

```css
@import "../../deps/armature/priv/static/armature.css";
@import "../../deps/otp_form_assistant/priv/static/form_assistant.css";
```

The CSS uses Armature tokens. Adjust these paths for local path dependencies.

Merge this package's colocated hooks into the host's `LiveSocket` options:

```javascript
import {hooks as appHooks} from "phoenix-colocated/my_app"
import {hooks as formHooks} from "phoenix-colocated/otp_form_assistant"

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...appHooks, ...formHooks}
})
```

The asset bundler must search `Mix.Project.build_path()` for generated hooks,
as the standard esbuild configuration for Phoenix does. The hook name is
`FormAssistant.Components.FormAssistantVoice`.

## Enable voice

Add the optional runtime to the host's supervision tree:

```elixir
{FormAssistant.Supervisor,
 name: MyApp.FormAssistantRuntime,
 sessions: MyApp.FormAssistantSessions}
```

Set `config.voice` to the matching session supervisor:

```elixir
%FormAssistant.Voice.Options{
  supervisor: MyApp.FormAssistantSessions,
  transport: MyApp.FormVoiceTransport,
  model: voice_model,
  voice: voice,
  delegate_model: backend_model
}
```

The default runtime and session names are `FormAssistant.Supervisor` and
`FormAssistant.Voice.Sessions`. Use distinct names for independent runtimes.

Session children are temporary. A crash does not recreate an external
conversation. A session ends when its page exits or its time limit expires.

Voice needs a secure browser context and microphone permission. The host
transport owns the provider connection and authentication. Leave `voice: nil`
for text-only use.

## Development

Run `MIX_ENV=test mix deps.get`.
Run `MIX_ENV=test mix quality`.

The suite uses a synthetic form, a fake transport, and an isolated test
LiveView. It needs no database, provider credentials, or running phone app.
The quality gates include coverage, Dialyzer, security checks, and package build.

## Publication

Run every command in `.hone-gates.json` before a push or publication.
Build the archive with `mix hex.build`.
Inspect the archive contents before publishing.
Publish an approved version with `mix hex.publish`.

Hex publication is separate from creating this repository. Keep credentials
in a platform secret store and pass them to the publishing process in memory.
