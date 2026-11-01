# Integration guide

This guide connects the package to an existing Phoenix LiveView application.
The host must already authenticate users and supply an authorized scope.

## Install the package

Use Elixir 1.20, Erlang/OTP 29, Phoenix LiveView 1.2, and Armature 0.4.
The module namespace is `FormAssistant`.
The OTP application name is `:otp_form_assistant`.

After publication to Hex, add the dependency to the host's `mix.exs`:

```elixir
{:otp_form_assistant, "~> 0.1.0"}
```

For an unpublished local trial, use a path dependency instead:

```elixir
{:otp_form_assistant, path: "../otp-form-assistant"}
```

Run `mix deps.get`.
Do not load this package beside another copy of the `FormAssistant` modules.
Remove the embedded copy during consumer migration, as a separate change.
This extraction leaves the original phone application unchanged.

## Implement the form contract

Implement `FormAssistant.Form` in a host module. Use string field IDs.
Return a map with those IDs from `load/1`. The host owns every stored value.

| Callback | Contract |
| --- | --- |
| `fields/0` | Returns field descriptors in display order. |
| `load(scope)` | Returns `{:ok, values}` or an access/storage error. |
| `validate(values)` | Returns normalized values or errors by field. |
| `save(scope, values, changed)` | Checks access and saves, or fails. |
| `context(scope)` | Returns the form context sent to the model. |
| `review(values)` | Optional host findings, each naming a field and issue. |

`validate/1` receives the full draft. It must parse model-provided strings,
check choices, and return a nonempty errors map on failure. Keep stored
values consistent with the corresponding field IDs.

The package applies a validated edit to its selected field. Do not rely on
`validate/1` to update other draft fields as a side effect. Make related
changes explicit.

`save/3` must recheck scope and enforce all storage constraints. The changed
IDs describe the draft. They are not authorization.

Use a transaction when several host records must change together.
Add optimistic locking if
concurrent editors must not overwrite each other.

