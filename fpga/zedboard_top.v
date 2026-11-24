// ZedBoard (Zynq-7000, xc7z020clg484-1) top level for the RISC-V core. NOT tested on hardware.
// Only the programmable fabric is used; the ARM cores are left unconfigured.
//   * 100 MHz board clock (pin Y9) divided by CLK_DIV (default 4 => 25 MHz) for the core
//   * BTNC = reset, LD0..LD7 = low byte of the LEDS register (0x1000_0010)
// In Vivado add blink.hex to the project as a memory file; PROGRAM is then found by its bare name.
module zedboard_top #(parameter CLK_DIV = 4, parameter PROGRAM = "blink.hex") (
    input        clk100,
    input        btn_reset,
    output [7:0] led
);
    localparam W = $clog2(CLK_DIV);
    reg [W-1:0] div_cnt = 0;
    always @(posedge clk100) div_cnt <= div_cnt + 1'b1;
    (* CLOCK_BUFFER_TYPE = "BUFG" *) wire clk = div_cnt[W-1];

    reg [2:0] rst_sync = 3'b111;
    always @(posedge clk) rst_sync <= {rst_sync[1:0], btn_reset};
    wire rst = rst_sync[2];

    wire halt; wire [31:0] exit_code; wire [15:0] leds;
    riscv_soc #(.INIT_FILE(PROGRAM)) u_soc (
        .clk(clk), .rst(rst), .ext_irq(1'b0), .halt(halt), .exit_code(exit_code), .leds(leds)
    );
    assign led = leds[7:0];
endmodule
