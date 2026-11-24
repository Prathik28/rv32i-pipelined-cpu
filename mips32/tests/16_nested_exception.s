# An exception raised while handling another one (Status.EXL = 1): EPC and Cause.BD are NOT overwritten
    j     main
    nop
    .org  0x180
handler:
    bne   $s0, $zero, second
    nop
    # first entry: remember EPC / Cause / Status, then fault again inside the handler
    li    $s0, 1
    mfc0  $s1, $14                # original EPC (the branch, because the fault is in its delay slot)
    mfc0  $s5, $12                # Status: EXL = 1 here
    mfc0  $t8, $13                # original Cause
    break                         # nested exception: EXL already 1, so EPC and BD must stay
    li    $s6, 0xBAD              # skipped
second:
    li    $t9, 1
    bne   $s0, $t9, resume        # only record the state on the first nested entry
    nop
    mfc0  $s2, $14                # must still equal the ORIGINAL EPC
    mfc0  $s3, $13                # ExcCode = 9 (break) but BD still 1
    addiu $s0, $s0, 1
resume:
    mfc0  $k0, $13
    mfc0  $k1, $14
    srl   $k0, $k0, 31
    sll   $k0, $k0, 2
    addiu $k1, $k1, 4
    addu  $k1, $k1, $k0           # skip the faulting instruction (and the branch if BD)
    mtc0  $k1, $14
    eret
main:
    li    $t0, 0x7FFFFFFF
    li    $t1, 1
    beq   $zero, $zero, over      # the faulting instruction below sits in a branch delay slot
    add   $t2, $t0, $t1           # overflow in a delay slot: EPC = the branch, BD = 1
    li    $s7, 0xDEAD             # executes after the handler returns past the delay slot
over:
    mfc0  $s4, $12                # Status after the ERET: EXL = 0
    halt
