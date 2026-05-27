#!/usr/bin/env python3
"""Extract the raw ARM64 Linux Image from a pmOS aarch64 vmlinuz.

The pmOS kernel on miatoll/sm7125 is a PE/COFF EFI zboot wrapper
(`MZ\\x00\\x00zimg...gzip...`) with a gzip-compressed Image inside.
Stock Android bootloaders cannot run the EFI wrapper, so for our custom
`fastboot boot` / `fastboot flash boot` flow we extract the inner Image
and feed it to mkbootimg.

We scan for the gzip magic (1F 8B 08) and decompress only the first stream
via zlib (gzip.decompress would error on the post-stream padding).

usage: extract-kernel-from-zboot.py <vmlinuz> <output Image>
"""
import io
import sys
import zlib


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    src, dst = sys.argv[1], sys.argv[2]
    with open(src, "rb") as f:
        data = f.read()

    idx = data.find(b"\x1f\x8b\x08")
    if idx < 0:
        print(f"ERROR: gzip magic not found in {src}", file=sys.stderr)
        return 1

    print(f"gzip magic at offset 0x{idx:x} of {len(data)} bytes total")

    dec = zlib.decompressobj(16 + zlib.MAX_WBITS)
    out = dec.decompress(data[idx:])
    out += dec.flush()

    with open(dst, "wb") as f:
        f.write(out)

    print(f"wrote {dst}: {len(out)} bytes")

    # Sanity-check ARM64 boot protocol magic at offset 0x38 ("ARM\x64")
    magic = out[0x38:0x3C]
    print(f"magic@0x38: {magic!r}  (expect: b'ARM\\\\x64')")
    if magic != b"ARM\x64":
        print("WARNING: ARM64 boot magic missing", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
