defmodule FormAssistant.Review do
  @moduledoc """
  What looks missing, thin or contradictory in a draft, for the `review`
  tool. Pure. The general checks are here: a field marked `worth_filling`
  that is empty, and a `:list` field with one item. The form adds its own
  (`c:FormAssistant.Form.review/1`). Each finding names the related fields
  from the form's dependency map unless the form names them itself.
  """

  alias FormAssistant.{Field, Form}

  @doc "The findings, in the form's field order."
  @spec review(module(), Form.values()) :: [Form.finding()]
  def review(form, values) do
    own = if function_exported?(form, :review, 1), do: form.review(values), else: []
    order = Form.ids(form)

    (general(form, values) ++ own)
    |> Enum.map(&Map.put_new_lazy(&1, "related", fn -> related(form, &1["field"]) end))
    |> Enum.sort_by(&Enum.find_index(order, fn id -> id == &1["field"] end))
  end

  @doc "The items of a list value: one for each line that is not blank, bullets removed."
  @spec items(term()) :: [String.t()]
  def items(text) when is_binary(text) do
    text
    |> String.split(~r/\R/)
    |> Enum.map(&(&1 |> String.trim() |> String.replace(~r/^[-*•]\s*/u, "")))
    |> Enum.reject(&(&1 == ""))
  end

  def items(_value), do: []

  defp general(form, values) do
    Enum.flat_map(form.fields(), fn %Field{} = field ->
      value = values[field.id]

      cond do
        field.worth_filling and blank?(value) ->
          [%{"field" => field.id, "issue" => "empty", "note" => "#{field.label} is empty."}]

        field.type == :list and length(items(value)) == 1 ->
          [
            %{
              "field" => field.id,
              "issue" => "thin",
              "note" => "#{field.label} has only one item."
            }
          ]

        true ->
          []
      end
    end)
  end

  defp related(form, id), do: form |> Form.related(id) |> Enum.map(&elem(&1, 0))

  defp blank?(nil), do: true
  defp blank?([]), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
