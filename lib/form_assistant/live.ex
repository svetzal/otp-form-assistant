defmodule FormAssistant.Live do
  @moduledoc """
  The form assistant in a LiveView: its state on the socket, its events and
  messages, and what the page must call. The components are in
  `FormAssistant.Components`.

  A host LiveView:

  1. calls `init/1` in `mount/3`;
  2. handles `"fa_open"` itself (it knows the scope and how to record), and
     calls `open/4` with a `FormAssistant.Config`, the saved values and an
     `on_change` function that refreshes the page from `draft/1` (it gets
     `:changed` or `:saved`);
  3. passes every other `"fa_" <> _` event to `handle_event/3`,
     `{:form_assistant_voice, _, _}` messages to `handle_info/2`, and the
     `:form_assistant_turn` async result to `handle_async/3`;
  4. while `active?/1`, sends the person's own form edits to `owner_edit/2`
     or `owner_set/3` instead of saving them, so they go on the same history.

  The state lives under the `:form_assistant` assign, and the conversation
  in the `:form_assistant_turns` stream.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, start_async: 3, stream: 3, stream_insert: 3]

  alias FormAssistant.{Config, Draft, Prompt, TextTurn, Tools}
  alias FormAssistant.Voice.Session
  alias Phoenix.LiveView.Socket

  @async :form_assistant_turn
  @max_audio_bytes 64_000

  @doc "Sets up the assistant's assigns, closed."
  @spec init(Socket.t()) :: Socket.t()
  def init(socket),
    do: socket |> assign(:form_assistant, nil) |> stream(:form_assistant_turns, [])

  @doc """
  Opens the assistant on saved values. The assistant then opens the
  conversation with a typed turn.
  """
  @spec open(Socket.t(), Config.t(), map(), (Socket.t(), :changed | :saved -> Socket.t())) ::
          Socket.t()
  def open(socket, %Config{} = config, values, on_change) do
    state = %{
      config: config,
      draft: Draft.new(config.form, values),
      open?: true,
      busy?: false,
      response_id: nil,
      voice: nil,
      on_change: on_change
    }

    socket |> assign(:form_assistant, state) |> on_change.(:changed) |> text_turn(nil)
  end

  @doc "Whether the page holds a draft."
  @spec active?(Socket.t()) :: boolean()
  def active?(socket), do: socket.assigns[:form_assistant] != nil

  @doc "The draft, or nil."
  @spec draft(Socket.t()) :: Draft.t() | nil
  def draft(socket), do: socket.assigns[:form_assistant] && socket.assigns.form_assistant.draft

  @doc "The person's edit of several fields at once, on the draft's history."
  @spec owner_edit(Socket.t(), map()) :: Socket.t()
  def owner_edit(socket, values), do: change(socket, &Draft.owner_edit(&1, values))

  @doc "The person's change of one field, on the draft's history."
  @spec owner_set(Socket.t(), String.t(), term()) :: {:ok, Socket.t()} | {:error, String.t()}
  def owner_set(socket, field, value) do
    case Draft.set(draft(socket), field, value, :owner) do
      {:ok, draft, _change} -> {:ok, change(socket, fn _ -> draft end)}
      {:error, message} -> {:error, message}
    end
  end

  @doc "Handles the assistant's `fa_` events. Anything else, or while closed, does nothing."
  @spec handle_event(String.t(), map(), Socket.t()) :: Socket.t()
  def handle_event(_event, _params, %{assigns: %{form_assistant: nil}} = socket), do: socket

  def handle_event("fa_say", %{"say" => %{"message" => message}}, socket) do
    case {String.trim(message), state(socket)} do
      {"", _state} -> socket
      {_text, %{busy?: true}} -> socket
      {text, %{voice: %{pid: pid}}} -> typed(socket, pid, text)
      {text, _state} -> text_turn(socket, text)
    end
  end

  def handle_event("fa_undo", _params, socket), do: step(socket, &Draft.undo/1)
  def handle_event("fa_redo", _params, socket), do: step(socket, &Draft.redo/1)

  def handle_event("fa_save", _params, socket) do
    if state(socket).busy? do
      socket
    else
      case FormAssistant.save(state(socket).config, draft(socket)) do
        {:ok, draft} -> socket |> put(draft: draft) |> notify(:saved)
        {:error, _reason} -> insert(socket, :assistant, "The form could not be saved.")
      end
    end
  end

  def handle_event("fa_close", _params, socket),
    do: socket |> stop_voice() |> put(open?: false)

  def handle_event("fa_reopen", _params, socket), do: put(socket, open?: true)

  def handle_event("fa_discard", _params, socket) do
    if state(socket).busy? do
      socket
    else
      %{on_change: on_change} = state(socket)
      socket |> stop_voice() |> assign(:form_assistant, nil) |> on_change.(:changed)
    end
  end

  def handle_event("fa_voice_start", _params, socket) do
    case state(socket) do
      %{voice: nil, config: %Config{voice: %{} = options} = config} ->
        {:ok, pid} =
          Session.start(%{
            owner: self(),
            options: options,
            instructions: Prompt.instructions(config.form, config.scope),
            tools: Tools.specs(config.form),
            record: config.record
          })

        socket
        |> put(voice: %{pid: pid, status: :connecting})
        |> push_event("fa:voice_start", %{rate: FormAssistant.Voice.Protocol.rate()})

      _state ->
        socket
    end
  end

  def handle_event("fa_voice_stop", _params, socket), do: stop_voice(socket)

  def handle_event("fa_voice_audio", %{"audio" => audio}, socket)
      when is_binary(audio) and byte_size(audio) <= @max_audio_bytes do
    case state(socket) do
      %{voice: %{pid: pid}} -> Session.audio(pid, audio)
      _state -> :ok
    end

    socket
  end

  def handle_event("fa_voice_error", %{"message" => message}, socket) do
    socket
    |> stop_voice()
    |> insert(
      :assistant,
      "The microphone could not start: #{String.slice(to_string(message), 0, 200)}"
    )
  end

  def handle_event(_event, _params, socket), do: socket

  @doc "Handles a typed turn's result."
  @spec handle_async(atom(), term(), Socket.t()) :: Socket.t()
  def handle_async(@async, _result, %{assigns: %{form_assistant: nil}} = socket), do: socket

  def handle_async(@async, {:ok, {:ok, result}}, socket) do
    socket
    |> put(busy?: false, draft: result.draft, response_id: result.response_id)
    |> insert(:assistant, result.reply)
    |> notify(if result.saved?, do: :saved, else: :changed)
  end

  def handle_async(@async, _failed, socket) do
    socket
    |> put(busy?: false)
    |> insert(:assistant, "Sorry, I could not answer just now. Please try again.")
  end

  @doc "Handles a voice session's message."
  @spec handle_info(term(), Socket.t()) :: Socket.t()
  def handle_info({:form_assistant_voice, pid, message}, socket) do
    case state(socket) do
      %{voice: %{pid: ^pid}} -> voice(socket, pid, message)
      _other -> socket
    end
  end

  def handle_info(_message, socket), do: socket

  defp voice(socket, _pid, {:audio, audio}),
    do: push_event(socket, "fa:voice_audio", %{audio: audio})

  defp voice(socket, _pid, {:said, speaker, text}), do: insert(socket, speaker, text)

  defp voice(socket, _pid, {:status, :ended}),
    do: socket |> put(voice: nil) |> push_event("fa:voice_stop", %{})

  defp voice(socket, _pid, {:status, {:failed, reason}}) do
    socket
    |> put(voice: nil)
    |> push_event("fa:voice_stop", %{})
    |> insert(:assistant, "Voice could not start: #{reason}. You can type instead.")
  end

  defp voice(socket, pid, {:status, status}), do: put(socket, voice: %{pid: pid, status: status})

  defp voice(socket, pid, {:tool_call, call}) do
    {output, draft, saved?} = FormAssistant.run_tool(state(socket).config, draft(socket), call)
    Session.tool_result(pid, call.call_id, output)
    socket |> put(draft: draft) |> notify(if saved?, do: :saved, else: :changed)
  end

  defp typed(socket, pid, text) do
    :ok = Session.typed(pid, text)
    insert(socket, :owner, text)
  end

  defp text_turn(socket, text) do
    %{config: config, draft: draft, response_id: previous} = state(socket)
    socket = if text, do: insert(socket, :owner, text), else: socket

    socket
    |> put(busy?: true)
    |> start_async(@async, fn -> TextTurn.run(config, draft, text, previous) end)
  end

  defp stop_voice(socket) do
    case state(socket) do
      %{voice: %{pid: pid}} ->
        Session.stop(pid)
        socket |> put(voice: nil) |> push_event("fa:voice_stop", %{})

      _state ->
        socket
    end
  end

  defp step(socket, fun) do
    case {state(socket), fun.(draft(socket))} do
      {%{busy?: true}, _} -> socket
      {_state, {:ok, draft, _change}} -> socket |> put(draft: draft) |> notify(:changed)
      {_state, :nothing} -> socket
    end
  end

  defp change(socket, fun), do: socket |> put(draft: fun.(draft(socket))) |> notify(:changed)

  defp notify(socket, what), do: state(socket).on_change.(socket, what)

  defp insert(socket, speaker, text) do
    stream_insert(socket, :form_assistant_turns, %{
      id: "fa-turn-#{System.unique_integer([:positive])}",
      speaker: speaker,
      text: text
    })
  end

  defp state(socket), do: socket.assigns.form_assistant

  defp put(socket, changes),
    do: assign(socket, :form_assistant, Map.merge(state(socket), Map.new(changes)))
end
