#!/usr/bin/env python3
"""Small MIPS32 assembler -> $readmemh hex (one 32-bit word per line).
No instruction reordering and no automatic delay-slot filling: the instruction after a branch or
jump is the delay slot and must be written explicitly (use `nop` when there is nothing useful)."""
import re, sys

NAMES = ['zero','at','v0','v1','a0','a1','a2','a3','t0','t1','t2','t3','t4','t5','t6','t7',
         's0','s1','s2','s3','s4','s5','s6','s7','t8','t9','k0','k1','gp','sp','fp','ra']
REG = {n: i for i, n in enumerate(NAMES)}; REG['s8'] = 30
for i in range(32): REG[str(i)] = i

R3 = {'add':0x20,'addu':0x21,'sub':0x22,'subu':0x23,'and':0x24,'or':0x25,'xor':0x26,'nor':0x27,'slt':0x2A,'sltu':0x2B}
SHI = {'sll':0,'srl':2,'sra':3}
SHV = {'sllv':4,'srlv':6,'srav':7}
MD  = {'mult':0x18,'multu':0x19,'div':0x1A,'divu':0x1B}
IOP = {'addi':8,'addiu':9,'slti':0xA,'sltiu':0xB,'andi':0xC,'ori':0xD,'xori':0xE}
MEM = {'lb':0x20,'lh':0x21,'lw':0x23,'lbu':0x24,'lhu':0x25,'sb':0x28,'sh':0x29,'sw':0x2B,
       'lwl':0x22,'lwr':0x26,'swl':0x2A,'swr':0x2E}
BR2 = {'beq':4,'bne':5}
BR1 = {'blez':6,'bgtz':7,'blezl':0x16,'bgtzl':0x17}
BR2L = {'beql':0x14,'bnel':0x15}
RGM = {'bltz':0,'bgez':1,'bltzl':2,'bgezl':3,'bltzal':0x10,'bgezal':0x11,'bltzall':0x12,'bgezall':0x13}
CP0N = {'badvaddr':8,'count':9,'compare':11,'status':12,'cause':13,'epc':14}
LISTING = []

def reg(s):
    s = s.strip().lstrip('$').lower()
    if s not in REG: raise ValueError(f'bad register {s!r}')
    return REG[s]
def num(s): return int(s.strip(), 0)
def split(a): return [x.strip() for x in a.split(',')] if a.strip() else []
def memop(s):
    m = re.fullmatch(r'\s*(-?\w*)\s*\(\s*(\$?\w+)\s*\)\s*', s)
    if not m: raise ValueError(f'bad memory operand {s!r}')
    return (num(m.group(1)) if m.group(1) else 0), reg(m.group(2))
def r_(op, rs, rt, rd, sh, fn): return (op<<26)|(rs<<21)|(rt<<16)|(rd<<11)|(sh<<6)|fn
def i_(op, rs, rt, imm):
    if not -32768 <= imm <= 65535: raise ValueError(f'immediate out of range: {imm}')
    return (op<<26)|(rs<<21)|(rt<<16)|(imm & 0xffff)

def expand(mn, a):
    if mn == 'nop':   return [('sll', ['$zero','$zero','0'])]
    if mn == 'move':  return [('addu', [a[0], a[1], '$zero'])]
    if mn == 'not':   return [('nor', [a[0], a[1], '$zero'])]
    if mn == 'negu':  return [('subu', [a[0], '$zero', a[1]])]
    if mn == 'b':     return [('beq', ['$zero','$zero',a[0]])]
    if mn == 'beqz':  return [('beq', [a[0],'$zero',a[1]])]
    if mn == 'bnez':  return [('bne', [a[0],'$zero',a[1]])]
    if mn == 'blt':   return [('slt', ['$at',a[0],a[1]]), ('bne', ['$at','$zero',a[2]])]
    if mn == 'bge':   return [('slt', ['$at',a[0],a[1]]), ('beq', ['$at','$zero',a[2]])]
    if mn == 'bgt':   return [('slt', ['$at',a[1],a[0]]), ('bne', ['$at','$zero',a[2]])]
    if mn == 'ble':   return [('slt', ['$at',a[1],a[0]]), ('beq', ['$at','$zero',a[2]])]
    if mn == 'exit':  return [('lui', ['$at', '0xFFFF']), ('sw', ['$a0', '0($at)'])]          # store $a0 to HALT
    if mn == 'halt':  return [('addu', ['$a0','$zero','$zero'])] + expand('exit', [])
    if mn == 'la':    return [('lui', [a[0], '%hi:'+a[1]]), ('ori', [a[0], a[0], '%lo:'+a[1]])]
    if mn == 'li':
        v = num(a[1]) & 0xffffffff; sv = v - (1<<32) if v & 0x80000000 else v
        if -32768 <= sv <= 32767: return [('addiu', [a[0], '$zero', str(sv)])]
        if 0 <= v <= 0xffff:      return [('ori',   [a[0], '$zero', str(v)])]
        out = [('lui', [a[0], str(v >> 16)])]
        if v & 0xffff: out.append(('ori', [a[0], a[0], str(v & 0xffff)]))
        return out
    return [(mn, a)]

