ExUnit.start()

{:ok, _} = Supervisor.start_link([FormAssistant.TestEndpoint], strategy: :one_for_one)
