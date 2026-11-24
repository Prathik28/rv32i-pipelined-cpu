# RAW hazards: back-to-back, 1-apart, 2-apart, 3-apart (regfile write-through)
    addiu $t0, $zero, 5
    addiu $t1, $t0, 3         # EX/MEM -> EX forward
    addu  $t2, $t1, $t0       # both operands forwarded from different stages
    nop
    addu  $t3, $t2, $t1       # MEM/WB forward
    nop
    nop
    addu  $t4, $t3, $t3       # 3 apart: write-through in the register file
    subu  $t5, $t4, $t0
    xor   $t6, $t5, $t5       # same register twice
    addiu $t7, $t6, 1
    addiu $t7, $t7, 1         # dependent chain
    addiu $t7, $t7, 1
    addiu $t7, $t7, 1
    addu  $zero, $t7, $t7     # writes to $0 are ignored
    addu  $s0, $zero, $t7     # $0 reads as zero
    sll   $s1, $t7, 4         # shift of a just-computed value
    srl   $s2, $s1, 2
    halt
