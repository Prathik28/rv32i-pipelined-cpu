#!/usr/bin/env python3
"""Golden-model RV32IM + Zicsr (machine mode) instruction-set simulator, non-pipelined.
Same platform as the RTL: Harvard (imem separate), 4 KiB data RAM at 0, MMIO at 0x1000_0000.
Models traps precisely (illegal, ecall, ebreak, misaligned) and MRET. Timer interrupts are not
modelled (they are timing dependent) -- those tests are self-checking instead."""
M = 0xffffffff
def sx(v, bits): return v - (1 << bits) if v & (1 << (bits-1)) else v

KNOWN_CSR = {0x300,0x301,0x304,0x305,0x340,0x341,0x342,0x343,0x344,0xB00,0xB02,0xB80,0xB82,
             0xC00,0xC02,0xC80,0xC82,0xF11,0xF12,0xF13,0xF14}

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
    if op == 0x73:
        if f3 == 0: return w not in (0x73, 0x100073, 0x30200073, 0x10500073)
        return f3 == 4
    return True

class Result: pass

def run(words, dmem_bytes=4096, max_steps=2_000_000):
    regs = [0]*32; mem = bytearray(dmem_bytes); pc = 0; steps = 0
    mstatus_mie = mpie = mtie = 0
    csr = {'mtvec':0,'mscratch':0,'mepc':0,'mcause':0,'mtval':0}
    mtimecmp = M; leds = 0; out = []; exit_code = None

    def csr_read(a):
        if a == 0x300: return (3<<11) | (mpie<<7) | (mstatus_mie<<3)
        if a == 0x301: return 0x40001100
        if a == 0x304: return mtie << 7
        if a == 0x305: return csr['mtvec']
        if a == 0x340: return csr['mscratch']
        if a == 0x341: return csr['mepc']
        if a == 0x342: return csr['mcause']
        if a == 0x343: return csr['mtval']
        if a in (0xB00,0xC00): return steps & M
        if a in (0xB02,0xC02): return steps & M
        return 0
    def ld(a, n, signed):
        if a & 0xf0000000 == 0x10000000:
            r = {0x10000008: mtimecmp, 0x1000000c: 0, 0x10000010: leds}.get(a & ~3 & M, 0)
            v = (r >> (8*(a & 3))) & ((1 << 8*n) - 1)
        else:
            v = int.from_bytes(bytes(mem[(a+i) % dmem_bytes] for i in range(n)), 'little')
        return (sx(v, 8*n) & M) if signed else v
    def st(a, n, v):
        nonlocal mtimecmp, leds, exit_code
        if a & 0xf0000000 == 0x10000000:
            if (a & 0x0fffffc0) != 0: return
            r = (a >> 2) & 0xf
            if r == 0: exit_code = v & M
            elif r == 1: out.append(chr(v & 0xff))
            elif r == 2: mtimecmp = v & M
            elif r == 4: leds = v & 0xffff
            return
        for i in range(n): mem[(a+i) % dmem_bytes] = (v >> (8*i)) & 0xff

    class Trap(Exception):
        def __init__(s, cause, val=0): s.cause, s.val = cause, val

    while steps < max_steps and exit_code is None:
        steps += 1
        w = words[pc//4] if pc//4 < len(words) else 0x13
        try:
            if is_illegal(w): raise Trap(2, w)
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
                if addr % n: raise Trap(4, addr)
                res = ld(addr, n, f3 < 4)
            elif op == 0x23:
                imm = sx(((w>>25)<<5)|((w>>7)&31), 12)
                addr = (a+imm)&M; n = 1 << f3
                if addr % n: raise Trap(6, addr)
                st(addr, n, b)
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
                    if   w == 0x73:       raise Trap(11)
                    elif w == 0x100073:   raise Trap(3)
                    elif w == 0x30200073:
                        nxt = csr['mepc']; mstatus_mie = mpie; mpie = 1
                else:
                    c = w >> 20
                    if c not in KNOWN_CSR: raise Trap(2, w)
                    src = rs1 if f3 >= 5 else a
                    do_write = (f3 & 3) == 1 or rs1 != 0
                    if do_write and (c >> 10) == 3: raise Trap(2, w)
                    old = csr_read(c); res = old
                    if do_write:
                        nv = src if (f3&3) == 1 else (old | src) if (f3&3) == 2 else (old & ~src) & M
                        if   c == 0x300: mstatus_mie, mpie = (nv>>3)&1, (nv>>7)&1
                        elif c == 0x304: mtie = (nv>>7)&1
                        elif c == 0x305: csr['mtvec'] = nv & ~3 & M
                        elif c == 0x340: csr['mscratch'] = nv
                        elif c == 0x341: csr['mepc'] = nv & ~3 & M
                        elif c == 0x342: csr['mcause'] = nv
                        elif c == 0x343: csr['mtval'] = nv
            if res is not None and rd: regs[rd] = res & M
            pc = nxt
        except Trap as t:
            csr['mepc'], csr['mcause'], csr['mtval'] = pc, t.cause, t.val
            mpie, mstatus_mie = mstatus_mie, 0
            pc = csr['mtvec']
    r = Result()
    r.regs, r.mem, r.steps, r.exit_code, r.out = regs, mem, steps, exit_code, ''.join(out)
    if exit_code is None: raise RuntimeError('ISS step limit exceeded')
    return r
