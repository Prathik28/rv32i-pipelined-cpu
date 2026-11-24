// SoC: MIPS core + instruction memory + 4 KiB data RAM (at 0) + a simulation console.
//   0x0000_0000..0x0000_0FFF  data RAM            0xFFFF_0004  PUTCHAR (W, simulation only)
// The program ends with SYSCALL; the value of $a0 is the exit code.
module mips_soc #(parameter INIT_FILE = "") (
    input         clk,
    input         rst,
    output        halt,
    output [31:0] exit_code,
    output [15:0] leds
);
    wire [31:0] imem_addr, imem_rdata, d_addr, d_wdata, d_rdata, ram_rdata, halt_code;
    wire [3:0]  d_be;
    wire        d_we;
    wire sel_ram = (d_addr[31:12] == 20'h00000);

    reg [31:0] exit_r;
    always @(posedge clk) if (rst) exit_r <= 0; else if (halt) exit_r <= halt_code;
    assign exit_code = exit_r;
    assign leds = 16'b0;

`ifndef SYNTHESIS
    always @(posedge clk) if (d_we && d_addr == 32'hFFFF0004) $write("%c", d_wdata[7:0]);
`endif

    assign d_rdata = sel_ram ? ram_rdata : 32'b0;

    mips_core u_core (
        .clk(clk), .rst(rst), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_we(d_we), .dmem_addr(d_addr), .dmem_wdata(d_wdata), .dmem_be(d_be), .dmem_rdata(d_rdata),
        .halt(halt), .halt_code(halt_code), .stop(halt),
        .perf_cycles(), .perf_instret(), .perf_stall_lu(), .perf_stall_br(), .perf_stall_div(), .perf_taken()
    );
    mips_imem #(.INIT_FILE(INIT_FILE)) u_imem (.addr(imem_addr), .rdata(imem_rdata));
    mips_dmem u_ram (.clk(clk), .we(d_we & sel_ram), .be(d_be), .addr(d_addr), .wdata(d_wdata), .rdata(ram_rdata));
endmodule
