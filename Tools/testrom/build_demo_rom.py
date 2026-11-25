#!/usr/bin/env python3
"""构建 Pocket Museum 自己的 NES 演示卡带。

机器上没有任何 6502 汇编器，所以这里带一个只覆盖本项目所用指令的两遍
汇编器：所有字节都由本脚本生成，产出的 ROM 完全属于本项目，可以直接用于
上架截图取证、审核演示，不存在任何第三方游戏文件的授权问题。

用法：
    python3 Tools/testrom/build_demo_rom.py

产物：
    RetroEmu/Demo/PocketMuseumDemo.nes   (iNES, 16K PRG + 8K CHR)

产物直接落在 App 的同步目录里，Xcode 会把它当资源打进 bundle；
首次启动时 ROMLibrary 再复制一份到 Documents，审核员开箱即可游玩。
"""

from pathlib import Path

# --------------------------------------------------------------------------
# 6502 指令表（只收录本 ROM 用到的助记符与寻址方式）
# --------------------------------------------------------------------------

OPCODES = {
    ("lda", "imm"): 0xA9, ("lda", "zp"): 0xA5, ("lda", "zpx"): 0xB5,
    ("lda", "abs"): 0xAD, ("lda", "absx"): 0xBD, ("lda", "absy"): 0xB9,
    ("lda", "indy"): 0xB1, ("lda", "indx"): 0xA1,
    ("sta", "zp"): 0x85, ("sta", "zpx"): 0x95, ("sta", "abs"): 0x8D,
    ("sta", "absx"): 0x9D, ("sta", "absy"): 0x99,
    ("sta", "indy"): 0x91, ("sta", "indx"): 0x81,
    ("ldx", "imm"): 0xA2, ("ldx", "zp"): 0xA6, ("ldx", "zpy"): 0xB6,
    ("ldx", "abs"): 0xAE, ("ldx", "absy"): 0xBE,
    ("ldy", "imm"): 0xA0, ("ldy", "zp"): 0xA4, ("ldy", "zpx"): 0xB4,
    ("ldy", "abs"): 0xAC, ("ldy", "absx"): 0xBC,
    ("stx", "zp"): 0x86, ("stx", "zpy"): 0x96, ("stx", "abs"): 0x8E,
    ("sty", "zp"): 0x84, ("sty", "zpx"): 0x94, ("sty", "abs"): 0x8C,
    ("tax", "imp"): 0xAA, ("tay", "imp"): 0xA8, ("txa", "imp"): 0x8A,
    ("tya", "imp"): 0x98, ("tsx", "imp"): 0xBA, ("txs", "imp"): 0x9A,
    ("inx", "imp"): 0xE8, ("iny", "imp"): 0xC8,
    ("dex", "imp"): 0xCA, ("dey", "imp"): 0x88,
    ("inc", "zp"): 0xE6, ("inc", "abs"): 0xEE,
    ("dec", "zp"): 0xC6, ("dec", "abs"): 0xCE,
    ("adc", "imm"): 0x69, ("adc", "zp"): 0x65, ("adc", "abs"): 0x6D,
    ("sbc", "imm"): 0xE9, ("sbc", "zp"): 0xE5, ("sbc", "abs"): 0xED,
    ("and", "imm"): 0x29, ("and", "zp"): 0x25, ("and", "abs"): 0x2D,
    ("ora", "imm"): 0x09, ("eor", "imm"): 0x49,
    ("cmp", "imm"): 0xC9, ("cmp", "zp"): 0xC5, ("cmp", "abs"): 0xCD,
    ("cpx", "imm"): 0xE0, ("cpx", "zp"): 0xE4, ("cpx", "abs"): 0xEC,
    ("cpy", "imm"): 0xC0, ("cpy", "zp"): 0xC4, ("cpy", "abs"): 0xCC,
    ("bit", "zp"): 0x24, ("bit", "abs"): 0x2C,
    ("asl", "acc"): 0x0A, ("lsr", "acc"): 0x4A,
    ("rol", "acc"): 0x2A, ("ror", "acc"): 0x6A,
    ("rol", "zp"): 0x26, ("rol", "abs"): 0x2E,
    ("lsr", "zp"): 0x46, ("lsr", "abs"): 0x4E,
    ("pha", "imp"): 0x48, ("pla", "imp"): 0x68,
    ("php", "imp"): 0x08, ("plp", "imp"): 0x28,
    ("jmp", "abs"): 0x4C, ("jmp", "ind"): 0x6C,
    ("jsr", "abs"): 0x20, ("rts", "imp"): 0x60, ("rti", "imp"): 0x40,
    ("bpl", "rel"): 0x10, ("bmi", "rel"): 0x30,
    ("bvc", "rel"): 0x50, ("bvs", "rel"): 0x70,
    ("bcc", "rel"): 0x90, ("bcs", "rel"): 0xB0,
    ("bne", "rel"): 0xD0, ("beq", "rel"): 0xF0,
    ("sei", "imp"): 0x78, ("cli", "imp"): 0x58,
    ("cld", "imp"): 0xD8, ("sed", "imp"): 0xF8,
    ("clc", "imp"): 0x18, ("sec", "imp"): 0x38, ("clv", "imp"): 0xB8,
    ("nop", "imp"): 0xEA,
}

SIZES = {"imp": 1, "acc": 1, "imm": 2, "zp": 2, "zpx": 2, "zpy": 2,
         "abs": 3, "absx": 3, "absy": 3, "ind": 3, "indy": 2, "indx": 2,
         "rel": 2}


