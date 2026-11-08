#!/usr/bin/env python3
"""Tiny homebrew test programs, one per system, written from scratch (no copyrighted code).
Each boots, sets the screen to a solid color where that's simple, and loops forever.
Used by the cloud build (simulator screenshots) and by Tests/core_test on Linux.

usage: make_test_roms.py <output folder>"""
import os, struct, sys, zlib

out = sys.argv[1] if len(sys.argv) > 1 else "test-roms"
os.makedirs(out, exist_ok=True)


def write(name, data):
    with open(os.path.join(out, name), "wb") as f:
        f.write(bytes(data))


# NES: iNES mapper 0, sets the background color to green and turns the picture on.
prg = bytearray([0xFF] * 0x4000)
code = [
    0x78, 0xD8, 0xA2, 0x40, 0x8E, 0x17, 0x40, 0xA2, 0xFF, 0x9A, 0xE8, 0x8E, 0x00, 0x20, 0x8E, 0x01, 0x20,
    0x2C, 0x02, 0x20, 0x10, 0xFB, 0x2C, 0x02, 0x20, 0x10, 0xFB,          # wait 2 vblanks
    0xA9, 0x3F, 0x8D, 0x06, 0x20, 0xA9, 0x00, 0x8D, 0x06, 0x20,          # PPU address $3F00
    0xA9, 0x2A, 0x8D, 0x07, 0x20,                                        # palette 0 = green
    0xA9, 0x00, 0x8D, 0x06, 0x20, 0x8D, 0x06, 0x20,
    0xA9, 0x0A, 0x8D, 0x01, 0x20,                                        # show background
]
loop = 0xC000 + len(code)
code += [0x4C, loop & 0xFF, loop >> 8, 0x40]                             # JMP loop ; RTI
prg[:len(code)] = code
rti = 0xC000 + len(code) - 1
prg[0x3FFA:0x4000] = struct.pack("<HHH", rti, 0xC000, rti)
write("test.nes", b"NES\x1a" + bytes([1, 1, 0, 0]) + bytes(8) + prg + bytes(0x2000))

# Super Nintendo: LoROM, backdrop green, screen on.
sfc = bytearray(0x8000)
c = [0x78, 0x18, 0xFB, 0xA9, 0x0F, 0x8D, 0x00, 0x21, 0x9C, 0x21, 0x21,
     0xA9, 0xE0, 0x8D, 0x22, 0x21, 0xA9, 0x03, 0x8D, 0x22, 0x21, 0x80, 0xFE]
sfc[:len(c)] = c
sfc[0x7FC0:0x7FD5] = b"EMU4IOS TEST".ljust(21)
sfc[0x7FD5], sfc[0x7FD6], sfc[0x7FD7], sfc[0x7FD8], sfc[0x7FD9] = 0x20, 0x00, 0x05, 0x00, 0x01
for v in range(0x7FE0, 0x8000, 2):
    sfc[v:v + 2] = struct.pack("<H", 0x8000)
sfc[0x7FDC:0x7FE0] = struct.pack("<HH", 0xFFFF, 0)
checksum = sum(sfc) & 0xFFFF
sfc[0x7FDC:0x7FE0] = struct.pack("<HH", checksum ^ 0xFFFF, checksum)
write("test.sfc", sfc)

# Master System / Game Gear / SG-1000: VDP backdrop green.
def sms(size=0x8000, gg=False):
    rom = bytearray(size)
    color = [0xF0, 0x00] if gg else [0x0C]
    c = [0xF3,
         0x3E, 0x40, 0xD3, 0xBF, 0x3E, 0x81, 0xD3, 0xBF,     # reg 1: display on
         0x3E, 0x00, 0xD3, 0xBF, 0x3E, 0x87, 0xD3, 0xBF]     # reg 7: backdrop color 0
    for addr in (0, 16 * len(color)):
        c += [0x3E, addr, 0xD3, 0xBF, 0x3E, 0xC0, 0xD3, 0xBF]
        for b in color:
            c += [0x3E, b, 0xD3, 0xBE]
    c += [0x18, 0xFE]
    rom[:len(c)] = bytes(c)
    rom[0x7FF0:0x7FF8] = b"TMR SEGA"
    rom[0x7FFF] = 0x6C if gg else 0x4C
    return rom
write("test.sms", sms())
write("test.gg", sms(gg=True))
write("test.sg", sms())

# Genesis / Mega Drive: CRAM color 0 green, display on.
md = bytearray(0x20000)
md[0:8] = struct.pack(">II", 0x00FFFE00, 0x200)
for i in range(2, 64):
    md[i * 4:i * 4 + 4] = struct.pack(">I", 0x200)
