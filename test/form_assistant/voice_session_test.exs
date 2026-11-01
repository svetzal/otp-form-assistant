defmodule FormAssistant.Voice.SessionTest do
  @moduledoc """
  The voice bridge with a fake GPT-Live transport. The transport finds the
  test through the application env, so the module is not async.
  """
  use ExUnit.Case, async: false

  alias FormAssistant.Voice.{Options, Session}

  setup do
    start_supervised!(FormAssistant.Supervisor)
    Application.put_env(:otp_form_assistant, :fake_transport_test, self())
    on_exit(fn -> Application.delete_env(:otp_form_assistant, :fake_transport_test) end)
    :ok
  end

  defp start(limit_ms \\ 3_600_000) do
    test = self()

    {:ok, pid} =
      Session.start(%{
        owner: test,
        options: %Options{
          transport: FormAssistant.FakeTransport,
          model: "live-1",
          voice: "gleam",
          delegate_model: "luna",
          limit_ms: limit_ms
        },
        instructions: "Help with the form.",
        tools: [%{"name" => "read_form"}],
        record: &send(test, {:recorded, &1})
      })

    assert_receive {:sent, %{"type" => "session.start", "session" => session}}
    assert session["audio"]["format"] == %{"type" => "audio/pcm", "rate" => 24_000}
    assert session["delegation"]["responses"]["model"] == "luna"
    assert session["delegation"]["responses"]["tools"] == [%{"name" => "read_form"}]
    assert session["instructions"] =~ "<|SpawnThinking|>"
    assert_receive {:form_assistant_voice, ^pid, {:status, :connecting}}
    pid
  end

  defp frames(pid, events),
    do: send(pid, {:fake_frames, Enum.map(events, &{:text, Jason.encode!(&1)})})

  test "opens, relays audio both ways, keeps the turns and passes tool calls to the page" do
    pid = start()

    frames(pid, [%{"type" => "session.started", "session" => %{"id" => "s1"}}])
    assert_receive {:form_assistant_voice, ^pid, {:status, :listening}}
    assert_receive {:sent, %{"type" => "session.instructions.append", "content" => opening}}
    assert opening =~ "Open the conversation"

    Session.audio(pid, "AAAA")
    assert_receive {:sent, %{"type" => "session.input_audio.append", "audio" => "AAAA"}}

    frames(pid, [
      %{"type" => "session.output_audio.delta", "delta" => "BBBB"},
      %{"type" => "session.output_transcript.delta", "delta" => "Anything "},
      %{"type" => "session.output_transcript.delta", "delta" => "look off?"},
      %{"type" => "session.input_transcript.delta", "delta" => "Make it blue."}
    ])

    assert_receive {:form_assistant_voice, ^pid, {:audio, "BBBB"}}
    assert_receive {:form_assistant_voice, ^pid, {:status, :speaking}}
    assert_receive {:form_assistant_voice, ^pid, {:said, :assistant, "Anything look off?"}}

    assert_receive {:recorded,
                    %{kind: :utterance, speaker: :assistant, text: "Anything look off?"}}

    assert_receive {:form_assistant_voice, ^pid, {:status, :listening}}

    frames(pid, [
      %{
        "type" => "response.event",
        "event" => %{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "function_call",
            "call_id" => "c1",
            "name" => "set_field",
            "arguments" => "{}"
          }
        }
      }
    ])

    assert_receive {:form_assistant_voice, ^pid,
                    {:tool_call, %{call_id: "c1", name: "set_field"}}}

    Session.tool_result(pid, "c1", %{"status" => "ok"})
    assert_receive {:sent, %{"type" => "response.item.create", "item" => %{"call_id" => "c1"}}}
    assert_receive {:sent, %{"type" => "response.create"}}

    Session.typed(pid, "Actually red")
    assert_receive {:recorded, %{kind: :utterance, speaker: :owner, text: "Make it blue."}}
    assert_receive {:recorded, %{kind: :utterance, speaker: :owner, text: "Actually red"}}
    assert_receive {:sent, %{"type" => "session.instructions.append", "content" => typed}}
    assert typed =~ ~s("Actually red")

    ref = Process.monitor(pid)
    Session.stop(pid)
    assert_receive {:sent, %{"type" => "session.close"}}
    assert_receive :closed
    assert_receive {:form_assistant_voice, ^pid, {:status, :ended}}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  test "ends when GPT-Live closes the session or the page goes away" do
    pid = start()
    ref = Process.monitor(pid)
    frames(pid, [%{"type" => "session.closed", "reason" => "idle"}])
    assert_receive {:recorded, %{kind: :notice, text: "The voice session ended: idle."}}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    test = self()
    page = spawn(fn -> receive do: (:go -> :ok) end)

    {:ok, pid} =
      Session.start(%{
        owner: page,
        options: %Options{
          transport: FormAssistant.FakeTransport,
          model: "m",
          voice: "v",
          delegate_model: "d"
        },
        instructions: "x",
        tools: [],
        record: &send(test, {:recorded, &1})
      })

    ref = Process.monitor(pid)
    send(page, :go)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert_receive {:recorded, %{text: "The voice session ended: page closed."}}
  end

  test "ends at the time limit, which the test sends at once" do
    pid = start()
    ref = Process.monitor(pid)
    send(pid, :limit)
    assert_receive {:recorded, %{text: "The voice session ended: time limit."}}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  @tag :capture_log
  test "says when the voice service cannot be reached" do
    Application.delete_env(:otp_form_assistant, :fake_transport_test)
    test = self()

    {:ok, pid} =
      Session.start(%{
        owner: test,
        options: %Options{
          transport: FormAssistant.FakeTransport,
          model: "m",
          voice: "v",
          delegate_model: "d"
        },
        instructions: "x",
        tools: [],
        record: fn _ -> :ok end
      })

    assert_receive {:form_assistant_voice, ^pid, {:status, {:failed, _reason}}}
  end
end
