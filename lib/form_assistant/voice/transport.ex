defmodule FormAssistant.Voice.Transport do
  @moduledoc """
  A GPT-Live WebSocket session of its own, as the application provides it.
  The socket belongs to the process that connects it, and its network
  messages arrive in that process's mailbox; `frames/2` reads one.
  """

  @type socket :: term()
  @type frame :: {:text, String.t()} | :closed

  @doc "Opens a new session. The first message must be `session.start`."
  @callback connect() :: {:ok, socket()} | {:error, term()}

  @doc "Sends one client event as JSON."
  @callback send_event(socket(), event :: map()) :: {:ok, socket()} | {:error, socket(), term()}

  @doc "Reads one mailbox message. `:unknown` when it is not this socket's."
  @callback frames(socket(), message :: term()) :: {:ok, socket(), [frame()]} | :unknown

  @doc "Closes the socket."
  @callback close(socket()) :: :ok
end
