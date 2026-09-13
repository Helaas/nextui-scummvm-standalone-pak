#!/usr/bin/env python3
"""Zero out DT_RPATH/DT_RUNPATH in an ELF64 binary by pointing the entry at the
empty string in .dynstr. Used because the toolchain image has no patchelf, and
the sysroot libraries carry RPATHs that point at the vendor's build machine."""
import struct
import sys


def strip(path):
    with open(path, "r+b") as f:
        data = bytearray(f.read())

    if data[:4] != b"\x7fELF" or data[4] != 2:
        return False

    endian = "<" if data[5] == 1 else ">"
    e_shoff = struct.unpack_from(endian + "Q", data, 0x28)[0]
    e_shentsize = struct.unpack_from(endian + "H", data, 0x3A)[0]
    e_shnum = struct.unpack_from(endian + "H", data, 0x3C)[0]
    e_shstrndx = struct.unpack_from(endian + "H", data, 0x3E)[0]

    def section(i):
        off = e_shoff + i * e_shentsize
        (name, _type, _flags, _addr, offset, size, _link, _info, _align,
         _entsize) = struct.unpack_from(endian + "IIQQQQIIQQ", data, off)
        return name, offset, size

    _, shstr_off, _ = section(e_shstrndx)

    def secname(nameoff):
        start = shstr_off + nameoff
        end = data.index(b"\0", start)
        return bytes(data[start:end]).decode()

    dynamic = None
    dynstr = None
    for i in range(e_shnum):
        name, offset, size = section(i)
        section_name = secname(name)
        if section_name == ".dynamic":
            dynamic = (offset, size)
        elif section_name == ".dynstr":
            dynstr = (offset, size)

    if dynamic is None or dynstr is None:
        return False

    if data[dynstr[0]] == 0:
        empty_off = 0
    else:
        empty_off = data.index(b"\0", dynstr[0]) - dynstr[0]

    changed = False
    for j in range(dynamic[1] // 16):
        off = dynamic[0] + j * 16
        tag, _val = struct.unpack_from(endian + "qQ", data, off)
        if tag in (15, 29):  # DT_RPATH, DT_RUNPATH
            struct.pack_into(endian + "qQ", data, off, tag, empty_off)
            changed = True

    if changed:
        with open(path, "r+b") as f:
            f.write(data)
    return changed


def main():
    failed = False
    for path in sys.argv[1:]:
        try:
            strip(path)
        except Exception as exc:  # noqa: BLE001 - report and continue
            print(f"strip-rpath: {path}: {exc}", file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