class Asm:
    """够用就好的两遍汇编器：标签、分支、绝对/零页寻址、数据块。"""

    def __init__(self, origin):
        self.origin = origin
        self.items = []
        self.labels = {}

    def label(self, name):
        self.items.append(("label", name))

    def op(self, mnem, mode=None, value=None):
        if mode is None:
            mode = "imp"
        self.items.append(("op", mnem, mode, value))

    def data(self, payload):
        self.items.append(("data", list(payload)))

    def word(self, target):
        self.items.append(("word", target))

    # -- 第一遍：定位标签 --------------------------------------------------
    def _resolve(self, spec, here):
        """把 int / 'label' / ('label', delta) 统一换算成地址。"""
        if isinstance(spec, int):
            return spec
        if isinstance(spec, str):
            if spec not in self.labels:
                raise KeyError(f"未定义标签 {spec}")
            return self.labels[spec]
        name, delta = spec
        return self.labels[name] + delta

    def assemble(self):
        pc = self.origin
        for item in self.items:
            if item[0] == "label":
                self.labels[item[1]] = pc
            elif item[0] == "op":
                pc += SIZES[item[2]]
            elif item[0] == "data":
                pc += len(item[1])
            elif item[0] == "word":
                pc += 2

        out = bytearray()
        pc = self.origin
        for item in self.items:
            if item[0] == "label":
                continue
            if item[0] == "data":
                out.extend(item[1])
                pc += len(item[1])
                continue
            if item[0] == "word":
                addr = self._resolve(item[1], pc)
                out.extend((addr & 0xFF, (addr >> 8) & 0xFF))
                pc += 2
                continue

            _, mnem, mode, value = item
            key = (mnem, mode)
            if key not in OPCODES:
                raise KeyError(f"未收录指令 {mnem} / {mode}")
            out.append(OPCODES[key])

            if mode in ("imp", "acc"):
                pass
            elif mode == "rel":
                target = self._resolve(value, pc)
                delta = target - (pc + 2)
                if not -128 <= delta <= 127:
                    raise ValueError(f"{mnem} 分支越界：{delta}")
                out.append(delta & 0xFF)
            elif mode in ("abs", "absx", "absy", "ind"):
                addr = self._resolve(value, pc)
                out.extend((addr & 0xFF, (addr >> 8) & 0xFF))
            elif mode in ("zp", "zpx", "zpy", "imm"):
                out.append(self._resolve(value, pc) & 0xFF)
            elif mode in ("indy", "indx"):
                out.append(self._resolve(value, pc) & 0xFF)
            pc += SIZES[mode]
        return bytes(out)


# --------------------------------------------------------------------------
# 字模：5x7 像素，右/下各留 1 像素间距，像素落在颜色 2
# --------------------------------------------------------------------------

GLYPHS = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01111"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"),
    "J": ("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "11011", "10001"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11111", "00010", "00100", "00010", "00001", "10001", "01110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    ".": ("00000", "00000", "00000", "00000", "00000", "01100", "01100"),
    "/": ("00001", "00010", "00010", "00100", "01000", "01000", "10000"),
    ":": ("00000", "01100", "01100", "00000", "01100", "01100", "00000"),
}

TILE_BLANK = 0x00
TILE_SOLID = 0x01
TILE_LATTICE = 0x02       # 展柜格栅底纹，像素值 1（暗棕），不跟正文抢注意力
TILE_FONT = 0x10          # A=0x10 .. Z=0x29
TILE_DIGIT = 0x30         # 0=0x30 .. 9=0x39
TILE_PUNCT = {"-": 0x3A, ".": 0x3B, "/": 0x3C, ":": 0x3D}
TILE_CART_TL = 0xE0            # 8x16 精灵：E0 取 E0/E1，E2 取 E2/E3
TILE_CART_BL = 0xE1
TILE_CART_TR = 0xE2
TILE_CART_BR = 0xE3
TILE_BOX_L = 0xD0              # 32x16 托盘，8 个图块：D0/D1、D2/D3、D4/D5、D6/D7
TILE_BOX_R2 = 0xD4
TILE_BOX_R3 = 0xD6

# 8 像素一格的织点：每个图块只在左上角留一个像素，
# 放大到全屏后是一层很淡的亚麻纹理，不会跟文字抢注意力
LATTICE_ROWS = (
    "10000000",
    "00000000",
    "00000000",
    "00000000",
    "00000000",
    "00000000",
    "00000000",
    "00000000",
)


def tile_index(ch):
    if ch == " ":
        return TILE_LATTICE
    if "A" <= ch <= "Z":
        return TILE_FONT + (ord(ch) - ord("A"))
    if "0" <= ch <= "9":
        return TILE_DIGIT + (ord(ch) - ord("0"))
    return TILE_PUNCT[ch]


def lattice_tile(rows):
    """背景格栅：像素值 1，读调色板的 index 1，所以只在暗色底上浮一点点。"""
    plane0 = bytearray()
    plane1 = bytearray(8)
    for y in range(8):
        bits = 0
        for x, ch in enumerate(rows[y]):
            if ch == "1":
                bits |= 0x80 >> x
        plane0.append(bits)
    return bytes(plane0) + bytes(plane1)


def glyph_tile(rows):
    """把 5x7 字模铺成 8x8、像素值 2（plane0=0，plane1=1）的 NES 图块。

    NES 图块的 16 字节是「plane0 的 8 行 + plane1 的 8 行」，不是按行交错。
    """
    plane0 = bytearray(8)
    plane1 = bytearray()
    for y in range(8):
        bits = 0
        if y < len(rows):
            for x, ch in enumerate(rows[y]):
                if ch == "1":
                    bits |= 0x80 >> (x + 1)     # 左右各留半像素，视觉居中
        plane1.append(bits)
    return bytes(plane0) + bytes(plane1)


