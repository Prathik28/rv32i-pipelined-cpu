# Self-checking: timer interrupt (Count/Compare -> IP7). Exit code 0 = pass.
    j     main
    nop
    .org  0x180
handler:
    mfc0  $k0, $13
    srl   $k0, $k0, 15
    andi  $k0, $k0, 1             # IP7 must be set
    beq   $k0, $zero, bad
    nop
    addiu $s0, $s0, 1             # interrupt count
    mfc0  $k1, $9                 # Count
    addiu $k1, $k1, 60
    mtc0  $k1, $11                # new Compare: clears IP7 and re-arms the timer
    eret
bad:
    li    $a0, 9
    exit
main:
    li    $s0, 0
    mfc0  $t0, $9
    addiu $t0, $t0, 60
    mtc0  $t0, $11                # Compare = Count + 60
    li    $t0, 0x8001             # IM7 + IE
    mtc0  $t0, $12
    li    $s1, 4
    li    $s2, 0
spin:
    addiu $s2, $s2, 1
    mult  $s2, $s2
    mflo  $t1
    div   $t1, $s2                # a divide in the loop: interrupts also arrive around it
    mflo  $t2
    bne   $s0, $s1, spin
    nop
    mtc0  $zero, $12              # interrupts off
    li    $a0, 1
    bne   $t2, $s2, done          # (t2 == s2 when the loop's arithmetic was not corrupted) else fail
    nop
    li    $a0, 0
    li    $t3, 3
    slt   $t4, $s2, $t3           # the loop must have made progress
    beq   $t4, $zero, done
    nop
    li    $a0, 2
done:
    exit
