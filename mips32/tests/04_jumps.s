# J / JAL / JR / JALR with delay slots, link = address of the instruction after the delay slot
    li    $s0, 0
    jal   func                # link = pc + 8
    addiu $s0, $s0, 1         # delay slot
    addiu $s0, $s0, 100       # executed after the return
    j     next
    addiu $s1, $zero, 7       # delay slot of J
    addiu $s0, $s0, 5000      # skipped
next:
    la    $t0, tgt
    jalr  $t0                 # jump through a register, link in $ra
    addiu $s2, $zero, 9
    addiu $s3, $s3, 1         # runs after the callee returns
    la    $t1, tgt2
    jalr  $s4, $t1            # link into a chosen register
    nop
    j     fin
    nop
func:
    addu  $s5, $ra, $zero
    jr    $ra
    addiu $s0, $s0, 10        # delay slot of JR: executes before the return
tgt:
    addiu $s6, $zero, 33
    jr    $ra
    nop
tgt2:
    addiu $s7, $zero, 44
    jr    $s4
    nop
fin:
    halt
