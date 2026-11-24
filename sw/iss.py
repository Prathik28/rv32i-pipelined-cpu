#!/usr/bin/env python3
"""Golden-model RV32IMA + Zicsr (M/U modes, PMP) instruction-set simulator, non-pipelined.
Same platform as the RTL (see rtl/riscv_soc.v): Harvard I/D memories, data RAM at 0, slow RAM at
0x2000_0000, instruction RAM visible at 0x3000_0000, MMIO at 0x1000_0000.
Models precise traps (all causes the core raises), MRET, PMP, LR/SC/AMO and hardware-handled
misaligned RAM accesses. Interrupts are timing dependent and are NOT modelled (self-checking
sc_*.s tests cover them)."""
M = 0xffffffff
def sx(v, bits): return v - (1 << bits) if v & (1 << (bits-1)) else v

KNOWN_CSR = {0x300,0x301,0x304,0x305,0x306,0x340,0x341,0x342,0x343,0x344,0x3A0,0x3B0,0x3B1,0x3B2,0x3B3,
             0xB00,0xB02,0xB80,0xB82,0xC00,0xC01,0xC02,0xC80,0xC81,0xC82,0xF11,0xF12,0xF13,0xF14}
AMO_OK_F5 = {0,1,2,3,4,8,12,16,20,24,28}

def is_illegal(w):
    if w & 3 != 3: return True
    op, f3, f7 = w & 0x7f, (w>>12)&7, w>>25
    if op == 0x33:  return not (f7 == 1 or f7 == 0 or (f7 == 0x20 and f3 in (0, 5)))
    if op == 0x13:  return (f3 == 1 and f7 != 0) or (f3 == 5 and f7 not in (0, 0x20))
    if op == 0x03:  return f3 not in (0,1,2,4,5)
    if op == 0x23:  return f3 > 2
    if op == 0x63:  return f3 in (2, 3)
    if op == 0x67:  return f3 != 0
    if op in (0x6f, 0x37, 0x17, 0x0f): return False
    if op == 0x2f:
        f5 = w >> 27
        return f3 != 2 or f5 not in AMO_OK_F5 or (f5 == 2 and ((w >> 20) & 31) != 0)
    if op == 0x73:
        if f3 == 0: return w not in (0x73, 0x100073, 0x30200073, 0x10500073)
        return f3 == 4
    return True

def region(a):
    if a >> 12 == 0: return 'ram'
    if a >> 12 == 0x20000: return 'slow'
    if a >> 12 == 0x30000: return 'iram'
    if a >> 8 == 0x100000: return 'mmio'
    return None

class Result: pass

