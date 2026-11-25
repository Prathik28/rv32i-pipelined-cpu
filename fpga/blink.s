# FPGA demo: a binary counter on the 16 LEDs (LEDS MMIO register), with the divider and
# multiplier in the loop so the whole datapath is exercised. Runs forever.
    li   x1, 0x10000000      # MMIO base
    li   x2, 0               # counter
    li   x4, 250000          # delay (~0.4 s per count at 25 MHz)
    li   x5, 7
loop:
    sw   x2, 16(x1)          # LEDS = counter
    addi x2, x2, 1
    li   x3, 0
delay:
    addi x3, x3, 1
    mul  x6, x3, x5
    div  x7, x6, x5          # == x3
    bne  x7, x3, fail        # sanity: divider/multiplier result must round-trip
    blt  x3, x4, delay
    j    loop
fail:
    li   x2, 0xFFFF
    sw   x2, 16(x1)          # LEDs stay on = error
    j    fail
