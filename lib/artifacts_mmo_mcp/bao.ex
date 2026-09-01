# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.Bao do
  @moduledoc """
  This app's identity in OpenBao, and the reads it makes with it.

  The listener requires and verifies a client certificate, so the certificate
  is the channel and the token is the authorization. Both are held in
  `:persistent_term` rather than read from the environment on each call, so
  `ArtifactsMMOMCP.Renew` can replace either one without a restart.

  A bao that cannot be reached is not fatal: the environment stays
  authoritative and the reason is logged. `.internal` names resolve to AAAA
  records only, so the connection is forced onto `:inet6`.
  """

  require Logger

  @key {__MODULE__, :identity}
  @secret_path "/v1/secret/data/artifacts-mmo/api"
  @env %{"token" => "ARTIFACTS_MMO_TOKEN", "mcp_auth_token" => "MCP_AUTH_TOKEN"}

  def load do
    case seed() do
      {:ok, _identity} -> apply_secret()
      {:skip, reason} -> log_skip(reason)
      {:error, reason} -> log_error(reason)
    end
  end

  def identity, do: :persistent_term.get(@key, nil)

  def configured?, do: identity() != nil

  @doc "Certificate expiry as a unix timestamp, or nil when bao is not configured."
  def cert_expiry do
    case identity() do
      nil -> nil
      %{cert_expiry: expiry} -> expiry
    end
  end

  @doc "Replace the client certificate after a re-issue."
  def put_certificate(cert_pem, key_pem, expiry) do
    with %{} = current <- identity(),
         {:ok, cert} <- pem_der(cert_pem, :cert),
         {:ok, key} <- pem_der(key_pem, :key) do
      options = Keyword.merge(current.tls, cert: cert, key: key)
      :persistent_term.put(@key, %{current | tls: options, cert_expiry: expiry})
      :ok
    else
      nil -> {:error, "bao is not configured"}
      other -> other
    end
  end

  def get(path), do: request(:get, path, nil)
  def post(path, body), do: request(:post, path, body)

  defp request(method, path, body) do
    case identity() do
      nil ->
        {:error, "bao is not configured"}

      %{addr: addr, token: token, tls: tls} ->
        opts =
          [
            method: method,
            url: String.trim_trailing(addr, "/") <> path,
            headers: [{"x-vault-token", token}],
            connect_options: [transport_opts: [:inet6 | tls]],
            receive_timeout: 10_000
          ] ++ if(body == nil, do: [], else: [json: body])

        case Req.request(opts) do
          {:ok, %Req.Response{status: status, body: response}} when status in 200..299 ->
            {:ok, response}

          {:ok, %Req.Response{status: status}} ->
            {:error, "HTTP #{status}"}

          {:error, exception} ->
            {:error, "unreachable: #{Exception.message(exception)}"}
        end
    end
  end

  defp apply_secret do
    case get(@secret_path) do
      {:ok, %{"data" => %{"data" => data}}} ->
        applied = put_env(data)
        Logger.info("bao: loaded #{Enum.join(applied, ", ")} from secret/artifacts-mmo/api")
        applied

      {:error, reason} ->
        log_error(reason)
    end
  end

  defp seed do
    addr = System.get_env("BAO_ADDR", "")
    token = System.get_env("BAO_TOKEN", "")

    cond do
      addr == "" ->
        {:skip, "BAO_ADDR unset"}

      token == "" ->
        {:skip, "BAO_TOKEN unset"}

      true ->
        with {:ok, cert_pem} <- decoded("BAO_CLIENT_CERT_B64"),
             {:ok, key_pem} <- decoded("BAO_CLIENT_KEY_B64"),
             {:ok, ca_pem} <- decoded("BAO_CA_CHAIN_B64"),
             {:ok, cert} <- pem_der(cert_pem, :cert),
             {:ok, key} <- pem_der(key_pem, :key),
             {:ok, cacerts} <- pem_ders(ca_pem) do
          tls = [
            verify: :verify_peer,
            cacerts: cacerts,
            cert: cert,
            key: key,
            server_name_indication: addr |> URI.parse() |> Map.get(:host) |> to_charlist(),
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]

          identity = %{addr: addr, token: token, tls: tls, cert_expiry: expiry_of(cert)}
          :persistent_term.put(@key, identity)
          {:ok, identity}
        end
    end
  end

  defp expiry_of(der) do
    {:Validity, _from, not_after} =
      der
      |> :public_key.pkix_decode_cert(:otp)
      |> then(fn {:OTPCertificate, tbs, _, _} -> elem(tbs, 5) end)

    case not_after do
      {:utcTime, time} -> to_unix(to_string(time), "20")
      {:generalTime, time} -> to_unix(to_string(time), "")
    end
  end

  defp to_unix(time, century) do
    <<y::binary-4, mo::binary-2, d::binary-2, h::binary-2, mi::binary-2, s::binary-2, _::binary>> =
      century <> time

    %DateTime{
      year: String.to_integer(y),
      month: String.to_integer(mo),
      day: String.to_integer(d),
      hour: String.to_integer(h),
      minute: String.to_integer(mi),
      second: String.to_integer(s),
      time_zone: "Etc/UTC",
      zone_abbr: "UTC",
      utc_offset: 0,
      std_offset: 0
    }
    |> DateTime.to_unix()
  end

  defp decoded(var) do
    case System.get_env(var, "") do
      "" ->
        {:error, "#{var} unset"}

      value ->
        case Base.decode64(value, ignore: :whitespace) do
          {:ok, pem} -> {:ok, pem}
          :error -> {:error, "#{var} is not base64"}
        end
    end
  end

  defp pem_der(pem, kind) do
    case :public_key.pem_decode(pem) do
      [{type, der, _} | _] when kind == :key -> {:ok, {type, der}}
      [{_type, der, _} | _] -> {:ok, der}
      [] -> {:error, "no PEM entry"}
    end
  end

  defp pem_ders(pem) do
    case Enum.map(:public_key.pem_decode(pem), fn {_type, der, _} -> der end) do
      [] -> {:error, "no PEM entry"}
      ders -> {:ok, ders}
    end
  end

  defp put_env(data) do
    applied =
      Enum.flat_map(@env, fn {key, var} ->
        case Map.get(data, key) do
          value when is_binary(value) and value != "" ->
            System.put_env(var, value)
            [var]

          _ ->
            []
        end
      end)

    case Map.get(data, "characters") do
      list when is_binary(list) and list != "" ->
        System.put_env(
          "ARTIFACTS_MMO_CHARACTER",
          list |> String.split(",") |> hd() |> String.trim()
        )

        applied ++ ["ARTIFACTS_MMO_CHARACTER"]

      _ ->
        applied
    end
  end

  defp log_skip(reason) do
    Logger.info("bao: not configured (#{reason}); using the environment as given")
    []
  end

  defp log_error(reason) do
    Logger.warning("bao: #{reason}; using the environment as given")
    []
  end
end
