#!/usr/bin/env python3
"""把演示 ROM 的 PPU 内容离线渲染成 PNG，不需要装机就能看画面。

做法：用 check_rom 的 6502 执行器跑几帧，把期间所有 $2007 写入重建成
VRAM，再按 NES 的图块/属性/调色板规则画出 256x240 的帧，最后叠上 OAM。

用法：
    python3 Tools/testrom/render_preview.py [-o 输出.png] [-n 帧数]
"""

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_rom as checker          # noqa: E402
import build_demo_rom as builder     # noqa: E402

# 2C02 调色板的常用子集：本 ROM 只用到这几个索引
NES_RGB = {
    0x00: (84, 84, 84), 0x0F: (0, 0, 0), 0x10: (188, 188, 188),
    0x16: (216, 29, 29), 0x17: (107, 79, 66), 0x18: (136, 79, 0),
    0x21: (116, 176, 216), 0x27: (192, 120, 0), 0x28: (136, 150, 0),
    0x37: (252, 184, 88),
    0x30: (252, 252, 252), 0x3F: (0, 0, 0),
}


def rgb(index):
    return NES_RGB.get(index, (255, 0, 255))


def load_vram(rom, frames, pad=0x00):
    prg = rom[16:16 + 16384]
    cpu = checker.Machine(rom, pad=pad)
    for addr, off in ((0xFFFA, 0x3FFA), (0xFFFB, 0x3FFB),
                      (0xFFFC, 0x3FFC), (0xFFFD, 0x3FFD)):
        cpu.mem[addr] = prg[off]
    problem = cpu.run(frames=frames)
    vram = {}
    for addr, value in cpu.vram_writes:
        vram[addr] = value
    return cpu, vram, problem


def tile_pixels(chr_bank, index, table):
    base = table + index * 16
    plane0 = chr_bank[base:base + 8]
    plane1 = chr_bank[base + 8:base + 16]
    rows = []
    for y in range(8):
        row = []
        for x in range(8):
            bit = 0x80 >> x
            value = (1 if plane0[y] & bit else 0) | (2 if plane1[y] & bit else 0)
            row.append(value)
        rows.append(row)
    return rows


def render(rom, cpu, vram):
    chr_bank = rom[16 + 16384:]
    bg_table = 0x1000 if cpu.ppuctrl & 0x10 else 0x0000
    sp_table = 0x1000 if cpu.ppuctrl & 0x08 else 0x0000

    image = Image.new("RGB", (256, 240), rgb(0x0F))
    px = image.load()

    for ty in range(30):
        for tx in range(32):
            index = vram.get(0x2000 + ty * 32 + tx, 0)
            if index == 0:
                continue
            attr = vram.get(0x23C0 + (ty // 4) * 8 + tx // 4, 0)
            shift = ((ty % 4) // 2) * 4 + ((tx % 4) // 2) * 2
            pal = (attr >> shift) & 0x03
            rows = tile_pixels(chr_bank, index, bg_table)
            for y in range(8):
                for x in range(8):
                    value = rows[y][x]
                    if value == 0:
                        continue
                    px[tx * 8 + x, ty * 8 + y] = rgb(vram.get(0x3F00 + pal * 4 + value, 0x0F))

    # 精灵：OAM 里 y 要 +1，y=$F8 之后属于隐藏区
    tall = bool(cpu.ppuctrl & 0x20)          # bit5：8x16 精灵
    height = 16 if tall else 8
    for i in range(64):
        sy, index, attr, sx = cpu.mem[0x200 + i * 4:0x204 + i * 4]
        if sy >= 0xEF or index == 0:
            continue
        pal = attr & 0x03
        flip_h = attr & 0x40
        if tall:
            index &= 0xFE                    # 8x16 模式：索引的低位由 PPU 补
        upper = tile_pixels(chr_bank, index, sp_table)
        lower = tile_pixels(chr_bank, index + 1, sp_table) if tall else upper
        for y in range(height):
            row = lower[y - 8] if y >= 8 else upper[y]
            for x in range(8):
                value = row[7 - x if flip_h else x]
                if value == 0:
                    continue
                dx = sx + x
                dy = sy + 1 + y
                if 0 <= dx < 256 and 0 <= dy < 240:
                    px[dx, dy] = rgb(vram.get(0x3F10 + pal * 4 + value, 0x0F))
    return image


def main():
    argv = sys.argv[1:]
    root = Path(__file__).resolve().parents[2]
    rom_path = root / "RetroEmu" / "Demo" / "PocketMuseumDemo.nes"
    if argv and not argv[0].startswith("-"):
        rom_path = Path(argv[0])
    frames = 5
    if "-n" in argv:
        frames = int(argv[argv.index("-n") + 1])
    out = root / ".tmp" / "testrom-preview.png"
    if "-o" in argv:
        out = Path(argv[argv.index("-o") + 1])
    pad = 0x00
    if "-p" in argv:
        pad = int(argv[argv.index("-p") + 1], 0)

    rom = rom_path.read_bytes()
    cpu, vram, problem = load_vram(rom, frames, pad=pad)
    print("CPU：%s  PPUCTRL=$%02X PPUMASK=$%02X NMI=%d" %
          (problem or "正常", cpu.ppuctrl, cpu.ppumask, cpu.nmi_count))

    image = render(rom, cpu, vram)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.resize((512, 480), Image.NEAREST).save(out)
    lit = sum(1 for p in image.getdata() if p != rgb(0x0F))
    print("已写出 %s（非黑像素 %d / %d）" % (out, lit, 256 * 240))
    return 0


if __name__ == "__main__":
    sys.exit(main())
