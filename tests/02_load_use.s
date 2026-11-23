# Load-use hazards (stall + forward), store-after-load data forwarding
    li   x1, 0x11223344
    sw   x1, 0x100(x0)
    lw   x2, 0x100(x0)
    add  x3, x2, x2       # immediate load-use -> 1 stall
    lw   x4, 0x100(x0)
    addi x5, x0, 7
    add  x6, x4, x5       # load, 1 independent, use -> forward from WB
    lw   x7, 0x100(x0)
    sw   x7, 0x104(x0)    # load -> store data (stall)
    lw   x8, 0x104(x0)
    andi x8, x8, 0xfc     # load result feeds address computation
    lw   x9, 0x100(x8)    # load-use through the address operand
    ecall
