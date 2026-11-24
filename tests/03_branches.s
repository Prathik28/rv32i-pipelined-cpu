# Control hazards: taken / not-taken for every branch type, branch after ALU/load dependence
    li   x1, 10
    li   x2, -10
    li   x20, 0
    beq  x1, x1, t1
    addi x20, x20, 1      # must be flushed
    addi x20, x20, 1
t1: bne  x1, x1, bad
    bne  x1, x2, t2
    addi x20, x20, 1
t2: blt  x2, x1, t3       # signed
    addi x20, x20, 1
t3: bge  x1, x2, t4
    addi x20, x20, 1
t4: bltu x1, x2, t5       # unsigned: 10 < 0xFFFFFFF6
    addi x20, x20, 1
t5: bgeu x2, x1, t6
    addi x20, x20, 1
t6: addi x3, x0, 4        # branch depends on just-computed value (forwarding into compare)
    addi x4, x0, 4
    beq  x3, x4, t7
    addi x20, x20, 1
t7: sw   x3, 0x40(x0)
    lw   x5, 0x40(x0)
    beq  x5, x3, t8       # branch depends on load result (load-use stall + compare)
    addi x20, x20, 1
t8: li   x6, 0
loop: addi x6, x6, 1      # backward loop: taken 9 times
    addi x7, x6, 0
    blt  x7, x1, loop
    j    done
bad: li  x20, 999
done: halt