The [synthetic consumer form](https://github.com/svetzal/otp-form-assistant/blob/main/examples/consumer/lib/settings_form.ex)
is a complete minimal implementation. Replace its in-memory save callback
with the host's authorized persistence path.

## Supply model and recording adapters

Create a `FormAssistant.Config` for the person and form:

```elixir
defp assistant_config(scope) do
  %FormAssistant.Config{
    form: MyApp.SettingsForm,
    scope: scope,
    text_model: MyApp.Models.form_model(),
    respond: &MyApp.ModelClient.respond/1,
    record: &MyApp.Conversations.record_event(scope, &1)
  }
end
```

The `MyApp` modules in this guide are host adapters, not package modules.
Implement them in the host before using these examples.

The `respond` function receives a request map. Return `{:ok, response_map}`
or `{:error, reason}`. Responses contain output messages or function calls.

Keep authentication, request timeouts, retry limits, and redacted logging
inside the adapter. The package does not fetch credentials.

The `record` function receives a map with `kind`, `speaker`, and optional
`text` and `payload` keys. Kinds include utterances, tool calls, tool results,
and notices. Scope each stored event to the authorized conversation.
Do not do slow remote work in this callback.

## Connect the LiveView

This example assumes an authentication hook assigns `:current_scope`.
The page loads saved values and displays draft values while a draft exists.

```elixir
defmodule MyAppWeb.SettingsLive do
  use MyAppWeb, :live_view

  alias FormAssistant.Live, as: AssistantLive

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    case MyApp.SettingsForm.load(scope) do
      {:ok, values} ->
        {:ok, socket |> assign(:values, values) |> AssistantLive.init()}

      {:error, _reason} ->
        {:ok, redirect(socket, to: "/")}
    end
  end

  def handle_event(
        "fa_open",
        _params,
        %{assigns: %{form_assistant: nil}} = socket
      ) do
    config = assistant_config(socket.assigns.current_scope)
    {:noreply, AssistantLive.open(socket, config, socket.assigns.values, &changed/2)}
  end

  def handle_event("fa_" <> _ = event, params, socket) do
    {:noreply, AssistantLive.handle_event(event, params, socket)}
  end

  def handle_async(:form_assistant_turn = name, result, socket) do
    {:noreply, AssistantLive.handle_async(name, result, socket)}
  end

  def handle_info({:form_assistant_voice, _, _} = message, socket) do
    {:noreply, AssistantLive.handle_info(message, socket)}
  end

  defp changed(socket, _event) do
    case AssistantLive.draft(socket) do
      nil ->
        case MyApp.SettingsForm.load(socket.assigns.current_scope) do
          {:ok, values} -> assign(socket, :values, values)
          {:error, _reason} -> redirect(socket, to: "/")
        end

      draft ->
        assign(socket, :values, draft.values)
    end
  end

  # Add assistant_config/1 from the previous section.
end
```

The `fa_open` guard preserves an existing draft on duplicate events.
A failed reload after discard redirects to the host's entry page.
Keep unrelated host events and messages in their existing handlers.

Render the assistant components inside the host's `render/1`:

```heex
<FormAssistant.Components.assistant
  id="assistant"
  state={@form_assistant}
  turns={@streams.form_assistant_turns}
>
  <:intro>Talk through the settings before saving.</:intro>
</FormAssistant.Components.assistant>
<FormAssistant.Components.draft_bar id="draft" state={@form_assistant} />
<FormAssistant.Components.change_notes
  state={@form_assistant}
  section="Settings"
/>
```

Render the host's fields from `@values`. While `AssistantLive.active?/1`
is true, route manual edits through `owner_edit/2` or `owner_set/3`.
Do not save those edits directly. After discard, resume the host's normal
editing path.

`owner_set/3` returns an error for a refused change.
`owner_edit/2` skips refused fields.

Use unique component IDs. The components send `fa_` events to the host
LiveView and use the `:form_assistant_turns` stream created by `init/1`.

## Include the CSS and hook

Import the package CSS after Armature:

```css
@import "../../deps/armature/priv/static/armature.css";
@import "../../deps/otp_form_assistant/priv/static/form_assistant.css";
```

Adjust paths for local dependencies. Keep Armature's token values available.
The package does not serve static files through its own endpoint.

Import both sets of hooks in the host's JavaScript:

```javascript
import {hooks as appHooks} from "phoenix-colocated/my_app"
import {hooks as formHooks} from "phoenix-colocated/otp_form_assistant"

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...appHooks, ...formHooks}
})
```

Use the host's existing `Socket`, `LiveSocket`, and CSRF token imports.
Do not create a second LiveSocket for the assistant. The bundler must find
`Mix.Project.build_path()` in its module search path. Standard Phoenix
esbuild configuration sets this through `NODE_PATH`.

The generated hook is `FormAssistant.Components.FormAssistantVoice`.
Build browser assets after compiling the package.

## Add optional voice

Add a child to the host's supervision tree:

```elixir
{FormAssistant.Supervisor,
 name: MyApp.FormAssistantRuntime,
 sessions: MyApp.FormVoiceSessions}
```

Set the voice options on the configuration:

```elixir
%FormAssistant.Voice.Options{
  transport: MyApp.FormVoiceTransport,
  supervisor: MyApp.FormVoiceSessions,
  model: voice_model,
  voice: voice_name,
  delegate_model: backend_model,
  limit_ms: 20 * 60 * 1000
}
```

Implement all callbacks in `FormAssistant.Voice.Transport`:

- `connect/0` opens an authenticated session and returns `{:ok, socket}`.
- `send_event/2` sends one event and returns the updated socket or an error.
- `frames/2` converts mailbox messages into text frames or a closed frame.
- `close/1` closes the socket and returns `:ok`.

The process calling `connect/0` must own the socket's network messages.
The package owns protocol event handling. Keep network details in the transport.

Browser audio is base64 PCM16 at 24 kHz. Audio events use the existing
LiveView connection. Use HTTPS and obtain microphone permission.

Leave `voice: nil` for text-only use. Distinct runtime names and session
supervisor names allow several independent runtimes in one VM.

## Check the integration

1. Open the assistant with model requests replaced by fixtures.
2. Apply a tool edit and confirm the database stays unchanged.
3. Mix manual and assistant changes through undo and redo.
4. Save through the host's authorized callback.
5. Try the same save with a scope that cannot edit.
6. Discard and confirm the saved values return.
7. Build the production JavaScript and CSS.
8. Check the voice hook with a fake transport.
9. Test a real voice connection in the intended browser before enabling voice.

Run `python3 scripts/check-package.py` from this repository after
`mix hex.build` to test a separate consumer against the unpacked archive.
That check needs no phone application, database, or model credentials.
