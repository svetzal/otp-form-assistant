defmodule FormAssistant.Supervisor do
  @moduledoc """
  The optional voice runtime. Add this child to the host's supervision tree
  when using voice. Text-only hosts need no runtime child.

      {FormAssistant.Supervisor, name: MyApp.FormAssistant, sessions: MyApp.FormVoice}

  Set `FormAssistant.Voice.Options.supervisor` to the same `:sessions` name.
  Multiple runtimes can coexist. Each runtime supervises temporary voice
  sessions: an external conversation is not recreated after a crash.
  """
  use Supervisor

  @doc false
  def child_spec(opts) do
    opts |> super() |> Map.put(:id, Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Starts a runtime with an optional supervisor name and session supervisor name."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    children = [
      {DynamicSupervisor,
       name: Keyword.get(opts, :sessions, FormAssistant.Voice.Sessions), strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
