`timescale 1ns/1ps
// Testbench: runs a program (+hex=file) until ECALL retires, then dumps
// registers, data memory and performance counters for the Python checker.
module tb_riscv;
    reg clk = 0, rst = 1;
    wire halt;
    wire [31:0] cyc, inst, stl, fls;
    integer i, maxc;

    riscv_soc dut (.clk(clk), .rst(rst), .halt(halt),
                   .perf_cycles(cyc), .perf_instret(inst),
                   .perf_stalls(stl), .perf_flushes(fls));

    always #5 clk = ~clk;

    initial begin
        if (!$value$plusargs("maxcycles=%d", maxc)) maxc = 100000;
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/wave.vcd");
            $dumpvars(0, tb_riscv);
        end
        repeat (3) @(posedge clk);
        #1 rst = 0;
    end

    always @(posedge clk) begin
        if (!rst && halt) begin
            #1;
            for (i = 0; i < 32; i = i + 1)
                $display("REG %0d %08x", i, dut.u_core.rf.regs[i]);
            for (i = 0; i < 1024; i = i + 1)
                if (dut.u_dmem.mem[i] != 0)
                    $display("MEM %0d %08x", i*4, dut.u_dmem.mem[i]);
            $display("PERF %0d %0d %0d %0d", cyc, inst, stl, fls);
            $display("DONE");
            $finish;
        end else if (!rst && cyc > maxc) begin
            $display("TIMEOUT");
            $finish;
        end
    end
endmodule
