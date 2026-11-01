defmodule FormAssistant.LiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias FormAssistant.Voice.Session

  @moduletag :capture_log
  @endpoint FormAssistant.TestEndpoint

  setup do
    start_supervised!(FormAssistant.Supervisor)
    Application.put_env(:otp_form_assistant, :fake_transport_test, self())
    on_exit(fn -> Application.delete_env(:otp_form_assistant, :fake_transport_test) end)
    :ok
  end

  defp text(words) do
    {:ok,
     %{
       "id" => "response",
       "output" => [
         %{"type" => "message", "content" => [%{"type" => "output_text", "text" => words}]}
       ]
     }}
  end

  defp tool(name, args) do
    {:ok,
     %{
       "id" => "tool-response",
       "output" => [
         %{
           "type" => "function_call",
           "call_id" => "call-1",
           "name" => name,
           "arguments" => Jason.encode!(args)
         }
       ]
     }}
  end

  defp mount_form(replies, opts) do
    agent = start_supervised!({Agent, fn -> replies end})

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{
        "test" => self(),
        "respond" => agent,
        "voice" => Keyword.get(opts, :voice, false),
        "scope" => Keyword.get(opts, :scope, :allowed)
      })

    {:ok, view, _html} = live(conn, "/form")
    view
  end

  defp open(replies \\ [text("What would you change?")], opts \\ []) do
    view = mount_form(replies, opts)
    view |> element("#assistant-open") |> render_click()
    render_async(view)
    view
  end

  defp say(view, words) do
    view |> form("#assistant-say", %{"say" => %{"message" => words}}) |> render_submit()
    render_async(view)
  end

  test "a text-only host opens without a voice control" do
    view = open()
    assert has_element?(view, "#assistant-turns", "What would you change?")
    assert has_element?(view, "#draft-count", "No changes yet")
    refute has_element?(view, "#assistant-voice-start")
    assert_received {:request, %{"model" => "test-model"}}
  end

  test "assistant edits remain drafts until the person saves" do
    view =
      open([
        text("Hello"),
        tool("set_field", %{"field" => "name", "value" => "Sam", "reason" => "you asked"}),
        text("Changed")
      ])

    say(view, "Call me Sam")
    assert has_element?(view, "#values", "Sam")
    assert has_element?(view, "#fa-changed-name", "you asked")
    assert has_element?(view, "#draft-count", "1 change not saved")
    refute has_element?(view, "#changed", "saved")
    view |> element("#draft-save") |> render_click()
    assert has_element?(view, "#changed", "saved")
    assert has_element?(view, "#draft-count", "No changes yet")
  end

  test "manual edits share undo and redo history" do
    view = open()
    render_hook(view, "owner", %{"name" => "Sam"})
    assert has_element?(view, "#fa-changed-name", "changed by you")
    view |> element("#draft-undo") |> render_click()
    assert has_element?(view, "#values", "Pat")
    view |> element("#draft-redo") |> render_click()
    assert has_element?(view, "#values", "Sam")
    render_hook(view, "owner_set", %{"name" => "Lee"})
    assert has_element?(view, "#values", "Lee")
    render_hook(view, "owner_set", %{"name" => ""})
    assert has_element?(view, "#changed", "can't be blank")
  end

  test "a host refusal to save leaves the draft intact" do
    view = open([text("Hello")], scope: :denied)
    render_hook(view, "owner", %{"name" => "Sam"})
    view |> element("#draft-save") |> render_click()
    assert has_element?(view, "#assistant-turns", "could not be saved")
    assert has_element?(view, "#draft-count", "1 change not saved")
  end

  test "the assistant saves through the host callback" do
    view =
      open([
        text("Hello"),
        tool("set_field", %{"field" => "name", "value" => "Sam", "reason" => "asked"}),
        tool("save", %{"owner_words" => "save it"}),
        text("Saved")
      ])

    say(view, "Call me Sam and save it")
    assert has_element?(view, "#changed", "saved")
    assert has_element?(view, "#draft-count", "No changes yet")
  end

  test "closing keeps the draft for reopening" do
    view = open()
    render_hook(view, "owner", %{"name" => "Sam"})
    view |> element("#assistant-close") |> render_click()
    refute has_element?(view, "#assistant-say")
    view |> element("#assistant-reopen") |> render_click()
    assert has_element?(view, "#values", "Sam")
  end

  test "discard removes the draft" do
    view = open()
    render_hook(view, "owner", %{"name" => "Sam"})
    view |> element("#draft-discard") |> render_click()
    refute has_element?(view, "#draft")
    assert has_element?(view, "#assistant-open")
    render_hook(view, "fa_say", %{"say" => %{"message" => "ignored"}})
    refute has_element?(view, "#draft")
  end

  test "a provider failure leaves the text box usable" do
    view = open([{:error, :timeout}, text("Recovered")])
    assert has_element?(view, "#assistant-turns", "could not answer")
    say(view, "Try again")
    assert has_element?(view, "#assistant-turns", "Recovered")
  end

  test "blank messages do not call the provider" do
    view = open()
    assert_receive {:request, _}
    say(view, "   ")
    refute_received {:request, _}
  end

  test "voice relays audio and applies tool changes to the same draft" do
    view = open([text("Hello")], voice: true)
    view |> element("#assistant-voice-start") |> render_click()
    assert_push_event(view, "fa:voice_start", %{rate: 24_000})
    assert_receive {:sent, %{"type" => "session.start"}}
    [{_, pid, _, _}] = DynamicSupervisor.which_children(FormAssistant.Voice.Sessions)

    send(pid, {:fake_frames, [{:text, Jason.encode!(%{"type" => "session.started"})}]})
    assert_receive {:sent, %{"type" => "session.instructions.append"}}
    assert has_element?(view, "#assistant-voice-state", "Listening")

    render_hook(view, "fa_voice_audio", %{"audio" => "AAAA"})
    assert_receive {:sent, %{"type" => "session.input_audio.append", "audio" => "AAAA"}}
    send(view.pid, {:form_assistant_voice, pid, {:audio, "BBBB"}})
    assert_push_event(view, "fa:voice_audio", %{audio: "BBBB"})
    send(view.pid, {:form_assistant_voice, pid, {:said, :assistant, "Hello aloud"}})
    assert has_element?(view, "#assistant-turns", "Hello aloud")

    send(
      view.pid,
      {:form_assistant_voice, pid,
       {:tool_call,
        %{
          call_id: "c",
          name: "set_field",
          arguments: ~s({"field":"name","value":"Lee","reason":"asked"})
        }}}
    )

    assert has_element?(view, "#values", "Lee")
    assert_receive {:sent, %{"type" => "response.item.create"}}
    say(view, "Thanks")
    assert_receive {:sent, %{"type" => "session.instructions.append", "content" => content}}
    assert content =~ "Thanks"

    view |> element("#assistant-voice-stop") |> render_click()
    assert_push_event(view, "fa:voice_stop", %{})
    assert has_element?(view, "#assistant-voice-start")
  end

  test "microphone failures leave typed interaction available" do
    view = open()
    render_hook(view, "fa_voice_error", %{"message" => "Permission denied"})
    assert has_element?(view, "#assistant-turns", "Permission denied")
    assert has_element?(view, "#assistant-send:not([disabled])")
  end

  test "voice failure returns the page to text mode" do
    view = open([text("Hello")], voice: true)
    view |> element("#assistant-voice-start") |> render_click()
    assert_receive {:sent, %{"type" => "session.start"}}
    [{_, pid, _, _}] = DynamicSupervisor.which_children(FormAssistant.Voice.Sessions)
    send(view.pid, {:form_assistant_voice, pid, {:status, {:failed, "unavailable"}}})
    assert has_element?(view, "#assistant-turns", "You can type instead")
    assert_push_event(view, "fa:voice_stop", %{})
    Session.stop(pid)
  end

  test "an ended voice session removes the voice controls" do
    view = open([text("Hello")], voice: true)
    view |> element("#assistant-voice-start") |> render_click()
    assert_receive {:sent, %{"type" => "session.start"}}
    [{_, pid, _, _}] = DynamicSupervisor.which_children(FormAssistant.Voice.Sessions)
    ref = Process.monitor(pid)
    Session.stop(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert has_element?(view, "#assistant-voice-start")
    assert_push_event(view, "fa:voice_stop", %{})
  end
end
