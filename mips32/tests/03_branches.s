# Branch delay slots: every branch type taken and not taken; the delay slot ALWAYS executes
    li    $t0, 10
    li    $t1, -10
    li    $s0, 0              # counts delay-slot executions
    li    $s7, 0              # counts wrongly-executed (skipped) instructions
    beq   $t0, $t0, b1
    addiu $s0, $s0, 1         # delay slot: executes although the branch is taken
    addiu $s7, $s7, 1         # skipped
b1: bne   $t0, $t0, bad
    addiu $s0, $s0, 1         # delay slot of a NOT-taken branch: executes
    bne   $t0, $t1, b2
    addiu $s0, $s0, 1
    addiu $s7, $s7, 1
b2: blez  $t1, b3             # -10 <= 0 taken
    addiu $s0, $s0, 1
    addiu $s7, $s7, 1
b3: blez  $t0, bad            # 10 <= 0 not taken
    addiu $s0, $s0, 1
    bgtz  $t0, b4             # 10 > 0 taken
    addiu $s0, $s0, 1
    addiu $s7, $s7, 1
b4: bgtz  $t1, bad            # not taken
    addiu $s0, $s0, 1
    bltz  $t1, b5             # taken
    addiu $s0, $s0, 1
    addiu $s7, $s7, 1
b5: bltz  $t0, bad            # not taken
    addiu $s0, $s0, 1
    bgez  $t0, b6             # taken
    addiu $s0, $s0, 1
    addiu $s7, $s7, 1
b6: bgez  $t1, bad            # not taken
    addiu $s0, $s0, 1
    bgez  $zero, b7           # 0 >= 0 taken
    nop
    addiu $s7, $s7, 1
b7: blez  $zero, b8           # 0 <= 0 taken
    nop
    addiu $s7, $s7, 1
b8: bgtz  $zero, bad          # not taken
    nop
    # BLTZAL / BGEZAL write $ra whether or not the branch is taken
    bltzal $t1, b9
    nop
    addiu $s7, $s7, 1
b9: move  $s1, $ra
    bgezal $t1, bad           # not taken: $ra still written
    nop
    move  $s2, $ra
    j     done
    nop
bad: li   $s7, 999
done: halt
