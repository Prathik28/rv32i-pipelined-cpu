# Self-checking: software / external / timer interrupts, vectored mtvec, priorities,
# 64-bit counters, time CSR.  Exit code 0 = pass, otherwise the failing step number.
    la   x1, vec
    ori  x1, x1, 1            # vectored mode
    csrw mtvec, x1
    li   x2, 0x10000000
    li   x20, 0               # interrupt order log (hex digits of causes)
    li   x21, 0               # exception counter (vectored mode: exceptions go to the base)
    sw   x0, 32(x2)           # mtimecmp high = 0
    # step 1: software interrupt (cause 3)
    li   x3, 8
    csrw mie, x3              # MSIE
    csrsi mstatus, 8
    li   x4, 1
    sw   x4, 24(x2)           # MSIP = 1
    nop
    nop
    nop
    nop
    li   x5, 3
    li   x30, 1
    bne  x20, x5, fail
    # step 2: external interrupt (cause 11)
    li   x3, 0x808
    csrw mie, x3
    li   x4, 1
    sw   x4, 28(x2)
    nop
    nop
    nop
    nop
    li   x5, 0x3B
    li   x30, 2
    bne  x20, x5, fail
    # step 3: both pending at once, interrupts globally disabled -> MEI (11) is taken before MSI (3)
    li   x20, 0
    csrci mstatus, 8
    li   x4, 1
    sw   x4, 24(x2)
    sw   x4, 28(x2)
    csrsi mstatus, 8
    nop
    nop
    nop
    nop
    nop
    nop
    li   x5, 0xB3
    li   x30, 3
    bne  x20, x5, fail
    # step 4: timer interrupt (cause 7), vectored
    li   x20, 0
    li   x3, 0x888
    csrw mie, x3
    lw   x6, 12(x2)
    addi x6, x6, 80
    sw   x6, 8(x2)
    li   x7, 0
wait7:
    addi x7, x7, 1
    li   x8, 7
    bne  x20, x8, wait7
    li   x30, 4
    li   x3, 1000
    blt  x7, x3, ok4
    j    fail
ok4:
    # step 5: ECALL in vectored mode still goes to the base entry (cause 11, not vectored)
    li   x30, 5
    ecall
    li   x5, 1
    bne  x21, x5, fail
    # step 6: 64-bit counters
    li   x30, 6
    csrw mcycleh, x0
    li   x3, 0xFFFFFFF0
    csrw mcycle, x3
    li   x4, 0
cnt:
    addi x4, x4, 1
    li   x5, 40
    blt  x4, x5, cnt
    csrr x6, mcycleh          # the low word wrapped: high word must now be 1
    li   x5, 1
    bne  x6, x5, fail
    csrr x6, timeh
    csrr x7, time
    beqz x7, fail
    csrr x7, minstret
    beqz x7, fail
    sw   x0, 0(x2)            # PASS
fail:
    sw   x30, 0(x2)           # exit code = failing step
vec:                          # vector table: entry i at vec + 4*i
    j    exc_handler          # 0  (all exceptions)
    j    bad
    j    bad
    j    msi                  # 3
    j    bad
    j    bad
    j    bad
    j    mti                  # 7
    j    bad
    j    bad
    j    bad
    j    mei                  # 11
bad:
    li   x30, 99
    li   x31, 0x10000000
    sw   x30, 0(x31)
msi:
    slli x20, x20, 4
    ori  x20, x20, 3
    li   x31, 0x10000000
    sw   x0, 24(x31)          # clear MSIP
    mret
mei:
    slli x20, x20, 4
    ori  x20, x20, 11
    li   x31, 0x10000000
    sw   x0, 28(x31)          # clear the external line
    mret
mti:
    slli x20, x20, 4
    ori  x20, x20, 7
    li   x31, 0x10000000
    li   x29, -1
    sw   x29, 8(x31)          # push mtimecmp away (low word all-ones, high word is 0)
    sw   x29, 32(x31)
    mret
exc_handler:
    addi x21, x21, 1
    csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
