#!/usr/bin/env python3
"""Builds a tiny homebrew GBA test program (no copyrighted code): it draws a
color gradient and animates it each frame. Used only by CI screenshots."""
import struct, sys

def arm(*words):
    return b"".join(struct.pack("<I", w) for w in words)

rom = bytearray(0x200)
rom[0:4] = struct.pack("<I", 0xEA00002E)          # b 0xC0
rom[0xA0:0xAC] = b"E4 DEMO\0\0\0\0\0"
rom[0xAC:0xB0] = b"E4DM"; rom[0xB0:0xB2] = b"00"; rom[0xB2] = 0x96
chk = 0
for b in rom[0xA0:0xBD]:
    chk = (chk - b) & 0xFF
rom[0xBD] = (chk - 0x19) & 0xFF

code = arm(
    0xE3A00301,  # mov r0, #0x04000000      (I/O)
    0xE3A01B01,  # mov r1, #0x400
    0xE3811003,  # orr r1, r1, #3           (mode 3, BG2 on)
    0xE1C010B0,  # strh r1, [r0]
    0xE3A05000,  # mov r5, #0               (frame offset)
    # frame:
    0xE3A02406,  # mov r2, #0x06000000      (VRAM)
    0xE1A03005,  # mov r3, r5
    0xE3A04C96,  # mov r4, #0x9600          (240*160 pixels)
    # pixel loop:
    0xE0C230B2,  # strh r3, [r2], #2
    0xE2833001,  # add r3, r3, #1
    0xE2544001,  # subs r4, r4, #1
    0x1AFFFFFB,  # bne pixel loop
    # wait for vblank: while (VCOUNT != 160)
    0xE1D060B6,  # ldrh r6, [r0, #6]
    0xE35600A0,  # cmp r6, #160
    0x1AFFFFFC,  # bne wait
    0xE2855C01,  # add r5, r5, #0x100       (shift colors)
    0xEAFFFFF1,  # b frame
)
rom[0xC0:0xC0 + len(code)] = code
open(sys.argv[1] if len(sys.argv) > 1 else "E4Demo.gba", "wb").write(rom)