def sprite_tile(rows):
    """精灵图块：1 -> 颜色 1，2 -> 颜色 2，0 透明。"""
    plane0 = bytearray()
    plane1 = bytearray()
    for y in range(8):
        low = high = 0
        if y < len(rows):
            for x, ch in enumerate(rows[y]):
                if ch == "0":
                    continue
                bit = 0x80 >> x
                if ch == "1":
                    low |= bit
                else:
                    high |= bit
        plane0.append(low)
        plane1.append(high)
    return bytes(plane0) + bytes(plane1)


CART_ROWS = (
    "1111111111111111",
    "1222222222222221",
    "1222222222222221",
    "1222111111112221",
    "1222111111112221",
    "1222111111112221",
    "1222111111112221",
    "1222111111112221",
    "1222222222222221",
    "1222222222222221",
    "1111111111111111",
    "1111011111011111",
    "1111111111111111",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
)


BOX_ROWS = (
    "00000000000000000000000000000000",
    "10000000000000000000000000000001",
    "10000000000000000000000000000001",
    "10000000000000000000000000000001",
    "10000000000000000000000000000001",
    "10000000000000000000000000000001",
    "10000000000000000000000000000001",
    "10000000000000000000000000000001",
    "10000000000000000000000000000001",
    "10000000000000000000000000000001",
    "10000000000000000000000000000001",
    "12222222222222222222222222222221",
    "12222222222222222222222222222221",
    "12222222222222222222222222222221",
    "12222222222222222222222222222221",
    "11111111111111111111111111111111",
)


def slice16(rows, origin_y, origin_x):
    """从 16x16 的精灵图案里切一块 8x8 出来（8x16 精灵模式按上下拼）。"""
    part = tuple(row[origin_x:origin_x + 8] for row in rows[origin_y:origin_y + 8])
    return sprite_tile(part)


def cart_tile(origin_y, origin_x):
    return slice16(CART_ROWS, origin_y, origin_x)


def box_tile(origin_y, origin_x):
    return slice16(BOX_ROWS, origin_y, origin_x)


def build_chr():
    bank = bytearray(8192)
    bank[TILE_SOLID * 16:(TILE_SOLID + 1) * 16] = bytes([0xFF] * 8 + [0x00] * 8)
    bank[TILE_LATTICE * 16:(TILE_LATTICE + 1) * 16] = lattice_tile(LATTICE_ROWS)
    for ch, rows in GLYPHS.items():
        idx = tile_index(ch)
        bank[idx * 16:(idx + 1) * 16] = glyph_tile(rows)
    # 8x16 精灵模式下，索引 E0 就是 E0/E1 这一对，E2 是 E2/E3
    bank[TILE_CART_TL * 16:(TILE_CART_TL + 1) * 16] = cart_tile(0, 0)
    bank[TILE_CART_BL * 16:(TILE_CART_BL + 1) * 16] = cart_tile(8, 0)
    bank[TILE_CART_TR * 16:(TILE_CART_TR + 1) * 16] = cart_tile(0, 8)
    bank[TILE_CART_BR * 16:(TILE_CART_BR + 1) * 16] = cart_tile(8, 8)
    for i in range(4):                     # 托盘 32 像素宽，四组 8x16
        upper = TILE_BOX_L + i * 2
        bank[upper * 16:(upper + 1) * 16] = box_tile(0, i * 8)
        bank[(upper + 1) * 16:(upper + 2) * 16] = box_tile(8, i * 8)
    return bytes(bank)


# --------------------------------------------------------------------------
# 画面：32x30 图块网格 + 调色板归属
# --------------------------------------------------------------------------

PAL_TITLE = 0
PAL_BODY = 1
PAL_PROMPT = 2

SCREEN_TEXT = [
    # 前 8 行留给 App 的悬浮工具条，正文从第 9 行开始
    (9, 13, "POCKET", PAL_TITLE),
    (11, 13, "MUSEUM", PAL_TITLE),
    (13, 11, "DEMO CARD", PAL_BODY),
    (16, 2, "CABINET 01", PAL_BODY),
    (18, 2, "NES - 1983", PAL_BODY),
    (21, 2, "SAVE TIMELINE", PAL_BODY),
    (23, 2, "READY", PAL_BODY),
    (25, 10, "PRESS START", PAL_PROMPT),
    (28, 2, "ORIGINAL CONTENT", PAL_BODY),
    (28, 24, "NO.0001", PAL_BODY),
]

PROMPT_ROW, PROMPT_COL = 25, 10
PROMPT_ADDR = 0x2000 + PROMPT_ROW * 32 + PROMPT_COL
PROMPT_TEXT = "PRESS START"


