# fib(0..15) into memory then summed; loop delay slots do useful work
    li    $t0, 0              # a
    li    $t1, 1              # b
    li    $t2, 0              # i
    li    $t3, 16
    li    $t4, 0x200
fib:
    sw    $t0, 0($t4)
    addu  $t5, $t0, $t1
    move  $t0, $t1
    move  $t1, $t5
    addiu $t2, $t2, 1
    bne   $t2, $t3, fib
    addiu $t4, $t4, 4         # delay slot: pointer bump (executes on every iteration, incl. the last)
    li    $t4, 0x200
    li    $t2, 0
    li    $s0, 0
sum:
    lw    $t6, 0($t4)
    addiu $t2, $t2, 1
    addu  $s0, $s0, $t6       # load-use separated by one instruction
    bne   $t2, $t3, sum
    addiu $t4, $t4, 4
    halt
