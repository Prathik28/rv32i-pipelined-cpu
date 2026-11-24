# Byte / half / word loads and stores, sign and zero extension
    li    $t0, 0x8899AABB
    sw    $t0, 0x80($zero)
    lb    $t1, 0x80($zero)    # 0xBB sign-extended
    lbu   $t2, 0x80($zero)
    lb    $t3, 0x83($zero)    # 0x88 sign-extended
    lbu   $t4, 0x83($zero)
    lh    $t5, 0x80($zero)    # 0xAABB sign-extended
    lhu   $t6, 0x80($zero)
    lh    $t7, 0x82($zero)    # 0x8899
    lhu   $s0, 0x82($zero)
    li    $s1, 0x55
    sb    $s1, 0x81($zero)
    sh    $s1, 0x86($zero)
    lw    $s2, 0x80($zero)
    lw    $s3, 0x84($zero)
    sw    $s2, 0x90($zero)
    lw    $s4, 0x90($zero)
    sw    $s4, 0x94($zero)
    lw    $s5, 0x94($zero)
    halt
