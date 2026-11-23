# JAL / JALR / call-return, link register forwarding, AUIPC, LUI
    li   x10, 3
    jal  ra, func         # call
    addi x11, x11, 100    # executed after return
    jal  x0, end
    addi x11, x11, 1      # flushed
func:
    add  x11, x10, x10
    jalr x0, 0(ra)        # return (ra forwarded from JAL)
    addi x11, x11, 1      # flushed
end:
    auipc x12, 1
    lui  x13, 0xABCDE
    addi x13, x13, 0x123
    la_target: auipc x14, 0
    addi x14, x14, 16     # address of 'tgt'
    jalr x15, 0(x14)      # indirect jump (base forwarded), link in x15
    li   x16, 666         # flushed
tgt: li  x17, 77
    ecall
