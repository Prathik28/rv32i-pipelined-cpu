# Console output through the PUTCHAR register and a non-zero exit code through SYSCALL
    li    $t0, 0xFFFF0004
    li    $t1, 72             # 'H'
    sb    $t1, 0($t0)
    li    $t1, 105            # 'i'
    sb    $t1, 0($t0)
    li    $t1, 10
    sb    $t1, 0($t0)
    li    $a0, 3
    syscall
