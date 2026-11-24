#!/usr/bin/env python3
"""Golden-model MIPS32 ISS (non-pipelined): delay slots, branch-likely annulment, CP0 (Status, Cause,
EPC, BadVAddr, Compare), precise exceptions (overflow, address error, syscall, break, reserved
instruction), software interrupts, ERET, LWL/LWR/SWL/SWR.
Platform = rtl/mips_soc.v: data RAM at 0 (4 KiB); HALT 0xFFFF0000 (exit code), PUTCHAR 0xFFFF0004,
LEDS 0xFFFF0008; exception vector 0x180. Timer interrupts are not modelled (self-checking tests)."""
M = 0xffffffff
VECTOR = 0x180
def sx(v, bits): return v - (1 << bits) if v & (1 << (bits-1)) else v
class Result: pass
class Exc(Exception):
    def __init__(s, code, badv=None): s.code, s.badv = code, badv

SPECIAL_OK = {0,2,3,4,6,7,8,9,0xC,0xD,0x10,0x11,0x12,0x13,0x18,0x19,0x1A,0x1B,0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x2A,0x2B}
OPS_OK = {2,3,4,5,6,7,0x14,0x15,0x16,0x17,8,9,0xA,0xB,0xC,0xD,0xE,0xF,0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x28,0x29,0x2A,0x2B,0x2E}
REGIMM_OK = {0,1,2,3,0x10,0x11,0x12,0x13}

