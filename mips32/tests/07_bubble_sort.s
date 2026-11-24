# Bubble sort of 12 words (load-use + branch-operand hazards everywhere)
    li    $s0, 0x300
    li    $t0, 91
    sw    $t0, 0($s0)
    li    $t0, -5
    sw    $t0, 4($s0)
    li    $t0, 33
    sw    $t0, 8($s0)
    li    $t0, 7
    sw    $t0, 12($s0)
    li    $t0, 120
    sw    $t0, 16($s0)
    li    $t0, 0
    sw    $t0, 20($s0)
    li    $t0, -77
    sw    $t0, 24($s0)
    li    $t0, 42
    sw    $t0, 28($s0)
    sw    $t0, 32($s0)
    li    $t0, 1000
    sw    $t0, 36($s0)
    li    $t0, 15
    sw    $t0, 40($s0)
    li    $t0, -1
    sw    $t0, 44($s0)
    li    $s1, 11             # outer count
outer:
    li    $t1, 0              # j
    move  $t2, $s0            # pointer
inner:
    lw    $t3, 0($t2)
    lw    $t4, 4($t2)
    slt   $t5, $t4, $t3       # t4 < t3 ?
    beq   $t5, $zero, noswap  # branch on a value computed just before (1 stall)
    nop
    sw    $t4, 0($t2)
    sw    $t3, 4($t2)
noswap:
    addiu $t2, $t2, 4
    addiu $t1, $t1, 1
    bne   $t1, $s1, inner
    nop
    addiu $s1, $s1, -1
    bgtz  $s1, outer
    nop
    halt
