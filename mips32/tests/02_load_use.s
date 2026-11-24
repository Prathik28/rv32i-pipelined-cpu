# Load-use hazards, store data forwarded from a load
    li    $t0, 0x11223344
    sw    $t0, 0x100($zero)
    lw    $t1, 0x100($zero)
    addu  $t2, $t1, $t1       # immediate load-use: 1 stall
    lw    $t3, 0x100($zero)
    addiu $t4, $zero, 7
    addu  $t5, $t3, $t4       # one instruction between: forward from WB
    lw    $t6, 0x100($zero)
    sw    $t6, 0x104($zero)   # load -> store data (stall)
    lw    $t7, 0x104($zero)
    andi  $t7, $t7, 0xfc
    lw    $s0, 0x100($t7)     # load feeding the address of the next load
    halt
