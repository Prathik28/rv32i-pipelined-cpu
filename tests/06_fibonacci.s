# fib(0..15) into memory, then sum them (loop with RAW, load-use, branch hazards)
    li   x1, 0           # a
    li   x2, 1           # b
    li   x3, 0           # i
    li   x4, 16
    li   x5, 0x200       # base
fib: sw  x1, 0(x5)
    add  x6, x1, x2
    mv   x1, x2
    mv   x2, x6
    addi x5, x5, 4
    addi x3, x3, 1
    bne  x3, x4, fib
    li   x5, 0x200
    li   x3, 0
    li   x7, 0           # sum
sum: lw  x8, 0(x5)
    add  x7, x7, x8      # load-use each iteration
    addi x5, x5, 4
    addi x3, x3, 1
    bne  x3, x4, sum
    halt
