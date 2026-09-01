# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.Server do
  @moduledoc """
  MCP tools for playing ArtifactsMMO, shaped so a taskweft RECTGTN domain can
  drive them: every action tool takes `run_id` and `step`, and `record_plan`
  writes the planner entry those two fields join to.

  A tool call with no `run_id` still plays the game and writes no trace, which
  is what interactive probing wants; a run that should have been recorded and
  was not is therefore visible as an empty file rather than as silence.
  """

  use ExMCP.Server.Handler
  use ExMCP.Server.DSL, name: "artifacts-mmo-mcp"

  alias ArtifactsMMOMCP.{Client, Trace}

  tool "start_run", "Open a trace run and return its run_id" do
    param(:character, :string, required: false, description: "Character this run plays")
    param(:domain, :string, required: false, description: "taskweft domain name driving the run")
    param(:planner, :string, required: false, description: "taskweft MCP endpoint used")
    param(:note, :string, required: false, description: "Free-text note stored with the run")

    run(fn args, state ->
      run_id = Trace.start_run(Map.new(args, fn {k, v} -> {to_string(k), v} end))
      {:ok, Jason.encode!(%{"run_id" => run_id}), state}
    end)
  end

  tool "record_plan", "Record one taskweft plan call as the planner layer of a run" do
    param(:run_id, :string, required: true, description: "Run this plan belongs to")
    param(:step, :integer, required: true, description: "Step index, joins to the action taken")
    param(:todo_list, :object, required: false, description: "todo_list handed to the planner")
    param(:plan, {:array, :object}, required: false, description: "Plan taskweft returned")
    param(:chosen_task, :object, required: false, description: "Task actually executed")
    param(:state_before, :object, required: false, description: "Character state the plan saw")
    param(:latency_ms, :integer, required: false, description: "Planner round-trip in ms")

    run(fn args, state ->
      Trace.plan_step(Map.new(args, fn {k, v} -> {to_string(k), v} end))
      {:ok, "recorded", state}
    end)
  end

  tool "character", "Read a character's current state" do
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run to trace this read into")
    param(:step, :integer, required: false, description: "Step index")

    run(fn args, state ->
      name = character(args)
      reply(Client.get("/characters/#{name}", [], args[:run_id], args[:step]), state)
    end)
  end

  tool "map_at", "Read the map tile at a position on a layer" do
    param(:layer, :string, required: true, description: "Map layer, e.g. overworld")
    param(:x, :integer, required: true, description: "Tile x")
    param(:y, :integer, required: true, description: "Tile y")
    param(:run_id, :string, required: false, description: "Run to trace this read into")
    param(:step, :integer, required: false, description: "Step index")

    run(fn args, state ->
      path = "/maps/#{args.layer}/#{args.x}/#{args.y}"
      reply(Client.get(path, [], args[:run_id], args[:step]), state)
    end)
  end

  tool "catalog", "List game data: items, monsters, resources, maps, or tasks" do
    param(:collection, :string,
      required: true,
      description: "One of items, monsters, resources, maps, tasks/list, npcs/items"
    )

    param(:query, :object,
      required: false,
      description: "Query parameters, e.g. {\"craft_skill\": \"weaponcrafting\", \"page\": 1}"
    )

    param(:run_id, :string, required: false, description: "Run to trace this read into")
    param(:step, :integer, required: false, description: "Step index")

    run(fn args, state ->
      params = args |> Map.get(:query, %{}) |> Enum.to_list()
      reply(Client.get("/#{args.collection}", params, args[:run_id], args[:step]), state)
    end)
  end

  tool "bank_items", "List the items held in the account bank" do
    param(:run_id, :string, required: false, description: "Run to trace this read into")
    param(:step, :integer, required: false, description: "Step index")

    run(fn args, state ->
      reply(Client.get("/my/bank/items", [], args[:run_id], args[:step]), state)
    end)
  end

  tool "move", "Move the character to a position" do
    param(:x, :integer, required: false, description: "Destination x")
    param(:y, :integer, required: false, description: "Destination y")
    param(:map_id, :integer, required: false, description: "Destination map id, instead of x/y")
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state ->
      act(args, "move", take(args, [:x, :y, :map_id]), state)
    end)
  end

  tool "fight", "Fight the monster on the character's current tile" do
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "fight", %{}, state) end)
  end

  tool "gather", "Gather the resource on the character's current tile" do
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "gathering", nil, state) end)
  end

  tool "rest", "Rest to restore hit points" do
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "rest", nil, state) end)
  end

  tool "craft", "Craft an item at the workshop on the current tile" do
    param(:code, :string, required: true, description: "Item code to craft")
    param(:quantity, :integer, required: false, description: "How many, default 1")
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "crafting", take(args, [:code, :quantity]), state) end)
  end

  tool "recycle", "Recycle a crafted item back into materials" do
    param(:code, :string, required: true, description: "Item code to recycle")
    param(:quantity, :integer, required: false, description: "How many, default 1")
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "recycling", take(args, [:code, :quantity]), state) end)
  end

  tool "use_item", "Use a consumable from the inventory" do
    param(:code, :string, required: true, description: "Item code")
    param(:quantity, :integer, required: true, description: "How many")
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "use", take(args, [:code, :quantity]), state) end)
  end

  tool "equip", "Equip items into slots" do
    param(:items, {:array, :object},
      required: true,
      description: "Up to 20 of {\"code\": string, \"slot\": string, \"quantity\": integer}"
    )

    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "equip", args.items, state) end)
  end

  tool "unequip", "Unequip items from slots" do
    param(:items, {:array, :object},
      required: true,
      description: "Up to 20 of {\"slot\": string, \"quantity\": integer}"
    )

    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "unequip", args.items, state) end)
  end

  tool "bank_deposit", "Deposit items into the account bank" do
    param(:items, {:array, :object},
      required: true,
      description: "Up to 20 of {\"code\": string, \"quantity\": integer}"
    )

    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "bank/deposit/item", args.items, state) end)
  end

  tool "bank_withdraw", "Withdraw items from the account bank" do
    param(:items, {:array, :object},
      required: true,
      description: "Up to 20 of {\"code\": string, \"quantity\": integer}"
    )

    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "bank/withdraw/item", args.items, state) end)
  end

  tool "task_new", "Accept a new task from the task master on the current tile" do
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "task/new", nil, state) end)
  end

  tool "task_complete", "Complete the current task and take its reward" do
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "task/complete", nil, state) end)
  end

  tool "npc_buy", "Buy an item from the NPC merchant on the current tile" do
    param(:code, :string, required: true, description: "Item code")
    param(:quantity, :integer, required: true, description: "How many")
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "npc/buy", take(args, [:code, :quantity]), state) end)
  end

  tool "npc_sell", "Sell an item to the NPC merchant on the current tile" do
    param(:code, :string, required: true, description: "Item code")
    param(:quantity, :integer, required: true, description: "How many")
    param(:name, :string, required: false, description: "Character name")
    param(:run_id, :string, required: false, description: "Run this action belongs to")
    param(:step, :integer, required: false, description: "Step index, joins to the plan")

    run(fn args, state -> act(args, "npc/sell", take(args, [:code, :quantity]), state) end)
  end

  defp act(args, action_path, body, state) do
    case character(args) do
      "" ->
        {:error, "no character: pass name, or set ARTIFACTS_MMO_CHARACTER", state}

      name ->
        name
        |> Client.action(action_path, body, args[:run_id], args[:step])
        |> reply(state)
    end
  end

  defp reply({:ok, body}, state), do: {:ok, Jason.encode!(body), state}
  defp reply({:error, reason}, state), do: {:error, Client.describe_error(reason), state}

  defp character(args), do: Map.get(args, :name) || Client.default_character()

  defp take(args, keys) do
    keys
    |> Enum.flat_map(fn key ->
      case Map.get(args, key) do
        nil -> []
        value -> [{to_string(key), value}]
      end
    end)
    |> Map.new()
  end
end
