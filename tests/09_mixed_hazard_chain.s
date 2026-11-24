# Load -> ALU -> branch -> store chain with every hazard type stacked
    li   x1, 6
    sw   x1, 0x60(x0)
    lw   x2, 0x60(x0)
    addi x3, x2, 1        # load-use
    beq  x3, x1, skip     # not taken (7 != 6), depends on forwarded value
    addi x4, x3, 1        # 8
    bne  x4, x3, taken    # taken
    li   x5, 111          # flushed
taken:
    sw   x4, 0x64(x0)
    lw   x6, 0x64(x0)
    jal  x7, sub1
    add  x8, x6, x9       # uses result of subroutine
    halt
skip: li x5, 222
sub1: addi x9, x6, 100
    jalr x0, 0(x7)
