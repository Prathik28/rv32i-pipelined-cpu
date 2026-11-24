# M extension: all 8 ops, edge cases, and hazards around the multi-cycle divider
    li   x1, 0x12345678
    li   x2, -7
    li   x3, 0x80000000
    li   x4, -1
    mul    x5,  x1, x2
    mulh   x6,  x1, x2
    mulhsu x7,  x2, x1      # signed * unsigned
    mulhu  x8,  x2, x1
    mulh   x9,  x3, x3
    mulhu  x10, x4, x4
    div    x11, x1, x2
    divu   x12, x2, x1
    rem    x13, x1, x2
    remu   x14, x2, x1
    div    x15, x3, x4      # signed overflow: INT_MIN / -1
    rem    x16, x3, x4      # -> 0
    div    x17, x1, x0      # divide by zero -> -1
    divu   x18, x1, x0      # -> 0xFFFFFFFF
    rem    x19, x1, x0      # -> dividend
    remu   x20, x1, x0
    # hazards around the divider
    li   x21, 100
    li   x22, 7
    div  x23, x21, x22      # 14
    add  x24, x23, x23      # dependent on div result (forward after stall)
    mul  x25, x24, x22      # mul consuming forwarded value
    rem  x26, x25, x22      # back-to-back divides
    div  x27, x25, x22
    sw   x27, 0x40(x0)
    lw   x28, 0x40(x0)
    div  x29, x28, x22      # load-use into divider
    beq  x29, x23, ok       # branch consuming div result
    li   x30, 111
ok: addi x30, x30, 5
    halt
