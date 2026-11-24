# LWL / LWR / SWL / SWR at every byte offset, merging with the destination register
    li    $t0, 0x44332211
    sw    $t0, 0x100($zero)
    li    $t1, 0x88776655
    sw    $t1, 0x104($zero)
    li    $t2, 0xCCBBAA99
    sw    $t2, 0x108($zero)
    # unaligned word loads: LWR at A, LWL at A+3
    lwr   $s0, 0x101($zero)
    lwl   $s0, 0x104($zero)       # bytes 0x101..0x104
    lwr   $s1, 0x102($zero)
    lwl   $s1, 0x105($zero)
    lwr   $s2, 0x103($zero)
    lwl   $s2, 0x106($zero)
    lwr   $s3, 0x104($zero)       # aligned: LWR loads the whole word
    lwl   $s3, 0x107($zero)
    # partial loads keep the untouched bytes of the register
    li    $s4, 0xAAAAAAAA
    lwl   $s4, 0x102($zero)       # high 3 bytes replaced
    li    $s5, 0xBBBBBBBB
    lwr   $s5, 0x102($zero)       # low 2 bytes replaced
    li    $s6, 0xDDDDDDDD
    lwl   $s6, 0x100($zero)       # only the top byte
    li    $s7, 0xEEEEEEEE
    lwr   $s7, 0x103($zero)       # only the low byte
    # unaligned word stores: SWR at A, SWL at A+3
    li    $t3, 0x01020304
    swr   $t3, 0x111($zero)
    swl   $t3, 0x114($zero)
    li    $t4, 0x0A0B0C0D
    swr   $t4, 0x122($zero)
    swl   $t4, 0x125($zero)
    li    $t5, 0x11121314
    swr   $t5, 0x133($zero)
    swl   $t5, 0x136($zero)
    lw    $t6, 0x110($zero)
    lw    $t7, 0x114($zero)
    lw    $t8, 0x120($zero)
    lw    $t9, 0x124($zero)
    lw    $a0, 0x130($zero)
    lw    $a1, 0x134($zero)
    # partial stores
    li    $a2, 0x99887766
    swl   $a2, 0x140($zero)       # one byte
    swr   $a2, 0x143($zero)       # one byte
    lw    $a3, 0x140($zero)
    # hazards: a load feeding LWL's merge value, back-to-back LWR/LWL on the same register
    lw    $v0, 0x100($zero)
    lwl   $v0, 0x103($zero)       # merge value comes straight from a load (stall)
    lwr   $v1, 0x101($zero)
    lwl   $v1, 0x104($zero)
    addu  $at, $v1, $v0
    halt
