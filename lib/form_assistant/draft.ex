defmodule FormAssistant.Draft do
  @moduledoc """
  A draft of a form's values with one history of changes. Pure.

  `values` are the draft's values; `saved` are the values last saved. Every
  change, by the person (`:owner`) or by the assistant, goes on the same
  history, so "undo that" works whoever made it. A new change clears what
  was undone. A change is checked by the form (`c:FormAssistant.Form.validate/1`)
  and stored in the form it gives.
  """

  alias FormAssistant.Form

  @type author :: :owner | :assistant

  @type change :: %{
          field: String.t(),
          from: term(),
          to: term(),
          by: author(),
          reason: String.t() | nil
        }

  @type t :: %__MODULE__{
          form: module(),
          saved: Form.values(),
          values: Form.values(),
          done: [change()],
          undone: [change()]
        }

  @enforce_keys [:form]
  defstruct [:form, saved: %{}, values: %{}, done: [], undone: []]

  @doc "A draft of saved values, with no history."
  @spec new(module(), Form.values()) :: t()
  def new(form, values), do: %__MODULE__{form: form, saved: values, values: values}

  @doc """
  Changes one field. `{:ok, draft, nil}` when it already has that value.
  """
  @spec set(t(), String.t(), term(), author(), String.t() | nil) ::
          {:ok, t(), change() | nil} | {:error, String.t()}
  def set(%__MODULE__{form: form} = draft, field, value, by, reason \\ nil) do
    with :ok <- known(form, field),
         {:ok, checked} <- check(form, Map.put(draft.values, field, value), field) do
      new_value = Map.get(checked, field)
      old_value = Map.get(draft.values, field)

      if new_value == old_value do
        {:ok, draft, nil}
      else
        change = %{field: field, from: old_value, to: new_value, by: by, reason: reason}
        values = Map.put(draft.values, field, new_value)
        {:ok, %{draft | values: values, done: [change | draft.done], undone: []}, change}
      end
    end
  end

  @doc "Empties one field, as `set/5` with nil."
  @spec clear(t(), String.t(), author(), String.t() | nil) ::
          {:ok, t(), change() | nil} | {:error, String.t()}
  def clear(draft, field, by, reason \\ nil), do: set(draft, field, nil, by, reason)

  @doc """
  Records the person's edit of several fields at once (a form section), one
  change for each field that differs. Fields the form refuses are left out.
  """
  @spec owner_edit(t(), Form.values()) :: t()
  def owner_edit(%__MODULE__{} = draft, values) do
    Enum.reduce(Form.ids(draft.form), draft, fn field, acc ->
      with true <- Map.has_key?(values, field) and values[field] != acc.values[field],
           {:ok, acc, _change} <- set(acc, field, values[field], :owner) do
        acc
      else
        _ -> acc
      end
    end)
  end

  @doc "Takes back the last change, whoever made it."
  @spec undo(t()) :: {:ok, t(), change()} | :nothing
  def undo(%__MODULE__{done: []}), do: :nothing

  def undo(%__MODULE__{done: [change | done]} = draft) do
    values = Map.put(draft.values, change.field, change.from)
    {:ok, %{draft | values: values, done: done, undone: [change | draft.undone]}, change}
  end

  @doc "Makes the last undone change again."
  @spec redo(t()) :: {:ok, t(), change()} | :nothing
  def redo(%__MODULE__{undone: []}), do: :nothing

  def redo(%__MODULE__{undone: [change | undone]} = draft) do
    values = Map.put(draft.values, change.field, change.to)
    {:ok, %{draft | values: values, done: [change | draft.done], undone: undone}, change}
  end

  @doc "The fields whose value is not the saved one, in the form's order."
  @spec changed_fields(t()) :: [String.t()]
  def changed_fields(%__MODULE__{} = draft),
    do:
      Enum.filter(Form.ids(draft.form), &(Map.get(draft.values, &1) != Map.get(draft.saved, &1)))

  @doc "Whether the draft has changes not saved."
  @spec dirty?(t()) :: boolean()
  def dirty?(draft), do: changed_fields(draft) != []

  @doc "The latest change still in effect for a field, or nil."
  @spec last_change(t(), String.t()) :: change() | nil
  def last_change(%__MODULE__{done: done}, field), do: Enum.find(done, &(&1.field == field))

  @doc "The draft after a save: these are now the saved values. The history stays."
  @spec saved(t(), Form.values()) :: t()
  def saved(%__MODULE__{} = draft, values), do: %{draft | saved: values, values: values}

  defp known(form, field) do
    if field in Form.ids(form), do: :ok, else: {:error, "#{inspect(field)} is not a field"}
  end

  defp check(form, values, field) do
    case form.validate(values) do
      {:ok, checked} ->
        {:ok, checked}

      {:error, errors} ->
        {name, text} =
          case Map.fetch(errors, field) do
            {:ok, text} -> {field, text}
            :error -> errors |> Enum.sort() |> hd()
          end

        {:error, "#{name} #{text}"}
    end
  end
end
