#!/usr/bin/env python3
"""Random hazard-stress program generator (always terminates: only forward branches)."""
import random, sys

def gen(seed, n=200):
    r = random.Random(seed)
    pool = [1,2,3,4,5,6,7,8]          # small pool => many RAW hazards
    R = lambda: f'x{r.choice(pool)}'
    L = [f'li x{i}, {r.randint(-2**31, 2**31-1)}' for i in pool]
    alu_r = ['add','sub','sll','slt','sltu','xor','srl','sra','or','and']
    alu_i = ['addi','slti','sltiu','xori','ori','andi']
    sh_i  = ['slli','srli','srai']
    br    = ['beq','bne','blt','bge','bltu','bgeu']
    lbl = 0; pending = []             # (labelname, remaining instrs before placing)
    out = list(L)
    for _ in range(n):
        k = r.random()
        if   k < 0.30: out.append(f'{r.choice(alu_r)} {R()}, {R()}, {R()}')
        elif k < 0.45: out.append(f'{r.choice(alu_i)} {R()}, {R()}, {r.randint(-2048,2047)}')
        elif k < 0.50: out.append(f'{r.choice(sh_i)} {R()}, {R()}, {r.randint(0,31)}')
        elif k < 0.54: out.append(f'lui {R()}, {r.randint(0,0xfffff)}')
        elif k < 0.56: out.append(f'auipc {R()}, {r.randint(0,0xfffff)}')
        elif k < 0.70:  # store then often immediately reload (store->load, load-use)
            o = r.choice(range(0,256,4)) + 0x100
            sz = r.choice(['sw','sh','sb'])
            off = o + (r.choice([0,2]) if sz=='sh' else r.randint(0,3) if sz=='sb' else 0)
            out.append(f'{sz} {R()}, {off}(x0)')
        elif k < 0.85:
            ld = r.choice(['lw','lh','lhu','lb','lbu'])
            o = r.choice(range(0,256,4)) + 0x100
            off = o + (r.choice([0,2]) if ld in ('lh','lhu') else r.randint(0,3) if ld in ('lb','lbu') else 0)
            out.append(f'{ld} {R()}, {off}(x0)')
            if r.random() < 0.6:   # immediate consumer => load-use hazard
                out.append(f'add {R()}, {R()}, {R()}')
        elif k < 0.95:
            lbl += 1; name = f'L{lbl}'
            if r.random() < 0.8: out.append(f'{r.choice(br)} {R()}, {R()}, {name}')
            else:                out.append(f'jal {R()}, {name}')
            pending.append([name, r.randint(1,4)])
        else:
            lbl += 1; name = f'L{lbl}'     # jalr to a computed forward address
            out.append(f'auipc x9, 0'); out.append(f'addi x9, x9, 12'); out.append(f'jalr x10, 0(x9)')
        for p in pending: p[1] -= 1
        for p in [p for p in pending if p[1] <= 0]:
            out.append(f'{p[0]}:'); pending.remove(p)
    for p in pending: out.append(f'{p[0]}:')
    out.append('ecall')
    return '\n'.join(out) + '\n'

if __name__ == '__main__':
    print(gen(int(sys.argv[1])), end='')
