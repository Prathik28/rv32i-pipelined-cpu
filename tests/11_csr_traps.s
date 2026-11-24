# Machine-mode CSRs, exceptions and MRET.  Handler records cause/tval and skips the instruction.
    la   x1, handler
    csrw mtvec, x1
    li   x20, 0              # trap counter
    li   x21, 0              # xor of causes
    li   x22, 0              # sum of tvals
    csrw mscratch, x20
    li   x2, 0xAB
    csrrw x3, mscratch, x2   # x3 = 0, mscratch = 0xAB
    csrrs x4, mscratch, x0   # read only
    csrrsi x5, mscratch, 0x14
    csrrci x6, mscratch, 0x3
    csrr x7, mscratch
    csrr x8, misa
    ecall                    # cause 11
    ebreak                   # cause 3
    .word 0xFFFFFFFF         # illegal, tval = instr
    .word 0x00000000         # illegal
    lw   x9, 1(x0)           # misaligned load  (cause 4, tval = 1)
    lh   x9, 3(x0)           # misaligned load
    sw   x2, 6(x0)           # misaligned store (cause 6)
    sh   x2, 5(x0)           # misaligned store
    csrw misa, x2            # WARL write ignored
    csrw mhartid, x2         # write to read-only CSR -> illegal
    csrr x10, 0x7C0          # unknown CSR -> illegal
    la   x11, target
    jalr x12, 2(x11)         # misaligned jump target (cause 0)
    li   x13, 1
    beq  x13, x13, target    # fine
target:
    csrr x14, mstatus
    csrsi mstatus, 8         # set MIE
    csrr x15, mstatus
    csrci mstatus, 8
    csrr x16, mepc
    halt
handler:
    addi x20, x20, 1
    csrr x28, mcause
    xor  x21, x21, x28
    add  x21, x21, x20
    csrr x28, mtval
    add  x22, x22, x28
    csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
