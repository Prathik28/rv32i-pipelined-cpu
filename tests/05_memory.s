# Byte/half/word loads & stores, sign/zero extension, store forwarding patterns
    li   x1, 0x8899AABB
    sw   x1, 0x80(x0)
    lb   x2, 0x80(x0)     # 0xBB sign ext
    lbu  x3, 0x80(x0)
    lb   x4, 0x83(x0)     # 0x88 sign ext
    lbu  x5, 0x83(x0)
    lh   x6, 0x80(x0)     # 0xAABB sign ext
    lhu  x7, 0x80(x0)
    lh   x8, 0x82(x0)     # 0x8899
    lhu  x9, 0x82(x0)
    li   x10, 0x55
    sb   x10, 0x81(x0)
    sh   x10, 0x86(x0)
    lw   x11, 0x80(x0)
    lw   x12, 0x84(x0)
    sw   x11, 0x90(x0)    # back-to-back loads/stores
    lw   x13, 0x90(x0)
    sw   x13, 0x94(x0)
    lw   x14, 0x94(x0)
    halt