def build_nametable():
    # 底纹先铺满，文字盖在上面。进游戏时只抹掉文字格，格栅自然留在原地。
    tiles = [[TILE_LATTICE] * 32 for _ in range(30)]
    pals = [[PAL_TITLE] * 32 for _ in range(30)]
    for row, col, text, pal in SCREEN_TEXT:
        for i, ch in enumerate(text):
            tiles[row][col + i] = tile_index(ch)
        # 属性表一个字节管 4x4 图块，四个象限分别由组内 (0,0)/(0,2)/(2,0)/(2,2)
        # 这四格的调色板号决定。也就是说文字那一行的配色，实际读的是它所在
        # 「偶数行」的值。所以要写到 row - row%2 上，并且整行刷满，才会稳定。
        attr_row = row - row % 2
        for x in range(32):
            pals[attr_row][x] = pal

    # 最底一行铺成实心，当作陈列柜的边缘
    for x in range(32):
        tiles[29][x] = TILE_SOLID

    table = bytearray()
    for row in range(30):
        table.extend(tiles[row])
    assert len(table) == 960, "图块表必须是 32x30"

    attrs = bytearray()
    for ay in range(8):
        for ax in range(8):
            quad = []
            for dy in (0, 2):
                for dx in (0, 2):
                    quad.append(pals[min(ay * 4 + dy, 29)][min(ax * 4 + dx, 31)])
            attrs.append(quad[0] | (quad[1] << 2) | (quad[2] << 4) | (quad[3] << 6))

    block = bytes(table) + bytes(attrs)
    assert len(block) == 1024, "图块表 + 属性表必须正好 1KB"
    return block


# 背景：0 号调色板给标题（琥珀），1 号给正文（白），2 号给提示（闪烁）
# 注意 NES 的 0x28 是黄绿、0x37 是米白，只有 0x27 才是稳的琥珀金。
PALETTE = bytes([
    0x0F, 0x17, 0x27, 0x17,     # 0 标题：黑底 + 琥珀（index1 给格栅用）
    0x0F, 0x17, 0x30, 0x00,     # 1 正文：暗棕格栅 + 白字
    0x0F, 0x17, 0x27, 0x00,     # 2 提示：暗棕格栅 + 琥珀
    0x0F, 0x10, 0x30, 0x00,     # 3 备用
    0x0F, 0x30, 0x27, 0x17,     # 精灵 0：卡带
    0x0F, 0x30, 0x21, 0x17,
    0x0F, 0x30, 0x16, 0x17,
    0x0F, 0x30, 0x27, 0x17,
])

# 零页变量
PAD1, FRAME, BOXX, CARTX, CARTY = 0x10, 0x11, 0x12, 0x13, 0x14
STATE, DIRTY, SCORE, MISS, SEED = 0x15, 0x16, 0x17, 0x18, 0x19
UPD_IDX, UPD_N, TMP, TMP2, SPDX = 0x1A, 0x1B, 0x1C, 0x1D, 0x1E
PREV, EDGE, LTICK = 0x1F, 0x20, 0x21

# 状态机：0 标题页 / 1 接卡带 / 2 结束
ST_TITLE, ST_PLAY, ST_OVER = 0, 1, 2

# 游戏区几何
BOX_Y = 0xD8              # 托盘顶边 y = 216
BOX_MIN, BOX_MAX = 0x00, 0xE0   # 托盘 32 像素宽，右边缘别超过 256
SPAWN_Y = 0x60            # 卡带出生 y = 96，落在 HUD 下面
CART_W = 0x18             # 托盘半宽 16 加卡带半宽 8，够宽松
MISS_LIMIT = 3

# HUD 放在第 11 行，刚好躲开 App 的悬浮工具条
HUD_ROW = 11
SCORE_ADDR = 0x2000 + HUD_ROW * 32 + 1
SCORE_DIGIT_ADDR = SCORE_ADDR + 6
MISS_ADDR = 0x2000 + HUD_ROW * 32 + 25
MISS_DIGIT_ADDR = MISS_ADDR + 5
HUD_LABELS = ((SCORE_ADDR, "SCORE"), (MISS_ADDR, "MISS"))
PROMPT_LEN = len(PROMPT_TEXT)


def build_clear_table():
    """进游戏时一次性抹掉的格子：标题页所有文字 + HUD 标签。

    NES 没有清屏指令，只能逐格往 $2007 写。写成三张平行表（地址高低字节 +
    图块号），NMI 里按条目号索引，每帧限写一批，避免超出垂直消隐。
    """
    cells = []
    for row, col, text, _pal in SCREEN_TEXT:
        if row == PROMPT_ROW:
            continue                       # 提示行单独由 DIRTY 处理
        for i in range(len(text)):
            cells.append((0x2000 + row * 32 + col + i, TILE_LATTICE))
    for addr, label in HUD_LABELS:
        for i, ch in enumerate(label):
            cells.append((addr + i, tile_index(ch)))
    hi = bytes(a >> 8 for a, _ in cells)
    lo = bytes(a & 0xFF for a, _ in cells)
    tile = bytes(t for _, t in cells)
    return hi, lo, tile


CLEAR_TABLE = build_clear_table()
CLEAR_COUNT = len(CLEAR_TABLE[0])


