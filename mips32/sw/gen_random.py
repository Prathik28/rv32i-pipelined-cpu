#!/usr/bin/env python3
"""Random hazard-dense MIPS program generator (always terminates: forward branches + counted loops).
Every branch/jump is followed by an explicit delay-slot instruction (never another branch)."""
import random, sys

def gen(seed, n=160):
    r = random.Random(seed)
    pool = [8,9,10,11,12,13,14,15]                        # $t0..$t7: small pool => many RAW hazards
    R  = lambda: f'${r.choice(pool)}' if r.random() > 0.04 else '$zero'
    Rd = lambda: f'${r.choice(pool)}'
    specials = [0x80000000, 0xFFFFFFFF, 0, 1, 2, 0x7FFFFFFF]
    out = []
    for i in pool:
        v = r.choice(specials) if r.random() < 0.3 else r.randint(0, 2**32-1)
        out.append(f'li ${i}, {v}')
    alu3 = ['addu','subu','and','or','xor','nor','slt','sltu']
    alui = ['addiu','slti','sltiu']
    alul = ['andi','ori','xori']
    shi  = ['sll','srl','sra']; shv = ['sllv','srlv','srav']
    br2  = ['beq','bne']; br1 = ['blez','bgtz','bltz','bgez']
    lbl = 0; pending = []

    def alu_op():
        k = r.random()
        if   k < 0.40: return f'{r.choice(alu3)} {Rd()}, {R()}, {R()}'
        elif k < 0.55: return f'{r.choice(alui)} {Rd()}, {R()}, {r.randint(-32768,32767)}'
        elif k < 0.65: return f'{r.choice(alul)} {Rd()}, {R()}, {r.randint(0,65535)}'
        elif k < 0.75: return f'{r.choice(shi)} {Rd()}, {R()}, {r.randint(0,31)}'
        elif k < 0.82: return f'{r.choice(shv)} {Rd()}, {R()}, {R()}'
        elif k < 0.87: return f'lui {Rd()}, {r.randint(0,65535)}'
        elif k < 0.93: return f'mul {Rd()}, {R()}, {R()}'
        elif k < 0.96: return f'{r.choice(["mfhi","mflo"])} {Rd()}'
        else:          return f'{r.choice(["mthi","mtlo"])} {R()}'
    def hilo_op():
        return [f'{r.choice(["mult","multu","div","divu"])} {R()}, {R()}'] + \
               ([f'{r.choice(["mfhi","mflo"])} {Rd()}'] if r.random() < 0.7 else [])
    def mem_op():
        o = r.choice(range(0, 256, 4)) + 0x100
        if r.random() < 0.45:
            sz = r.choice(['sw','sh','sb'])
            off = o + (r.choice([0,2]) if sz == 'sh' else r.randint(0,3) if sz == 'sb' else 0)
            return [f'{sz} {R()}, {off}($zero)']
        ld = r.choice(['lw','lh','lhu','lb','lbu'])
        off = o + (r.choice([0,2]) if ld in ('lh','lhu') else r.randint(0,3) if ld in ('lb','lbu') else 0)
        l = [f'{ld} {Rd()}, {off}($zero)']
        if r.random() < 0.6: l.append(f'addu {Rd()}, {R()}, {R()}')        # load-use
        return l
    def slot():                       # delay-slot filler: never a control transfer
        return alu_op() if r.random() < 0.7 else 'nop'
    def flush_pending():
        for p in pending: out.append(f'{p[0]}:')
        pending.clear()

    for _ in range(n):
        k = r.random()
        if   k < 0.35: out.append(alu_op())
        elif k < 0.55: out.extend(mem_op())
        elif k < 0.62: out.extend(hilo_op())
        elif k < 0.78:                                      # forward conditional branch + delay slot
            lbl += 1; name = f'L{lbl}'
            if r.random() < 0.5: out.append(f'{r.choice(br2)} {R()}, {R()}, {name}')
            else:                out.append(f'{r.choice(br1)} {R()}, {name}')
            out.append(slot()); pending.append([name, r.randint(1,4)])
        elif k < 0.83:                                      # jump / call forward
            lbl += 1; name = f'L{lbl}'
            out.append(r.choice([f'j {name}', f'jal {name}'])); out.append(slot())
            pending.append([name, r.randint(1,4)])
        elif k < 0.89:                                      # counted loop (trains nothing, but stresses back-edges)
            flush_pending()
            lbl += 1; name = f'L{lbl}'
            out.append(f'li $24, {r.randint(2,6)}')
            out.append(f'{name}:')
            for _ in range(r.randint(1,4)): out.append(alu_op() if r.random() < 0.7 else mem_op()[0])
            out.append('addiu $24, $24, -1')
            out.append(f'bnez $24, {name}')
            out.append(slot())
        elif k < 0.94:                                      # jr / jalr to a computed forward address
            out.append(f'la $25, JT{lbl+1}'); lbl += 1
            out.append(r.choice(['jr $25', 'jalr $25']))
            out.append(slot()); out.append(f'JT{lbl}:')
        else: out.append('nop')
        for p in pending: p[1] -= 1
        for p in [p for p in pending if p[1] <= 0]:
            out.append(f'{p[0]}:'); pending.remove(p)
    flush_pending()
    out.append('halt')
    return '\n'.join(out) + '\n'

if __name__ == '__main__': print(gen(int(sys.argv[1])), end='')
