# Every ALU / shift / logic operation with forwarded operands
    li    $t0, 0x80000001
    li    $t1, 5
    addu  $t2, $t0, $t1
    subu  $t3, $t0, $t1
    sllv  $t4, $t0, $t1
    srlv  $t5, $t0, $t1
    srav  $t6, $t0, $t1
    slt   $t7, $t0, $t1
    sltu  $s0, $t0, $t1
    xor   $s1, $t0, $t1
    or    $s2, $t0, $t1
    and   $s3, $t0, $t1
    nor   $s4, $t0, $t1
    sll   $s5, $t1, 31
    srl   $s6, $s5, 31
    sra   $s7, $s5, 31
    slti  $t8, $t0, -1
    sltiu $t9, $t0, -1
    andi  $a0, $t0, 0xFFFF
    ori   $a1, $t1, 0x7FF0
    xori  $a2, $t0, 0xFFFF
    lui   $a3, 0xABCD
    ori   $a3, $a3, 0x1234
    addiu $v0, $zero, -1
    subu  $v1, $zero, $t1
    halt
