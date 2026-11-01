defmodule FormAssistant.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :otp_form_assistant

  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Session, store: :cookie, key: "_test", signing_salt: "test-only")
  plug(FormAssistant.TestRouter)
end
