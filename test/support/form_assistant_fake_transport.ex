defmodule FormAssistant.FakeTransport do
  @moduledoc """
  A GPT-Live transport for the form assistant's tests. `connect/0` gives a
  socket that is the test process's pid (from the `:fake_transport_test`
  application env, or the caller's `$callers`); each sent event goes to the
  test as `{:sent, event}`. Frames arrive as `{:fake_frames, frames}`.
  """
  @behaviour FormAssistant.Voice.Transport

  @impl true
  def connect do
    case Application.get_env(:otp_form_assistant, :fake_transport_test) do
      pid when is_pid(pid) -> {:ok, pid}
      _ -> {:error, :no_test}
    end
  end

  @impl true
  def send_event(test, event) do
    send(test, {:sent, event})
    {:ok, test}
  end

  @impl true
  def frames(test, {:fake_frames, frames}), do: {:ok, test, frames}
  def frames(_test, _message), do: :unknown

  @impl true
  def close(test) do
    send(test, :closed)
    :ok
  end
end