def build_prg():
    a = Asm(0x8000)

    a.label("reset")
    a.op("sei")
    a.op("cld")
    a.op("ldx", "imm", 0x40)
    a.op("stx", "abs", 0x4017)          # 关 APU 帧中断
    a.op("ldx", "imm", 0xFF)
    a.op("txs")
    a.op("inx")                          # X = 0
    a.op("stx", "abs", 0x2000)
    a.op("stx", "abs", 0x2001)
    a.op("stx", "abs", 0x4010)

    a.label("vbl1")                      # 等两次垂直消隐，PPU 就绪
    a.op("bit", "abs", 0x2002)
    a.op("bpl", "rel", "vbl1")
    a.label("vbl2")
    a.op("bit", "abs", 0x2002)
    a.op("bpl", "rel", "vbl2")

    a.op("lda", "imm", 0x00)
    a.label("clr")                        # 清 2KB 内存
    for page in range(8):
        a.op("sta", "absx", page << 8)
    a.op("inx")
    a.op("bne", "rel", "clr")

    a.op("ldx", "imm", 0x00)
    a.op("lda", "imm", 0xFE)              # 精灵全部挪出画面
    a.label("hide")
    a.op("sta", "absx", 0x0200)
    a.op("inx")
    a.op("bne", "rel", "hide")

    a.op("bit", "abs", 0x2002)
    a.op("lda", "imm", 0x3F)
    a.op("sta", "abs", 0x2006)
    a.op("lda", "imm", 0x00)
    a.op("sta", "abs", 0x2006)
    a.op("ldx", "imm", 0x00)
    a.label("pal")
    a.op("lda", "absx", "palette_data")
    a.op("sta", "abs", 0x2007)
    a.op("inx")
    a.op("cpx", "imm", 0x20)
    a.op("bne", "rel", "pal")

    a.op("lda", "imm", 0x20)              # 写整屏图块
    a.op("sta", "abs", 0x2006)
    a.op("lda", "imm", 0x00)
    a.op("sta", "abs", 0x2006)
    for page in range(4):
        name = f"nt{page}"
        a.op("ldx", "imm", 0x00)
        a.label(name)
        a.op("lda", "absx", ("screen", page * 256))
        a.op("sta", "abs", 0x2007)
        a.op("inx")
        a.op("bne", "rel", name)

    a.op("lda", "imm", 0xC0)              # 标题页：卡带在右侧窄栏里来回
    a.op("sta", "zp", CARTX)
    a.op("lda", "imm", SPAWN_Y)
    a.op("sta", "zp", CARTY)
    a.op("lda", "imm", 0x02)
    a.op("sta", "zp", SPDX)
    a.op("lda", "imm", 0x70)
    a.op("sta", "zp", BOXX)
    a.op("lda", "imm", 0x00)
    a.op("sta", "zp", FRAME)
    a.op("sta", "zp", STATE)              # 从标题页开始
    a.op("sta", "zp", DIRTY)
    a.op("sta", "zp", SCORE)
    a.op("sta", "zp", MISS)
    a.op("sta", "zp", SEED)
    a.op("sta", "zp", UPD_IDX)

    # PPUCTRL：bit7 开 NMI，bit5 用 8x16 精灵，bit3/bit4 分别选精灵与背景的
    # 图块表，两位都置 0 才都落在 $0000（字模与卡带图块都在这张表里）。
    a.op("cli")                            # 必须放开 I，否则 NMI 一辈子进不来
    a.op("lda", "imm", 0xA0)
    a.op("sta", "abs", 0x2000)
    a.op("lda", "imm", 0x1E)              # 开背景与精灵
    a.op("sta", "abs", 0x2001)

    a.label("main")
    a.op("lda", "zp", FRAME)              # 主循环每帧只走一遍，其余时间空转等 NMI
    a.op("cmp", "zp", LTICK)
    a.op("beq", "rel", "main")
    a.op("sta", "zp", LTICK)
    a.op("jsr", "abs", "readpad")
    a.op("lda", "zp", STATE)
    a.op("cmp", "imm", ST_PLAY)
    a.op("beq", "rel", "play")
    a.op("cmp", "imm", ST_OVER)
    a.op("beq", "rel", "over")

    a.op("lda", "zp", CARTX)              # 标题页：卡带在右侧窄栏里来回
    a.op("cmp", "imm", 0xC0)
    a.op("bcs", "rel", "t_hi")
    a.op("lda", "imm", 0x02)
    a.op("sta", "zp", SPDX)
    a.label("t_hi")
    a.op("lda", "zp", CARTX)
    a.op("cmp", "imm", 0xE8)
    a.op("bcc", "rel", "t_move")
    a.op("lda", "imm", 0xFE)
    a.op("sta", "zp", SPDX)
    a.label("t_move")
    a.op("lda", "zp", CARTX)
    a.op("clc")
    a.op("adc", "zp", SPDX)
    a.op("sta", "zp", CARTX)
    a.op("lda", "zp", EDGE)               # START 的上升沿才开新局
    a.op("beq", "rel", "main")
    a.op("jsr", "abs", "start_game")
    a.op("jmp", "abs", "main")

    a.label("over")                        # 结束页：再按一次 START 重开
    a.op("lda", "zp", EDGE)
    a.op("beq", "rel", "main")
    a.op("jsr", "abs", "start_game")
    a.op("jmp", "abs", "main")

    a.label("play")                        # 接卡带：方向键挪托盘
    a.op("lda", "zp", PAD1)
    a.op("and", "imm", 0x02)              # 左
    a.op("beq", "rel", "p_rt")
    a.op("lda", "zp", BOXX)
    a.op("sec")
    a.op("sbc", "imm", 0x04)
    a.op("bcs", "rel", "p_lstore")
    a.op("lda", "imm", BOX_MIN)
    a.label("p_lstore")
    a.op("sta", "zp", BOXX)
    a.label("p_rt")
    a.op("lda", "zp", PAD1)
    a.op("and", "imm", 0x01)              # 右
    a.op("beq", "rel", "p_fall")
    a.op("lda", "zp", BOXX)
    a.op("clc")
    a.op("adc", "imm", 0x04)
    a.op("cmp", "imm", BOX_MAX + 1)
    a.op("bcc", "rel", "p_rstore")
    a.op("lda", "imm", BOX_MAX)
    a.label("p_rstore")
    a.op("sta", "zp", BOXX)
    a.label("p_fall")
    a.op("lda", "zp", CARTY)              # 卡带匀速下落
    a.op("clc")
    a.op("adc", "imm", 0x01)
    a.op("sta", "zp", CARTY)
    a.op("cmp", "imm", BOX_Y)
    a.op("bcc", "rel", "main")

    a.op("lda", "zp", BOXX)               # 横向重叠就算接住
    a.op("sec")
    a.op("sbc", "zp", CARTX)
    a.op("bcs", "rel", "p_abs")
    a.op("eor", "imm", 0xFF)              # 负数取绝对值：取反再加一
    a.op("adc", "imm", 0x01)
    a.label("p_abs")
    a.op("cmp", "imm", CART_W)
    a.op("bcs", "rel", "p_missed")
    a.op("lda", "zp", SCORE)
    a.op("cmp", "imm", 99)                # 两位数字到头就不再涨
    a.op("bcs", "rel", "p_respawn")
    a.op("inc", "zp", SCORE)
    a.op("jmp", "abs", "p_respawn")
    a.label("p_missed")
    a.op("inc", "zp", MISS)
    a.op("lda", "zp", MISS)
    a.op("cmp", "imm", MISS_LIMIT)
    a.op("bcc", "rel", "p_respawn")
    a.op("lda", "imm", ST_OVER)           # 三次漏接就收摊
    a.op("sta", "zp", STATE)
    a.op("lda", "imm", 0x02)
    a.op("sta", "zp", DIRTY)              # 把提示行写回 PRESS START
    a.label("p_respawn")
    a.op("lda", "imm", SPAWN_Y)
    a.op("sta", "zp", CARTY)
    a.op("jsr", "abs", "rnd_x")
    a.op("jmp", "abs", "main")

    a.label("start_game")                  # 开一局：清分、摆位、清屏
    a.op("lda", "imm", 0x00)
    a.op("sta", "zp", SCORE)
    a.op("sta", "zp", MISS)
    a.op("sta", "zp", UPD_IDX)
    a.op("sta", "zp", SEED)
    a.op("lda", "imm", 0x70)
    a.op("sta", "zp", BOXX)
    a.op("lda", "imm", SPAWN_Y)
    a.op("sta", "zp", CARTY)
    a.op("jsr", "abs", "rnd_x")
    a.op("lda", "imm", ST_PLAY)
    a.op("sta", "zp", STATE)
    a.op("lda", "imm", 0x01)
    a.op("sta", "zp", DIRTY)              # 抹掉标题页那句 PRESS START
    a.op("rts")

    a.label("rnd_x")                       # 8 位 LFSR，落在 16 像素网格上
    a.op("lda", "zp", SEED)
    a.op("bne", "rel", "r_shift")
    a.op("lda", "imm", 0xA5)              # 0 是 LFSR 的坏状态，先种一个
    a.label("r_shift")
    a.op("asl", "acc")
    a.op("bcc", "rel", "r_store")
    a.op("eor", "imm", 0x1D)
    a.label("r_store")
    a.op("sta", "zp", SEED)
    a.op("lsr", "acc")
    a.op("lsr", "acc")
    a.op("lsr", "acc")
    a.op("lsr", "acc")
    a.op("and", "imm", 0x0F)
    a.op("asl", "acc")
    a.op("asl", "acc")
    a.op("asl", "acc")
    a.op("asl", "acc")
    a.op("cmp", "imm", 241)               # 右边缘别超出 256
    a.op("bcc", "rel", "r_ok")
    a.op("lda", "imm", 0xE0)
    a.label("r_ok")
    a.op("sta", "zp", CARTX)
    a.op("rts")

    a.label("readpad")
    a.op("lda", "imm", 0x01)
    a.op("sta", "abs", 0x4016)
    a.op("lda", "imm", 0x00)
    a.op("sta", "abs", 0x4016)
    a.op("lda", "imm", 0x00)
    a.op("sta", "zp", PAD1)
    a.op("ldx", "imm", 0x08)
    a.label("rp")
    a.op("lda", "abs", 0x4016)
    a.op("lsr", "acc")                    # 串行读出的位进 carry
    a.op("rol", "zp", PAD1)               # 依次压入 PAD1 的高位
    a.op("dex")
    a.op("bne", "rel", "rp")
    a.op("lda", "zp", PAD1)               # 只在按下的那一帧算一次，避免按住连开
    a.op("and", "imm", 0x10)
    a.op("sta", "zp", EDGE)
    a.op("lda", "zp", PREV)
    a.op("and", "imm", 0x10)
    a.op("eor", "imm", 0xFF)              # 上一帧按着就不算新的按下
    a.op("and", "zp", EDGE)
    a.op("sta", "zp", EDGE)
    a.op("lda", "zp", PAD1)
    a.op("sta", "zp", PREV)
    a.op("rts")

    a.label("nmi")
    a.op("pha")
    a.op("txa")
    a.op("pha")
    a.op("tya")
    a.op("pha")
    a.op("inc", "zp", FRAME)

    # 槽 0/1：卡带左半与右半（8x16）。结束页把它挪出画面，只留空柜。
    a.op("lda", "zp", STATE)
    a.op("cmp", "imm", ST_OVER)
    a.op("bne", "rel", "n_cart_y")
    a.op("lda", "imm", 0xF8)
    a.op("jmp", "abs", "n_cart_set")
    a.label("n_cart_y")
    a.op("lda", "zp", CARTY)
    a.label("n_cart_set")
    a.op("sta", "abs", 0x0200)
    a.op("sta", "abs", 0x0204)
    a.op("lda", "imm", TILE_CART_TL)
    a.op("sta", "abs", 0x0201)
    a.op("lda", "imm", TILE_CART_TR)
    a.op("sta", "abs", 0x0205)
    a.op("lda", "imm", 0x00)
    a.op("sta", "abs", 0x0202)
    a.op("sta", "abs", 0x0206)
    a.op("lda", "zp", CARTX)
    a.op("sta", "abs", 0x0203)
    a.op("lda", "zp", CARTX)
    a.op("clc")
    a.op("adc", "imm", 0x08)
    a.op("sta", "abs", 0x0207)

    # 槽 2-5：32 像素宽的托盘。标题页藏起来。
    a.op("lda", "zp", STATE)
    a.op("bne", "rel", "n_box_y")
    a.op("lda", "imm", 0xF8)
    a.op("jmp", "abs", "n_box_set")
    a.label("n_box_y")
    a.op("lda", "imm", BOX_Y)
    a.label("n_box_set")
    a.op("sta", "abs", 0x0208)
    a.op("sta", "abs", 0x020C)
    a.op("sta", "abs", 0x0210)
    a.op("sta", "abs", 0x0214)
    a.op("lda", "imm", TILE_BOX_L)
    a.op("sta", "abs", 0x0209)
    a.op("lda", "imm", TILE_BOX_L + 2)
    a.op("sta", "abs", 0x020D)
    a.op("lda", "imm", TILE_BOX_R2)
    a.op("sta", "abs", 0x0211)
    a.op("lda", "imm", TILE_BOX_R3)
    a.op("sta", "abs", 0x0215)
    a.op("lda", "imm", 0x00)
    a.op("sta", "abs", 0x020A)
    a.op("sta", "abs", 0x020E)
    a.op("sta", "abs", 0x0212)
    a.op("sta", "abs", 0x0216)
    a.op("lda", "zp", BOXX)
    a.op("sta", "abs", 0x020B)
    a.op("clc")
    a.op("adc", "imm", 0x08)
    a.op("sta", "abs", 0x020F)
    a.op("clc")
    a.op("adc", "imm", 0x08)
    a.op("sta", "abs", 0x0213)
    a.op("clc")
    a.op("adc", "imm", 0x08)
    a.op("sta", "abs", 0x0217)

    a.op("lda", "imm", 0x02)
    a.op("sta", "abs", 0x4014)            # OAM DMA

    a.op("lda", "zp", DIRTY)              # 提示行改写（进局抹掉 / 结束写回）
    a.op("beq", "rel", "n_bg")
    a.op("jsr", "abs", "write_prompt")
    a.label("n_bg")
    a.op("lda", "zp", STATE)
    a.op("beq", "rel", "n_blink")
    a.op("cmp", "imm", ST_PLAY)
    a.op("bne", "rel", "n_hud")            # 结束页不再清屏，但 HUD 还得刷最后的分数

    a.label("n_play")                      # 分批抹掉标题页文字
    a.op("ldx", "zp", UPD_IDX)
    a.op("cpx", "imm", CLEAR_COUNT)
    a.op("bcs", "rel", "n_hud")
    a.op("lda", "imm", 0x18)              # 每帧最多 24 格，留够消隐时间
    a.op("sta", "zp", UPD_N)
    a.label("n_clear")
    a.op("lda", "absx", "clear_hi")
    a.op("sta", "abs", 0x2006)
    a.op("lda", "absx", "clear_lo")
    a.op("sta", "abs", 0x2006)
    a.op("lda", "absx", "clear_tile")
    a.op("sta", "abs", 0x2007)
    a.op("inx")
    a.op("dec", "zp", UPD_N)
    a.op("bne", "rel", "n_clear")
    a.op("stx", "zp", UPD_IDX)

    a.label("n_hud")                       # SCORE 两位 + MISS 一位
    a.op("lda", "zp", SCORE)
    a.op("ldx", "imm", 0x00)
    a.op("sec")
    a.label("n_tens")
    a.op("cmp", "imm", 10)
    a.op("bcc", "rel", "n_tens_done")
    a.op("sbc", "imm", 10)
    a.op("inx")
    a.op("jmp", "abs", "n_tens")
    a.label("n_tens_done")
    a.op("sta", "zp", TMP)                # 个位
    a.op("stx", "zp", TMP2)               # 十位
    a.op("lda", "imm", SCORE_DIGIT_ADDR >> 8)
    a.op("sta", "abs", 0x2006)
    a.op("lda", "imm", SCORE_DIGIT_ADDR & 0xFF)
    a.op("sta", "abs", 0x2006)
    a.op("lda", "zp", TMP2)
    a.op("clc")
    a.op("adc", "imm", TILE_DIGIT)
    a.op("sta", "abs", 0x2007)
    a.op("lda", "zp", TMP)
    a.op("clc")
    a.op("adc", "imm", TILE_DIGIT)
    a.op("sta", "abs", 0x2007)
    a.op("lda", "imm", MISS_DIGIT_ADDR >> 8)
    a.op("sta", "abs", 0x2006)
    a.op("lda", "imm", MISS_DIGIT_ADDR & 0xFF)
    a.op("sta", "abs", 0x2006)
    a.op("lda", "zp", MISS)
    a.op("clc")
    a.op("adc", "imm", TILE_DIGIT)
    a.op("sta", "abs", 0x2007)
    a.op("jmp", "abs", "scroll")

    a.label("n_blink")                     # 标题页：提示色呼吸
    a.op("lda", "zp", FRAME)
    a.op("and", "imm", 0x1F)              # 每 32 帧改一次就够，少碰 $2006
    a.op("bne", "rel", "scroll")
    a.op("lda", "zp", FRAME)
    a.op("and", "imm", 0x20)
    a.op("beq", "rel", "blink_dim")
    a.op("lda", "imm", 0x27)
    a.op("jmp", "abs", "blink_set")
    a.label("blink_dim")
    a.op("lda", "imm", 0x17)
    a.label("blink_set")
    a.op("bit", "abs", 0x2002)
    a.op("ldx", "imm", 0x3F)
    a.op("stx", "abs", 0x2006)
    a.op("ldx", "imm", 0x0A)              # $3F0A = 2 号调色板的 index 2
    a.op("stx", "abs", 0x2006)
    a.op("sta", "abs", 0x2007)

    # 写 $2006 会连带把 t 的 nametable 选择位改成调色板那一段（$3F06 的 bit10-11 = 3）。
    # 只写 $2005 修不回来——它只动 coarse X/Y 和 fine Y。必须用 $2006 写两次 0
    # 把 v 和 t 一起复位，否则 PPU 会一直从空的 nametable 3 取图块，整屏全黑。
    a.label("scroll")
    a.op("lda", "imm", 0x00)
    a.op("sta", "abs", 0x2006)
    a.op("sta", "abs", 0x2006)
    a.op("sta", "abs", 0x2005)
    a.op("sta", "abs", 0x2005)
    a.op("pla")
    a.op("tay")
    a.op("pla")
    a.op("tax")
    a.op("pla")
    a.op("rti")

    a.label("write_prompt")                # DIRTY=1 抹掉，=2 写回 PRESS START
    a.op("lda", "zp", DIRTY)
    a.op("pha")
    a.op("lda", "imm", 0x00)
    a.op("sta", "zp", DIRTY)
    a.op("lda", "imm", 0x3F)              # 顺手把提示色恢复成亮琥珀
    a.op("sta", "abs", 0x2006)
    a.op("lda", "imm", 0x0A)
    a.op("sta", "abs", 0x2006)
    a.op("lda", "imm", 0x27)
    a.op("sta", "abs", 0x2007)
    a.op("lda", "imm", PROMPT_ADDR >> 8)
    a.op("sta", "abs", 0x2006)
    a.op("lda", "imm", PROMPT_ADDR & 0xFF)
    a.op("sta", "abs", 0x2006)
    a.op("pla")
    a.op("cmp", "imm", 0x01)
    a.op("beq", "rel", "wp_blank")
    a.op("ldx", "imm", 0x00)
    a.label("wp_text")
    a.op("lda", "absx", "prompt_text")
    a.op("sta", "abs", 0x2007)
    a.op("inx")
    a.op("cpx", "imm", PROMPT_LEN)
    a.op("bne", "rel", "wp_text")
    a.op("rts")
    a.label("wp_blank")
    a.op("lda", "imm", TILE_LATTICE)      # 抹回底纹，不是黑洞
    a.op("ldx", "imm", 0x00)
    a.label("wp_zero")
    a.op("sta", "abs", 0x2007)
    a.op("inx")
    a.op("cpx", "imm", PROMPT_LEN)
    a.op("bne", "rel", "wp_zero")
    a.op("rts")

    a.label("irq")
    a.op("rti")

    a.label("palette_data")
    a.data(PALETTE)
    a.label("screen")
    a.data(build_nametable())
    a.label("prompt_text")
    a.data(b"".join(bytes([tile_index(c)]) for c in PROMPT_TEXT))
    clear_hi, clear_lo, clear_tile = CLEAR_TABLE
    a.label("clear_hi")
    a.data(clear_hi)
    a.label("clear_lo")
    a.data(clear_lo)
    a.label("clear_tile")
    a.data(clear_tile)

    # 向量表固定在 PRG 尾部
    code = a.assemble()
    base = 0x8000
    vectors = bytearray(6)
    for i, name in enumerate(("nmi", "reset", "irq")):
        addr = a.labels[name]
        vectors[i * 2] = addr & 0xFF
        vectors[i * 2 + 1] = (addr >> 8) & 0xFF

    prg = bytearray(code)
    tail = 0x4000 - 6
    if len(prg) > tail:
        raise ValueError("PRG 超限：%d > %d" % (len(prg), tail))
    prg.extend(bytes(tail - len(prg)))
    prg.extend(vectors)
    return bytes(prg)


def build_rom():
    prg = build_prg()
    chr_bank = build_chr()
    header = bytes([
        0x4E, 0x45, 0x53, 0x1A,   # "NES" + MS-DOS EOF
        len(prg) // 16384,        # PRG 16K 页数
        len(chr_bank) // 8192,    # CHR 8K 页数
        0x00,                     # 水平镜像、无电池
        0x00,                     # 仅 iNES 0
    ]) + bytes(8)                 # 其余 8 字节留空，头部共 16 字节
    assert len(header) == 16, "iNES 头必须是 16 字节"
    return header + prg + chr_bank


def main():
    root = Path(__file__).resolve().parents[2]
    out = root / "RetroEmu" / "Demo" / "PocketMuseumDemo.nes"
    out.parent.mkdir(parents=True, exist_ok=True)
    rom = build_rom()
    out.write_bytes(rom)
    print("已生成 %s (%d 字节)" % (out.relative_to(root), len(rom)))
    print("  PRG 16K / CHR 8K / iNES 头 16 字节")


if __name__ == "__main__":
    main()
