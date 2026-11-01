defmodule Consumer.SettingsForm do
  @moduledoc false
  @behaviour FormAssistant.Form

  @impl true
  def fields, do: [%FormAssistant.Field{id: "title", label: "Title", section: "Settings"}]

  @impl true
  def load(:editor), do: {:ok, %{"title" => "Original"}}

  @impl true
  def validate(values), do: {:ok, values}

  @impl true
  def save(:editor, values, _changed), do: {:ok, values}
  def save(_scope, _values, _changed), do: {:error, :unauthorized}

  @impl true
  def context(_scope), do: "Help with the document title."
end
