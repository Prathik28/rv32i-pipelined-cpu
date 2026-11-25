# FPGA demo (MIPS): binary counter on the 16 LEDs (LEDS register at 0xFFFF0008) with the multiplier and
# the divider in the delay loop. Runs forever. LEDs staying on = the multiply/divide round trip failed.
    li    $s0, 0xFFFF0008      # LEDS register
    li    $s1, 0               # counter
    li    $s2, 250000          # delay (about 0.4 s per count at 25 MHz)
    li    $s4, 7
loop:
    sw    $s1, 0($s0)
    addiu $s1, $s1, 1
    li    $t0, 0
delay:
    addiu $t0, $t0, 1
    mul   $t1, $t0, $s4
    divu  $t1, $s4             # LO = t0
    mflo  $t2
    bne   $t2, $t0, fail
    nop
    bne   $t0, $s2, delay
    nop
    b     loop
    nop
fail:
    li    $t3, 0xFFFF
    sw    $t3, 0($s0)
    b     fail
    nop
