# Branch-likely: the delay slot is annulled when the branch is NOT taken
    li    $s0, 0                  # delay slots that executed
    li    $s1, 0                  # annulled slots that wrongly executed (stays 0)
    li    $t0, 5
    li    $t1, -5
    beql  $t0, $t0, l1            # taken: slot executes
    addiu $s0, $s0, 1
    addiu $s1, $s1, 100
l1: beql  $t0, $t1, bad           # not taken: slot ANNULLED
    addiu $s1, $s1, 1
    bnel  $t0, $t1, l2            # taken
    addiu $s0, $s0, 1
    addiu $s1, $s1, 100
l2: bnel  $t0, $t0, bad           # not taken: annulled
    addiu $s1, $s1, 1
    blezl $t1, l3                 # taken
    addiu $s0, $s0, 1
    addiu $s1, $s1, 100
l3: blezl $t0, bad                # not taken: annulled
    addiu $s1, $s1, 1
    bgtzl $t0, l4                 # taken
    addiu $s0, $s0, 1
    addiu $s1, $s1, 100
l4: bgtzl $t1, bad                # not taken: annulled
    addiu $s1, $s1, 1
    bltzl $t1, l5                 # taken
    addiu $s0, $s0, 1
    addiu $s1, $s1, 100
l5: bltzl $t0, bad                # not taken: annulled
    addiu $s1, $s1, 1
    bgezl $t0, l6                 # taken
    addiu $s0, $s0, 1
    addiu $s1, $s1, 100
l6: bgezl $t1, bad                # not taken: annulled
    addiu $s1, $s1, 1
    # the annulled slot may hold anything, even an instruction that would trap or store
    li    $t2, 0x7FFFFFFF
    beql  $zero, $t0, bad
    add   $t3, $t2, $t2           # would overflow if executed
    beql  $zero, $t0, bad
    sw    $t0, 0x40($zero)        # would store if executed
    # likely-and-link writes $ra whether or not the branch is taken
    bltzall $t1, l7
    nop
    addiu $s1, $s1, 100
l7: move  $s2, $ra
    bgezall $t1, bad
    addiu $s1, $s1, 1             # annulled
    move  $s3, $ra
    # a likely branch directly after an instruction that produces its operand
    addiu $t4, $zero, 7
    beql  $t4, $zero, bad
    addiu $s1, $s1, 1
    lw    $t5, 0x40($zero)
    beql  $t5, $zero, l8          # operand from a load (2 stalls); value 0 -> taken
    addiu $s0, $s0, 1
    addiu $s1, $s1, 100
l8: j     fin
    nop
bad: li   $s1, 999
fin: halt