def run(words, max_steps=2_000_000):
    regs = [0]*32; pc = 0; steps = 0
    ram = bytearray(4096); slow = bytearray(4096)
    imem = bytearray(b'\x13\x00\x00\x00' * 1024)
    for i, w in enumerate(words): imem[4*i:4*i+4] = (w & M).to_bytes(4, 'little')
    priv = 3; mie = mpie = 0; mpp = 1; msie = mtie = meie = 0
    mtvec = mscratch = mepc = mcause = mtval = 0; mcounteren = 0
    pcfg = [0]*4; paddr = [0]*4
    mmio = {'mtimecmp': M, 'mtimecmph': M, 'leds': 0, 'wait': 0, 'msip': 0, 'extirq': 0}
    out = []; exit_code = None; resv = None

    # ------------------------------------------------------------------ PMP
    def pmp_ok(lo, hi, kind):           # kind: 0=r 1=w 2=x
        wl, wh = (lo & M) >> 2, (hi & M) >> 2
        pv = [0] + [p & 0x3fffffff for p in paddr]
        for i in range(4):
            c = pcfg[i]; a = (c >> 3) & 3
            if a == 0: continue
            def m(w):
                if a == 1: return pv[i] <= w < pv[i+1]
                if a == 2: return w == pv[i+1]
                p = pv[i+1]; mask = ~(p ^ ((p + 1) & 0x3fffffff)) & 0x3fffffff
                return ((w ^ p) & mask) == 0
            ml, mh = m(wl), m(wh)
            if ml or mh:
                if priv == 3 and not (c & 0x80): return True
                return ml and mh and bool((c >> kind) & 1)
        return priv == 3

    class Trap(Exception):
        def __init__(s, cause, val=0): s.cause, s.val = cause, val

    # ------------------------------------------------------------- CSR access
    def csr_known(c): return c in KNOWN_CSR
    def csr_priv_ok(c):
        if (c >> 4) in (0xC0, 0xC8):
            bit = 0 if (c & 15) == 0 else 1 if (c & 15) == 1 else 2
            return priv == 3 or bool((mcounteren >> bit) & 1)
        return priv >= ((c >> 8) & 3)
    def csr_read(c):
        if c == 0x300: return ((3 if mpp else 0) << 11) | (mpie << 7) | (mie << 3)
        if c == 0x301: return 0x40101101
        if c == 0x304: return (meie << 11) | (mtie << 7) | (msie << 3)
        if c == 0x305: return mtvec
        if c == 0x306: return mcounteren
        if c == 0x340: return mscratch
        if c == 0x341: return mepc
        if c == 0x342: return mcause
        if c == 0x343: return mtval
        if c == 0x344: return (mmio['extirq'] << 11) | (mmio['msip'] << 3)
        if c == 0x3A0: return pcfg[0] | pcfg[1] << 8 | pcfg[2] << 16 | pcfg[3] << 24
        if 0x3B0 <= c <= 0x3B3: return paddr[c - 0x3B0]
        if c in (0xB00, 0xC00, 0xB02, 0xC02): return steps & M     # nondeterministic vs RTL: tests avoid
        return 0
    def pa_locked(i):
        return bool(pcfg[i] & 0x80) or (i < 3 and bool(pcfg[i+1] & 0x80) and ((pcfg[i+1] >> 3) & 3) == 1)

    # ------------------------------------------------------------ data memory
    def check_data(addr, n, rd, wr, amo):
        end = (addr + n - 1) & M
        rlo, rhi = region(addr), region(end)
        ok = rlo is not None and rlo == rhi
        if amo and rlo not in ('ram', 'slow'): ok = False
        if rd and not pmp_ok(addr, end, 0): ok = False
        if wr and not pmp_ok(addr, end, 1): ok = False
        if not ok: raise Trap(7 if wr else 5, addr)
        if addr & (n - 1) and (amo or rlo == 'mmio'): raise Trap(6 if wr else 4, addr)
    def mmio_reg(a):
        return {0: None, 2: mmio['mtimecmp'], 3: 0, 4: mmio['leds'], 5: mmio['wait'], 6: mmio['msip'],
                7: mmio['extirq'], 8: mmio['mtimecmph'], 9: 0}.get((a >> 2) & 63, 0)
    def mread(a, n):
        r = region(a)
        if r == 'mmio':
            v = mmio_reg(a & ~3) or 0
            return (v >> (8 * (a & 3))) & ((1 << (8*n)) - 1)
        buf = {'ram': ram, 'slow': slow, 'iram': imem}[r]; o = a & 0xfff
        return int.from_bytes(buf[o:o+n], 'little')
    def mwrite(a, n, v):
        nonlocal exit_code
        r = region(a); v &= (1 << (8*n)) - 1
        if r == 'mmio':
            idx = (a >> 2) & 63
            if idx == 0: exit_code = v
            elif idx == 1: out.append(chr(v & 0xff))
            elif idx == 2: mmio['mtimecmp'] = v
            elif idx == 4: mmio['leds'] = v & 0xffff
            elif idx == 5: mmio['wait'] = v & 15
            elif idx == 6: mmio['msip'] = v & 1
            elif idx == 7: mmio['extirq'] = v & 1
            elif idx == 8: mmio['mtimecmph'] = v
            return
        buf = {'ram': ram, 'slow': slow, 'iram': imem}[r]; o = a & 0xfff
        buf[o:o+n] = v.to_bytes(n, 'little')

    def amo_op(f5, old, b):
        sa, sb = sx(old, 32), sx(b, 32)
        return {1: b, 0: (old + b) & M, 4: old ^ b, 12: old & b, 8: old | b,
                16: old if sa < sb else b, 20: b if sa < sb else old,
                24: old if old < b else b, 28: b if old < b else old}[f5]

    while steps < max_steps and exit_code is None:
        steps += 1
        try:
            if pc >> 12 != 0 or not pmp_ok(pc, pc + 3, 2): raise Trap(1, pc)
            w = int.from_bytes(imem[pc:pc+4], 'little')
            if is_illegal(w) or (w == 0x30200073 and priv != 3): raise Trap(2, w)
            op, rd, f3 = w & 0x7f, (w>>7)&31, (w>>12)&7
            rs1, rs2, f7 = (w>>15)&31, (w>>20)&31, w>>25
            a, b = regs[rs1], regs[rs2]
            nxt, res = (pc+4) & M, None
            if op == 0x33 and f7 == 1:
                sa, sb = sx(a,32), sx(b,32)
                if   f3 == 0: res = (a*b) & M
                elif f3 == 1: res = ((sa*sb) >> 32) & M
                elif f3 == 2: res = ((sa*b) >> 32) & M
                elif f3 == 3: res = ((a*b) >> 32) & M
                elif f3 == 4: res = M if b == 0 else (a if (a == 0x80000000 and b == M) else (abs(sa)//abs(sb) * (1 if (sa<0)==(sb<0) else -1)) & M)
                elif f3 == 5: res = M if b == 0 else a // b
                elif f3 == 6: res = a if b == 0 else (0 if (a == 0x80000000 and b == M) else (abs(sa) % abs(sb) * (1 if sa >= 0 else -1)) & M)
                else:         res = a if b == 0 else a % b
            elif op == 0x33:
                if   f3==0: res = (a-b)&M if f7==0x20 else (a+b)&M
                elif f3==1: res = (a << (b&31)) & M
                elif f3==2: res = int(sx(a,32) < sx(b,32))
                elif f3==3: res = int(a < b)
                elif f3==4: res = a ^ b
                elif f3==5: res = (sx(a,32) >> (b&31)) & M if f7==0x20 else a >> (b&31)
                elif f3==6: res = a | b
                else:       res = a & b
            elif op == 0x13:
                imm = sx(w>>20, 12) & M
                if   f3==0: res = (a+imm)&M
                elif f3==1: res = (a << rs2) & M
                elif f3==2: res = int(sx(a,32) < sx(imm,32))
                elif f3==3: res = int(a < imm)
                elif f3==4: res = a ^ imm
                elif f3==5: res = (sx(a,32) >> rs2) & M if f7==0x20 else a >> rs2
                elif f3==6: res = a | imm
                else:       res = a & imm
            elif op == 0x03:
                addr = (a + sx(w>>20,12)) & M; n = 1 << (f3 & 3)
                check_data(addr, n, True, False, False)
                v = mread(addr, n); res = (sx(v, 8*n) & M) if f3 < 4 else v
            elif op == 0x23:
                imm = sx(((w>>25)<<5)|((w>>7)&31), 12)
                addr = (a+imm)&M; n = 1 << f3
                check_data(addr, n, False, True, False)
                mwrite(addr, n, b)
            elif op == 0x2f:
                f5 = w >> 27; addr = a
                if f5 == 2:
                    check_data(addr, 4, True, False, True); res = mread(addr, 4); resv = addr >> 2
                elif f5 == 3:
                    check_data(addr, 4, False, True, True)
                    if resv == addr >> 2: mwrite(addr, 4, b); res = 0
                    else: res = 1
                    resv = None
                else:
                    check_data(addr, 4, True, True, True)
                    old = mread(addr, 4); mwrite(addr, 4, amo_op(f5, old, b)); res = old
            elif op == 0x63:
                imm = sx((((w>>31)&1)<<12)|(((w>>7)&1)<<11)|(((w>>25)&0x3f)<<5)|(((w>>8)&0xf)<<1), 13)
                sa, sb = sx(a,32), sx(b,32)
                t = {0:a==b,1:a!=b,4:sa<sb,5:sa>=sb,6:a<b,7:a>=b}[f3]
                if t:
                    nxt = (pc+imm)&M
                    if nxt & 2: raise Trap(0, nxt)
            elif op == 0x6f:
                imm = sx((((w>>31)&1)<<20)|(((w>>12)&0xff)<<12)|(((w>>20)&1)<<11)|(((w>>21)&0x3ff)<<1), 21)
                res = (pc+4)&M; nxt = (pc+imm)&M
                if nxt & 2: raise Trap(0, nxt)
            elif op == 0x67:
                res = (pc+4)&M; nxt = (a + sx(w>>20,12)) & M & ~1
                if nxt & 2: raise Trap(0, nxt)
            elif op == 0x37: res = w & 0xfffff000
            elif op == 0x17: res = (pc + (w & 0xfffff000)) & M
            elif op == 0x73:
                if f3 == 0:
                    if   w == 0x73:       raise Trap(11 if priv == 3 else 8)
                    elif w == 0x100073:   raise Trap(3)
                    elif w == 0x30200073:
                        nxt = mepc; priv = 3 if mpp else 0; mie = mpie; mpie = 1; mpp = 0
                else:
                    c = w >> 20
                    src = rs1 if f3 >= 5 else a
                    do_write = (f3 & 3) == 1 or rs1 != 0
                    if not csr_known(c) or not csr_priv_ok(c) or (do_write and (c >> 10) == 3): raise Trap(2, w)
                    old = csr_read(c); res = old
                    if do_write:
                        nv = src if (f3&3) == 1 else (old | src) if (f3&3) == 2 else (old & ~src) & M
                        if   c == 0x300:
                            mie, mpie = (nv>>3)&1, (nv>>7)&1
                            if (nv >> 11) & 3 == 3: mpp = 1
                            elif (nv >> 11) & 3 == 0: mpp = 0
                        elif c == 0x304: msie, mtie, meie = (nv>>3)&1, (nv>>7)&1, (nv>>11)&1
                        elif c == 0x305: mtvec = (nv & ~3 & M) | (nv & 1)
                        elif c == 0x306: mcounteren = nv & 7
                        elif c == 0x340: mscratch = nv
                        elif c == 0x341: mepc = nv & ~3 & M
                        elif c == 0x342: mcause = nv
                        elif c == 0x343: mtval = nv
                        elif c == 0x3A0:
                            for k in range(4):
                                nb = (nv >> (8*k)) & 0x9F
                                if not (pcfg[k] & 0x80) and not ((nb >> 1) & 1 and not nb & 1): pcfg[k] = nb
                        elif 0x3B0 <= c <= 0x3B3:
                            if not pa_locked(c - 0x3B0): paddr[c - 0x3B0] = nv
            if res is not None and rd: regs[rd] = res & M
            pc = nxt
        except Trap as t:
            mepc, mcause, mtval = pc, t.cause, t.val
            mpie, mie, mpp, priv = mie, 0, int(priv == 3), 3
            resv = None
            pc = mtvec & ~3 & M
    r = Result()
    r.regs, r.exit_code, r.out, r.steps = regs, exit_code, ''.join(out), steps
    r.mem, r.slow = ram, slow
    if exit_code is None: raise RuntimeError('ISS step limit exceeded')
    return r
