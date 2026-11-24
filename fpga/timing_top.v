// Minimal top level used only for place-and-route timing runs (sw/ecp5_timing.sh).
// The core clock comes straight from a pin so the tool reports the core's own Fmax.
module timing_top (
    input         clk,
    input         rst,
    output        halt,
    output [15:0] led
);
    wire [31:0] exit_code;
    riscv_soc #(.INIT_FILE("fpga/blink.hex")) u_soc (
        .clk(clk), .rst(rst), .halt(halt), .exit_code(exit_code), .leds(led)
    );
endmodule
