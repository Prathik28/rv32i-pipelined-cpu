# mult/multu/div/divu/mul/mfhi/mflo/mthi/mtlo, divide by zero, INT_MIN/-1, hazards around the divider
    li    $t0, 0x12345678
    li    $t1, -7
    li    $t2, 0x80000000
    li    $t3, -1
    mult  $t0, $t1
    mfhi  $s0
    mflo  $s1                 # right after mult
    multu $t1, $t0
    mfhi  $s2
    mflo  $s3
    mult  $t2, $t2
    mfhi  $s4
    mflo  $s5
    mul   $s6, $t0, $t1       # 3-operand multiply
    div   $t0, $t1
    mflo  $s7                 # waits for the 32-cycle divider
    mfhi  $t4
    divu  $t1, $t0
    mflo  $t5
    mfhi  $t6
    div   $t2, $t3            # INT_MIN / -1
    mflo  $t7
    mfhi  $t8
    div   $t0, $zero          # divide by zero (implementation-defined: LO = -1, HI = dividend)
    mflo  $t9
    mfhi  $a0
    mthi  $t0
    mtlo  $t1
    mfhi  $a1
    mflo  $a2
    # divider followed by dependent instructions and a branch on the result
    li    $v0, 100
    li    $v1, 7
    div   $v0, $v1
    mflo  $a3                 # 14
    addu  $s0, $a3, $a3
    mult  $s0, $v1
    mflo  $s1
    div   $s1, $v1
    mflo  $s2
    beq   $s2, $s0, ok
    nop
    li    $s3, 111
ok: addiu $s3, $s3, 5
    li    $a0, 0
    halt
