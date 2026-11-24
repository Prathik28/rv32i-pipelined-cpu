`timescale 1ns/1ps
// Runs +hex=prog.hex until SYSCALL reaches MEM, then dumps registers, HI/LO, RAM, exit code, counters.
// Options: +maxcycles=N  +vcd  +trace (per-cycle pipeline trace)
module tb_mips;
    reg clk = 0, rst = 1;
    wire halt; wire [31:0] exit_code; wire [15:0] leds;
    integer i, maxc; reg trace;

    mips_soc dut (.clk(clk), .rst(rst), .halt(halt), .exit_code(exit_code), .leds(leds));
    always #5 clk = ~clk;

    initial begin
        if (!$value$plusargs("maxcycles=%d", maxc)) maxc = 200000;
        trace = $test$plusargs("trace");
        if ($test$plusargs("vcd")) begin $dumpfile("build/wave.vcd"); $dumpvars(0, tb_mips); end
        repeat (3) @(posedge clk);
        #1 rst = 0;
    end

    // TRACE cyc pc_if pc_id pc_ex pc_mem pc_wb load_use ex_stall branch_stall taken fwd_a fwd_b trap
    reg [31:0] s_mem_pc = 32'hFFFFFFFF, s_wb_pc = 32'hFFFFFFFF;
    always @(posedge clk) begin
        s_wb_pc  <= s_mem_pc;
        s_mem_pc <= (dut.u_core.idex_valid && dut.u_core.ex_commit) ? dut.u_core.idex_pc : 32'hFFFFFFFF;
    end
    always @(posedge clk) if (!rst && trace)
        $display("TRACE %0d %08x %08x %08x %08x %08x %0d %0d %0d %0d %0d %0d %0d",
            dut.u_core.perf_cycles, dut.u_core.pc,
            dut.u_core.ifid_valid ? dut.u_core.ifid_pc : 32'hFFFFFFFF,
            dut.u_core.idex_valid ? dut.u_core.idex_pc : 32'hFFFFFFFF,
            s_mem_pc, s_wb_pc,
            dut.u_core.stall_lu && !dut.u_core.ex_stall,
            dut.u_core.ex_stall,
            dut.u_core.stall_br && !dut.u_core.stall_lu && !dut.u_core.ex_stall,
            dut.u_core.id_redirect, dut.u_core.fwd_a, dut.u_core.fwd_b, dut.u_core.trap_take);

    always @(posedge clk) begin
        if (!rst && halt) begin
            #1;
            $display("");
            $display("----");
            for (i = 0; i < 32; i = i + 1) $display("REG %0d %08x", i, dut.u_core.rf.regs[i]);
            $display("HI %08x", dut.u_core.hi);
            $display("CP0 %08x %08x %08x", dut.u_core.u_cp0.epc, dut.u_core.u_cp0.badvaddr, {dut.u_core.u_cp0.bd, 15'b0, 8'b0 | {dut.u_core.u_cp0.ip7,5'b0,dut.u_core.u_cp0.ip_soft}, 1'b0, dut.u_core.u_cp0.exccode, 2'b0});
            $display("LO %08x", dut.u_core.lo);
            for (i = 0; i < 1024; i = i + 1)
                if ({dut.u_ram.b3[i], dut.u_ram.b2[i], dut.u_ram.b1[i], dut.u_ram.b0[i]} != 0)
                    $display("MEM %0d %08x", i*4, {dut.u_ram.b3[i], dut.u_ram.b2[i], dut.u_ram.b1[i], dut.u_ram.b0[i]});
            $display("EXIT %0d", exit_code);
            $display("PERF %0d %0d %0d %0d %0d %0d %0d", dut.u_core.perf_cycles, dut.u_core.perf_instret,
                dut.u_core.perf_stall_lu, dut.u_core.perf_stall_br, dut.u_core.perf_stall_div, dut.u_core.perf_taken, dut.u_core.perf_traps);
            $display("DONE");
            $finish;
        end else if (!rst && dut.u_core.perf_cycles > maxc) begin
            $display("TIMEOUT pc=%08x", dut.u_core.pc);
            $finish;
        end
    end
endmodule