def assemble(text):
    global LISTING
    items, labels = [], {}
    for ln, raw in enumerate(text.splitlines(), 1):
        line = re.split(r'#|//', raw)[0].strip()
        while True:
            m = re.match(r'^(\w+)\s*:\s*(.*)$', line)
            if not m: break
            labels[m.group(1)] = len(items) * 4; line = m.group(2).strip()
        if not line: continue
        parts = line.split(None, 1)
        mn, args = parts[0].lower(), (parts[1] if len(parts) > 1 else '')
        if mn == '.org':
            target_addr = num(args)
            while len(items) * 4 < target_addr: items.append(('sll', ['$zero','$zero','0'], ln))
            continue
        for e in expand(mn, split(args)): items.append((e[0], e[1], ln))
    LISTING = [f'{mn} {", ".join(a)}'.strip() for mn, a, ln in items]
    words = []
    for idx, (mn, a, ln) in enumerate(items):
        pc = idx * 4
        try:
            def tgt(s): return labels[s] if s in labels else num(s)
            def boff(s):
                off = (tgt(s) - (pc + 4)) >> 2
                if not -32768 <= off <= 32767: raise ValueError('branch out of range')
                return off
            if   mn in R3:  w = r_(0, reg(a[1]), reg(a[2]), reg(a[0]), 0, R3[mn])
            elif mn in SHI: w = r_(0, 0, reg(a[1]), reg(a[0]), num(a[2]) & 31, SHI[mn])
            elif mn in SHV: w = r_(0, reg(a[2]), reg(a[1]), reg(a[0]), 0, SHV[mn])
            elif mn in MD:  w = r_(0, reg(a[0]), reg(a[1]), 0, 0, MD[mn])
            elif mn == 'mul': w = r_(0x1c, reg(a[1]), reg(a[2]), reg(a[0]), 0, 2)
            elif mn == 'mfhi': w = r_(0, 0, 0, reg(a[0]), 0, 0x10)
            elif mn == 'mflo': w = r_(0, 0, 0, reg(a[0]), 0, 0x12)
            elif mn == 'mthi': w = r_(0, reg(a[0]), 0, 0, 0, 0x11)
            elif mn == 'mtlo': w = r_(0, reg(a[0]), 0, 0, 0, 0x13)
            elif mn == 'jr':   w = r_(0, reg(a[0]), 0, 0, 0, 8)
            elif mn == 'jalr':
                rd, rs = (31, reg(a[0])) if len(a) == 1 else (reg(a[0]), reg(a[1]))
                w = r_(0, rs, 0, rd, 0, 9)
            elif mn == 'syscall': w = 0x0c
            elif mn == 'break':   w = 0x0d
            elif mn == 'eret':    w = 0x42000018
            elif mn in ('mfc0', 'mtc0'):
                c = a[1].strip().lstrip('$').lower(); cp = CP0N[c] if c in CP0N else num(c)
                w = (0x10 << 26) | ((0 if mn == 'mfc0' else 4) << 21) | (reg(a[0]) << 16) | (cp << 11)
            elif mn in BR2L: w = i_(BR2L[mn], reg(a[0]), reg(a[1]), boff(a[2]))
            elif mn in IOP:
                imm = num(a[2]) if not a[2].startswith('%') else 0
                w = i_(IOP[mn], reg(a[1]), reg(a[0]), imm) if not a[2].startswith('%lo:') else \
                    i_(IOP[mn], reg(a[1]), reg(a[0]), labels[a[2][4:]] & 0xffff)
            elif mn == 'lui':
                imm = (labels[a[1][4:]] >> 16) if a[1].startswith('%hi:') else num(a[1])
                w = i_(0xf, 0, reg(a[0]), imm & 0xffff)
            elif mn in MEM:
                off, rs = memop(a[1]); w = i_(MEM[mn], rs, reg(a[0]), off)
            elif mn in BR2: w = i_(BR2[mn], reg(a[0]), reg(a[1]), boff(a[2]))
            elif mn in BR1: w = i_(BR1[mn], reg(a[0]), 0, boff(a[1]))
            elif mn in RGM: w = (1<<26)|(reg(a[0])<<21)|(RGM[mn]<<16)|(boff(a[1]) & 0xffff)
            elif mn in ('j', 'jal'): w = ((2 if mn == 'j' else 3) << 26) | ((tgt(a[0]) >> 2) & 0x3ffffff)
            elif mn == '.word': w = num(a[0])
            else: raise ValueError(f'unknown mnemonic {mn!r}')
        except Exception as e:
            raise SystemExit(f'asm error line {ln}: {mn} {a}: {e}')
        words.append(w & 0xffffffff)
    return words

if __name__ == '__main__':
    if len(sys.argv) != 3: sys.exit('usage: masm.py prog.s prog.hex')
    ws = assemble(open(sys.argv[1]).read())
    open(sys.argv[2], 'w').write(''.join(f'{w:08x}\n' for w in ws))
