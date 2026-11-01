defmodule FormAssistant.Voice.Protocol do
  @moduledoc """
  The GPT-Live messages a voice session with the form assistant uses. Pure.

  Copied from live-session probes and phone calls made on 2026-10-31.
  VERIFIED in the source implementation: `session.start` and
  `session.started` on a direct session, output audio as 24 kHz PCM16 in
  `session.output_audio.delta`, transcript deltas, delegated tool calls
  wrapped in `response.event`, and the `response.item.create` and
  `response.create` reply.

  INFERRED: input audio as 24 kHz PCM16 (the source verified mu-law input),
  and that `session.instructions.append` with typed words gets an answer.
  Extraction preserves these shapes and does not add live verification.
  """

  @rate 24_000

  @doc "The audio sample rate both ways."
  @spec rate() :: pos_integer()
  def rate, do: @rate

  @doc "The first message: the voice model, its instructions, 24 kHz PCM16 audio and the backend with the tools."
  @spec session_start(map()) :: map()
  def session_start(%{model: model, voice: voice, instructions: instructions} = opts) do
    %{
      "type" => "session.start",
      "event_id" => "start",
      "session" => %{
        "model" => model,
        "instructions" => instructions,
        "audio" => %{
          "format" => %{"type" => "audio/pcm", "rate" => @rate},
          "output" => %{"voice" => voice}
        },
        "delegation" => %{
          "type" => "responses",
          "responses" => %{
            "model" => opts.delegate_model,
            "instructions" => opts.delegate_instructions,
            "tools" => opts.tools
          }
        }
      }
    }
  end

  @doc "Whether an event says the session has started."
  @spec started?(term()) :: boolean()
  def started?(%{"type" => "session.started"}), do: true
  def started?(_event), do: false

  @doc "The reason in `session.closed`, or nil."
  @spec closed_reason(term()) :: String.t() | nil
  def closed_reason(%{"type" => "session.closed"} = event),
    do: if(is_binary(event["reason"]), do: event["reason"], else: "closed")

  def closed_reason(_event), do: nil

  @doc "The person's audio, base64 PCM16 at 24 kHz."
  @spec input_audio(String.t()) :: map()
  def input_audio(base64), do: %{"type" => "session.input_audio.append", "audio" => base64}

  @doc "The model's audio in an output delta, base64, or nil."
  @spec output_audio(term()) :: String.t() | nil
  def output_audio(%{"type" => "session.output_audio.delta", "delta" => delta})
      when is_binary(delta),
      do: delta

  def output_audio(_event), do: nil

  @doc "A transcript delta: `{:owner | :assistant, text}`, or nil."
  @spec transcript(term()) :: {:owner | :assistant, String.t()} | nil
  def transcript(%{"type" => "session.input_transcript.delta", "delta" => text})
      when is_binary(text),
      do: {:owner, text}

  def transcript(%{"type" => "session.output_transcript.delta", "delta" => text})
      when is_binary(text),
      do: {:assistant, text}

  def transcript(_event), do: nil

  @doc "A finished tool call from the backend, or nil."
  @spec function_call(term()) ::
          %{call_id: String.t(), name: String.t(), arguments: String.t()} | nil
  def function_call(%{"type" => "response.event", "event" => event}) when is_map(event),
    do: function_call(event)

  def function_call(%{
        "type" => "response.output_item.done",
        "item" => %{
          "type" => "function_call",
          "call_id" => id,
          "name" => name,
          "arguments" => args
        }
      })
      when is_binary(id) and is_binary(name) and is_binary(args),
      do: %{call_id: id, name: name, arguments: args}

  def function_call(_event), do: nil

  @doc "A tool's output for the backend."
  @spec function_call_output(String.t(), map(), String.t()) :: map()
  def function_call_output(call_id, output, event_id) do
    %{
      "type" => "response.item.create",
      "event_id" => event_id,
      "item" => %{
        "type" => "function_call_output",
        "call_id" => call_id,
        "output" => Jason.encode!(output)
      }
    }
  end

  @doc "Asks the backend to continue after a tool output."
  @spec response_create(String.t()) :: map()
  def response_create(event_id), do: %{"type" => "response.create", "event_id" => event_id}

  @doc "Asks the voice model to say or take in something now."
  @spec instructions_append(String.t(), String.t()) :: map()
  def instructions_append(content, event_id) do
    %{
      "type" => "session.instructions.append",
      "event_id" => event_id,
      "delegation_id" => nil,
      "content" => content
    }
  end

  @doc "Ends the session."
  @spec session_close(String.t()) :: map()
  def session_close(event_id), do: %{"type" => "session.close", "event_id" => event_id}
end
