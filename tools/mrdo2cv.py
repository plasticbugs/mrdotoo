#!/usr/bin/env python3
"""Mr. Do! for the ColecoVision + Super Game Module, built from your own
copy of the arcade game.

    python3 mrdo2cv.py ROMSET [-o mrdo_cv.rom] [-p mrdo_cv.bps]

ROMSET is MAME's `mrdo` set (Mr. Do!, Universal 1982): its zip, a folder
holding the zip (such as MAME's roms folder), or a folder of its files.
Files are found by checksum, so their names do not matter. Needs Python 3.6
or later and nothing else.

The cartridge runs the arcade's own program on the ColecoVision, so it is
made from your arcade ROMs: the patch (mrdo_cv.bps, next to this script)
holds the port's code and graphics and copies the arcade's bytes from your
files. It is a standard BPS patch, so other patchers (Flips, RomPatcher.js)
can apply it too, to the program ROMs joined in this order:
a4-01 c4-02 e4-03 f4-04 (32 KB).

The result is a 512 KB MegaCart image. It needs a ColecoVision with the
Super Game Module (and a flash cart that takes MegaCart images); in
openMSX: openmsx -machine ColecoVision_SGM -carta mrdo_cv.rom
-romtype ColecoMegaCart
"""
import argparse
import hashlib
import os
import sys
import zipfile
import zlib

# The patch source: these files of MAME's mrdo set, joined in this order
# (name in MAME, size, CRC32, SHA-1).
SOURCE = [
    ("a4-01.bin", 0x2000, 0x03DCFBA2, "c15e3d0c4225e0ca120bcd28aca39632575f8e11"),
    ("c4-02.bin", 0x2000, 0x0ECDD39C, "c64b3363593911a676c647bf3dba8fe063fcb0de"),
    ("e4-03.bin", 0x2000, 0x358F5DC2, "9fed1f5d1d04935d1b77687c8b2f3bfce970dc08"),
    ("f4-04.bin", 0x2000, 0xF4190CFC, "24f5125d900f944294d4eda068b710c8f1c6d39f"),
]
SIZES = {size for _, size, _, _ in SOURCE}
MAX_ZIP = 4 << 20          # zips bigger than this are not a Mr. Do! set


def fail(msg):
    sys.exit("mrdo2cv: " + msg)


# ---- finding the romset files ------------------------------------------

def from_zip(path, found):
    try:
        with zipfile.ZipFile(path) as z:
            for info in z.infolist():
                if info.file_size in SIZES:
                    found.setdefault(info.CRC, lambda z=path, n=info.filename: read_member(z, n))
    except (zipfile.BadZipFile, OSError):
        pass


def read_member(path, name):
    with zipfile.ZipFile(path) as z:
        return z.read(name)


def from_file(path, found):
    with open(path, "rb") as f:
        data = f.read()
    found.setdefault(zlib.crc32(data) & 0xFFFFFFFF, lambda d=data: d)


def scan(path):
    """CRC32 -> loader for every candidate file under path."""
    found = {}
    if os.path.isfile(path):
        if zipfile.is_zipfile(path):
            from_zip(path, found)
        elif os.path.getsize(path) in SIZES:
            from_file(path, found)
        return found
    if not os.path.isdir(path):
        fail("%s: no such file or folder" % path)
    # a MAME roms folder: look at its mrdo set first, and only there if it has one
    for sub in ("mrdo.zip", "mrdo"):
        p = os.path.join(path, sub)
        if os.path.exists(p):
            found.update(scan(p))
    if all(crc in found for _, _, crc, _ in SOURCE):
        return found
    for root, dirs, files in os.walk(path):
        dirs.sort()
        for name in sorted(files):
            p = os.path.join(root, name)
            try:
                size = os.path.getsize(p)
            except OSError:
                continue
            if size in SIZES:
                from_file(p, found)
            elif name.lower().endswith(".zip") and size <= MAX_ZIP:
                from_zip(p, found)
    return found


