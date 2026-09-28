#!/usr/bin/env python3
"""Dev-time capture of a non-gameplay screen's tile cells (needs MAME output).

usage: capture_screen.py NAME CAM SPEC [...] [--band R0-R1] [--font] [--cells SPEC ...] [--not SPEC ...]
  SPEC  RECORDING.ram:FIRST-LAST   tools/diff/mame_record.lua recording (8KB per
                                   vblank handler: work RAM, then video RAM)
        scene:PREFIX:FIRST-LAST    tools/capture/scene_record.lua recording
                                   (PREFIX.bin per video frame + PREFIX.scroll)
Collects every (bg attr, bg tile, fg attr, fg tile) cell in the camera window
(player-view rows CAM..CAM+23, playfield columns) over the given frames, picks
a signature cell (an fg tile constant over the whole run, unusual elsewhere,
and never seen at that cell in the --not frames, e.g. other screens that
share the logo), and writes tools/data/screens/NAME.txt, which
tools/gen_screens.py turns into a tile set. Commit the .txt.

--cells SPEC ...: more frames whose cells the screen needs, left out of the
signature search (e.g. an opening that other screens share).

--font: the screen shows text that varies (names, scores): tools/gen_screens.py
adds every font character in each text colour it uses.

--band R0-R1: player rows R0..R1 hold background art that the arcade scrolls
(the cutscenes' characters; bg scroll register $F800, pixels along the
player-view x axis). Those rows are left out of the static cells; instead
every (left bg cell, right bg cell) pair the scroll brings into a cell is
listed, for pre-shifted tiles. A pair seen only at phase 0 has no right cell
(written ff ff). The band must never have foreground art over it.
"""
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REC = 8192
SCENE_REC = 4096 + 256 + 4096
BLANK_BG = 0x29


def load(spec):
    """-> list of (video RAM 4KB, bg scroll)"""
    if spec.startswith("scene:"):
        _, prefix, rng = spec.split(":")
        first, last = (int(x) for x in rng.split("-"))
        d = Path(prefix + ".bin").read_bytes()
        n = len(d) // SCENE_REC
        # scroll writes tagged frame f are in effect from record f-1 on (the
        # recorder dumps record i at the end of frame i+2)
        writes = {}
        for line in Path(prefix + ".scroll").read_text().splitlines():
            p = line.split()
            if p[0] in ("SNAP", "POKE"):
                continue
            if int(p[1], 16) >= 0xF800:
                writes.setdefault(int(p[0]), []).append(int(p[2], 16))
        out, y = [], 0
        for i in range(n):
            for v in writes.get(i + 1, []):
                y = v
            f = i + 2
            if first <= f <= last:
                out.append((d[i * SCENE_REC:i * SCENE_REC + 4096], y))
        return out
    path, rng = spec.rsplit(":", 1)
    first, last = (int(x) for x in rng.split("-"))
    d = Path(path).read_bytes()
    return [(d[h * REC + 4096:(h + 1) * REC], 0) for h in range(first, min(last + 1, len(d) // REC))]


def main():
    name, cam = sys.argv[1], int(sys.argv[2])
    args = sys.argv[3:]
    nots = args[args.index("--not") + 1:] if "--not" in args else []
    args = args[:args.index("--not")] if "--not" in args else args
    more = args[args.index("--cells") + 1:] if "--cells" in args else []
    args = args[:args.index("--cells")] if "--cells" in args else args
    font = "--font" in args
    args = [a for a in args if a != "--font"]
    band = None
    if "--band" in args:
        i = args.index("--band")
        band = tuple(int(x) for x in args[i + 1].split("-"))
        args = args[:i] + args[i + 2:]
    specs = args
    frames = []
    for spec in specs:
        frames += load(spec)
    extra_frames = []
    for spec in more:
        extra_frames += [(v, y, True) for v, y in load(spec)]
    frames = [(v, y, False) for v, y in frames] + extra_frames
    seen_elsewhere = set()
    for spec in nots:
        for v, _ in load(spec):
            seen_elsewhere.update((o, v[0xC00 + o]) for o in range(0x400))

    combos, pairs = Counter(), Counter()
    const = None
    for v, scroll, cells_only in frames:
        cells = {}
        for row in range(cam, cam + 24):
            c = 31 - row
            in_band = band and band[0] <= row <= band[1]
            for sx in range(24):
                o = (sx + 4) * 32 + c
                if in_band:
                    assert v[0xC00 + o] == BLANK_BG, f"foreground art over the band at row {row}"
                    rp = sx * 8 + 32 + scroll
                    r0, s = (rp >> 3) & 31, rp & 7
                    lo, ro = r0 * 32 + c, ((r0 + 1) & 31) * 32 + c
                    left = (v[lo], v[0x400 + lo])
                    right = (v[ro], v[0x400 + ro]) if s else (0xFF, 0xFF)
                    if left[1] == BLANK_BG and (not s or right[1] == BLANK_BG):
                        continue
                    pairs[left + right] += 1
                    continue
                k = (v[o], v[0x400 + o], v[0x800 + o], v[0xC00 + o])
                combos[k] += 1
                cells[o] = v[0xC00 + o]
        if not cells_only:
            const = cells if const is None else {o: t for o, t in const.items() if cells.get(o) == t}
    # signature: a constant fg tile that is not blank, dirt, tunnel or font
    const = {o: t for o, t in const.items() if (o, t) not in seen_elsewhere}
    cand = [(o, t) for o, t in const.items() if t >= 0xC0 or 0x40 <= t < 0x72]
    if not cand:
        cand = [(o, t) for o, t in const.items() if t not in (0x29, 0x77)]
    sig = sorted(cand, key=lambda ot: -ot[1])[0]
    out = ROOT / "tools" / "data" / "screens" / f"{name}.txt"
    lines = [f"# {name}: captured from {' '.join(Path(a).name for a in specs)}"
             + (f" (signature unseen in {' '.join(Path(a).name for a in nots)})" if nots else ""),
             f"cam {cam}", f"sig {sig[0]:03x} {sig[1]:02x}"]
    if font:
        lines.append("font")
    if band:
        lines.append(f"band {band[0]} {band[1]}")
        lines += [f"pair {a:02x} {b:02x} {c:02x} {e:02x} {n}" for (a, b, c, e), n in pairs.most_common()]
    lines += [f"{a:02x} {b:02x} {c:02x} {e:02x} {n}" for (a, b, c, e), n in combos.most_common()]
    out.write_text("\n".join(lines) + "\n")
    print(f"{name}: {len(combos)} cells, {len(pairs)} band pairs, signature cell ${sig[0]:03x} = "
          f"fg tile ${sig[1]:02x} -> {out}")


if __name__ == "__main__":
    main()
