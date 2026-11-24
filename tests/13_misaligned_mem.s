# Misaligned loads/stores are handled in hardware (two bus transactions) in RAM and slow RAM
    li   x1, 0x11223344
    li   x2, 0x55667788
    sw   x1, 0x100(x0)
    sw   x2, 0x104(x0)
    lw   x3, 0x101(x0)        # straddles the word boundary
    lw   x4, 0x102(x0)
    lw   x5, 0x103(x0)
    lh   x6, 0x103(x0)        # halfword across the boundary, sign-extended
    lhu  x7, 0x103(x0)
    lh   x8, 0x101(x0)        # inside one word, odd offset
    lhu  x9, 0x101(x0)
    li   x20, 0xAABBCCDD
    sw   x20, 0x109(x0)       # misaligned stores
    sh   x20, 0x10F(x0)
    sh   x20, 0x111(x0)
    sw   x20, 0x116(x0)
    lw   x10, 0x108(x0)
    lw   x11, 0x10C(x0)
    lw   x12, 0x110(x0)
    lw   x13, 0x114(x0)
    lw   x14, 0x118(x0)
    # hazards around misaligned accesses
    lw   x15, 0x101(x0)
    add  x16, x15, x15        # load-use on a two-phase load
    sw   x16, 0x121(x0)
    lw   x17, 0x121(x0)       # store -> load, both misaligned
    addi x18, x17, 1
    # the same in slow RAM
    lui  x21, 0x20000
    sw   x1, 0x100(x21)
    sw   x2, 0x104(x21)
    lw   x22, 0x101(x21)
    lh   x23, 0x103(x21)
    sw   x20, 0x109(x21)
    lw   x24, 0x108(x21)
    lw   x25, 0x10C(x21)
    # misaligned access to MMIO is NOT supported: it must trap (cause 4 / 6)
    la   x26, handler
    csrw mtvec, x26
    li   x27, 0x10000000
    lw   x28, 2(x27)          # trap
    sw   x28, 6(x27)          # trap
    li   x29, 77
    halt
handler:
    csrr x30, mcause
    add  x31, x31, x30        # sum of causes (4 + 6)
    csrr x30, mepc
    addi x30, x30, 4
    csrw mepc, x30
    mret
