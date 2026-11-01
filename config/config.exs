import Config

if config_env() == :test do
  config :phoenix, :json_library, Jason

  config :otp_form_assistant, FormAssistant.TestEndpoint,
    url: [host: "localhost"],
    secret_key_base: String.duplicate("test-only-fixture-", 4),
    live_view: [signing_salt: "test-only"],
    server: false
end
