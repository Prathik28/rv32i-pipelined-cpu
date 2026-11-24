// SoC: MIPS core + instruction memory + 4 KiB data RAM (at 0) + a small MMIO block.
//   0x0000_0000..0x0000_0FFF  data RAM
//   0xFFFF_0000  HALT     (W)  write ends the program; value = exit code
//   0xFFFF_0004  PUTCHAR  (W)  prints a character in simulation
//   0xFFFF_0008  LEDS     (RW) 16-bit GPIO output (FPGA LEDs)
// Reset vector 0x0000_0000, exception vector 0x0000_0180.
module mips_soc #(parameter INIT_FILE = "") (
    input         clk,
    input         rst,
    output        halt,
    output [31:0] exit_code,
    output [15:0] leds
);
    wire [31:0] imem_addr, imem_rdata, d_addr, d_wdata, d_rdata, ram_rdata;
    wire [3:0]  d_be;
    wire        d_we;
    wire sel_ram  = (d_addr[31:12] == 20'h00000);
    wire sel_mmio = (d_addr[31:4]  == 28'hFFFF000);

    reg [31:0] exit_r;
    reg [15:0] led_r;
    assign halt = d_we & (d_addr == 32'hFFFF0000);
    always @(posedge clk) begin
        if (rst) begin exit_r <= 0; led_r <= 0; end
        else begin
            if (halt) exit_r <= d_wdata;
            if (d_we && d_addr == 32'hFFFF0008) led_r <= d_wdata[15:0];
        end
    end
    assign exit_code = exit_r;
    assign leds = led_r;

`ifndef SYNTHESIS
    always @(posedge clk) if (d_we && d_addr == 32'hFFFF0004) $write("%c", d_wdata[7:0]);
`endif

    assign d_rdata = sel_ram ? ram_rdata : (sel_mmio && d_addr[3:0] == 4'h8) ? {16'b0, led_r} : 32'b0;

    mips_core u_core (
        .clk(clk), .rst(rst), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_we(d_we), .dmem_addr(d_addr), .dmem_wdata(d_wdata), .dmem_be(d_be), .dmem_rdata(d_rdata),
        .stop(halt),
        .perf_cycles(), .perf_instret(), .perf_stall_lu(), .perf_stall_br(), .perf_stall_div(),
        .perf_taken(), .perf_traps()
    );
    mips_imem #(.INIT_FILE(INIT_FILE)) u_imem (.addr(imem_addr), .rdata(imem_rdata));
    mips_dmem u_ram (.clk(clk), .we(d_we & sel_ram), .be(d_be), .addr(d_addr), .wdata(d_wdata), .rdata(ram_rdata));
endmodule
