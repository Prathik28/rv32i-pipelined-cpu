# Branch / jump operands produced at every distance (ID-stage forwarding and stalls)
# PERF stall_br<=22
    li    $s0, 0
    li    $t0, 3
    addiu $t1, $t0, 0         # producer immediately before the branch (stall)
    beq   $t0, $t1, p1
    nop
    li    $s7, 1
p1: addiu $s0, $s0, 1
    addiu $t2, $zero, 4
    nop
    bne   $t2, $zero, p2      # producer two before: forwarded from MEM, no stall
    nop
    li    $s7, 2
p2: addiu $s0, $s0, 1
    li    $t3, 9
    sw    $t3, 0x40($zero)
    lw    $t4, 0x40($zero)
    beq   $t4, $t3, p3        # LOAD immediately before the branch (2 stalls)
    nop
    li    $s7, 3
p3: addiu $s0, $s0, 1
    lw    $t5, 0x40($zero)
    nop
    bgtz  $t5, p4             # load one instruction earlier (1 stall)
    nop
    li    $s7, 4
p4: addiu $s0, $s0, 1
    lw    $t6, 0x40($zero)
    nop
    nop
    bgez  $t6, p5             # load two instructions earlier (no stall)
    nop
    li    $s7, 5
p5: addiu $s0, $s0, 1
    la    $t7, p6
    jr    $t7                 # jump register computed just before (stall)
    nop
    li    $s7, 6
p6: addiu $s0, $s0, 1
    lw    $t8, 0x40($zero)
    sw    $t8, 0x44($zero)
    li    $t9, 1
    sub:  subu $t9, $t9, $t9
    bne   $t9, $zero, bad     # branch consumes a value computed by the previous instruction
    nop
    jal   p7
    nop
    j     fin
    nop
p7: jr    $ra                 # $ra written by JAL two instructions earlier
    nop
bad: li   $s7, 99
fin: halt
