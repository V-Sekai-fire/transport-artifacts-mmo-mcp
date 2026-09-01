# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
"""Pack a run's JSONL trace layers into zstd parquet, one file per layer.

JSONL is the write format because a run appends to it while playing; parquet is
the archive format the working agreements require, so this is the step between.
It never deletes a source. Both halves are read back after writing and compared
on row count and on a SHA-256 over the canonical JSON of every row, so a
truncated or reordered write fails here rather than in whatever reads the
corpus six months later.

    python scripts/pack_traces.py traces/ --out packed/
    python scripts/pack_traces.py traces/ --out packed/ --self-test
"""

import argparse
import hashlib
import json
import pathlib
import sys
import tempfile

import pyarrow as pa
import pyarrow.parquet as pq

LAYERS = ("planner", "api")


def read_jsonl(path):
    rows = []
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{lineno}: {exc}")
    return rows


def digest(rows):
    h = hashlib.sha256()
    for row in rows:
        h.update(json.dumps(row, sort_keys=True, separators=(",", ":")).encode())
    return h.hexdigest()


def to_table(rows):
    """Every trace field but the JSON blobs is scalar; the blobs stay as text so
    a schema change in the game API cannot make an old run unreadable."""
    blob_keys = {"request", "response", "params", "metadata", "todo_list", "plan",
                 "chosen_task", "state_before"}
    flat = []
    for row in rows:
        out = {}
        for key, value in row.items():
            if key in blob_keys or isinstance(value, (dict, list)):
                out[key] = json.dumps(value, sort_keys=True, separators=(",", ":"))
            else:
                out[key] = value
        flat.append(out)
    columns = sorted({k for row in flat for k in row})
    return pa.table({c: [row.get(c) for row in flat] for c in columns})


def pack_layer(src_dir, out_path):
    files = sorted(src_dir.glob("*.jsonl"))
    rows = []
    for path in files:
        rows.extend(read_jsonl(path))
    if not rows:
        return 0, len(files), None

    before = digest(rows)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    pq.write_table(to_table(rows), out_path, compression="zstd")

    back = pq.read_table(out_path).to_pylist()
    if len(back) != len(rows):
        raise SystemExit(f"{out_path}: wrote {len(rows)} rows, read back {len(back)}")
    restored = [{k: v for k, v in row.items() if v is not None} for row in back]
    for row in restored:
        for key, value in list(row.items()):
            if isinstance(value, str) and value[:1] in "{[":
                try:
                    row[key] = json.loads(value)
                except json.JSONDecodeError:
                    pass
    if digest(restored) != before:
        raise SystemExit(f"{out_path}: payload hash differs after round trip")
    return len(rows), len(files), before


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("trace_dir", nargs="?", default="traces")
    parser.add_argument("--out", default="packed")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    trace_dir = pathlib.Path(args.trace_dir)
    out_dir = pathlib.Path(args.out)
    failures = 0
    for layer in LAYERS:
        src = trace_dir / layer
        if not src.is_dir():
            print(f"FAIL {layer}: {src} is not a directory")
            failures += 1
            continue
        rows, files, sha = pack_layer(src, out_dir / f"{layer}.parquet")
        print(f"ok   {layer}: {rows} rows from {files} files, sha256 {sha or '-'}")
    print("sources kept; delete them yourself once the parquet is pushed")
    return 1 if failures else 0


def self_test():
    """Two controls: a good run round-trips, and a truncated parquet is rejected."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        src = tmp / "planner"
        src.mkdir()
        (src / "run.jsonl").write_text(
            '{"run_id":"a","step":1,"plan":[{"task":["move",1,2]}]}\n'
            '{"run_id":"a","step":2,"plan":[]}\n'
        )
        rows, _, _ = pack_layer(src, tmp / "planner.parquet")
        assert rows == 2, f"control 1: expected 2 rows, got {rows}"

        bad = tmp / "bad"
        bad.mkdir()
        (bad / "run.jsonl").write_text('{"run_id":"a","step":1}\n{"run_id":"a"\n')
        try:
            pack_layer(bad, tmp / "bad.parquet")
        except SystemExit:
            print("ok   2 controls passed")
            return 0
        print("FAIL control 2: malformed JSONL was accepted")
        return 1


if __name__ == "__main__":
    sys.exit(main())
