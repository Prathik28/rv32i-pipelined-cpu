#!/usr/bin/env python3
"""Assemble each test, run it on the golden ISS and on the RTL (iverilog), compare."""
import glob, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
import asm, iss, gen_random

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BUILD = os.path.join(ROOT, 'build'); os.makedirs(BUILD, exist_ok=True)
SIM = os.path.join(BUILD, 'sim')

def build_rtl():
    srcs = sorted(glob.glob(f'{ROOT}/rtl/*.v')) + [f'{ROOT}/tb/tb_riscv.v']
    subprocess.run(['iverilog','-g2012','-Wall','-Wno-timescale','-o',SIM] + srcs, check=True)

def run_rtl(hexfile, extra=()):
    hexfile = os.path.relpath(hexfile, ROOT)  # +hex= can't contain spaces
    p = subprocess.run(['vvp', SIM, f'+hex={hexfile}', *extra], capture_output=True, text=True, cwd=ROOT, timeout=120)
    out = p.stdout
    if 'DONE' not in out: return None
    regs = [0]*32; mem = {}; perf = None
    for l in out.splitlines():
        t = l.split()
        if t[:1] == ['REG']: regs[int(t[1])] = int(t[2], 16)
        elif t[:1] == ['MEM']: mem[int(t[1])] = int(t[2], 16)
        elif t[:1] == ['PERF']: perf = list(map(int, t[1:]))
    return regs, mem, perf

def check(name, text, verbose=True):
    words = asm.assemble(text)
    hexf = os.path.join(BUILD, name + '.hex')
    open(hexf, 'w').write(''.join(f'{w:08x}\n' for w in words))
    eregs, emem, _ = iss.run(words)
    emem_w = {i: int.from_bytes(emem[i:i+4], 'little') for i in range(0, 4096, 4)}
    emem_w = {k: v for k, v in emem_w.items() if v}
    res = run_rtl(hexf)
    if res is None: return False, 'RTL timeout / no DONE', None
    rregs, rmem, perf = res
    errs = [f'x{i}: rtl={rregs[i]:08x} iss={eregs[i]:08x}' for i in range(32) if rregs[i] != eregs[i]]
    for a in sorted(set(rmem) | set(emem_w)):
        if rmem.get(a, 0) != emem_w.get(a, 0):
            errs.append(f'mem[{a:#x}]: rtl={rmem.get(a,0):08x} iss={emem_w.get(a,0):08x}')
    return (not errs), '; '.join(errs[:6]), perf

def main():
    nrand = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    build_rtl()
    fails = 0
    print(f'{"test":<22}{"result":<8}{"cycles":>8}{"instret":>9}{"stalls":>8}{"flushes":>9}{"CPI":>7}')
    for f in sorted(glob.glob(f'{ROOT}/tests/*.s')):
        name = os.path.basename(f)[:-2]
        ok, msg, perf = check(name, open(f).read())
        if perf: print(f'{name:<22}{"PASS" if ok else "FAIL":<8}{perf[0]:>8}{perf[1]:>9}{perf[2]:>8}{perf[3]:>9}{perf[0]/max(perf[1],1):>7.2f}')
        else:    print(f'{name:<22}FAIL')
        if not ok: fails += 1; print('   ', msg)
    rfail = 0
    for s in range(nrand):
        ok, msg, _ = check(f'rand_{s}', gen_random.gen(s))
        if not ok: rfail += 1; print(f'random seed {s} FAIL: {msg}')
    print(f'random programs: {nrand - rfail}/{nrand} passed')
    total = fails + rfail
    print('ALL TESTS PASSED' if total == 0 else f'{total} FAILURES')
    sys.exit(1 if total else 0)

if __name__ == '__main__': main()
