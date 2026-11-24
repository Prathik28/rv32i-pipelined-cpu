#!/usr/bin/env python3
"""Render selected signals of a VCD file as an SVG waveform (no GTKWave needed).
usage: vcd2svg.py wave.vcd out.svg [first_cycle] [n_cycles]
Signals are sampled once per clock (just before each rising edge)."""
import re, sys

SIGNALS = [  # (label, hierarchical suffix, kind)
    ('clk',             'tb_riscv.clk',                      'bit'),
    ('pc (IF)',         'tb_riscv.dut.u_core.pc',            'hex'),
    ('load_use stall',  'tb_riscv.dut.u_core.load_use',      'bit'),
    ('div busy stall',  'tb_riscv.dut.u_core.ex_stall',      'bit'),
    ('mispredict',      'tb_riscv.dut.u_core.mispredict',    'bit'),
    ('trap_take',       'tb_riscv.dut.u_core.trap_take',     'bit'),
    ('redirect',        'tb_riscv.dut.u_core.redirect',      'bit'),
    ('fwd_a (EX)',      'tb_riscv.dut.u_core.fwd_a',         'dec'),
    ('fwd_b (EX)',      'tb_riscv.dut.u_core.fwd_b',         'dec'),
    ('EX/MEM rd',       'tb_riscv.dut.u_core.exmem_rd',      'dec'),
    ('WB data',         'tb_riscv.dut.u_core.wb_data',       'hex'),
]

def parse(path):
    ids, scope, vals, changes, t = {}, [], {}, [], 0
    want = {s[1]: s for s in SIGNALS}
    code2name = {}
    for line in open(path):
        line = line.strip()
        if line.startswith('$scope'): scope.append(line.split()[2])
        elif line.startswith('$upscope'): scope.pop()
        elif line.startswith('$var'):
            p = line.split(); code, name = p[3], p[4]
            full = '.'.join(scope + [name])
            if full in want: code2name.setdefault(code, []).append(full)
        elif line.startswith('#'): t = int(line[1:])
        elif line and line[0] in '01xz' and len(line) > 1 and line[1:] in code2name:
            changes.append((t, line[1:], line[0]))
        elif re.match(r'^b[01xzXZ]+ \S+$', line):
            v, code = line[1:].split()
            if code in code2name: changes.append((t, code, v))
    return code2name, changes

def main():
    vcd, out = sys.argv[1], sys.argv[2]
    first = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    ncyc = int(sys.argv[4]) if len(sys.argv) > 4 else 40
    code2name, changes = parse(vcd)
    names = {n: c for c, ns in code2name.items() for n in ns}
    clkc = names['tb_riscv.clk']
    # clock rising edges
    cur, edges = {}, []
    state = {}
    seq = sorted(changes, key=lambda x: x[0])
    # sample values just before each rising edge of clk
    samples = []; val = {}; prev_clk = '0'
    from itertools import groupby
    for t, grp in groupby(seq, key=lambda x: x[0]):
        grp = list(grp)
        rising = any(c == clkc and v == '1' for (_, c, v) in grp) and prev_clk != '1'
        if rising: samples.append(dict(val))          # value just BEFORE the edge
        for (_, c, v) in grp:
            val[c] = v
            if c == clkc: prev_clk = v
    samples = samples[3:]                       # skip reset cycles
    samples = samples[first:first+ncyc]
    W, H, L, rowh = 40, 26, 130, 34
    width = L + W * len(samples) + 20; height = 40 + rowh * len(SIGNALS)
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" font-family="monospace" font-size="11">',
           f'<rect width="{width}" height="{height}" fill="white"/>']
    for k in range(len(samples)):
        svg.append(f'<text x="{L+k*W+W/2}" y="14" text-anchor="middle" fill="#666">{first+k}</text>')
        svg.append(f'<line x1="{L+k*W}" y1="20" x2="{L+k*W}" y2="{height}" stroke="#eee"/>')
    for r, (label, full, kind) in enumerate(SIGNALS):
        y0 = 30 + r * rowh; code = names[full]
        svg.append(f'<text x="4" y="{y0+17}" fill="#222">{label}</text>')
        last = None
        for k, s in enumerate(samples):
            v = s.get(code, '0'); x = L + k * W
            if kind == 'bit' and label != 'clk':
                hi = (v == '1'); y = y0 + (4 if hi else 22)
                col = '#d33' if hi and label in ('mispredict','trap_take','redirect') else '#e90' if hi else '#37a'
                svg.append(f'<line x1="{x}" y1="{y}" x2="{x+W}" y2="{y}" stroke="{col}" stroke-width="2"/>')
                if last is not None and last != hi:
                    svg.append(f'<line x1="{x}" y1="{y0+4}" x2="{x}" y2="{y0+22}" stroke="{col}" stroke-width="2"/>')
                last = hi
            elif label == 'clk':
                svg.append(f'<polyline points="{x},{y0+22} {x},{y0+4} {x+W/2},{y0+4} {x+W/2},{y0+22} {x+W},{y0+22}" fill="none" stroke="#37a"/>')
            else:
                num = int(v, 2) if set(v) <= {'0','1'} else None
                txt = '?' if num is None else (f'{num:x}' if kind == 'hex' else str(num))
                if kind == 'hex' and num is not None and len(txt) > 4: txt = txt[-4:]
                chg = (last != num)
                fill = '#dfe9f7' if chg else '#f3f6fb'
                svg.append(f'<rect x="{x+1}" y="{y0+4}" width="{W-2}" height="18" fill="{fill}" stroke="#9ab"/>')
                svg.append(f'<text x="{x+W/2}" y="{y0+17}" text-anchor="middle" fill="#123">{txt}</text>')
                last = num
    svg.append('</svg>')
    open(out, 'w').write('\n'.join(svg))

if __name__ == '__main__': main()
