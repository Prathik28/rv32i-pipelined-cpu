// SoC: core + instruction memory + data memory + tiny MMIO block.
//
//   0x0000_0000 .. 0x0000_0FFF   data RAM (4 KiB, aliased above)
//   0x1000_0000  HALT      (W)   write ends the program; value = exit code
//   0x1000_0004  PUTCHAR   (W)   prints a character in simulation
//   0x1000_0008  MTIMECMP  (RW)  timer compare (reset = 0xFFFFFFFF => no interrupt)
//   0x1000_000C  MTIME     (R)   free-running cycle counter
//   0x1000_0010  LEDS      (RW)  GPIO output (FPGA LEDs)
module riscv_soc #(parameter INIT_FILE = "", parameter BTB_ENTRIES = 16) (
    input         clk,
    input         rst,
    output        halt,
    output [31:0] exit_code,
    output [15:0] leds
);
    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata, ram_rdata;
    wire [3:0]  dmem_be;
    wire        dmem_we;

    wire is_mmio = (dmem_addr[31:28] == 4'h1);
    wire [3:0] reg_sel = dmem_addr[5:2];
    wire mmio_w = dmem_we & is_mmio & (dmem_addr[27:6] == 22'b0);

    reg [31:0] mtime, mtimecmp, mmio_rdata;
    reg [15:0] led_r;

    assign halt      = mmio_w & (reg_sel == 4'd0);
    assign exit_code = dmem_wdata;
    assign leds      = led_r;

    always @(posedge clk) begin
        if (rst) begin
            mtime <= 0; mtimecmp <= 32'hFFFF_FFFF; led_r <= 0;
        end else begin
            mtime <= mtime + 1;
            if (mmio_w && reg_sel == 4'd2) mtimecmp <= dmem_wdata;
            if (mmio_w && reg_sel == 4'd4) led_r    <= dmem_wdata[15:0];
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk)
        if (mmio_w && reg_sel == 4'd1) $write("%c", dmem_wdata[7:0]);
`endif

    always @* begin
        case (reg_sel)
            4'd2:    mmio_rdata = mtimecmp;
            4'd3:    mmio_rdata = mtime;
            4'd4:    mmio_rdata = {16'b0, led_r};
            default: mmio_rdata = 32'b0;
        endcase
    end

    wire irq_timer = (mtime >= mtimecmp);

    riscv_core #(.BTB_ENTRIES(BTB_ENTRIES)) u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_be(dmem_be),
        .dmem_we(dmem_we), .dmem_rdata(is_mmio ? mmio_rdata : ram_rdata),
        .irq_timer(irq_timer), .stop(halt),
        .perf_cycles(), .perf_instret(), .perf_stall_lu(), .perf_stall_div(),
        .perf_flushes(), .perf_branches(), .perf_mispred(), .perf_traps()
    );
    imem #(.INIT_FILE(INIT_FILE)) u_imem (.addr(imem_addr), .rdata(imem_rdata));
    dmem u_dmem (.clk(clk), .we(dmem_we & ~is_mmio), .be(dmem_be), .addr(dmem_addr),
                 .wdata(dmem_wdata), .rdata(ram_rdata));
endmodule
