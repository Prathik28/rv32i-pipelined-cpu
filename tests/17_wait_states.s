# Slow RAM with wait states: the pipeline freezes in MEM; forwarding and hazards must still work
    li   x21, 0x10000000
    li   x22, 3
    sw   x22, 20(x21)         # WAITCFG = 3 extra cycles per slow access
    lui  x20, 0x20000
    li   x1, 0
    li   x2, 8
    mv   x3, x20
fill:
    sw   x1, 0(x3)            # array[i] = i*i in slow RAM
    mul  x4, x1, x1
    sw   x4, 0(x3)
    addi x3, x3, 4
    addi x1, x1, 1
    blt  x1, x2, fill
    li   x5, 0
    li   x1, 0
    mv   x3, x20
sum:
    lw   x6, 0(x3)            # load-use on a slow load
    add  x5, x5, x6
    addi x3, x3, 4
    addi x1, x1, 1
    blt  x1, x2, sum
    # producer / consumer pairs straddling a frozen pipeline
    addi x7, x0, 7
    lw   x8, 0(x20)           # slow load in MEM while younger instructions wait
    add  x9, x7, x7           # consumer of a value produced just before the load
    add  x10, x9, x7
    lw   x11, 4(x20)
    lw   x12, 8(x20)
    add  x13, x11, x12
    sw   x13, 0x40(x0)        # fast RAM store after slow loads
    lw   x14, 0x40(x0)
    # misaligned + atomic + divide mixed with waits
    lw   x15, 0x101(x20)
    sw   x15, 0x105(x20)
    lw   x16, 0x104(x20)
    li   x17, 3
    amoadd.w x18, x17, (x20)
    div  x19, x5, x17
    rem  x23, x5, x17
    lw   x24, 0(x20)
    sw   x22, 20(x21)         # WAITCFG again (MMIO store while frozen traffic around)
    lw   x25, 28(x20)
    beq  x25, x25, ok
    li   x26, 5
ok: add  x27, x25, x25
    halt
