defmodule FormAssistant do
  @moduledoc """
  An assistant that helps a person fill in and tidy a form by talking it
  through, by voice or by text. It works on a draft of the form with one
  undo history for the person's and its own changes, through tools made from
  the form's description, and saves only when the person says so.

  It is a capability any Phoenix application can use, packaged as
  `:otp_form_assistant`. The host owns authorization, persistence and
  provider connections. This application starts no processes automatically.
  An application provides:

  - a form: a module implementing `FormAssistant.Form` (its fields, how to
    load, check and save them for a scope, its own review checks and the
    context the agent needs);
  - a `FormAssistant.Config`: the form, the scope, a function that calls the
    Responses API, a function that records the conversation, and, for
    voice, a GPT-Live transport and models;
  - the page glue: `FormAssistant.Live` in a LiveView, with its components.

  The parts:

  - `FormAssistant.Field`, `FormAssistant.Form`: the form descriptor contract.
  - `FormAssistant.Draft`: the draft and its history.
  - `FormAssistant.Tools`, `FormAssistant.Review`, `FormAssistant.Prompt`:
    what the agent can do, what it is told to look at, and how it talks.
  - `FormAssistant.TextTurn`: a typed turn through the Responses API.
  - `FormAssistant.Voice.Session`: the GPT-Live bridge for voice. Optional.
  - `FormAssistant.Live`: LiveView state, events and components.
  """

  alias FormAssistant.{Config, Draft, Tools}

  @doc """
  Saves the draft through the form, with the person's scope. The form
  checks the scope. Returns the draft with the saved values.
  """
  @spec save(Config.t(), Draft.t()) :: {:ok, Draft.t()} | {:error, term()}
  def save(%Config{form: form, scope: scope}, %Draft{} = draft) do
    with {:ok, values} <- form.save(scope, draft.values, Draft.changed_fields(draft)) do
      {:ok, Draft.saved(draft, values)}
    end
  end

  @doc """
  Runs one tool call from the model on the draft, saving when the person
  asked, and records the call and its result. Returns the output for the
  model, the new draft and whether it saved. Used by typed turns and by the
  voice session's page alike.
  """
  @spec run_tool(Config.t(), Draft.t(), %{
          call_id: String.t(),
          name: String.t(),
          arguments: term()
        }) ::
          {map(), Draft.t(), boolean()}
  def run_tool(%Config{} = config, %Draft{} = draft, call) do
    config.record.(%{
      kind: :tool_call,
      speaker: :assistant,
      payload: %{"name" => call.name, "call_id" => call.call_id, "arguments" => call.arguments}
    })

    result = Tools.run(call.name, call.arguments, draft)
    {output, draft, saved?} = maybe_save(config, result)

    config.record.(%{
      kind: :tool_result,
      speaker: :system,
      payload: %{"name" => call.name, "call_id" => call.call_id, "output" => output}
    })

    {output, draft, saved?}
  end

  defp maybe_save(_config, %{save: nil, output: output, draft: draft}), do: {output, draft, false}

  defp maybe_save(config, %{save: words, draft: draft}) do
    case save(config, draft) do
      {:ok, draft} ->
        {%{"status" => "saved", "owner_words" => words}, draft, true}

      {:error, :unauthorized} ->
        {%{"error" => "this person may not save the form"}, draft, false}

      {:error, _} ->
        {%{"error" => "the draft could not be saved; a field is not valid"}, draft, false}
    end
  end
end
