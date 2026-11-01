defmodule FormAssistant.Form do
  @moduledoc """
  The behaviour an application implements for each form the assistant can
  help with. Values are a map of field id to value. The scope is the
  application's own (who is asking, for what); the assistant only passes it
  back.

  `validate/1` checks a whole set of values and returns them as they would
  be stored (trimmed, normalised), or the errors by field id. It receives a
  field's value as the agent or the page gave it (often a string), so it
  also parses. `save/3` must check the scope itself: the assistant never
  saves without it.
  """

  alias FormAssistant.Field

  @type values :: %{String.t() => term()}
  @typedoc "A review finding: field, issue (empty, thin or conflict), note and related ids."
  @type finding :: %{String.t() => term()}

  @doc "The fields, in the order the page shows them."
  @callback fields() :: [Field.t()]

  @doc "The saved values for the scope, or an error when the scope may not edit."
  @callback load(scope :: term()) :: {:ok, values()} | {:error, term()}

  @doc "The values as they would be stored, or the errors by field id."
  @callback validate(values()) :: {:ok, values()} | {:error, %{String.t() => String.t()}}

  @doc "Saves the values for the scope. `changed` names the fields that changed."
  @callback save(scope :: term(), values(), changed :: [String.t()]) ::
              {:ok, values()} | {:error, term()}

  @doc "The form's own checks: fields that disagree, beyond empty and thin ones."
  @callback review(values()) :: [finding()]

  @doc "What the agent needs to know about this form and whose it is, in plain words."
  @callback context(scope :: term()) :: String.t()

  @optional_callbacks review: 1

  @doc "One field by id, or nil."
  @spec field(module(), String.t()) :: Field.t() | nil
  def field(form, id), do: Enum.find(form.fields(), &(&1.id == id))

  @doc "The field ids, in order."
  @spec ids(module()) :: [String.t()]
  def ids(form), do: Enum.map(form.fields(), & &1.id)

  @doc """
  The fields a field affects, with why: those it names, then those that name
  it.
  """
  @spec related(module(), String.t()) :: [{String.t(), String.t()}]
  def related(form, id) do
    own = (field(form, id) || %{affects: []}).affects

    others =
      for other <- form.fields(),
          {^id, why} <- other.affects,
          not List.keymember?(own, other.id, 0),
          do: {other.id, why}

    own ++ others
  end
end
