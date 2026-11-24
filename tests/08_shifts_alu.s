# Every ALU op with forwarded operands
    li   x1, 0x80000001
    li   x2, 5
    add  x3, x1, x2
    sub  x4, x1, x2
    sll  x5, x1, x2
    srl  x6, x1, x2
    sra  x7, x1, x2
    slt  x8, x1, x2
    sltu x9, x1, x2
    xor  x10, x1, x2
    or   x11, x1, x2
    and  x12, x1, x2
    slli x13, x2, 31
    srli x14, x13, 31
    srai x15, x13, 31
    slti x16, x1, -1
    sltiu x17, x1, -1
    xori x18, x1, -1
    ori  x19, x2, 0x7F0
    andi x20, x1, 0x7FF
    halt