def source_from(path):
    found = scan(path)
    parts, missing = [], []
    for name, size, crc, sha1 in SOURCE:
        data = found[crc]() if crc in found else None
        if data is None or len(data) != size or hashlib.sha1(data).hexdigest() != sha1:
            missing.append("  %-10s %5d bytes  CRC %08x" % (name, size, crc))
        else:
            parts.append(data)
    if missing:
        fail("%s does not hold these files of MAME's mrdo set (Mr. Do!, Universal):\n%s\n"
             "Clones (mrdot, mrdofix, mrlo, mrdu, mrdoy, yankeedo) have a different program;\n"
             "the parent set, mrdo, is needed. A .7z set must be unpacked first."
             % (path, "\n".join(missing)))
    return b"".join(parts)


# ---- BPS (byuu's patch format) -----------------------------------------

def crc32(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def bps_apply(patch, source):
    """The patched file, after checking the patch, source and result CRCs.
    Returns (target, metadata)."""
    if patch[:4] != b"BPS1" or len(patch) < 16:
        fail("the patch is not a BPS file")
    if crc32(patch[:-4]) != int.from_bytes(patch[-4:], "little"):
        fail("the patch file is damaged (checksum mismatch)")
    pos = 4

    def num():
        nonlocal pos
        data, shift = 0, 1
        while True:
            x = patch[pos]
            pos += 1
            data += (x & 0x7F) * shift
            if x & 0x80:
                return data
            shift <<= 7
            data += shift

    src_size, tgt_size, meta_size = num(), num(), num()
    meta = patch[pos:pos + meta_size]
    pos += meta_size
    if src_size != len(source) or crc32(source) != int.from_bytes(patch[-12:-8], "little"):
        fail("the romset files do not match the patch's source")
    out = bytearray()
    src_rel = tgt_rel = 0
    end = len(patch) - 12
    while pos < end:
        data = num()
        cmd, length = data & 3, (data >> 2) + 1
        if cmd == 0:                            # SourceRead
            out += source[len(out):len(out) + length]
        elif cmd == 1:                          # TargetRead
            out += patch[pos:pos + length]
            pos += length
        else:
            off = num()
            off = -(off >> 1) if off & 1 else off >> 1
            if cmd == 2:                        # SourceCopy
                src_rel += off
                out += source[src_rel:src_rel + length]
                src_rel += length
            else:                               # TargetCopy (may overlap itself)
                tgt_rel += off
                while length:
                    n = min(length, len(out) - tgt_rel)
                    out += out[tgt_rel:tgt_rel + n]
                    tgt_rel += n
                    length -= n
    if len(out) != tgt_size or crc32(out) != int.from_bytes(patch[-8:-4], "little"):
        fail("patching went wrong: the result does not match the patch's checksum")
    return bytes(out), meta.decode("utf-8", "replace")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(
        description="Build the ColecoVision + SGM Mr. Do! cartridge from MAME's mrdo romset.")
    ap.add_argument("romset", help="mrdo.zip, a folder holding it, or a folder of its files")
    ap.add_argument("-o", "--output", default="mrdo_cv.rom", help="cartridge image to write (default mrdo_cv.rom)")
    ap.add_argument("-p", "--patch", default=os.path.join(here, "mrdo_cv.bps"),
                    help="the patch (default: mrdo_cv.bps next to this script)")
    args = ap.parse_args()
    try:
        with open(args.patch, "rb") as f:
            patch = f.read()
    except OSError as e:
        fail("cannot read the patch: %s" % e)
    rom, meta = bps_apply(patch, source_from(args.romset))
    with open(args.output, "wb") as f:
        f.write(rom)
    if meta:
        print(meta)
    print("wrote %s (%d KB, SHA-1 %s)" % (args.output, len(rom) // 1024, hashlib.sha1(rom).hexdigest()))


if __name__ == "__main__":
    main()
