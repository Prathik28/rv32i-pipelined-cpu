# A extension: LR/SC reservations, every AMO, hazards, slow RAM, traps
    li   x1, 0x200
    li   x2, 5
    sw   x2, 0(x1)
    lr.w x3, (x1)             # x3 = 5
    li   x4, 9
    sc.w x5, x4, (x1)         # succeeds -> x5 = 0, mem = 9
    sc.w x6, x4, (x1)         # reservation consumed -> fails, x6 = 1
    lw   x7, 0(x1)
    lr.w x8, (x1)
    addi x9, x1, 4
    sc.w x10, x4, (x9)        # different address -> fails
    amoswap.w x11, x2, (x1)   # old 9, new 5
    amoadd.w  x12, x4, (x1)   # old 5, new 14
    amoxor.w  x13, x2, (x1)   # old 14, new 11
    amoand.w  x14, x4, (x1)   # old 11 & 9 = 9
    amoor.w   x15, x2, (x1)   # old 9, new 13
    lw   x16, 0(x1)
    li   x17, -7
    sw   x17, 8(x1)
    addi x18, x1, 8
    li   x19, 3
    amomin.w  x20, x19, (x18)  # signed min(-7,3) = -7
    amomax.w  x21, x19, (x18)  # signed max(-7,3) = 3
    amominu.w x22, x17, (x18)  # unsigned min(3, 0xFFFFFFF9) = 3
    amomaxu.w x23, x17, (x18)  # unsigned max -> 0xFFFFFFF9
    lw   x24, 0(x18)
    # AMO result used immediately (load-use through the AMO), and AMO chain
    amoadd.w x25, x2, (x1)
    add  x26, x25, x25
    amoadd.w x27, x26, (x1)
    # slow RAM
    lui  x28, 0x20000
    li   x29, 100
    sw   x29, 0(x28)
    amoadd.w x30, x2, (x28)
    lr.w x31, (x28)
    sw   x30, 0x40(x0)
    sc.w x30, x2, (x28)
    sw   x30, 0x44(x0)
    # traps: misaligned AMO (cause 6), LR misaligned (cause 4), AMO to MMIO (cause 7)
    la   x1, handler
    csrw mtvec, x1
    li   x2, 0x201
    amoadd.w x3, x4, (x2)
    lr.w x3, (x2)
    li   x2, 0x10000008
    amoadd.w x3, x4, (x2)
    # a trap cancels the reservation: LR; ecall; SC must fail
    li   x5, 0x300
    lr.w x6, (x5)
    ecall
    sc.w x7, x4, (x5)
    halt
handler:
    csrr x8, mcause
    add  x9, x9, x8
    csrr x8, mepc
    addi x8, x8, 4
    csrw mepc, x8
    mret
