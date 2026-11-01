defmodule FormAssistant.Voice.Session do
  @moduledoc """
  One voice conversation with the form assistant: a process that holds a
  GPT-Live session of its own and bridges it to the page that started it
  (the owner, usually a LiveView). It knows nothing of telephones.

  - The page sends the person's microphone audio (`audio/2`, base64 PCM16
    at 24 kHz) and typed words (`typed/2`).
  - The session sends the page `{:form_assistant_voice, pid, message}`:
    `{:status, status}` (`:connecting`, `:listening`, `:speaking`, `:ended`
    or `{:failed, reason}`), `{:audio, base64}` to play, `{:said, speaker,
    text}` for each finished turn, and `{:tool_call, call}`.
  - The page runs each tool call on its draft and answers with
    `tool_result/3`, which goes back to GPT-Live's backend.

  The voice model talks; the session's backend (the configured
  `delegate_model`) makes the tool calls, as GPT-Live delegation does on a
  phone call. The process ends when the page stops it or goes away, when
  GPT-Live closes the session, or at the time limit. It records each turn
  through the `record` function it is given.

  Start sessions under the dynamic supervisor in `FormAssistant.Voice.Options`.
  The host adds `FormAssistant.Supervisor` when using voice.
  """
  use GenServer, restart: :temporary

  require Logger

  alias FormAssistant.Voice.{Options, Protocol}

  @typedoc "What a session starts with."
  @type args :: %{
          owner: pid(),
          options: Options.t(),
          instructions: String.t(),
          tools: [map()],
          record: (map() -> term())
        }

  @doc "Starts a session under the configured dynamic supervisor."
  @spec start(args()) :: DynamicSupervisor.on_start_child()
  def start(args),
    do: DynamicSupervisor.start_child(args.options.supervisor, {__MODULE__, args})

  @doc false
  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @doc "The person's audio: base64 PCM16 at 24 kHz."
  @spec audio(pid(), String.t()) :: :ok
  def audio(pid, base64), do: GenServer.cast(pid, {:audio, base64})

  @doc "Words the person typed while the voice session runs."
  @spec typed(pid(), String.t()) :: :ok
  def typed(pid, text), do: GenServer.cast(pid, {:typed, text})

  @doc "A tool call's output, from the page."
  @spec tool_result(pid(), String.t(), map()) :: :ok
  def tool_result(pid, call_id, output), do: GenServer.cast(pid, {:tool_result, call_id, output})

  @doc "Ends the session."
  @spec stop(pid()) :: :ok
  def stop(pid), do: GenServer.cast(pid, :stop)

  @doc """
  What the voice model is told: the form's instructions, and that its
  backend reads and changes the form. Delegation works as on a phone call:
  the model asks its backend with `<|SpawnThinking|>`.
  """
  @spec voice_instructions(String.t()) :: String.t()
  def voice_instructions(instructions) do
    instructions <>
      """

      # Speaking

      You are speaking with the person. Keep each turn to a sentence or two.
      A backend does the tool work for you. Generate <|SpawnThinking|> when you
      need to read the form, review it, change, clear, undo or redo a field, or
      save. Say what the backend's result says; do not guess it while you wait.
      """
  end

  @doc "What the session's backend is told."
  @spec backend_instructions(String.t()) :: String.t()
  def backend_instructions(instructions) do
    instructions <>
      """

      # Backend

      You are the backend for a voice assistant that talks with the person. Call
      the tools the conversation needs, then write what the voice should say next
      in one or two short sentences.
      """
  end

  @impl true
  def init(args) do
    Process.send_after(self(), :limit, args.options.limit_ms)
    send(self(), :connect)

    {:ok,
     %{
       owner: args.owner,
       owner_ref: Process.monitor(args.owner),
       transport: args.options.transport,
       start: start_message(args),
       record: args.record,
       socket: nil,
       turn: nil,
       speaking?: false,
       sequence: 0
     }}
  end

  @impl true
  def handle_cast({:audio, base64}, %{socket: socket} = state) when socket != nil,
    do: {:noreply, push(state, Protocol.input_audio(base64))}

  def handle_cast({:audio, _base64}, state), do: {:noreply, state}

  def handle_cast({:typed, text}, state) do
    state = flush(state)
    state.record.(%{kind: :utterance, speaker: :owner, text: text})
    note = ~s(The person typed this in the text box: "#{text}". Answer it.)
    {:noreply, push(state, Protocol.instructions_append(note, event_id(state)))}
  end

  def handle_cast({:tool_result, call_id, output}, state) do
    state =
      state
      |> push(Protocol.function_call_output(call_id, output, event_id(state)))
      |> push(Protocol.response_create(event_id(state)))

    {:noreply, state}
  end

  def handle_cast(:stop, state), do: {:stop, :normal, close(state, "stopped")}

  @impl true
  def handle_info(:connect, state) do
    tell(state, {:status, :connecting})

    with {:ok, socket} <- state.transport.connect(),
         {:ok, socket} <- state.transport.send_event(socket, state.start) do
      {:noreply, %{state | socket: socket}}
    else
      failure ->
        Logger.warning("form assistant voice session could not start: #{inspect(failure)}")
        tell(state, {:status, {:failed, "the voice service did not answer"}})
        {:stop, :normal, state}
    end
  end

  def handle_info(:limit, state), do: {:stop, :normal, close(state, "time limit")}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = state),
    do: {:stop, :normal, close(state, "page closed")}

  def handle_info(message, %{socket: socket} = state) when socket != nil do
    case state.transport.frames(socket, message) do
      {:ok, socket, frames} -> frames(%{state | socket: socket}, frames)
      :unknown -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp frames(state, []), do: {:noreply, state}

  defp frames(state, [:closed | _rest]),
    do: {:stop, :normal, ended(%{state | socket: nil}, "closed")}

  defp frames(state, [{:text, text} | rest]) do
    case Jason.decode(text) do
      {:ok, event} ->
        case event(state, event) do
          {:stop, state} -> {:stop, :normal, state}
          state -> frames(state, rest)
        end

      {:error, _} ->
        frames(state, rest)
    end
  end

  defp event(state, event) do
    cond do
      Protocol.started?(event) -> opened(state)
      audio = Protocol.output_audio(event) -> speaking(state, audio)
      piece = Protocol.transcript(event) -> transcript(state, piece)
      call = Protocol.function_call(event) -> tool_call(state, call)
      reason = Protocol.closed_reason(event) -> {:stop, ended(%{state | socket: nil}, reason)}
      true -> state
    end
  end

  defp opened(state) do
    tell(state, {:status, :listening})

    push(
      state,
      Protocol.instructions_append(
        "Open the conversation now: have the backend read and review the form, then ask " <>
          "your one open question.",
        event_id(state)
      )
    )
  end

  defp speaking(state, audio) do
    tell(state, {:audio, audio})

    if state.speaking? do
      state
    else
      tell(state, {:status, :speaking})
      %{state | speaking?: true}
    end
  end

  defp transcript(state, {speaker, text}) do
    state =
      case state.turn do
        {^speaker, words} -> %{state | turn: {speaker, words <> text}}
        _other -> %{flush(state) | turn: {speaker, text}}
      end

    if speaker == :owner and state.speaking? do
      tell(state, {:status, :listening})
      %{state | speaking?: false}
    else
      state
    end
  end

  defp tool_call(state, call) do
    tell(state, {:tool_call, call})
    state
  end

  # A finished turn goes to the page and the record.
  defp flush(%{turn: nil} = state), do: state

  defp flush(%{turn: {speaker, words}} = state) do
    text = String.trim(words)

    if text != "" do
      state.record.(%{kind: :utterance, speaker: speaker, text: text})
      tell(state, {:said, speaker, text})
    end

    %{state | turn: nil}
  end

  defp close(state, reason) do
    state =
      if state.socket do
        state = push(state, Protocol.session_close(event_id(state)))
        state.transport.close(state.socket)
        %{state | socket: nil}
      else
        state
      end

    ended(state, reason)
  end

  defp ended(state, reason) do
    state = flush(state)
    state.record.(%{kind: :notice, speaker: :system, text: "The voice session ended: #{reason}."})
    tell(state, {:status, :ended})
    state
  end

  defp push(%{socket: nil} = state, _event), do: state

  defp push(state, event) do
    state = %{state | sequence: state.sequence + 1}

    case state.transport.send_event(state.socket, event) do
      {:ok, socket} ->
        %{state | socket: socket}

      {:error, socket, reason} ->
        Logger.warning("form assistant voice session could not send: #{inspect(reason)}")
        %{state | socket: socket}
    end
  end

  defp event_id(state), do: "fa_#{state.sequence + 1}"

  defp tell(state, message), do: send(state.owner, {:form_assistant_voice, self(), message})

  defp start_message(args) do
    Protocol.session_start(%{
      model: args.options.model,
      voice: args.options.voice,
      instructions: voice_instructions(args.instructions),
      delegate_model: args.options.delegate_model,
      delegate_instructions: backend_instructions(args.instructions),
      tools: args.tools
    })
  end
end
