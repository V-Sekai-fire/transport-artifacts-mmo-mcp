# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.BaoTest do
  use ExUnit.Case, async: false

  alias ArtifactsMMOMCP.{Bao, Renew}

  @fixture "test/fixtures/expiry-cert.pem"
  @fixture_expiry 2_133_826_975

  setup do
    :persistent_term.erase({Bao, :identity})

    for v <- ~w(BAO_ADDR BAO_TOKEN BAO_CLIENT_CERT_B64 BAO_CLIENT_KEY_B64 BAO_CA_CHAIN_B64),
        do: System.delete_env(v)

    :ok
  end

  defp configure(overrides \\ %{}) do
    pem = File.read!(@fixture) |> Base.encode64()

    %{
      "BAO_ADDR" => "https://weftspun-bao.internal:8200",
      "BAO_TOKEN" => "s.test",
      "BAO_CLIENT_CERT_B64" => pem,
      "BAO_CLIENT_KEY_B64" => key_pem(),
      "BAO_CA_CHAIN_B64" => pem
    }
    |> Map.merge(overrides)
    |> Enum.each(fn {k, v} -> System.put_env(k, v) end)
  end

  defp key_pem do
    der =
      {:namedCurve, :secp256r1}
      |> :public_key.generate_key()
      |> then(&:public_key.der_encode(:ECPrivateKey, &1))

    :public_key.pem_encode([{:ECPrivateKey, der, :not_encrypted}]) |> Base.encode64()
  end

  test "an unconfigured bao is skipped, not fatal" do
    assert Bao.load() == []
    refute Bao.configured?()
  end

  test "a configured identity parses the certificate's expiry" do
    configure()
    Bao.load()
    assert Bao.configured?()
    assert Bao.cert_expiry() == @fixture_expiry
  end

  test "base64 that is not base64 is refused rather than half-applied" do
    configure(%{"BAO_CLIENT_CERT_B64" => "not base64!!"})
    assert Bao.load() == []
    refute Bao.configured?()
  end

  test "renewal status reports an unconfigured identity" do
    assert %{running: true, configured: false, cert_expires_at: nil} = Renew.status()
  end
end
