# PERF mispred<=60
# Branch-predictor workout: nested counted loops, alternating pattern, JAL/JALR targets
    li   x1, 0               # accumulator
    li   x2, 0               # i
    li   x3, 20
outer:
    li   x4, 0               # j
    li   x5, 6
inner:
    add  x1, x1, x4
    addi x4, x4, 1
    blt  x4, x5, inner       # taken 5/6 -> well predicted
    andi x6, x2, 1
    beqz x6, even            # alternates every iteration
    addi x1, x1, 100
even:
    addi x2, x2, 1
    blt  x2, x3, outer
    # indirect jumps in a loop (same target every time)
    li   x7, 0
    li   x8, 10
    la   x9, tgt
again:
    jalr x10, 0(x9)
back:
    addi x7, x7, 1
    blt  x7, x8, again
    # one indirect-jump site whose target changes once (phase A x8, then phase B x8):
    # a BTB that cannot retrain its target mispredicts all of phase B
    li   x13, 0
    la   x20, tA
    la   x21, tB
    li   x16, 16
ind:
    slti x15, x13, 8
    mv   x9, x21
    beqz x15, go
    mv   x9, x20
go: jalr x10, 0(x9)
rind:
    addi x13, x13, 1
    blt  x13, x16, ind
    # branch taken once, then not taken 15 times: the 2-bit counter must decay
    li   x13, 0
rl: beqz x13, rare
    addi x1, x1, 5
rare:
    addi x13, x13, 1
    blt  x13, x16, rl
    halt
tA: addi x1, x1, 2
    jalr x0, 0(x10)
tB: addi x1, x1, 3
    jalr x0, 0(x10)
tgt:
    addi x1, x1, 1
    jalr x0, 0(x10)
