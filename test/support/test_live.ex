defmodule FormAssistant.TestLive do
  @moduledoc false
  use Phoenix.LiveView

  alias FormAssistant.{Config, TestForm}
  alias FormAssistant.Voice.Options

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:test, session["test"])
     |> assign(:respond, session["respond"])
     |> assign(:scope, session["scope"] || :allowed)
     |> assign(:voice?, session["voice"] || false)
     |> assign(:last_change, nil)
     |> FormAssistant.Live.init()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="test-form">
      <FormAssistant.Components.assistant
        id="assistant"
        state={@form_assistant}
        turns={@streams.form_assistant_turns}
      >
        <:intro>Review this form.</:intro>
      </FormAssistant.Components.assistant>
      <FormAssistant.Components.draft_bar :if={@form_assistant} id="draft" state={@form_assistant} />
      <FormAssistant.Components.change_notes
        :if={@form_assistant}
        state={@form_assistant}
        section="About"
      />
      <p id="values">{if @form_assistant, do: inspect(@form_assistant.draft.values)}</p>
      <p id="changed">{@last_change}</p>
    </div>
    """
  end

  @impl true
  def handle_event("fa_open", _params, socket) do
    test = socket.assigns.test
    respond = socket.assigns.respond

    config = %Config{
      form: TestForm,
      scope: socket.assigns.scope,
      respond: fn body ->
        send(test, {:request, body})
        Agent.get_and_update(respond, fn [next | rest] -> {next, rest} end)
      end,
      record: &send(test, {:recorded, &1}),
      text_model: "test-model",
      voice: voice_options(socket.assigns.voice?)
    }

    {:ok, values} = TestForm.load(:allowed)
    {:noreply, FormAssistant.Live.open(socket, config, values, &assign(&1, :last_change, &2))}
  end

  def handle_event("owner", %{"name" => name}, socket),
    do: {:noreply, FormAssistant.Live.owner_edit(socket, %{"name" => name})}

  def handle_event("owner_set", %{"name" => name}, socket) do
    case FormAssistant.Live.owner_set(socket, "name", name) do
      {:ok, socket} -> {:noreply, socket}
      {:error, reason} -> {:noreply, assign(socket, :last_change, reason)}
    end
  end

  def handle_event(event, params, socket),
    do: {:noreply, FormAssistant.Live.handle_event(event, params, socket)}

  @impl true
  def handle_async(name, result, socket),
    do: {:noreply, FormAssistant.Live.handle_async(name, result, socket)}

  @impl true
  def handle_info(message, socket),
    do: {:noreply, FormAssistant.Live.handle_info(message, socket)}

  defp voice_options(false), do: nil

  defp voice_options(true) do
    %Options{
      transport: FormAssistant.FakeTransport,
      model: "voice",
      voice: "gleam",
      delegate_model: "backend"
    }
  end
end
