defmodule FormAssistantTest do
  use ExUnit.Case, async: true

  alias FormAssistant.{Config, Draft, Form, Prompt, Review, TestForm, TextTurn, Tools}

  defp draft, do: Draft.new(TestForm, %{"name" => "Pat", "colour" => "red", "things" => nil})

  defp config(respond, scope \\ :allowed) do
    test = self()

    %Config{
      form: TestForm,
      scope: scope,
      respond: respond,
      record: &send(test, {:recorded, &1}),
      text_model: "model-1"
    }
  end

  describe "the draft" do
    test "the person's and the assistant's changes share one history" do
      {:ok, draft, %{by: :owner}} = Draft.set(draft(), "name", " Sam ", :owner)
      assert draft.values["name"] == "Sam"
      {:ok, draft, change} = Draft.set(draft, "colour", "blue", :assistant, "they said blue")
      assert change.reason == "they said blue"
      assert Draft.changed_fields(draft) == ["name", "colour"]

      {:ok, draft, %{field: "colour"}} = Draft.undo(draft)
      {:ok, draft, %{by: :owner}} = Draft.undo(draft)
      refute Draft.dirty?(draft)
      assert Draft.undo(draft) == :nothing
      {:ok, draft, %{field: "name"}} = Draft.redo(draft)
      {:ok, draft, _} = Draft.set(draft, "things", "cups", :owner)
      assert Draft.redo(draft) == :nothing
      assert Draft.last_change(draft, "name").to == "Sam"
    end

    test "refuses what the form refuses, and unknown fields" do
      assert {:error, "colour is not red or blue"} = Draft.set(draft(), "colour", "green", :owner)
      assert {:error, "name can't be blank"} = Draft.clear(draft(), "name", :owner)
      assert {:error, ~s("size" is not a field)} = Draft.set(draft(), "size", "L", :owner)
      assert {:ok, _same, nil} = Draft.set(draft(), "name", "Pat", :owner)
    end

    test "an edit of a section is one change for each field that differs" do
      draft = Draft.owner_edit(draft(), %{"name" => "Sam", "colour" => "red", "things" => "a\nb"})
      assert Enum.map(draft.done, & &1.field) == ["things", "name"]
      assert Draft.owner_edit(draft, %{"colour" => "green"}) == draft
      assert Draft.saved(draft, draft.values) |> Draft.dirty?() == false
    end
  end

  describe "the dependency map and the review" do
    test "related fields are read both ways" do
      assert Form.related(TestForm, "things") == [{"colour", "Things come in the colour."}]
      assert Form.related(TestForm, "colour") == [{"things", "Things come in the colour."}]
      assert Form.related(TestForm, "name") == []
    end

    test "finds empty and thin fields, then the form's own" do
      findings =
        Review.review(TestForm, %{"name" => "", "colour" => "red", "things" => "green cups"})

      assert [
               %{"field" => "name", "issue" => "empty", "related" => []},
               %{"field" => "things", "issue" => "thin", "related" => ["colour"]},
               %{"field" => "things", "issue" => "conflict"}
             ] = findings

      assert Review.items("- a\n\n* b") == ["a", "b"]
      assert Review.items(nil) == []
    end
  end

  describe "the tools" do
    defp run(draft, name, args), do: Tools.run(name, Jason.encode!(args), draft)

    test "are made from the form's description" do
      specs = Tools.specs(TestForm)

      assert Enum.map(specs, & &1["name"]) ==
               ~w(describe_form read_form set_field clear_field undo redo review save)

      set = Enum.find(specs, &(&1["name"] == "set_field"))
      assert set["parameters"]["properties"]["field"]["enum"] == ~w(name colour things)

      %{output: %{"fields" => fields}} = run(draft(), "describe_form", %{})

      assert %{
               "field" => "colour",
               "choices" => ["red", "blue"],
               "affects" => [%{"field" => "things"}]
             } =
               Enum.find(fields, &(&1["field"] == "colour"))
    end

    test "set, clear, undo, redo, read and review work on the draft" do
      %{output: out, draft: d} =
        run(draft(), "set_field", %{"field" => "things", "value" => "cups", "reason" => "r"})

      assert out["related"] == [
               %{"field" => "colour", "value" => "red", "why" => "Things come in the colour."}
             ]

      %{output: %{"status" => "unchanged"}} =
        run(d, "set_field", %{"field" => "things", "value" => "cups", "reason" => "r"})

      %{output: %{"error" => "colour is not red or blue"}} =
        run(d, "set_field", %{"field" => "colour", "value" => "green", "reason" => "r"})

      %{draft: d} = run(d, "clear_field", %{"field" => "colour", "reason" => "r"})
      %{output: %{"changed_not_saved" => ["colour", "things"]}} = run(d, "read_form", %{})
      %{output: %{"status" => "undone", "field" => "colour"}, draft: d} = run(d, "undo", %{})
      %{output: %{"status" => "redone"}} = run(d, "redo", %{})
      %{output: %{"findings" => [_ | _]}} = run(d, "review", %{})
    end

    test "save needs the person's words and a change, and only asks to save" do
      %{output: %{"status" => "nothing to save"}} =
        run(draft(), "save", %{"owner_words" => "save"})

      {:ok, changed, _} = Draft.set(draft(), "name", "Sam", :owner)
      %{save: "save", draft: ^changed} = run(changed, "save", %{"owner_words" => "save"})
      %{output: %{"error" => "missing arguments for save"}} = run(changed, "save", %{})
      %{output: %{"error" => "unknown tool fly"}} = run(changed, "fly", %{})
      %{output: %{"error" => _}} = Tools.run("review", "[", changed)
    end
  end

  test "the prompt is the base conversation style with the form's context" do
    text = Prompt.instructions(TestForm, :allowed)
    assert String.starts_with?(text, Prompt.base())
    assert text =~ "The form is a test form."
    assert text =~ "Never call save unless the person has just told you to save"
  end

  describe "saving" do
    test "goes through the form with the scope" do
      {:ok, changed, _} = Draft.set(draft(), "name", "Sam", :owner)
      assert {:ok, saved} = FormAssistant.save(config(nil), changed)
      refute Draft.dirty?(saved)
      assert FormAssistant.save(config(nil, :someone), changed) == {:error, :unauthorized}
    end

    test "a tool call to save records the call and the result" do
      {:ok, changed, _} = Draft.set(draft(), "name", "Sam", :owner)
      call = %{call_id: "c1", name: "save", arguments: ~s({"owner_words": "save it"})}

      {%{"status" => "saved"}, saved, true} = FormAssistant.run_tool(config(nil), changed, call)
      refute Draft.dirty?(saved)
      assert_received {:recorded, %{kind: :tool_call}}

      assert_received {:recorded,
                       %{kind: :tool_result, payload: %{"output" => %{"status" => "saved"}}}}

      {%{"error" => "this person may not save the form"}, _, false} =
        FormAssistant.run_tool(config(nil, :someone), changed, call)
    end
  end

  describe "a typed turn" do
    defp replies(list) do
      {:ok, agent} = Agent.start_link(fn -> list end)
      test = self()

      fn body ->
        send(test, {:request, body})
        Agent.get_and_update(agent, fn [next | rest] -> {next, rest} end)
      end
    end

    defp call_response(id, name, args),
      do:
        {:ok,
         %{
           "id" => id,
           "output" => [
             %{
               "type" => "function_call",
               "call_id" => "c" <> id,
               "name" => name,
               "arguments" => Jason.encode!(args)
             }
           ]
         }}

    defp text_response(id, text),
      do:
        {:ok,
         %{
           "id" => id,
           "output" => [
             %{"type" => "message", "content" => [%{"type" => "output_text", "text" => text}]}
           ]
         }}

    test "runs the model's tool calls on the draft and ends with its reply" do
      respond =
        replies([
          call_response("r1", "set_field", %{
            "field" => "colour",
            "value" => "blue",
            "reason" => "said so"
          }),
          text_response("r2", "Colour is blue now.")
        ])

      {:ok, result} = TextTurn.run(config(respond), draft(), "Make it blue", "r0")

      assert result.reply == "Colour is blue now."
      assert result.draft.values["colour"] == "blue"
      assert result.response_id == "r2"
      refute result.saved?

      assert_received {:request, first}
      assert first["previous_response_id"] == "r0"
      assert first["model"] == "model-1"
      assert first["instructions"] =~ "The form is a test form."
      assert [%{"role" => "user", "content" => "Make it blue"}] = first["input"]
      assert_received {:request, second}
      assert [%{"type" => "function_call_output", "call_id" => "cr1"}] = second["input"]

      assert_received {:recorded, %{kind: :utterance, speaker: :owner}}

      assert_received {:recorded,
                       %{kind: :utterance, speaker: :assistant, text: "Colour is blue now."}}
    end

    test "opens the conversation without words, and an error comes back as an error" do
      {:ok, %{reply: "Hello."}} =
        TextTurn.run(config(replies([text_response("r1", "Hello.")])), draft(), nil, nil)

      assert_received {:request, %{"input" => [%{"content" => opening}]}}
      assert opening == TextTurn.opening()
      refute_received {:recorded, %{speaker: :owner}}

      assert {:error, :timeout} =
               TextTurn.run(config(replies([{:error, :timeout}])), draft(), "hi", nil)
    end

    @tag :capture_log
    test "gives up after too many tool rounds, and an empty reply is replaced" do
      looping = fn _body -> call_response("r", "review", %{}) end
      {:ok, %{reply: reply}} = TextTurn.run(config(looping), draft(), "hi", nil)
      assert reply =~ "lost track"

      {:ok, %{reply: ^reply}} =
        TextTurn.run(config(fn _ -> text_response("r", "") end), draft(), "hi", nil)
    end
  end
end
