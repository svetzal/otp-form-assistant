defmodule ConsumerTest do
  use ExUnit.Case, async: true

  alias FormAssistant.{Config, Draft, TextTurn}

  test "the unpacked package supports a host form without phone app code" do
    {:ok, values} = Consumer.SettingsForm.load(:editor)
    draft = Draft.new(Consumer.SettingsForm, values)
    test = self()

    config = %Config{
      form: Consumer.SettingsForm,
      scope: :editor,
      text_model: "fixture-model",
      record: &send(test, {:record, &1}),
      respond: fn _request ->
        {:ok,
         %{
           "id" => "r1",
           "output" => [
             %{
               "type" => "message",
               "content" => [%{"type" => "output_text", "text" => "What title would you like?"}]
             }
           ]
         }}
      end
    }

    assert {:ok, %{reply: "What title would you like?"}} = TextTurn.run(config, draft, nil, nil)
    assert_received {:record, %{speaker: :assistant}}
    assert {:ok, changed, _} = Draft.set(draft, "title", "Revised", :owner)
    assert {:ok, saved} = FormAssistant.save(config, changed)
    refute Draft.dirty?(saved)
    assert {:error, :unauthorized} = FormAssistant.save(%{config | scope: :reader}, changed)
    assert :code.which(PhoneAssistant) == :non_existing
  end

  test "CSS and voice hooks are available to the consumer build" do
    assert File.read!(Application.app_dir(:otp_form_assistant, "priv/static/form_assistant.css")) =~
             ".fa-draft-bar"

    hooks = Path.join(Mix.Project.build_path(), "phoenix-colocated/otp_form_assistant/index.js")
    assert File.read!(hooks) =~ "FormAssistant.Components.FormAssistantVoice"
    assert is_list(FormAssistant.Components.__info__(:functions))
    assert Process.whereis(FormAssistant.Voice.Sessions) == nil
  end
end
