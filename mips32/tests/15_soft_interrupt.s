# Software interrupts through Cause.IP0/IP1: masking (IE, EXL, IM), precise EPC, ERET, ordering
    j     main
    nop
    .org  0x180
handler:
    mfc0  $k0, $13                # Cause
    mfc0  $k1, $14                # EPC
    srl   $t8, $k0, 8
    andi  $t8, $t8, 3             # pending software bits
    sll   $s7, $s7, 4
    addu  $s7, $s7, $t8           # log of what was pending
    addu  $s6, $s6, $k1           # sum of the EPCs
    addiu $s5, $s5, 1             # interrupt count
    mtc0  $zero, $13              # clear both requests
    eret                          # return to the interrupted instruction
main:
    li    $s0, 0
    li    $t0, 0x301              # IM = IP0 + IP1, IE = 1
    mtc0  $t0, $12
    li    $t1, 0x100
    mtc0  $t1, $13                # request IP0: taken before the NEXT instruction
    addiu $s0, $s0, 1             # executes after the handler returns (EPC = this instruction)
    li    $t1, 0x200
    mtc0  $t1, $13                # IP1
    addiu $s0, $s0, 1
    # masked by IE = 0 alone (the IM bits stay set): stays pending
    li    $t0, 0x300
    mtc0  $t0, $12
    li    $t1, 0x100
    mtc0  $t1, $13
    addiu $s0, $s0, 1
    addiu $s0, $s0, 1             # still no interrupt
    mfc0  $s1, $13                # pending bit visible in Cause
    li    $t0, 0x301
    mtc0  $t0, $12                # unmask: the interrupt is taken right now
    addiu $s0, $s0, 1
    # masked by IM: only IP1 enabled, IP0 requested
    li    $t0, 0x201
    mtc0  $t0, $12
    li    $t1, 0x100
    mtc0  $t1, $13
    addiu $s0, $s0, 1             # IP0 masked: no interrupt
    mfc0  $s2, $13
    li    $t1, 0x300
    mtc0  $t1, $13                # now IP1 as well: only IP1 is enabled -> taken (Cause shows both)
    addiu $s0, $s0, 1
    # EXL set (as inside an exception handler) blocks interrupts
    li    $t0, 0x303              # IM = both, IE, EXL
    mtc0  $t0, $12
    li    $t1, 0x100
    mtc0  $t1, $13
    addiu $s0, $s0, 1             # no interrupt: EXL = 1
    mfc0  $s3, $12
    # interrupt in front of a branch and in front of a divide
    li    $t0, 0x301
    mtc0  $t0, $12
    mtc0  $zero, $13
    li    $t4, 100
    li    $t5, 7
    li    $t1, 0x100
    mtc0  $t1, $13
    div   $t4, $t5                # the interrupt is taken before the divide starts
    mflo  $s4
    li    $t1, 0x100
    mtc0  $t1, $13
    beq   $zero, $zero, end       # interrupt is taken before the branch (EPC = the branch)
    addiu $s0, $s0, 1000
    addiu $s0, $s0, 5000
end:
    mtc0  $zero, $12
    mfc0  $v0, $14
    halt
