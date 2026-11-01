defmodule FormAssistant.Responses do
  @moduledoc """
  The few OpenAI Responses API shapes a typed turn needs (DOCUMENTED). Pure.
  `previous_response_id` does not carry instructions or tools over, so each
  request sends them again.
  """

  @doc "A request body."
  @spec request(keyword()) :: map()
  def request(opts) do
    body = %{
      "model" => Keyword.fetch!(opts, :model),
      "instructions" => Keyword.fetch!(opts, :instructions),
      "input" => Keyword.fetch!(opts, :input),
      "tools" => Keyword.fetch!(opts, :tools),
      "store" => true
    }

    case Keyword.get(opts, :previous_response_id) do
      nil -> body
      previous -> Map.put(body, "previous_response_id", previous)
    end
  end

  @doc "A user message input item."
  @spec user_message(String.t()) :: map()
  def user_message(text), do: %{"role" => "user", "content" => text}

  @doc "A tool's output as an input item, JSON-encoded."
  @spec function_call_output(String.t(), map()) :: map()
  def function_call_output(call_id, output),
    do: %{
      "type" => "function_call_output",
      "call_id" => call_id,
      "output" => Jason.encode!(output)
    }

  @doc "The response id, or nil."
  @spec id(map()) :: String.t() | nil
  def id(%{"id" => id}) when is_binary(id), do: id
  def id(_response), do: nil

  @doc "The function calls in a response's output, in order."
  @spec function_calls(map()) :: [%{call_id: String.t(), name: String.t(), arguments: String.t()}]
  def function_calls(response) do
    for %{"type" => "function_call", "call_id" => call_id, "name" => name, "arguments" => args}
        when is_binary(call_id) and is_binary(name) and is_binary(args) <- output(response) do
      %{call_id: call_id, name: name, arguments: args}
    end
  end

  @doc "The text of a response's output messages, joined and trimmed."
  @spec text(map()) :: String.t()
  def text(response) do
    for %{"type" => "message", "content" => content} when is_list(content) <- output(response),
        %{"type" => "output_text", "text" => text} when is_binary(text) <- content,
        into: "" do
      text
    end
    |> String.trim()
  end

  defp output(%{"output" => output}) when is_list(output), do: output
  defp output(_response), do: []
end
