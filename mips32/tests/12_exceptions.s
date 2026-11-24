# Precise exceptions: overflow, address error (load/store), SYSCALL, BREAK, reserved instruction,
# an exception inside a branch delay slot (EPC = the branch, Cause.BD = 1), CP0 and ERET.
    j     main
    nop
    .org  0x180
handler:                          # records the cause code, BD, EPC and BadVAddr, then skips the instruction
    mfc0  $k0, $13                # Cause
    mfc0  $k1, $14                # EPC
    addiu $s6, $s6, 1             # trap counter
    srl   $t8, $k0, 2
    andi  $t8, $t8, 0x1f          # ExcCode
    sll   $s7, $s7, 4
    addu  $s7, $s7, $t8           # hash of the cause codes
    srl   $t9, $k0, 31            # BD
    addu  $s5, $s5, $t9           # number of exceptions taken in a delay slot
    addu  $s4, $s4, $k1           # sum of the EPCs
    mfc0  $t8, $8                 # BadVAddr
    addu  $s3, $s3, $t8
    sll   $t9, $t9, 2
    addiu $k1, $k1, 4
    addu  $k1, $k1, $t9           # resume at EPC + 4 (+ 4 more if the exception was in a delay slot)
    mtc0  $k1, $14
    eret                          # no delay slot after ERET
    li    $s0, 0xBAD              # never executed
main:
    li    $t0, 0x7FFFFFFF
    li    $t1, 1
    add   $t2, $t0, $t1           # overflow (12); $t2 stays 0
    addi  $t3, $t0, 1             # overflow (12)
    li    $t5, 0x80000000
    sub   $t6, $t5, $t1           # overflow (12)
    addu  $t7, $t0, $t1           # no trap
    lw    $a0, 2($zero)           # AdEL (4), BadVAddr = 2
    sw    $t1, 6($zero)           # AdES (5), BadVAddr = 6
    lh    $a1, 1($zero)           # AdEL
    sh    $t1, 3($zero)           # AdES
    lw    $a2, 0x101($zero)       # AdEL
    syscall                       # 8
    break                         # 9
    .word 0xFFFFFFFF              # reserved instruction (10)
    .word 0x70000040              # reserved (SPECIAL2 with an unknown function)
    mfc0  $s1, $12                # Status: EXL must be 0 again after ERET
    # exception in a branch delay slot
    li    $v0, 1
    beq   $zero, $zero, after     # taken branch ...
    add   $t2, $t0, $t1           # ... whose delay slot overflows: EPC = the branch, BD = 1
    li    $v0, 2                  # resumed here (the branch is abandoned)
after:
    li    $v1, 3
    # exception in the delay slot of a NOT taken branch
    bne   $zero, $zero, skip
    lw    $a3, 1($zero)           # AdEL in a delay slot
    nop
skip:
    # EPC / BadVAddr / Cause stay readable after ERET
    mfc0  $s2, $14
    mfc0  $t4, $13
    mfc0  $t8, $8
    halt
