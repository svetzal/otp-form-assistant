defmodule FormAssistant.Voice.Options do
  @moduledoc """
  What a voice session needs from the application: the GPT-Live transport
  (a module implementing `FormAssistant.Voice.Transport`), the voice model,
  the voice, the backend model that makes the tool calls, the dynamic
  supervisor that owns the session, and the most a session may last.
  The default supervisor is `FormAssistant.Voice.Sessions`.
  """

  @type t :: %__MODULE__{
          transport: module(),
          model: String.t(),
          voice: String.t(),
          delegate_model: String.t(),
          supervisor: Supervisor.supervisor(),
          limit_ms: pos_integer()
        }

  @enforce_keys [:transport, :model, :voice, :delegate_model]
  defstruct [
    :transport,
    :model,
    :voice,
    :delegate_model,
    supervisor: FormAssistant.Voice.Sessions,
    limit_ms: 20 * 60 * 1000
  ]
end
