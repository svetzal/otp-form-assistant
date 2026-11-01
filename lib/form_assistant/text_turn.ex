defmodule FormAssistant.TextTurn do
  @moduledoc """
  One typed turn: the person's words go to the Responses API (through the
  config's `respond` function) with the assistant's instructions and tools.
  Tool calls run on the draft (`FormAssistant.Tools`); a save goes through
  `FormAssistant.save/2` with the person's scope. The turn ends with the
  model's reply. Both sides, every tool call and every result are recorded
  through the config's `record` function.
  """

  require Logger

  alias FormAssistant.{Config, Draft, Prompt, Responses, Tools}

  @max_tool_rounds 8
  @fallback "Sorry, I lost track there. Could you say that again?"

  @type result :: %{
          reply: String.t(),
          draft: Draft.t(),
          response_id: String.t() | nil,
          saved?: boolean()
        }

  @doc """
  Runs a turn. `text` is the person's words, or nil to have the assistant
  open the conversation.
  """
  @spec run(Config.t(), Draft.t(), String.t() | nil, String.t() | nil) ::
          {:ok, result()} | {:error, term()}
  def run(%Config{} = config, %Draft{} = draft, text, previous_id) do
    if text, do: config.record.(%{kind: :utterance, speaker: :owner, text: text})

    state = %{
      config: config,
      draft: draft,
      saved?: false,
      instructions: Prompt.instructions(config.form, config.scope),
      previous_id: previous_id
    }

    converse(state, [Responses.user_message(text || opening())], 1)
  end

  @doc "What the model is told when the person opens the assistant without a word yet."
  @spec opening() :: String.t()
  def opening,
    do:
      "(The person has opened the assistant next to the form and has not said anything " <>
        "yet. Open the conversation.)"

  defp converse(state, _input, round) when round > @max_tool_rounds do
    Logger.warning("form assistant: the model kept calling tools for #{@max_tool_rounds} rounds")
    finish(state, @fallback)
  end

  defp converse(state, input, round) do
    request =
      Responses.request(
        model: state.config.text_model,
        instructions: state.instructions,
        input: input,
        tools: Tools.specs(state.config.form),
        previous_response_id: state.previous_id
      )

    with {:ok, response} <- state.config.respond.(request) do
      state = %{state | previous_id: Responses.id(response) || state.previous_id}

      case Responses.function_calls(response) do
        [] ->
          finish(state, nonempty(Responses.text(response)))

        calls ->
          {outputs, state} = Enum.map_reduce(calls, state, &run_tool/2)
          converse(state, outputs, round + 1)
      end
    end
  end

  defp run_tool(call, state) do
    {output, draft, saved?} = FormAssistant.run_tool(state.config, state.draft, call)
    state = %{state | draft: draft, saved?: state.saved? or saved?}
    {Responses.function_call_output(call.call_id, output), state}
  end

  defp finish(state, reply) do
    state.config.record.(%{kind: :utterance, speaker: :assistant, text: reply})

    {:ok,
     %{reply: reply, draft: state.draft, response_id: state.previous_id, saved?: state.saved?}}
  end

  defp nonempty(""), do: @fallback
  defp nonempty(text), do: text
end
