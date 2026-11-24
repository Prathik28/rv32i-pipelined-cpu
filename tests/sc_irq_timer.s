# Self-checking: machine timer interrupt.  Exit code 0 = pass.
# main loop spins until the handler has run 4 times; each interrupt re-arms the timer.
    la   x1, handler
    csrw mtvec, x1
    li   x20, 0              # interrupt counter (written by handler)
    li   x2, 0x10000000
    lw   x3, 12(x2)          # mtime
    addi x3, x3, 60
    sw   x3, 8(x2)           # mtimecmp = mtime + 60
    li   x4, 0x80
    csrw mie, x4             # MTIE
    csrsi mstatus, 8         # MIE
    li   x5, 4
    li   x6, 0               # spin counter (arithmetic keeps the pipeline busy: div, mul, branches)
spin:
    addi x6, x6, 1
    mul  x7, x6, x6
    div  x8, x7, x6
    bne  x20, x5, spin
    csrci mstatus, 8         # disable interrupts
    li   x9, 0x80000007
    csrr x10, mcause
    bne  x10, x9, fail
    li   x11, 20
    blt  x6, x11, fail
    # x8 must equal x6 (div(mul(x6,x6),x6)) => interrupted arithmetic was not corrupted
    bne  x8, x6, fail
    sw   x0, 0(x2)           # HALT, exit code 0
fail:
    li   x30, 1
    sw   x30, 0(x2)
handler:
    addi x20, x20, 1
    li   x28, 0x10000000
    lw   x29, 12(x28)
    addi x29, x29, 60
    sw   x29, 8(x28)         # re-arm (also clears the pending interrupt)
    mret
