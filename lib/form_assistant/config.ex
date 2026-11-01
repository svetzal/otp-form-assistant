defmodule FormAssistant.Config do
  @moduledoc """
  What an application gives the assistant for one person on one form.

  - `form`: the module implementing `FormAssistant.Form`.
  - `scope`: the application's scope, passed back to the form.
  - `respond`: a function that sends a Responses API request body and
    returns `{:ok, response}` or `{:error, reason}`. The application owns
    the HTTP client and the key.
  - `record`: a function that keeps one conversation event, a map with
    `:kind` (`:utterance`, `:tool_call`, `:tool_result`, `:notice`),
    `:speaker` (`:owner`, `:assistant`, `:system`), `:text` and `:payload`.
    The application decides where it is stored and who reads it.
  - `text_model`: the Responses model for typed turns.
  - `voice`: nil for text only, or `FormAssistant.Voice.Options`.
  """

  @type t :: %__MODULE__{
          form: module(),
          scope: term(),
          respond: (map() -> {:ok, map()} | {:error, term()}),
          record: (map() -> term()),
          text_model: String.t(),
          voice: FormAssistant.Voice.Options.t() | nil
        }

  @enforce_keys [:form, :scope, :respond, :record, :text_model]
  defstruct [:form, :scope, :respond, :record, :text_model, voice: nil]
end
