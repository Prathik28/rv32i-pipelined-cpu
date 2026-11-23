# RAW hazards: back-to-back, 1-apart, 2-apart, 3-apart (regfile write-through)
    addi x1, x0, 5
    addi x2, x1, 3        # EX/MEM -> EX forward (distance 1)
    add  x3, x2, x1       # both sources forwarded from different stages
    nop
    add  x4, x3, x2       # MEM/WB forward (distance 2 to x3 producer is nop-separated)
    nop
    nop
    add  x5, x4, x4       # distance 3: regfile write-through
    sub  x6, x5, x1
    xor  x7, x6, x6       # same reg both operands
    addi x8, x7, 1
    addi x8, x8, 1        # chained dependency
    addi x8, x8, 1
    addi x8, x8, 1
    add  x0, x8, x8       # write to x0 must be ignored
    add  x9, x0, x8       # x0 must read as zero
    ecall
