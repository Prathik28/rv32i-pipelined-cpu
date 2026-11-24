// Example FPGA top level for a Digilent Basys 3 (Artix-7).  NOT tested on hardware.
//   * 100 MHz board clock divided by CLK_DIV (default 4 => 25 MHz) for the core
//   * btnC = reset, LD0..LD15 = LEDS MMIO register
module fpga_top #(parameter CLK_DIV = 4, parameter PROGRAM = "fpga/blink.hex") (
    input         clk100,
    input         btn_reset,
    output [15:0] led
);
    // divided clock
    localparam W = $clog2(CLK_DIV);
    reg [W-1:0] div_cnt = 0;
    always @(posedge clk100) div_cnt <= div_cnt + 1'b1;
    wire clk = div_cnt[W-1];

    // synchronise reset into the core clock domain
    reg [2:0] rst_sync = 3'b111;
    always @(posedge clk) rst_sync <= {rst_sync[1:0], btn_reset};
    wire rst = rst_sync[2];

    wire halt; wire [31:0] exit_code;
    riscv_soc #(.INIT_FILE(PROGRAM)) u_soc (
        .clk(clk), .rst(rst), .ext_irq(1'b0), .halt(halt), .exit_code(exit_code), .leds(led)
    );
endmodule