md[0x100:0x110] = b"SEGA MEGA DRIVE "
md[0x120:0x150] = b"EMU4IOS TEST".ljust(48)
md[0x150:0x180] = b"EMU4IOS TEST".ljust(48)
md[0x1A0:0x1A8] = struct.pack(">II", 0, len(md) - 1)
md[0x1F0:0x1F3] = b"JUE"
words = [
    0x1039, 0x00A1, 0x0001, 0x0200, 0x000F, 0x670A,              # TMSS check
    0x23FC, 0x5345, 0x4741, 0x00A1, 0x4000,
    0x33FC, 0x8004, 0x00C0, 0x0004,
    0x33FC, 0x8144, 0x00C0, 0x0004,
    0x33FC, 0x8700, 0x00C0, 0x0004,
    0x23FC, 0xC000, 0x0000, 0x00C0, 0x0004,
    0x33FC, 0x00E0, 0x00C0, 0x0000,
    0x60FE,
]
md[0x200:0x200 + len(words) * 2] = b"".join(struct.pack(">H", w) for w in words)
write("test.md", md)

# PC Engine: reset vector → infinite loop.
pce = bytearray(0x8000)
pce[0:3] = [0x4C, 0x00, 0xE0]
pce[0x1FFA:0x2000] = struct.pack("<HHH", 0xE000, 0xE000, 0xE000)
write("test.pce", pce)
write("test.sgx", pce)

# Neo Geo Pocket Color: header + JR to self.
ngp = bytearray(0x80000)
ngp[0:28] = b" LICENSED BY SNK CORPORATION"
ngp[0x1C:0x20] = struct.pack("<I", 0x200040)
ngp[0x23] = 0x10
ngp[0x24:0x30] = b"EMU4IOS TEST"
ngp[0x40:0x42] = [0x68, 0xFE]
write("test.ngc", ngp)
write("test.ngp", ngp)

# WonderSwan: reset jumps to a JMP-to-self.
ws = bytearray(0x80000)
ws[-0x20:-0x1E] = [0xEB, 0xFE]
ws[-0x10:-0x0B] = [0xEA, 0xE0, 0xFF, 0x00, 0xF0]
ws[-0x06] = 0x02
write("test.ws", ws)
write("test.wsc", ws)

# Virtual Boy: reset vector at the end of ROM, BR to self.
vb = bytearray(0x100000)
vb[-0x10:-0x0E] = [0x00, 0x85]
write("test.vb", vb)

# Atari 2600: 4K, JMP to self.
a26 = bytearray(0x1000)
a26[0:3] = [0x4C, 0x00, 0xF0]
a26[0xFFA:0x1000] = struct.pack("<HHH", 0xF000, 0xF000, 0xF000)
write("test.a26", a26)

# Atari 7800: header + 32K ROM, JMP to self.
a78 = bytearray(0x8000)
a78[0:3] = [0x4C, 0x00, 0x80]
a78[0x7FFA:0x8000] = struct.pack("<HHH", 0x8000, 0x8000, 0x8000)
hdr = bytearray(128)
hdr[0] = 1
hdr[1:10] = b"ATARI7800"
hdr[17:49] = b"EMU4IOS TEST".ljust(32, b"\0")
hdr[49:53] = struct.pack(">I", len(a78))
hdr[100:128] = b"ACTUAL CART DATA STARTS HERE"
write("test.a78", hdr + a78)

# Atari 5200: 16K cart, start vector → JMP to self.
a52 = bytearray(0x4000)
a52[0:3] = [0x4C, 0x00, 0x80]
a52[0x3FFD] = 0xFF
a52[0x3FFE:0x4000] = struct.pack("<H", 0x8000)
write("test.a52", a52)

# Pokémon mini: header only (the core's free BIOS boots it).
pm = bytearray(0x10000)
pm[0x2100:0x2102] = b"MN"
pm[0x21A4:0x21AC] = b"NINTENDO"
pm[0x21AC:0x21B0] = b"TEST"
write("test.min", pm)

# DOS: a .COM program that loops forever.
write("test.com", [0xEB, 0xFE])

# Commodore 64: BASIC "10 GOTO 10".
write("test.prg", [0x01, 0x08, 0x0B, 0x08, 0x0A, 0x00, 0x89, 0x31, 0x30, 0x00, 0x00, 0x00])

# Amiga: a blank double-density floppy (boots to the insert-disk screen).
write("test.adf", bytearray(901120))

# Nintendo DS: both CPUs branch to themselves (direct boot, no logo or BIOS needed).
nds = bytearray(0x400)
nds[0:12] = b"EMU4IOS TEST"
nds[0x0C:0x10] = b"E4TE"
nds[0x20:0x30] = struct.pack("<IIII", 0x200, 0x02000000, 0x02000000, 4)   # ARM9 offset, entry, RAM, size
nds[0x30:0x40] = struct.pack("<IIII", 0x204, 0x037F8000, 0x037F8000, 4)   # ARM7
nds[0x80:0x88] = struct.pack("<II", len(nds), 0x4000)
nds[0x200:0x208] = struct.pack("<II", 0xEAFFFFFE, 0xEAFFFFFE)              # b .
def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc
nds[0x15E:0x160] = struct.pack("<H", crc16(nds[:0x15E]))
write("test.nds", nds)

# Jaguar: blank cartridge.
write("test.j64", bytearray(0x200000))

print("wrote test programs to", out)
