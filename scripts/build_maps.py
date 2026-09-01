# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
"""Compose per-layer background PNGs from the game's tile inventory + Kenney art.

The map does not change during play, so the terrain is pre-composed and
committed. Content markers and characters draw on top of these images live in
the browser, so the game's live state stays interactive.

CC0 tile art: Kenney Tiny Town, Tiny Battle, Tiny Dungeon
(https://kenney.nl/, LICENSE in priv/static/tiles/).

Usage: python scripts/build_maps.py [--world path/to/world.json]

The mapping table below is exhaustive against the game's 18 unique tile names
across three layers, and self-tests do NOT ship — they run every invocation
and fail the build when a name in world.json is not covered.
"""

import argparse
import json
import pathlib
import random
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
TILES = ROOT / "priv" / "static" / "tiles"
MAPS = ROOT / "priv" / "static" / "maps"


def load_tile(pack, index):
    path = TILES / pack / f"tile_{index:04d}.png"
    return Image.open(path).convert("RGBA")


# All 18 terrain names in the world data, mapped to a base tile plus optional
# variation choices. `alt` is a set of tiles picked deterministically per (x,y)
# so a big grass field is not one flat rectangle.
TERRAIN = {
    "overworld": {
        "Forest":            {"base": ("town", 0),  "alt": [("town", 0), ("town", 1)]},
        "Sea":               {"base": ("battle", 55)},
        "Sandwhisper Isle":  {"base": ("town", 12), "alt": [("town", 12), ("town", 13), ("town", 14)]},
        "City":              {"base": ("town", 43)},
        "Graveyard":         {"base": ("town", 0)},
        "Enchanted Forest":  {"base": ("town", 0),  "tint": (170, 130, 200, 90)},
        "Mountain":          {"base": ("town", 12), "alt": [("town", 12), ("town", 13)]},
        "Lake":              {"base": ("battle", 55)},
        "Spawn":             {"base": ("town", 2)},
        "Forest (Forge)":    {"base": ("town", 0)},
    },
    "underground": {
        "Empty":              {"base": ("dungeon", 0), "alt": [("dungeon", 0), ("dungeon", 1)]},
        "Lava Underground":   {"base": ("dungeon", 0), "tint": (210, 80, 40, 120)},
        "Mine":               {"base": ("dungeon", 12), "alt": [("dungeon", 12), ("dungeon", 13)]},
        "Sandwhisper Mine":   {"base": ("dungeon", 48), "alt": [("dungeon", 48), ("dungeon", 49), ("dungeon", 50)]},
        "Lich Tomb":          {"base": ("dungeon", 12), "tint": (140, 100, 180, 120)},
        "Abandoned House":    {"base": ("town", 72)},
    },
    "interior": {
        "Empty":              None,
        "Rosenblood House":   {"base": ("dungeon", 24)},
        "Empress House":      {"base": ("dungeon", 48)},
        "Abandoned House":    {"base": ("town", 72)},
    },
}

# What overlays on a tile after the terrain: trees on forest, small scatter on
# grass, etc. Keyed by name; each entry is a list of (pack, tile, chance).
# Deterministic by (x, y) so re-running gives the same picture.
DECOR = {
    "Forest":           [("town", 4, 0.35), ("town", 5, 0.15), ("town", 3, 0.10)],
    "Enchanted Forest": [("town", 11, 0.7),  ("town", 5, 0.3)],
    "Sandwhisper Isle": [("town", 18, 0.10), ("town", 20, 0.05)],
    "Mountain":         [("town", 5, 0.15)],
    "Graveyard":        [("dungeon", 122, 0.4), ("dungeon", 121, 0.3)],
    "Mine":             [("dungeon", 122, 0.15)],
    "Lava Underground": [("dungeon", 29, 0.15)],
    "City":             [("town", 44, 0.05)],
}


def compose_layer(tiles, layer, out_path, tile_size=16):
    layer_tiles = [t for t in tiles if t["layer"] == layer]
    if not layer_tiles:
        return None

    xs = [t["x"] for t in layer_tiles]
    ys = [t["y"] for t in layer_tiles]
    min_x, min_y = min(xs), min(ys)
    max_x, max_y = max(xs), max(ys)
    w = (max_x - min_x + 1) * tile_size
    h = (max_y - min_y + 1) * tile_size

    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    missing = set()

    for t in layer_tiles:
        px = (t["x"] - min_x) * tile_size
        py = (t["y"] - min_y) * tile_size

        entry = TERRAIN[layer].get(t["name"], "MISS")
        if entry == "MISS":
            missing.add(t["name"])
            continue
        if entry is None:
            continue  # deliberately blank (Empty on interior)

        # A cheap PRNG that returns the same alt for the same (layer, x, y).
        r = random.Random((t["x"] * 73856093) ^ (t["y"] * 19349663) ^ hash(layer))

        base = entry["base"]
        if "alt" in entry:
            base = r.choice(entry["alt"])
        tile = load_tile(*base)

        if "tint" in entry:
            tint_layer = Image.new("RGBA", tile.size, entry["tint"])
            tile = Image.alpha_composite(tile, tint_layer)

        canvas.paste(tile, (px, py), tile)

        for pack, idx, chance in DECOR.get(t["name"], []):
            if r.random() < chance:
                deco = load_tile(pack, idx)
                canvas.paste(deco, (px, py), deco)

    if missing:
        print(f"UNMAPPED terrain names on {layer}: {sorted(missing)}", file=sys.stderr)
        raise SystemExit(2)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)
    meta = {"layer": layer, "min_x": min_x, "min_y": min_y,
            "max_x": max_x, "max_y": max_y, "tile_size": tile_size,
            "width": w, "height": h}
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--world", default=None,
                    help="path to a captured GET /api/world response")
    args = ap.parse_args()

    if args.world:
        world = json.load(open(args.world))
    else:
        import urllib.request
        world = json.load(urllib.request.urlopen("https://watch.chibifire.com/api/world"))

    metas = {}
    for layer in ("overworld", "underground", "interior"):
        out = MAPS / f"{layer}.png"
        meta = compose_layer(world["tiles"], layer, out)
        if meta:
            metas[layer] = meta
            print(f"ok  {layer}: {meta['width']}×{meta['height']} px  -> {out.relative_to(ROOT)}")

    (MAPS / "meta.json").write_text(json.dumps(metas, indent=2))
    print(f"wrote {MAPS.relative_to(ROOT)}/meta.json")


if __name__ == "__main__":
    main()
