#!/usr/bin/env python3
"""Assemble each test, run it on the golden ISS and on the RTL (iverilog), compare.
  tests/NN_*.s  : RTL must match the ISS (registers, data memory, exit code, console output)
  tests/sc_*.s  : self-checking (timing-dependent, e.g. interrupts): RTL exit code must be 0
Usage: run_tests.py [N_RANDOM]"""
import glob, os, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
import asm, iss, gen_random

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BUILD = os.path.join(ROOT, 'build'); os.makedirs(BUILD, exist_ok=True)
SIM = os.path.join(BUILD, 'sim')

def build_rtl():
    srcs = sorted(glob.glob(f'{ROOT}/rtl/*.v')) + [f'{ROOT}/tb/tb_riscv.v']
    subprocess.run(['iverilog','-g2012','-Wall','-Wno-timescale','-o',SIM] + srcs, check=True)

def run_rtl(hexfile, extra=()):
    hexfile = os.path.relpath(hexfile, ROOT)       # +hex= cannot contain spaces
    p = subprocess.run(['vvp', SIM, f'+hex={hexfile}', *extra], capture_output=True, text=True, cwd=ROOT, timeout=300)
    stdout = '\n'.join(l for l in p.stdout.split('\n') if not l.startswith('WARNING'))
    head, sep, tail = stdout.partition('\n----\n')
    if 'DONE' not in tail: return None
    regs = [0]*32; mem = {}; slow = {}; perf = None; exit_code = None
    for l in tail.splitlines():
        t = l.split()
        if   t[:1] == ['REG']:  regs[int(t[1])] = int(t[2], 16)
        elif t[:1] == ['MEM']:  mem[int(t[1])] = int(t[2], 16)
        elif t[:1] == ['SLOW']: slow[int(t[1])] = int(t[2], 16)
        elif t[:1] == ['EXIT']: exit_code = int(t[1])
        elif t[:1] == ['PERF']: perf = list(map(int, t[1:]))
    return regs, mem, perf, exit_code, head.rstrip('\n'), slow

def perf_limits(text):
    """'# PERF mispred<=N cycles<=M' lines pin performance (predictor quality) for a test."""
    lim = {}
    for l in text.splitlines():
        if l.startswith('# PERF'):
            for tok in l.split()[2:]:
                k, v = tok.split('<='); lim[k] = int(v)
    return lim

def check(name, text, selfcheck=False):
    words = asm.assemble(text)
    hexf = os.path.join(BUILD, name + '.hex')
    open(hexf, 'w').write(''.join(f'{w:08x}\n' for w in words))
    res = run_rtl(hexf)
    if res is None: return False, 'RTL timeout / no DONE', None
    rregs, rmem, perf, rexit, rout, rslow = res
    if selfcheck:
        return rexit == 0, f'exit code {rexit}', perf
    g = iss.run(words)
    gmem = {i: int.from_bytes(g.mem[i:i+4], 'little') for i in range(0, 4096, 4)}
    gmem = {k: v for k, v in gmem.items() if v}
    errs = [f'x{i}: rtl={rregs[i]:08x} iss={g.regs[i]:08x}' for i in range(32) if rregs[i] != g.regs[i]]
    for a in sorted(set(rmem) | set(gmem)):
        if rmem.get(a, 0) != gmem.get(a, 0):
            errs.append(f'mem[{a:#x}]: rtl={rmem.get(a,0):08x} iss={gmem.get(a,0):08x}')
    if perf:
        for k, idx in (('cycles', 0), ('mispred', 6)):
            lim = perf_limits(text).get(k)
            if lim is not None and perf[idx] > lim: errs.append(f'perf: {k}={perf[idx]} exceeds limit {lim}')
    gslow = {i: int.from_bytes(g.slow[i:i+4], 'little') for i in range(0, 4096, 4)}
    gslow = {k: v for k, v in gslow.items() if v}
    for a in sorted(set(rslow) | set(gslow)):
        if rslow.get(a, 0) != gslow.get(a, 0):
            errs.append(f'slow[{a:#x}]: rtl={rslow.get(a,0):08x} iss={gslow.get(a,0):08x}')
    if rexit != g.exit_code: errs.append(f'exit rtl={rexit} iss={g.exit_code}')
    if rout != g.out: errs.append(f'console rtl={rout!r} iss={g.out!r}')
    return (not errs), '; '.join(errs[:6]), perf

def main():
    nrand = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    build_rtl()
    fails = 0
    print(f'{"test":<22}{"result":<7}{"cycles":>7}{"instret":>8}{"CPI":>6}{"ld-use":>7}{"div":>5}{"flush":>6}{"branch":>7}{"mispred":>8}{"traps":>6}')
    for f in sorted(glob.glob(f'{ROOT}/tests/*.s')):
        name = os.path.basename(f)[:-2]
        ok, msg, p = check(name, open(f).read(), selfcheck=name.startswith('sc_'))
        if p:
            acc = f'{100*(1-p[6]/p[5]):.0f}%' if p[5] else '-'
            print(f'{name:<22}{"PASS" if ok else "FAIL":<7}{p[0]:>7}{p[1]:>8}{p[0]/max(p[1],1):>6.2f}{p[2]:>7}{p[3]:>5}{p[4]:>6}{p[5]:>7}{p[6]:>6} {acc:>3}{p[7]:>5}')
        else: print(f'{name:<22}FAIL')
        if not ok:
            fails += 1; print('   ', msg)
            if os.environ.get('FAILFAST'): sys.exit(1)
    rfail = 0
    for s in range(nrand):
        ok, msg, _ = check(f'rand_{s}', gen_random.gen(s))
        if not ok:
            rfail += 1; print(f'random seed {s} FAIL: {msg}')
            if os.environ.get('FAILFAST'): sys.exit(1)
    print(f'random programs: {nrand - rfail}/{nrand} passed')
    total = fails + rfail
    print('ALL TESTS PASSED' if total == 0 else f'{total} FAILURES')
    sys.exit(1 if total else 0)

if __name__ == '__main__': main()
