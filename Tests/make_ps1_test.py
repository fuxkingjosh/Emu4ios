#!/usr/bin/env python3
"""Builds a tiny homebrew PS1 program (PS-X EXE, our own code): sets up the GPU and
draws animated color bars. Used only for automated tests and screenshots."""
import struct, sys

BASE = 0x80010000
code = []
def emit(w): code.append(w & 0xFFFFFFFF)
def pc(): return BASE + 4 * len(code)
def lui(rt, imm): emit(0x3C000000 | rt << 16 | (imm & 0xFFFF))
def ori(rt, rs, imm): emit(0x34000000 | rs << 21 | rt << 16 | (imm & 0xFFFF))
def addiu(rt, rs, imm): emit(0x24000000 | rs << 21 | rt << 16 | (imm & 0xFFFF))
def sw(rt, off, base): emit(0xAC000000 | base << 21 | rt << 16 | (off & 0xFFFF))
def and_(rd, rs, rt): emit(rs << 21 | rt << 16 | rd << 11 | 0x24)
def or_(rd, rs, rt): emit(rs << 21 | rt << 16 | rd << 11 | 0x25)
def li(rt, v): lui(rt, v >> 16); ori(rt, rt, v)
def bne(rs, rt, target): emit(0x14000000 | rs << 21 | rt << 16 | (((target - (pc() + 4)) >> 2) & 0xFFFF))
def j(target): emit(0x08000000 | ((target & 0x0FFFFFFF) >> 2))
def nop(): emit(0)

T0, T1, T2, T3, T4, T5, T6, T7, S0 = 8, 9, 10, 11, 12, 13, 14, 15, 16
li(T0, 0x1F801810)                     # GP0 (GP1 = +4)
for gp1 in (0x00000000, 0x03000000, 0x06C60260, 0x07040010, 0x08000001, 0x05000000):
    li(T1, gp1); sw(T1, 4, T0)
for gp0 in (0xE1000400, 0xE3000000, 0xE403BD3F, 0xE5000000):
    li(T1, gp0); sw(T1, 0, T0)
li(T2, 0x00203040)                      # color
li(T4, 0x02000000)                      # fill-rectangle command
li(T7, 0x00FFFFFF)                      # color mask
li(S0, 0x00F00050)                      # 80x240 bar
loop = pc()
for bar in range(4):
    and_(T3, T2, T7); or_(T3, T3, T4); sw(T3, 0, T0)
    li(T5, bar * 80); sw(T5, 0, T0)          # y=0, x=bar*80
    sw(S0, 0, T0)
    li(T6, 0x00102030 * (bar + 1)); emit(0x21 | T2 << 21 | T6 << 16 | T2 << 11)  # addu t2,t2,t6
lui(T6, 0x0003)                         # delay
delay = pc()
addiu(T6, T6, -1); bne(T6, 0, delay); nop()
li(T6, 0x00030507); emit(0x21 | T2 << 21 | T6 << 16 | T2 << 11)
j(loop); nop()

text = b"".join(struct.pack("<I", w) for w in code)
text += b"\0" * (-len(text) % 0x800)
header = bytearray(0x800)
header[0:8] = b"PS-X EXE"
struct.pack_into("<IIII", header, 0x10, BASE, 0, BASE, len(text))
struct.pack_into("<II", header, 0x30, 0x801FFFF0, 0)
header[0x4C:0x4C + 32] = b"Sony Computer Entertainment Inc."[:32]  # region marker string, not code
open(sys.argv[1] if len(sys.argv) > 1 else "E4Demo.exe", "wb").write(bytes(header) + text)
