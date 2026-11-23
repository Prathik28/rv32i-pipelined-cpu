#!/usr/bin/env python3
"""Golden-model RV32I instruction-set simulator (non-pipelined).
Harvard layout, same as the RTL: program in imem, data memory is 4 KiB from address 0."""
M = 0xffffffff
def sx(v, bits): return v - (1 << bits) if v & (1 << (bits-1)) else v

def run(words, dmem_bytes=4096, max_steps=1_000_000):
    regs = [0]*32; mem = bytearray(dmem_bytes); pc = 0; steps = 0
    def rd8(a):  return mem[a % dmem_bytes]
    def ld(a, n, signed):
        if a % n: raise RuntimeError(f'misaligned load @{a:#x}')
        v = int.from_bytes(bytes(mem[(a+i) % dmem_bytes] for i in range(n)), 'little')
        return (sx(v, 8*n) & M) if signed else v
    def st(a, n, v):
        if a % n: raise RuntimeError(f'misaligned store @{a:#x}')
        for i in range(n): mem[(a+i) % dmem_bytes] = (v >> (8*i)) & 0xff
    while steps < max_steps:
        steps += 1
        w = words[pc//4] if pc//4 < len(words) else 0x13
        op, rd, f3 = w & 0x7f, (w>>7)&31, (w>>12)&7
        rs1, rs2, f7 = (w>>15)&31, (w>>20)&31, w>>25
        a, b = regs[rs1], regs[rs2]
        nxt, res = (pc+4) & M, None
        if op == 0x33:
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
            addr = (a + sx(w>>20,12)) & M
            res = {0:lambda:ld(addr,1,1),1:lambda:ld(addr,2,1),2:lambda:ld(addr,4,0),
                   4:lambda:ld(addr,1,0),5:lambda:ld(addr,2,0)}[f3]()
        elif op == 0x23:
            imm = sx(((w>>25)<<5)|((w>>7)&31), 12)
            st((a+imm)&M, 1<<f3, b)
        elif op == 0x63:
            imm = sx((((w>>31)&1)<<12)|(((w>>7)&1)<<11)|(((w>>25)&0x3f)<<5)|(((w>>8)&0xf)<<1), 13)
            sa, sb = sx(a,32), sx(b,32)
            t = {0:a==b,1:a!=b,4:sa<sb,5:sa>=sb,6:a<b,7:a>=b}[f3]
            if t: nxt = (pc+imm)&M
        elif op == 0x6f:
            imm = sx((((w>>31)&1)<<20)|(((w>>12)&0xff)<<12)|(((w>>20)&1)<<11)|(((w>>21)&0x3ff)<<1), 21)
            res = (pc+4)&M; nxt = (pc+imm)&M
        elif op == 0x67:
            res = (pc+4)&M; nxt = (a + sx(w>>20,12)) & M & ~1
        elif op == 0x37: res = w & 0xfffff000
        elif op == 0x17: res = (pc + (w & 0xfffff000)) & M
        elif op == 0x73: break
        if res is not None and rd: regs[rd] = res & M
        pc = nxt
    else:
        raise RuntimeError('ISS step limit exceeded')
    return regs, mem, steps
