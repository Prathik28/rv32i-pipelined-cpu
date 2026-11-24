#!/usr/bin/env python3
"""Tiny RV32I assembler -> $readmemh hex (one 32-bit word per line)."""
import re, sys

ABI = ['zero','ra','sp','gp','tp','t0','t1','t2','s0','s1','a0','a1','a2','a3','a4','a5',
       'a6','a7','s2','s3','s4','s5','s6','s7','s8','s9','s10','s11','t3','t4','t5','t6']
REG = {f'x{i}': i for i in range(32)}
REG.update({n: i for i, n in enumerate(ABI)}); REG['fp'] = 8

R_OPS = {'add':(0,0),'sub':(0,0x20),'sll':(1,0),'slt':(2,0),'sltu':(3,0),'xor':(4,0),
         'srl':(5,0),'sra':(5,0x20),'or':(6,0),'and':(7,0),
         'mul':(0,1),'mulh':(1,1),'mulhsu':(2,1),'mulhu':(3,1),
         'div':(4,1),'divu':(5,1),'rem':(6,1),'remu':(7,1)}
CSR_NAMES = {'mstatus':0x300,'misa':0x301,'mie':0x304,'mtvec':0x305,'mscratch':0x340,'mepc':0x341,
             'mcause':0x342,'mtval':0x343,'mip':0x344,'mcycle':0xB00,'minstret':0xB02,'mhartid':0xF14,
             'cycle':0xC00,'instret':0xC02}
CSR_OPS = {'csrrw':1,'csrrs':2,'csrrc':3,'csrrwi':5,'csrrsi':6,'csrrci':7}

I_OPS = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
SH_OPS = {'slli':(1,0),'srli':(5,0),'srai':(5,0x20)}
LD_OPS = {'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}
ST_OPS = {'sb':0,'sh':1,'sw':2}
BR_OPS = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}

def reg(s):
    s = s.strip()
    if s not in REG: raise ValueError(f'bad register {s!r}')
    return REG[s]

def num(s): return int(s.strip(), 0)

def mem_operand(s):
    m = re.fullmatch(r'\s*(-?\w*)\s*\(\s*(\w+)\s*\)\s*', s)
    if not m: raise ValueError(f'bad memory operand {s!r}')
    return (num(m.group(1)) if m.group(1) else 0), reg(m.group(2))

