# MIPS hazard demo: forwarding, load-use, branch-operand stalls, branch delay slot, divider
    addiu $t0, $zero, 5
    addiu $t1, $t0, 1         # RAW: forward EX/MEM -> EX
    addu  $t2, $t1, $t0       # RAW: forward from both stages
    sw    $t2, 0x40($zero)
    lw    $t3, 0x40($zero)
    addu  $t4, $t3, $t0       # load-use: 1 stall
    li    $t5, 3
    div   $t4, $t5            # structural: iterative divider stalls the front end
    mflo  $t6
    addiu $t7, $zero, 0
loop:
    addiu $t7, $t7, 1         # (branch operand produced by the previous instruction)
    bne   $t7, $t5, loop      # taken twice; the delay slot below executes every time
    addiu $t6, $t6, 1         # delay slot: useful work, no branch penalty
    halt
