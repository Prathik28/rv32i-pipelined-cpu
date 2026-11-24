#!/usr/bin/env python3
"""Golden-model MIPS32 integer ISS (non-pipelined) with branch delay slots.
Platform = rtl/mips_soc.v: data RAM at 0 (4 KiB), PUTCHAR at 0xFFFF0004, SYSCALL ends the run
with $a0 as the exit code. Divide-by-zero / overflow results follow rtl/mips_div.v."""
M = 0xffffffff
def sx(v, bits): return v - (1 << bits) if v & (1 << (bits-1)) else v
class Result: pass

def run(words, max_steps=2_000_000):
    regs = [0]*32; hi = lo = 0; pc = 0; npc = 4; steps = 0
    mem = bytearray(4096); out = []; exit_code = None
    def ld(a, n, signed):
        if a % n: raise RuntimeError(f'misaligned load @{a:#x}')
        v = int.from_bytes(mem[a:a+n], 'little') if a >> 12 == 0 else 0
        return (sx(v, 8*n) & M) if signed else v
    def st(a, n, v):
        if a % n: raise RuntimeError(f'misaligned store @{a:#x}')
        if a >> 12 == 0: mem[a:a+n] = (v & ((1 << 8*n) - 1)).to_bytes(n, 'little')
        elif a == 0xFFFF0004: out.append(chr(v & 0xff))
    while steps < max_steps and exit_code is None:
        steps += 1
        w = words[pc//4] if pc//4 < len(words) else 0
        cur = pc; pc = npc; npc = (pc + 4) & M
        op, rs, rt, rd, sh, fn = w >> 26, (w>>21)&31, (w>>16)&31, (w>>11)&31, (w>>6)&31, w & 63
        imm = w & 0xffff; simm = sx(imm, 16)
        a, b = regs[rs], regs[rt]
        res, dest = None, rd
        if op == 0:
            if   fn == 0:  res = (b << sh) & M
            elif fn == 2:  res = b >> sh
            elif fn == 3:  res = (sx(b, 32) >> sh) & M
            elif fn == 4:  res = (b << (a & 31)) & M
            elif fn == 6:  res = b >> (a & 31)
            elif fn == 7:  res = (sx(b, 32) >> (a & 31)) & M
            elif fn == 8:  npc = a
            elif fn == 9:  res = (cur + 8) & M; npc = a
            elif fn == 0x0C: exit_code = regs[4]
            elif fn == 0x10: res = hi
            elif fn == 0x11: hi = a
            elif fn == 0x12: res = lo
            elif fn == 0x13: lo = a
            elif fn == 0x18: p = sx(a,32)*sx(b,32); hi, lo = (p >> 32) & M, p & M
            elif fn == 0x19: p = a*b; hi, lo = (p >> 32) & M, p & M
            elif fn == 0x1A:
                if b == 0: lo, hi = M, a
                elif a == 0x80000000 and b == M: lo, hi = 0x80000000, 0
                else:
                    sa, sb = sx(a,32), sx(b,32); q = abs(sa)//abs(sb) * (1 if (sa<0)==(sb<0) else -1)
                    lo, hi = q & M, (sa - q*sb) & M
            elif fn == 0x1B:
                if b == 0: lo, hi = M, a
                else: lo, hi = a // b, a % b
            elif fn in (0x20, 0x21): res = (a + b) & M
            elif fn in (0x22, 0x23): res = (a - b) & M
            elif fn == 0x24: res = a & b
            elif fn == 0x25: res = a | b
            elif fn == 0x26: res = a ^ b
            elif fn == 0x27: res = ~(a | b) & M
            elif fn == 0x2A: res = int(sx(a,32) < sx(b,32))
            elif fn == 0x2B: res = int(a < b)
        elif op == 0x1C and fn == 2: res = (sx(a,32)*sx(b,32)) & M
        elif op == 1:
            if rt in (0, 1, 0x10, 0x11):
                cond = sx(a,32) < 0 if rt in (0, 0x10) else sx(a,32) >= 0
                if rt >= 0x10: regs[31] = (cur + 8) & M
                if cond: npc = (cur + 4 + (simm << 2)) & M
        elif op == 2: npc = ((cur + 4) & 0xf0000000) | ((w & 0x3ffffff) << 2)
        elif op == 3: regs[31] = (cur + 8) & M; npc = ((cur + 4) & 0xf0000000) | ((w & 0x3ffffff) << 2)
        elif op == 4:
            if a == b: npc = (cur + 4 + (simm << 2)) & M
        elif op == 5:
            if a != b: npc = (cur + 4 + (simm << 2)) & M
        elif op == 6:
            if sx(a,32) <= 0: npc = (cur + 4 + (simm << 2)) & M
        elif op == 7:
            if sx(a,32) > 0: npc = (cur + 4 + (simm << 2)) & M
        elif op in (8, 9): res, dest = (a + simm) & M, rt
        elif op == 0xA: res, dest = int(sx(a,32) < simm), rt
        elif op == 0xB: res, dest = int(a < (simm & M)), rt
        elif op == 0xC: res, dest = a & imm, rt
        elif op == 0xD: res, dest = a | imm, rt
        elif op == 0xE: res, dest = a ^ imm, rt
        elif op == 0xF: res, dest = (imm << 16) & M, rt
        elif op == 0x20: res, dest = ld((a + simm) & M, 1, True), rt
        elif op == 0x21: res, dest = ld((a + simm) & M, 2, True), rt
        elif op == 0x23: res, dest = ld((a + simm) & M, 4, False), rt
        elif op == 0x24: res, dest = ld((a + simm) & M, 1, False), rt
        elif op == 0x25: res, dest = ld((a + simm) & M, 2, False), rt
        elif op == 0x28: st((a + simm) & M, 1, b)
        elif op == 0x29: st((a + simm) & M, 2, b)
        elif op == 0x2B: st((a + simm) & M, 4, b)
        if res is not None and dest: regs[dest] = res & M
    r = Result(); r.regs, r.hi, r.lo, r.mem, r.exit_code, r.out, r.steps = regs, hi, lo, mem, exit_code, ''.join(out), steps
    if exit_code is None: raise RuntimeError('ISS step limit exceeded')
    return r
