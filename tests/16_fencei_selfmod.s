# Self-modifying code through the instruction RAM data port; FENCE.I flushes the pipeline
    lui  x1, 0x30000          # instruction RAM as seen from the data bus
    la   x2, patch
    add  x4, x1, x2
    li   x3, 0x00500513       # addi x10, x0, 5
    sw   x3, 0(x4)
    fence.i
patch:
    addi x10, x0, 99          # replaced by the store above (must NOT execute)
    lw   x5, 0(x4)            # the data port sees the new encoding
    # patch repeatedly with different immediates inside a loop
    li   x6, 0
    li   x7, 5
    la   x8, patch2
    add  x9, x1, x8
loop:
    slli x11, x6, 20          # immediate << 20
    li   x12, 0x00000593      # addi x11, x0, 0
    or   x12, x12, x11
    sw   x12, 0(x9)
    fence.i
patch2:
    addi x11, x0, 0
    add  x13, x13, x11        # accumulate the patched constants 0+1+2+3+4
    addi x6, x6, 1
    blt  x6, x7, loop
    # patch a branch into a taken jump over an instruction
    la   x14, patch3
    add  x15, x1, x14
    li   x16, 0x0080006f      # jal x0, +8
    sw   x16, 0(x15)
    fence.i
patch3:
    nop
    li   x17, 111             # skipped by the patched jump
    li   x18, 222
    halt
