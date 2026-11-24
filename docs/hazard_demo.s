# Short program that triggers every hazard type once (used for the pipeline diagrams)
    li   x1, 5
    addi x2, x1, 1        # RAW: forward EX/MEM -> EX
    add  x3, x2, x1       # RAW: forward from both stages
    sw   x3, 0x40(x0)
    lw   x4, 0x40(x0)
    add  x5, x4, x1       # load-use: 1 stall, then forward from WB
    li   x6, 3
    div  x7, x5, x6       # structural: iterative divider stalls the front end
    addi x8, x7, 1        # uses div result
    li   x9, 0
loop:
    addi x9, x9, 1
    blt  x9, x6, loop     # taken twice, then falls through: BTB learns, then mispredicts exit
    addi x10, x9, 0
    halt
