# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.WorldTest do
  use ExUnit.Case, async: true

  test "the world page is served at / without a credential" do
    conn = Plug.Test.conn(:get, "/")
    conn = ArtifactsMMOMCP.Router.call(conn, ArtifactsMMOMCP.Router.init([]))
    assert conn.status == 200
    assert String.contains?(conn.resp_body, "World · Live")
  end

  test "/world stays as a 301 redirect so old links still land" do
    conn = Plug.Test.conn(:get, "/world")
    conn = ArtifactsMMOMCP.Router.call(conn, ArtifactsMMOMCP.Router.init([]))
    assert conn.status == 301
    assert Plug.Conn.get_resp_header(conn, "location") == ["/"]
  end
end