def run(words, max_steps=2_000_000):
    regs = [0]*32; hi = lo = 0; pc = 0; npc = 4; steps = 0
    mem = bytearray(4096); out = []; exit_code = None; leds = 0
    im = 0; exl = 0; ie = 0; bd = 0; soft = 0; exccode = 0; epc = 0; badv = 0; compare = M
    in_delay = False; branch_pc = 0

    def rd8(a): return mem[a] if a >> 12 == 0 else 0
    def ld(a, n, signed):
        v = int.from_bytes(mem[a:a+n], 'little') if a >> 12 == 0 else (leds if a == 0xFFFF0008 else 0)
        return (sx(v, 8*n) & M) if signed else v
    def st(a, n, v):
        nonlocal exit_code, leds
        if a >> 12 == 0: mem[a:a+n] = (v & ((1 << 8*n) - 1)).to_bytes(n, 'little')
        elif a == 0xFFFF0000: exit_code = v & M
        elif a == 0xFFFF0004: out.append(chr(v & 0xff))
        elif a == 0xFFFF0008: leds = v & 0xffff
    def cp0_read(r):
        if r == 8:  return badv
        if r == 9:  return steps & M                     # Count: nondeterministic vs RTL, tests avoid it
        if r == 11: return compare
        if r == 12: return (im << 8) | (exl << 1) | ie
        if r == 13: return (bd << 31) | (soft << 8) | (exccode << 2)
        if r == 14: return epc
        return 0
    def take(code, epc_pc, in_slot, bv=None):
        nonlocal exl, bd, epc, exccode, badv, pc, npc, in_delay
        if not exl: epc, bd = epc_pc, int(in_slot)
        exl = 1; exccode = code
        if bv is not None: badv = bv & M
        pc, npc, in_delay = VECTOR, VECTOR + 4, False

    while steps < max_steps and exit_code is None:
        steps += 1
        if ie and not exl and (soft & im & 3):                       # software interrupt, before this instruction
            take(0, branch_pc if in_delay else pc, in_delay); continue
        w = words[pc//4] if pc//4 < len(words) else 0
        cur = pc; was_delay = in_delay
        pc = npc; npc = (pc + 4) & M; in_delay = False
        op, rs, rt, rd, sh, fn = w >> 26, (w>>21)&31, (w>>16)&31, (w>>11)&31, (w>>6)&31, w & 63
        imm = w & 0xffff; simm = sx(imm, 16)
        a, b = regs[rs], regs[rt]
        res, dest = None, rd
        try:
            legal = ((op == 0 and fn in SPECIAL_OK) or (op == 0x1C and fn == 2) or (op == 1 and rt in REGIMM_OK)
                     or op in OPS_OK or
                     (op == 0x10 and ((rs in (0, 4) and (w >> 3) & 0xff == 0) or (rs == 0x10 and fn == 0x18))))
            if not legal: raise Exc(10)
            is_ctrl = False
            def branch(cond, likely=False):
                nonlocal npc, pc, is_ctrl
                is_ctrl = True
                if cond: npc = (cur + 4 + (simm << 2)) & M
                elif likely: pc = npc; npc = (pc + 4) & M; is_ctrl = False   # annul the delay slot
            if op == 0:
                if   fn == 0:  res = (b << sh) & M
                elif fn == 2:  res = b >> sh
                elif fn == 3:  res = (sx(b, 32) >> sh) & M
                elif fn == 4:  res = (b << (a & 31)) & M
                elif fn == 6:  res = b >> (a & 31)
                elif fn == 7:  res = (sx(b, 32) >> (a & 31)) & M
                elif fn == 8:  npc = a; is_ctrl = True
                elif fn == 9:  res = (cur + 8) & M; npc = a; is_ctrl = True
                elif fn == 0x0C: raise Exc(8)
                elif fn == 0x0D: raise Exc(9)
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
                elif fn in (0x20, 0x21):
                    s = sx(a,32) + sx(b,32)
                    if fn == 0x20 and not -(1<<31) <= s < (1<<31): raise Exc(12)
                    res = (a + b) & M
                elif fn in (0x22, 0x23):
                    s = sx(a,32) - sx(b,32)
                    if fn == 0x22 and not -(1<<31) <= s < (1<<31): raise Exc(12)
                    res = (a - b) & M
                elif fn == 0x24: res = a & b
                elif fn == 0x25: res = a | b
                elif fn == 0x26: res = a ^ b
                elif fn == 0x27: res = ~(a | b) & M
                elif fn == 0x2A: res = int(sx(a,32) < sx(b,32))
                elif fn == 0x2B: res = int(a < b)
            elif op == 0x1C: res = (sx(a,32)*sx(b,32)) & M
            elif op == 1:
                cond = sx(a,32) < 0 if rt in (0, 2, 0x10, 0x12) else sx(a,32) >= 0
                if rt >= 0x10: regs[31] = (cur + 8) & M
                branch(cond, likely=rt in (2, 3, 0x12, 0x13))
            elif op == 2: npc = ((cur + 4) & 0xf0000000) | ((w & 0x3ffffff) << 2); is_ctrl = True
            elif op == 3: regs[31] = (cur + 8) & M; npc = ((cur + 4) & 0xf0000000) | ((w & 0x3ffffff) << 2); is_ctrl = True
            elif op == 4:    branch(a == b)
            elif op == 5:    branch(a != b)
            elif op == 6:    branch(sx(a,32) <= 0)
            elif op == 7:    branch(sx(a,32) > 0)
            elif op == 0x14: branch(a == b, True)
            elif op == 0x15: branch(a != b, True)
            elif op == 0x16: branch(sx(a,32) <= 0, True)
            elif op == 0x17: branch(sx(a,32) > 0, True)
            elif op in (8, 9):
                if op == 8 and not -(1<<31) <= sx(a,32) + simm < (1<<31): raise Exc(12)
                res, dest = (a + simm) & M, rt
            elif op == 0xA: res, dest = int(sx(a,32) < simm), rt
            elif op == 0xB: res, dest = int(a < (simm & M)), rt
            elif op == 0xC: res, dest = a & imm, rt
            elif op == 0xD: res, dest = a | imm, rt
            elif op == 0xE: res, dest = a ^ imm, rt
            elif op == 0xF: res, dest = (imm << 16) & M, rt
            elif op == 0x10:
                if rs == 0:   res, dest = cp0_read(rd), rt
                elif rs == 4:
                    if   rd == 9:  pass
                    elif rd == 11: compare = b
                    elif rd == 12: im, exl, ie = (b >> 8) & 0xff, (b >> 1) & 1, b & 1
                    elif rd == 13: soft = (b >> 8) & 3
                    elif rd == 14: epc = b
                else:         # ERET: no delay slot
                    pc = epc; npc = (pc + 4) & M; exl = 0
            elif op in (0x20, 0x21, 0x23, 0x24, 0x25):
                addr = (a + simm) & M; n = {0x20:1, 0x24:1, 0x21:2, 0x25:2, 0x23:4}[op]
                if addr % n: raise Exc(4, addr)
                res, dest = ld(addr, n, op in (0x20, 0x21)), rt
            elif op in (0x28, 0x29, 0x2B):
                addr = (a + simm) & M; n = {0x28:1, 0x29:2, 0x2B:4}[op]
                if addr % n: raise Exc(5, addr)
                st(addr, n, b)
            elif op in (0x22, 0x26, 0x2A, 0x2E):         # LWL LWR SWL SWR (little-endian)
                addr = (a + simm) & M; base = addr & ~3; off = addr & 3
                if op == 0x22:
                    r = regs[rt]
                    for j in range(off + 1):
                        k = (3 - off) + j; r = (r & ~(0xff << 8*k)) | (rd8(base + j) << 8*k if base >> 12 == 0 else 0)
                    res, dest = r & M, rt
                elif op == 0x26:
                    r = regs[rt]
                    for j in range(off, 4):
                        k = j - off; r = (r & ~(0xff << 8*k)) | (rd8(base + j) << 8*k if base >> 12 == 0 else 0)
                    res, dest = r & M, rt
                elif op == 0x2A:
                    for j in range(off + 1):
                        if base >> 12 == 0: mem[base + j] = (b >> 8 * ((3 - off) + j)) & 0xff
                else:
                    for j in range(off, 4):
                        if base >> 12 == 0: mem[base + j] = (b >> 8 * (j - off)) & 0xff
            if res is not None and dest: regs[dest] = res & M
            in_delay = is_ctrl; branch_pc = cur
        except Exc as e:
            take(e.code, branch_pc if was_delay else cur, was_delay, e.badv)
    r = Result()
    r.regs, r.hi, r.lo, r.mem, r.exit_code, r.out, r.steps = regs, hi, lo, mem, exit_code, ''.join(out), steps
    r.epc, r.badv, r.cause = epc, badv, (bd << 31) | (soft << 8) | (exccode << 2)
    if exit_code is None: raise RuntimeError('ISS step limit exceeded')
    return r
