defmodule OtpFormAssistant.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/svetzal/otp-form-assistant"

  def project do
    [
      app: :otp_form_assistant,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description:
        "A form assistant for Phoenix LiveView with drafts, tools, review and optional voice sessions.",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @source_url},
        files:
          ~w(lib priv/static .formatter.exs mix.exs README.md CHANGELOG.md LICENSE.md CHARTER.md)
      ],
      source_url: @source_url,
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      test_coverage: [
        summary: [threshold: 90],
        ignore_modules: [~r/^FormAssistant.Test/, FormAssistant.FakeTransport]
      ],
      dialyzer: [plt_local_path: "priv/plts", plt_core_path: "priv/plts"],
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        extras: ["README.md", "CHARTER.md", "CHANGELOG.md"]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.2"},
      {:armature, "~> 0.4.0"},
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.0.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "test --cover",
        "credo --strict",
        "dialyzer",
        "docs --warnings-as-errors",
        "hex.audit",
        "deps.audit",
        "sobelow --config",
        "hex.build",
        "cmd python3 scripts/check-package.py"
      ]
    ]
  end
end
