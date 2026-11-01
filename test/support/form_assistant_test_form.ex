defmodule FormAssistant.TestForm do
  @moduledoc """
  A small form for the form assistant's own tests: a name, a colour from a
  list, and a list of things that affects the colour. `save/3` accepts only
  the scope `:allowed`. It names nothing from the phone assistant.
  """
  @behaviour FormAssistant.Form

  alias FormAssistant.Field

  @impl true
  def fields do
    [
      %Field{
        id: "name",
        label: "Name",
        section: "About",
        help: "Who it is.",
        limits: "Required.",
        worth_filling: true
      },
      %Field{
        id: "colour",
        label: "Colour",
        section: "About",
        type: :choice,
        choices: ~w(red blue),
        limits: "red or blue."
      },
      %Field{
        id: "things",
        label: "Things",
        section: "Lists",
        type: :list,
        worth_filling: true,
        affects: [{"colour", "Things come in the colour."}]
      }
    ]
  end

  @impl true
  def load(:allowed), do: {:ok, %{"name" => "Pat", "colour" => "red", "things" => nil}}
  def load(_scope), do: {:error, :unauthorized}

  @impl true
  def validate(values) do
    values = Map.new(values, fn {k, v} -> {k, if(is_binary(v), do: String.trim(v), else: v)} end)

    errors =
      Map.reject(
        %{
          "name" => if(values["name"] in [nil, ""], do: "can't be blank"),
          "colour" => if(values["colour"] not in [nil, "red", "blue"], do: "is not red or blue")
        },
        fn {_k, v} -> is_nil(v) end
      )

    if errors == %{}, do: {:ok, values}, else: {:error, errors}
  end

  @impl true
  def save(:allowed, values, _changed), do: {:ok, values}
  def save(_scope, _values, _changed), do: {:error, :unauthorized}

  @impl true
  def review(values) do
    if (is_binary(values["things"]) and values["colour"]) &&
         String.contains?(values["things"], "green"),
       do: [
         %{
           "field" => "things",
           "issue" => "conflict",
           "note" => "Green things, #{values["colour"]} colour."
         }
       ],
       else: []
  end

  @impl true
  def context(_scope), do: "The form is a test form."
end
