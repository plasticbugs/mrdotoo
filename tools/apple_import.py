#!/usr/bin/env python3
"""Apple Lab saves -> tools/data/apples.json (read by tools/gen_tiles.py).

The lab (artifacts/23-apple-lab, https://claude.ai/artifact/6VV9ryyWC2WryMR58mnwrK)
saves one document per level look in its `apples` collection: {pixels:
256 TMS colours, row-major 16x16 player view, pair: "aa/tt" dirt attr/tile,
...}. Claude exports them with the ArtifactData tool (list, out_dir=DIR);
this merges DIR/apples/*.json into the design file.
usage: apple_import.py DIR"""
import json
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent / "data" / "apples.json"


def main():
    designs = json.loads(OUT.read_text()) if OUT.exists() else {}
    n = 0
    for f in sorted(Path(sys.argv[1]).rglob("*.json")):
        doc = json.loads(f.read_text())
        doc = doc.get("data", doc)
        px, pair = doc.get("pixels"), doc.get("pair")
        if not (isinstance(px, list) and len(px) == 256 and isinstance(pair, str)):
            print(f"skip {f.name}: no pixels/pair")
            continue
        assert all(isinstance(c, int) and 1 <= c <= 15 for c in px), f"{f.name}: bad colour"
        for y in range(16):                 # the TMS9918 rule the lab enforces
            for h in (0, 8):
                assert len(set(px[y * 16 + h:y * 16 + h + 8])) <= 2, f"{f.name}: row {y} has 3+ colours"
        designs[pair] = px
        n += 1
    OUT.write_text(json.dumps(designs, indent=0) + "\n")
    print(f"{n} designs imported -> {OUT} ({len(designs)} in all)")


if __name__ == "__main__":
    main()
