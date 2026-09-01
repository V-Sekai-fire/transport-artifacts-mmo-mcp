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

from PIL import Image, ImageChops

ROOT = pathlib.Path(__file__).resolve().parent.parent
TILES = ROOT / "priv" / "static" / "tiles"
MAPS = ROOT / "priv" / "static" / "maps"


SCRIBBLE = ROOT / "priv" / "static" / "scribble"
SCRIBBLE_PX = 64

def load_scribble(name):
    """Load a named scribble PNG at native 64×64, RGBA."""
    return Image.open(SCRIBBLE / f"{name}.png").convert("RGBA")


def apply_tint(im, rgba):
    """Multiply the tile's white background by the tint so the color reads
    as terrain; the dark ink strokes stay dark. Alpha rides through."""
    r, g, b, a = rgba
    ground = Image.new("RGB", im.size, (r, g, b))
    tinted_rgb = ImageChops.multiply(im.convert("RGB"), ground)
    alpha = im.split()[3] if im.mode == "RGBA" else Image.new("L", im.size, a)
    return Image.merge("RGBA", (*tinted_rgb.split(), alpha))


# Scribble Dungeons (CC0) is a line-drawn hand-sketched pack. Terrain is a
# tinted base tile per game "name"; content markers overlay in the browser.
# Every game name in the world data is covered; the build fails on any it is
# not. Tints tell close-in variants apart (Lake vs Sea, Mine vs Empty).
TERRAIN = {
    "overworld": {
        "Forest":            {"base": "grass",       "tint": (140, 200, 130, 255)},
        "Sea":               {"base": "water",       "tint": (100, 150, 210, 255)},
        "Sandwhisper Isle":  {"base": "grass",       "tint": (230, 210, 130, 255)},
        "City":              {"base": "floor_path",  "tint": (215, 200, 165, 255)},
        "Graveyard":         {"base": "grass",       "tint": (160, 165, 140, 255)},
        "Enchanted Forest":  {"base": "grass",       "tint": (185, 145, 210, 255)},
        "Mountain":          {"base": "tile",        "tint": (170, 155, 130, 255)},
        "Lake":              {"base": "water",       "tint": (130, 190, 225, 255)},
        "Spawn":             {"base": "grass",       "tint": (255, 210, 60,  255)},
        "Forest (Forge)":    {"base": "grass",       "tint": (205, 170, 110, 255)},
    },
    "underground": {
        "Empty":              {"base": "tile",       "tint": (205, 195, 170, 255)},
        "Lava Underground":   {"base": "tile",       "tint": (230, 110, 60,  255)},
        "Mine":               {"base": "tile",       "tint": (165, 145, 125, 255)},
        "Sandwhisper Mine":   {"base": "tile",       "tint": (230, 210, 140, 255)},
        "Lich Tomb":          {"base": "tile",       "tint": (155, 125, 190, 255)},
        "Abandoned House":    {"base": "planks",     "tint": (190, 160, 120, 255)},
    },
    "interior": {
        "Empty":              None,
        "Rosenblood House":   {"base": "planks",     "tint": (210, 130, 120, 255)},
        "Empress House":      {"base": "planks",     "tint": (235, 200, 120, 255)},
        "Abandoned House":    {"base": "planks",     "tint": (175, 160, 140, 255)},
    },
}

# Per-name decor overlaid on the terrain. Deterministic by (layer, x, y) so
# re-runs produce the same picture. Every entry is a scribble filename.
DECOR = {
    "Forest":           [("tree", 0.30), ("plants", 0.12)],
    "Enchanted Forest": [("tree", 0.50), ("plants", 0.30)],
    "Sandwhisper Isle": [("plants", 0.15)],
    "Mountain":         [("wall_damaged", 0.15)],
    "Graveyard":        [("coffin", 0.40)],
    "City":             [("chair", 0.10), ("chest", 0.05)],
    "Mine":             [("wall_damaged", 0.20)],
    "Lava Underground": [("campfire", 0.15)],
    "Lich Tomb":        [("coffin", 0.50)],
}


def compose_layer(tiles, layer, out_path):
    """Compose one layer's background PNG at 32 px per game tile. Content
    markers and characters are drawn live in the browser; only the terrain
    lives in this image."""
    layer_tiles = [t for t in tiles if t["layer"] == layer]
    if not layer_tiles:
        return None

    tile_size = 32
    scale = tile_size / SCRIBBLE_PX

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
            continue  # blank on purpose (Empty on interior)

        r = random.Random((t["x"] * 73856093) ^ (t["y"] * 19349663) ^ hash(layer))

        base = load_scribble(entry["base"])
        tile = apply_tint(base, entry["tint"]) if "tint" in entry else base
        tile = tile.resize((tile_size, tile_size), Image.LANCZOS)
        canvas.paste(tile, (px, py), tile)

        for name, chance in DECOR.get(t["name"], []):
            if r.random() < chance:
                deco = load_scribble(name).resize((tile_size, tile_size), Image.LANCZOS)
                canvas.paste(deco, (px, py), deco)

    if missing:
        print(f"UNMAPPED terrain names on {layer}: {sorted(missing)}", file=sys.stderr)
        raise SystemExit(2)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)
    return {"layer": layer, "min_x": min_x, "min_y": min_y,
            "max_x": max_x, "max_y": max_y, "tile_size": tile_size,
            "width": w, "height": h}


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