def enc_r(f7,rs2,rs1,f3,rd,op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_i(imm,rs1,f3,rd,op):
    if not -2048 <= imm <= 2047: raise ValueError(f'imm12 out of range: {imm}')
    return ((imm&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_s(imm,rs2,rs1,f3,op):
    if not -2048 <= imm <= 2047: raise ValueError(f'imm12 out of range: {imm}')
    imm &= 0xfff
    return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1f)<<7)|op
def enc_b(imm,rs2,rs1,f3,op):
    if imm % 2 or not -4096 <= imm <= 4094: raise ValueError(f'branch offset out of range: {imm}')
    imm &= 0x1fff
    return ((imm>>12)<<31)|(((imm>>5)&0x3f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((imm>>1)&0xf)<<8)|(((imm>>11)&1)<<7)|op
def enc_u(imm,rd,op): return ((imm&0xfffff)<<12)|(rd<<7)|op
def enc_j(imm,rd,op):
    if imm % 2 or not -(1<<20) <= imm < (1<<20): raise ValueError(f'jal offset out of range: {imm}')
    imm &= 0x1fffff
    return ((imm>>20)<<31)|(((imm>>1)&0x3ff)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xff)<<12)|(rd<<7)|op

def split(args):
    return [a.strip() for a in args.split(',')] if args.strip() else []

def expand(mn, a):
    """Expand pseudo-instructions into (mnemonic, [operands]) lists."""
    if mn == 'nop':  return [('addi',['x0','x0','0'])]
    if mn == 'mv':   return [('addi',[a[0],a[1],'0'])]
    if mn == 'not':  return [('xori',[a[0],a[1],'-1'])]
    if mn == 'neg':  return [('sub',[a[0],'x0',a[1]])]
    if mn == 'seqz': return [('sltiu',[a[0],a[1],'1'])]
    if mn == 'snez': return [('sltu',[a[0],'x0',a[1]])]
    if mn == 'j':    return [('jal',['x0',a[0]])]
    if mn == 'jal' and len(a) == 1: return [('jal',['ra',a[0]])]
    if mn == 'jr':   return [('jalr',['x0',a[0],'0'])]
    if mn == 'ret':  return [('jalr',['x0','ra','0'])]
    if mn == 'beqz': return [('beq',[a[0],'x0',a[1]])]
    if mn == 'bnez': return [('bne',[a[0],'x0',a[1]])]
    if mn == 'bgt':  return [('blt',[a[1],a[0],a[2]])]
    if mn == 'ble':  return [('bge',[a[1],a[0],a[2]])]
    if mn == 'bgtu': return [('bltu',[a[1],a[0],a[2]])]
    if mn == 'bleu': return [('bgeu',[a[1],a[0],a[2]])]
    if mn == 'halt':  return [('lui',['x31','0x10000']),('sw',['x0','0(x31)'])]
    if mn == 'csrr':  return [('csrrs',[a[0],a[1],'x0'])]
    if mn == 'csrw':  return [('csrrw',['x0',a[0],a[1]])]
    if mn == 'csrs':  return [('csrrs',['x0',a[0],a[1]])]
    if mn == 'csrc':  return [('csrrc',['x0',a[0],a[1]])]
    if mn == 'csrwi': return [('csrrwi',['x0',a[0],a[1]])]
    if mn == 'csrsi': return [('csrrsi',['x0',a[0],a[1]])]
    if mn == 'csrci': return [('csrrci',['x0',a[0],a[1]])]
    if mn == 'la':    return [('auipc',[a[0],'%pcrel_hi:'+a[1]]),('addi',[a[0],a[0],'%pcrel_lo:'+a[1]])]
    if mn == 'li':
        v = num(a[1]) & 0xffffffff
        sv = v - (1<<32) if v & 0x80000000 else v
        if -2048 <= sv <= 2047: return [('addi',[a[0],'x0',str(sv)])]
        lo = sv & 0xfff
        if lo & 0x800: lo -= 0x1000
        hi = ((v - lo) >> 12) & 0xfffff
        out = [('lui',[a[0],str(hi)])]
        if lo: out.append(('addi',[a[0],a[0],str(lo)]))
        return out
    return [(mn, a)]

LISTING = []

def assemble(text):
    global LISTING
    items, labels = [], {}
    for ln, raw in enumerate(text.splitlines(), 1):
        line = re.split(r'#|//', raw)[0].strip()
        while True:
            m = re.match(r'^(\w+)\s*:\s*(.*)$', line)
            if not m: break
            labels[m.group(1)] = len(items) * 4
            line = m.group(2).strip()
        if not line: continue
        parts = line.split(None, 1)
        mn, args = parts[0].lower(), (parts[1] if len(parts) > 1 else '')
        for e in expand(mn, split(args)):
            items.append((e[0], e[1], ln))

    LISTING = [f'{mn} {", ".join(a)}'.strip() for mn, a, ln in items]
    words = []
    for idx, (mn, a, ln) in enumerate(items):
        pc = idx * 4
        def target(s):
            return labels[s] - pc if s in labels else num(s)
        try:
            if   mn in R_OPS:  f3,f7 = R_OPS[mn]; w = enc_r(f7,reg(a[2]),reg(a[1]),f3,reg(a[0]),0x33)
            elif mn in I_OPS:
                if a[2].startswith('%pcrel_lo:'):
                    off = labels[a[2][10:]] - (pc - 4); lo = off - (((off + 0x800) >> 12) << 12)
                    w = enc_i(lo,reg(a[1]),I_OPS[mn],reg(a[0]),0x13)
                else: w = enc_i(num(a[2]),reg(a[1]),I_OPS[mn],reg(a[0]),0x13)
            elif mn in SH_OPS:
                f3,f7 = SH_OPS[mn]; sh = num(a[2])
                if not 0 <= sh < 32: raise ValueError('shift amount')
                w = enc_r(f7,sh,reg(a[1]),f3,reg(a[0]),0x13)
            elif mn in LD_OPS: off,rs1 = mem_operand(a[1]); w = enc_i(off,rs1,LD_OPS[mn],reg(a[0]),0x03)
            elif mn in ST_OPS: off,rs1 = mem_operand(a[1]); w = enc_s(off,reg(a[0]),rs1,ST_OPS[mn],0x23)
            elif mn in BR_OPS: w = enc_b(target(a[2]),reg(a[1]),reg(a[0]),BR_OPS[mn],0x63)
            elif mn == 'lui':   w = enc_u(num(a[1]),reg(a[0]),0x37)
            elif mn == 'auipc':
                if a[1].startswith('%pcrel_hi:'):
                    off = labels[a[1][10:]] - pc; hi = ((off + 0x800) >> 12) & 0xfffff
                    w = enc_u(hi,reg(a[0]),0x17)
                else: w = enc_u(num(a[1]),reg(a[0]),0x17)
            elif mn == 'jal':   w = enc_j(target(a[1]),reg(a[0]),0x6f)
            elif mn == 'jalr':
                if len(a) == 2 and '(' in a[1]: off,rs1 = mem_operand(a[1])
                else: rs1, off = reg(a[1]), (num(a[2]) if len(a) > 2 else 0)
                w = enc_i(off,rs1,0,reg(a[0]),0x67)
            elif mn in CSR_OPS:
                c = CSR_NAMES[a[1]] if a[1] in CSR_NAMES else num(a[1])
                f3 = CSR_OPS[mn]
                src = (num(a[2]) & 31) if f3 >= 5 else reg(a[2])
                w = (c << 20) | (src << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x73
            elif mn == 'mret':   w = 0x30200073
            elif mn == '.word':  w = num(a[0])
            elif mn == 'ecall':  w = 0x00000073
            elif mn == 'ebreak': w = 0x00100073
            else: raise ValueError(f'unknown mnemonic {mn!r}')
        except Exception as e:
            raise SystemExit(f'asm error line {ln}: {mn} {a}: {e}')
        words.append(w & 0xffffffff)
    return words

if __name__ == '__main__':
    if len(sys.argv) != 3: sys.exit('usage: asm.py prog.s prog.hex')
    ws = assemble(open(sys.argv[1]).read())
    open(sys.argv[2], 'w').write(''.join(f'{w:08x}\n' for w in ws))
