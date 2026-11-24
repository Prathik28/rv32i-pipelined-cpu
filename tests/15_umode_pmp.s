# User mode, PMP (locked / NA4 / NAPOT entries), access faults, mcounteren, ECALL from U-mode
    la   x1, handler
    csrw mtvec, x1
    li   x10, 0              # trap counter
    li   x11, 0              # running hash of causes
    li   x12, 0              # sum of mtvals
    # PMP:  e0 = locked NA4 @0x800, no permission (even M-mode is blocked)
    #       e1 = NA4 @0x400, read-only     e2 = NAPOT 0xC00..0xCFF, RW (no execute)
    #       e3 = NAPOT 0..0xFFF, RWX
    li   x2, 0x200
    csrw pmpaddr0, x2
    li   x2, 0x100
    csrw pmpaddr1, x2
    li   x2, 0x31F
    csrw pmpaddr2, x2
    li   x2, 0x1FF
    csrw pmpaddr3, x2
    li   x2, 0x1F1B1190
    csrw pmpcfg0, x2
    csrr x13, pmpcfg0
    csrr x14, pmpaddr0
    li   x2, 0x55
    csrw pmpaddr0, x2        # locked: ignored
    csrw pmpcfg0, x0         # entry 0 locked: byte 0 unchanged, the others cleared
    csrr x15, pmpcfg0
    csrr x16, pmpaddr0
    li   x2, 0x1F1B1190
    csrw pmpcfg0, x2         # restore entries 1-3
    # M-mode: the locked entry blocks M-mode too
    sw   x2, 0x7FC(x0)       # fine
    li   x5, 0x800
    lw   x17, 0(x5)          # load access fault (cause 5)
    sw   x2, 0(x5)           # store access fault (cause 7)
    csrw mcounteren, x0
    # enter U-mode: MPP = 0
    li   x2, 0x1800
    csrc mstatus, x2
    la   x2, user
    csrw mepc, x2
    mret
user:
    li   x20, 0x123
    sw   x20, 0x300(x0)      # ok
    lw   x21, 0x300(x0)
    lw   x22, 0x400(x0)      # read-only entry: load ok
    sw   x20, 0x400(x0)      # store fault (7)
    sw   x20, 0x404(x0)      # ok
    li   x5, 0xC00
    sw   x20, 0(x5)          # NAPOT RW: ok
    li   x5, 0x800
    lw   x23, 0(x5)          # locked no-permission entry: fault (5)
    li   x2, 0x10000000
    sw   x20, 16(x2)         # MMIO has no PMP entry: store fault (7)
    lw   x24, 12(x2)         # load fault (5)
    lui  x2, 0x20000
    lw   x25, 0(x2)          # slow RAM: no entry: fault (5)
    lui  x2, 0x40000
    lw   x26, 0(x2)          # unmapped address: fault (5)
    csrr x27, mscratch       # M-mode CSR from U: illegal (2)
    csrr x28, cycle          # mcounteren = 0: illegal (2)
    mret                     # illegal in U-mode (2)
    ecall                    # ECALL from U-mode: cause 8
    la   x30, back
    li   x2, 0xC00
    jalr x0, 0(x2)           # fetch from the no-execute region: instruction access fault (1)
back:
    li   x2, 0x2000
    jalr x0, 0(x2)           # fetch outside instruction memory: fault (1)
back2:
    li   x17, 1              # tell the handler to finish
    ecall
handler:
    csrr x28, mcause
    slli x11, x11, 3
    add  x11, x11, x28
    addi x10, x10, 1
    csrr x29, mtval
    add  x12, x12, x29
    li   x29, 1
    beq  x28, x29, fetchfault
    li   x29, 8
    bne  x28, x29, resume
    li   x29, 1
    beq  x17, x29, done      # final ECALL
resume:
    csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
fetchfault:
    csrr x28, mepc
    li   x29, 0xC00
    bne  x28, x29, ffb
    csrw mepc, x30           # case 1: resume at `back`
    mret
ffb:
    la   x29, back2          # case 2: resume at `back2`
    csrw mepc, x29
    mret
done:
    halt
