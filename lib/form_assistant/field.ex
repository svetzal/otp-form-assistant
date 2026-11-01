defmodule FormAssistant.Field do
  @moduledoc """
  One field of a form, as the assistant sees it.

  - `id`: the field's name in the form's values, a string.
  - `label`, `section`, `help`: what a person reads.
  - `type`: `:text`, `:long_text`, `:list` (one item to a line), `:choice`,
    or another atom the form explains in `limits`.
  - `limits`: its limits and allowed values, in words, for the agent.
  - `choices`: the allowed values of a `:choice`, or nil.
  - `affects`: the fields this one affects, with why: `[{id, why}]`. This is
    the dependency map. `FormAssistant.Form.related/2` reads it both ways.
  - `worth_filling`: whether the review calls the field out when it is empty.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          section: String.t(),
          help: String.t(),
          type: atom(),
          limits: String.t(),
          choices: [String.t()] | nil,
          affects: [{String.t(), String.t()}],
          worth_filling: boolean()
        }

  @enforce_keys [:id, :label, :section]
  defstruct [
    :id,
    :label,
    :section,
    help: "",
    type: :text,
    limits: "",
    choices: nil,
    affects: [],
    worth_filling: false
  ]
end
