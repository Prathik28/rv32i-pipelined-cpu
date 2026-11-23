# Bubble sort of 12 words in memory (heavy load-use + branch hazards)
    li   x10, 0x300
    li   x1, 12
    li   x2, 91
    sw x2, 0(x10)
    li x2, -5
    sw x2, 4(x10)
    li x2, 33
    sw x2, 8(x10)
    li x2, 7
    sw x2, 12(x10)
    li x2, 120
    sw x2, 16(x10)
    li x2, 0
    sw x2, 20(x10)
    li x2, -77
    sw x2, 24(x10)
    li x2, 42
    sw x2, 28(x10)
    li x2, 42
    sw x2, 32(x10)
    li x2, 1000
    sw x2, 36(x10)
    li x2, 15
    sw x2, 40(x10)
    li x2, -1
    sw x2, 44(x10)
    addi x3, x1, -1       # outer = n-1
outer:
    li   x4, 0            # j
    li   x5, 0            # base ptr
inner:
    add  x6, x10, x5
    lw   x7, 0(x6)
    lw   x8, 4(x6)
    ble  x7, x8, noswap   # load-use on both
    sw   x8, 0(x6)
    sw   x7, 4(x6)
noswap:
    addi x5, x5, 4
    addi x4, x4, 1
    blt  x4, x3, inner
    addi x3, x3, -1
    bnez x3, outer
    ecall
