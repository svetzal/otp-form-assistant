defmodule FormAssistant.IndependenceTest do
  use ExUnit.Case, async: true

  test "the package has no references to its original host" do
    modules = Application.spec(:otp_form_assistant, :modules)
    assert FormAssistant.Draft in modules
    assert FormAssistant.Components in modules
    assert FormAssistant.Voice.Session in modules

    for module <- modules do
      {:ok, {^module, [atoms: atoms]}} =
        :beam_lib.chunks(
          to_charlist(Application.app_dir(:otp_form_assistant, "ebin/#{module}.beam")),
          [:atoms]
        )

      references =
        for {_index, atom} <- atoms,
            String.starts_with?(Atom.to_string(atom), "Elixir.PhoneAssistant"),
            do: atom

      assert references == [], "#{inspect(module)} refers to #{inspect(references)}"
    end
  end

  test "the package includes its stylesheet and generated voice hook" do
    css = Application.app_dir(:otp_form_assistant, "priv/static/form_assistant.css")
    assert File.read!(css) =~ ".fa-draft-bar"

    hooks =
      Path.wildcard(
        Path.join([
          Mix.Project.build_path(),
          "phoenix-colocated",
          "otp_form_assistant",
          "**",
          "*.js"
        ])
      )

    assert Enum.any?(hooks, &(File.read!(&1) =~ "FormAssistantVoice"))
  end
end
