defmodule FormAssistant.TestRouter do
  @moduledoc false
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:protect_from_forgery)
  end

  scope "/" do
    pipe_through(:browser)
    live("/form", FormAssistant.TestLive)
  end
end
