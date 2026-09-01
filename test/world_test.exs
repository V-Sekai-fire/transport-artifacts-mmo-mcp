# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.WorldTest do
  use ExUnit.Case, async: true

  test "the router serves /world without a credential" do
    conn = Plug.Test.conn(:get, "/world")
    conn = ArtifactsMMOMCP.Router.call(conn, ArtifactsMMOMCP.Router.init([]))
    assert conn.status == 200
    assert String.contains?(conn.resp_body, "World · Live")
  end
end
