#!/usr/bin/env python3
"""Render the MIPS RTL's +trace log as a pipeline-occupancy diagram (SVG).
usage: pipeline_diagram.py prog.s out.svg [first_cycle] [n_cycles]
orange = held by a stall (load-use / branch operand / divider)   blue AM/AW/BM/BW = forwarding
green outline on ID = a branch or jump redirects fetch (the delay slot is already in IF)"""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
import masm
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

def main():
    src, out = sys.argv[1], sys.argv[2]
    first = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    ncyc = int(sys.argv[4]) if len(sys.argv) > 4 else 40
    words = masm.assemble(open(src).read()); listing = masm.LISTING
    hexf = os.path.join(ROOT, 'build', 'diagram.hex')
    open(hexf, 'w').write(''.join(f'{w:08x}\n' for w in words))
    p = subprocess.run(['vvp', 'build/sim', '+hex=build/diagram.hex', '+trace'], cwd=ROOT, capture_output=True, text=True)
    rows = [l.split()[1:] for l in p.stdout.splitlines() if l.startswith('TRACE')][first:first+ncyc]
    cols = []
    for r in rows:                      # collapse runs of identical cycles (e.g. the 32-cycle divide)
        if cols and cols[-1][1] == r[1:]: cols[-1][2] += 1; cols[-1][3] = r[0]
        else: cols.append([r, r[1:], 1, r[0]])
    def text(pc):
        pc = int(pc, 16)
        if pc == 0xFFFFFFFF: return ''
        i = pc // 4
        return listing[i] if i < len(listing) else 'nop'
    CW, RH, L, PER = 118, 30, 44, 9
    PH = 24 + RH * 5 + 30; npan = (len(cols) + PER - 1) // PER
    W = L + CW * PER + 10; H = PH * npan + 24
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="monospace" font-size="10.5">',
         f'<rect width="{W}" height="{H}" fill="white"/>']
    for k, (r, _key, rep, last) in enumerate(cols):
        oy = (k // PER) * PH; col = k % PER; x = L + col * CW
        if col == 0:
            for rr, name in enumerate(['IF', 'ID', 'EX', 'MEM', 'WB']):
                s.append(f'<text x="6" y="{oy+24+rr*RH+17}" font-weight="bold" fill="#234">{name}</text>')
        cyc, pcs = r[0], r[1:6]
        lu, exs, brs, taken, fa, fb = r[6], r[7], r[8], r[9], int(r[10]), int(r[11])
        lbl = "cycle " + cyc if rep == 1 else f"cycles {cyc}-{last}  (x{rep})"
        s.append(f'<text x="{x+CW/2}" y="{oy+14}" text-anchor="middle" fill="#666">{lbl}</text>')
        held = lu == '1' or exs == '1' or brs == '1'
        for st in range(5):
            y = oy + 24 + st * RH; t = text(pcs[st]); fill = '#eef3fa'
            if st <= 1 and held: fill = '#ffe2b0'
            if st == 2 and exs == '1': fill = '#ffe2b0'
            if not t: fill = '#fafafa'
            stroke = '#2a9d4a' if (st == 1 and taken == '1') else '#b8c4d4'
            sw = 2.2 if stroke == '#2a9d4a' else 1
            s.append(f'<rect x="{x+1}" y="{y}" width="{CW-2}" height="{RH-4}" rx="3" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')
            s.append(f'<text x="{x+6}" y="{y+(RH-4)/2+4}" fill="#123">{t[:18]}</text>')
        if text(pcs[2]):
            for lab, f in (('A', fa), ('B', fb)):
                if f:
                    ox = x + CW - 38 + (0 if lab == 'A' else 18)
                    s.append(f'<rect x="{ox}" y="{oy+24+2*RH-1}" width="17" height="11" rx="2" fill="#2f6fd0"/>'
                             f'<text x="{ox+8.5}" y="{oy+24+2*RH+8}" text-anchor="middle" fill="white" font-size="9">{lab}{"M" if f==2 else "W"}</text>')
        ev = [e for e, c in (('load-use stall', lu == '1'), ('branch stall', brs == '1'),
                             ('divider busy', exs == '1'), ('taken', taken == '1')) if c]
        if ev: s.append(f'<text x="{x+CW/2}" y="{oy+24+5*RH+12}" text-anchor="middle" fill="#b02020" font-size="9">{" + ".join(ev)[:26]}</text>')
    s.append(f'<text x="{L}" y="{H-8}" fill="#555" font-size="10">orange = held by stall, green outline = taken branch/jump, blue AM/AW/BM/BW = operand A/B forwarded from EX/MEM (M) or MEM/WB (W)</text>')
    s.append('</svg>'); open(out, 'w').write('\n'.join(s))

if __name__ == '__main__': main()
