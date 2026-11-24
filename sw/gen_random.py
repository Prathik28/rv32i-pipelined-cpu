#!/usr/bin/env python3
"""Random hazard-dense program generator. Always terminates:
only forward branches, plus counted loops with a private counter register.
Includes M-extension ops, CSR ops, misaligned accesses, illegal instructions,
ECALL/EBREAK (a trap handler skips the faulting instruction and folds cause/tval into x29)."""
import random, sys

def gen(seed, n=200):
    r = random.Random(seed)
    pool = [1,2,3,4,5,6,7,8]                      # small pool => many RAW hazards
    def R(): return 'x0' if r.random() < 0.04 else f'x{r.choice(pool)}'
    def Rd(): return f'x{r.choice(pool)}'
    specials = [0x80000000, 0xFFFFFFFF, 0, 1, 2, 0x7FFFFFFF]
    out = ['la x30, handler', 'csrw mtvec, x30', 'li x29, 0']
    for i in pool:
        v = r.choice(specials) if r.random() < 0.3 else r.randint(0, 2**32-1)
        out.append(f'li x{i}, {v}')
    alu_r = ['add','sub','sll','slt','sltu','xor','srl','sra','or','and']
    m_ops = ['mul','mulh','mulhsu','mulhu','div','divu','rem','remu']
    alu_i = ['addi','slti','sltiu','xori','ori','andi']
    sh_i  = ['slli','srli','srai']
    br    = ['beq','bne','blt','bge','bltu','bgeu']
    csrs  = ['mscratch','mtvec','mepc'] 
    lbl = 0; pending = []

    def alu_op():
        k = r.random()
        if   k < 0.45: return f'{r.choice(alu_r)} {Rd()}, {R()}, {R()}'
        elif k < 0.60: return f'{r.choice(m_ops)} {Rd()}, {R()}, {R()}'
        elif k < 0.80: return f'{r.choice(alu_i)} {Rd()}, {R()}, {r.randint(-2048,2047)}'
        elif k < 0.90: return f'{r.choice(sh_i)} {Rd()}, {R()}, {r.randint(0,31)}'
        elif k < 0.95: return f'lui {Rd()}, {r.randint(0,0xfffff)}'
        else:          return f'auipc {Rd()}, {r.randint(0,0xfffff)}'
    def mem_op(allow_mis=True):
        o = r.choice(range(0,256,4)) + 0x100
        if r.random() < 0.5:
            sz = r.choice(['sw','sh','sb'])
            off = o + (r.choice([0,2]) if sz=='sh' else r.randint(0,3) if sz=='sb' else 0)
            if allow_mis and r.random() < 0.05: off += 1 if sz != 'sb' else 0
            return [f'{sz} {R()}, {off}(x0)']
        ld = r.choice(['lw','lh','lhu','lb','lbu'])
        off = o + (r.choice([0,2]) if ld in ('lh','lhu') else r.randint(0,3) if ld in ('lb','lbu') else 0)
        if allow_mis and r.random() < 0.05: off += 1 if ld != 'lb' and ld != 'lbu' else 0
        l = [f'{ld} {Rd()}, {off}(x0)']
        if r.random() < 0.6: l.append(f'add {Rd()}, {R()}, {R()}')   # load-use
        return l

    def flush_pending():
        for p in pending: out.append(f'{p[0]}:')
        pending.clear()

    for _ in range(n):
        k = r.random()
        if   k < 0.40: out.append(alu_op())
        elif k < 0.65: out.extend(mem_op())
        elif k < 0.70: out.append(f'{r.choice(["csrrw","csrrs","csrrc"])} {Rd()}, {r.choice(csrs[:1])}, {R()}')
        elif k < 0.72: out.append(r.choice(['ecall','ebreak','.word 0xFFFFFFFF','.word 0x00000000',
                                            f'.word {0x00100073|0x1000}', 'csrr x1, 0x7C0']))
        elif k < 0.84:
            lbl += 1; name = f'L{lbl}'
            if r.random() < 0.8: out.append(f'{r.choice(br)} {R()}, {R()}, {name}')
            else:                out.append(f'jal {Rd()}, {name}')
            pending.append([name, r.randint(1,4)])
        elif k < 0.90:   # counted loop (atomic: no forward labels cross it) -> trains the predictor
            flush_pending()
            lbl += 1; name = f'L{lbl}'
            out.append(f'li x11, {r.randint(2,7)}')
            out.append(f'{name}:')
            for _ in range(r.randint(1,4)):
                out.append(alu_op() if r.random() < 0.7 else mem_op(False)[0])
            out.append('addi x11, x11, -1')
            out.append(f'bnez x11, {name}')
        elif k < 0.95:   # jalr to computed forward address (sometimes misaligned -> trap)
            off = r.choice([0, 0, 0, 2])
            out.append('auipc x9, 0'); out.append('addi x9, x9, 12')
            out.append(f'jalr x10, {off}(x9)')
        else:
            out.append('nop')
        for p in pending: p[1] -= 1
        for p in [p for p in pending if p[1] <= 0]:
            out.append(f'{p[0]}:'); pending.remove(p)
    flush_pending()
    out.append('halt')
    out += ['handler:',
            'csrr x28, mcause', 'xor x29, x29, x28', 'csrr x28, mtval', 'add x29, x29, x28',
            'csrr x28, mepc', 'addi x28, x28, 4', 'csrw mepc, x28', 'mret']
    return '\n'.join(out) + '\n'

if __name__ == '__main__':
    print(gen(int(sys.argv[1])), end='')
