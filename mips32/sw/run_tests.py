#!/usr/bin/env python3
"""Assemble each test, run it on the golden ISS and on the RTL (iverilog), compare registers,
HI/LO, data memory, exit code and console output. Usage: run_tests.py [N_RANDOM]"""
import glob, os, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
import masm, mips_iss, gen_random

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BUILD = os.path.join(ROOT, 'build'); os.makedirs(BUILD, exist_ok=True)
SIM = os.path.join(BUILD, 'sim')

def build_rtl():
    srcs = sorted(glob.glob(f'{ROOT}/rtl/*.v')) + [f'{ROOT}/tb/tb_mips.v']
    subprocess.run(['iverilog','-g2012','-Wall','-Wno-timescale','-o',SIM] + srcs, check=True, stderr=subprocess.DEVNULL)

def run_rtl(hexfile, extra=()):
    hexfile = os.path.relpath(hexfile, ROOT)       # +hex= cannot contain spaces
    p = subprocess.run(['vvp', SIM, f'+hex={hexfile}', *extra], capture_output=True, text=True, cwd=ROOT, timeout=300)
    stdout = '\n'.join(l for l in p.stdout.split('\n') if not l.startswith('WARNING'))
    head, sep, tail = stdout.partition('\n----\n')
    if 'DONE' not in tail: return None
    regs = [0]*32; mem = {}; perf = None; exit_code = None; hi = lo = 0
    for l in tail.splitlines():
        t = l.split()
        if   t[:1] == ['REG']:  regs[int(t[1])] = int(t[2], 16)
        elif t[:1] == ['HI']:   hi = int(t[1], 16)
        elif t[:1] == ['LO']:   lo = int(t[1], 16)
        elif t[:1] == ['MEM']:  mem[int(t[1])] = int(t[2], 16)
        elif t[:1] == ['EXIT']: exit_code = int(t[1])
        elif t[:1] == ['PERF']: perf = list(map(int, t[1:]))
    return regs, hi, lo, mem, perf, exit_code, head.rstrip('\n')

def perf_limits(text):
    lim = {}
    for l in text.splitlines():
        if l.startswith('# PERF'):
            for tok in l.split()[2:]:
                k, v = tok.split('<='); lim[k] = int(v)
    return lim

def check(name, text):
    words = masm.assemble(text)
    hexf = os.path.join(BUILD, name + '.hex')
    open(hexf, 'w').write(''.join(f'{w:08x}\n' for w in words))
    res = run_rtl(hexf)
    if res is None: return False, 'RTL timeout / no DONE', None
    rregs, rhi, rlo, rmem, perf, rexit, rout = res
    g = mips_iss.run(words)
    gmem = {i: int.from_bytes(g.mem[i:i+4], 'little') for i in range(0, 4096, 4)}
    gmem = {k: v for k, v in gmem.items() if v}
    errs = [f'${i}: rtl={rregs[i]:08x} iss={g.regs[i]:08x}' for i in range(32) if rregs[i] != g.regs[i]]
    if rhi != g.hi: errs.append(f'HI rtl={rhi:08x} iss={g.hi:08x}')
    if rlo != g.lo: errs.append(f'LO rtl={rlo:08x} iss={g.lo:08x}')
    for a in sorted(set(rmem) | set(gmem)):
        if rmem.get(a, 0) != gmem.get(a, 0): errs.append(f'mem[{a:#x}]: rtl={rmem.get(a,0):08x} iss={gmem.get(a,0):08x}')
    if rexit != g.exit_code: errs.append(f'exit rtl={rexit} iss={g.exit_code}')
    if rout.rstrip('\n') != g.out.rstrip('\n'): errs.append(f'console rtl={rout!r} iss={g.out!r}')
    if perf:
        for k, idx in (('cycles', 0), ('stall_br', 3), ('stall_lu', 2)):
            lim = perf_limits(text).get(k)
            if lim is not None and perf[idx] > lim: errs.append(f'perf: {k}={perf[idx]} exceeds limit {lim}')
    return (not errs), '; '.join(errs[:6]), perf

def main():
    nrand = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    build_rtl(); fails = 0
    print(f'{"test":<22}{"result":<7}{"cycles":>7}{"instret":>8}{"CPI":>6}{"ld-use":>7}{"br-stall":>9}{"div":>5}{"taken":>7}')
    for f in sorted(glob.glob(f'{ROOT}/tests/*.s')):
        name = os.path.basename(f)[:-2]
        ok, msg, p = check(name, open(f).read())
        if p: print(f'{name:<22}{"PASS" if ok else "FAIL":<7}{p[0]:>7}{p[1]:>8}{p[0]/max(p[1],1):>6.2f}{p[2]:>7}{p[3]:>9}{p[4]:>5}{p[5]:>7}')
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
