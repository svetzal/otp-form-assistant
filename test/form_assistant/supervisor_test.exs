defmodule FormAssistant.SupervisorTest do
  use ExUnit.Case, async: false

  alias FormAssistant.Voice.{Options, Session}

  test "independent runtimes keep voice sessions separate" do
    first =
      start_supervised!({FormAssistant.Supervisor, name: FirstRuntime, sessions: FirstSessions})

    second =
      start_supervised!({FormAssistant.Supervisor, name: SecondRuntime, sessions: SecondSessions})

    assert first != second

    Application.put_env(:otp_form_assistant, :fake_transport_test, self())
    on_exit(fn -> Application.delete_env(:otp_form_assistant, :fake_transport_test) end)

    args = %{
      owner: self(),
      options: %Options{
        transport: FormAssistant.FakeTransport,
        model: "m",
        voice: "v",
        delegate_model: "d",
        supervisor: FirstSessions
      },
      instructions: "Help",
      tools: [],
      record: fn _ -> :ok end
    }

    {:ok, pid} = Session.start(args)
    assert_receive {:sent, %{"type" => "session.start"}}
    assert [{_, ^pid, _, _}] = DynamicSupervisor.which_children(FirstSessions)
    assert [] = DynamicSupervisor.which_children(SecondSessions)

    ref = Process.monitor(pid)
    Session.stop(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert [] = DynamicSupervisor.which_children(FirstSessions)
  end
end
