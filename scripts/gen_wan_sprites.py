# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
"""Generate scribble-style content sprites for every game code that currently
renders as a word label, using Wan 2.1's text-to-image path.

The world page reads `/static/wan/manifest.json` and silently swaps a word
label for `/static/wan/<type>-<code>.png` whenever that key is listed. So this
script never touches the browser code — it fills a directory, appends to a
manifest, and every generated sprite becomes live on the next page load.

Usage (GPU required for the real run):

    python scripts/gen_wan_sprites.py --world <path> --list-missing
    python scripts/gen_wan_sprites.py --world <path> --dry-run
    python scripts/gen_wan_sprites.py --world <path> --codes monster:goblin
    python scripts/gen_wan_sprites.py --world <path>              # all missing

Runs the Wan-VACE checkout at 3-interactor/wan-vace-upstream. T2I needs 8 GB+
VRAM and is not runnable on this laptop's MPS in full precision; use the local
CUDA box or rent a RunPod per CLAUDE.md.
"""

import argparse, json, os, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WAN_DIR = ROOT / "priv" / "static" / "wan"
MANIFEST = WAN_DIR / "manifest.json"
WAN_UPSTREAM = ROOT.parent.parent / "3-interactor" / "wan-vace-upstream"


def word_label_codes(world):
    """Every (content_type, content_code) that renders as a word today, in
    step with the world.html mapping."""
    covered = {
        "bank":          lambda c: c == "bank",
        "grand_exchange": lambda _: False,
        "raid":          lambda _: True,
        "monster":       lambda c: bool(re.search(r"dragon", c)),
        "resource":      lambda c: bool(re.search(r"_tree|_wood|mushroom|glowstem|nettle|sunflower|plant", c)),
        "workshop":      lambda c: c in {"mining", "woodcutting", "weaponcrafting", "gearcrafting", "alchemy"},
        "tasks_master":  lambda _: False,
        "npc":           lambda _: False,
    }
    seen, out = set(), []
    for t in world["tiles"]:
        ct, cc = t.get("content_type"), t.get("content_code")
        if not ct or ct not in covered or covered[ct](cc or ""):
            continue
        key = (ct, cc)
        if key in seen:
            continue
        seen.add(key)
        out.append(key)
    return out


def prompt_for(ct, cc):
    label = (cc or "").replace("_", " ")
    hint = {
        "monster":       f"a {label}, a top-down game monster icon",
        "resource":      f"a {label}, a top-down gatherable resource",
        "npc":           f"a {label}, a top-down NPC character",
        "workshop":      f"a {label} workshop tool, top-down game icon",
        "grand_exchange": "a grand-exchange market stall, top-down game icon",
        "tasks_master":  "a task master with a scroll, top-down game icon",
    }.get(ct, f"a {label}")
    return (
        f"Hand-drawn scribble line-art of {hint}, black outline on cream "
        "background, sketchbook style, minimal shading, top-down 64x64 game "
        "asset, matching Kenney Scribble Dungeons"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--world", required=True)
    ap.add_argument("--codes", nargs="*", default=None)
    ap.add_argument("--list-missing", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    world = json.load(open(args.world))
    codes = word_label_codes(world)
    if args.codes:
        wanted = {tuple(c.split(":", 1)) for c in args.codes}
        codes = [c for c in codes if c in wanted]

    if args.list_missing:
        for ct, cc in codes:
            print(f"{ct}:{cc}")
        print(f"# {len(codes)} codes without art", file=sys.stderr)
        return 0

    if not WAN_UPSTREAM.exists() and not args.dry_run:
        print(f"Wan upstream not at {WAN_UPSTREAM}; run `repo sync`.", file=sys.stderr)
        return 2

    WAN_DIR.mkdir(parents=True, exist_ok=True)
    manifest = set(json.loads(MANIFEST.read_text()) if MANIFEST.exists() else [])

    for ct, cc in codes:
        key = f"{ct}-{cc}"
        out = WAN_DIR / f"{key}.png"
        prompt = prompt_for(ct, cc)
        print(f"{key:40}  <- {prompt}")
        if args.dry_run:
            continue

        # Wan-VACE's generate.py takes a task, size, prompt, save path.
        # The caller controls checkpoint dir and any offload flags via env,
        # so the same command works on 8 GB (with --t5_cpu --offload) and
        # on a rented larger card.
        r = subprocess.run(
            [sys.executable, str(WAN_UPSTREAM / "generate.py"),
             "--task", "t2i-14B", "--size", "1024*1024",
             "--prompt", prompt, "--save_file", str(out)],
            cwd=WAN_UPSTREAM, env=os.environ.copy(),
        )
        if r.returncode != 0:
            print(f"  FAILED (exit {r.returncode}); skipping", file=sys.stderr)
            continue
        manifest.add(key)
        MANIFEST.write_text(json.dumps(sorted(manifest), indent=2))

    print(f"manifest now lists {len(manifest)} sprites -> {MANIFEST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
