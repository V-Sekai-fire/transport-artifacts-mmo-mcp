# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.Client do
  @moduledoc "Game API client (OpenAPI 8.2.2); every call is traced as the API layer of a run."

  alias ArtifactsMMOMCP.{Trace, Watch}

  @cooldown 499
  @in_progress 486

  def base_url, do: System.get_env("ARTIFACTS_MMO_API_URL", "https://api.artifactsmmo.com")

  # Sourced from OpenBao at `secret/artifacts-mmo/api`, injected by the deploy.
  def token, do: System.get_env("ARTIFACTS_MMO_TOKEN", "")

  def default_character, do: System.get_env("ARTIFACTS_MMO_CHARACTER", "")

  # `await_cooldown?` sleeps out a 499 and retries once, so the trace is of play
  # rather than of a client racing its own cooldown.
  def action(character, action_path, body, run_id, step, await_cooldown? \\ true) do
    path = "/my/#{character}/action/#{action_path}"

    result =
      case request(:post, path, body, run_id, step) do
        {:error, {@cooldown, %{"error" => %{"data" => %{"remaining_seconds" => seconds}}}}}
        when await_cooldown? ->
          Process.sleep(seconds * 1000 + 250)
          request(:post, path, body, run_id, step)

        other ->
          other
      end

    Watch.note_action(character, action_path, status_of(result))
    result
  end

  def get(path, params \\ [], run_id \\ nil, step \\ nil) do
    request(:get, path, nil, run_id, step, params)
  end

  defp request(method, path, body, run_id, step, params \\ []) do
    url = String.trim_trailing(base_url(), "/") <> path
    started = System.monotonic_time(:millisecond)

    opts =
      [
        method: method,
        url: url,
        headers: headers(),
        params: params,
        receive_timeout: 30_000
      ] ++ if(body == nil, do: [], else: [json: body])

    result =
      case Req.request(opts) do
        {:ok, %Req.Response{status: status, body: response}} when status in 200..299 ->
          {:ok, response}

        {:ok, %Req.Response{status: status, body: response}} ->
          {:error, {status, response}}

        {:error, exception} ->
          {:error, {:transport, Exception.message(exception)}}
      end

    Trace.api_call(%{
      run_id: run_id,
      step: step,
      method: method,
      path: path,
      params: Map.new(params),
      request: body,
      status: status_of(result),
      response: response_of(result),
      cooldown_seconds: cooldown_of(result),
      elapsed_ms: System.monotonic_time(:millisecond) - started
    })

    result
  end

  defp headers do
    base = [{"accept", "application/json"}, {"content-type", "application/json"}]
    if token() == "", do: base, else: [{"authorization", "Bearer #{token()}"} | base]
  end

  defp status_of({:ok, _}), do: 200
  defp status_of({:error, {status, _}}) when is_integer(status), do: status
  defp status_of({:error, {:transport, _}}), do: 0

  defp response_of({:ok, body}), do: body
  defp response_of({:error, {_, body}}), do: body

  defp cooldown_of({:ok, %{"data" => %{"cooldown" => %{"total_seconds" => seconds}}}}),
    do: seconds

  defp cooldown_of(_), do: 0

  def describe_error({@cooldown, body}), do: "character is in cooldown: #{detail(body)}"

  def describe_error({@in_progress, body}),
    do: "an action is already in progress: #{detail(body)}"

  def describe_error({:transport, message}), do: "request failed: #{message}"
  def describe_error({status, body}), do: "HTTP #{status}: #{detail(body)}"

  defp detail(%{"error" => %{"message" => message}}), do: message
  defp detail(body), do: inspect(body)
end
