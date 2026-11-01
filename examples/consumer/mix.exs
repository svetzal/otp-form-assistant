defmodule Consumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :form_assistant_consumer,
      version: "0.1.0",
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      deps: [{:otp_form_assistant, path: System.fetch_env!("FORM_ASSISTANT_SOURCE")}]
    ]
  end
end
