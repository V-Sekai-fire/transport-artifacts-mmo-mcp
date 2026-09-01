# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.Renew do
  @moduledoc """
  Renews the bao token daily and re-issues the client certificate once fewer
  than ten days of its 30-day life remain.

  A cold start after expiry cannot recover, since reaching bao needs a valid
  certificate; it falls back to the environment and says so on `/health`.
  """

  use GenServer
  require Logger

  alias ArtifactsMMOMCP.Bao

  @name __MODULE__
  @check_ms :timer.hours(1)
  @first_check_ms :timer.seconds(60)
  @token_every_s 24 * 3600
  @cert_margin_s 10 * 24 * 3600
  @common_name "artifacts-mmo-mcp.internal"
  @ttl "720h"

  def start_link(opts), do: GenServer.start_link(@name, opts, name: @name)

  @doc "What renewal has managed so far, for `/health`."
  def status do
    case GenServer.whereis(@name) do
      nil -> %{running: false}
      pid -> GenServer.call(pid, :status)
    end
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :check, @first_check_ms)
    {:ok, %{token_renewed_at: nil, cert_reissued_at: nil, last_error: nil}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    expiry = Bao.cert_expiry()

    reply = %{
      running: true,
      configured: Bao.configured?(),
      cert_expires_at: expiry && DateTime.from_unix!(expiry) |> DateTime.to_iso8601(),
      cert_days_left: expiry && Float.round((expiry - now()) / 86_400, 1),
      token_renewed_at: state.token_renewed_at,
      cert_reissued_at: state.cert_reissued_at,
      last_error: state.last_error
    }

    {:reply, reply, state}
  end

  @impl true
  def handle_info(:check, state) do
    Process.send_after(self(), :check, @check_ms)
    {:noreply, if(Bao.configured?(), do: state |> renew_token() |> reissue_cert(), else: state)}
  end

  defp renew_token(state) do
    if due?(state.token_renewed_at, @token_every_s) do
      case Bao.post("/v1/auth/token/renew-self", %{increment: @ttl}) do
        {:ok, _} ->
          Logger.info("bao: token renewed")
          %{state | token_renewed_at: iso_now(), last_error: nil}

        {:error, reason} ->
          Logger.warning("bao: token renewal failed: #{reason}")
          %{state | last_error: "token renewal: #{reason}"}
      end
    else
      state
    end
  end

  defp reissue_cert(state) do
    expiry = Bao.cert_expiry()

    if is_integer(expiry) and expiry - now() < @cert_margin_s do
      case Bao.post("/v1/pki/issue/service", %{common_name: @common_name, ttl: @ttl}) do
        {:ok, %{"data" => data}} ->
          apply_cert(state, data)

        {:error, reason} ->
          Logger.warning("bao: certificate re-issue failed: #{reason}")
          %{state | last_error: "certificate re-issue: #{reason}"}
      end
    else
      state
    end
  end

  defp apply_cert(state, data) do
    case Bao.put_certificate(data["certificate"], data["private_key"], data["expiration"]) do
      :ok ->
        Logger.info("bao: certificate re-issued, expires #{data["expiration"]}")
        %{state | cert_reissued_at: iso_now(), last_error: nil}

      {:error, reason} ->
        Logger.warning("bao: new certificate rejected: #{reason}")
        %{state | last_error: "new certificate: #{reason}"}
    end
  end

  defp due?(nil, _seconds), do: true

  defp due?(iso, seconds) do
    {:ok, at, _} = DateTime.from_iso8601(iso)
    DateTime.diff(DateTime.utc_now(), at) >= seconds
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_unix()
  defp iso_now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
