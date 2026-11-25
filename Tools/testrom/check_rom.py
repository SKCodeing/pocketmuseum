#!/usr/bin/env python3
"""离线跑一遍演示 ROM，用来定位卡死 / 空屏这类问题。

只实现 6502 里本项目用到的指令，PPU 用最小桩：$2002 读到 vblank 置位、
记录对 $2000/$2001/$2006/$2007 的写入，并按 PPUCTRL 的开位定期触发 NMI。
这样不用反复装机就能看出 CPU 走到哪、画面数据有没有写出去。

用法：
    python3 tools/testrom/check_rom.py [rom路径] [-n 帧数]
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_demo_rom as rom_builder  # noqa: E402

REV = {}
for (mnem, mode), opcode in rom_builder.OPCODES.items():
    REV.setdefault(opcode, (mnem, mode))

C, Z, I, D, B, U, V, N = 1, 2, 4, 8, 16, 32, 64, 128


class Machine:
    def __init__(self, rom, pad=0x00):
        prg = rom[16:16 + 16384]
        self.mem = bytearray(0x10000)
        self.mem[0x8000:0x8000 + len(prg)] = prg
        self.a = self.x = self.y = 0
        self.sp = 0xFF
        self.pc = prg[0x3FFC] | prg[0x3FFD] << 8
        self.flags = U | I
        self.cycles = 0
        self.vram_addr = 0
        self.addr_latch = False
        self.vram_writes = []
        self.ppuctrl = 0
        self.ppumask = 0
        self.nmi_count = 0
        self.nmi_due = False
        self.nmi_blocked = None
        self.illegal = None
        self.pcs = {}
        # 手柄：A=bit0 B=bit1 Select=bit2 Start=bit3 Up=bit4 Down=bit5 Left=bit6 Right=bit7
        self.pad_buttons = pad
        self.pad_shift = 0
        self.pad_strobe = False

    # -- 小工具 --------------------------------------------------------
    def rd(self, addr):
        addr &= 0xFFFF
        if addr == 0x2002:                 # $2002：vblank 永远置位
            self.addr_latch = False
            return 0x80
        if addr == 0x4016:                 # 手柄：按 write 1/0 选通后的串行位
            if self.pad_strobe:
                return self.pad_buttons & 1
            bit = self.pad_shift & 1
            self.pad_shift >>= 1
            return bit
        if addr == 0x4017:
            return 0
        return self.mem[addr]

    def wr(self, addr, value):
        addr &= 0xFFFF
        value &= 0xFF
        if addr == 0x4016:
            self.pad_strobe = bool(value & 1)
            if self.pad_strobe:
                self.pad_shift = self.pad_buttons
            return
        if addr == 0x2000:
            self.ppuctrl = value
            if value & 0x80:
                self.nmi_due = True
            return
        if addr == 0x2001:
            self.ppumask = value
            return
        if addr == 0x2003 or addr == 0x4014:
            return
        if addr == 0x2005:
            return
        if addr == 0x2006:
            if self.addr_latch:
                self.vram_addr = (self.vram_addr & 0xFF00) | value
            else:
                self.vram_addr = (self.vram_addr & 0x00FF) | (value << 8)
            self.addr_latch = not self.addr_latch
            return
        if addr == 0x2007:
            self.vram_writes.append((self.vram_addr, value))
            self.vram_addr = (self.vram_addr + (32 if self.ppuctrl & 0x04 else 1)) & 0x7FFF
            return
        self.mem[addr] = value

    def push(self, value):
        self.mem[0x100 + self.sp] = value & 0xFF
        self.sp = (self.sp - 1) & 0xFF

    def pop(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.mem[0x100 + self.sp]

    def set_nz(self, value):
        self.flags &= ~(Z | N)
        if value == 0:
            self.flags |= Z
        if value & 0x80:
            self.flags |= N

    def set_flag(self, bit, on):
        if on:
            self.flags |= bit
        else:
            self.flags &= ~bit

    # -- 寻址 ----------------------------------------------------------
    def operand_addr(self, mode):
        # 操作数从操作码的下一字节开始，别拿 self.pc 当操作数起点
        pc = self.pc + 1
        if mode == 'zp':
            return self.mem[pc]
        if mode == 'zpx':
            return (self.mem[pc] + self.x) & 0xFF
        if mode == 'zpy':
            return (self.mem[pc] + self.y) & 0xFF
        if mode == 'ind':
            return self.mem[pc] | self.mem[pc + 1] << 8
        if mode == 'abs':
            return self.mem[pc] | self.mem[pc + 1] << 8
        if mode == 'absx':
            return ((self.mem[pc] | self.mem[pc + 1] << 8) + self.x) & 0xFFFF
        if mode == 'absy':
            return ((self.mem[pc] | self.mem[pc + 1] << 8) + self.y) & 0xFFFF
        if mode == 'indy':
            zp = self.mem[pc]
            base = self.mem[zp] | self.mem[(zp + 1) & 0xFF] << 8
            return (base + self.y) & 0xFFFF
        if mode == 'indx':
            zp = (self.mem[pc] + self.x) & 0xFF
            return self.mem[zp] | self.mem[(zp + 1) & 0xFF] << 8
        raise ValueError(mode)

    # -- 执行一条 ------------------------------------------------------
    def step(self):
        pc = self.pc
        opcode = self.mem[pc]
        if opcode not in REV:
            self.illegal = (pc, opcode)
            return False
        mnem, mode = REV[opcode]
        size = rom_builder.SIZES[mode]
        operand = self.mem[pc + 1:pc + size]
        imm = operand[0] if size >= 2 else None
        addr = None
        if mode in ('zp', 'zpx', 'zpy', 'abs', 'absx', 'absy', 'indy', 'indx'):
            addr = self.operand_addr(mode)
        self.pc = (pc + size) & 0xFFFF
        self.cycles += size

        def value_at(a):
            return self.rd(a)

        if mnem == 'lda':
            self.a = imm if mode == 'imm' else value_at(addr)
            self.set_nz(self.a)
        elif mnem == 'ldx':
            self.x = imm if mode == 'imm' else value_at(addr)
            self.set_nz(self.x)
        elif mnem == 'ldy':
            self.y = imm if mode == 'imm' else value_at(addr)
            self.set_nz(self.y)
        elif mnem == 'sta':
            self.wr(addr, self.a)
        elif mnem == 'stx':
            self.wr(addr, self.x)
        elif mnem == 'sty':
            self.wr(addr, self.y)
        elif mnem == 'tax':
            self.x = self.a
            self.set_nz(self.x)
        elif mnem == 'tay':
            self.y = self.a
            self.set_nz(self.y)
        elif mnem == 'txa':
            self.a = self.x
            self.set_nz(self.a)
        elif mnem == 'tya':
            self.a = self.y
            self.set_nz(self.a)
        elif mnem == 'tsx':
            self.x = self.sp
            self.set_nz(self.x)
        elif mnem == 'txs':
            self.sp = self.x
        elif mnem == 'inx':
            self.x = (self.x + 1) & 0xFF
            self.set_nz(self.x)
        elif mnem == 'iny':
            self.y = (self.y + 1) & 0xFF
            self.set_nz(self.y)
        elif mnem == 'dex':
            self.x = (self.x - 1) & 0xFF
            self.set_nz(self.x)
        elif mnem == 'dey':
            self.y = (self.y - 1) & 0xFF
            self.set_nz(self.y)
        elif mnem == 'inc':
            v = (value_at(addr) + 1) & 0xFF
            self.wr(addr, v)
            self.set_nz(v)
        elif mnem == 'dec':
            v = (value_at(addr) - 1) & 0xFF
            self.wr(addr, v)
            self.set_nz(v)
        elif mnem in ('adc', 'sbc'):
            carry = 1 if self.flags & C else 0
            operand_value = imm if mode == 'imm' else value_at(addr)
            if mnem == 'sbc':
                operand_value = (~operand_value) & 0xFF
            total = self.a + operand_value + carry
            self.set_flag(C, total > 0xFF)
            self.set_flag(V, (~(self.a ^ operand_value) & (self.a ^ total) & 0x80) != 0)
            self.a = total & 0xFF
            self.set_nz(self.a)
        elif mnem == 'and':
            self.a &= (imm if mode == 'imm' else value_at(addr))
            self.set_nz(self.a)
        elif mnem == 'ora':
            self.a |= (imm if mode == 'imm' else value_at(addr))
            self.set_nz(self.a)
        elif mnem == 'eor':
            self.a ^= (imm if mode == 'imm' else value_at(addr))
            self.set_nz(self.a)
        elif mnem in ('cmp', 'cpx', 'cpy'):
            reg = {'cmp': self.a, 'cpx': self.x, 'cpy': self.y}[mnem]
            operand_value = imm if mode == 'imm' else value_at(addr)
            self.set_flag(C, reg >= operand_value)
            self.set_nz((reg - operand_value) & 0xFF)
        elif mnem == 'bit':
            v = value_at(addr)
            self.set_flag(Z, (self.a & v) == 0)
            self.flags &= ~(N | V)
            self.flags |= v & 0xC0
        elif mnem in ('asl', 'lsr', 'rol', 'ror'):
            if mode == 'acc':
                v = self.a
            else:
                v = value_at(addr)
            if mnem == 'asl':
                self.set_flag(C, v & 0x80)
                v = (v << 1) & 0xFF
            elif mnem == 'lsr':
                self.set_flag(C, v & 0x01)
                v >>= 1
            elif mnem == 'rol':
                carry = 1 if self.flags & C else 0
                self.set_flag(C, v & 0x80)
                v = ((v << 1) | carry) & 0xFF
            else:
                carry = 1 if self.flags & C else 0
                self.set_flag(C, v & 0x01)
                v = (v >> 1) | (carry << 7)
            if mode == 'acc':
                self.a = v
            else:
                self.wr(addr, v)
            self.set_nz(v)
        elif mnem == 'pha':
            self.push(self.a)
        elif mnem == 'pla':
            self.a = self.pop()
            self.set_nz(self.a)
        elif mnem == 'php':
            self.push(self.flags | B | U)
        elif mnem == 'plp':
            self.flags = (self.pop() | U) & ~B
        elif mnem == 'jmp':
            self.pc = addr if mode == 'abs' else self.mem[addr] | self.mem[(addr + 1) & 0xFFFF] << 8
        elif mnem == 'jsr':
            ret = (self.pc - 1) & 0xFFFF
            self.push(ret >> 8)
            self.push(ret & 0xFF)
            self.pc = addr
        elif mnem == 'rts':
            lo = self.pop()
            hi = self.pop()
            self.pc = ((hi << 8) | lo) + 1 & 0xFFFF
        elif mnem == 'rti':
            self.flags = (self.pop() | U) & ~B
            lo = self.pop()
            hi = self.pop()
            self.pc = (hi << 8) | lo
        elif mnem in ('bpl', 'bmi', 'bvc', 'bvs', 'bcc', 'bcs', 'bne', 'beq'):
            delta = imm - 256 if imm > 127 else imm
            take = {
                'bpl': not self.flags & N, 'bmi': bool(self.flags & N),
                'bvc': not self.flags & V, 'bvs': bool(self.flags & V),
                'bcc': not self.flags & C, 'bcs': bool(self.flags & C),
                'bne': not self.flags & Z, 'beq': bool(self.flags & Z),
            }[mnem]
            if take:
                self.pc = (self.pc + delta) & 0xFFFF
        elif mnem == 'sei':
            self.flags |= I
        elif mnem == 'cli':
            self.flags &= ~I
        elif mnem == 'cld':
            self.flags &= ~D
        elif mnem == 'sed':
            self.flags |= D
        elif mnem == 'clc':
            self.flags &= ~C
        elif mnem == 'sec':
            self.flags |= C
        elif mnem == 'clv':
            self.flags &= ~V
        elif mnem == 'nop':
            pass
        else:
            raise ValueError(mnem)
        return True

    def trigger_nmi(self):
        if not self.ppuctrl & 0x80:
            self.nmi_blocked = 'PPUCTRL bit7=0，NMI 从未开启'
            return
        if self.flags & I:
            self.nmi_blocked = 'I 屏蔽位始终没清（缺 cli），NMI 进不来'
            return
        self.push(self.pc >> 8)
        self.push(self.pc & 0xFF)
        self.push((self.flags | U) & ~B)
        self.flags |= I
        lo = self.mem[0xFFFA] | self.mem[0xFFFB] << 8
        self.pc = lo
        self.nmi_count += 1

    def run(self, frames=3, per_frame=29780):
        target = frames * per_frame
        next_nmi = per_frame
        while self.cycles < target:
            self.pcs[self.pc] = self.pcs.get(self.pc, 0) + 1
            if not self.step():
                return "非法指令 $%02X @ $%04X" % (self.illegal[1], self.illegal[0])
            if self.cycles >= next_nmi:
                next_nmi += per_frame
                self.trigger_nmi()
        return None


def main():
    argv = sys.argv[1:]
    rom_path = Path(argv[0]) if argv and not argv[0].startswith('-') else \
        Path(__file__).resolve().parents[2] / 'RetroEmu' / 'Demo' / 'PocketMuseumDemo.nes'
    frames = 3
    if '-n' in argv:
        frames = int(argv[argv.index('-n') + 1])
    pad = 0x00
    if '-p' in argv:
        pad = int(argv[argv.index('-p') + 1], 0)

    rom = rom_path.read_bytes()
    cpu = Machine(rom, pad=pad)
    # 向量表在 PRG 尾部
    prg = rom[16:16 + 16384]
    cpu.mem[0xFFFA] = prg[0x3FFA]
    cpu.mem[0xFFFB] = prg[0x3FFB]
    cpu.mem[0xFFFC] = prg[0x3FFC]
    cpu.mem[0xFFFD] = prg[0x3FFD]

    problem = cpu.run(frames=frames)
    print('复位入口 $%04X' % (prg[0x3FFC] | prg[0x3FFD] << 8))
    print('跑完 %d 帧，%s' % (frames, problem or '未卡死'))
    print('PPUCTRL=$%02X PPUMASK=$%02X  NMI 次数=%d' % (cpu.ppuctrl, cpu.ppumask, cpu.nmi_count))
    if cpu.nmi_count == 0 and cpu.nmi_blocked:
        print('  NMI 未触发：%s' % cpu.nmi_blocked)
    hottest = sorted(cpu.pcs.items(), key=lambda kv: -kv[1])[:3]
    print('执行最热的三处地址：' + '  '.join('$%04X×%d' % kv for kv in hottest))
    print('$2007 写入 %d 次' % len(cpu.vram_writes))
    if cpu.vram_writes:
        first = cpu.vram_writes[0]
        last = cpu.vram_writes[-1]
        print('  首次写入地址 $%04X 值 $%02X' % first)
        print('  末次写入地址 $%04X 值 $%02X' % last)
        nametable = [v for a, v in cpu.vram_writes if 0x2000 <= a < 0x2400]
        print('  落在 $2000-$23FF 的写入 %d 次，非零 %d 个' %
              (len(nametable), sum(1 for v in nametable if v)))
        palette = [v for a, v in cpu.vram_writes if 0x3F00 <= a < 0x3F20]
        print('  调色板写入 %d 次' % len(palette))
    print('零页 0x10-0x17:', ' '.join('%02X' % cpu.mem[i] for i in range(0x10, 0x18)))
    print('OAM 前 8 字节:', ' '.join('%02X' % cpu.mem[0x200 + i] for i in range(8)))
    return 0 if problem is None else 1


if __name__ == '__main__':
    sys.exit(main())
