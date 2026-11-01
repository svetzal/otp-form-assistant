defmodule FormAssistant.Tools do
  @moduledoc """
  The assistant's tools, a form editor over the draft, made from the form's
  description. Pure. `run/3` takes a tool call's name and arguments (JSON
  or a map) and the draft, and gives the output for the model, the new draft
  and, for `save`, the person's words that asked for it. Saving is not done
  here: it needs the scope (`FormAssistant.Session.save/2`).

  Bad input becomes an error output, never an exception.
  """

  alias FormAssistant.{Draft, Form, Review}

  @type result :: %{output: map(), draft: Draft.t(), save: String.t() | nil}

  @doc "The tool definitions, for the Responses API and GPT-Live's backend."
  @spec specs(module()) :: [map()]
  def specs(form) do
    field = %{
      "type" => "string",
      "enum" => Form.ids(form),
      "description" => "The field's id, from describe_form."
    }

    reason = %{
      "type" => "string",
      "description" => "A few words the person sees beside the field: why it changed."
    }

    [
      spec(
        "describe_form",
        "The form's sections and fields: what each is for, its limits and allowed values, and which other fields it affects.",
        %{}
      ),
      spec(
        "read_form",
        "The draft's values, the saved values, and which fields have changes not saved.",
        %{}
      ),
      spec(
        "set_field",
        "Change one field in the draft. The page shows it at once. Nothing is saved. The result has the stored value and the related fields with their values.",
        %{
          "field" => field,
          "value" => %{
            "type" => "string",
            "description" => "The new value, as describe_form says for the field."
          },
          "reason" => reason
        }
      ),
      spec("clear_field", "Empty one field in the draft.", %{"field" => field, "reason" => reason}),
      spec(
        "undo",
        "Take back the last change in the draft, whether the person or you made it.",
        %{}
      ),
      spec("redo", "Make the last undone change again.", %{}),
      spec(
        "review",
        "Fields that are empty, look thin, or disagree with another field, each with the related fields.",
        %{}
      ),
      spec(
        "save",
        "Save the draft. Call it only when the person has just said to save, in this turn.",
        %{
          "owner_words" => %{
            "type" => "string",
            "description" => "The person's words that asked you to save."
          }
        }
      )
    ]
  end

  defp spec(name, description, properties) do
    %{
      "type" => "function",
      "name" => name,
      "description" => description,
      "parameters" => %{
        "type" => "object",
        "properties" => properties,
        "required" => Map.keys(properties),
        "additionalProperties" => false
      }
    }
  end

  @doc "Runs one tool call on the draft."
  @spec run(String.t(), String.t() | map(), Draft.t()) :: result()
  def run(name, arguments, %Draft{} = draft) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, args} when is_map(args) -> run(name, args, draft)
      _ -> error(draft, "the arguments are not a JSON object")
    end
  end

  def run("describe_form", _args, draft), do: ok(draft, %{"fields" => describe(draft.form)})

  def run("read_form", _args, draft) do
    ok(draft, %{
      "draft" => draft.values,
      "saved" => draft.saved,
      "changed_not_saved" => Draft.changed_fields(draft)
    })
  end

  def run("set_field", %{"field" => field, "value" => value} = args, draft),
    do: change(draft, Draft.set(draft, field, value, :assistant, args["reason"]), field)

  def run("clear_field", %{"field" => field} = args, draft),
    do: change(draft, Draft.clear(draft, field, :assistant, args["reason"]), field)

  def run("undo", _args, draft), do: step(draft, Draft.undo(draft), "undone")
  def run("redo", _args, draft), do: step(draft, Draft.redo(draft), "redone")

  def run("review", _args, draft),
    do: ok(draft, %{"findings" => Review.review(draft.form, draft.values)})

  def run("save", %{"owner_words" => words}, draft) when is_binary(words) and words != "" do
    if Draft.dirty?(draft),
      do: %{output: %{"status" => "saving"}, draft: draft, save: words},
      else: ok(draft, %{"status" => "nothing to save"})
  end

  def run(name, _args, draft) do
    if name in ~w(describe_form read_form set_field clear_field undo redo review save),
      do: error(draft, "missing arguments for #{name}"),
      else: error(draft, "unknown tool #{name}")
  end

  @doc "The form's fields for `describe_form`."
  @spec describe(module()) :: [map()]
  def describe(form) do
    for field <- form.fields() do
      %{
        "field" => field.id,
        "section" => field.section,
        "label" => field.label,
        "help" => field.help,
        "type" => Atom.to_string(field.type),
        "limits" => field.limits,
        "choices" => field.choices,
        "affects" =>
          for({other, why} <- Form.related(form, field.id), do: %{"field" => other, "why" => why})
      }
    end
  end

  defp change(draft, {:ok, new_draft, nil}, field),
    do:
      ok(new_draft, %{"status" => "unchanged", "field" => field, "value" => draft.values[field]})

  defp change(_draft, {:ok, new_draft, change}, field) do
    ok(new_draft, %{
      "status" => "changed in the draft, not saved",
      "field" => field,
      "value" => change.to,
      "was" => change.from,
      "related" => related(new_draft, field)
    })
  end

  defp change(draft, {:error, message}, _field), do: error(draft, message)

  defp related(draft, field) do
    for {other, why} <- Form.related(draft.form, field),
        do: %{"field" => other, "value" => draft.values[other], "why" => why}
  end

  defp step(draft, :nothing, _verb),
    do: error(draft, "there is nothing to take back or make again")

  defp step(_draft, {:ok, new_draft, change}, verb) do
    ok(new_draft, %{
      "status" => verb,
      "field" => change.field,
      "value" => new_draft.values[change.field],
      "by" => Atom.to_string(change.by)
    })
  end

  defp ok(draft, output), do: %{output: output, draft: draft, save: nil}
  defp error(draft, message), do: %{output: %{"error" => message}, draft: draft, save: nil}
end
